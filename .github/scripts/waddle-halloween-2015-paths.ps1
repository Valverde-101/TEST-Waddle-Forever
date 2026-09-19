[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$updatesPath=Join-Path $repo 'src/server/updates/2015.ts'
$fileGeneratorsPath=Join-Path $repo 'src/server/file-generators/index.ts'
$preservedPathsPath=Join-Path $repo 'media/default/party2015/game_configs/paths.json'
foreach($path in @($updatesPath,$fileGeneratorsPath,$preservedPathsPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing=$path"}}
$updates=([IO.File]::ReadAllText($updatesPath)-replace "`r`n","`n")
$generators=([IO.File]::ReadAllText($fileGeneratorsPath)-replace "`r`n","`n")
$preservedPaths=([IO.File]::ReadAllText($preservedPathsPath)).Replace('\/','/')
function Require([bool]$Condition,[string]$Label){if(-not $Condition){throw "WADDLE_HALLOWEEN2015_PATHS=FAIL missing_contract=$Label"}}
function Match([string]$Text,[string]$Pattern,[string]$Label){Require ($Text -match $Pattern) $Label}

Require ($generators.Contains('const getRuntimePathsJson: FileGenerator')) 'runtime_paths_generator'
Require ($generators.Contains('...Object.fromEntries(d.getGlobalPaths())')) 'runtime_global_paths_merge'
Require ($generators.Contains("'play/en/web_service/game_configs/paths.json': getRuntimePathsJson")) 'runtime_paths_registration'
Require ($generators.Contains("const LATE_AS3_FEATURES_ROUTE = 'play/v2/content/global/content/features.swf';")) 'late_as3_features_route_guard'
Require ($generators.Contains("const LATE_AS3_FEATURES_CRUMB = 'w.app.generic.features';")) 'late_as3_features_crumb_guard'
Require ($generators.Contains("[LATE_AS3_FEATURES_CRUMB]: 'content/features.swf'")) 'late_as3_features_crumb_mapping'

Match $updates "activeFeatures\s*:\s*'20151101'" 'templated_selector'
Match $updates "'play/v2/content/global/content/party\.swf'\s*:\s*ref\('content/party-runtime-2015\.swf'\)" 'templated_party_runtime'
Match $updates "'play/v2/client/shell\.swf'\s*:\s*'svanilla:media/play/v2/client/shell\.swf'" 'modern_shell_reset'
Match $updates "'play/v2/content/global/content/features\.swf'\s*:\s*ref\('content/ContentFeatures-HalloweenParty2015\.swf'\)" 'features_runtime_route'
Match $updates "'close_ups/quest_interface\.swf'\s*:\s*\[ref\('close_ups/Close_upsQuest_interface-HalloweenParty2015\.swf'\).*?'w\.app\.generic\.partyinterface'" 'generic_quest_interface_crumb'
Match $updates "'content/party_icon\.swf'\s*:\s*\[[^\]]*'party_icon'[^\]]*'scavenger_hunt_icon'" 'party_icon_crumbs'
Match $updates "'avatar/sprites/robot\.swf'\s*:\s*\[ref\('avatar/PenguinRobot\.swf'\)\s*,\s*'robot_tf'\s*,\s*'w\.avatarSprite\.robot'\s*\]" 'robot_transform_tokens'
Match $preservedPaths '"w\.p2015\.may\.login"\s*:\s*"close_ups/halloLogin\.swf"' 'preserved_hallo_login_crumb'
Match $updates "'close_ups/halloLogin\.swf'\s*:\s*\[ref\('close_ups/Hallo15_dialogue_login\.swf'\).*?'w\.app\.loginprompt'" 'generic_login_prompt_alias'

$aliases=@(
  @{route='close_ups/halloHerbertMonologue.swf';target='close_ups/Hallo15_dialogue_Herbert_monologue.swf';crumb='halloHerbertMonologue'},
  @{route='close_ups/halloHerbertMonologue2.swf';target='close_ups/Hallo15_dialogue_Herbert_monologue_2.swf';crumb='halloHerbertMonologue2'},
  @{route='close_ups/halloHerbot.swf';target='close_ups/Hallo15_dialogue_Herbot.swf';crumb='halloHerbot'},
  @{route='close_ups/halloHerbertCage.swf';target='close_ups/Hallo15_dialogue_Herbert_caged.swf';crumb='halloHerbertCage'},
  @{route='close_ups/halloGaryLair.swf';target='close_ups/Hallo15_dialogue_Gary_lair.swf';crumb='halloGaryLair'},
  @{route='close_ups/halloHerbertGetaway.swf';target='close_ups/Hallo15_dialogue_Herbert_escape.swf';crumb='halloHerbertGetaway'},
  @{route='close_ups/halloGaryFinal.swf';target='close_ups/Hallo15_dialogue_Gary_final.swf';crumb='halloGaryFinal'},
  @{route='close_ups/tiles_minigame8v2.swf';target='close_ups/Close_upsTiles_minigame8-HalloweenParty2015.swf';crumb='halloHerbertGame'}
)
foreach($a in $aliases){$pattern="'"+[regex]::Escape($a.route)+"'\s*:\s*\[ref\('"+[regex]::Escape($a.target)+"'\)\s*,\s*'"+[regex]::Escape($a.crumb)+"'\]";Match $updates $pattern ('alias_'+$a.crumb)}
foreach($token in @('dialogueGlobalChanges','dialogueLocalChanges','tileGlobalChanges','tileLocalChanges')){Require ($updates.Contains('...'+$token)) ('routes_'+$token)}

Require ($generators.Contains("const HALLOWEEN_2015_SOLO_ROOM_ROUTE = 'play/v2/content/global/rooms/partysolo1.swf';")) 'solo_room_route_guard'
Match $generators "rooms\['891'\]\s*=\s*\{" 'solo_room_891'
Match $generators "room_key\s*:\s*'partysolo1'" 'solo_room_key'
Match $generators "path\s*:\s*'partysolo1\.swf'" 'solo_room_path'

foreach($stale in @("ref('content/party-base-2015.swf')","ref('content/party.swf')","ref('content/map.swf')",'ClientInterface-HalloweenClassic2015.swf','Close_upsQuest_interface-HalloweenClassic2015.swf')){Require (-not $updates.Contains($stale)) ('no_mixed_'+($stale-replace'[^A-Za-z0-9]+','_'))}
Write-Host "WADDLE_HALLOWEEN2015_PATHS=PASS runtime_paths=generated generic_runtime=templated-late-2015 activefeatures=20151101 features_crumb=w.app.generic.features quest_interface=exact-cparchives-2015 login=exact-cparchives-2015 solo_room=891 mixed_runtime=false"
