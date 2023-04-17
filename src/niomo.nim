# niomo --- Command line client for Nostr.
# Copyright © 2023 Gruruya <greytest@disroot.org>
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

## Command line client for Nostr.

import
  std/[os, strutils, sequtils, sugar, options, streams, random, asyncdispatch, terminal],
  pkg/[nmostr, yaml, adix/lptabz, cligen, ws],
  ./niomo/alias, ./niomo/lptabz_yaml

from std/terminal import getch

###### Types and helper utils ######

template usage(why: string): untyped =
  raise newException(HelpError, why & " ${HELP}")

proc promptYN(default: bool): bool =
  while true:
    case getch():
    of 'y', 'Y':
      return true
    of 'n', 'N':
      return false
    of '\13': # RET
      return default
    of '\3', '\4': # C-c, C-d
      return default
      # raise newException(CatchableError, "User requested exit")
    else:
      continue

type Config = object
  account = ""
  accounts: LPTabz[string, string, int8, 6]
  relays: LPSetz[string, int8, 6]
  relays_known: LPSetz[string, int8, 6] # TODO: NIP-65

template save(config: Config, path: string) =
  var s = newFileStream(path, fmWrite)
  dump(config, s)
  s.close()

template getConfig: Config =
  let configPath {.inject.} = os.getConfigDir() / "niomo/config.yaml"
  var config = Config()
  if not fileExists(configPath):
    createDir(parentDir configPath)
    for relay in ["wss://relay.snort.social"]: # Default relays
      config.relays_known.incl relay
      config.relays.incl relay
    config.save(configPath)
  else:
    var s = newFileStream(configPath)
    load(s, config)
    s.close()
  config

template display(keypair: Keypair, bech32 = false): string =
  if not bech32:
    "Private key: " & $keypair.seckey & "\n" &
    "Public key: " & $keypair.pubkey & "\n"
  else:
    "Private key: " & keypair.seckey.toBech32 & "\n" &
    "Public key: " & keypair.pubkey.toBech32 & "\n"

template keypair(config: Config, name: string): Keypair =
  if name in config.accounts:
    toKeypair(SkSecretKey.fromHex(config.accounts[name]).get)
  else:
    echo name, " isn't an existing account. Creating it."
    let created = newKeypair()
    echo display(created)
    config.accounts[name] = $created.seckey
    config.save(configPath)
    created

func parseSecretKey(key: string): SkSecretKey {.inline.} =
  if key.len == 64:
    return SkSecretKey.fromHex(key).tryGet
  elif key.len == 63 and key.startsWith("nsec1"):
    return SkSecretKey.fromRaw(decode("nsec1", key)).tryGet
  raise newException(ValueError, "Unknown private key format. Supported: hex, bech32")

  doAssert false # Silence compiler, will never reach
  return SkSecretKey.fromHex(key).tryGet

template defaultKeypair: Keypair =
  if config.account == "": newKeypair()
  else: config.keypair(config.account)

template getKeypair(account: Option[string]): Keypair =
  if account.isNone: defaultKeypair()
  elif account == some "": newKeypair()
  else:
    try: # Parse as private key
      parseSecretKey(unsafeGet account).toKeypair
    except:
      config.keypair(unsafeGet account)

template readstdin(arg: var seq[string]): bool =
  if not stdin.isatty:
    let input = stdin.readAll()

    if arg.len == 0:
      arg = @[input]

    elif "-" in arg or "/dev/stdin" in arg:
      for i, item in arg:
        if item == "-": arg[i] = input
        elif item == "/dev/stdin": arg[i] = input
    true
  else: false

###### CLI Commands ######

proc post*(echo = false, account: Option[string] = none string, text: seq[string]): int =
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
      for i in 0..<text.len:
        if text[i] in ["-", "/dev/stdin"]: text[i] = input

  let post = CMEvent(event: note(keypair, text.join(" "))).toJson # TODO: Recommend enabled relays

  if echo:
    echo post
    return

  proc send(relay, post: string) {.async.} =
    let ws = await newWebSocket(relay)
    await ws.send(post)
    echo await ws.receiveStrPacket()
    ws.close()

  var tasks = newSeqOfCap[Future[void]](config.relays.len)
  for relay in config.relays:
    tasks.add send(relay, post)
  waitFor all(tasks)

