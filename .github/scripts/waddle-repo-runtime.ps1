Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repository-local runtime policy.
#
# The interactive client uses the exact same repository tree on every machine:
#   <repo>\node_modules\electron\dist\electron.exe
#   <repo>\compiled\client\main.js
#   <repo>\assets\flash\pepflashplayer64_32_0_0_303.dll
#
# There is no AndroidBuild\Runtime deployment and no second node_modules tree.
# Setup/build are allowed to mutate repo\node_modules only while the client is
# stopped. Start then treats that tree as read-only until Waddle-Stop.

function Get-WaddleRepoRuntimeRoot {
  $repo = if ($env:WADDLE_REPO_ROOT) {
    [string]$env:WADDLE_REPO_ROOT
  } else {
    Join-Path $PSScriptRoot '..\..'
  }
  return [IO.Path]::GetFullPath($repo)
}

# Compatibility name retained because older launcher/certification code calls it.
# Its meaning is now "runtime home == repository root".
function Get-WaddleExternalRuntimeHome {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)
  [void]$AndroidBuildRoot
  Assert-WaddleWindowsOnly
  return Get-WaddleRepoRuntimeRoot
}

function Get-WaddleExternalRuntimeCurrentTarget {
  param([Parameter(Mandatory)][string]$RuntimeHome)
  return [IO.Path]::GetFullPath($RuntimeHome)
}

function Test-WaddleNetworkBackedPath {
  param([Parameter(Mandatory)][string]$Path)

  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\')) { return $true }

  $root = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($root)) { return $false }
  try {
    $drive = New-Object IO.DriveInfo($root)
    return $drive.DriveType -eq [IO.DriveType]::Network
  } catch {
    return $false
  }
}

# Override the historical probe. On a local/fixed drive we keep the cheap
# ELECTRON_RUN_AS_NODE smoke process. On SMB/network-backed mapped drives that
# smoke process can block in Windows image loading even though the GUI process
# is usable. In that case validate the binary/manifest synchronously here and
# defer executable proof to the real structured runtime health gate.
function Test-WaddleElectronRuntime {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [int]$ProbeTimeoutMilliseconds = 10000
  )

  Assert-WaddleWindowsOnly
  $modules = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $manifestPath = Join-Path $modules 'electron\package.json'
  $electronExe = [IO.Path]::GetFullPath((Join-Path $modules 'electron\dist\electron.exe'))
  $icu = Join-Path $modules 'electron\dist\icudtl.dat'
  $resources = Join-Path $modules 'electron\dist\resources.pak'

  foreach ($required in @($manifestPath,$electronExe,$icu,$resources)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "WADDLE_ELECTRON_RUNTIME=FAIL required_missing=$required"
    }
  }

  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $manifestVersion = [string]$manifest.version
  if ($manifestVersion -ne $ExpectedVersion -or $manifestVersion -ne '10.4.7') {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL version_mismatch expected=$ExpectedVersion pinned=10.4.7 actual=$manifestVersion"
  }

  $item = Get-Item -LiteralPath $electronExe -Force
  if ($item.Length -lt 1048576) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL suspicious_size=$($item.Length) executable=$electronExe"
  }

  $stream = [IO.File]::Open($electronExe,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try {
    $mz0 = $stream.ReadByte()
    $mz1 = $stream.ReadByte()
  } finally {
    $stream.Dispose()
  }
  if ($mz0 -ne 0x4D -or $mz1 -ne 0x5A) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL invalid_pe_signature executable=$electronExe"
  }

  $productVersion = [string]$item.VersionInfo.ProductVersion
  $fileVersion = [string]$item.VersionInfo.FileVersion
  if ($productVersion -notmatch '^10\.4\.7' -and $fileVersion -notmatch '^10\.4\.7') {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL pe_version_mismatch manifest=$manifestVersion product=$productVersion file=$fileVersion executable=$electronExe"
  }

  $networkBacked = Test-WaddleNetworkBackedPath -Path $electronExe
  $probeMode = 'PASS'
  if ($networkBacked) {
    $probeMode = 'DEFERRED_NETWORK_TO_RUNTIME_HEALTH'
  } else {
    $previousRunAsNode = [Environment]::GetEnvironmentVariable('ELECTRON_RUN_AS_NODE','Process')
    $probe = $null
    try {
      [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE','1','Process')
      $probe = Start-Process -FilePath $electronExe -ArgumentList @('-e','process.exit(0)') -WorkingDirectory (Split-Path -Parent $electronExe) -PassThru -ErrorAction Stop
      if (-not $probe.WaitForExit($ProbeTimeoutMilliseconds)) {
        try { $probe.Kill() } catch {}
        throw "WADDLE_ELECTRON_RUNTIME=FAIL probe_timeout_ms=$ProbeTimeoutMilliseconds executable=$electronExe"
      }
      $probe.Refresh()
      if ($probe.ExitCode -ne 0) {
        throw "WADDLE_ELECTRON_RUNTIME=FAIL probe_exit=$($probe.ExitCode) executable=$electronExe mode=run_as_node"
      }
    } catch {
      if ($_.Exception.Message -like 'WADDLE_ELECTRON_RUNTIME=FAIL*') { throw }
      throw "WADDLE_ELECTRON_RUNTIME=FAIL process_start executable=$electronExe error=$($_.Exception.Message)"
    } finally {
      if ($null -eq $previousRunAsNode) {
        Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
      } else {
        [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$previousRunAsNode,'Process')
      }
      if ($probe) { $probe.Dispose() }
    }
  }

  Write-Host "WADDLE_ELECTRON_RUNTIME=PASS version=$manifestVersion executable=$electronExe size=$($item.Length) pe=MZ direct_process_probe=$probeMode launch_mode=repo_dependency_direct network_backed=$networkBacked product_version=$productVersion file_version=$fileVersion"
  [pscustomobject]@{
    status = 'PASS'
    version = $manifestVersion
    executable = $electronExe
    size = [int64]$item.Length
    product_version = $productVersion
    file_version = $fileVersion
    launch_mode = 'repo_dependency_direct'
    direct_process_probe = $probeMode
    network_backed = [bool]$networkBacked
  }
}

