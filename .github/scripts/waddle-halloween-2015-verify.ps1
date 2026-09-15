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
  $item = Get-Item -LiteralPath $Path
  if ($item.Length -lt 100) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    $buf = New-Object byte[] 3
    if ($stream.Read($buf,0,3) -ne 3) { return $false }
    $sig = [Text.Encoding]::ASCII.GetString($buf)
    return @('FWS','CWS','ZWS') -contains $sig
  } finally {
    $stream.Dispose()
  }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$canonical = (Resolve-Path -LiteralPath $CanonicalRoot).Path
$updatePath = Join-Path $repo 'src/server/updates/2015.ts'
$filesPath = Join-Path $repo 'src/server/game-data/files.ts'
$generalPath = Join-Path $repo 'src/server/file-generators/general.json.ts'
$fileGeneratorsPath = Join-Path $repo 'src/server/file-generators/index.ts'
$dependenciesPath = Join-Path $repo 'src/server/file-generators/dependencies.json.ts'
$partyHandlersPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$timelinePath = Join-Path $repo 'src/client/views/timeline/timeline-static.ts'
$timelineHtmlPath = Join-Path $repo 'src/client/views/timeline/timeline.html'
$assetRoot = Join-Path $canonical 'media/default/party2015'
$manifestPath = Join-Path $assetRoot 'manifest.json'
$runtimePath = Join-Path $repo 'media/default/archives/PartyRuntime-CPImagined-HalloweenClassic.swf'

Assert (Test-Path -LiteralPath $updatePath -PathType Leaf) "updates_missing=$updatePath"
Assert (Test-Path -LiteralPath $filesPath -PathType Leaf) "files_registry_missing=$filesPath"
Assert (Test-Path -LiteralPath $generalPath -PathType Leaf) "general_generator_missing=$generalPath"
Assert (Test-Path -LiteralPath $fileGeneratorsPath -PathType Leaf) "file_generators_missing=$fileGeneratorsPath"
Assert (Test-Path -LiteralPath $dependenciesPath -PathType Leaf) "dependencies_generator_missing=$dependenciesPath"
Assert (Test-Path -LiteralPath $partyHandlersPath -PathType Leaf) "party_handlers_missing=$partyHandlersPath"
Assert (Test-Path -LiteralPath $timelinePath -PathType Leaf) "timeline_missing=$timelinePath"
Assert (Test-Path -LiteralPath $timelineHtmlPath -PathType Leaf) "timeline_html_missing=$timelineHtmlPath"
Assert (Test-Path -LiteralPath $manifestPath -PathType Leaf) "manifest_missing=$manifestPath"
Assert (Test-Swf $runtimePath) "modern_party_runtime_invalid=$runtimePath"

$updates = [IO.File]::ReadAllText($updatePath)
$files = [IO.File]::ReadAllText($filesPath)
$general = [IO.File]::ReadAllText($generalPath)
$fileGenerators = [IO.File]::ReadAllText($fileGeneratorsPath)
$dependencies = [IO.File]::ReadAllText($dependenciesPath)
$partyHandlers = [IO.File]::ReadAllText($partyHandlersPath)
$timeline = [IO.File]::ReadAllText($timelinePath)
$timelineHtml = [IO.File]::ReadAllText($timelineHtmlPath)

Assert ($updates.Contains("date: '2015-10-21'")) 'party_start_missing'
Assert ($updates.Contains("partyName: 'Halloween Party 2015'")) 'party_name_missing'
Assert ($updates.Contains("activeFeatures: '20150501'")) 'activefeatures_20150501_missing'
Assert ($updates.Contains("date: '2015-11-05'")) 'party_exclusive_end_date_missing'
Assert ($updates.Contains("partyEndDate: '2015-11-05 00:00:00'")) 'partyservice_end_missing'
Assert ($updates.Contains("end: ['party']")) 'party_end_missing'
Assert ($files.Contains("const PARTY2015 = 'party2015';")) 'party2015_fileref_constant_missing'
Assert ($files.Contains('  PARTY2015,')) 'party2015_fileref_registry_missing'
Assert ($timeline.Contains('getDateFromDateInfo(days[days.length - 1])')) 'dynamic_timeline_end_missing'
Assert ($timelineHtml.Contains('<option>2015</option>')) 'timeline_2015_option_missing'

