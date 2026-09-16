[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Read-N([string]$Path) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "WADDLE_HALLOWEEN2015_DATA=FAIL missing=$Path"}
  return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}
function Require([bool]$Condition,[string]$Label) {
  if(-not $Condition){throw "WADDLE_HALLOWEEN2015_DATA=FAIL missing_contract=$Label"}
}

# Committed source is authoritative. This gate validates the data contract only;
# the canonical hydrator owns downloading byte-exact preserved runtime assets.
$pufflePath = Join-Path $repo 'src/server/socket-server/handlers/puffle.ts'
$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$canonicalManifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
$puffle = Read-N $pufflePath
$updates = Read-N $updatesPath
$canonical = Get-Content -LiteralPath $canonicalManifestPath -Raw | ConvertFrom-Json

Require ($puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) 'creature_price_from_puffle_data'
Require ($updates.Contains("partyName: 'Halloween Party 2015'")) 'party_name'
Require ($updates.Contains("activeFeatures: '20150501'")) 'activefeatures_20150501'
Require ($updates.Contains("id: 'halloween-2015'")) 'party_progress_id'
Require ($updates.Contains('messageCount: 10')) 'message_count'
Require ($updates.Contains('communicatorMessageCount: 5')) 'communicator_count'
Require ($updates.Contains('taskCount: 10')) 'task_count'
Require ($updates.Contains('maxCoinUpdate: 10')) 'coin_cap'
Require ($updates.Contains("partyStartDate: '2015-10-21 00:00:00'")) 'party_service_start'
Require ($updates.Contains("partyEndDate: '2015-11-05 00:00:00'")) 'party_service_end'
Require ($updates.Contains('unlockDayIndex: 16')) 'party_service_unlock_day'
Require ($updates.Contains('numOfDaysInParty: 16')) 'party_service_days'

$iconAsset = "P + 'content/ContentParty_icon-HalloweenParty2015.swf'"
Require ($updates.Contains("'play/v2/client/interface.swf': P + 'client/ClientInterface-HalloweenClassic2015.swf'")) 'client_interface_route'
Require ($updates.Contains("'play/v2/content/global/content/interface.swf': P + 'client/ClientInterface-HalloweenClassic2015.swf'")) 'content_interface_alias'
Require ($updates.Contains("'play/v2/content/global/content/party_icon.swf': $iconAsset")) 'party_icon_canonical_route'
Require ($updates.Contains("'play/v2/content/global/content/party.swf': P + 'content/party.swf'")) 'preserved_party_runtime'
Require ($updates.Contains("'play/v2/content/global/content/map.swf': P + 'content/map.swf'")) 'preserved_party_map'
Require ($updates.Contains("'play/v2/client/QuestCommunicator.swf': P + 'client/QuestCommunicator.swf'")) 'quest_communicator'
Require ($updates.Contains("'play/en/web_service/game_configs.bin': P + 'game_configs/game_configs.bin'")) 'game_configs_bundle'
Require ($updates -match "'content/party_icon\.swf'\s*:\s*\[[^\]]*'party_icon'[^\]]*\]") 'party_icon_global_crumb'
Require ($updates -match "'content/party_icon\.swf'\s*:\s*\[[^\]]*'scavenger_hunt_icon'[^\]]*\]") 'party_icon_scavenger_alias'
Require ($updates.Contains("'close_ups/quest_interface.swf': [P + 'close_ups/Close_upsQuest_interface-HalloweenClassic2015.swf', 'w.p2015.may.partyinterface', 'w.app.generic.partyinterface', 'scavenger_hunt']")) 'quest_interface_global_path'
Require ($updates.Contains("'close_ups/quest_interface.swf': { en: P + 'close_ups/Close_upsQuest_interface-HalloweenClassic2015.swf' }")) 'quest_interface_local_path'
Require ($updates -match "'content/map\.swf'\s*:\s*\[[^\]]*'w\.p2015\.may\.partymap'[^\]]*\]") 'party_map_global_path'
Require ($updates -match "'close_ups/ghostAdopt\.swf'\s*:\s*\[[^\]]*'ghostAdopt'[^\]]*\]") 'ghost_adopt_global_path'
Require ($updates -match "'close_ups/skipDialogue\.swf'\s*:\s*\[[^\]]*'skipDialogue'[^\]]*\]") 'skip_dialogue_global_path'
Require ($updates.Contains("'close_ups/ghostAdopt.swf': { en: P + 'close_ups/ghostAdopt.swf' }")) 'ghost_adopt_local_path'
Require ($updates.Contains("'close_ups/skipDialogue.swf': { en: P + 'close_ups/skipDialogue.swf' }")) 'skip_dialogue_local_path'
Require (-not $updates.Contains("P + 'client/ClientInterface-HalloweenParty2015.swf'")) 'historical_interface_not_served'

Require ($canonical.schema -eq 'waddle-canonical-assets/v1') 'canonical_manifest_schema'
$assets = @($canonical.assets)
Require ($assets.Count -gt 0) 'canonical_manifest_nonempty'
$targets = @($assets | ForEach-Object { [string]$_.target })
Require (@($targets | Sort-Object -Unique).Count -eq $targets.Count) 'canonical_targets_unique'
foreach ($target in @(
  'content/party.swf','content/map.swf','client/QuestCommunicator.swf',
  'client/ClientInterface-HalloweenClassic2015.swf',
  'close_ups/Close_upsQuest_interface-HalloweenClassic2015.swf',
  'close_ups/ghostAdopt.swf','close_ups/skipDialogue.swf',
  'game_configs/game_configs.bin','game_configs/game_strings.json','game_configs/general.json',
  'game_configs/paths.json','game_configs/rooms.json'
)) {
  Require ($targets -contains $target) ("canonical_" + ($target -replace '[^A-Za-z0-9]+','_'))
}

if ($updates -match 'gameStringChanges:\s*\{(?s:.*?)w\.app\.p2015\.halloween') {
  throw 'WADDLE_HALLOWEEN2015_DATA=FAIL unverified_halloween_strings_remain'
}

$swfCount = @($assets | Where-Object { [string]$_.kind -eq 'swf' }).Count
Write-Host "WADDLE_HALLOWEEN2015_DATA=PASS mode=validation_only mutation=false party=halloween-2015 tasks=10 activefeatures=20150501 partyservice=true ghost_puffle=1022 party_icon=true runtime=preserved-halloween map=preserved-halloween interface=coherent-halloween-classic quest_interface=coherent-halloween-classic quest_communicator=true ghost_adopt=true skip_dialogue=true config_bundle=true canonical_assets=$($assets.Count) canonical_swfs=$swfCount"
