[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
function Read-N([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WADDLE_HALLOWEEN2015_DATA=FAIL missing=$Path"};return ([IO.File]::ReadAllText($Path)-replace "`r`n","`n")}
function Require([bool]$Condition,[string]$Label){if(-not $Condition){throw "WADDLE_HALLOWEEN2015_DATA=FAIL missing_contract=$Label"}}
function Match([string]$Text,[string]$Pattern,[string]$Label){Require ($Text -match $Pattern) $Label}

$puffle=Read-N (Join-Path $repo 'src/server/socket-server/handlers/puffle.ts')
$updates=Read-N (Join-Path $repo 'src/server/updates/2015.ts')
$generators=Read-N (Join-Path $repo 'src/server/file-generators/index.ts')
$historical=Get-Content -LiteralPath (Join-Path $repo 'media/default/party2015/manifest.json') -Raw|ConvertFrom-Json
$canonical=Get-Content -LiteralPath (Join-Path $repo '.github/manifests/halloween-2015-canonical.json') -Raw|ConvertFrom-Json

Require ($puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) 'creature_price_from_puffle_data'
Match $updates "partyName\s*:\s*'Halloween Party 2015'" 'party_name'
Match $updates "activeFeatures\s*:\s*'20151101'" 'templated_selector'
Match $updates "id\s*:\s*'halloween-2015'" 'party_id'
foreach($pair in @(@('messageCount',10),@('communicatorMessageCount',5),@('taskCount',10),@('maxCoinUpdate',10),@('unlockDayIndex',16),@('numOfDaysInParty',16))){Match $updates ("{0}\s*:\s*{1}" -f $pair[0],$pair[1]) ('progress_'+$pair[0])}
Match $updates "partyStartDate\s*:\s*'2015-10-21 00:00:00'" 'party_start'
Match $updates "partyEndDate\s*:\s*'2015-11-05 00:00:00'" 'party_end'
Match $updates "rooms\s*:\s*HALLOWEEN_2015_ROOMS" 'rooms'
Match $updates "music\s*:\s*HALLOWEEN_2015_MUSIC" 'music'
Match $updates "'play/v2/content/global/content/party\.swf'\s*:\s*ref\('content/party-runtime-2015\.swf'\)" 'party_runtime_templated_2015'
Match $updates "'play/v2/client/shell\.swf'\s*:\s*'svanilla:media/play/v2/client/shell\.swf'" 'late_as3_shell_reset'
Match $updates "'play/v2/content/global/content/interface\.swf'\s*:\s*ref\('client/ClientInterface-HalloweenParty2015\.swf'\)" 'client_interface_historical'
Match $updates "'play/v2/content/global/content/features\.swf'\s*:\s*ref\('content/ContentFeatures-HalloweenParty2015\.swf'\)" 'features_historical'
Match $updates "'play/v2/content/global/content/party_icon\.swf'\s*:\s*ref\('content/ContentParty_icon-HalloweenParty2015\.swf'\)" 'party_icon_historical'
Match $updates "'play/v2/client/QuestCommunicator\.swf'\s*:\s*ref\('client/QuestCommunicator\.swf'\)" 'quest_communicator'
Match $updates "'close_ups/quest_interface\.swf'\s*:\s*\[ref\('close_ups/Close_upsQuest_interface-HalloweenParty2015\.swf'\).*?'w\.app\.generic\.partyinterface'" 'quest_interface_generic_crumb'
Match $updates "'close_ups/halloLogin\.swf'\s*:\s*\[ref\('close_ups/Hallo15_dialogue_login\.swf'\).*?'w\.app\.loginprompt'" 'login_prompt_generic_crumb'
Match $updates "'content/party_icon\.swf'\s*:\s*\[[^\]]*'party_icon'[^\]]*'scavenger_hunt_icon'" 'party_icon_crumbs'
Require (-not $updates.Contains("ref('content/party-base-2015.swf')")) 'obsolete_mayparty_runtime_absent'
Require (-not $updates.Contains("ref('content/party.swf')")) 'recreation_party_runtime_absent'
Require (-not $updates.Contains("ref('content/map.swf')")) 'recreation_map_absent'

# The Mine Shack doorway targets the preserved 2015 School key at room 122.
# Waddle's static room table calls the same id "eco", so the runtime metadata
# must restore "school" while the Halloween room asset is active.
Require ($generators.Contains("const HALLOWEEN_2015_SCHOOL_ROOM_ROUTE = 'play/v2/content/global/rooms/school.swf';")) 'school_room_route_guard'
Match $generators "rooms\['122'\]\s*=\s*\{" 'school_room_122_mount'
Match $generators "room_key\s*:\s*'school'" 'school_room_key'
Match $generators "path\s*:\s*'school\.swf'" 'school_room_path'

# The Coffee Shop's preserved Halloween hotspot targets the private solo room 891.
Require ($generators.Contains("const HALLOWEEN_2015_SOLO_ROOM_ROUTE = 'play/v2/content/global/rooms/partysolo1.swf';")) 'solo_room_route_guard'
Match $generators "rooms\['891'\]\s*=\s*\{" 'solo_room_891_mount'
Match $generators "room_key\s*:\s*'partysolo1'" 'solo_room_key'
Match $generators "path\s*:\s*'partysolo1\.swf'" 'solo_room_path'

Require ([int]$historical.requiredCount -eq 132) 'historical_required_count_132'
$historicalAssets=@($historical.assets); Require ($historicalAssets.Count -eq 132) 'historical_assets_132'
$historicalTargets=@($historicalAssets|ForEach-Object{[string]$_.relativePath})
foreach($target in @('client/ClientInterface-HalloweenParty2015.swf','close_ups/Close_upsQuest_interface-HalloweenParty2015.swf','content/ContentFeatures-HalloweenParty2015.swf','content/ContentParty_icon-HalloweenParty2015.swf','rooms/Hallo15_partysolo1.swf')){Require ($historicalTargets -contains $target) ('historical_'+($target-replace'[^A-Za-z0-9]+','_'))}

Require ($canonical.schema -eq 'waddle-canonical-assets/v1') 'canonical_manifest_schema'
$canonicalAssets=@($canonical.assets); $canonicalTargets=@($canonicalAssets|ForEach-Object{[string]$_.target})
Require ($canonicalTargets -contains 'client/QuestCommunicator.swf') 'canonical_quest_communicator_source'
Require ($canonicalTargets -contains 'content/party-runtime-2015-base.swf') 'canonical_runtime_donor'
$runtime=$canonicalAssets|Where-Object{$_.target -eq 'content/party-runtime-2015-base.swf'}|Select-Object -First 1
Require ([long]$runtime.bytes -eq 39406) 'runtime_donor_bytes'
Require (([string]$runtime.sha256).ToLowerInvariant() -eq 'd30fcd85c2f4a6b9ef6d1b81aac3a6d2f592af5f68ae13bb9d1564cb5b115cf7') 'runtime_donor_sha256'

Write-Host "WADDLE_HALLOWEEN2015_DATA=PASS party=halloween-2015 runtime=generated-halloween-compat donor=operation-crustacean-2015 activefeatures=20151101 features=historical-cparchives icon=historical-cparchives school_room=122:school solo_room=891 historical_swfs=132 canonical_provenance=$($canonicalAssets.Count)"
