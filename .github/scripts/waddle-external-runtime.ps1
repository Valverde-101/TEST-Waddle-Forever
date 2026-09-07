Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WaddleExternalRuntimeHome {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)
  Assert-WaddleWindowsOnly
  return [IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Runtime\Waddle-Forever'))
}

function Get-WaddleExternalRuntimeCurrentTarget {
  param([Parameter(Mandatory)][string]$RuntimeHome)
  $current = Join-Path $RuntimeHome 'Current'
  if (-not (Test-Path -LiteralPath $current)) { return $null }
  try { return Get-WaddleJunctionTarget -Path $current } catch { return $null }
}

function Test-WaddleExternalRuntimeDeployment {
  param(
    [Parameter(Mandatory)][string]$VersionRoot,
    [Parameter(Mandatory)][string]$SourceSha,
    [Parameter(Mandatory)][string]$DependencyFingerprint,
    [Parameter(Mandatory)][string]$ElectronVersion
  )

  $manifestPath = Join-Path $VersionRoot 'runtime-deployment.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason='manifest_missing' } }
  try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch { return [pscustomobject]@{ ready=$false; reason='manifest_invalid' } }

  if ([string]$manifest.source_sha -ne $SourceSha) { return [pscustomobject]@{ ready=$false; reason='source_sha_mismatch' } }
  if ([string]$manifest.dependency_fingerprint -ne $DependencyFingerprint) { return [pscustomobject]@{ ready=$false; reason='fingerprint_mismatch' } }
  if ([string]$manifest.electron_version -ne $ElectronVersion) { return [pscustomobject]@{ ready=$false; reason='electron_version_mismatch' } }

  $electron = Join-Path $VersionRoot 'electron\electron.exe'
  $icu = Join-Path $VersionRoot 'electron\icudtl.dat'
  $flash = Join-Path $VersionRoot ('flash\' + [string]$manifest.flash_file)
  $appRoot = Join-Path $VersionRoot 'app'
  $entry = Join-Path $appRoot 'compiled\client\main.js'
  $fileServer = Join-Path $appRoot 'compiled\server\file-server\index.js'
  $runtimeModules = Join-Path $appRoot 'node_modules'
  foreach ($required in @($electron,$icu,$flash,$entry,$fileServer,$runtimeModules,(Join-Path $appRoot 'package.json'))) {
    if (-not (Test-Path -LiteralPath $required)) { return [pscustomobject]@{ ready=$false; reason="file_missing:$required" } }
  }

  if ((Get-FileHash -LiteralPath $electron -Algorithm SHA256).Hash -ne [string]$manifest.electron_sha256) { return [pscustomobject]@{ ready=$false; reason='electron_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $icu -Algorithm SHA256).Hash -ne [string]$manifest.icudtl_sha256) { return [pscustomobject]@{ ready=$false; reason='icudtl_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $flash -Algorithm SHA256).Hash -ne [string]$manifest.flash_sha256) { return [pscustomobject]@{ ready=$false; reason='flash_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash -ne [string]$manifest.app_entry_sha256) { return [pscustomobject]@{ ready=$false; reason='app_entry_hash_mismatch' } }

  $package = Get-Content -LiteralPath (Join-Path $appRoot 'package.json') -Raw | ConvertFrom-Json
  foreach ($prop in $package.dependencies.PSObject.Properties) {
    $depManifest = Join-Path (Join-Path $runtimeModules ($prop.Name -replace '/','\')) 'package.json'
    if (-not (Test-Path -LiteralPath $depManifest -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="runtime_dependency_missing:$($prop.Name)" } }
  }

  return [pscustomobject]@{
    ready=$true
    reason='valid'
    manifest=$manifest
    manifest_path=$manifestPath
    root=$VersionRoot
    electron=$electron
    flash=$flash
    app_root=$appRoot
    app_entry=$entry
    runtime_node_modules=$runtimeModules
  }
}

function Set-WaddleExternalRuntimeCurrent {
  param(
    [Parameter(Mandatory)][string]$RuntimeHome,
    [Parameter(Mandatory)][string]$VersionRoot
  )

  $current = Join-Path $RuntimeHome 'Current'
  Ensure-WaddleJunction -LinkPath $current -TargetPath $VersionRoot
  $actual = Get-WaddleJunctionTarget -Path $current
  if (-not $actual -or $actual.TrimEnd('\') -ine ([IO.Path]::GetFullPath($VersionRoot)).TrimEnd('\')) {
    throw "WADDLE_RUNTIME_CURRENT=FAIL actual=$actual expected=$VersionRoot"
  }
  Write-Host "WADDLE_RUNTIME_CURRENT=PASS path=$current target=$actual"
  return $current
}

function Write-WaddleExternalRuntimeState {
  param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)]$Validation,
    [Parameter(Mandatory)][string]$CurrentRoot,
    [Parameter(Mandatory)][string]$Mode
  )

  $stateDir = Join-Path $WorkRoot 'state'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $statePath = Join-Path $stateDir 'runtime-snapshot.json'
  [ordered]@{
    schema='waddle-runtime-deployment/v2'
    status='PASS'
    platform='windows-x64'
    runtime_mode='external_deployment'
    runtime_home=[string]$Validation.manifest.runtime_home
    version_root=[string]$Validation.root
    current_root=$CurrentRoot
    source_sha=[string]$Validation.manifest.source_sha
    dependency_fingerprint=[string]$Validation.manifest.dependency_fingerprint
    electron_version=[string]$Validation.manifest.electron_version
    electron_executable=[string]$Validation.electron
    ppapi_flash_path=[string]$Validation.flash
    app_root=[string]$Validation.app_root
    app_entry=[string]$Validation.app_entry
    runtime_node_modules=[string]$Validation.runtime_node_modules
    deployment_manifest=[string]$Validation.manifest_path
    mode=$Mode
    updated_utc=[DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
  return $statePath
}

function Remove-WaddleExternalRuntimeVersions {
  param(
    [Parameter(Mandatory)][string]$RuntimeHome,
    [Parameter(Mandatory)][string]$KeepRoot,
    [int]$Retain = 3
  )

  $versions = Join-Path $RuntimeHome 'Versions'
  if (-not (Test-Path -LiteralPath $versions -PathType Container)) { return }

  $active = New-Object System.Collections.Generic.List[string]
  foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    try { if ($proc.ExecutablePath) { $active.Add([IO.Path]::GetFullPath([string]$proc.ExecutablePath)) } } catch {}
  }

  $dirs = @(Get-ChildItem -LiteralPath $versions -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
  $kept = 0
  foreach ($dir in $dirs) {
    $root = [IO.Path]::GetFullPath($dir.FullName)
    $electron = Join-Path $root 'electron\electron.exe'
    $isActive = @($active | Where-Object { $_ -ieq $electron }).Count -gt 0
    if ($root.TrimEnd('\') -ieq ([IO.Path]::GetFullPath($KeepRoot)).TrimEnd('\') -or $isActive -or $kept -lt $Retain) {
      $kept++
      continue
    }
    try {
      Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
      Write-Host "WADDLE_RUNTIME_CLEANUP=PASS removed=$root"
    } catch {
      Write-Host "WADDLE_RUNTIME_CLEANUP=INFO preserved=$root reason=$($_.Exception.Message)"
    }
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
  if (-not $env:ANDROIDBUILD_ROOT) { throw 'WADDLE_RUNTIME_DEPLOY=FAIL ANDROIDBUILD_ROOT_missing' }
  if ($ElectronVersion -ne '10.4.7') { throw "WADDLE_RUNTIME_DEPLOY=FAIL electron_expected=10.4.7 actual=$ElectronVersion" }
  if ($PepperFlashVersion -ne '32.0.0.303') { throw "WADDLE_RUNTIME_DEPLOY=FAIL flash_expected=32.0.0.303 actual=$PepperFlashVersion" }

  $runtimeHome = Get-WaddleExternalRuntimeHome -AndroidBuildRoot $env:ANDROIDBUILD_ROOT
  $versions = Join-Path $runtimeHome 'Versions'
  New-Item -ItemType Directory -Force -Path $runtimeHome,$versions | Out-Null

  $shaToken = if ($SourceSha.Length -gt 12) { $SourceSha.Substring(0,12) } else { $SourceSha }
  $fingerToken = if ($DependencyFingerprint.Length -gt 12) { $DependencyFingerprint.Substring(0,12) } else { $DependencyFingerprint }
  $target = Join-Path $versions ("$shaToken-$fingerToken-e$ElectronVersion")

  $existing = Test-WaddleExternalRuntimeDeployment -VersionRoot $target -SourceSha $SourceSha -DependencyFingerprint $DependencyFingerprint -ElectronVersion $ElectronVersion
  if ($existing.ready) {
    $current = Set-WaddleExternalRuntimeCurrent -RuntimeHome $runtimeHome -VersionRoot $target
    $statePath = Write-WaddleExternalRuntimeState -WorkRoot $WorkRoot -Validation $existing -CurrentRoot $current -Mode 'reused'
    Remove-WaddleExternalRuntimeVersions -RuntimeHome $runtimeHome -KeepRoot $target
    New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot 'runtime\interactive') | Out-Null
    Write-Host "WADDLE_RUNTIME_DEPLOY=PASS mode=reused root=$target current=$current app=$($existing.app_root) electron=$($existing.electron) flash=$($existing.flash) work_execution=false"
    return [pscustomobject]@{ status='PASS'; mode='reused'; root=$target; current_root=$current; electron_executable=$existing.electron; ppapi_flash_path=$existing.flash; ppapi_flash_version=$PepperFlashVersion; app_root=$existing.app_root; app_entry=$existing.app_entry; runtime_node_modules=$existing.runtime_node_modules; manifest=$statePath }
  }

  if (Test-Path -LiteralPath $target) {
    $target = Join-Path $versions ("$shaToken-$fingerToken-e$ElectronVersion-repair-" + (Get-Date -Format 'yyyyMMddHHmmss'))
  }

  $staging = Join-Path $runtimeHome ('.staging-' + [Guid]::NewGuid().ToString('N'))
  $stagingElectron = Join-Path $staging 'electron'
  $stagingFlash = Join-Path $staging 'flash'
  $stagingApp = Join-Path $staging 'app'
  $stagingCompiled = Join-Path $stagingApp 'compiled'
  $stagingModules = Join-Path $stagingApp 'node_modules'
  New-Item -ItemType Directory -Force -Path $stagingElectron,$stagingFlash,$stagingApp | Out-Null

  try {
    $sourceDist = Split-Path -Parent ([IO.Path]::GetFullPath($ElectronExecutable))
    $sourceIcu = Join-Path $sourceDist 'icudtl.dat'
    $sourceCompiled = Join-Path $RepoRoot 'compiled'
    $sourceEntry = Join-Path $sourceCompiled 'client\main.js'
    $sourceFileServer = Join-Path $sourceCompiled 'server\file-server\index.js'
    foreach ($required in @($ElectronExecutable,$sourceIcu,$PepperFlashPath,$sourceCompiled,$sourceEntry,$sourceFileServer,(Join-Path $RepoRoot 'package.json'),(Join-Path $RepoRoot 'yarn.lock'))) {
      if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_RUNTIME_DEPLOY=FAIL source_missing=$required" }
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction Stop
    & $robocopy.Source $sourceDist $stagingElectron /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $electronCopyExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($electronCopyExit -ge 8) { throw "WADDLE_RUNTIME_DEPLOY=FAIL electron_copy_exit=$electronCopyExit" }

    & $robocopy.Source $sourceCompiled $stagingCompiled /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $compiledCopyExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($compiledCopyExit -ge 8) { throw "WADDLE_RUNTIME_DEPLOY=FAIL compiled_copy_exit=$compiledCopyExit" }

    $flashFile = [IO.Path]::GetFileName($PepperFlashPath)
    $stagingFlashPath = Join-Path $stagingFlash $flashFile
    Copy-Item -LiteralPath $PepperFlashPath -Destination $stagingFlashPath -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'package.json') -Destination (Join-Path $stagingApp 'package.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'yarn.lock') -Destination (Join-Path $stagingApp 'yarn.lock') -Force

    $yarn = Get-Command yarn.cmd -ErrorAction Stop
    $cache = Join-Path $WorkRoot 'cache\yarn'
    Push-Location $RepoRoot
    try {
      & $yarn.Source install --production --frozen-lockfile --non-interactive --modules-folder $stagingModules --cache-folder $cache | Out-Host
      $runtimeInstallExit = $LASTEXITCODE
    } finally { Pop-Location }
    $global:LASTEXITCODE = 0
    if ($runtimeInstallExit -ne 0) { throw "WADDLE_RUNTIME_DEPLOY=FAIL runtime_yarn_exit=$runtimeInstallExit" }

    $stagingExe = Join-Path $stagingElectron 'electron.exe'
    $stagingIcu = Join-Path $stagingElectron 'icudtl.dat'
    $stagingEntry = Join-Path $stagingCompiled 'client\main.js'
    $stagingFileServer = Join-Path $stagingCompiled 'server\file-server\index.js'
    foreach ($required in @($stagingExe,$stagingIcu,$stagingFlashPath,$stagingEntry,$stagingFileServer,$stagingModules)) {
      if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_RUNTIME_DEPLOY=FAIL staged_missing=$required" }
    }

    $package = Get-Content -LiteralPath (Join-Path $RepoRoot 'package.json') -Raw | ConvertFrom-Json
    foreach ($prop in $package.dependencies.PSObject.Properties) {
      $depManifest = Join-Path (Join-Path $stagingModules ($prop.Name -replace '/','\')) 'package.json'
      if (-not (Test-Path -LiteralPath $depManifest -PathType Leaf)) { throw "WADDLE_RUNTIME_DEPLOY=FAIL runtime_dependency_missing=$($prop.Name)" }
    }

    $electronHash = (Get-FileHash -LiteralPath $ElectronExecutable -Algorithm SHA256).Hash
    $icuHash = (Get-FileHash -LiteralPath $sourceIcu -Algorithm SHA256).Hash
    $flashHash = (Get-FileHash -LiteralPath $PepperFlashPath -Algorithm SHA256).Hash
    $entryHash = (Get-FileHash -LiteralPath $sourceEntry -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $stagingExe -Algorithm SHA256).Hash -ne $electronHash) { throw 'WADDLE_RUNTIME_DEPLOY=FAIL electron_copy_hash' }
    if ((Get-FileHash -LiteralPath $stagingIcu -Algorithm SHA256).Hash -ne $icuHash) { throw 'WADDLE_RUNTIME_DEPLOY=FAIL icudtl_copy_hash' }
    if ((Get-FileHash -LiteralPath $stagingFlashPath -Algorithm SHA256).Hash -ne $flashHash) { throw 'WADDLE_RUNTIME_DEPLOY=FAIL flash_copy_hash' }
    if ((Get-FileHash -LiteralPath $stagingEntry -Algorithm SHA256).Hash -ne $entryHash) { throw 'WADDLE_RUNTIME_DEPLOY=FAIL app_entry_copy_hash' }

    $finalElectron = Join-Path $target 'electron\electron.exe'
    $finalFlash = Join-Path $target ('flash\' + $flashFile)
    $finalAppRoot = Join-Path $target 'app'
    $finalEntry = Join-Path $finalAppRoot 'compiled\client\main.js'
    $finalModules = Join-Path $finalAppRoot 'node_modules'
    [ordered]@{
      schema='waddle-runtime-deployment/v2'
      status='PASS'
      platform='windows-x64'
      runtime_mode='external_deployment'
      runtime_home=$runtimeHome
      source_sha=$SourceSha
      dependency_fingerprint=$DependencyFingerprint
      electron_version=$ElectronVersion
      electron_executable=$finalElectron
      electron_sha256=$electronHash
      icudtl_sha256=$icuHash
      flash_file=$flashFile
      ppapi_flash_path=$finalFlash
      ppapi_flash_version=$PepperFlashVersion
      flash_sha256=$flashHash
      app_root=$finalAppRoot
      app_entry=$finalEntry
      app_entry_sha256=$entryHash
      runtime_node_modules=$finalModules
      created_utc=[DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $staging 'runtime-deployment.json') -Encoding UTF8

    Move-Item -LiteralPath $staging -Destination $target -ErrorAction Stop
    $validation = Test-WaddleExternalRuntimeDeployment -VersionRoot $target -SourceSha $SourceSha -DependencyFingerprint $DependencyFingerprint -ElectronVersion $ElectronVersion
    if (-not $validation.ready) { throw "WADDLE_RUNTIME_DEPLOY=FAIL post_move=$($validation.reason)" }

    $current = Set-WaddleExternalRuntimeCurrent -RuntimeHome $runtimeHome -VersionRoot $target
    $statePath = Write-WaddleExternalRuntimeState -WorkRoot $WorkRoot -Validation $validation -CurrentRoot $current -Mode 'created'
    Remove-WaddleExternalRuntimeVersions -RuntimeHome $runtimeHome -KeepRoot $target
    New-Item -ItemType Directory -Force -Path (Join-Path $WorkRoot 'runtime\interactive') | Out-Null

    Write-Host "WADDLE_RUNTIME_DEPLOY=PASS mode=created root=$target current=$current app=$($validation.app_root) electron=$($validation.electron) flash=$($validation.flash) runtime_node_modules=$($validation.runtime_node_modules) work_execution=false"
    return [pscustomobject]@{ status='PASS'; mode='created'; root=$target; current_root=$current; electron_executable=$validation.electron; ppapi_flash_path=$validation.flash; ppapi_flash_version=$PepperFlashVersion; app_root=$validation.app_root; app_entry=$validation.app_entry; runtime_node_modules=$validation.runtime_node_modules; manifest=$statePath }
  } finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
