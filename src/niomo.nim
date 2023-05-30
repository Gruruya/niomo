# niomo --- Command-line client for Nostr.
# Copyright © 2023 Gruruya <gruruya.chi4c@slmails.com>
#
# This file is part of niomo.
#
# niomo is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, version 3 of the License.
#
# niomo is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with niomo.  If not, see <http://www.gnu.org/licenses/>.

## Command-line client for Nostr.

import
  os, strutils, sequtils, sugar, options, streams, random, terminal, locks,
  pkg/[nmostr, yaml, adix/lptabz, cligen, malebolgia, whisky],
  ./niomo/alias, ./niomo/lptabz_yaml

#[___ Types and helper utils _________________________________________]#

type Config = object
  account = ""
  accounts: LPTabz[string, string, int8, 6]
  relays: LPSetz[string, int8, 6]
  relays_known: LPSetz[string, int8, 6] # TODO: NIP-65
  path {.transient.}: string

proc save(config: Config) {.inline.} =
  var s = newFileStream(config.path, fmWrite)
  dump(config, s)
  s.close()

proc getConfig: Config =
  var config = Config(path: os.getConfigDir() / "niomo/config.yaml")
  if not fileExists(config.path):
    createDir(parentDir config.path)
    for relay in ["wss://relay.snort.social"]: # Default relays
      config.relays_known.add relay
      config.relays.add relay
    config.save()
  else:
    var s = newFileStream(config.path)
    load(s, config)
    s.close()
  config

proc display(keypair: Keypair, bech32 = false): string {.inline.} =
  if not bech32:
    "Public key: " & $keypair.pubkey & "\n" &
    "Private key: " & $keypair.seckey & "\n"
  else:
    "Public key: " & keypair.pubkey.toBech32 & "\n" &
    "Private key: " & keypair.seckey.toBech32 & "\n"

template keypair(config: Config, name: string): Keypair =
  if name in config.accounts:
    toKeypair(SecretKey.fromHex(config.accounts[name]).get)
  else:
    echo name, " isn't an existing account. Creating it."
    let created = newKeypair()
    echo display(created)
    config.accounts[name] = $created.seckey
    config.save()
    created

func parseSecretKey(key: string): SecretKey {.inline.} =
  if key.len == 64:
    return SecretKey.fromHex(key).get
  elif key.len == 63 and key.startsWith("nsec1"):
    return SecretKey.fromRaw(decode("nsec1", key)).get
  raise newException(ValueError, "Unknown private key format. Supported: hex, bech32")

template defaultKeypair: Keypair =
  if config.account.len == 0: newKeypair()
  else: config.keypair(config.account)

template getKeypair(account: Option[string]): Keypair =
  if account.isNone: defaultKeypair()
  elif unsafeGet(account).len == 0: newKeypair()
  else:
    try: # Treat as private key
      parseSecretKey(unsafeGet account).toKeypair
    except:
      config.keypair(unsafeGet account)

template usage(why: string): untyped =
  raise newException(HelpError, why & " ${HELP}")

proc promptYN(default: bool): bool =
  while true:
    case stdin.readLine().toLower():
    of "y", "ye", "yes":
      return true
    else:
      break

proc stripSlash(url: string): string =
  if url[^1] == '/': url[0..^2]
  else: url

#[___ CLI Commands _________________________________________]#


proc post*(echo = false, account: Option[string] = none string, raw = false, event = false, pow = 0, text: seq[string]): int =
  ## make a post
  var config = getConfig()
  let keypair = getKeypair(account)

  var text = text
  if not stdin.isatty: # stdin handling
    if text.len == 0:
      let input = stdin.readAll()
      text = @[input]

    elif "-" in text or "/dev/stdin" in text:
      let input = stdin.readAll()
      for i in 0..text.high:
        if text[i] in ["-", "/dev/stdin"]: text[i] = input

  let post =
    if raw: text.join(" ")
    else:
      var note =
        if not event: note(keypair, text.join(" ")) # TODO: Recommend enabled relays
        else: text.join(" ").fromJson(nmostr.Event)

      if pow > 0:
        note.pow(pow)

      CMEvent(event: note).toJson

  if echo:
    echo post
    return

  proc send(relay, post: string) {.nimcall.} =
    let ws = whisky.newWebSocket(relay)
    ws.send(post)
    # Read back response
    let r = ws.receiveMessage()
    if r.isSome:
      let response = r.unsafeGet
      stdout.write relay & ": "
      if likely response.kind == TextMessage:
            echo response.data
      else: echo response
    ws.close()

  var m = createMaster()
  m.awaitAll:
    for relay in config.relays:
      m.spawn send(relay, post)

