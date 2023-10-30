# Nimbus
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed
# except according to those terms.

## Unify different ledger management APIs.

{.push raises: [].}

import
  eth/common,
  chronicles,
  ../../../stateless/multi_keys,
  ../core_db,
  ./base/[base_desc, validate]

type
  ReadOnlyStateDB* = distinct LedgerRef

export
  LedgerType,
  LedgerRef,
  LedgerSpRef

when defined(release):
  const AutoValidateDescriptors = false
else:
  const AutoValidateDescriptors = true

const
  EnableApiTracking = true and false
    ## When enabled, API functions are logged. Tracking is enabled by setting
    ## the `trackApi` flag to `true`.

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

when EnableApiTracking:
  import std/strutils, stew/byteutils

  template apiTxt(info: static[string]): static[string] =
    "Ledger API " & info

  template ifTrackApi(ldg: LedgerRef; code: untyped) =
    when EnableApiTracking:
      if ldg.trackApi:
        code

  proc oaToStr(w: openArray[byte]): string =
    w.toHex.toLowerAscii

  proc toStr(w: EthAddress): string =
    w.oaToStr

  proc toStr(w: Hash256): string =
    w.data.oaToStr

  proc toStr(w: Blob): string =
    if 0 < w.len and w.len < 5: "<" & w.oaToStr & ">"
    else: "Blob[" & $w.len & "]"

  proc toStr(w: seq[Log]): string =
    "Logs[" & $w.len & "]"

else:
  template ifTrackApi(ldg: LedgerRef; code: untyped) = discard

# ------------------------------------------------------------------------------
# Public constructor helper
# ------------------------------------------------------------------------------

proc bless*(ldg: LedgerRef; db: CoreDbRef): LedgerRef =
  when AutoValidateDescriptors:
    ldg.validate()
  when EnableApiTracking:
    ldg.trackApi = db.trackLedgerApi
    if ldg.trackApi:
      info apiTxt "LedgerRef.init()", ldgType=ldg.ldgType
  ldg

# ------------------------------------------------------------------------------
# Public methods
# ------------------------------------------------------------------------------

proc accessList*(ldg: LedgerRef, eAddr: EthAddress) =
  ldg.methods.accessListFn(eAddr)
  ldg.ifTrackApi: info apiTxt "accessList()", eAddr=eAddr.toStr

proc accessList*(ldg: LedgerRef, eAddr: EthAddress, slot: UInt256) =
  ldg.methods.accessList2Fn(eAddr, slot)
  ldg.ifTrackApi: info apiTxt "accessList()", eAddr=eAddr.toStr, slot

proc accountExists*(ldg: LedgerRef, eAddr: EthAddress): bool =
  result = ldg.methods.accountExistsFn(eAddr)
  ldg.ifTrackApi: info apiTxt "accountExists()", eAddr=eAddr.toStr, result

proc addBalance*(ldg: LedgerRef, eAddr: EthAddress, delta: UInt256) =
  ldg.methods.addBalanceFn(eAddr, delta)
  ldg.ifTrackApi: info apiTxt "addBalance()", eAddr=eAddr.toStr, delta

proc addLogEntry*(ldg: LedgerRef, log: Log) =
  ldg.methods.addLogEntryFn(log)
  ldg.ifTrackApi: info apiTxt "addLogEntry()"

proc beginSavepoint*(ldg: LedgerRef): LedgerSpRef =
  result = ldg.methods.beginSavepointFn()
  ldg.ifTrackApi: info apiTxt "beginSavepoint()"

proc clearStorage*(ldg: LedgerRef, eAddr: EthAddress) =
  ldg.methods.clearStorageFn(eAddr)
  ldg.ifTrackApi: info apiTxt "clearStorage()", eAddr=eAddr.toStr

proc clearTransientStorage*(ldg: LedgerRef) =
  ldg.methods.clearTransientStorageFn()
  ldg.ifTrackApi: info apiTxt "clearTransientStorage()"

