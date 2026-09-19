param(
  [ValidateSet('assets')][string]$Mode = 'assets',
  [string]$RepoRoot = $env:GITHUB_WORKSPACE
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
  } finally { $stream.Dispose() }
}

$canonical = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $canonical '.git'))) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL canonical_repo_missing=$canonical"
}
$target = Join-Path $canonical 'media/default/party2015'
$categories = @('rooms','avatar','client','close_ups','content','membership','other','music')
foreach ($category in $categories) {
  New-Item -ItemType Directory -Force -Path (Join-Path $target $category) | Out-Null
}

$roomNames = @(
  'Hallo15_beach.swf','Hallo15_beacon.swf','Hallo15_book.swf','Hallo15_cave.swf','Hallo15_shop.swf','Hallo15_cloudforest.swf',
  'Hallo15_coffee.swf','Hallo15_cove.swf','Hallo15_dance.swf','Hallo15_dock.swf','Hallo15_dojo.swf','Hallo15_dojoext.swf',
  'Hallo15_agentlobbymulti.swf','Hallo15_dojofire.swf','Hallo15_forest.swf','Hallo15_party1.swf','Hallo15_partysolo1.swf','Hallo15_party2.swf',
  'Hallo15_berg.swf','Hallo15_light.swf','Hallo15_attic.swf','Hallo15_lounge.swf','Hallo15_shack.swf','Hallo15_pet.swf','Hallo15_pizza.swf',
  'Hallo15_plaza.swf','Hallo15_mall.swf','Hallo15_hotellobby.swf','Hallo15_hotelroof.swf','Hallo15_hotelspa.swf','Hallo15_park.swf',
  'Hallo15_pufflewild.swf','Hallo15_school.swf','Hallo15_skatepark.swf','Hallo15_mtn.swf','Hallo15_lodge.swf','Hallo15_village.swf',
  'Hallo15_dojosnow.swf','Hallo15_forts.swf','Hallo15_rink.swf','RoomsTown-HalloweenParty2015.swf'
)
$dialogues = @(
  'Hallo15_dialogue_login.swf',
  'Hallo15_dialogue_AA_start.swf','Hallo15_dialogue_AA_instruct.swf','Hallo15_dialogue_AA_congrats.swf',
  'Hallo15_dialogue_Cad_start.swf','Hallo15_dialogue_Cad_instruct.swf','Hallo15_dialogue_Cad_congrats.swf',
  'Hallo15_dialogue_Dot_start.swf','Hallo15_dialogue_Dot_instruct.swf','Hallo15_dialogue_Dot_congrats.swf',
  'Hallo15_dialogue_PH_start.swf','Hallo15_dialogue_PH_instruct.swf','Hallo15_dialogue_PH_congrats.swf',
  'Hallo15_dialogue_RH_start.swf','Hallo15_dialogue_RH_instruct.swf','Hallo15_dialogue_RH_congrats.swf',
  'Hallo15_dialogue_Rook_start.swf','Hallo15_dialogue_Rook_instruct.swf','Hallo15_dialogue_Rook_congrats.swf','Hallo15_dialogue_Rookie_bot.swf',
  'Hallo15_dialogue_Sen_start.swf','Hallo15_dialogue_Sen_instruct.swf','Hallo15_dialogue_Sen_congrats.swf',
  'Hallo15_dialogue_Gary_instruct.swf','Hallo15_dialogue_Gary_instruct_2.swf','Hallo15_dialogue_Gary_instruct_3.swf','Hallo15_dialogue_Gary_lair.swf','Hallo15_dialogue_Gary_congrats.swf','Hallo15_dialogue_Gary_final.swf',
  'Hallo15_dialogue_Herbert_caged.swf','Hallo15_dialogue_Herbert_escape.swf','Hallo15_dialogue_Herbot.swf','Hallo15_dialogue_Herbert_monologue.swf','Hallo15_dialogue_Herbert_monologue_2.swf'
)
$minigames = 0..8 | ForEach-Object { "Close_upsTiles_minigame$_-HalloweenParty2015.swf" }
$musicIds = @(345,403,532,588,659,669,838,884,922,1031,1032,1033,1034,1035,1036,1037,1038,1039,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1067)
$musicNames = $musicIds | ForEach-Object { "Music$_.swf" }
$required = @(
  $roomNames +
  @('PenguinRobot.swf','ClientInterface-HalloweenParty2015.swf') +
  $dialogues + $minigames +
  @('Close_upsQuest_interface-HalloweenParty2015.swf','ContentFeatures-HalloweenParty2015.swf','ContentLogo-HalloweenParty2015.swf','ContentParty_icon-HalloweenParty2015.swf','MembershipParty1-HalloweenParty2015.swf','MembershipParty2-HalloweenParty2015.swf','Telescope-HalloweenParty2015.swf','Binoculars-HalloweenParty2015.swf') +
  $musicNames
)
$required = @($required | Select-Object -Unique)
if ($required.Count -ne 132) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL inventory_count=$($required.Count) expected=132"
}

