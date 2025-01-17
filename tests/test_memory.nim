# Nimbus
# Copyright (c) 2018-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/sequtils,
  unittest2,
  ../nimbus/evm/evm_errors,
  ../nimbus/evm/memory

proc memory32: EvmMemoryRef =
  result = EvmMemoryRef.new(32)

proc memory128: EvmMemoryRef =
  result = EvmMemoryRef.new(123)

proc memoryMain*() =
  suite "memory":
    test "write":
      var mem = memory32()
      # Test that write creates 32byte string == value padded with zeros
      check mem.write(startPos = 0, value = @[1.byte, 0.byte, 1.byte, 0.byte]).isOk
      check(mem.bytes == @[1.byte, 0.byte, 1.byte, 0.byte].concat(repeat(0.byte, 28)))

    test "write rejects values beyond memory size":
      var mem = memory128()
      check mem.write(startPos = 128, value = @[1.byte, 0.byte, 1.byte, 0.byte]).error.code == EvmErrorCode.MemoryFull
      check mem.write(startPos = 128, value = 1.byte).error.code == EvmErrorCode.MemoryFull

    test "extends appropriately extends memory":
      var mem = EvmMemoryRef.new()
      # Test extends to 32 byte array: 0 < (start_position + size) <= 32
      mem.extend(startPos = 0, size = 10)
      check(mem.bytes == repeat(0.byte, 32))
      # Test will extend past length if params require: 32 < (start_position + size) <= 64
      mem.extend(startPos = 28, size = 32)
      check(mem.bytes == repeat(0.byte, 64))
      # Test won't extend past length unless params require: 32 < (start_position + size) <= 64
      mem.extend(startPos = 48, size = 10)
      check(mem.bytes == repeat(0.byte, 64))

    test "read returns correct bytes":
      var mem = memory32()
      check mem.write(startPos = 5, value = @[1.byte, 0.byte, 1.byte, 0.byte]).isOk
      check(mem.read(startPos = 5, size = 4) == @[1.byte, 0.byte, 1.byte, 0.byte])
      check(mem.read(startPos = 6, size = 4) == @[0.byte, 1.byte, 0.byte, 0.byte])
      check(mem.read(startPos = 1, size = 3) == @[0.byte, 0.byte, 0.byte])

when isMainModule:
  memoryMain()