proc collectWitnessData*(ldg: LedgerRef) =
  ldg.methods.collectWitnessDataFn()
  ldg.ifTrackApi: info apiTxt "collectWitnessData()"

proc commit*(ldg: LedgerRef, sp: LedgerSpRef) =
  ldg.methods.commitFn(sp)
  ldg.ifTrackApi: info apiTxt "commit()"

proc deleteAccount*(ldg: LedgerRef, eAddr: EthAddress) =
  ldg.methods.deleteAccountFn(eAddr)
  ldg.ifTrackApi: info apiTxt "deleteAccount()", eAddr=eAddr.toStr

proc dispose*(ldg: LedgerRef, sp: LedgerSpRef) =
  ldg.methods.disposeFn(sp)
  ldg.ifTrackApi: info apiTxt "dispose()"

proc getAndClearLogEntries*(ldg: LedgerRef): seq[Log] =
  result = ldg.methods.getAndClearLogEntriesFn()
  ldg.ifTrackApi: info apiTxt "getAndClearLogEntries()"

proc getBalance*(ldg: LedgerRef, eAddr: EthAddress): UInt256 =
  result = ldg.methods.getBalanceFn(eAddr)
  ldg.ifTrackApi: info apiTxt "getBalance()", eAddr=eAddr.toStr, result

proc getCode*(ldg: LedgerRef, eAddr: EthAddress): Blob =
  result = ldg.methods.getCodeFn(eAddr)
  ldg.ifTrackApi:
    info apiTxt "getCode()", eAddr=eAddr.toStr, result=result.toStr

proc getCodeHash*(ldg: LedgerRef, eAddr: EthAddress): Hash256  =
  result = ldg.methods.getCodeHashFn(eAddr)
  ldg.ifTrackApi:
    info apiTxt "getCodeHash()", eAddr=eAddr.toStr, result=result.toStr

proc getCodeSize*(ldg: LedgerRef, eAddr: EthAddress): int =
  result = ldg.methods.getCodeSizeFn(eAddr)
  ldg.ifTrackApi: info apiTxt "getCodeSize()", eAddr=eAddr.toStr, result

proc getCommittedStorage*(ldg: LedgerRef, eAddr: EthAddress, slot: UInt256): UInt256 =
  result = ldg.methods.getCommittedStorageFn(eAddr, slot)
  ldg.ifTrackApi:
    info apiTxt "getCommittedStorage()", eAddr=eAddr.toStr, slot, result

proc getNonce*(ldg: LedgerRef, eAddr: EthAddress): AccountNonce =
  result = ldg.methods.getNonceFn(eAddr)
  ldg.ifTrackApi: info apiTxt "getNonce()", eAddr=eAddr.toStr, result

proc getStorage*(ldg: LedgerRef, eAddr: EthAddress, slot: UInt256): UInt256 =
  result = ldg.methods.getStorageFn(eAddr, slot)
  ldg.ifTrackApi: info apiTxt "getStorage()", eAddr=eAddr.toStr, slot, result

proc getStorageRoot*(ldg: LedgerRef, eAddr: EthAddress): Hash256 =
  result = ldg.methods.getStorageRootFn(eAddr)
  ldg.ifTrackApi:
    info apiTxt "getStorageRoot()", eAddr=eAddr.toStr, result=result.toStr

proc getTransientStorage*(ldg: LedgerRef, eAddr: EthAddress, slot: UInt256): UInt256 =
  result = ldg.methods.getTransientStorageFn(eAddr, slot)
  ldg.ifTrackApi:
    info apiTxt "getTransientStorage()", eAddr=eAddr.toStr, slot, result

proc hasCodeOrNonce*(ldg: LedgerRef, eAddr: EthAddress): bool =
  result = ldg.methods.hasCodeOrNonceFn(eAddr)
  ldg.ifTrackApi: info apiTxt "hasCodeOrNonce()", eAddr=eAddr.toStr, result

