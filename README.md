[
Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
SPDX-License-Identifier: CC-BY-SA-4.0
]:#

# niomo $\textcolor{gold}{\textsf{Powered by Nim}}$

Command-line client for Nostr. Experimental.  
_Reference client for [nmostr](https://github.com/Gruruya/nmostr)_ $\color{grey}{\textsf{— the Nim Nostr library }}$

Usage
---
```bash
# Use (and create) the account "first account" and post Hello world!
niomo post -a 'first account' Hello world!
# Show the global feed of your enabled relays
niomo show
# Add and enable a new relay
niomo relays add wss://relay.mostr.pub
# Echo 30 new keypairs
niomo account create 30 -e
# Unset default account, generating a new keypair for every post
niomo a s # Same as niomo account set
```

```bash
Usage:
  niomo {SUBCMD}  [sub-command options & parameters]
where {SUBCMD} is one of:
  help      print comprehensive or per-cmd help
  show      show a post
  post      make a post
  accounts  manage your identities/keypairs. run `accounts help` for subsubcommands
  relays    manage what relays to send posts to. run `relays help` for subsubcommands
```

Commands can be shortened to any unique string, so `niomo a l` is the same as `niomo accounts list`

Install
---
Install Nim 2.0, one way of doing so is with [choosenim](https://github.com/dom96/choosenim#installation) by running `choosenim devel`

Then, run `nimble install https://github.com/Gruruya/niomo`

---
<pre>
<a href="../../actions/workflows/build.yml"><img src="../../actions/workflows/build.yml/badge.svg?branch=master" /></a> <a href="https://nim-lang.org"><img src="https://img.shields.io/badge/Nim-1.9.3+-informational?logo=Nim&labelColor=232733&color=F3D400"/></a> <a href="LICENSE.md"><img src="https://img.shields.io/github/license/Gruruya/niomo?logo=GNU&logoColor=000000&labelColor=FFFFFF&color=663366"/></a>
</pre>
