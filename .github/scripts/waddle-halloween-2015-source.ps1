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
  if (-not $Text.Contains($Needle)) {
    throw "WADDLE_PARTY2015_SOURCE=FAIL missing_contract=$Label"
  }
}

function Require-NotContains([string]$Text,[string]$Needle,[string]$Label) {
  if ($Text.Contains($Needle)) {
    throw "WADDLE_PARTY2015_SOURCE=FAIL stale_contract=$Label"
  }
}

function Require-Regex([string]$Text,[string]$Pattern,[string]$Label) {
  if ($Text -notmatch $Pattern) {
    throw "WADDLE_PARTY2015_SOURCE=FAIL missing_contract=$Label"
  }
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

function Test-ZipConfig([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 4) { return $false }
    $header = New-Object byte[] 4
    if ($stream.Read($header,0,4) -ne 4) { return $false }
    return $header[0] -eq 0x50 -and $header[1] -eq 0x4B -and $header[2] -eq 0x03 -and $header[3] -eq 0x04
  } finally { $stream.Dispose() }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$filesPath = Join-Path $repo 'src/server/game-data/files.ts'
$roomsPath = Join-Path $repo 'src/server/game-data/rooms.ts'
$partyPath = Join-Path $repo 'src/server/updates/2015.ts'
$updatesPath = Join-Path $repo 'src/server/updates/updates.ts'
$generalPath = Join-Path $repo 'src/server/file-generators/general.json.ts'
$fileGeneratorsPath = Join-Path $repo 'src/server/file-generators/index.ts'
$dependenciesPath = Join-Path $repo 'src/server/file-generators/dependencies.json.ts'
$xtHandlerPath = Join-Path $repo 'src/server/socket-server/xt-handler.ts'
$protocolPath = Join-Path $repo 'src/server/socket-server/handlers/protocol.ts'
$joinHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/join.ts'
$partyHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$partyDataPath = Join-Path $repo 'src/server/game-data/party.ts'
$timelinePath = Join-Path $repo 'src/client/views/timeline/timeline-static.ts'
$htmlPath = Join-Path $repo 'src/client/views/timeline/timeline.html'
$canonicalManifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
$partyRoot = Join-Path $repo 'media/default/party2015'

$files = Read-Normalized $filesPath
Require-Contains $files "const PARTY2015 = 'party2015';" 'party2015_file_ref_constant'
Require-Regex $files '(?m)^\s*PARTY2015,\s*$' 'party2015_file_ref_registration'

$rooms = Read-Normalized $roomsPath
$roomContracts = [ordered]@{ dojosnow=326; hotellobby=430; hotelspa=431; hotelroof=432; cloudforest=433; skatepark=435; pufflewild=436; pufflepark=890 }
foreach ($entry in $roomContracts.GetEnumerator()) {
  $escaped = [regex]::Escape([string]$entry.Key)
  Require-Regex $rooms ("(?s)'{0}'\s*:\s*\{{.*?\bid\s*:\s*{1}\b" -f $escaped,[int]$entry.Value) ("room_{0}_{1}" -f $entry.Key,$entry.Value)
}

$party = Read-Normalized $partyPath
foreach ($contract in @(
  "const P = 'party2015:';",
  "date: '2015-10-21'",
  "partyName: 'Halloween Party 2015'",
  "activeFeatures: '20150501'",
  "id: 'halloween-2015'",
  'messageCount: 10',
  'communicatorMessageCount: 5',
  'taskCount: 10',
  'maxCoinUpdate: 10',
  "partyStartDate: '2015-10-21 00:00:00'",
  "partyEndDate: '2015-11-05 00:00:00'",
  'unlockDayIndex: 16',
  'numOfDaysInParty: 16',
  "date: '2015-11-05'",
  "end: ['party']",
  "'play/en/web_service/game_configs.bin': P + 'game_configs/game_configs.bin'",
  "'play/v2/client/QuestCommunicator.swf': P + 'client/QuestCommunicator.swf'",
  "'play/v2/content/global/content/party.swf': P + 'content/party.swf'",
  "'play/v2/content/global/content/map.swf': P + 'content/map.swf'",
  "'play/v2/client/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/features.swf'",
  "'play/v2/content/global/content/party_icon.swf': P + 'content/ContentParty_icon-HalloweenParty2015.swf'",
  "'play/v2/content/global/logo/logo.swf'",
  "'content/map.swf': [P + 'content/map.swf', 'w.p2015.may.partymap']",
  "'content/party_icon.swf': [P + 'content/ContentParty_icon-HalloweenParty2015.swf', 'party_icon', 'scavenger_hunt_icon']",
  "'close_ups/quest_interface.swf'",
  "'w.p2015.may.partyinterface'",
  "'w.p2015.may.login'",
  "'halloHerbertGame'"
)) {
  Require-Contains $party $contract ("party_" + ($contract -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
Require-NotContains $party "'play/v2/content/global/content/logo.swf'" 'legacy_wrong_logo_route'
Require-NotContains $party 'PartyRuntime-CPImagined-HalloweenClassic.swf' 'obsolete_runtime_alias'

$general = Read-Normalized $generalPath
Require-Contains $general "const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';" 'modern_party_icon_route'
Require-Contains $general 'd.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined' 'modern_party_icon_activation'
Require-Contains $general '"hunt_active": hunt !== null || fair || d.getPartyIcon() || modernPartyIconActive' 'modern_hunt_activation'
Require-Contains $general '"party_icon_active": modernPartyIconActive' 'modern_party_option_activation'

$fileGenerators = Read-Normalized $fileGeneratorsPath
Require-Contains $fileGenerators 'const getRuntimePathsJson: FileGenerator' 'runtime_paths_generator'
Require-Contains $fileGenerators '...Object.fromEntries(d.getGlobalPaths())' 'global_paths_merge'
Require-Contains $fileGenerators "'play/en/web_service/game_configs/paths.json': getRuntimePathsJson" 'runtime_paths_registration'

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

$joinHandlers = Read-Normalized $joinHandlersPath
Require-Contains $joinHandlers "import { sendModernPartyBootstrap } from './party';" 'join_party_bootstrap_import'
Require-Contains $joinHandlers 'if (data.getPartyProgress() !== null)' 'join_party_bootstrap_guard'
Require-Contains $joinHandlers 'await sendModernPartyBootstrap(ctx);' 'join_party_bootstrap_call'

$partyHandlers = Read-Normalized $partyHandlersPath
Require-Contains $partyHandlers "await ctx.msg.send(ctx.penguin, 'activefeatures'" 'party_activefeatures_bootstrap'
Require-Contains $partyHandlers "await ctx.msg.send(ctx.penguin, 'partycookie'" 'party_cookie_response_contract'
Require-Contains $partyHandlers "await msg.send(penguin, 'partyservice'" 'party_service_response_contract'
Require-Contains $partyHandlers "action: 'modern-party-bootstrap'" 'party_full_bootstrap_trace'
Require-Contains $partyHandlers "action: 'partycookie-partyservice'" 'party_cookie_fallback_trace'

$partyData = Read-Normalized $partyDataPath
Require-Contains $partyData 'export type PartyServiceConfig' 'party_service_type'
Require-Contains $partyData "'halloween-2015':" 'party_service_archive_fallback'

$canonicalManifest = Get-Content -LiteralPath $canonicalManifestPath -Raw | ConvertFrom-Json
if ($canonicalManifest.schema -ne 'waddle-canonical-assets/v1') { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_schema=$($canonicalManifest.schema)" }
if (@($canonicalManifest.assets).Count -ne 11) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_assets=$(@($canonicalManifest.assets).Count) expected=11" }
$requiredCanonicalTargets = @(
  'content/party.swf','content/map.swf','client/QuestCommunicator.swf','game_configs/game_configs.bin',
  'game_configs/game_strings.json','game_configs/general.json','game_configs/paths.json','game_configs/rooms.json'
)
foreach ($target in $requiredCanonicalTargets) {
  if (-not (@($canonicalManifest.assets | ForEach-Object { [string]$_.target }) -contains $target)) {
    throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_target_missing=$target"
  }
}

# Hosted source validation runs before the self-hosted canonical hydrator on a new
# integration. Validate any already-committed supplements byte-for-byte, while the
# hydrate/publish job is responsible for materializing missing ones into Git.
$presentCanonical = 0
foreach ($entry in @($canonicalManifest.assets)) {
  $path = Join-Path $partyRoot (([string]$entry.target).Replace('/','\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
  $presentCanonical++
  $item = Get-Item -LiteralPath $path
  if ([long]$item.Length -ne [long]$entry.bytes) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_bytes target=$($entry.target)" }
  if ((Get-GitBlobSha $path) -ne ([string]$entry.gitBlobSha).ToLowerInvariant()) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_blob target=$($entry.target)" }
  if ([string]$entry.kind -eq 'swf' -and -not (Test-Swf $path)) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_swf target=$($entry.target)" }
  if ([string]$entry.kind -eq 'zip-config' -and -not (Test-ZipConfig $path)) { throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_zip target=$($entry.target)" }
}

$updates = Read-Normalized $updatesPath
Require-Contains $updates 'import { UPDATES_2015 } from "./2015";' 'updates_2015_import'
Require-Contains $updates '...UPDATES_2015' 'updates_2015_registration'

$timeline = Read-Normalized $timelinePath
Require-Contains $timeline 'function syncYearOptions(days: DateInfo[])' 'timeline_year_sync'
Require-Contains $timeline 'const lastSelectableYear = Math.max' 'timeline_selectable_horizon'
$html = Read-Normalized $htmlPath
foreach ($year in 2013..2017) { Require-Regex $html ('<option(?:\s+value="{0}")?>{0}</option>' -f $year) ("timeline_year_{0}" -f $year) }

Write-Host "WADDLE_PARTY2015_SOURCE=PASS mode=validate_committed_source runtime=preserved-halloween canonical_manifest=11 canonical_present=$presentCanonical config_bundle=true quest_communicator=true map_2015=true native_namespace=true bimp_telemetry=true activefeatures=20150501 partyservice=true client_interface=party2015 exclusive_end=2015-11-05 years=2005-2017 mutation=false"
