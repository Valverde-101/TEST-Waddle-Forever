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
  "'play/v2/client/interface.swf'",
  "'play/v2/content/global/content/features.swf'",
  "'play/v2/content/global/avatar/sprites/penguin_robot.swf'"
)) {
  Require-Contains $party $contract ("party_" + ($contract -replace '[^A-Za-z0-9]+','_').Trim('_'))
}

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

Write-Host "WADDLE_PARTY2015_SOURCE=PASS mode=validate_committed_source media_prefix=party2015 years=2005-2017 modern_room_ids=326,430,431,432,433,435,436,890 party_start=2015-10-21 party_end=2015-11-04 mutation=false"
