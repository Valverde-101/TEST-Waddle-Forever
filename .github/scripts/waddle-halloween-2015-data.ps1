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

$pufflePath = Join-Path $repo 'src/server/socket-server/handlers/puffle.ts'
$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$historicalManifestPath = Join-Path $repo 'media/default/party2015/manifest.json'
$canonicalManifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
$puffle = Read-N $pufflePath
$updates = Read-N $updatesPath
$historical = Get-Content -LiteralPath $historicalManifestPath -Raw | ConvertFrom-Json
$canonical = Get-Content -LiteralPath $canonicalManifestPath -Raw | ConvertFrom-Json

Require ($puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) 'creature_price_from_puffle_data'
foreach ($needle in @(
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
  '...musicFileChanges',
  '...dialogueGlobalChanges',
  '...dialogueLocalChanges',
  '...tileGlobalChanges',
  '...tileLocalChanges'
)) { Require ($updates.Contains($needle)) ("update_" + ($needle -replace '[^A-Za-z0-9]+','_').Trim('_')) }

# Exact October 2015 interaction family. The preserved CPArchives interface and
# quest interface are authoritative; the 2310 recreation is archival provenance.
Require ($updates.Contains("'play/v2/client/interface.swf': ref('client/ClientInterface-HalloweenParty2015.swf')")) 'client_interface_historical_2015'
Require ($updates.Contains("'play/v2/content/global/content/interface.swf': ref('client/ClientInterface-HalloweenParty2015.swf')")) 'content_interface_historical_2015'
Require ($updates.Contains("'play/v2/content/global/content/features.swf': ref('content/ContentFeatures-HalloweenParty2015.swf')")) 'features_historical_2015'
Require ($updates.Contains("'play/v2/content/global/content/party_icon.swf': ref('content/ContentParty_icon-HalloweenParty2015.swf')")) 'party_icon_historical_2015'
Require ($updates.Contains("'play/v2/client/QuestCommunicator.swf': ref('client/QuestCommunicator.swf')")) 'quest_communicator'
Require ($updates.Contains("'close_ups/quest_interface.swf': [ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf'), 'w.p2015.may.partyinterface', 'w.app.generic.partyinterface', 'scavenger_hunt']")) 'quest_interface_global_historical_2015'
Require ($updates.Contains("'close_ups/quest_interface.swf': { en: ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf') }")) 'quest_interface_local_historical_2015'
Require ($updates -match "'content/party_icon\.swf'\s*:\s*\[[^\]]*'party_icon'[^\]]*'scavenger_hunt_icon'[^\]]*\]") 'party_icon_crumbs'

# Root regression guards: these requests caused the visually loaded but inert
# mixed stack (including dynamic 2048 music and party_map_note requests).
foreach ($stale in @(
  "'play/en/web_service/game_configs.bin'",
  "'play/v2/content/global/content/party.swf'",
  "'play/v2/content/global/content/map.swf'",
  "'content/map.swf':",
  'ClientInterface-HalloweenClassic2015.swf',
  'Close_upsQuest_interface-HalloweenClassic2015.swf',
  "'close_ups/ghostAdopt.swf'",
  "'close_ups/skipDialogue.swf'",
  "'close_ups/halloLogin.swf'"
)) { Require (-not $updates.Contains($stale)) ("no_mixed_2310_" + ($stale -replace '[^A-Za-z0-9]+','_').Trim('_')) }

Require ([int]$historical.requiredCount -eq 132) 'historical_required_count_132'
$historicalAssets = @($historical.assets)
Require ($historicalAssets.Count -eq 132) 'historical_assets_132'
$historicalTargets = @($historicalAssets | ForEach-Object { [string]$_.relativePath })
foreach ($target in @(
  'client/ClientInterface-HalloweenParty2015.swf',
  'close_ups/Close_upsQuest_interface-HalloweenParty2015.swf',
  'content/ContentFeatures-HalloweenParty2015.swf',
  'content/ContentParty_icon-HalloweenParty2015.swf',
  'close_ups/Hallo15_dialogue_login.swf',
  'close_ups/Close_upsTiles_minigame0-HalloweenParty2015.swf',
  'close_ups/Close_upsTiles_minigame8-HalloweenParty2015.swf'
)) { Require ($historicalTargets -contains $target) ("historical_" + ($target -replace '[^A-Za-z0-9]+','_')) }

# Canonical supplements remain byte-pinned provenance but are no longer treated
# as the live Halloween 2015 family.
Require ($canonical.schema -eq 'waddle-canonical-assets/v1') 'canonical_manifest_schema'
$canonicalAssets = @($canonical.assets)
Require ($canonicalAssets.Count -gt 0) 'canonical_manifest_nonempty'
$canonicalTargets = @($canonicalAssets | ForEach-Object { [string]$_.target })
Require (@($canonicalTargets | Sort-Object -Unique).Count -eq $canonicalTargets.Count) 'canonical_targets_unique'
Require ($canonicalTargets -contains 'client/QuestCommunicator.swf') 'canonical_quest_communicator_source'

Write-Host "WADDLE_HALLOWEEN2015_DATA=PASS mode=validation_only mutation=false party=halloween-2015 tasks=10 activefeatures=20150501 partyservice=true runtime=base-modern interface=exact-cparchives-2015 quest_interface=exact-cparchives-2015 dialogues=exact-cparchives-2015 rooms=exact-cparchives-2015 music=exact-cparchives-2015 quest_communicator=true historical_swfs=132 canonical_provenance=$($canonicalAssets.Count) mixed_2310=false"
