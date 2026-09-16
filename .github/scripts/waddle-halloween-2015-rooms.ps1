[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$roomsSourcePath = Join-Path $repo 'src/server/game-data/rooms.ts'
$roomsConfigPath = Join-Path $repo 'media/default/party2015/game_configs/rooms.json'

foreach ($path in @($updatesPath,$roomsSourcePath,$roomsConfigPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL missing=$path"
  }
}

$updates = ([IO.File]::ReadAllText($updatesPath) -replace "`r`n", "`n")
$roomsSource = ([IO.File]::ReadAllText($roomsSourcePath) -replace "`r`n", "`n")
$roomsConfig = Get-Content -LiteralPath $roomsConfigPath -Raw | ConvertFrom-Json
$configRooms = @($roomsConfig.PSObject.Properties | ForEach-Object { $_.Value })

# Every decorated room in the 2015 update. The value is the preserved room_key.
# Waddle keeps stable semantic names even where the late-AS3 crumbs use a newer
# literal key: stage->mall, eco->school and pufflepark->park. IDs must still match.
$decorated = [ordered]@{
  beach='beach'; beacon='beacon'; book='book'; cave='cave'; shop='shop';
  cloudforest='cloudforest'; coffee='coffee'; cove='cove'; dance='dance'; dock='dock';
  dojo='dojo'; dojoext='dojoext'; agentlobbymulti='agentlobbymulti'; dojofire='dojofire';
  forest='forest'; party1='party1'; party2='party2'; berg='berg'; light='light'; attic='attic';
  lounge='lounge'; shack='shack'; pet='pet'; pizza='pizza'; plaza='plaza'; stage='mall';
  hotellobby='hotellobby'; hotelroof='hotelroof'; hotelspa='hotelspa'; pufflepark='park';
  pufflewild='pufflewild'; eco='school'; skatepark='skatepark'; mtn='mtn'; lodge='lodge';
  village='village'; dojosnow='dojosnow'; forts='forts'; rink='rink'; town='town'
}

if ($decorated.Count -ne 40) {
  throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL decorated_contract_count=$($decorated.Count) expected=40"
}

$ids = @{}
foreach ($entry in $decorated.GetEnumerator()) {
  $waddleKey = [string]$entry.Key
  $preservedKey = [string]$entry.Value

  $roomMatches = @($configRooms | Where-Object { [string]$_.room_key -ceq $preservedKey })
  if ($roomMatches.Count -ne 1) {
    throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL preserved_room key=$preservedKey matches=$($roomMatches.Count)"
  }
  $preservedId = [int]$roomMatches[0].room_id

  $roomPattern = "(?s)'$([regex]::Escape($waddleKey))'\s*:\s*\{.*?\bid\s*:\s*(\d+)"
  $sourceMatch = [regex]::Match($roomsSource, $roomPattern)
  if (-not $sourceMatch.Success) {
    throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL waddle_room_missing=$waddleKey"
  }
  $waddleId = [int]$sourceMatch.Groups[1].Value
  if ($waddleId -ne $preservedId) {
    throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL id_mismatch waddle=$waddleKey preserved=$preservedKey waddle_id=$waddleId preserved_id=$preservedId"
  }
  if ($ids.ContainsKey($waddleId)) {
    throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL duplicate_decorated_id id=$waddleId first=$($ids[$waddleId]) second=$waddleKey"
  }
  $ids[$waddleId] = $waddleKey

  $updatePattern = "(?m)^\s*$([regex]::Escape($waddleKey))\s*:\s*P\s*\+\s*'rooms/[^']+\.swf',?\s*$"
  if ($updates -notmatch $updatePattern) {
    throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL decorated_route_missing=$waddleKey"
  }
}

Write-Host "WADDLE_HALLOWEEN2015_ROOMS=PASS decorated=$($decorated.Count) ids_unique=$($ids.Count) aliases=stage->mall,eco->school,pufflepark->park source=preserved_rooms_json"