function New-WaddleRuntimeSnapshot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$ElectronExecutable,
    [Parameter(Mandatory)][string]$ElectronVersion,
    [Parameter(Mandatory)][string]$PepperFlashPath,
    [Parameter(Mandatory)][string]$PepperFlashVersion,
    [Parameter(Mandatory)][string]$SourceSha,
    [Parameter(Mandatory)][string]$DependencyFingerprint
  )

  Assert-WaddleWindowsOnly
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
  $modules = [IO.Path]::GetFullPath((Join-Path $repo 'node_modules'))
  $electron = [IO.Path]::GetFullPath($ElectronExecutable)
  $expectedElectron = [IO.Path]::GetFullPath((Join-Path $modules 'electron\dist\electron.exe'))
  $flash = [IO.Path]::GetFullPath($PepperFlashPath)
  $expectedFlash = [IO.Path]::GetFullPath((Join-Path $repo 'assets\flash\pepflashplayer64_32_0_0_303.dll'))
  $entry = [IO.Path]::GetFullPath((Join-Path $repo 'compiled\client\main.js'))
  $fileServer = [IO.Path]::GetFullPath((Join-Path $repo 'compiled\server\file-server\index.js'))

  if ($ElectronVersion -ne '10.4.7') { throw "WADDLE_RUNTIME_DIRECT=FAIL electron_expected=10.4.7 actual=$ElectronVersion" }
  if ($PepperFlashVersion -ne '32.0.0.303') { throw "WADDLE_RUNTIME_DIRECT=FAIL flash_expected=32.0.0.303 actual=$PepperFlashVersion" }
  if ($electron -ine $expectedElectron) { throw "WADDLE_RUNTIME_DIRECT=FAIL electron_outside_repo actual=$electron expected=$expectedElectron" }
  if ($flash -ine $expectedFlash) { throw "WADDLE_RUNTIME_DIRECT=FAIL flash_outside_repo actual=$flash expected=$expectedFlash" }
  foreach ($required in @($electron,$flash,$entry,$fileServer,(Join-Path $repo 'package.json'),$modules)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_RUNTIME_DIRECT=FAIL required_missing=$required" }
  }

  $stateDir = Join-Path $WorkRoot 'state'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $statePath = Join-Path $stateDir 'runtime-snapshot.json'
  $networkBacked = Test-WaddleNetworkBackedPath -Path $electron
  [ordered]@{
    schema='waddle-runtime-deployment/v4'
    status='PASS'
    platform='windows-x64'
    runtime_mode='repo_local_direct'
    runtime_home=$repo
    version_root=$repo
    current_root=$repo
    current_target=$repo
    source_sha=$SourceSha
    dependency_fingerprint=$DependencyFingerprint
    electron_version=$ElectronVersion
    electron_executable=$electron
    electron_sha256=(Get-FileHash -LiteralPath $electron -Algorithm SHA256).Hash
    ppapi_flash_path=$flash
    flash_sha256=(Get-FileHash -LiteralPath $flash -Algorithm SHA256).Hash
    app_root=$repo
    app_entry=$entry
    app_entry_sha256=(Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash
    runtime_node_modules=$modules
    copies_created=0
    network_backed=[bool]$networkBacked
    mode='direct'
    updated_utc=[DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

  Write-Host "WADDLE_RUNTIME_DEPLOY=PASS mode=repo_local_direct root=$repo electron=$electron flash=$flash app_entry=$entry node_modules=$modules copies=0 network_backed=$networkBacked work_execution=false"
  [pscustomobject]@{
    status='PASS'
    mode='repo_local_direct'
    root=$repo
    current_root=$repo
    electron_executable=$electron
    ppapi_flash_path=$flash
    ppapi_flash_version=$PepperFlashVersion
    app_root=$repo
    app_entry=$entry
    runtime_node_modules=$modules
    manifest=$statePath
    network_backed=[bool]$networkBacked
  }
}

# Compatibility no-ops. Repository-local direct mode has no version directories,
# Current junction, staging deployment, or runtime dependency copies to clean.
function Remove-WaddleExternalRuntimeVersions {
  param([string]$RuntimeHome,[string]$KeepRoot,[int]$Retain = 3)
  [void]$RuntimeHome; [void]$KeepRoot; [void]$Retain
}

function Set-WaddleExternalRuntimeCurrent {
  param([Parameter(Mandatory)][string]$RuntimeHome,[Parameter(Mandatory)][string]$VersionRoot)
  [void]$RuntimeHome
  return [IO.Path]::GetFullPath($VersionRoot)
}
