[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$pathsPath = Join-Path $repo 'media/default/party2015/game_configs/paths.json'

if (-not (Test-Path -LiteralPath $updatesPath -PathType Leaf)) {
  throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing=$updatesPath"
}
if (-not (Test-Path -LiteralPath $pathsPath -PathType Leaf)) {
  throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing=$pathsPath"
}

$updates = ([IO.File]::ReadAllText($updatesPath) -replace "`r`n", "`n")
$paths = Get-Content -LiteralPath $pathsPath -Raw | ConvertFrom-Json
if ($null -eq $paths.global) {
  throw 'WADDLE_HALLOWEEN2015_PATHS=FAIL global_paths_missing'
}

# These are the party-specific late-AS3 routes for which we have byte-preserved
# assets or a verified Waddle historical asset that is safe to expose under the
# literal path returned by the preserved 2015 paths.json.
$contracts = @(
  @{ key='skipDialogue'; route='close_ups/skipDialogue.swf'; source="'close_ups/skipDialogue.swf': [P + 'close_ups/skipDialogue.swf', 'skipDialogue']" },
  @{ key='w.p2015.may.login'; route='close_ups/halloLogin.swf'; source="'close_ups/halloLogin.swf': [P + 'close_ups/halloLogin.swf', 'w.p2015.may.login']" },
  @{ key='w.p2015.may.partyinterface'; route='close_ups/quest_interface.swf'; source="'close_ups/quest_interface.swf': [P + 'close_ups/Close_upsQuest_interface-HalloweenParty2015.swf', 'w.p2015.may.partyinterface'" },
  @{ key='w.p2015.may.partymap'; route='content/map.swf'; source="'content/map.swf': [P + 'content/map.swf', 'w.p2015.may.partymap']" },
  @{ key='ghostAdopt'; route='close_ups/ghostAdopt.swf'; source="'close_ups/ghostAdopt.swf': [P + 'close_ups/ghostAdopt.swf', 'ghostAdopt']" },
  @{ key='halloHerbertMonologue'; route='close_ups/halloHerbertMonologue.swf'; source="'close_ups/halloHerbertMonologue.swf': [P + 'close_ups/Hallo15_dialogue_Herbert_monologue.swf', 'halloHerbertMonologue']" },
  @{ key='halloHerbertMonologue2'; route='close_ups/halloHerbertMonologue2.swf'; source="'close_ups/halloHerbertMonologue2.swf': [P + 'close_ups/Hallo15_dialogue_Herbert_monologue_2.swf', 'halloHerbertMonologue2']" },
  @{ key='halloHerbot'; route='close_ups/halloHerbot.swf'; source="'close_ups/halloHerbot.swf': [P + 'close_ups/Hallo15_dialogue_Herbot.swf', 'halloHerbot']" },
  @{ key='halloHerbertCage'; route='close_ups/halloHerbertCage.swf'; source="'close_ups/halloHerbertCage.swf': [P + 'close_ups/Hallo15_dialogue_Herbert_caged.swf', 'halloHerbertCage']" },
  @{ key='halloGaryLair'; route='close_ups/halloGaryLair.swf'; source="'close_ups/halloGaryLair.swf': [P + 'close_ups/Hallo15_dialogue_Gary_lair.swf', 'halloGaryLair']" },
  @{ key='halloHerbertGetaway'; route='close_ups/halloHerbertGetaway.swf'; source="'close_ups/halloHerbertGetaway.swf': [P + 'close_ups/Hallo15_dialogue_Herbert_escape.swf', 'halloHerbertGetaway']" },
  @{ key='halloGaryFinal'; route='close_ups/halloGaryFinal.swf'; source="'close_ups/halloGaryFinal.swf': [P + 'close_ups/Hallo15_dialogue_Gary_final.swf', 'halloGaryFinal']" },
  @{ key='halloHerbertGame'; route='close_ups/tiles_minigame8v2.swf'; source="'close_ups/tiles_minigame8v2.swf': [P + 'close_ups/Close_upsTiles_minigame8-HalloweenParty2015.swf', 'halloHerbertGame']" }
)

foreach ($contract in $contracts) {
  $property = $paths.global.PSObject.Properties[$contract.key]
  if ($null -eq $property) {
    throw "WADDLE_HALLOWEEN2015_PATHS=FAIL preserved_key_missing=$($contract.key)"
  }
  $actual = ([string]$property.Value).Replace('\','/')
  if ($actual -ne $contract.route) {
    throw "WADDLE_HALLOWEEN2015_PATHS=FAIL preserved_route key=$($contract.key) expected=$($contract.route) actual=$actual"
  }
  if (-not $updates.Contains($contract.source)) {
    throw "WADDLE_HALLOWEEN2015_PATHS=FAIL source_route_missing key=$($contract.key) route=$($contract.route)"
  }
}

# The preserved config also names these two routes, but no corresponding binary
# exists in the pinned source archive or current Waddle media. Keep the gap visible
# rather than silently substituting an unrelated SWF. If one is recovered later it
# can be promoted into the contracts above and the canonical manifest.
$archiveOnly = @('halloIglooList','petShopAdopt')
$archiveOnlyDetails = @()
foreach ($key in $archiveOnly) {
  $property = $paths.global.PSObject.Properties[$key]
  if ($null -ne $property) {
    $archiveOnlyDetails += "$key=$(([string]$property.Value).Replace('\','/'))"
  }
}

Write-Host "WADDLE_HALLOWEEN2015_PATHS=PASS supported=$($contracts.Count) preserved_literal_routes=true archive_only=$($archiveOnlyDetails -join ',')"