proc show*(echo = false, raw = false, kinds: seq[int] = @[1, 6, 30023], limit = 10, search = "", ids: seq[string]): int =
  ## show a post
  ##
  ## input (ids) can be an event ID, filter JSON, or NIP-19 bech32 address
  # TODO: Reversing output
  # TODO: Following and "niomo show" without arguments showing a feed
  var ids = ids
  if not stdin.isatty: # stdin handling
    if ids.len == 0:
      for line in stdin.lines:
        for word in line.split(' '):
          ids.add word

    # replace each occurence of - with stdin
    elif "-" in ids or "/dev/stdin" in ids:
      var words: seq[string]
      for line in stdin.lines:
        for word in line.split(' '):
          words.add word
      var newIDs: seq[string]
      for i in 0..ids.high:
        if ids[i] in ["-", "/dev/stdin"]:
              newIDs.add(words)
        else: newIDs.add ids[i]
      ids = newIDs

  elif ids.len == 0:
    ids = @[""]

  var kinds = kinds
  if -1 in kinds: # no kind filtering if user put -1
    kinds = @[]
  elif kinds.len > 3: # remove defaults kinds if any were user specified
    kinds = kinds[3..^1]

  proc getFilter(postid: string): CMRequest =
    template inputToFilter: Filter =
      ## Assume input to be an event ID
      if postid.len == 0:
            Filter(kinds: kinds, limit: limit, search: search)
      else: Filter(ids: @[postid], kinds: kinds, limit: limit, search: search)

    # TODO: Get relays as well
    var filter =
      try: fromNostrBech32(postid).toFilter # Try to parse as NIP-19 bech32 entity
      except:
        if postid.len != 0 and postid[0] == '{' and postid[^1] == '}' and likely postid[1] == '"':
          try: postid.fromJson(Filter)

          except: return CMRequest(id: randomID(), filter: inputToFilter())
        else: return CMRequest(id: randomID(), filter: inputToFilter())

    if limit != 10 or filter.limit == 0:
      filter.limit = limit
    if kinds != @[1, 6, 30023]:
      for kind in kinds:
        if kind notin filter.kinds: filter.kinds.add kind
    if search.len > 0:
      filter.search = search

    CMRequest(id: randomID(), filter: filter)

  if echo:
    for id in ids:
      echo getFilter(id).toJson
    return

  #[___ Global variables for use in threads ___]#
  template withLock(a: Lock, body: untyped) =
    acquire(a)
    {.gcsafe.}:
      try:
        body
      finally:
        release(a)

  var config {.global.} = getConfig()
  var foundSigs {.global.} = initLPSetz[SchnorrSignature, int8, 6]()

  var configLock {.global.}: Lock
  var foundSigsLock {.global.}: Lock

  #[___ Threaded request implementation ___]#
  proc request[K,Z,z](req: string, relays: LPSetz[K,Z,z], raw: bool) {.gcsafe.} # Early declare for mutual recursion

  proc request(req, relay: string, raw: bool) {.nimcall, gcsafe.} =
    let ws = whisky.newWebSocket(relay)
    var m = createMaster()
    m.awaitAll:
      ws.send(req)
      while true:
        let r = ws.receiveMessage()
        if r.isNone: break
        let response = r.unsafeGet
        if response.kind != TextMessage or response.data.len == 0: break
        try:
          let msgUnion = response.data.fromMessage
          unpack msgUnion, msg:

            if raw:
              echo msg.toJson

            else:
              when msg is SMEvent:
                template event: untyped = msg.event

                template display(event: nmostr.Event) =
                  let header  =
                    event.pubkey.toBech32 & "\n" &
                    NNote(id: event.id).toBech32 & "\n" &
                    event.created_at.format("h:mm:ss MM/dd/YYYY") & ":" & "\n"

                  withLock foundSigsLock:
                    if event.sig notin foundSigs:
                      echo header, event.content, "\n"
                      foundSigs.add event.sig
 
                for tag in event.tags: # collect relays
                  if tag.len >= 3 and (tag[0] == "e" or tag[0] == "p") and tag[2].startsWith("ws"):
                    withLock configLock:
                      config.relays_known.incl tag[2].stripSlash

                case event.kind:
                of 2: # recommend relay
                  if event.content.startsWith("\"ws"):
                    withLock configLock:
                      config.relays_known.incl event.content.stripSlash

                of 6: # repost, NIP-18
                  template echoRepost =
                    if event.content.len > 0:
                      display event

                    var filter = Filter(limit: 1)
                    var relays = initLPSetz[string, int8, 6]()
                    for tag in event.tags:
                      if tag.len >= 2 and tag[1].len > 0:
                        case tag[0]:
                        of "e":
                          filter.ids.add tag[1]
                          if tag.high >= 2 and tag[2].len > 0:
                            relays.incl tag[2].stripSlash
                        of "p":
                          filter.authors.add tag[1]
                          if tag.high >= 2 and tag[2].len > 0:
                            relays.incl tag[2].stripSlash
                    if filter != Filter(limit: 1):
                      if relays.len > 0:
                        m.spawn request(CMRequest(id: randomID(), filter: filter).toJson, relays, raw)
                      else:
                        m.spawn request(CMRequest(id: randomID(), filter: filter).toJson, relay, raw)

                  if event.content.startsWith("{"): # contains a stringified post
                    try:
                      let parsed = event.content.fromJson(nmostr.Event)
                      display parsed
                    except JsonError:
                      echoRepost
                  else:
                    echoRepost
                else:
                  display event

            when msg is SMEose: break
        except: discard
    ws.close()

  proc request[K,Z,z](req: string, relays: LPSetz[K,Z,z], raw: bool) {.gcsafe.} =
    # Call `randomize()` first
    var relays = relays
    var m = createMaster()
    # TODO: Fetch via recommended relays
    m.awaitAll:
      while relays.len > 0:
        let relay = relays.nthKey(rand(relays.len - 1))
        relays.del(relay)
        m.spawn request(req, relay, raw) # TODO: Check if any more posts can be fetched

  if config.relays.len == 0:
    usage "No relays configured, add relays with `niomo relays add`"
  randomize()
  initLock(configLock)
  initLock(foundSigsLock)
  var m = createMaster()
  m.awaitAll:
    for id in ids:
      m.spawn request(getFilter(id).toJson, config.relays, raw)
  config.save()

