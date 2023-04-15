version     = "0.0.1"
author      = "Gruruya"
description = "Nostr reference command line client using nmostr."
license     = "AGPL-3.0-only"

srcDir = "src"
skipDirs = @["tests"]
bin = @["niomo"]

# Dependencies
requires "nim >= 1.9.1"
requires "https://github.com/Gruruya/niomo"
requires "cligen ^= 1.6.0"
requires "yaml ^= 1.1.0"
requires "whisky ^= 0.1.1"
requires "adix >= 0.5.2"