proc show*(echo = false, raw = false, kinds: seq[int] = @[1, 6, 30023], limit = 10, ids: seq[string]): int =
  ## show a post
  # TODO: Reversing output
  # TODO: Following and "niomo show" without arguments showing a feed

  var ids = ids
  if not stdin.isatty: # stdin handling
    if ids.len == 0:
      for line in stdin.lines:
        for word in line.split(' '):
          ids.add word

    elif "-" in ids or "/dev/stdin" in ids:
      var words: seq[string]
      for line in stdin.lines:
        for word in line.split(' '):
          words.add word

      var newIDs: seq[string]
      for i in 0..<ids.len:
        if ids[i] in ["-", "/dev/stdin"]:
          newIDs.add(words)
        else:
          newIDs.add ids[i]
      ids = newIDs

  elif ids.len == 0:
    ids = @[""]

  var kinds = kinds
  if -1 in kinds:
    kinds = @[]
  elif kinds.len > 3:
    kinds = kinds[3..^1]

  var config = getConfig()

  template parse(postid: string): untyped =
    var filter = Filter(limit: limit, kinds: kinds)
    try:
      # TODO: Get relays as well
      let bech32 = fromNostrBech32(postid) # Check if it's an encoded bech32 string
      unpack bech32, entity:
        when entity is NNote:
          filter.ids = @[entity.id.toHex]
        elif entity is NProfile:
          filter.authors = @[entity.pubkey.toHex]
        elif entity is NEvent:
          filter.ids = @[entity.id.toHex]
        elif entity is NAddr:
          filter.authors = @[entity.author.toHex]
          filter.tags = @[@["#d", entity.id]]
        elif entity is SkXOnlyPublicKey:
          filter.authors = @[entity.toHex]

    except InvalidBech32Error, UnknownTLVError:
      if postid.len != 0:
        filter.ids.add postid

    CMRequest(id: randomID(), filter: filter)

  if echo:
    for id in ids:
      echo parse(id).toJson
    return

  var foundSigs = initLPSetz[SkSchnorrSignature, int8, 6]()

  proc request[K,Z,z](req: string, relays: LPSetz[K,Z,z]) {.async.}

  proc request(req, relay: string) {.async.} =
    let ws = await newWebSocket(relay)

    proc request(req: string) {.async.} =
      var tasks: seq[Future[void]]

      await ws.send(req)
      while true:
        let optMsg = await ws.receiveStrPacket()
        if optMsg == "": break
        try:
          let msgUnion = optMsg.fromMessage
          unpack msgUnion, msg:

            if raw:
              echo msg.toJson

            else:
              when msg is SMEvent:
                template event: untyped = msg.event

                let header  =
                  event.pubkey.toBech32 & "\n" &
                  $event.id & "\n" &
                  $event.created_at & ":" & "\n"

                template display(event: events.Event) =
                  if event.sig notin foundSigs:
                    foundSigs.incl event.sig
                    echo header, event.content, "\n"

                for tag in event.tags: # collect relays
                  if tag.len >= 3 and (tag[0] == "e" or tag[0] == "p") and tag[2].len > 0:
                    config.relays_known.incl tag[2]

                case event.kind:
                of 2: # recommend relay
                  if event.content.startsWith('"'):
                    config.relays_known.incl event.content

                of 6: # repost, NIP-18
                  template echoRepost =
                    var filter = Filter(limit: 1)
                    var relays = initLPSetz[string, int8, 6]()
                    for tag in event.tags:
                      if tag.len >= 2 and tag[1].len > 0:
                        case tag[0]:
                        of "e":
                          filter.ids.add tag[1]
                          if tag.len >= 3 and tag[2].len > 0:
                            relays.add tag[2]
                        of "p":
                          filter.authors.add tag[1]
                          if tag.len >= 3 and tag[2].len > 0:
                            relays.add tag[2]
                    if filter != Filter(limit: 1):
                      if event.content.len > 0:
                        display event
                      if relays.len > 0:
                        tasks.add request(CMRequest(id: randomID(), filter: filter).toJson, relays)
                      else:
                        tasks.add request(CMRequest(id: randomID(), filter: filter).toJson)
                    else:
                      display event
                  if event.content.startsWith("{"): # is a stringified post
                    try:
                      let parsed = event.content.fromJson(events.Event)
                      display parsed
                    except JsonError:
                      echoRepost
                  else:
                    echoRepost
                else:
                  display event # TODO: Replace duplicate displays with breaks

            when msg is SMEose: break
        except: discard
        await all(tasks)
    await request(req)
    ws.close()

  proc request[K,Z,z](req: string, relays: LPSetz[K,Z,z]) {.async.} =
    # Call `randomize()` first
    var relays = relays
    var tasks = newSeqOfCap[Future[void]](relays.len)
    while relays.len > 0:
      let relay = relays.nthKey(rand(relays.len - 1))
      relays.del(relay)
      tasks.add request(req, relay) # TODO: Check if any more posts can be fetched
    await all(tasks)

  if config.relays.len == 0:
    usage "No relays configured, add relays with `niomo relay enable`"
  randomize()
  var tasks = newSeqOfCap[Future[void]](ids.len * config.relays.len)
  for id in ids:
    tasks.add request(parse(id).toJson, config.relays)
  waitFor all(tasks)
  config.save(configPath)

### Config management ###

template randomAccount: (string, Keypair) =
  var kp = newKeypair()
  var name = generateAlias(kp.pubkey)
  while name in config.accounts:
    kp = newKeypair()
    name = generateAlias(kp.seckey.toPublicKey)
  (name, kp)

template addAcc(config: Config, name: string, kp: Keypair, echo: bool): string =
  if not echo:
    config.accounts[name] = $kp.seckey
    config.save(configPath)
  name & ":\n" & display(kp)

