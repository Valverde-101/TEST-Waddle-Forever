[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [switch]$PatchGenerator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$ignorePath = Join-Path $repo '.gitignore'
if (-not (Test-Path -LiteralPath $ignorePath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_VERSIONING=FAIL gitignore_missing=$ignorePath"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$ignore = [IO.File]::ReadAllText($ignorePath) -replace "`r`n", "`n"
$cleanIgnore = [regex]::Replace($ignore, '(?m)^/media/default/party2015/\s*\n?', '')
if ($cleanIgnore -ne $ignore) {
  [IO.File]::WriteAllText($ignorePath, $cleanIgnore, $utf8)
}

if ($PatchGenerator) {
  $sourcePath = Join-Path $repo '.github\scripts\waddle-halloween-2015-source.ps1'
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "WADDLE_PARTY2015_VERSIONING=FAIL source_generator_missing=$sourcePath"
  }
  $source = [IO.File]::ReadAllText($sourcePath) -replace "`r`n", "`n"
  $pattern = '(?ms)^# Keep the physically hydrated party media canonical on V: without making the checkout dirty\.\n\$ignorePath = Join-Path \$RepoRoot ''\.gitignore''\n\$ignore = Read-Normalized \$ignorePath\nif \(-not \$ignore\.Contains\(''/media/default/party2015/''\)\) \{\n  \$ignore = \$ignore\.TrimEnd\(\) \+ "`n/media/default/party2015/`n"\n\}\nWrite-Utf8 \$ignorePath \$ignore\n\n'
  $patched = [regex]::Replace($source, $pattern, '', 1)
  if ($patched -eq $source -and $source -match '/media/default/party2015/') {
    throw 'WADDLE_PARTY2015_VERSIONING=FAIL generator_ignore_block_not_removed'
  }
  if ($patched -ne $source) {
    [IO.File]::WriteAllText($sourcePath, $patched, $utf8)
  }

  # The historical manifest is already canonical and manifest-driven. Verify
  # its schema and ordinal ordering; never rewrite it in CI.
  $manifestPath = Join-Path $repo 'media\default\party2015\manifest.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "WADDLE_PARTY2015_VERSIONING=FAIL manifest_missing=$manifestPath"
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ([int]$manifest.schema -ne 3) {
    throw "WADDLE_PARTY2015_VERSIONING=FAIL manifest_schema=$($manifest.schema) expected=3"
  }
  $assets = @($manifest.assets)
  if ([int]$manifest.requiredCount -ne 132 -or [int]$manifest.total -ne $assets.Count -or $assets.Count -ne 132) {
    throw "WADDLE_PARTY2015_VERSIONING=FAIL manifest_count required=$($manifest.requiredCount) total=$($manifest.total) entries=$($assets.Count)"
  }
  foreach ($volatile in @('generatedAt','downloaded','reused','canonicalRoot')) {
    if ($manifest.PSObject.Properties.Name -contains $volatile) {
      throw "WADDLE_PARTY2015_VERSIONING=FAIL volatile_manifest_field=$volatile"
    }
  }
  [string[]]$paths = @($assets | ForEach-Object { ([string]$_.relativePath).Replace('\','/') })
  [string[]]$expectedPaths = @($paths)
  [Array]::Sort($expectedPaths,[StringComparer]::Ordinal)
  for ($i=0; $i -lt $paths.Count; $i++) {
    if (-not $paths[$i].Equals($expectedPaths[$i],[StringComparison]::Ordinal)) {
      throw "WADDLE_PARTY2015_VERSIONING=FAIL manifest_not_ordinal index=$i actual=$($paths[$i]) expected=$($expectedPaths[$i])"
    }
  }

}

$remaining = [IO.File]::ReadAllText($ignorePath)
if ($remaining -match '(?m)^/media/default/party2015/\s*$') {
  throw 'WADDLE_PARTY2015_VERSIONING=FAIL party2015_still_ignored'
}

Write-Host "WADDLE_PARTY2015_VERSIONING=PASS tracked_media=true deterministic_manifest=true patch_generator=$([bool]$PatchGenerator)"
