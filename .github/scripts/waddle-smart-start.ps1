[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$launcher = Join-Path $PSScriptRoot 'waddle-launcher.ps1'
$summaryPath = Join-Path $repo '.work\state\waddle-build-summary.json'
$compiledEntry = Join-Path $repo 'compiled\client\main.js'
$compiledServer = Join-Path $repo 'compiled\server\file-server\index.js'
$reuse = $false
$reason = 'build_state_missing'
$currentSha = ''
$currentFingerprint = ''

function Get-WaddleSmartStartFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($name in @('package.json','yarn.lock')) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $parts.Add((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant())
  }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join '|'))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

try {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) {
    $safe = $repo.Replace('"','\"')
    $head = & $git.Source -c "safe.directory=$safe" -C $repo rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $head) { $currentSha = ([string]$head).Trim().ToLowerInvariant() }
    $global:LASTEXITCODE = 0
  }

  $currentFingerprint = Get-WaddleSmartStartFingerprint -RepoRoot $repo
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    $reason = 'build_summary_missing'
  } elseif (-not (Test-Path -LiteralPath $compiledEntry -PathType Leaf) -or -not (Test-Path -LiteralPath $compiledServer -PathType Leaf)) {
    $reason = 'compiled_output_missing'
  } elseif ([string]::IsNullOrWhiteSpace($currentSha)) {
    $reason = 'git_head_unresolved'
  } elseif ([string]::IsNullOrWhiteSpace($currentFingerprint)) {
    $reason = 'dependency_fingerprint_unresolved'
  } else {
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    $summarySha = ([string]$summary.source_sha).Trim().ToLowerInvariant()
    $summaryFingerprint = ([string]$summary.dependency_fingerprint).Trim().ToUpperInvariant()
    if ([string]$summary.status -ne 'PASS') {
      $reason = 'previous_build_not_pass'
    } elseif ($summarySha -ne $currentSha) {
      $reason = "source_sha_changed:$summarySha->$currentSha"
    } elseif ($summaryFingerprint -ne $currentFingerprint) {
      $reason = 'dependency_fingerprint_changed'
    } else {
      $reuse = $true
      $reason = 'same_sha_same_dependencies_compiled_present'
    }
  }
} catch {
  $reuse = $false
  $reason = "freshness_probe_error:$($_.Exception.Message)"
}

if ($reuse) {
  Write-Host "WADDLE_FAST_START=PASS mode=reuse_build sha=$currentSha fingerprint=$currentFingerprint reason=$reason"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action start -SkipBuild
} else {
  Write-Host "WADDLE_FAST_START=INFO mode=full_build sha=$currentSha fingerprint=$currentFingerprint reason=$reason"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action start
}
$exit = $LASTEXITCODE
$global:LASTEXITCODE = 0
exit $exit
