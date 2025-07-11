# Nimbus
# Copyright (c) 2023-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables],
  eth/common/[hashes, headers],
  chronicles,
  minilru,
  web3/execution_types,
  ./web3_eth_conv,
  ./payload_conv,
  ./api_handler/api_utils,
  ../core/tx_pool,
  ../core/pooled_txs,
  ../core/chain/forked_chain,
  ../core/chain/forked_chain/block_quarantine

export
  forked_chain,
  block_quarantine,
  pooled_txs

type
  ExecutionBundle* = object
    payload*: ExecutionPayload
    blockValue*: UInt256
    blobsBundle*: BlobsBundle
    executionRequests*: Opt[seq[seq[byte]]]

  BeaconEngineRef* = ref object
    txPool: TxPoolRef
    queue : LruCache[Bytes8, ExecutionBundle]

    # The forkchoice update and new payload method require us to return the
    # latest valid hash in an invalid chain. To support that return, we need
    # to track historical bad blocks as well as bad tipsets in case a chain
    # is constantly built on it.
    #
    # There are a few important caveats in this mechanism:
    #   - The bad block tracking is ephemeral, in-memory only. We must never
    #     persist any bad block information to disk as a bug in Geth could end
    #     up blocking a valid chain, even if a later Geth update would accept
    #     it.
    #   - Bad blocks will get forgotten after a certain threshold of import
    #     attempts and will be retried. The rationale is that if the network
    #     really-really-really tries to feed us a block, we should give it a
    #     new chance, perhaps us being racey instead of the block being legit
    #     bad (this happened in Geth at a point with import vs. pending race).
    #   - Tracking all the blocks built on top of the bad one could be a bit
    #     problematic, so we will only track the head chain segment of a bad
    #     chain to allow discarding progressing bad chains and side chains,
    #     without tracking too much bad data.

    # Ephemeral cache to track invalid blocks and their hit count
    invalidBlocksHits: Table[Hash32, int]
    # Ephemeral cache to track invalid tipsets and their bad ancestor
    invalidTipsets   : Table[Hash32, Header]

{.push gcsafe, raises:[].}

const
  # invalidBlockHitEviction is the number of times an invalid block can be
  # referenced in forkchoice update or new payload before it is attempted
  # to be reprocessed again.
  invalidBlockHitEviction = 128

  # invalidTipsetsCap is the max number of recent block hashes tracked that
  # have lead to some bad ancestor block. It's just an OOM protection.
  invalidTipsetsCap = 512

  # maxTrackedPayloads is the maximum number of prepared payloads the execution
  # engine tracks before evicting old ones. Ideally we should only ever track
  # the latest one; but have a slight wiggle room for non-ideal conditions.
  MaxTrackedPayloads = 10

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

func setWithdrawals(xp: TxPoolRef, attrs: PayloadAttributes) =
  case attrs.version
  of Version.V2, Version.V3:
    xp.withdrawals = ethWithdrawals attrs.withdrawals.get
  else:
    xp.withdrawals = @[]

template wrapException(body: untyped): auto =
  try:
    body
  except CatchableError as ex:
    err(ex.msg)

# setInvalidAncestor is a callback for the downloader to notify us if a bad block
# is encountered during the async sync.
func setInvalidAncestor(ben: BeaconEngineRef,
                         invalid, origin: Header) =
  ben.invalidTipsets[origin.computeBlockHash] = invalid
  inc ben.invalidBlocksHits.mgetOrPut(invalid.computeBlockHash, 0)

# ------------------------------------------------------------------------------
# Constructors
# ------------------------------------------------------------------------------

func new*(_: type BeaconEngineRef,
          txPool: TxPoolRef): BeaconEngineRef =
  let ben = BeaconEngineRef(
    txPool: txPool,
    queue : LruCache[Bytes8, ExecutionBundle].init(MaxTrackedPayloads),
  )

  txPool.com.notifyBadBlock = proc(invalid, origin: Header)
    {.gcsafe, raises: [].} =
    ben.setInvalidAncestor(invalid, origin)

  ben

# ------------------------------------------------------------------------------
# Public functions, setters
# ------------------------------------------------------------------------------

func putPayloadBundle*(ben: BeaconEngineRef, id: Bytes8,
          payload: ExecutionBundle) =
  ben.queue.put(id, payload)

# ------------------------------------------------------------------------------
# Public functions, getters
# ------------------------------------------------------------------------------
func com*(ben: BeaconEngineRef): CommonRef =
  ben.txPool.com

func chain*(ben: BeaconEngineRef): ForkedChainRef =
  ben.txPool.chain

func txPool*(ben: BeaconEngineRef): TxPoolRef =
  ben.txPool

func getPayloadBundle*(ben: BeaconEngineRef, id: Bytes8): Opt[ExecutionBundle] =
  ben.queue.get(id)

