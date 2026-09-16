[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$fileGeneratorsPath = Join-Path $repo 'src/server/file-generators/index.ts'

if (-not (Test-Path -LiteralPath $updatesPath -PathType Leaf)) { throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing=$updatesPath" }
if (-not (Test-Path -LiteralPath $fileGeneratorsPath -PathType Leaf)) { throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing=$fileGeneratorsPath" }
$updates = ([IO.File]::ReadAllText($updatesPath) -replace "`r`n", "`n")
$generators = ([IO.File]::ReadAllText($fileGeneratorsPath) -replace "`r`n", "`n")

function Require([bool]$Condition,[string]$Label) {
  if(-not $Condition){throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing_contract=$Label"}
}

# Runtime paths are generated from the selected timeline party's globalChanges.
# The CPImagined 2310 paths.json is retained as provenance only and must not be
# interpreted as the authoritative October 2015 route table.
Require ($generators.Contains('const getRuntimePathsJson: FileGenerator')) 'runtime_paths_generator'
Require ($generators.Contains('...Object.fromEntries(d.getGlobalPaths())')) 'runtime_global_paths_merge'
Require ($generators.Contains("'play/en/web_service/game_configs/paths.json': getRuntimePathsJson")) 'runtime_paths_registration'

Require ($updates.Contains("'close_ups/quest_interface.swf': [ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf'), 'w.p2015.may.partyinterface', 'w.app.generic.partyinterface', 'scavenger_hunt']")) 'historical_quest_interface_crumbs'
Require ($updates.Contains("'close_ups/quest_interface.swf': { en: ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf') }")) 'historical_quest_interface_local'
Require ($updates.Contains("'content/party_icon.swf': [ref('content/ContentParty_icon-HalloweenParty2015.swf'), 'party_icon', 'scavenger_hunt_icon']")) 'party_icon_crumbs'

# These aliases are emitted by the preserved 2015 interaction content and must
# remain mapped to the matching historical close-up files.
$aliases = @(
  @{ route='close_ups/halloHerbertMonologue.swf'; target='close_ups/Hallo15_dialogue_Herbert_monologue.swf'; crumb='halloHerbertMonologue' },
  @{ route='close_ups/halloHerbertMonologue2.swf'; target='close_ups/Hallo15_dialogue_Herbert_monologue_2.swf'; crumb='halloHerbertMonologue2' },
  @{ route='close_ups/halloHerbot.swf'; target='close_ups/Hallo15_dialogue_Herbot.swf'; crumb='halloHerbot' },
  @{ route='close_ups/halloHerbertCage.swf'; target='close_ups/Hallo15_dialogue_Herbert_caged.swf'; crumb='halloHerbertCage' },
  @{ route='close_ups/halloGaryLair.swf'; target='close_ups/Hallo15_dialogue_Gary_lair.swf'; crumb='halloGaryLair' },
  @{ route='close_ups/halloHerbertGetaway.swf'; target='close_ups/Hallo15_dialogue_Herbert_escape.swf'; crumb='halloHerbertGetaway' },
  @{ route='close_ups/halloGaryFinal.swf'; target='close_ups/Hallo15_dialogue_Gary_final.swf'; crumb='halloGaryFinal' },
  @{ route='close_ups/tiles_minigame8v2.swf'; target='close_ups/Close_upsTiles_minigame8-HalloweenParty2015.swf'; crumb='halloHerbertGame' }
)
foreach ($alias in $aliases) {
  $literal = "'$($alias.route)': [ref('$($alias.target)'), '$($alias.crumb)']"
  Require ($updates.Contains($literal)) ("alias_" + $alias.crumb)
}

Require ($updates.Contains('...dialogueGlobalChanges')) 'dialogue_global_routes'
Require ($updates.Contains('...dialogueLocalChanges')) 'dialogue_local_routes'
Require ($updates.Contains('...tileGlobalChanges')) 'tile_global_routes'
Require ($updates.Contains('...tileLocalChanges')) 'tile_local_routes'

# Root regression guards. These paths belong to the later 2310 recreation. When
# they were live they caused map.swf -> party_map_note.swf 404 and 2048.swf 404.
foreach ($stale in @(
  "'content/map.swf':",
  "'close_ups/halloLogin.swf'",
  "'close_ups/ghostAdopt.swf'",
  "'close_ups/skipDialogue.swf'",
  'ClientInterface-HalloweenClassic2015.swf',
  'Close_upsQuest_interface-HalloweenClassic2015.swf',
  "'play/en/web_service/game_configs.bin'",
  "'play/v2/content/global/content/party.swf'",
  "'play/v2/content/global/content/map.swf'"
)) {
  Require (-not $updates.Contains($stale)) ("no_2310_" + ($stale -replace '[^A-Za-z0-9]+','_').Trim('_'))
}

Write-Host "WADDLE_HALLOWEEN2015_PATHS=PASS runtime_paths=generated-from-selected-party quest_interface=exact-cparchives-2015 dialogue_aliases=$($aliases.Count) map_note_dependency=false party_map=base-runtime cpimagined_paths=provenance-only mixed_2310=false"
