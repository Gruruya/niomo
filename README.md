# niomo

Command-line client for Nostr.
Experimental, very new and featureless.

Highlights:
* Pass -e to echo JSON rather than submitting it.
* Posting without an account will generate a random key for every post.

Install
---
Install Nim 2.0, here are two options:
* See `Installing Nim 2.0 RC2` at the Nim-lang blog [here](https://nim-lang.org/blog/2023/03/31/version-20-rc2.html)
* Install [choosenim](https://github.com/dom96/choosenim#installation) and run `choosenim devel`

Then, run `nimble install https://github.com/Gruruya/niomo`

Usage
---
```bash
niomo post -a first-account Hello world!
niomo show
```

See `niomo help` to list the subcommands, you can do the same for any subcommand containing subsubcommands by doing `niomo account help`, using `account` as an example.  
For individual commands pass the `-h` flag `niomo post -h`

Commands can be shortened to any unique string, so `niomo a l` is the same as `niomo account list`

---
[![GitHub CI](../../actions/workflows/build.yml/badge.svg?branch=master)](../../actions/workflows/build.yml)
[![Minimum supported Nim version](https://img.shields.io/badge/Nim-1.9.1+-informational?logo=Nim&labelColor=232733&color=F3D400)](https://nim-lang.org)
[![License](https://img.shields.io/github/license/Gruruya/niomo?logo=GNU&logoColor=000000&labelColor=FFFFFF&color=663366)](LICENSE.md)