#[___ Config management _________________________________________]#

template randomAccount: (string, Keypair) =
  var kp = newKeypair()
  var name = generateAlias(kp.pubkey)
  while unlikely name in config.accounts:
    kp = newKeypair()
    name = generateAlias(kp.seckey.toPublicKey)
  (name, kp)

template addAcc(config: Config, name: string, kp: Keypair, echo: bool, bech32 = false): string =
  if not echo:
    config.accounts[name] = $kp.seckey
    config.save()
  name & ":\n" & display(kp, bech32)

proc accountCreate*(echo = false, overwrite = false, bech32 = false, names: seq[string]): string =
  ## generate new accounts
  var config = getConfig()

  if names.len == 0:
    # Generate a new account with a random name based on its public key
    var (name, kp) = randomAccount()
    return config.addAcc(name, kp, echo, bech32)
  else:
    if names.len == 1:
      # Check if `name` is a number, if so, create that many accounts
      try:
        let num = parseInt(names[0])
        for _ in 1..num:
          var (name, kp) = randomAccount()
          result &= config.addAcc(name, kp, echo, bech32)
        return
      except ValueError: discard
    for name in names:
      if overwrite or name notin config.accounts:
        result &= config.addAcc(name, newKeypair(), echo, bech32)
      else:
        result &= name & " already exists, refusing to overwrite\n"

