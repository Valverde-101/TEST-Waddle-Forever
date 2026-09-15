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

$roomSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$roomNames | ForEach-Object { [void]$roomSet.Add($_) }
function Get-Category([string]$Name) {
  if ($roomSet.Contains($Name)) { return 'rooms' }
  if ($Name -eq 'PenguinRobot.swf') { return 'avatar' }
  if ($Name -like 'Client*') { return 'client' }
  if ($Name -like 'Content*') { return 'content' }
  if ($Name -like 'Membership*') { return 'membership' }
  if ($Name -like 'Music*.swf') { return 'music' }
  if ($Name -like 'Telescope*' -or $Name -like 'Binoculars*') { return 'other' }
  return 'close_ups'
}

$pages = @(
  'https://archives.clubpenguinwiki.info/wiki/Halloween_Party_2015',
  'https://toolbox.solero.me/cparchives/wiki/Halloween_Party_2015.html'
)
$headers = @{
  'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Waddle-Forever-Halloween2015/2.0'
  'Accept' = 'text/html,application/xhtml+xml,*/*'
}
$html = $null
$pageUsed = $null
foreach ($page in $pages) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $page -Headers $headers -TimeoutSec 45
    if ($response.Content -and $response.Content.Length -gt 1000) {
      $html = $response.Content
      $pageUsed = $page
      break
    }
  } catch {
    Write-Host "WADDLE_PARTY2015_ARCHIVE_PAGE=WARN url=$page error=$($_.Exception.Message)"
  }
}
if (-not $html) { throw 'WADDLE_PARTY2015_ASSETS=FAIL archive_page_unavailable' }

$linkMap = @{}
$matches = [regex]::Matches($html, 'href=["'']([^"'']+\.swf(?:\?[^"'']*)?)["'']', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
foreach ($match in $matches) {
  $href = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
  try {
    $absolute = [Uri]::new([Uri]$pageUsed,$href).AbsoluteUri
    $uri = [Uri]$absolute
    $name = [Uri]::UnescapeDataString([IO.Path]::GetFileName($uri.AbsolutePath))
    if ($name -and $name.EndsWith('.swf',[StringComparison]::OrdinalIgnoreCase) -and -not $linkMap.ContainsKey($name)) {
      $linkMap[$name] = $absolute
    }
  } catch {}
}

$missing = @($required | Where-Object { -not $linkMap.ContainsKey($_) })
if ($missing.Count -gt 0) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL archive_missing_required count=$($missing.Count) names=$($missing -join ',')"
}

# Download every unique SWF linked from the archive page, while requiring the complete known 132-file inventory.
$assetNames = @($linkMap.Keys | Sort-Object)
if ($assetNames.Count -lt 132) {
  throw "WADDLE_PARTY2015_ASSETS=FAIL archive_links_too_few count=$($assetNames.Count) expected_at_least=132"
}

$downloaded = 0
$reused = 0
$manifestAssets = New-Object System.Collections.Generic.List[object]
foreach ($name in $assetNames) {
  $category = Get-Category $name
  $dir = Join-Path $target $category
  $final = Join-Path $dir $name
  $url = $linkMap[$name]
  if (Test-Swf $final) {
    $reused++
  } else {
    $tmp = $final + '.part'
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $ok = $false
    for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -OutFile $tmp -TimeoutSec 90
        if (-not (Test-Swf $tmp)) { throw 'downloaded payload is not a valid SWF' }
        Move-Item -LiteralPath $tmp -Destination $final -Force
        $ok = $true
      } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if ($attempt -eq 3) { throw "WADDLE_PARTY2015_ASSETS=FAIL file=$name url=$url error=$($_.Exception.Message)" }
        Start-Sleep -Seconds (2 * $attempt)
      }
    }
    $downloaded++
  }
  if (-not (Test-Swf $final)) { throw "WADDLE_PARTY2015_ASSETS=FAIL invalid_after_download=$final" }
  $item = Get-Item -LiteralPath $final
  $sha = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
  $manifestAssets.Add([pscustomobject]@{
    category = $category
    name = $name
    relativePath = "$category/$name"
    url = $url
    bytes = [long]$item.Length
    sha256 = $sha
    required = ($required -contains $name)
  }) | Out-Null
}

foreach ($requiredName in $required) {
  $category = Get-Category $requiredName
  $path = Join-Path (Join-Path $target $category) $requiredName
  if (-not (Test-Swf $path)) { throw "WADDLE_PARTY2015_ASSETS=FAIL required_invalid=$requiredName" }
}

$manifest = [ordered]@{
  schema = 2
  party = 'Halloween Party 2015'
  sourcePage = $pageUsed
  canonicalRoot = $target
  requiredCount = 132
  total = $manifestAssets.Count
  downloaded = $downloaded
  reused = $reused
  generatedAt = [DateTime]::UtcNow.ToString('o')
  assets = $manifestAssets
}
$manifestPath = Join-Path $target 'manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "WADDLE_PARTY2015_ASSETS=PASS required=132 total=$($manifestAssets.Count) downloaded=$downloaded reused=$reused root=$target source=$pageUsed"
