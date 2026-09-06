Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WaddleDependencyFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($name in @('package.json','yarn.lock')) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "WADDLE_DEPENDENCY_FINGERPRINT=FAIL missing=$path" }
    $parts.Add((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant())
  }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join '|'))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Get-WaddleJunctionTarget {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return $null }
  $raw = $null
  try { $raw = @($item.Target)[0] } catch {}
  if (-not $raw) { return $null }
  if ([IO.Path]::IsPathRooted([string]$raw)) { return [IO.Path]::GetFullPath([string]$raw) }
  return [IO.Path]::GetFullPath((Join-Path $item.Parent.FullName ([string]$raw)))
}

function Ensure-WaddleJunction {
  param(
    [Parameter(Mandatory)][string]$LinkPath,
    [Parameter(Mandatory)][string]$TargetPath,
    [int]$Attempts = 12
  )

  $link = [IO.Path]::GetFullPath($LinkPath)
  $target = [IO.Path]::GetFullPath($TargetPath)
  New-Item -ItemType Directory -Force -Path $target | Out-Null

  if (Test-Path -LiteralPath $link) {
    $existingTarget = Get-WaddleJunctionTarget -Path $link
    if ($existingTarget) {
      if ($existingTarget.TrimEnd('\') -ieq $target.TrimEnd('\')) {
        Write-Host "WORK_JUNCTION=PASS path=$link target=$target mode=existing"
        return
      }
      & cmd.exe /d /c "rmdir `"$link`"" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "WORK_JUNCTION=FAIL remove_wrong_target=$link exit=$LASTEXITCODE" }
    } else {
      $entries = @(Get-ChildItem -LiteralPath $link -Force -ErrorAction SilentlyContinue)
      if ($entries.Count -gt 0) { throw "WORK_JUNCTION=FAIL physical_directory_not_empty=$link" }
      Remove-Item -LiteralPath $link -Force -Recurse -ErrorAction Stop
    }
  }

  $lastError = ''
  for ($attempt=1; $attempt -le $Attempts; $attempt++) {
    try {
      if (Test-Path -LiteralPath $link) {
        $actual = Get-WaddleJunctionTarget -Path $link
        if ($actual -and $actual.TrimEnd('\') -ieq $target.TrimEnd('\')) {
          Write-Host "WORK_JUNCTION=PASS path=$link target=$target mode=race_existing attempt=$attempt"
          return
        }
        & cmd.exe /d /c "rmdir `"$link`"" 2>$null | Out-Null
      }
      New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
      $actual = Get-WaddleJunctionTarget -Path $link
      if ($actual -and $actual.TrimEnd('\') -ieq $target.TrimEnd('\')) {
        Write-Host "WORK_JUNCTION=PASS path=$link target=$target mode=created attempt=$attempt"
        return
      }
      $lastError = 'post_create_target_mismatch'
    } catch {
      $lastError = $_.Exception.Message
    }
    Start-Sleep -Milliseconds ([Math]::Min(1500,200 * $attempt))
  }

  # PowerShell's Junction provider can intermittently return Access denied while a
  # scanner/process releases a directory handle. mklink /J uses the native path and
  # is a safe final fallback after bounded retries.
  & cmd.exe /d /c "mklink /J `"$link`" `"$target`"" | Out-Null
  $mklinkExit = $LASTEXITCODE
  $finalTarget = Get-WaddleJunctionTarget -Path $link
  if ($mklinkExit -ne 0 -or -not $finalTarget -or $finalTarget.TrimEnd('\') -ine $target.TrimEnd('\')) {
    throw "WORK_JUNCTION=FAIL path=$link target=$target attempts=$Attempts mklink_exit=$mklinkExit last_error=$lastError"
  }
  Write-Host "WORK_JUNCTION=PASS path=$link target=$target mode=mklink_fallback attempts=$Attempts"
}

function Test-WaddleDependencyTree {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  $target = Join-Path $WorkRoot 'dependencies\node_modules'
  $packagePath = Join-Path $RepoRoot 'package.json'
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason='package_json_missing' } }
  $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  $required = New-Object System.Collections.Generic.List[string]
  foreach ($section in @('dependencies','devDependencies')) {
    $obj = $package.$section
    if ($null -eq $obj) { continue }
    foreach ($prop in $obj.PSObject.Properties) { if (-not $required.Contains($prop.Name)) { $required.Add($prop.Name) } }
  }
  foreach ($name in $required) {
    $manifest = Join-Path (Join-Path $target ($name -replace '/','\')) 'package.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
      return [pscustomobject]@{ ready=$false; reason="package_missing:$name" }
    }
  }

  $electronManifest = Join-Path $target 'electron\package.json'
  $electron = Get-Content -LiteralPath $electronManifest -Raw | ConvertFrom-Json
  if (-not ([string]$electron.version).StartsWith('10.')) {
    return [pscustomobject]@{ ready=$false; reason="electron_contract:$($electron.version)" }
  }
  if ($env:OS -eq 'Windows_NT' -and [Environment]::Is64BitOperatingSystem) {
    $native = Join-Path $target '@typescript\typescript-win32-x64\package.json'
    if (-not (Test-Path -LiteralPath $native -PathType Leaf)) {
      return [pscustomobject]@{ ready=$false; reason='typescript_native_missing' }
    }
  }
  return [pscustomobject]@{ ready=$true; reason='complete'; electron=[string]$electron.version }
}

function Write-WaddleDependencyState {
  param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$Fingerprint,
    [Parameter(Mandatory)][string]$Electron,
    [Parameter(Mandatory)][string]$Mode
  )
  $stateDir = Join-Path $WorkRoot 'state'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $path = Join-Path $stateDir 'dependencies.json'
  [ordered]@{
    schema='waddle-dependencies/v1'
    fingerprint=$Fingerprint
    electron=$Electron
    mode=$Mode
    updated_utc=[DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-WaddleDependencyBootstrap {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  $target = Join-Path $WorkRoot 'dependencies\node_modules'
  $link = Join-Path $RepoRoot 'node_modules'
  $fingerprint = Get-WaddleDependencyFingerprint -RepoRoot $RepoRoot
  $statePath = Join-Path $WorkRoot 'state\dependencies.json'
  $tree = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  $stateMatches = $false
  if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
      $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      $stateMatches = ([string]$state.fingerprint -eq $fingerprint)
    } catch {}
  }

  if ($tree.ready -and ($stateMatches -or -not (Test-Path -LiteralPath $statePath -PathType Leaf))) {
    Ensure-WaddleJunction -LinkPath $link -TargetPath $target
    Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
    $mode = if ($stateMatches) { 'reused' } else { 'adopted_existing' }
    Write-WaddleDependencyState -WorkRoot $WorkRoot -Fingerprint $fingerprint -Electron $tree.electron -Mode $mode | Out-Null
    Write-Host "WADDLE_DEPENDENCIES=PASS mode=$mode target=$target electron=$($tree.electron) fingerprint=$fingerprint"
    return [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$tree.electron; fingerprint=$fingerprint; mode=$mode }
  }

  Write-Host "WADDLE_DEPENDENCIES=INSTALL reason=$($tree.reason) fingerprint_changed=$(-not $stateMatches) no_visual_studio_required=true"
  $installError = $null
  try {
    $installed = Install-WaddleDependencies -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  } catch {
    $installError = $_.Exception.Message
    # Yarn may have completed successfully while PowerShell lost a race recreating
    # the repo junction. Recover the link and classify from the installed tree.
    Ensure-WaddleJunction -LinkPath $link -TargetPath $target
    $recovered = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
    if (-not $recovered.ready) { throw }
    $installed = [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$recovered.electron }
    Write-Host "WADDLE_DEPENDENCIES=RECOVERED reason=junction_post_install install_error=$installError"
  }

  Ensure-WaddleJunction -LinkPath $link -TargetPath $target
  $final = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  if (-not $final.ready) { throw "WADDLE_DEPENDENCIES=FAIL post_install_tree=$($final.reason)" }
  Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
  Write-WaddleDependencyState -WorkRoot $WorkRoot -Fingerprint $fingerprint -Electron $final.electron -Mode 'installed' | Out-Null
  Write-Host "WADDLE_DEPENDENCIES=PASS mode=installed target=$target electron=$($final.electron) fingerprint=$fingerprint no_visual_studio_required=true"
  return [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$final.electron; fingerprint=$fingerprint; mode='installed' }
}
