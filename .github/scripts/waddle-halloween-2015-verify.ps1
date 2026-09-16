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

function Test-ZipConfig([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 4) { return $false }
    $buf = New-Object byte[] 4
    if ($stream.Read($buf,0,4) -ne 4) { return $false }
    return $buf[0] -eq 0x50 -and $buf[1] -eq 0x4B -and $buf[2] -eq 0x03 -and $buf[3] -eq 0x04
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
$filesPath = Join-Path $repo 'src/server/game-data/files.ts'
$generalPath = Join-Path $repo 'src/server/file-generators/general.json.ts'
$fileGeneratorsPath = Join-Path $repo 'src/server/file-generators/index.ts'
$dependenciesPath = Join-Path $repo 'src/server/file-generators/dependencies.json.ts'
$partyHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$joinHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/join.ts'
$protocolPath = Join-Path $repo 'src/server/socket-server/handlers/protocol.ts'
$xtHandlerPath = Join-Path $repo 'src/server/socket-server/xt-handler.ts'
$timelinePath = Join-Path $repo 'src/client/views/timeline/timeline-static.ts'
$timelineHtmlPath = Join-Path $repo 'src/client/views/timeline/timeline.html'
$assetRoot = Join-Path $canonical 'media/default/party2015'
$manifestPath = Join-Path $assetRoot 'manifest.json'
$canonicalManifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'

foreach ($requiredPath in @($updatePath,$filesPath,$generalPath,$fileGeneratorsPath,$dependenciesPath,$partyHandlersPath,$joinHandlersPath,$protocolPath,$xtHandlerPath,$timelinePath,$timelineHtmlPath,$manifestPath,$canonicalManifestPath)) {
  Assert (Test-Path -LiteralPath $requiredPath -PathType Leaf) "missing=$requiredPath"
}

$updates = [IO.File]::ReadAllText($updatePath)
$files = [IO.File]::ReadAllText($filesPath)
$general = [IO.File]::ReadAllText($generalPath)
$fileGenerators = [IO.File]::ReadAllText($fileGeneratorsPath)
$dependencies = [IO.File]::ReadAllText($dependenciesPath)
$partyHandlers = [IO.File]::ReadAllText($partyHandlersPath)
$joinHandlers = [IO.File]::ReadAllText($joinHandlersPath)
$protocol = [IO.File]::ReadAllText($protocolPath)
$xtHandler = [IO.File]::ReadAllText($xtHandlerPath)
$timeline = [IO.File]::ReadAllText($timelinePath)
$timelineHtml = [IO.File]::ReadAllText($timelineHtmlPath)

Assert ($updates.Contains("date: '2015-10-21'")) 'party_start_missing'
Assert ($updates.Contains("partyName: 'Halloween Party 2015'")) 'party_name_missing'
Assert ($updates.Contains("activeFeatures: '20150501'")) 'activefeatures_20150501_missing'
Assert ($updates.Contains("date: '2015-11-05'")) 'party_exclusive_end_date_missing'
Assert ($updates.Contains("partyEndDate: '2015-11-05 00:00:00'")) 'partyservice_end_missing'
Assert ($updates.Contains("end: ['party']")) 'party_end_missing'
Assert ($files.Contains("const PARTY2015 = 'party2015';")) 'party2015_fileref_constant_missing'
Assert ($timeline.Contains('getDateFromDateInfo(days[days.length - 1])')) 'dynamic_timeline_end_missing'
Assert ($timelineHtml.Contains('<option>2015</option>')) 'timeline_2015_option_missing'

foreach ($route in @(
  "'play/en/web_service/game_configs.bin': P + 'game_configs/game_configs.bin'",
  "'play/v2/client/QuestCommunicator.swf': P + 'client/QuestCommunicator.swf'",
  "'play/v2/content/global/content/party.swf': P + 'content/party.swf'",
  "'play/v2/content/global/content/map.swf': P + 'content/map.swf'",
  "'play/v2/client/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/features.swf': P + 'content/ContentFeatures-HalloweenParty2015.swf'",
  "'play/v2/content/global/content/party_icon.swf': P + 'content/ContentParty_icon-HalloweenParty2015.swf'",
  "'play/v2/content/global/logo/logo.swf': P + 'content/ContentLogo-HalloweenParty2015.swf'"
)) { Assert ($updates.Contains($route)) "route_missing=$route" }
Assert (-not $updates.Contains("'play/v2/content/global/content/logo.swf'")) 'legacy_wrong_logo_route_present'
Assert ($updates.Contains("'w.p2015.may.partymap'")) 'map_global_path_missing'
Assert ($updates.Contains("'w.p2015.may.partyinterface'")) 'quest_global_path_missing'
Assert ($updates.Contains("'w.p2015.may.login'")) 'login_global_path_missing'
Assert ($updates.Contains("'halloHerbertGame'")) 'herbert_game_global_path_missing'
Assert ($general.Contains('"hunt_active": hunt !== null || fair || d.getPartyIcon() || modernPartyIconActive')) 'hunt_not_modern_party_driven'
Assert ($general.Contains('"party_icon_active": modernPartyIconActive')) 'party_icon_option_not_dynamic'
Assert ($fileGenerators.Contains('...Object.fromEntries(d.getGlobalPaths())')) 'global_paths_not_merged_into_paths_json'
Assert ($fileGenerators.Contains("'play/en/web_service/game_configs/paths.json': getRuntimePathsJson")) 'runtime_paths_generator_not_registered'
Assert ($dependencies -match '(?s)const DEPENDENCIES_VANILLA = \{.*?"boot"\s*:\s*\[.*?"id"\s*:\s*"party"') 'modern_party_boot_dependency_missing'
Assert ($partyHandlers.Contains("await ctx.msg.send(ctx.penguin, 'activefeatures'")) 'party_activefeatures_bootstrap_missing'
Assert ($partyHandlers.Contains("await sendCurrentPartyCookie(ctx);`n  await sendCurrentPartyService(ctx);")) 'party_cookie_service_order_missing'
Assert ($joinHandlers.Contains('await sendModernPartyBootstrap(ctx);')) 'join_eager_party_bootstrap_missing'
Assert ($protocol.Contains("action: 's%party#partycookie'")) 'party_cookie_selector_compatibility_missing'
Assert ($protocol.Contains("exactArguments: ['0']")) 'party_cookie_fixed_selector_missing'
Assert ($protocol.Contains("'s%nx#bimp'")) 'map_impression_telemetry_missing'
foreach ($alias in @('halloween#partycookie','halloween#msgviewed','halloween#qcmsgviewed','halloween#qtaskcomplete','halloween#qtupdate')) {
  Assert ($xtHandler.Contains($alias)) "native_namespace_alias_missing=$alias"
}

# The archive-page manifest describes exactly the 132 original visual/event SWFs.
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert ([int]$manifest.requiredCount -eq 132) "manifest_required_count=$($manifest.requiredCount) expected=132"
$manifestByRelative = @{}
foreach ($asset in @($manifest.assets)) {
  $rel = ([string]$asset.relativePath).Replace('\\','/')
  if (-not [string]::IsNullOrWhiteSpace($rel)) { $manifestByRelative[$rel.ToLowerInvariant()] = $asset }
}
$requiredManifest = @($manifest.assets | Where-Object { [bool]$_.required })
Assert ($requiredManifest.Count -eq 132) "manifest_required_entries=$($requiredManifest.Count) expected=132"

# 2015.ts additionally routes exactly three preserved runtime SWFs. Keep them
# outside the historical 132 count so the provenance of both layers stays clear.
$matches = [regex]::Matches($updates, "P\s*\+\s*'([^']+\.swf)'", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$refs = @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$runtimeSwfRefs = @('content/party.swf','content/map.swf','client/QuestCommunicator.swf')
$coreRefs = @($refs | Where-Object { $runtimeSwfRefs -notcontains $_ })
Assert ($refs.Count -eq 135) "all_swf_ref_count=$($refs.Count) expected=135"
Assert ($coreRefs.Count -eq 132) "historical_swf_ref_count=$($coreRefs.Count) expected=132"
foreach ($runtimeRef in $runtimeSwfRefs) { Assert ($refs -contains $runtimeRef) "runtime_ref_missing=$runtimeRef" }

$missing = New-Object System.Collections.Generic.List[string]
$invalid = New-Object System.Collections.Generic.List[string]
$manifestMissing = New-Object System.Collections.Generic.List[string]
foreach ($ref in $coreRefs) {
  $relative = $ref.Replace('\\','/')
  $path = Join-Path $assetRoot $relative.Replace('/','\\')
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add($relative) | Out-Null; continue }
  if (-not (Test-Swf $path)) { $invalid.Add($relative) | Out-Null }
  if (-not $manifestByRelative.ContainsKey($relative.ToLowerInvariant())) { $manifestMissing.Add($relative) | Out-Null }
}
Assert ($missing.Count -eq 0) "missing_historical_assets=$($missing.Count) files=$($missing -join ',')"
Assert ($invalid.Count -eq 0) "invalid_historical_assets=$($invalid.Count) files=$($invalid -join ',')"
Assert ($manifestMissing.Count -eq 0) "manifest_missing_historical_assets=$($manifestMissing.Count) files=$($manifestMissing -join ',')"

$requiredPaths = @($requiredManifest | ForEach-Object { ([string]$_.relativePath).Replace('\\','/') } | Sort-Object -Unique)
$notReferenced = @($requiredPaths | Where-Object { $coreRefs -notcontains $_ })
Assert ($notReferenced.Count -eq 0) "required_not_referenced=$($notReferenced.Count) files=$($notReferenced -join ',')"

# The canonical supplement manifest is immutable and byte-verifiable.
$canonicalManifest = Get-Content -LiteralPath $canonicalManifestPath -Raw | ConvertFrom-Json
Assert ($canonicalManifest.schema -eq 'waddle-canonical-assets/v1') "canonical_schema=$($canonicalManifest.schema)"
$canonicalAssets = @($canonicalManifest.assets)
Assert ($canonicalAssets.Count -eq 11) "canonical_asset_count=$($canonicalAssets.Count) expected=11"
$canonicalMissing = New-Object System.Collections.Generic.List[string]
foreach ($entry in $canonicalAssets) {
  $target = [string]$entry.target
  $path = Join-Path $assetRoot $target.Replace('/','\\')
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $canonicalMissing.Add($target) | Out-Null; continue }
  $item = Get-Item -LiteralPath $path
  Assert ([long]$item.Length -eq [long]$entry.bytes) "canonical_bytes target=$target expected=$($entry.bytes) actual=$($item.Length)"
  Assert ((Get-GitBlobSha $path) -eq ([string]$entry.gitBlobSha).ToLowerInvariant()) "canonical_blob target=$target"
  if ([string]$entry.kind -eq 'swf') { Assert (Test-Swf $path) "canonical_swf target=$target" }
  if ([string]$entry.kind -eq 'zip-config') { Assert (Test-ZipConfig $path) "canonical_zip target=$target" }
}
Assert ($canonicalMissing.Count -eq 0) "canonical_missing=$($canonicalMissing.Count) files=$($canonicalMissing -join ',')"

