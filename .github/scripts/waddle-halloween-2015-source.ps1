param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Read-Normalized([string]$Path) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WADDLE_PARTY2015_SOURCE=FAIL missing=$Path"}
  return ([IO.File]::ReadAllText($Path) -replace "`r`n","`n")
}
function Require-Contains([string]$Text,[string]$Needle,[string]$Label){if(-not $Text.Contains($Needle)){throw "WADDLE_PARTY2015_SOURCE=FAIL missing_contract=$Label"}}
function Require-Regex([string]$Text,[string]$Pattern,[string]$Label){if($Text -notmatch $Pattern){throw "WADDLE_PARTY2015_SOURCE=FAIL missing_contract=$Label"}}
function Require-NotContains([string]$Text,[string]$Needle,[string]$Label){if($Text.Contains($Needle)){throw "WADDLE_PARTY2015_SOURCE=FAIL stale_contract=$Label"}}
function Get-GitBlobSha([string]$Path){
  $payload=[IO.File]::ReadAllBytes($Path); $prefix=[Text.Encoding]::UTF8.GetBytes("blob $($payload.Length)`0")
  $all=New-Object byte[] ($prefix.Length+$payload.Length); [Buffer]::BlockCopy($prefix,0,$all,0,$prefix.Length); [Buffer]::BlockCopy($payload,0,$all,$prefix.Length,$payload.Length)
  $sha1=[Security.Cryptography.SHA1]::Create(); try{return (($sha1.ComputeHash($all)|ForEach-Object{$_.ToString('x2')})-join '')} finally{$sha1.Dispose()}
}
function Test-Swf([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}; $s=[IO.File]::OpenRead($Path)
  try{if($s.Length -lt 8){return $false};$b=New-Object byte[] 3;if($s.Read($b,0,3)-ne 3){return $false};return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($b)}finally{$s.Dispose()}
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path

# Parse every Halloween 2015 PowerShell gate before running expensive FFDec work.
# This catches truncated quotes/braces/regexes in validate-pr-source instead of
# letting a malformed diagnostic script fail much later in protocol-evidence.
$halloweenScripts = @(Get-ChildItem -LiteralPath (Join-Path $repo '.github\scripts') -Filter 'waddle-halloween-2015*.ps1' -File | Sort-Object FullName)
foreach ($script in $halloweenScripts) {
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors)
  if (@($parseErrors).Count -gt 0) {
    foreach ($parseError in @($parseErrors)) {
      Write-Host "WADDLE_PARTY2015_PS_PARSE_ERROR file=$($script.Name) line=$($parseError.Extent.StartLineNumber) column=$($parseError.Extent.StartColumnNumber) message=$($parseError.Message)"
    }
    throw "WADDLE_PARTY2015_SOURCE=FAIL powershell_parse_errors=$(@($parseErrors).Count) file=$($script.Name)"
  }
  Write-Host "WADDLE_PARTY2015_PS_PARSE=PASS file=$($script.Name)"
}

$partyPath=Join-Path $repo 'src/server/updates/2015.ts'
$gameDataPath=Join-Path $repo 'src/server/timelines/game-data.ts'
$filesPath=Join-Path $repo 'src/server/game-data/files.ts'
$roomsPath=Join-Path $repo 'src/server/game-data/rooms.ts'
$updatesPath=Join-Path $repo 'src/server/updates/updates.ts'
$generalPath=Join-Path $repo 'src/server/file-generators/general.json.ts'
$fileGeneratorsPath=Join-Path $repo 'src/server/file-generators/index.ts'
$dependenciesPath=Join-Path $repo 'src/server/file-generators/dependencies.json.ts'
$xtHandlerPath=Join-Path $repo 'src/server/socket-server/xt-handler.ts'
$protocolPath=Join-Path $repo 'src/server/socket-server/handlers/protocol.ts'
$joinHandlersPath=Join-Path $repo 'src/server/socket-server/handlers/join.ts'
$partyHandlersPath=Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$worldHandlersPath=Join-Path $repo 'src/server/socket-server/world-handlers.ts'
$partyDataPath=Join-Path $repo 'src/server/game-data/party.ts'
$canonicalManifestPath=Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
$runtimePatchPath=Join-Path $repo '.github/scripts/waddle-halloween-2015-runtime-patch.ps1'
$partyRoot=Join-Path $repo 'media/default/party2015'
$historicalManifestPath=Join-Path $partyRoot 'manifest.json'

