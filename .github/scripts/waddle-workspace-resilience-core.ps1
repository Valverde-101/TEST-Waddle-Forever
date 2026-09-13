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
    [int]$Attempts = 12,
    [switch]$AllowPhysicalDirectory
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
      $global:LASTEXITCODE = 0
    } else {
      if ($AllowPhysicalDirectory) {
        Write-Host "WORK_PATH=PASS path=$link target=$target mode=physical_existing"
        return
      }
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
        $global:LASTEXITCODE = 0
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

  & cmd.exe /d /c "mklink /J `"$link`" `"$target`"" | Out-Null
  $mklinkExit = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  $finalTarget = Get-WaddleJunctionTarget -Path $link
  if ($mklinkExit -eq 0 -and $finalTarget -and $finalTarget.TrimEnd('\') -ieq $target.TrimEnd('\')) {
    Write-Host "WORK_JUNCTION=PASS path=$link target=$target mode=mklink_fallback attempts=$Attempts"
    return
  }

  if ($AllowPhysicalDirectory) {
    if (Test-Path -LiteralPath $link) {
      try {
        $item = Get-Item -LiteralPath $link -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          & cmd.exe /d /c "rmdir `"$link`"" | Out-Null
          $global:LASTEXITCODE = 0
        }
      } catch {}
    }
    if (-not (Test-Path -LiteralPath $link)) { New-Item -ItemType Directory -Force -Path $link | Out-Null }
    Write-Host "WORK_PATH=PASS path=$link target=$target mode=physical_fallback attempts=$Attempts mklink_exit=$mklinkExit last_error=$lastError"
    return
  }

  throw "WORK_JUNCTION=FAIL path=$link target=$target attempts=$Attempts mklink_exit=$mklinkExit last_error=$lastError"
}

function Test-WaddleDependencyTree {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot)
  Assert-WaddleWindowsOnly
  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
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
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="package_missing:$name" } }
  }
  $electronManifest = Join-Path $target 'electron\package.json'
  $electron = Get-Content -LiteralPath $electronManifest -Raw | ConvertFrom-Json
  if ([string]$electron.version -ne '10.4.7') { return [pscustomobject]@{ ready=$false; reason="electron_contract:$($electron.version)" } }
  foreach ($runtimeFile in @('electron\dist\electron.exe','electron\dist\icudtl.dat','electron\dist\resources.pak')) {
    $runtimePath = Join-Path $target $runtimeFile
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="electron_runtime_missing:$runtimeFile" } }
  }
  $native = Join-Path $target '@typescript\typescript-win32-x64\package.json'
  if (-not (Test-Path -LiteralPath $native -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason='typescript_native_missing' } }
  foreach ($wrapper in @('copyfiles.cmd','electron.cmd','eslint.cmd','tsc-alias.cmd','tsx.cmd')) {
    $wrapperPath = Join-Path $target ('.bin\' + $wrapper)
    if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="bin_wrapper_missing:$wrapper" } }
  }
  return [pscustomobject]@{ ready=$true; reason='complete'; electron=[string]$electron.version }
}

function Write-WaddleDependencyState {
  param([Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$Fingerprint,[Parameter(Mandatory)][string]$Electron,[Parameter(Mandatory)][string]$Mode)
  $stateDir = Join-Path $WorkRoot 'state'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $path = Join-Path $stateDir 'dependencies.json'
  [ordered]@{ schema='waddle-dependencies/v2'; platform='windows-x64'; root='dependencies/current/node_modules'; fingerprint=$Fingerprint; electron=$Electron; mode=$Mode; updated_utc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-WaddleDependencyBootstrap {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot)
  Assert-WaddleWindowsOnly
  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $link = Join-Path $RepoRoot 'node_modules'
  $fingerprint = Get-WaddleDependencyFingerprint -RepoRoot $RepoRoot
  $statePath = Join-Path $WorkRoot 'state\dependencies.json'
  $tree = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  $stateMatches = $false
  if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
      $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      $stateMatches = ([string]$state.fingerprint -eq $fingerprint -and [string]$state.root -eq 'dependencies/current/node_modules')
    } catch {}
  }
  if ($tree.ready -and ($stateMatches -or -not (Test-Path -LiteralPath $statePath -PathType Leaf))) {
    Ensure-WaddleJunction -LinkPath $link -TargetPath $target
    Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
    $mode = if ($stateMatches) { 'reused' } else { 'adopted_existing' }
    Write-WaddleDependencyState -WorkRoot $WorkRoot -Fingerprint $fingerprint -Electron $tree.electron -Mode $mode | Out-Null
    Write-Host "WADDLE_DEPENDENCIES=PASS mode=$mode target=$target electron=$($tree.electron) fingerprint=$fingerprint runtime_isolated=true"
    return [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$tree.electron; fingerprint=$fingerprint; mode=$mode }
  }
  Write-Host "WADDLE_DEPENDENCIES=INSTALL reason=$($tree.reason) fingerprint_changed=$(-not $stateMatches) target=$target no_visual_studio_required=true"
  $installed = Install-WaddleDependencies -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  Ensure-WaddleJunction -LinkPath $link -TargetPath $target
  $final = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  if (-not $final.ready) { throw "WADDLE_DEPENDENCIES=FAIL post_install_tree=$($final.reason)" }
  Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
  Write-WaddleDependencyState -WorkRoot $WorkRoot -Fingerprint $fingerprint -Electron $final.electron -Mode 'installed' | Out-Null
  Write-Host "WADDLE_DEPENDENCIES=PASS mode=installed target=$target electron=$($final.electron) fingerprint=$fingerprint no_visual_studio_required=true runtime_isolated=true"
  return [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$final.electron; fingerprint=$fingerprint; mode='installed' }
}
