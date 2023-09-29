# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
# SPDX-License-Identifier: AGPL-3.0-only

version     = "0.0.12"
author      = "Gruruya"
description = "Reference Nostr command-line client using nmostr."
license     = "AGPL-3.0-only"

srcDir = "src"
bin = @["niomo"]

# Dependencies
requires "nim >= 2.0.0"
requires "nmostr >= 0.1.1"
requires "cligen >= 1.6.0 & < 2.0.0"
requires "yaml >= 1.1.0 & < 2.0.0"
requires "adix >= 0.5.2"
requires "whisky >= 0.1.2"
requires "malebolgia >= 0.1.0"