proc accountCreate*(echo = false, overwrite = false, names: seq[string]): string =
  ## generate new accounts
  var config = getConfig()

  if names.len == 0:
    # Generate a new account with a random name based on its public key
    var (name, kp) = randomAccount()
    return config.addAcc(name, kp, echo)
  else:
    if names.len == 1:
      # Check if `name` is a number, if so, create that many accounts
      try:
        let num = parseInt(names[0])
        for _ in 1..num:
          var (name, kp) = randomAccount()
          result &= config.addAcc(name, kp, echo)
        return
      except ValueError: discard
    for name in names:
      if overwrite or name notin config.accounts:
        result &= config.addAcc(name, newKeypair(), echo)
      else:
        result &= name & " already exists, refusing to overwrite\n"

proc accountImport*(echo = false, private_keys: seq[string]): int =
  ## import private keys as accounts
  var config = getConfig()
  if privateKeys.len == 0:
    usage "No private keys given, nothing to import. ${HELP}"
  for key in privateKeys:
    let seckey = parseSecretKey(key)
    let kp = seckey.toKeypair
    echo config.addAcc(generateAlias(seckey.toPublicKey), kp, echo)

proc accountSet*(name: seq[string]): string =
  ## change what account to use by default, pass no arguments to be anonymous
  ##
  ## without an account set, a new key will be generated every time you post
  var config = getConfig()

  if name.len == 0:
    result = "Unsetting default account. A new random key will be generated for every post."
    config.account = ""
    config.save(configPath)
    return

  let name = name.join(" ")

  if name in config.accounts.keys.toSeq:
    result = "Setting default account to \"" & name & '"'
    config.account = name
    config.save(configPath)
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
          if config.account == name: config.account = ""
          config.accounts.del(name)
    config.save(configPath)

proc accountList*(bech32 = false, prefixes: seq[string]): string =
  ## list accounts (optionally) only showing those whose names start with any of the given `prefixes`
  let config = getConfig()
  if config.account != "":
        echo "Default account: " & config.account
  else: echo "No default account set, a random key will be generated every time you post"

  for account, key in config.accounts.pairs:
    if prefixes.len == 0 or any(prefixes, prefix => account.startsWith(prefix)):
      let kp = SkSecretKey.fromHex(key).tryGet.toKeypair
      result &= account & ":\n" & display(kp, bech32)

  if result.len == 0:
    result = "No accounts found. Use `account create` to make one.\nYou could also use niomo without an account and it will generate different random key for every post."

proc relayAdd*(enable = true, relays: seq[string]): int =
  ## add relays to known relays
  var config = getConfig()
  for relay in relays:
    if enable:
      if relay in config.relays_known:
        echo "Enabling ", relay
      else:
        echo "Adding and enabling ", relay
      config.relays.incl relay
    else: echo "Adding ", relay
    config.relays_known.incl relay
  config.save(configPath)

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
          config.relays.incl relay
      else:
        echo $index & " is out of bounds, there are only " & $config.relays_known.len & " known relays."

    except ValueError: # Parse as url
      if relay in config.relays_known:
        echo "Enabling ", relay
      else:
        echo "Adding and enabling ", relay
        config.relays_known.incl relay
      config.relays.incl relay
  config.save(configPath)

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
    if relay in config.relays_known:
      disable(relay)
    else:
      try: # Disable by index
        let index = parseInt(relay)
        if index <= config.relays_known.len and index > 0:
          indexRemove.add config.relays_known.nthKey(index - 1)
      except ValueError: discard # Ignore request to disable non-existant relay
  config.save(configPath)
  if indexRemove.len > 0:
    return relayDisable(delete, indexRemove)

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

###### CLI ######
when isMainModule:
  import pkg/[cligen/argcvt]
  # taken from c-blake "https://github.com/c-blake/cligen/issues/212#issuecomment-1167777874"
  include cligen/mergeCfgEnvMulMul
  const nimbleFile = staticRead(currentSourcePath().parentDir /../ "niomo.nimble")
  clCfg.version = nimbleFile.fromNimble("version")
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
    ["relay"],
    [relayAdd, cmdName = "add", dispatchName = "rAdd"],
    [relayEnable, cmdName = "enable", dispatchName = "rEnable", usage = "$command $args\n${doc}"],
    [relayDisable, cmdName = "disable", dispatchName = "rDisable"],
    [relayRemove, cmdName = "remove", dispatchName = "rRemove", usage = "$command $args\n${doc}"],
    [relayList, cmdName = "list", dispatchName = "rList", usage = "$command $args\n${doc}"])
  dispatchMulti(["multi", cmdName = "niomo"],
    [show, help = {"kinds": "kinds to filter for, pass -1 for any", "raw": "display all of the response rather than filtering to just the content"}, positional = "ids"],
    [post],
    [accounts, doc = "manage your identities/keypairs. run `accounts help` for subsubcommands", stopWords = @["create", "set", "import", "remove", "list"]],
    [relay, doc = "manage what relays to send posts to. run `relay help` for subsubcommands", stopWords = @["add", "enable", "disable", "remove", "list"]])