# The versioned manifest is the authoritative historical inventory. Do not
# rediscover the same files from a live wiki on every run: mirrors can change
# ordering, markup or availability without the party assets changing at all.
$manifestPath = Join-Path $target 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_missing=$manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([int]$manifest.schema -ne 3) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_schema=$($manifest.schema) expected=3"
}
if ([string]$manifest.party -ne 'Halloween Party 2015') {
  throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_party=$($manifest.party)"
}
if ([int]$manifest.requiredCount -ne 132) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_required=$($manifest.requiredCount) expected=132"
}

$manifestAssets = @($manifest.assets)
if ([int]$manifest.total -ne $manifestAssets.Count -or $manifestAssets.Count -ne 132) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_total=$($manifest.total) entries=$($manifestAssets.Count) expected=132"
}

$assetByName = @{}
$assetByPath = @{}
foreach ($entry in $manifestAssets) {
  $name = [string]$entry.name
  $relative = ([string]$entry.relativePath).Replace('\','/')
  $category = [string]$entry.category
  $url = [string]$entry.url
  $sha256 = [string]$entry.sha256

  if ([string]::IsNullOrWhiteSpace($name) -or -not $name.EndsWith('.swf',[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_invalid_name=$name"
  }
  if ($relative.StartsWith('/') -or $relative.Contains('../') -or $relative.Contains(':')) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_unsafe_relative=$relative"
  }
  if (-not $relative.Equals(($category.Trim('/') + '/' + $name),[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_path_mismatch name=$name relative=$relative category=$category"
  }
  if (-not $url.StartsWith('https://',[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_url=$url"
  }
  if ([long]$entry.bytes -lt 100 -or $sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_identity name=$name bytes=$($entry.bytes) sha256=$sha256"
  }
  if (-not [bool]$entry.required) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_nonrequired_entry=$name"
  }
  if ($assetByName.ContainsKey($name)) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_duplicate_name=$name"
  }
  if ($assetByPath.ContainsKey($relative)) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_duplicate_path=$relative"
  }
  $assetByName[$name] = $entry
  $assetByPath[$relative] = $entry
}

foreach ($requiredName in $required) {
  if (-not $assetByName.ContainsKey($requiredName)) {
    throw "WADDLE_PARTY2015_ASSETS=FAIL manifest_missing_required=$requiredName"
  }
}

[string[]]$relativePaths = @($assetByPath.Keys)
[Array]::Sort($relativePaths,[StringComparer]::Ordinal)

$headers = @{
  'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Waddle-Forever-Halloween2015/3.0'
  'Accept' = 'application/x-shockwave-flash,application/octet-stream,*/*'
}
$downloaded = 0
$reused = 0

foreach ($relative in $relativePaths) {
  $entry = $assetByPath[$relative]
  $final = Join-Path $target $relative.Replace('/','\')
  $expectedBytes = [long]$entry.bytes
  $expectedSha = ([string]$entry.sha256).ToUpperInvariant()

  if (Test-Path -LiteralPath $final -PathType Leaf) {
    if (-not (Test-Swf $final)) {
      throw "WADDLE_PARTY2015_ASSETS=FAIL tracked_invalid_swf=$relative"
    }
    $actualBytes = [long](Get-Item -LiteralPath $final).Length
    $actualSha = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualBytes -ne $expectedBytes -or $actualSha -ne $expectedSha) {
      throw "WADDLE_PARTY2015_ASSETS=FAIL tracked_identity_drift=$relative bytes=$actualBytes expected_bytes=$expectedBytes sha256=$actualSha expected_sha256=$expectedSha"
    }
    $reused++
    continue
  }

  # Missing files may be recovered, but only from the URL and identity already
  # pinned in Git. A mirror can never silently redefine an existing asset.
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $final) | Out-Null
  $tmp = $final + '.part'
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $ok = $false
  for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri ([string]$entry.url) -Headers $headers -OutFile $tmp -TimeoutSec 90
      if (-not (Test-Swf $tmp)) { throw 'downloaded payload is not a valid SWF' }
      $actualBytes = [long](Get-Item -LiteralPath $tmp).Length
      $actualSha = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToUpperInvariant()
      if ($actualBytes -ne $expectedBytes -or $actualSha -ne $expectedSha) {
        throw "identity mismatch bytes=$actualBytes expected_bytes=$expectedBytes sha256=$actualSha expected_sha256=$expectedSha"
      }
      Move-Item -LiteralPath $tmp -Destination $final -Force
      $ok = $true
    } catch {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      if ($attempt -eq 3) {
        throw "WADDLE_PARTY2015_ASSETS=FAIL recovery_failed=$relative url=$($entry.url) error=$($_.Exception.Message)"
      }
      Start-Sleep -Seconds (2 * $attempt)
    }
  }
  $downloaded++
}

$manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "WADDLE_PARTY2015_HISTORICAL_MANIFEST=PASS schema=3 assets=$($manifestAssets.Count) required=132 reused=$reused recovered=$downloaded sha256=$manifestSha source=$($manifest.sourcePage)"

# The wiki inventory is only the visual/event asset layer. Hydrate the preserved
# late-AS3 runtime/configuration supplements separately from an immutable Git commit
# and verify every byte using the versioned canonical manifest.
$canonicalHydrator = Join-Path $canonical '.github/scripts/waddle-halloween-2015-canonical.ps1'
if (-not (Test-Path -LiteralPath $canonicalHydrator -PathType Leaf)) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL canonical_hydrator_missing=$canonicalHydrator"
}
& $canonicalHydrator -RepoRoot $canonical
$canonicalStatePath = Join-Path $target 'canonical-state.json'
if (-not (Test-Path -LiteralPath $canonicalStatePath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL canonical_state_missing=$canonicalStatePath"
}
$canonicalState = Get-Content -LiteralPath $canonicalStatePath -Raw | ConvertFrom-Json
$canonicalSupplementCount = [int]$canonicalState.verified
if ($canonicalSupplementCount -ne @($canonicalState.assetTargets).Count) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL canonical_state_count verified=$canonicalSupplementCount targets=$(@($canonicalState.assetTargets).Count)"
}

# The archived Operation Crustacean runtime is a compatible late-2015 donor,
# but Halloween's Robot Rampage rooms call additional client-local APIs that
# the donor does not define. Keep the donor byte-exact and deterministically
# materialize the live compatibility runtime from it on the managed runner.
$runtimePatch = Join-Path $canonical '.github/scripts/waddle-halloween-2015-runtime-patch.ps1'
if (-not (Test-Path -LiteralPath $runtimePatch -PathType Leaf)) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL runtime_patch_missing=$runtimePatch"
}
& $runtimePatch -RepoRoot $canonical
if (-not $?) { throw 'WADDLE_PARTY2015_ASSETS=FAIL runtime_patch_failed' }

Write-Host "WADDLE_PARTY2015_ASSETS=PASS required=132 total=$($manifestAssets.Count) recovered=$downloaded reused=$reused canonical_supplements=$canonicalSupplementCount generated_runtime=1 root=$target source=$($manifest.sourcePage) architecture=manifest-driven"
