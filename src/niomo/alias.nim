# Pubkey to human-friendly name --- niomo
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only
#
# This file incorporates work covered by the following copyright:
#   Copyright © 2020, 2021 Status Research & Development GmbH
#   SPDX-License-Identifier: MIT

## Generate a deterministic friendly name for a public key
## Modified from `nim-status/status/private/alias.nim`

import
  std/bitops,
  pkg/[secp256k1, stew/endians2],
  ./wordpool

# For details: https://en.wikipedia.org/wiki/Linear-feedback_shift_register
type
  Lsfr = ref object
    poly*: uint64
    data*: uint64

proc next(self: Lsfr): uint64 {.raises: [].} =
  var bit: uint64 = 0
  for i in 0..64:
    if bitand(self.poly, 1.uint64 shl i) != 0:
      bit = bitxor(bit, self.data shr i)
  bit = bitand(bit, 1.uint64)
  self.data = bitor(self.data shl 1, bit)
  result = self.data

func truncPubkey(pubkey: SkPublicKey): uint64 =
  let rawKey = pubkey.toRaw
  fromBytesBE(uint64, rawKey[25..32])

func truncPubkey(pubkey: SkXOnlyPublicKey): uint64 =
  let rawKey = pubkey.toRaw
  fromBytesBE(uint64, rawKey[24..31])

func generateAlias*(pubkey: SkPublicKey | SkXOnlyPublicKey): string =
  ## generateAlias returns a 3-words generated name given a public key.
  ## We ignore any error, empty string result is considered an error.
  let seed = truncPubkey(pubkey)
  const poly: uint64 = 0xB8
  let
    generator = Lsfr(poly: poly, data: seed)
    adjective1 = adjectives[generator.next mod adjectives.len]
    adjective2 = adjectives[generator.next mod adjectives.len]
    animal = animals[generator.next mod animals.len]
  adjective1 & adjective2 & animal
