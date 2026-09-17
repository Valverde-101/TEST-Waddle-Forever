[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$updatesPath=Join-Path $repo 'src/server/updates/2015.ts'
$roomsSourcePath=Join-Path $repo 'src/server/game-data/rooms.ts'
$roomsConfigPath=Join-Path $repo 'media/default/party2015/game_configs/rooms.json'
$generatorsPath=Join-Path $repo 'src/server/file-generators/index.ts'
foreach($path in @($updatesPath,$roomsSourcePath,$roomsConfigPath,$generatorsPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL missing=$path"}}
$updates=([IO.File]::ReadAllText($updatesPath)-replace "`r`n","`n")
$roomsSource=([IO.File]::ReadAllText($roomsSourcePath)-replace "`r`n","`n")
$generators=([IO.File]::ReadAllText($generatorsPath)-replace "`r`n","`n")
$roomsConfig=Get-Content -LiteralPath $roomsConfigPath -Raw|ConvertFrom-Json
$configRooms=@($roomsConfig.PSObject.Properties|ForEach-Object{$_.Value})

$decorated=[ordered]@{
  beach='beach';beacon='beacon';book='book';cave='cave';shop='shop';cloudforest='cloudforest';coffee='coffee';cove='cove';dance='dance';dock='dock';
  dojo='dojo';dojoext='dojoext';agentlobbymulti='agentlobbymulti';dojofire='dojofire';forest='forest';party1='party1';party2='party2';berg='berg';light='light';attic='attic';
  lounge='lounge';shack='shack';pet='pet';pizza='pizza';plaza='plaza';stage='mall';hotellobby='hotellobby';hotelroof='hotelroof';hotelspa='hotelspa';pufflepark='park';
  pufflewild='pufflewild';eco='school';skatepark='skatepark';mtn='mtn';lodge='lodge';village='village';dojosnow='dojosnow';forts='forts';rink='rink';town='town'
}
if($decorated.Count-ne40){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL decorated_contract_count=$($decorated.Count) expected=40"}
$ids=@{}
foreach($entry in $decorated.GetEnumerator()){
  $waddleKey=[string]$entry.Key;$preservedKey=[string]$entry.Value
  $roomMatches=@($configRooms|Where-Object{[string]$_.room_key-ceq$preservedKey});if($roomMatches.Count-ne1){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL preserved_room key=$preservedKey matches=$($roomMatches.Count)"}
  $preservedId=[int]$roomMatches[0].room_id
  $sourceMatch=[regex]::Match($roomsSource,"(?s)'$([regex]::Escape($waddleKey))'\s*:\s*\{.*?\bid\s*:\s*(\d+)");if(-not$sourceMatch.Success){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL waddle_room_missing=$waddleKey"}
  $waddleId=[int]$sourceMatch.Groups[1].Value;if($waddleId-ne$preservedId){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL id_mismatch waddle=$waddleKey preserved=$preservedKey waddle_id=$waddleId preserved_id=$preservedId"}
  if($ids.ContainsKey($waddleId)){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL duplicate_decorated_id id=$waddleId"};$ids[$waddleId]=$waddleKey
  if($waddleKey-eq'town'){$asset='rooms/RoomsTown-HalloweenParty2015.swf'}elseif($waddleKey-eq'stage'){$asset='rooms/Hallo15_mall.swf'}elseif($waddleKey-eq'pufflepark'){$asset='rooms/Hallo15_park.swf'}elseif($waddleKey-eq'eco'){$asset='rooms/Hallo15_school.swf'}else{$asset="rooms/Hallo15_$waddleKey.swf"}
  $routePattern='["'']'+[regex]::Escape($waddleKey)+'["'']\s*:\s*ref\(\s*["'']'+[regex]::Escape($asset)+'["'']\s*\)'
  if($updates-notmatch$routePattern){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL decorated_route_missing=$waddleKey"}
}

# partysolo1 is a real Halloween-only room and must not be put into Waddle's
# global static room list. The preserved config proves room_id=891; the runtime
# rooms generator mounts that metadata only while its exact SWF route is active.
$solo=@($configRooms|Where-Object{[string]$_.room_key-ceq'partysolo1'});if($solo.Count-ne1){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL solo_preserved_matches=$($solo.Count)"}
if([int]$solo[0].room_id-ne891){throw "WADDLE_HALLOWEEN2015_ROOMS=FAIL solo_preserved_id=$($solo[0].room_id) expected=891"}
if($updates-notmatch"'play/v2/content/global/rooms/partysolo1\.swf'\s*:\s*ref\('rooms/Hallo15_partysolo1\.swf'\)"){throw 'WADDLE_HALLOWEEN2015_ROOMS=FAIL solo_swf_route_missing'}
if($generators-notmatch"rooms\['891'\]\s*=\s*\{"){throw 'WADDLE_HALLOWEEN2015_ROOMS=FAIL solo_runtime_metadata_missing'}
if($generators-notmatch"room_key\s*:\s*'partysolo1'"){throw 'WADDLE_HALLOWEEN2015_ROOMS=FAIL solo_runtime_key_missing'}
if($generators-notmatch"d\.lookupFile\(HALLOWEEN_2015_SOLO_ROOM_ROUTE\)\s*!==\s*undefined"){throw 'WADDLE_HALLOWEEN2015_ROOMS=FAIL solo_temporal_guard_missing'}

Write-Host "WADDLE_HALLOWEEN2015_ROOMS=PASS decorated=$($decorated.Count) ids_unique=$($ids.Count) solo_room=891 solo_temporal=true aliases=stage->mall,eco->school,pufflepark->park source=preserved_rooms_json"
