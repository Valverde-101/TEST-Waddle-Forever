[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

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

function Test-CanonicalAsset($Entry,[string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $item = Get-Item -LiteralPath $Path
  if ([long]$item.Length -ne [long]$Entry.bytes) { return $false }
  if ((Get-GitBlobSha $Path) -ne ([string]$Entry.gitBlobSha).ToLowerInvariant()) { return $false }
  if ([string]$Entry.kind -eq 'swf' -and -not (Test-Swf $Path)) { return $false }
  return $true
}

function Escape-Path([string]$Path) {
  return (($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$manifestPath = Join-Path $repo '.github/manifests/halloween-2015-canonical.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL manifest_missing=$manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'waddle-canonical-assets/v1') {
  throw "WADDLE_HALLOWEEN2015_CANONICAL=FAIL schema=$($manifest.schema)"
}
if (-not $manifest.sourceRepository -or -not $manifest.sourceCommit) {
  throw 'WADDLE_HALLOWEEN2015_CANONICAL=FAIL source_identity_missing'
}

$targetRoot = Join-Path $repo 'media/default/party2015'
New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
$headers = @{
  'User-Agent' = 'Waddle-Forever-Halloween2015-Canonical/1.0'
  'Accept' = 'application/octet-stream,*/*'
}
$downloaded = 0
$reused = 0
$verified = 0

foreach ($entry in @($manifest.assets)) {
  $relativeTarget = ([string]$entry.target).Replace('/', [IO.Path]::DirectorySeparatorChar)
  $final = Join-Path $targetRoot $relativeTarget
  $parent = Split-Path -Parent $final
  New-Item -ItemType Directory -Force -Path $parent | Out-Null

  if (Test-CanonicalAsset $entry $final) {
    $reused++
    $verified++
    continue
  }

  $encodedPath = Escape-Path ([string]$entry.sourcePath)
  $url = "https://raw.githubusercontent.com/$($manifest.sourceRepository)/$($manifest.sourceCommit)/$encodedPath"
  $tmp = $final + '.part'
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $ok = $false
  for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -OutFile $tmp -TimeoutSec 120
      if (-not (Test-CanonicalAsset $entry $tmp)) {
        $actualBytes = if (Test-Path -LiteralPath $tmp) { (Get-Item -LiteralPath $tmp).Length } else { 0 }
        $actualSha = if (Test-Path -LiteralPath $tmp) { Get-GitBlobSha $tmp } else { '' }
        throw "verification_mismatch expected_bytes=$($entry.bytes) actual_bytes=$actualBytes expected_blob=$($entry.gitBlobSha) actual_blob=$actualSha"
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

$state = [ordered]@{
  schema = 'waddle-canonical-assets-state/v1'
  party = $manifest.party
  sourceRepository = $manifest.sourceRepository
  sourceCommit = $manifest.sourceCommit
  verified = $verified
  downloaded = $downloaded
  reused = $reused
  generatedAt = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $targetRoot 'canonical-state.json') -Encoding UTF8

Write-Host "WADDLE_HALLOWEEN2015_CANONICAL=PASS assets=$verified downloaded=$downloaded reused=$reused source=$($manifest.sourceRepository)@$($manifest.sourceCommit)"