proc inAccessList*(ldg: LedgerRef, eAddr: EthAddress): bool =
  result = ldg.methods.inAccessListFn(eAddr)
  ldg.ifTrackApi: info apiTxt "inAccessList()", eAddr=eAddr.toStr, result

proc inAccessList*(ldg: LedgerRef, eAddr: EthAddress, slot: UInt256): bool =
  result = ldg.methods.inAccessList2Fn(eAddr, slot)
  ldg.ifTrackApi: info apiTxt "inAccessList()", eAddr=eAddr.toStr, slot, result

proc incNonce*(ldg: LedgerRef, eAddr: EthAddress) =
  ldg.methods.incNonceFn(eAddr)
  ldg.ifTrackApi: info apiTxt "incNonce()", eAddr=eAddr.toStr

proc isDeadAccount*(ldg: LedgerRef, eAddr: EthAddress): bool =
  result = ldg.methods.isDeadAccountFn(eAddr)
  ldg.ifTrackApi: info apiTxt "isDeadAccount()", eAddr=eAddr.toStr, result

proc isEmptyAccount*(ldg: LedgerRef, eAddr: EthAddress): bool =
  result = ldg.methods.isEmptyAccountFn(eAddr)
  ldg.ifTrackApi: info apiTxt "isEmptyAccount()", eAddr=eAddr.toStr, result

proc isTopLevelClean*(ldg: LedgerRef): bool =
  result = ldg.methods.isTopLevelCleanFn()
  ldg.ifTrackApi: info apiTxt "isTopLevelClean()", result

proc logEntries*(ldg: LedgerRef): seq[Log] =
  result = ldg.methods.logEntriesFn()
  ldg.ifTrackApi: info apiTxt "logEntries()", result=result.toStr

proc makeMultiKeys*(ldg: LedgerRef): MultikeysRef =
  result = ldg.methods.makeMultiKeysFn()
  ldg.ifTrackApi: info apiTxt "makeMultiKeys()"

proc persist*(ldg: LedgerRef, clearEmptyAccount = false, clearCache = true) =
  ldg.methods.persistFn(clearEmptyAccount, clearCache)
  ldg.ifTrackApi: info apiTxt "persist()", clearEmptyAccount, clearCache

proc ripemdSpecial*(ldg: LedgerRef) =
  ldg.methods.ripemdSpecialFn()
  ldg.ifTrackApi: info apiTxt "ripemdSpecial()"

proc rollback*(ldg: LedgerRef, sp: LedgerSpRef) =
  ldg.methods.rollbackFn(sp)
  ldg.ifTrackApi: info apiTxt "rollback()"

proc rootHash*(ldg: LedgerRef): Hash256 =
  result = ldg.methods.rootHashFn()
  ldg.ifTrackApi: info apiTxt "rootHash()", result=result.toStr

proc safeDispose*(ldg: LedgerRef, sp: LedgerSpRef) =
  ldg.methods.safeDisposeFn(sp)
  ldg.ifTrackApi: info apiTxt "safeDispose()"

proc selfDestruct*(ldg: LedgerRef, eAddr: EthAddress) =
  ldg.methods.selfDestructFn(eAddr)
  ldg.ifTrackApi: info apiTxt "selfDestruct()"

proc selfDestruct6780*(ldg: LedgerRef, eAddr: EthAddress) =
  ldg.methods.selfDestruct6780Fn(eAddr)
  ldg.ifTrackApi: info apiTxt "selfDestruct6780()"

proc selfDestructLen*(ldg: LedgerRef): int =
  result = ldg.methods.selfDestructLenFn()
  ldg.ifTrackApi: info apiTxt "selfDestructLen()", result

proc setBalance*(ldg: LedgerRef, eAddr: EthAddress, balance: UInt256) =
  ldg.methods.setBalanceFn(eAddr, balance)
  ldg.ifTrackApi: info apiTxt "setBalance()", eAddr=eAddr.toStr, balance

