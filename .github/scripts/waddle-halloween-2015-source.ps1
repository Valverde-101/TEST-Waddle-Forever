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
$worldHandlersPath = Join-Path $repo 'src/server/socket-server/world-handlers.ts'
$partyHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$partyDataPath = Join-Path $repo 'src/server/game-data/party.ts'
$timelinePath = Join-Path $repo 'src/client/views/timeline/timeline-static.ts'
$htmlPath = Join-Path $repo 'src/client/views/timeline/timeline.html'
$runtimePath = Join-Path $repo 'media/default/archives/PartyRuntime-CPImagined-HalloweenClassic.swf'

$files = Read-Normalized $filesPath
Require-Contains $files "const PARTY2015 = 'party2015';" 'party2015_file_ref_constant'
Require-Regex $files '(?m)^\s*PARTY2015,\s*$' 'party2015_file_ref_registration'
Require-Contains $files "'archives'" 'archives_fileref_registration'

$rooms = Read-Normalized $roomsPath
$roomContracts = [ordered]@{
  dojosnow = 326
  hotellobby = 430
  hotelspa = 431
  hotelroof = 432
  cloudforest = 433
  skatepark = 435
  pufflewild = 436
  pufflepark = 890
}
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
  "'close_ups/quest_interface.swf'",
  "'w.p2015.may.partyinterface'",
  "'w.p2015.may.login'",
  "'halloHerbertGame'",
  "'play/v2/client/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/party.swf': 'archives:PartyRuntime-CPImagined-HalloweenClassic.swf'",
  "'play/v2/content/global/content/features.swf'",
  "'play/v2/content/global/content/party_icon.swf': P + 'content/ContentParty_icon-HalloweenParty2015.swf'",
  "'play/v2/content/global/logo/logo.swf'",
  "'content/party_icon.swf': [P + 'content/ContentParty_icon-HalloweenParty2015.swf', 'party_icon', 'scavenger_hunt_icon']",
  "'play/v2/content/global/avatar/sprites/penguin_robot.swf'"
)) {
  Require-Contains $party $contract ("party_" + ($contract -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
Require-NotContains $party "'play/v2/content/global/content/logo.swf'" 'legacy_wrong_logo_route'
Require-NotContains $party "PartyRuntime-CPImaginedReference.swf" 'runtime_inside_hydrated_party_inventory'

if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_SOURCE=FAIL runtime_missing=$runtimePath"
}
$runtimeInfo = Get-Item -LiteralPath $runtimePath
if ($runtimeInfo.Length -lt 100000) {
  throw "WADDLE_PARTY2015_SOURCE=FAIL runtime_too_small bytes=$($runtimeInfo.Length)"
}
$stream = [IO.File]::OpenRead($runtimePath)
try {
  $signature = New-Object byte[] 3
  if ($stream.Read($signature,0,3) -ne 3) { throw 'WADDLE_PARTY2015_SOURCE=FAIL runtime_header_short' }
  $runtimeSig = [Text.Encoding]::ASCII.GetString($signature)
  if (@('FWS','CWS','ZWS') -notcontains $runtimeSig) { throw "WADDLE_PARTY2015_SOURCE=FAIL runtime_signature=$runtimeSig" }
} finally {
  $stream.Dispose()
}

$general = Read-Normalized $generalPath
Require-Contains $general "const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';" 'modern_party_icon_route'
Require-Contains $general 'd.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined' 'modern_party_icon_activation'
Require-Contains $general '"party_icon_active": modernPartyIconActive' 'modern_party_option_activation'

$fileGenerators = Read-Normalized $fileGeneratorsPath
Require-Contains $fileGenerators 'const getRuntimePathsJson: FileGenerator' 'runtime_paths_generator'
Require-Contains $fileGenerators '...Object.fromEntries(d.getGlobalPaths())' 'global_paths_merge'
Require-Contains $fileGenerators "'play/en/web_service/game_configs/paths.json': getRuntimePathsJson" 'runtime_paths_registration'

$dependencies = Read-Normalized $dependenciesPath
Require-Regex $dependencies '(?s)const DEPENDENCIES_VANILLA = \{.*?"boot"\s*:\s*\[.*?"id"\s*:\s*"party"' 'modern_party_boot_dependency'

$xtHandler = Read-Normalized $xtHandlerPath
Require-Contains $xtHandler 'resolveXtActionAlias' 'xt_party_alias_resolver'
Require-Contains $xtHandler "const emptyArrayFraming = Array.isArray(signature) && signature.length === 0 && args.length === 1 && args[0] === '';" 'xt_empty_array_frame_detection'
Require-Contains $xtHandler 'const argsForParsing = emptyArrayFraming ? [] : args;' 'xt_empty_array_frame_normalization'
Require-Contains $xtHandler "? 'protocol-alias'" 'xt_party_alias_diagnostic'
Require-Contains $xtHandler 'compatibility: actionAlias !== undefined || compatibility !== undefined || emptyArrayFraming' 'xt_alias_completion_diagnostic'

$protocol = Read-Normalized $protocolPath
foreach ($alias in @(
  "action: 's%fair#fair'",
  "canonicalAction: 's%party#partycookie'",
  "action: 's%fair#partycookie'",
  "action: 's%fair#msgviewed'",
  "action: 's%fair#fmsgviewed'",
  "action: 's%fair#qcmsgviewed'",
  "action: 's%fair#qtaskcomplete'"
)) {
  Require-Contains $protocol $alias ("protocol_" + ($alias -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
Require-Contains $protocol "exactArguments: ['0']" 'protocol_fair_cookie_fixed_selector'
Require-Contains $protocol 'dropArguments: true' 'protocol_fair_cookie_selector_drop'

$joinHandlers = Read-Normalized $joinHandlersPath
Require-Contains $joinHandlers "import { sendModernPartyBootstrap } from './party';" 'join_party_bootstrap_import'
Require-Contains $joinHandlers 'if (data.getPartyProgress() !== null)' 'join_party_bootstrap_guard'
Require-Contains $joinHandlers 'await sendModernPartyBootstrap(ctx);' 'join_party_bootstrap_call'

$worldHandlers = Read-Normalized $worldHandlersPath
Require-Regex $worldHandlers "p\.xt\('s',\s*'party#partycookie',\s*\[\],\s*handleRetrievePartyCookie\)" 'party_cookie_zero_arg_contract'
Require-NotContains $worldHandlers "'party#partycookie', ['number']" 'party_cookie_fake_numeric_arg'

$partyHandlers = Read-Normalized $partyHandlersPath
Require-Contains $partyHandlers "await ctx.msg.send(ctx.penguin, 'activefeatures'" 'party_activefeatures_bootstrap'
Require-Contains $partyHandlers "await ctx.msg.send(ctx.penguin, 'partycookie'" 'party_cookie_response_contract'
Require-Contains $partyHandlers "await msg.send(penguin, 'partyservice'" 'party_service_response_contract'
Require-Contains $partyHandlers "await ctx.msg.send(ctx.penguin, 'activefeatures', activeFeatures ?? '');`n  await sendCurrentPartyCookie(ctx);`n  await sendCurrentPartyService(ctx);" 'party_full_bootstrap_order'
Require-Contains $partyHandlers "action: 'modern-party-bootstrap'" 'party_full_bootstrap_trace'
Require-Contains $partyHandlers "action: 'partycookie-partyservice'" 'party_cookie_fallback_trace'

$partyData = Read-Normalized $partyDataPath
Require-Contains $partyData 'export type PartyServiceConfig' 'party_service_type'
Require-Contains $partyData "'halloween-2015':" 'party_service_archive_fallback'
Require-Contains $partyData "partyStartDate: '2015-10-21 00:00:00'" 'party_service_start'
Require-Contains $partyData "partyEndDate: '2015-11-05 00:00:00'" 'party_service_end'

$updates = Read-Normalized $updatesPath
Require-Contains $updates 'import { UPDATES_2015 } from "./2015";' 'updates_2015_import'
Require-Contains $updates '...UPDATES_2015' 'updates_2015_registration'

$timeline = Read-Normalized $timelinePath
if ($timeline -match 'new Date\(2013\s*,\s*0\s*,\s*1\)') {
  throw 'WADDLE_PARTY2015_SOURCE=FAIL legacy_timeline_cutoff=2013'
}
Require-Contains $timeline 'function syncYearOptions(days: DateInfo[])' 'timeline_year_sync'
Require-Contains $timeline 'const lastSelectableYear = Math.max' 'timeline_selectable_horizon'

$html = Read-Normalized $htmlPath
foreach ($year in 2013..2017) {
  Require-Regex $html ('<option(?:\s+value="{0}")?>{0}</option>' -f $year) ("timeline_year_{0}" -f $year)
}

Write-Host "WADDLE_PARTY2015_SOURCE=PASS mode=validate_committed_source media_prefix=party2015 runtime=archives client_interface=party2015 modern_party_id=20150501 party_start=2015-10-21 exclusive_end=2015-11-05 paths_global_merged=true eager_bootstrap=true fair_aliases=true runtime_sig=$runtimeSig years=2005-2017 mutation=false"
