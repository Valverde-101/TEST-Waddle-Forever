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
$dependenciesPath = Join-Path $repo 'src/server/file-generators/dependencies.json.ts'
$xtHandlerPath = Join-Path $repo 'src/server/socket-server/xt-handler.ts'
$worldHandlersPath = Join-Path $repo 'src/server/socket-server/world-handlers.ts'
$timelinePath = Join-Path $repo 'src/client/views/timeline/timeline-static.ts'
$htmlPath = Join-Path $repo 'src/client/views/timeline/timeline.html'

$files = Read-Normalized $filesPath
Require-Contains $files "const PARTY2015 = 'party2015';" 'party2015_file_ref_constant'
Require-Regex $files '(?m)^\s*PARTY2015,\s*$' 'party2015_file_ref_registration'

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
  "id: 'halloween-2015'",
  'messageCount: 10',
  'communicatorMessageCount: 5',
  'taskCount: 10',
  'maxCoinUpdate: 10',
  "date: '2015-11-04'",
  "end: ['party']",
  "'close_ups/quest_interface.swf'",
  "'close_ups/tiles_minigame8.swf'",
  "'play/v2/content/global/content/interface.swf'",
  "'play/v2/content/global/content/party.swf': 'svanilla:media/play/v2/content/global/content/party.swf'",
  "'play/v2/content/global/content/features.swf'",
  "'play/v2/content/global/logo/logo.swf'",
  "'play/v2/content/global/content/party_icon.swf'",
  "'play/v2/content/global/avatar/sprites/penguin_robot.swf'"
)) {
  Require-Contains $party $contract ("party_" + ($contract -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
Require-NotContains $party "'play/v2/client/interface.swf'" 'legacy_wrong_interface_route'
Require-NotContains $party "'play/v2/content/global/content/logo.swf'" 'legacy_wrong_logo_route'

$general = Read-Normalized $generalPath
Require-Contains $general "const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';" 'modern_party_icon_route'
Require-Contains $general 'd.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined' 'modern_party_icon_activation'
Require-Contains $general '"party_icon_active": modernPartyIconActive' 'modern_party_option_activation'

$dependencies = Read-Normalized $dependenciesPath
Require-Regex $dependencies '(?s)const DEPENDENCIES_VANILLA = \{.*?"boot"\s*:\s*\[.*?"id"\s*:\s*"party"' 'modern_party_boot_dependency'

# Modern ServerCookieService calls Airtower with [] for cookie retrieval. Airtower
# serializes that as a trailing empty XT payload field (..%room%%). Waddle must
# normalize that transport representation only for callbacks that explicitly
# declare a zero-argument signature. Otherwise party initialization stops before
# the cookie can drive login state / party-icon visibility.
$xtHandler = Read-Normalized $xtHandlerPath
Require-Contains $xtHandler "const emptyArrayFraming = Array.isArray(signature) && signature.length === 0 && args.length === 1 && args[0] === '';" 'xt_empty_array_frame_detection'
Require-Contains $xtHandler 'const argsForParsing = emptyArrayFraming ? [] : args;' 'xt_empty_array_frame_normalization'
Require-Contains $xtHandler "status: emptyArrayFraming ? 'empty-array-framing'" 'xt_empty_array_frame_diagnostic'
Require-Contains $xtHandler 'compatibility: compatibility !== undefined || emptyArrayFraming' 'xt_empty_array_frame_completion'

$worldHandlers = Read-Normalized $worldHandlersPath
Require-Regex $worldHandlers "p\.xt\('s',\s*'party#partycookie',\s*\[\],\s*handleRetrievePartyCookie\)" 'party_cookie_zero_arg_contract'
Require-NotContains $worldHandlers "'party#partycookie', ['number']" 'party_cookie_fake_numeric_arg'

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

Write-Host "WADDLE_PARTY2015_SOURCE=PASS mode=validate_committed_source media_prefix=party2015 years=2005-2017 modern_room_ids=326,430,431,432,433,435,436,890 party_start=2015-10-21 party_end=2015-11-04 modern_ui_routes=canonical party_icon_activation=route_driven airtower_empty_array=normalized_zero_arg_only mutation=false"