proc accountImport*(echo = false, privateKeys: seq[string]): int =
  ## import private keys as accounts
  var config = getConfig()
  if privateKeys.len == 0:
    usage "No private keys given, nothing to import. ${HELP}"
  for key in privateKeys:
    let seckey = parseSecretKey(key)
    echo config.addAcc(generateAlias(seckey.toPublicKey), seckey, echo)

proc accountSet*(name: seq[string]): string =
  ## change what account to use by default, pass no arguments to be anonymous
  ##
  ## without an account set, a new key will be generated every time you post
  var config = getConfig()

  if name.len == 0:
    result = "Unsetting default account. A new random key will be generated for every post."
    config.account = ""
    config.save()
    return

  let name = name.join(" ")

  if name in config.accounts.keys.toSeq:
    result = "Setting default account to \"" & name & '"'
    config.account = name
    config.save()
    return

  echo name, " doesn't exist, creating it"
  echo accountCreate(names = @[name])
  accountSet(@[name])

proc accountRemove*(names: seq[string]): int =
  ## remove accounts
  if names.len == 0:
    usage "No account names given, nothing to remove"
  else:
    var config = getConfig()
    for name in names: # Only do exact match
      if name in config.accounts:
        echo "About to remove record of " & name & "'s private key, are you sure? [y/N]"
        if promptYN(false):
          echo "Removing account: " & name & "\n" & display(config.keypair(name))
          if config.account == name: config.account = "" # Unset if it's default account
          config.accounts.del(name)
    config.save()

proc accountList*(bech32 = false, prefixes: seq[string]): string =
  ## list accounts (optionally) only showing those whose names start with any of the given `prefixes`
  let config = getConfig()
  if config.account.len > 0:
        echo "Default account: " & config.account
  else: echo "No default account set, a random key will be generated every time you post"

  for account, key in config.accounts.pairs:
    if prefixes.len == 0 or any(prefixes, prefix => account.startsWith(prefix)):
      let kp = SecretKey.fromHex(key).get.toKeypair
      result &= account & ":\n" & display(kp, bech32)

  if result.len == 0:
    result = "No accounts found. Use `account create` to make one.\nYou could also use niomo without an account and it will generate different random key for every post."

proc relayAdd*(activate = true, relays: seq[string]): int =
  ## add relays to known relays
  var config = getConfig()
  for relay in relays:
    let relay = relay.stripSlash()
    if activate:
      if relay in config.relays_known:
        echo "Enabling ", relay
      else:
        echo "Adding and enabling ", relay
      config.relays.add relay
    else: echo "Adding ", relay
    config.relays_known.incl relay
  config.save()

proc relayEnable*(relays: seq[string]): int =
  ## enable relays to broadcast your posts with
  var config = getConfig()
  for relay in relays:
    try: # Parse as index
      let index = parseInt(relay)
      if index <= config.relays_known.len and index > 0:
        let relay = config.relays_known.nthKey(index - 1)
        if relay in config.relays:
          echo relay & " is already enabled"
        else:
          echo "Enabling ", relay
          config.relays.add relay
      else:
        echo $index & " is out of bounds, there are only " & $config.relays_known.len & " known relays."

    except ValueError: # Parse as url
      let relay = relay.stripSlash()
      if relay in config.relays_known:
        echo "Enabling ", relay
      else:
        echo "Adding and enabling ", relay
        config.relays_known.add relay
      config.relays.incl relay
  config.save()

