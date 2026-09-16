param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$CanonicalRoot = $RepoRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert([bool]$Condition,[string]$Message) {
  if (-not $Condition) { throw "WADDLE_PARTY2015_VERIFY=FAIL $Message" }
}

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 8) { return $false }
    $buf = New-Object byte[] 3
    if ($stream.Read($buf,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($buf)
  } finally { $stream.Dispose() }
}

function Get-GitBlobSha([string]$Path) {
  $payload = [IO.File]::ReadAllBytes($Path)
  $prefix = [Text.Encoding]::UTF8.GetBytes("blob $($payload.Length)`0")
  $all = New-Object byte[] ($prefix.Length + $payload.Length)
  [Buffer]::BlockCopy($prefix,0,$all,0,$prefix.Length)
  [Buffer]::BlockCopy($payload,0,$all,$prefix.Length,$payload.Length)
  $sha1 = [Security.Cryptography.SHA1]::Create()
  try { return (($sha1.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '') }
  finally { $sha1.Dispose() }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$canonical = (Resolve-Path -LiteralPath $CanonicalRoot).Path
$updatePath = Join-Path $repo 'src/server/updates/2015.ts'
$assetRoot = Join-Path $canonical 'media/default/party2015'
$manifestPath = Join-Path $assetRoot 'manifest.json'
$canonicalManifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
$partyHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$xtHandlerPath = Join-Path $repo 'src/server/socket-server/xt-handler.ts'

foreach ($path in @($updatePath,$manifestPath,$canonicalManifestPath,$partyHandlersPath,$xtHandlerPath)) {
  Assert (Test-Path -LiteralPath $path -PathType Leaf) "missing=$path"
}
$updates = ([IO.File]::ReadAllText($updatePath) -replace "`r`n", "`n")
$partyHandlers = [IO.File]::ReadAllText($partyHandlersPath)
$xtHandler = [IO.File]::ReadAllText($xtHandlerPath)

Assert ($updates.Contains("date: '2015-10-21'")) 'party_start_missing'
Assert ($updates.Contains("partyName: 'Halloween Party 2015'")) 'party_name_missing'
Assert ($updates.Contains("activeFeatures: '20150501'")) 'activefeatures_missing'
Assert ($updates.Contains("partyEndDate: '2015-11-05 00:00:00'")) 'partyservice_end_missing'
Assert ($updates.Contains("date: '2015-11-05'")) 'party_end_date_missing'
Assert ($updates.Contains("end: ['party']")) 'party_end_missing'

$requiredLive = @(
  "'play/v2/client/QuestCommunicator.swf': ref('client/QuestCommunicator.swf')",
  "'play/v2/client/interface.swf': ref('client/ClientInterface-HalloweenParty2015.swf')",
  "'play/v2/content/global/content/interface.swf': ref('client/ClientInterface-HalloweenParty2015.swf')",
  "'play/v2/content/global/content/features.swf': ref('content/ContentFeatures-HalloweenParty2015.swf')",
  "'play/v2/content/global/content/party_icon.swf': ref('content/ContentParty_icon-HalloweenParty2015.swf')",
  "'play/v2/content/global/logo/logo.swf': ref('content/ContentLogo-HalloweenParty2015.swf')",
  "'close_ups/quest_interface.swf': [ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf')",
  "'close_ups/quest_interface.swf': { en: ref('close_ups/Close_upsQuest_interface-HalloweenParty2015.swf') }",
  "'close_ups/halloLogin.swf': [ref('close_ups/Hallo15_dialogue_login.swf'), 'w.p2015.may.login']",
  "'close_ups/halloLogin.swf': { en: ref('close_ups/Hallo15_dialogue_login.swf') }"
)
foreach ($contract in $requiredLive) { Assert ($updates.Contains($contract)) "live_contract_missing=$contract" }

foreach ($stale in @(
  "ref('content/party.swf')","ref('content/map.swf')",
  "ref('client/ClientInterface-HalloweenClassic2015.swf')",
  "ref('close_ups/Close_upsQuest_interface-HalloweenClassic2015.swf')",
  "ref('close_ups/ghostAdopt.swf')","ref('close_ups/skipDialogue.swf')",
  "ref('game_configs/game_configs.bin')","'w.p2015.may.partymap'",
  '2048.swf','2049.swf','2050.swf','2051.swf','2052.swf','2053.swf'
)) { Assert (-not $updates.Contains($stale)) "mixed_or_missing_runtime_dependency=$stale" }
Assert ($updates.Contains('...dialogueGlobalChanges')) 'dialogue_global_routes_missing'
Assert ($updates.Contains('...dialogueLocalChanges')) 'dialogue_local_routes_missing'
Assert ($updates.Contains('...tileGlobalChanges')) 'tile_global_routes_missing'
Assert ($updates.Contains('...tileLocalChanges')) 'tile_local_routes_missing'
Assert ($updates.Contains('...musicFileChanges')) 'music_routes_missing'

foreach ($token in @('activefeatures','partycookie','partyservice','qtupdate')) {
  Assert ($partyHandlers.Contains($token)) "party_handler_missing=$token"
}
foreach ($alias in @('halloween#partycookie','halloween#msgviewed','halloween#qcmsgviewed','halloween#qtaskcomplete','halloween#qtupdate')) {
  Assert ($xtHandler.Contains($alias)) "native_namespace_alias_missing=$alias"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert ([int]$manifest.requiredCount -eq 132) "historical_required=$($manifest.requiredCount) expected=132"
$historical = @($manifest.assets | Where-Object { [bool]$_.required })
Assert ($historical.Count -eq 132) "historical_entries=$($historical.Count) expected=132"
$historicalTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $historical) {
  $relative = ([string]$entry.relativePath).Replace('\','/')
  Assert ($historicalTargets.Add($relative)) "duplicate_historical_target=$relative"
  $path = Join-Path $assetRoot $relative.Replace('/','\')
  Assert (Test-Path -LiteralPath $path -PathType Leaf) "historical_missing=$relative"
  $item = Get-Item -LiteralPath $path
  Assert ([int64]$item.Length -eq [int64]$entry.bytes) "historical_bytes=$relative actual=$($item.Length) expected=$($entry.bytes)"
  Assert (Test-Swf $path) "historical_invalid_swf=$relative"
  $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  Assert ($sha256 -eq ([string]$entry.sha256).ToUpperInvariant()) "historical_sha256=$relative"
}
foreach ($critical in @(
  'client/ClientInterface-HalloweenParty2015.swf','close_ups/Close_upsQuest_interface-HalloweenParty2015.swf',
  'content/ContentFeatures-HalloweenParty2015.swf','content/ContentParty_icon-HalloweenParty2015.swf','content/ContentLogo-HalloweenParty2015.swf',
  'close_ups/Hallo15_dialogue_login.swf'
)) { Assert ($historicalTargets.Contains($critical)) "critical_historical_missing=$critical" }

$canonicalManifest = Get-Content -LiteralPath $canonicalManifestPath -Raw | ConvertFrom-Json
Assert ($canonicalManifest.schema -eq 'waddle-canonical-assets/v1') "canonical_schema=$($canonicalManifest.schema)"
$canonicalAssets = @($canonicalManifest.assets)
Assert ($canonicalAssets.Count -eq 16) "canonical_assets=$($canonicalAssets.Count) expected=16"
$canonicalTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$canonicalSwfs = 0
foreach ($entry in $canonicalAssets) {
  $target = ([string]$entry.target).Replace('\','/')
  Assert ($canonicalTargets.Add($target)) "duplicate_canonical_target=$target"
  $path = Join-Path $assetRoot $target.Replace('/','\')
  Assert (Test-Path -LiteralPath $path -PathType Leaf) "canonical_missing=$target"
  $item = Get-Item -LiteralPath $path
  Assert ([int64]$item.Length -eq [int64]$entry.bytes) "canonical_bytes=$target"
  Assert ((Get-GitBlobSha $path) -eq ([string]$entry.gitBlobSha).ToLowerInvariant()) "canonical_blob=$target"
  if ([string]$entry.kind -eq 'swf') { $canonicalSwfs++; Assert (Test-Swf $path) "canonical_invalid_swf=$target" }
}
Assert ($canonicalSwfs -eq 8) "canonical_swfs=$canonicalSwfs expected=8"
Assert ($canonicalTargets.Contains('client/QuestCommunicator.swf')) 'quest_communicator_provenance_missing'

$dialogueNames = @(
  'dialogue_login','dialogue_AA_start','dialogue_AA_instruct','dialogue_AA_congrats','dialogue_Cad_start','dialogue_Cad_instruct','dialogue_Cad_congrats',
  'dialogue_Dot_start','dialogue_Dot_instruct','dialogue_Dot_congrats','dialogue_PH_start','dialogue_PH_instruct','dialogue_PH_congrats',
  'dialogue_RH_start','dialogue_RH_instruct','dialogue_RH_congrats','dialogue_Rook_start','dialogue_Rook_instruct','dialogue_Rook_congrats','dialogue_Rookie_bot',
  'dialogue_Sen_start','dialogue_Sen_instruct','dialogue_Sen_congrats','dialogue_Gary_instruct','dialogue_Gary_instruct_2','dialogue_Gary_instruct_3','dialogue_Gary_lair',
  'dialogue_Gary_congrats','dialogue_Gary_final','dialogue_Herbert_caged','dialogue_Herbert_escape','dialogue_Herbot','dialogue_Herbert_monologue','dialogue_Herbert_monologue_2'
)
Assert ($dialogueNames.Count -eq 34) "dialogue_contract=$($dialogueNames.Count) expected=34"
foreach ($name in $dialogueNames) {
  $relative = "close_ups/Hallo15_$name.swf"
  Assert ($historicalTargets.Contains($relative)) "dialogue_manifest_missing=$relative"
  Assert (Test-Swf (Join-Path $assetRoot $relative.Replace('/','\'))) "dialogue_invalid=$relative"
}
foreach ($i in 0..8) {
  $relative = "close_ups/Close_upsTiles_minigame$i-HalloweenParty2015.swf"
  Assert ($historicalTargets.Contains($relative)) "tile_manifest_missing=$relative"
}
$musicIds = @(345,403,532,588,659,669,838,884,922,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1067)
Assert ($musicIds.Count -eq 38) "music_contract=$($musicIds.Count) expected=38"
foreach ($id in $musicIds) {
  $relative = "music/Music$id.swf"
  Assert ($historicalTargets.Contains($relative)) "music_manifest_missing=$relative"
  Assert (Test-Swf (Join-Path $assetRoot $relative.Replace('/','\'))) "music_invalid=$relative"
}

$physicalSwfs = @(Get-ChildItem -LiteralPath $assetRoot -Filter '*.swf' -File -Recurse)
Assert ($physicalSwfs.Count -eq 140) "physical_swfs=$($physicalSwfs.Count) expected=140"

Write-Host "WADDLE_PARTY2015_VERIFY=PASS runtime=exact-cparchives-2015 historical_verified=132 canonical_provenance=16 canonical_swfs=8 physical_swfs=140 dialogues=34 hallo_login=historical-alias tiles=9 music=38 interface=historical-2015 quest=historical-2015 party_map=base-runtime dynamic_loader_assets=verified mixed_2310=false"
