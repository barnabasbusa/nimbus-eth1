# Nimbus
# Copyright (c) 2024-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or
# distributed except according to those terms.

{.used.}

import unittest2, std/sequtils, ../../execution_chain/db/aristo/aristo_blobify

suite "Aristo blobify":
  test "VertexRef roundtrip":
    let
      leafAccount = AccLeafRef.init(
        NibblesBuf.nibble(1),
        AristoAccount(nonce: 100, balance: 123.u256),
        (isValid: true, vid: VertexID(5)),
      )
      leafStoData = StoLeafRef.init(NibblesBuf.nibble(3), 42.u256)
      branch = BranchRef.init(VertexID(0x334452), 0x43'u16)
      extension = ExtBranchRef.init(NibblesBuf.nibble(2), VertexID(0x55), 0x12'u16)

      key = HashKey.fromBytes(repeat(0x34'u8, 32))[]

    check:
      deblobify(blobify(leafAccount, key), VertexRef)[] == leafAccount
      deblobify(blobify(leafStoData, key), VertexRef)[] == leafStoData
      deblobify(blobify(branch, key), VertexRef)[] == branch
      deblobify(blobify(extension, key), VertexRef)[] == extension

      deblobify(blobify(branch, key), HashKey)[] == key
      deblobify(blobify(extension, key), HashKey)[] == key

      deblobifyType(blobify(leafAccount, key), VertexRef)[] == AccLeaf
      deblobifyType(blobify(leafStoData, key), VertexRef)[] == StoLeaf
      deblobifyType(blobify(branch, key), VertexRef)[] == Branch
      deblobifyType(blobify(extension, key), VertexRef)[] == ExtBranch