proc setCode*(ldg: LedgerRef, eAddr: EthAddress, code: Blob) =
  ldg.methods.setCodeFn(eAddr, code)
  ldg.ifTrackApi: info apiTxt "setCode()", eAddr=eAddr.toStr, code=code.toStr

proc setNonce*(ldg: LedgerRef, eAddr: EthAddress, nonce: AccountNonce) =
  ldg.methods.setNonceFn(eAddr, nonce)
  ldg.ifTrackApi: info apiTxt "setNonce()", eAddr=eAddr.toStr, nonce

proc setStorage*(ldg: LedgerRef, eAddr: EthAddress, slot, val: UInt256) =
  ldg.methods.setStorageFn(eAddr, slot, val)
  ldg.ifTrackApi: info apiTxt "setStorage()", eAddr=eAddr.toStr, slot, val

proc setTransientStorage*(ldg: LedgerRef, eAddr: EthAddress, slot, val: UInt256) =
  ldg.methods.setTransientStorageFn(eAddr, slot, val)
  ldg.ifTrackApi:
    info apiTxt "setTransientStorage()", eAddr=eAddr.toStr, slot, val

proc subBalance*(ldg: LedgerRef, eAddr: EthAddress, delta: UInt256) =
  ldg.methods.subBalanceFn(eAddr, delta)
  ldg.ifTrackApi: info apiTxt "setTransientStorage()", eAddr=eAddr.toStr, delta

# ------------------------------------------------------------------------------
# Public methods, extensions to go away
# ------------------------------------------------------------------------------

proc rawRootHash*(ldg: LedgerRef): Hash256 =
  result = ldg.extras.rawRootHashFn()
  ldg.ifTrackApi: info apiTxt "rawRootHash()", result=result.toStr

# ------------------------------------------------------------------------------
# Public virtual read-only methods
# ------------------------------------------------------------------------------

proc rootHash*(db: ReadOnlyStateDB): KeccakHash {.borrow.}
proc getCodeHash*(db: ReadOnlyStateDB, eAddr: EthAddress): Hash256 {.borrow.}
proc getStorageRoot*(db: ReadOnlyStateDB, eAddr: EthAddress): Hash256 {.borrow.}
proc getBalance*(db: ReadOnlyStateDB, eAddr: EthAddress): UInt256 {.borrow.}
proc getStorage*(db: ReadOnlyStateDB, eAddr: EthAddress, slot: UInt256): UInt256 {.borrow.}
proc getNonce*(db: ReadOnlyStateDB, eAddr: EthAddress): AccountNonce {.borrow.}
proc getCode*(db: ReadOnlyStateDB, eAddr: EthAddress): seq[byte] {.borrow.}
proc getCodeSize*(db: ReadOnlyStateDB, eAddr: EthAddress): int {.borrow.}
proc hasCodeOrNonce*(db: ReadOnlyStateDB, eAddr: EthAddress): bool {.borrow.}
proc accountExists*(db: ReadOnlyStateDB, eAddr: EthAddress): bool {.borrow.}
proc isDeadAccount*(db: ReadOnlyStateDB, eAddr: EthAddress): bool {.borrow.}
proc isEmptyAccount*(db: ReadOnlyStateDB, eAddr: EthAddress): bool {.borrow.}
proc getCommittedStorage*(db: ReadOnlyStateDB, eAddr: EthAddress, slot: UInt256): UInt256 {.borrow.}
func inAccessList*(db: ReadOnlyStateDB, eAddr: EthAddress): bool {.borrow.}
func inAccessList*(db: ReadOnlyStateDB, eAddr: EthAddress, slot: UInt256): bool {.borrow.}
func getTransientStorage*(db: ReadOnlyStateDB, eAddr: EthAddress, slot: UInt256): UInt256 {.borrow.}

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------