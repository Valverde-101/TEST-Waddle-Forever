[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-GitBlobSha([string]$Path) {
  $payload = [IO.File]::ReadAllBytes($Path)
  $prefix = [Text.Encoding]::UTF8.GetBytes("blob $($payload.Length)`0")
  $all = New-Object byte[] ($prefix.Length + $payload.Length)
  [Buffer]::BlockCopy($prefix, 0, $all, 0, $prefix.Length)
  [Buffer]::BlockCopy($payload, 0, $all, $prefix.Length, $payload.Length)
  $sha1 = [Security.Cryptography.SHA1]::Create()
  try {
    return (($sha1.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha1.Dispose()
  }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 8) { return $false }
    $header = New-Object byte[] 3
    if ($stream.Read($header, 0, 3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($header)
  } finally {
    $stream.Dispose()
  }
}

function Test-ZipConfig([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 4) { return $false }
    $header = New-Object byte[] 4
    if ($stream.Read($header,0,4) -ne 4) { return $false }
    return $header[0] -eq 0x50 -and $header[1] -eq 0x4B -and $header[2] -eq 0x03 -and $header[3] -eq 0x04
  } finally {
    $stream.Dispose()
  }
}

function Test-CanonicalAsset($Entry,[string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $item = Get-Item -LiteralPath $Path
  if ([long]$item.Length -ne [long]$Entry.bytes) { return $false }

  if ($Entry.PSObject.Properties.Name -contains 'sha256' -and -not [string]::IsNullOrWhiteSpace([string]$Entry.sha256)) {
    if ((Get-Sha256 $Path) -ne ([string]$Entry.sha256).ToLowerInvariant()) { return $false }
  } elseif ($Entry.PSObject.Properties.Name -contains 'gitBlobSha' -and -not [string]::IsNullOrWhiteSpace([string]$Entry.gitBlobSha)) {
    if ((Get-GitBlobSha $Path) -ne ([string]$Entry.gitBlobSha).ToLowerInvariant()) { return $false }
  } else {
    return $false
  }

  if ([string]$Entry.kind -eq 'swf' -and -not (Test-Swf $Path)) { return $false }
  if ([string]$Entry.kind -eq 'zip-config' -and -not (Test-ZipConfig $Path)) { return $false }
  return $true
}

function Escape-Path([string]$Path) {
  return (($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

function Get-CanonicalUrl($Entry,$Manifest) {
  if ($Entry.PSObject.Properties.Name -contains 'sourceUrl' -and -not [string]::IsNullOrWhiteSpace([string]$Entry.sourceUrl)) {
    $uri = [Uri]([string]$Entry.sourceUrl)
    if ($uri.Scheme -ne 'https') { throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL insecure_source=$($Entry.sourceUrl)" }
    return $uri.AbsoluteUri
  }
  if (-not ($Entry.PSObject.Properties.Name -contains 'sourcePath') -or [string]::IsNullOrWhiteSpace([string]$Entry.sourcePath)) {
    throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL source_missing=$($Entry.target)"
  }
  $encodedPath = Escape-Path ([string]$Entry.sourcePath)
  return "https://raw.githubusercontent.com/$($Manifest.sourceRepository)/$($Manifest.sourceCommit)/$encodedPath"
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
  $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/halloween-2015-canonical.json'
}
$manifestPathResolved = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction SilentlyContinue).Path
if (-not $manifestPathResolved -or -not (Test-Path -LiteralPath $manifestPathResolved -PathType Leaf)) {
  throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL manifest_missing=$ManifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPathResolved -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'waddle-canonical-assets/v1') {
  throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL schema=$($manifest.schema)"
}
if (-not $manifest.sourceRepository -or -not $manifest.sourceCommit) {
  throw 'WADDLE_HALLOWEEN2015_CANONICAL=FAIL source_identity_missing'
}
$assets = @($manifest.assets)
if ($assets.Count -lt 1) {
  throw 'WADDLE_HALLOWEEN2015_CANONICAL=FAIL asset_count=0'
}
[string[]]$targets = @($assets | ForEach-Object { [string]$_.target })
$targetSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($target in $targets) {
  if (-not $targetSet.Add($target)) {
    throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL duplicate_target=$target"
  }
}

$targetRoot = Join-Path $repo 'media/default/party2015'
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
$headers = @{
  'User-Agent' = 'Waddle-Forever-Halloween2015-Canonical/2.3'
  'Accept' = 'application/octet-stream,*/*'
}
$downloaded = 0
$reused = 0
$verified = 0

foreach ($entry in $assets) {
  $relativeTarget = ([string]$entry.target).Replace('/', [IO.Path]::DirectorySeparatorChar)
  $final = Join-Path $targetRoot $relativeTarget
  $parent = Split-Path -Parent $final
  New-Item -ItemType Directory -Force -Path $parent | Out-Null

  if (Test-CanonicalAsset $entry $final) {
    $reused++
    $verified++
    continue
  }

  $url = Get-CanonicalUrl $entry $manifest
  $tmp = $final + '.part'
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $ok = $false
  for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -OutFile $tmp -TimeoutSec 120
      if (-not (Test-CanonicalAsset $entry $tmp)) {
        $actualBytes = if (Test-Path -LiteralPath $tmp) { (Get-Item -LiteralPath $tmp).Length } else { 0 }
        $actualSha256 = if (Test-Path -LiteralPath $tmp) { Get-Sha256 $tmp } else { '' }
        $actualBlob = if (Test-Path -LiteralPath $tmp) { Get-GitBlobSha $tmp } else { '' }
        throw "verification_mismatch expected_bytes=$($entry.bytes) actual_bytes=$actualBytes actual_sha256=$actualSha256 actual_blob=$actualBlob"
      }
      Move-Item -LiteralPath $tmp -Destination $final -Force
      $ok = $true
    } catch {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      if ($attempt -eq 3) {
        throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL target=$($entry.target) source=$url error=$($_.Exception.Message)"
      }
      Start-Sleep -Seconds (2 * $attempt)
    }
  }
  if (-not (Test-CanonicalAsset $entry $final)) {
    throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL post_download_verify=$($entry.target)"
  }
  $downloaded++
  $verified++
}

# Sort with an explicit ordinal comparer. PowerShell Sort-Object is
# culture-sensitive, so punctuation such as '-' vs '.' can be ordered
# differently across runners and create byte-level drift in canonical-state.json.
[string[]]$sortedTargets = @($targets)
[Array]::Sort($sortedTargets, [StringComparer]::Ordinal)

$state = [ordered]@{
  schema = 'waddle-canonical-assets-state/v2'
  party = [string]$manifest.party
  sourceRepository = [string]$manifest.sourceRepository
  sourceCommit = [string]$manifest.sourceCommit
  verified = $verified
  assetTargets = $sortedTargets
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
# Compact JSON is the canonical on-disk representation. Windows PowerShell 5
# otherwise emits version-specific alignment whitespace, which can create a
# false generated-drift failure even when the state is semantically identical.
$stateJson = ($state | ConvertTo-Json -Depth 5 -Compress) -replace "`r`n", "`n"
$statePath = Join-Path $targetRoot 'canonical-state.json'
$statePayload = $stateJson + "`n"
[IO.File]::WriteAllText($statePath, $statePayload, $utf8)

# Report the exact deterministic artifact identity. If this ever drifts again,
# CI can distinguish content drift from a line-ending/encoding issue immediately.
$stateSha256 = (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash.ToLowerInvariant()
$stateBytes = (Get-Item -LiteralPath $statePath).Length
Write-Host "WADDLE_HALLOWEEN2015_CANONICAL_STATE=PASS bytes=$stateBytes sha256=$stateSha256 sort=ordinal encoding=utf8-nobom newline=lf"

Write-Host "WADDLE_HALLOWEEN2015_CANONICAL=PASS assets=$verified downloaded=$downloaded reused=$reused source=$($manifest.sourceRepository)@$($manifest.sourceCommit) manifest=$manifestPathResolved target=$targetRoot state=deterministic"