# ------------------------------------------------------------------------------
# Public functions
# ------------------------------------------------------------------------------
proc generateExecutionBundle*(ben: BeaconEngineRef,
                      attrs: PayloadAttributes):
                         Result[ExecutionBundle, string] =
  wrapException:
    let
      xp  = ben.txPool
      headBlock = ben.chain.latestHeader

    xp.prevRandao   = attrs.prevRandao
    xp.timestamp    = ethTime attrs.timestamp
    xp.feeRecipient = attrs.suggestedFeeRecipient

    if attrs.parentBeaconBlockRoot.isSome:
      xp.parentBeaconBlockRoot = attrs.parentBeaconBlockRoot.get

    xp.setWithdrawals(attrs)

    if xp.timestamp <= headBlock.timestamp:
      return err "timestamp must be strictly later than parent"

    # someBaseFee = true: make sure bundle.blk.header
    # have the same blockHash with generated payload
    let bundle = xp.assembleBlock(someBaseFee = true).valueOr:
      return err(error)

    if bundle.blk.header.extraData.len > 32:
      return err "extraData length should not exceed 32 bytes"

    ok ExecutionBundle(
      payload: executionPayload(bundle.blk),
      blobsBundle: bundle.blobsBundle,
      blockValue: bundle.blockValue,
      executionRequests: bundle.executionRequests)

func setInvalidAncestor*(ben: BeaconEngineRef, header: Header, blockHash: Hash32) =
  ben.invalidBlocksHits[blockHash] = 1
  ben.invalidTipsets[blockHash] = header

# checkInvalidAncestor checks whether the specified chain end links to a known
# bad ancestor. If yes, it constructs the payload failure response to return.
proc checkInvalidAncestor*(ben: BeaconEngineRef,
                           check, head: Hash32): Opt[PayloadStatusV1] =
  proc latestValidHash(chain: ForkedChainRef, invalid: auto): Hash32 =
    let parent = chain.headerByHash(invalid.parentHash).valueOr:
      return invalid.parentHash
    if parent.difficulty != 0.u256:
      return default(Hash32)
    invalid.parentHash

  # If the hash to check is unknown, return valid
  ben.invalidTipsets.withValue(check, invalid) do:
    # If the bad hash was hit too many times, evict it and try to reprocess in
    # the hopes that we have a data race that we can exit out of.
    let badHash = invalid[].computeBlockHash

    inc ben.invalidBlocksHits.mgetOrPut(badHash, 0)
    if ben.invalidBlocksHits.getOrDefault(badHash) >= invalidBlockHitEviction:
      warn "Too many bad block import attempt, trying",
        number=invalid.number, hash=badHash.short

      ben.invalidBlocksHits.del(badHash)

      var deleted = newSeq[Hash32]()
      for descendant, badHeader in ben.invalidTipsets:
        if badHeader.computeBlockHash == badHash:
          deleted.add descendant

      for x in deleted:
        ben.invalidTipsets.del(x)

      return Opt.none(PayloadStatusV1)

    # Not too many failures yet, mark the head of the invalid chain as invalid
    if check != head:
      warn "Marked new chain head as invalid",
        hash=head, badnumber=invalid.number, badhash=badHash

      if ben.invalidTipsets.len >= invalidTipsetsCap:
        let size = invalidTipsetsCap - ben.invalidTipsets.len
        var deleted = newSeqOfCap[Hash32](size)
        for key in ben.invalidTipsets.keys:
          deleted.add key
          if deleted.len >= size:
            break
        for x in deleted:
          ben.invalidTipsets.del(x)

      ben.invalidTipsets[head] = invalid[]

    # If the last valid hash is the terminal pow block, return 0x0 for latest valid hash
    let lastValid = latestValidHash(ben.chain, invalid)
    return Opt.some invalidStatus(lastValid, "links to previously rejected block")
  do:
    return Opt.none(PayloadStatusV1)

# delayPayloadImport stashes the given block away for import at a later time,
# either via a forkchoice update or a sync extension. This method is meant to
# be called by the newpayload command when the block seems to be ok, but some
# prerequisite prevents it from being processed (e.g. no parent, or snap sync).
proc delayPayloadImport*(ben: BeaconEngineRef, blockHash: Hash32, blk: Block): PayloadStatusV1 =
  # Sanity check that this block's parent is not on a previously invalidated
  # chain. If it is, mark the block as invalid too.
  ben.checkInvalidAncestor(blk.header.parentHash, blockHash).valueOr:
    # Stash the block away for a potential forced forkchoice update to it
    # at a later time.
    ben.chain.quarantine.addOrphan(blockHash, blk)
    return PayloadStatusV1(status: PayloadExecutionStatus.syncing)

func latestFork*(ben: BeaconEngineRef): HardFork =
  let timestamp = max(ben.txPool.timestamp, ben.chain.latestHeader.timestamp)
  ben.com.toHardFork(timestamp)