Assert ($updates.Contains("'play/v2/content/global/content/interface.swf': P + 'client/ClientInterface-HalloweenParty2015.swf'")) 'modern_interface_route_missing'
Assert (-not $updates.Contains("'play/v2/client/interface.swf'")) 'legacy_wrong_interface_route_present'
Assert ($updates.Contains("'play/v2/content/global/content/features.swf': P + 'content/ContentFeatures-HalloweenParty2015.swf'")) 'modern_features_route_missing'
Assert ($updates.Contains("'play/v2/content/global/logo/logo.swf': P + 'content/ContentLogo-HalloweenParty2015.swf'")) 'modern_logo_route_missing'
Assert (-not $updates.Contains("'play/v2/content/global/content/logo.swf'")) 'legacy_wrong_logo_route_present'
Assert ($updates.Contains("'play/v2/content/global/content/party_icon.swf': P + 'content/ContentParty_icon-HalloweenParty2015.swf'")) 'modern_party_icon_route_missing'
Assert ($updates.Contains("'play/v2/content/global/content/party.swf': 'archives:PartyRuntime-CPImagined-HalloweenClassic.swf'")) 'modern_party_runtime_route_missing'
Assert (-not $updates.Contains('PartyRuntime-CPImaginedReference.swf')) 'runtime_leaked_into_party2015_inventory'
Assert ($updates.Contains("'w.p2015.may.partyinterface'")) 'quest_global_path_missing'
Assert ($updates.Contains("'w.p2015.may.login'")) 'login_global_path_missing'
Assert ($updates.Contains("'halloHerbertGame'")) 'herbert_game_global_path_missing'
Assert ($general.Contains("d.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined")) 'party_icon_activation_not_route_driven'
Assert ($general.Contains('"party_icon_active": modernPartyIconActive')) 'party_icon_option_not_dynamic'
Assert ($fileGenerators.Contains('...Object.fromEntries(d.getGlobalPaths())')) 'global_paths_not_merged_into_paths_json'
Assert ($fileGenerators.Contains("'play/en/web_service/game_configs/paths.json': getRuntimePathsJson")) 'runtime_paths_generator_not_registered'
Assert ($dependencies -match '(?s)const DEPENDENCIES_VANILLA = \{.*?"boot"\s*:\s*\[.*?"id"\s*:\s*"party"') 'modern_party_boot_dependency_missing'
Assert ($partyHandlers.Contains("await sendCurrentPartyCookie(ctx);`n  await sendCurrentPartyService(ctx);")) 'party_cookie_service_order_missing'
Assert ($partyHandlers.Contains("action: 'partycookie-partyservice'")) 'party_bootstrap_trace_missing'

$matches = [regex]::Matches($updates, "P\s*\+\s*'([^']+\.swf)'", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$refs = @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert ($refs.Count -eq 132) "source_ref_count=$($refs.Count) expected=132"

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert ([int]$manifest.requiredCount -eq 132) "manifest_required_count=$($manifest.requiredCount) expected=132"
Assert ([int]$manifest.total -ge 132) "manifest_total=$($manifest.total) expected_at_least=132"

$manifestByRelative = @{}
foreach ($asset in @($manifest.assets)) {
  $rel = ([string]$asset.relativePath).Replace('\\','/')
  if (-not [string]::IsNullOrWhiteSpace($rel)) { $manifestByRelative[$rel.ToLowerInvariant()] = $asset }
}

$missing = New-Object System.Collections.Generic.List[string]
$invalid = New-Object System.Collections.Generic.List[string]
$manifestMissing = New-Object System.Collections.Generic.List[string]
foreach ($ref in $refs) {
  $relative = $ref.Replace('\\','/')
  $path = Join-Path $assetRoot $relative.Replace('/','\\')
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $missing.Add($relative) | Out-Null
    continue
  }
  if (-not (Test-Swf $path)) {
    $invalid.Add($relative) | Out-Null
  }
  if (-not $manifestByRelative.ContainsKey($relative.ToLowerInvariant())) {
    $manifestMissing.Add($relative) | Out-Null
  }
}

Assert ($missing.Count -eq 0) "missing_routed_assets=$($missing.Count) files=$($missing -join ',')"
Assert ($invalid.Count -eq 0) "invalid_routed_assets=$($invalid.Count) files=$($invalid -join ',')"
Assert ($manifestMissing.Count -eq 0) "manifest_missing_routed_assets=$($manifestMissing.Count) files=$($manifestMissing -join ',')"

$requiredManifest = @($manifest.assets | Where-Object { [bool]$_.required })
Assert ($requiredManifest.Count -eq 132) "manifest_required_entries=$($requiredManifest.Count) expected=132"

$requiredPaths = @($requiredManifest | ForEach-Object { ([string]$_.relativePath).Replace('\\','/') } | Sort-Object -Unique)
$notReferenced = @($requiredPaths | Where-Object { $refs -notcontains $_ })
Assert ($notReferenced.Count -eq 0) "required_not_referenced=$($notReferenced.Count) files=$($notReferenced -join ',')"

$roomRefs = @($refs | Where-Object { $_ -like 'rooms/*' })
$musicRefs = @($refs | Where-Object { $_ -like 'music/*' })
$closeUpRefs = @($refs | Where-Object { $_ -like 'close_ups/*' })
Assert ($roomRefs.Count -eq 41) "room_ref_count=$($roomRefs.Count) expected=41"
Assert ($musicRefs.Count -eq 38) "music_ref_count=$($musicRefs.Count) expected=38"
Assert ($closeUpRefs.Count -eq 44) "close_up_ref_count=$($closeUpRefs.Count) expected=44"

$runtimeInfo = Get-Item -LiteralPath $runtimePath
$runtimeSha = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash
Write-Host "WADDLE_PARTY2015_VERIFY=PASS source_refs=132 rooms=$($roomRefs.Count) music=$($musicRefs.Count) closeups=$($closeUpRefs.Count) manifest_total=$($manifest.total) runtime_bytes=$($runtimeInfo.Length) runtime_sha256=$runtimeSha activefeatures=20150501 partyservice=true global_paths=true exclusive_end=2015-11-05 root=$assetRoot"