proc relayDisable*(delete = false, relays: seq[string]): int =
  ## stop sending posts to specified relays
  template disable(relay: string) =
    if delete:
      if relay in config.relays_known:
        echo "Deleting ", relay
        config.relays.excl relay
        config.relays_known.excl relay
      else:
        echo relay, " doesn't exist"
    elif relay in config.relays:
      echo "Disabling ", relay
      config.relays.excl relay
    else:
      echo relay, " is already disabled"

  var config = getConfig()
  var indexRemove: seq[string]
  for relay in relays:
    let relay = relay.stripSlash
    if relay in config.relays_known:
      disable(relay)
    else:
      try: # Disable by index
        let index = parseInt(relay)
        if index <= config.relays_known.len and index > 0:
          indexRemove.add config.relays_known.nthKey(index - 1)
      except ValueError: discard # Ignore request to disable non-existant relay
  config.save()
  if indexRemove.len > 0:
    result = relayDisable(delete, indexRemove)

proc relayRemove(relays: seq[string]): int =
  ## remove a relay
  relayDisable(delete = true, relays = relays)

proc relayList*(prefixes: seq[string]): string =
  ## list relay urls and their indexes. enable/disable/remove can use the index instead of a url.
  ##
  ## optionally filters shown relays to only those matching a given `prefix`
  let config = getConfig()
  for i, relay in pairs[string, int8, 6](config.relays_known):
    if prefixes.len == 0 or any(prefixes, prefix => relay.startsWith(prefix)):
      echo $(i + 1), (if relay in config.relays: " * " else: " "), relay
  # could put enabled relays first

#[___ CLI _________________________________________]#
when isMainModule:
  import pkg/[cligen/argcvt]
  include cligen/mergeCfgEnvMulMul
  const nimbleFile = staticRead(currentSourcePath().parentDir /../ "niomo.nimble")
  clCfg.version = nimbleFile.fromNimble("version")

  # Option[T] helpdoc
  # taken from c-blake "https://github.com/c-blake/cligen/issues/212#issuecomment-1167777874"
  proc argParse[T](dst: var Option[T], dfl: Option[T], a: var ArgcvtParams): bool =
      var uw: T # An unwrapped value
      if argParse(uw, (if dfl.isSome: dfl.get else: uw), a):
        dst = option(uw); return true
  proc argHelp*[T](dfl: Option[T]; a: var ArgcvtParams): seq[string] =
    result = @[ a.argKeys, $T, (if dfl.isSome: $dfl.get else: "?")]

  dispatchMultiGen(
    ["accounts"],
    [accountCreate, cmdName = "create", help = {"echo": "generate and print accounts without saving", "overwrite": "overwrite existing accounts"}, dispatchName = "aCreate"],
    [accountSet, cmdName = "set", dispatchName = "aSet", usage = "$command $args\n${doc}"],
    [accountImport, cmdName = "import", dispatchName = "aImport"],
    [accountRemove, cmdName = "remove", dispatchName = "aRemove", usage = "$command $args\n${doc}"], # alias rm
    [accountList, cmdName = "list", dispatchName = "aList", usage = "$command $args\n${doc}"])
  dispatchMultiGen(
    ["relays"],
    [relayAdd, cmdName = "add", dispatchName = "rAdd"],
    [relayEnable, cmdName = "enable", dispatchName = "rEnable", usage = "$command $args\n${doc}"],
    [relayDisable, cmdName = "disable", dispatchName = "rDisable"],
    [relayRemove, cmdName = "remove", dispatchName = "rRemove", usage = "$command $args\n${doc}"],
    [relayList, cmdName = "list", dispatchName = "rList", usage = "$command $args\n${doc}"])
  dispatchMulti(["multi", cmdName = "niomo"],
    [show, help = {"kinds": "kinds to filter for, pass -1 for any", "raw": "display raw JSON of the response"}, short = {"raw": 'R'}, positional = "ids"],
    [post, help = {"raw": "treat input as raw message (JSON)", "event": "treat input as raw event JSON"}, short = {"raw": 'R', "event": 'E', "pow": 'P'}],
    [accounts, doc = "manage your identities/keypairs. run `accounts help` for subsubcommands", stopWords = @["create", "set", "import", "remove", "list"]],
    [relays, doc = "manage what relays to send posts to. run `relay help` for subsubcommands", stopWords = @["add", "enable", "disable", "remove", "list"]])
