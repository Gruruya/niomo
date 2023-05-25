version     = "0.0.8.9"
author      = "Gruruya"
description = "Reference Nostr command-line client using nmostr."
license     = "AGPL-3.0-only"

srcDir = "src"
bin = @["niomo"]

# Dependencies
requires "nim >= 1.9.3"
requires "nmostr >= 0.0.10.1"
requires "cligen ^= 1.6.0"
requires "yaml ^= 1.1.0"
requires "adix >= 0.5.2"
requires "whisky >= 0.1.2"
requires "malebolgia >= 0.1.0"
