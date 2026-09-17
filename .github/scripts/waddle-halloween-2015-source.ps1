param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-Normalized([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "WADDLE_PARTY2015_SOURCE=FAIL missing=$Path"
  }
  return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Require-Contains([string]$Text,[string]$Needle,[string]$Label) {
  if (-not $Text.Contains($Needle)) { throw "WADDLE_PARTY2015_SOURCE=FAIL missing_contract=$Label" }
}

function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
  if ($Text.Contains($Needle)) { throw "WADDLE_PARTY2015_SOURCE=FAIL stale_contract=$Label" }
}

function Require-Regex([string]$Text,[string]$Pattern,[string]$Label) {
  if ($Text -notmatch $Pattern) { throw "WADDLE_PARTY2015_SOURCE=FAIL missing_contract=$Label" }
}

function Get-GitBlobSha([string]$Path) {
  $payload = [IO.File]::ReadAllBytes($Path)
  $prefix = [Text.Encoding]::UTF8.GetBytes("blob $($payload.Length)`0")
  $all = New-Object byte[] ($prefix.Length + $payload.Length)
  [Buffer]::BlockCopy($prefix,0,$all,0,$prefix.Length)
  [Buffer]::BlockCopy($payload,0,$all,$prefix.Length,$payload.Length)
  $sha1 = [Security.Cryptography.SHA1]::Create()
  try { return (($sha1.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') }
  finally { $sha1.Dispose() }
}

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 8) { return $false }
    $header = New-Object byte[] 3
    if ($stream.Read($header,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($header)
  } finally { $stream.Dispose() }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$partyPath = Join-Path $repo 'src/server/updates/2015.ts'
$filesPath = Join-Path $repo 'src/server/game-data/files.ts'
$roomsPath = Join-Path $repo 'src/server/game-data/rooms.ts'
$updatesPath = Join-Path $repo 'src/server/updates/updates.ts'
$generalPath = Join-Path $repo 'src/server/file-generators/general.json.ts'
$fileGeneratorsPath = Join-Path $repo 'src/server/file-generators/index.ts'
$dependenciesPath = Join-Path $repo 'src/server/file-generators/dependencies.json.ts'
$xtHandlerPath = Join-Path $repo 'src/server/socket-server/xt-handler.ts'
$protocolPath = Join-Path $repo 'src/server/socket-server/handlers/protocol.ts'
$joinHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/join.ts'
$partyHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$partyDataPath = Join-Path $repo 'src/server/game-data/party.ts'
$canonicalManifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
$partyRoot = Join-Path $repo 'media/default/party2015'
$historicalManifestPath = Join-Path $partyRoot 'manifest.json'

$files = Read-Normalized $filesPath
Require-Contains $files "const PARTY2015 = 'party2015';" 'party2015_file_ref_constant'
Require-Regex $files '(?m)^\s*PARTY2015,\s*$' 'party2015_file_ref_registration'

$rooms = Read-Normalized $roomsPath
foreach ($roomKey in @('dojosnow','hotellobby','hotelspa','hotelroof','cloudforest','pufflepark','skatepark','pufflewild')) {
  Require-Regex $rooms ("(?s)'{0}'\s*:\s*\{{.*?\bid\s*:\s*\d+\b" -f [regex]::Escape($roomKey)) ("room_symbol_{0}" -f $roomKey)
}

$party = Read-Normalized $partyPath
foreach ($contract in @(
  "const P = 'party2015:';",
  "const ref = (relative: string) => P + relative;",
  "date: '2015-10-21'",
  "partyName: 'Halloween Party 2015'",
  "activeFeatures: '20150501'",
  'gameStringChanges: HALLOWEEN_2015_DIALOGUE_STRINGS',
  "id: 'halloween-2015'",
  'messageCount: 10',
  'communicatorMessageCount: 5',
  'taskCount: 10',
  'maxCoinUpdate: 10',
  "partyStartDate: '2015-10-21 00:00:00'",
  "partyEndDate: '2015-11-05 00:00:00'",
  'unlockDayIndex: 16',
  'numOfDaysInParty: 16',
  'rooms: HALLOWEEN_2015_ROOMS',
  'music: HALLOWEEN_2015_MUSIC',
  "'play/v2/content/global/content/party.swf': 'svanilla:media/play/v2/content/global/content/party.swf'",
  "'play/v2/client/QuestCommunicator.swf': ref('client/QuestCommunicator.swf')",
  "'play/v2/client/interface.swf': ref('client/ClientInterface-HalloweenParty2015.swf')",
  "'play/v2/content/global/content/interface.swf': ref('client/ClientInterface-HalloweenParty2015.swf')",
  "'play/v2/content/global/content/features.swf': ref('content/ContentFeatures-HalloweenParty2015.swf')",
  "'play/v2/content/global/content/party_icon.swf': ref('content/ContentParty_icon-HalloweenParty2015.swf')",
  "'content/party_icon.swf': [ref('content/ContentParty_icon-HalloweenParty2015.swf'), 'party_icon', 'scavenger_hunt_icon']",
  "'close_ups/quest_interface.swf': [ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf'), 'w.p2015.may.partyinterface', 'w.app.generic.partyinterface', 'scavenger_hunt']",
  "'close_ups/quest_interface.swf': { en: ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf') }",
  "'close_ups/halloLogin.swf': [ref('close_ups/Hallo15_dialogue_login.swf'), 'w.p2015.may.login']",
  "'close_ups/halloLogin.swf': { en: ref('close_ups/Hallo15_dialogue_login.swf') }",
  '...dialogueGlobalChanges',
  '...dialogueLocalChanges',
  '...tileGlobalChanges',
  '...tileLocalChanges',
  '...musicFileChanges',
  "date: '2015-11-05'",
  "end: ['party']"
)) {
  Require-Contains $party $contract ("party_" + ($contract -replace '[^A-Za-z0-9]+','_').Trim('_'))
}

# Root rule: October 2015 uses the preserved CPArchives interaction family on
# top of Waddle's canonical late-AS3 generic party runtime. The later CPImagined
# 2310 recreation may stay in media as provenance, but its replacement
# party/map/config/interface stack must never become the live runtime.
foreach ($stale in @(
  "'play/en/web_service/game_configs.bin'",
  "'play/v2/content/global/content/party.swf': ref('content/party.swf')",
  "'play/v2/content/global/content/map.swf'",
  "'content/map.swf':",
  'ClientInterface-HalloweenClassic2015.swf',
  'Close_upsQuest_interface-HalloweenClassic2015.swf',
  "'close_ups/ghostAdopt.swf'",
  "'close_ups/skipDialogue.swf'"
)) {
  Require-NotContains $party $stale ("mixed_2310_" + ($stale -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
Require-NotContains $party "'play/v2/content/global/content/logo.swf'" 'legacy_wrong_logo_route'

# The dynamic route tables are generated from the party's committed changes;
# they are the authoritative way the preserved interface resolves crumbs.
$fileGenerators = Read-Normalized $fileGeneratorsPath
Require-Contains $fileGenerators 'const getRuntimePathsJson: FileGenerator' 'runtime_paths_generator'
Require-Contains $fileGenerators '...Object.fromEntries(d.getGlobalPaths())' 'global_paths_merge'
Require-Contains $fileGenerators "'play/en/web_service/game_configs/paths.json': getRuntimePathsJson" 'runtime_paths_registration'
Require-Contains $fileGenerators 'const getRuntimeRoomsJson: FileGenerator' 'runtime_rooms_generator'
Require-Contains $fileGenerators "version >= '2017-01-31' && version < '2017-03-30'" 'community_pin_historical_window'
Require-Contains $fileGenerators "'play/en/web_service/game_configs/rooms.json': getRuntimeRoomsJson" 'runtime_rooms_registration'
Require-Contains $fileGenerators 'const getRuntimeGameStringsJson: FileGenerator' 'runtime_game_strings_generator'
Require-Contains $fileGenerators "'play/en/web_service/game_configs/game_strings.json': getRuntimeGameStringsJson" 'runtime_game_strings_registration'

$general = Read-Normalized $generalPath
Require-Contains $general "const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';" 'modern_party_icon_route'
Require-Contains $general 'd.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined' 'modern_party_icon_activation'

$dependencies = Read-Normalized $dependenciesPath
Require-Regex $dependencies '(?s)const DEPENDENCIES_VANILLA = \{.*?"boot"\s*:\s*\[.*?"id"\s*:\s*"party"' 'modern_party_boot_dependency'

$xtHandler = Read-Normalized $xtHandlerPath
foreach ($alias in @('halloween#partycookie','halloween#msgviewed','halloween#qcmsgviewed','halloween#qtaskcomplete','halloween#qtupdate')) {
  Require-Contains $xtHandler $alias ("native_alias_" + ($alias -replace '[^A-Za-z0-9]+','_'))
}
Require-Contains $xtHandler 'const canonicalizeXtAction' 'native_namespace_canonicalizer'

$protocol = Read-Normalized $protocolPath
Require-Contains $protocol "action: 's%party#partycookie'" 'party_cookie_selector_compatibility'
Require-Contains $protocol "exactArguments: ['0']" 'party_cookie_fixed_selector'
Require-Contains $protocol "'s%nx#bimp'" 'map_impression_telemetry_ack'
Require-Contains $protocol "action: 's%musictrack#broadcastingmusictracks'" 'soundstudio_broadcast_query'
Require-Contains $protocol "responseArgs: [0, -1, '']" 'soundstudio_empty_playlist_response'

$joinHandlers = Read-Normalized $joinHandlersPath
Require-Contains $joinHandlers "import { sendModernPartyBootstrap } from './party';" 'join_party_bootstrap_import'
Require-Contains $joinHandlers 'if (data.getPartyProgress() !== null)' 'join_party_bootstrap_guard'
Require-Contains $joinHandlers 'await sendModernPartyBootstrap(ctx);' 'join_party_bootstrap_call'

$partyHandlers = Read-Normalized $partyHandlersPath
foreach ($needle in @('activefeatures','partycookie','partyservice','modern-party-bootstrap','partycookie-partyservice')) {
  Require-Contains $partyHandlers $needle ("party_handler_" + $needle)
}
$partyData = Read-Normalized $partyDataPath
Require-Contains $partyData "'halloween-2015':" 'party_service_archive_fallback'

if (-not (Test-Path -LiteralPath $historicalManifestPath -PathType Leaf)) { throw "WADDLE_PARTY2015_SOURCE=FAIL historical_manifest_missing=$historicalManifestPath" }
$historicalManifest = Get-Content -LiteralPath $historicalManifestPath -Raw | ConvertFrom-Json
$historicalAssets = @($historicalManifest.assets)
if ([int]$historicalManifest.requiredCount -ne 132 -or $historicalAssets.Count -ne 132) {
  throw "WADDLE_PARTY2015_SOURCE=FAIL historical_count manifest=$($historicalManifest.requiredCount) assets=$($historicalAssets.Count) expected=132"
}
$historicalTargets = @($historicalAssets | ForEach-Object { [string]$_.relativePath })
foreach ($required in @('client/ClientInterface-HalloweenParty2015.swf','close_ups/Close_upsQuest_interface-HalloweenParty2015.swf','content/ContentFeatures-HalloweenParty2015.swf','content/ContentParty_icon-HalloweenParty2015.swf','close_ups/Hallo15_dialogue_login.swf')) {
  if (-not ($historicalTargets -contains $required)) { throw "WADDLE_PARTY2015_SOURCE=FAIL historical_runtime_missing=$required" }
  $path = Join-Path $partyRoot ($required.Replace('/','\'))
  if (-not (Test-Swf $path)) { throw "WADDLE_PARTY2015_SOURCE=FAIL historical_runtime_invalid=$required" }
}

# Canonical supplements are retained for provenance/other compatibility work.
# Validate anything already materialized byte-for-byte, but never treat those
# files as proof that the October 2015 live runtime is coherent.
$canonicalManifest = Get-Content -LiteralPath $canonicalManifestPath -Raw | ConvertFrom-Json
if ($canonicalManifest.schema -ne 'waddle-canonical-assets/v1') { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_schema=$($canonicalManifest.schema)" }
$canonicalAssets = @($canonicalManifest.assets)
$presentCanonical = 0
foreach ($entry in $canonicalAssets) {
  $path = Join-Path $partyRoot (([string]$entry.target).Replace('/','\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
  $presentCanonical++
  if ([long](Get-Item -LiteralPath $path).Length -ne [long]$entry.bytes) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_bytes target=$($entry.target)" }
  if ((Get-GitBlobSha $path) -ne ([string]$entry.gitBlobSha).ToLowerInvariant()) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_blob target=$($entry.target)" }
  if ([string]$entry.kind -eq 'swf' -and -not (Test-Swf $path)) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_swf target=$($entry.target)" }
}

$updates = Read-Normalized $updatesPath
Require-Contains $updates 'import { UPDATES_2015 } from "./2015";' 'updates_2015_import'
Require-Contains $updates '...UPDATES_2015' 'updates_2015_registration'

Write-Host "WADDLE_PARTY2015_SOURCE=PASS runtime=exact-cparchives-2015 generic_party=svanilla temporal_room_metadata=true historical_swfs=132 canonical_provenance=$($canonicalAssets.Count) canonical_present=$presentCanonical party_map=base-runtime game_configs=base-runtime client_interface=historical-2015 quest_interface=historical-2015 hallo_login=historical-2015 dialogues=historical-2015 music=historical-2015 native_namespace=true activefeatures=20150501 partyservice=true mutation=false"
