# Nimbus
# Copyright (c) 2021-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed except
# according to those terms.

import
  std/sequtils,
  eth/common

# ------------------------------------------------------------------------------
# Public helpers
# ------------------------------------------------------------------------------

proc startAt*(
    h: openArray[EthBlock];
    start: uint64;
      ): seq[EthBlock] =
  ## Filter out blocks with smaller `blockNumber`
  if start.toBlockNumber <= h[0].header.blockNumber:
    return h.toSeq()
  if start.toBlockNumber <= h[^1].header.blockNumber:
    # There are at least two headers, find the least acceptable one
    var n = 1
    while h[n].header.blockNumber < start.toBlockNumber:
      n.inc
    return h[n ..< h.len]

proc stopAfter*(
    h: openArray[EthBlock];
    last: uint64;
      ): seq[EthBlock] =
  ## Filter out blocks with larger `blockNumber`
  if h[^1].header.blockNumber <= last.toBlockNumber:
    return h.toSeq()
  if h[0].header.blockNumber <= last.toBlockNumber:
    # There are at least two headers, find the last acceptable one
    var n = 1
    while h[n].header.blockNumber <= last.toBlockNumber:
      n.inc
    return h[0 ..< n]

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