$files=Read-Normalized $filesPath
Require-Contains $files "const PARTY2015 = 'party2015';" 'party2015_file_ref_constant'
Require-Regex $files '(?m)^\s*PARTY2015,\s*$' 'party2015_file_ref_registration'

$rooms=Read-Normalized $roomsPath
foreach($roomKey in @('dojosnow','hotellobby','hotelspa','hotelroof','cloudforest','pufflepark','skatepark','pufflewild')){
  Require-Regex $rooms ("(?s)'{0}'\s*:\s*\{{.*?\bid\s*:\s*\d+\b" -f [regex]::Escape($roomKey)) ("room_symbol_{0}" -f $roomKey)
}

# Validate the timeline semantically. Late-AS3 source files are intentionally
# compact, so whitespace or formatting must never decide whether integration is valid.
$gameData=Read-Normalized $gameDataPath
Require-NotContains $gameData "this.addRoute('play/v2/client/intro_to_cp.swf', 'svanilla:media/play/v2/client/world.swf');" 'intro_module_must_not_boot_world'

$party=Read-Normalized $partyPath
$partyContracts=@{
  date="date\s*:\s*'2015-10-21'";
  name="partyName\s*:\s*'Halloween Party 2015'";
  selector="activeFeatures\s*:\s*'20151101'";
  id="id\s*:\s*'halloween-2015'";
  runtime="'play/v2/content/global/content/party\.swf'\s*:\s*ref\('content/party-runtime-2015\.swf'\)";
  shell="'play/v2/client/shell\.swf'\s*:\s*'svanilla:media/play/v2/client/shell\.swf'";
  intro="'play/v2/client/intro_to_cp\.swf'\s*:\s*'svanilla:media/play/v2/client/intro_to_cp\.swf'";
  interface="'play/v2/content/global/content/interface\.swf'\s*:\s*ref\('client/ClientInterface-HalloweenParty2015\.swf'\)";
  features="'play/v2/content/global/content/features\.swf'\s*:\s*ref\('content/ContentFeatures-HalloweenParty2015\.swf'\)";
  icon="'play/v2/content/global/content/party_icon\.swf'\s*:\s*ref\('content/ContentParty_icon-HalloweenParty2015\.swf'\)";
  robotRoute="'play/v2/content/global/avatar/sprites/robot\.swf'\s*:\s*ref\('avatar/PenguinRobot\.swf'\)";
  notlsRoute="'play/v2/content/global/rooms/NOTLS-ALL-EN\.swf'\s*:\s*'svanilla:media/play/v2/content/global/rooms/NOTLS-ALL-EN\.swf'";
  robotPath="'avatar/sprites/robot\.swf'\s*:\s*\[ref\('avatar/PenguinRobot\.swf'\)\s*,\s*'robot_tf'\s*,\s*'w\.avatarSprite\.robot'\s*\]";
  quest="'close_ups/quest_interface\.swf'\s*:\s*\[ref\('close_ups/Close_upsQuest_interface-HalloweenParty2015\.swf'\).*?'w\.app\.generic\.partyinterface'";
  login="'close_ups/halloLogin\.swf'\s*:\s*\[ref\('close_ups/Hallo15_dialogue_login\.swf'\).*?'w\.app\.loginprompt'";
  end="date\s*:\s*'2015-11-05'[\s\S]*?end\s*:\s*\['party'\]"
}
foreach($entry in $partyContracts.GetEnumerator()){Require-Regex $party $entry.Value ("party_"+$entry.Key)}
foreach($taskIndex in 0..9){
  $completedPattern = 'w\.app\.generic\.questui\.description\.task' + $taskIndex + '\.completed"\s*:\s*"[^"]+"'
  Require-Regex $party $completedPattern ("quest_completed_string_"+$taskIndex)
}
foreach($needle in @('gameStringChanges:HALLOWEEN_2015_DIALOGUE_STRINGS','rooms:HALLOWEEN_2015_ROOMS','music:HALLOWEEN_2015_MUSIC','...dialogueGlobalChanges','...dialogueLocalChanges','...tileGlobalChanges','...tileLocalChanges','...musicFileChanges')){
  Require-Regex $party ([regex]::Escape($needle).Replace('\:', '\s*:\s*')) ('party_'+($needle -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
Require-NotContains $party "ref('content/party.swf')" 'mixed_2310_party_runtime'
Require-NotContains $party "ref('content/party-base-2015.swf')" 'obsolete_mayparty_runtime'
Require-NotContains $party "ref('content/map.swf')" 'unproven_recreation_map'

$fileGenerators=Read-Normalized $fileGeneratorsPath
Require-Contains $fileGenerators 'const getRuntimePathsJson: FileGenerator' 'runtime_paths_generator'
Require-Contains $fileGenerators 'Object.fromEntries(d.getGlobalPaths())' 'runtime_global_paths_merge'
Require-Contains $fileGenerators 'const getRuntimeRoomsJson: FileGenerator' 'runtime_rooms_generator'
Require-Contains $fileGenerators "const HALLOWEEN_2015_MALL_ROOM_ROUTE = 'play/v2/content/global/rooms/mall.swf';" 'halloween_mall_room_guard'
Require-Regex $fileGenerators "rooms\['340'\]\s*=\s*\{[\s\S]*?room_key\s*:\s*'mall'[\s\S]*?path\s*:\s*'mall\.swf'" 'halloween_mall_runtime_identity'
Require-Contains $fileGenerators "const HALLOWEEN_2015_SCHOOL_ROOM_ROUTE = 'play/v2/content/global/rooms/school.swf';" 'halloween_school_room_guard'
Require-Regex $fileGenerators "rooms\['122'\]\s*=\s*\{[\s\S]*?room_key\s*:\s*'school'" 'halloween_school_runtime_identity'
Require-Contains $fileGenerators "version >= '2017-01-31' && version < '2017-03-30'" 'community_pin_historical_window'
Require-Contains $fileGenerators "'play/en/web_service/game_configs/rooms.json': getRuntimeRoomsJson" 'runtime_rooms_registration'

$general=Read-Normalized $generalPath
Require-Contains $general "const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';" 'modern_party_icon_route'
Require-Contains $general 'd.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined' 'modern_party_icon_activation'
Require-Regex $general '(?s)HALLOWEEN_2015_PARTY_ID.*?"isMapNoteActive"\s*:\s*false' 'halloween2015_map_note_disabled_without_asset'

$dependencies=Read-Normalized $dependenciesPath
Require-Regex $dependencies '(?s)const DEPENDENCIES_VANILLA = \{.*?"boot"\s*:\s*\[.*?"id"\s*:\s*"party"' 'modern_party_boot_dependency'

$xt=Read-Normalized $xtHandlerPath
foreach($alias in @('halloween#partycookie','halloween#msgviewed','halloween#qcmsgviewed','halloween#qtaskcomplete','halloween#qtupdate','party#transform','party#undefined')){Require-Contains $xt $alias ('xt_alias_'+$alias)}
Require-Contains $xt "['s%party#transform', 's%pt#spts']" 'templated_transform_alias'
Require-Contains $xt "['s%party#undefined', 's%pt#spts']" 'templated_transform_undefined_fallback'
Require-Contains $xt 'TRACE_PAYLOAD_ACTIONS' 'late_as3_payload_trace_set'
Require-Contains $xt 'payloadPreview' 'late_as3_payload_trace_preview'

$protocol=Read-Normalized $protocolPath
Require-Contains $protocol "action: 's%party#partycookie'" 'party_cookie_compatibility'
Require-Contains $protocol "action: 's%musictrack#broadcastingmusictracks'" 'soundstudio_broadcast_query'
Require-Contains $protocol "action: 's%i#currencies'" 'late_as3_currency_query'
Require-Contains $protocol "action: 's%g#cli'" 'late_as3_igloo_like_query'

$join=Read-Normalized $joinHandlersPath
Require-Contains $join 'await sendModernPartyBootstrap(ctx);' 'join_party_bootstrap'
Require-Contains $join "action: 'room-avatar-state'" 'room_avatar_diagnostic'
$handlers=Read-Normalized $partyHandlersPath
foreach($token in @('activefeatures','partycookie','partyservice','modern-party-bootstrap')){Require-Contains $handlers $token ('party_handler_'+$token)}
Require-Contains $handlers 'handleModernBitmapInteraction' 'party_bitmap_interaction_handler'
Require-Contains $handlers 'party-bitmap-interaction' 'party_bitmap_interaction_trace'
$worldHandlers=Read-Normalized $worldHandlersPath
Require-Contains $worldHandlers "p.xt('s', 'nx#bimp', ['string'], handleModernBitmapInteraction)" 'party_bitmap_interaction_registration'
$partyData=Read-Normalized $partyDataPath
Require-Contains $partyData "'halloween-2015':" 'party_service_archive_fallback'

if(-not(Test-Path -LiteralPath $historicalManifestPath -PathType Leaf)){throw "WADDLE_PARTY2015_SOURCE=FAIL historical_manifest_missing"}
$historicalManifest=Get-Content -LiteralPath $historicalManifestPath -Raw|ConvertFrom-Json
if([int]$historicalManifest.requiredCount -ne 132){throw "WADDLE_PARTY2015_SOURCE=FAIL historical_count=$($historicalManifest.requiredCount)"}

$canonicalManifest=Get-Content -LiteralPath $canonicalManifestPath -Raw|ConvertFrom-Json
if($canonicalManifest.schema -ne 'waddle-canonical-assets/v1'){throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_schema=$($canonicalManifest.schema)"}
$canonicalAssets=@($canonicalManifest.assets); $canonicalTargets=@($canonicalAssets|ForEach-Object{[string]$_.target})
if(-not($canonicalTargets -contains 'content/party-runtime-2015-base.swf')){throw 'WADDLE_PARTY2015_SOURCE=FAIL runtime_donor_manifest_missing'}
$runtimeEntry=$canonicalAssets|Where-Object{$_.target -eq 'content/party-runtime-2015-base.swf'}|Select-Object -First 1
if([long]$runtimeEntry.bytes -ne 39406 -or ([string]$runtimeEntry.sha256).ToLowerInvariant() -ne 'd30fcd85c2f4a6b9ef6d1b81aac3a6d2f592af5f68ae13bb9d1564cb5b115cf7'){throw 'WADDLE_PARTY2015_SOURCE=FAIL runtime_donor_identity'}
if(-not(Test-Path -LiteralPath $runtimePatchPath -PathType Leaf)){throw 'WADDLE_PARTY2015_SOURCE=FAIL runtime_patch_missing'}
$runtimePatch=Read-Normalized $runtimePatchPath
foreach($contract in @('WADDLE_HALLOWEEN_2015_ROBOT_RAMPAGE_V2','static function pickupItem','static function showRobotInstructionsPopup','static function loadMiniGame','static function getCompletionDialogue','static function getCompletedTaskIndex','static function finishMiniGamePresentation','PENULTIMATE_TASK_ID','HERBOT_DEFEATED_TASK_ID','dialogue_Gary_congrats','dialogue_Rook_congrats','taskCompleteRoomUpdate','CONSTANTS.COFFEE_CUP','CONSTANTS.CLOWN')){
  Require-Contains $runtimePatch $contract ('runtime_patch_'+($contract -replace '[^A-Za-z0-9]+','_').Trim('_'))
}
$presentCanonical=0
foreach($entry in $canonicalAssets){
  $path=Join-Path $partyRoot (([string]$entry.target).Replace('/','\')); if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}; $presentCanonical++
  if([long](Get-Item -LiteralPath $path).Length -ne [long]$entry.bytes){throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_bytes target=$($entry.target)"}
  if($entry.PSObject.Properties.Name -contains 'sha256' -and -not [string]::IsNullOrWhiteSpace([string]$entry.sha256)){
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant(); if($actual -ne ([string]$entry.sha256).ToLowerInvariant()){throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_sha256 target=$($entry.target)"}
  } else {
    if((Get-GitBlobSha $path) -ne ([string]$entry.gitBlobSha).ToLowerInvariant()){throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_blob target=$($entry.target)"}
  }
  if([string]$entry.kind -eq 'swf' -and -not(Test-Swf $path)){throw "WADDLE_PARTY2015_SOURCE=FAIL canonical_swf target=$($entry.target)"}
}

$updates=Read-Normalized $updatesPath
Require-Contains $updates 'import { UPDATES_2015 } from "./2015";' 'updates_2015_import'
Require-Contains $updates '...UPDATES_2015' 'updates_2015_registration'
Write-Host "WADDLE_PARTY2015_SOURCE=PASS runtime=generated-halloween-compat donor=operation-crustacean-2015 activefeatures=20151101 shell=svanilla features=party-json-parser transform=party-to-spts robot_tf=canonical bitmap_interaction=instrumented historical_swfs=132 canonical_provenance=$($canonicalAssets.Count) canonical_present=$presentCanonical"