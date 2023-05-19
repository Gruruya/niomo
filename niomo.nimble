version     = "0.0.6.3"
author      = "Gruruya"
description = "Nostr reference command line client using nmostr."
license     = "AGPL-3.0-only"

srcDir = "src"
bin = @["niomo"]

# Dependencies
requires "nim >= 1.9.1"
requires "nmostr >= 0.0.8.4"
requires "cligen ^= 1.6.0"
requires "yaml ^= 1.1.0"
requires "ws >= 0.5.0"
requires "adix >= 0.5.2"