$gameConfigs = Join-Path $assetRoot 'game_configs/game_configs.bin'
Assert (Test-ZipConfig $gameConfigs) 'game_configs_bin_not_zip'
Assert ((Get-Item -LiteralPath $gameConfigs).Length -eq 232384) 'game_configs_bin_size_mismatch'

$allSwfs = @(Get-ChildItem -LiteralPath $assetRoot -Filter '*.swf' -File -Recurse)
Assert ($allSwfs.Count -eq 135) "physical_swfs=$($allSwfs.Count) expected=135"

$roomRefs = @($coreRefs | Where-Object { $_ -like 'rooms/*' })
$musicRefs = @($coreRefs | Where-Object { $_ -like 'music/*' })
$closeUpRefs = @($coreRefs | Where-Object { $_ -like 'close_ups/*' })
Assert ($roomRefs.Count -eq 41) "room_ref_count=$($roomRefs.Count) expected=41"
Assert ($musicRefs.Count -eq 38) "music_ref_count=$($musicRefs.Count) expected=38"
Assert ($closeUpRefs.Count -eq 44) "close_up_ref_count=$($closeUpRefs.Count) expected=44"

Write-Host "WADDLE_PARTY2015_VERIFY=PASS historical_swfs=132 runtime_swfs=3 total_swfs=135 canonical_assets=11 game_configs_bin=true quest_communicator=true party_runtime=true party_map=true rooms=$($roomRefs.Count) music=$($musicRefs.Count) closeups=$($closeUpRefs.Count) activefeatures=20150501 partyservice=true halloween_namespace=true bimp_telemetry=true global_paths=true exclusive_end=2015-11-05 root=$assetRoot"
