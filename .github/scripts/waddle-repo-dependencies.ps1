Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Canonical dependency layout for interactive Waddle on Windows:
#   <repo>\node_modules            = the single persistent dependency tree
#   <repo>\.work                   = cache/build/log/state only
#   <AndroidBuild>\Runtime\Waddle = Electron/Flash/compiled deployment only
#
# Electron itself still executes from the external runtime so icudtl.dat and
# friends are never locked inside the repository dependency tree. The app uses
# repo\node_modules through NODE_PATH; no second runtime node_modules is copied.

function Get-WaddleRepoRootFromWorkRoot {
  param([Parameter(Mandatory)][string]$WorkRoot)
  $work = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
  if ([IO.Path]::GetFileName($work) -ieq '.work') {
    return [IO.Path]::GetFullPath((Split-Path -Parent $work))
  }
  if ($env:WADDLE_REPO_ROOT) { return [IO.Path]::GetFullPath([string]$env:WADDLE_REPO_ROOT) }
  throw "WADDLE_NODE_MODULES=FAIL cannot_resolve_repo_from_work=$work"
}

function Get-WaddleNodeModulesPath {
  param([Parameter(Mandatory)][string]$WorkRoot)
  $repo = Get-WaddleRepoRootFromWorkRoot -WorkRoot $WorkRoot
  return [IO.Path]::GetFullPath((Join-Path $repo 'node_modules'))
}

function Move-WaddleDependencyTreeOnce {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return $false }
  if (Test-Path -LiteralPath $Destination) { return $false }
  try {
    Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    Write-Host "WADDLE_DEPENDENCY_MIGRATION=PASS mode=move source=$Source destination=$Destination"
    return $true
  } catch {
    $moveError = $_.Exception.Message
  }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $robocopy = Get-Command robocopy.exe -ErrorAction Stop
  & $robocopy.Source $Source $Destination /E /MOVE /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  $copyExit = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($copyExit -ge 8) {
    throw "WADDLE_DEPENDENCY_MIGRATION=FAIL source=$Source destination=$Destination robocopy_exit=$copyExit move_error=$moveError"
  }
  try { Remove-Item -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  Write-Host "WADDLE_DEPENDENCY_MIGRATION=PASS mode=robocopy_move source=$Source destination=$Destination move_error=$moveError"
  return $true
}

function Remove-WaddleInactiveRuntimeDependencyCopies {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)
  $versions = Join-Path $AndroidBuildRoot 'Runtime\Waddle-Forever\Versions'
  if (-not (Test-Path -LiteralPath $versions -PathType Container)) { return }

  $activeExecutables = New-Object System.Collections.Generic.List[string]
  foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    try { if ($proc.ExecutablePath) { $activeExecutables.Add([IO.Path]::GetFullPath([string]$proc.ExecutablePath)) } } catch {}
  }

  foreach ($version in @(Get-ChildItem -LiteralPath $versions -Directory -ErrorAction SilentlyContinue)) {
    $electron = [IO.Path]::GetFullPath((Join-Path $version.FullName 'electron\electron.exe'))
    $isActive = @($activeExecutables | Where-Object { $_ -ieq $electron }).Count -gt 0
    $duplicate = Join-Path $version.FullName 'app\node_modules'
    if (-not (Test-Path -LiteralPath $duplicate)) { continue }
    if ($isActive) {
      Write-Host "WADDLE_RUNTIME_DEPENDENCIES=INFO action=preserve_active path=$duplicate"
      continue
    }
    try {
      Remove-Item -LiteralPath $duplicate -Recurse -Force -ErrorAction Stop
      Write-Host "WADDLE_RUNTIME_DEPENDENCIES=PASS action=removed_duplicate path=$duplicate"
    } catch {
      Write-Host "WADDLE_RUNTIME_DEPENDENCIES=WARN action=preserved path=$duplicate error=$($_.Exception.Message)"
    }
  }
}

function Initialize-WaddleWorkspace {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$AndroidBuildRoot
  )
  Assert-WaddleWindowsOnly
  $coreWork = Initialize-AndroidBuildProjectWork -RepoRoot $RepoRoot -EnsureGitIgnore
  $work = [string]$coreWork.work_root
  foreach ($relative in @(
    'cache\yarn','runtime\interactive','downloads','content','swf-analysis','diagnostics',
    'logs\build','logs\runtime','dist\package','tmp','state'
  )) { Ensure-WaddleDirectory (Join-Path $work $relative) }

  $repoModules = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'node_modules'))
  $junctionTarget = $null
  if (Test-Path -LiteralPath $repoModules) {
    $item = Get-Item -LiteralPath $repoModules -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      try { $junctionTarget = Get-WaddleJunctionTarget -Path $repoModules } catch {}
      & cmd.exe /d /c "rmdir `"$repoModules`"" | Out-Null
      $removeExit = $LASTEXITCODE
      $global:LASTEXITCODE = 0
      if ($removeExit -ne 0 -and (Test-Path -LiteralPath $repoModules)) {
        throw "WADDLE_NODE_MODULES=FAIL junction_remove exit=$removeExit path=$repoModules"
      }
    }
  }

  if (-not (Test-Path -LiteralPath $repoModules -PathType Container)) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($junctionTarget) { $candidates.Add([string]$junctionTarget) }
    $current = Join-Path $work 'dependencies\current\node_modules'
    $legacy = Join-Path $work 'dependencies\node_modules'
    foreach ($candidate in @($current,$legacy)) {
      if ((Test-Path -LiteralPath $candidate -PathType Container) -and -not $candidates.Contains($candidate)) { $candidates.Add($candidate) }
    }
    foreach ($candidate in $candidates) {
      if (Move-WaddleDependencyTreeOnce -Source $candidate -Destination $repoModules) { break }
    }
  }

  # Old .work dependency copies are no longer canonical. Remove only real,
  # inactive directories after the canonical repo tree exists.
  if (Test-Path -LiteralPath $repoModules -PathType Container) {
    foreach ($old in @((Join-Path $work 'dependencies\current\node_modules'),(Join-Path $work 'dependencies\node_modules'))) {
      if (-not (Test-Path -LiteralPath $old)) { continue }
      try {
        $oldItem = Get-Item -LiteralPath $old -Force
        if (($oldItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          & cmd.exe /d /c "rmdir `"$old`"" | Out-Null
          $global:LASTEXITCODE = 0
        } else {
          Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction Stop
        }
        Write-Host "WADDLE_DEPENDENCY_CLEANUP=PASS removed=$old"
      } catch {
        Write-Host "WADDLE_DEPENDENCY_CLEANUP=WARN preserved=$old error=$($_.Exception.Message)"
      }
    }
  }

  Ensure-WaddleJunction -LinkPath (Join-Path $RepoRoot 'compiled') -TargetPath (Join-Path $work 'build\compiled') -AllowPhysicalDirectory
  Ensure-WaddleJunction -LinkPath (Join-Path $RepoRoot 'dist') -TargetPath (Join-Path $work 'dist\package') -AllowPhysicalDirectory

  $envPath = Join-Path $RepoRoot '.env'
  $templatePath = Join-Path $RepoRoot 'template.env'
  if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'WADDLE_ENV=FAIL template.env_missing' }
    Copy-Item -LiteralPath $templatePath -Destination $envPath
    Write-Host 'WADDLE_ENV=PASS mode=created_from_template'
  } else { Write-Host 'WADDLE_ENV=PASS mode=existing' }

  $env:YARN_CACHE_FOLDER = Join-Path $work 'cache\yarn'
  $env:WADDLE_WORK_ROOT = $work
  $env:WADDLE_REPO_ROOT = $RepoRoot
  $env:WADDLE_NODE_MODULES = $repoModules
  $env:ANDROIDBUILD_ROOT = $AndroidBuildRoot
  Remove-WaddleInactiveRuntimeDependencyCopies -AndroidBuildRoot $AndroidBuildRoot

  $layoutMode = if (Test-Path -LiteralPath $repoModules -PathType Container) { 'repo_physical_existing' } else { 'repo_physical_pending_install' }
  Write-Host "WADDLE_NODE_MODULES_LAYOUT=PASS mode=$layoutMode path=$repoModules work_dependency_copy=false"
  [pscustomobject]@{ status='PASS'; repo_root=$RepoRoot; work_root=$work; node_modules=$repoModules; yarn_cache=$env:YARN_CACHE_FOLDER }
}

function Enable-WaddleLocalNodeTooling {
  param([Parameter(Mandatory)][string]$WorkRoot)
  $modules = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $bin = [IO.Path]::GetFullPath((Join-Path $modules '.bin'))
  $env:WADDLE_NODE_MODULES = $modules
  $env:NODE_PATH = $modules
  $pathParts = @([string]$env:PATH -split ';' | Where-Object { $_ })
  if (-not ($pathParts | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') })) { $env:PATH = "$bin;$env:PATH" }
  Write-Host "WADDLE_NODE_TOOLING=PASS modules=$modules bin=$bin layout=repo_physical"
  [pscustomobject]@{ status='PASS'; modules=$modules; bin=$bin }
}

function Test-WaddleDependencyTree {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot)
  Assert-WaddleWindowsOnly
  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $packagePath = Join-Path $RepoRoot 'package.json'
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason='package_json_missing' } }
  if (-not (Test-Path -LiteralPath $target -PathType Container)) { return [pscustomobject]@{ ready=$false; reason='repo_node_modules_missing' } }
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
    if (-not (Test-Path -LiteralPath (Join-Path $target $runtimeFile) -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="electron_runtime_missing:$runtimeFile" } }
  }
  $native = Join-Path $target '@typescript\typescript-win32-x64\package.json'
  if (-not (Test-Path -LiteralPath $native -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason='typescript_native_missing' } }
  foreach ($wrapper in @('copyfiles.cmd','electron.cmd','eslint.cmd','tsc-alias.cmd','tsx.cmd')) {
    if (-not (Test-Path -LiteralPath (Join-Path $target ('.bin\' + $wrapper)) -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="bin_wrapper_missing:$wrapper" } }
  }
  [pscustomobject]@{ ready=$true; reason='complete'; electron=[string]$electron.version }
}

function Write-WaddleDependencyState {
  param([Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$Fingerprint,[Parameter(Mandatory)][string]$Electron,[Parameter(Mandatory)][string]$Mode)
  $stateDir = Join-Path $WorkRoot 'state'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  $path = Join-Path $stateDir 'dependencies.json'
  [ordered]@{ schema='waddle-dependencies/v3'; platform='windows-x64'; root='node_modules'; fingerprint=$Fingerprint; electron=$Electron; mode=$Mode; updated_utc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Install-WaddleDependencies {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot)
  Assert-WaddleWindowsOnly
  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $cache = Join-Path $WorkRoot 'cache\yarn'
  New-Item -ItemType Directory -Force -Path $cache | Out-Null
  $yarn = Get-Command yarn.cmd -ErrorAction Stop
  $env:YARN_CACHE_FOLDER = $cache
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Push-Location $RepoRoot
  try {
    & $yarn.Source install --frozen-lockfile --non-interactive --cache-folder $cache | Out-Host
    $exit = $LASTEXITCODE
  } finally { Pop-Location }
  $sw.Stop()
  if ($exit -ne 0) { throw "WADDLE_DEPENDENCIES=FAIL exit=$exit duration_ms=$($sw.ElapsedMilliseconds) target=$target" }
  $electronManifest = Join-Path $target 'electron\package.json'
  if (-not (Test-Path -LiteralPath $electronManifest -PathType Leaf)) { throw "WADDLE_DEPENDENCIES=FAIL electron_missing=$electronManifest" }
  $electron = Get-Content -LiteralPath $electronManifest -Raw | ConvertFrom-Json
  if ([string]$electron.version -ne '10.4.7') { throw "WADDLE_DEPENDENCIES=FAIL electron_contract expected=10.4.7 actual=$($electron.version)" }
  Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
  Write-Host "WADDLE_DEPENDENCIES=PASS target=$target cache=$cache electron=$($electron.version) duration_ms=$($sw.ElapsedMilliseconds) layout=repo_physical"
  [pscustomobject]@{ status='PASS'; node_modules=$target; yarn_cache=$cache; electron=[string]$electron.version }
}

function Invoke-WaddleDependencyBootstrap {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot)
  Assert-WaddleWindowsOnly
  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $fingerprint = Get-WaddleDependencyFingerprint -RepoRoot $RepoRoot
  $statePath = Join-Path $WorkRoot 'state\dependencies.json'
  $tree = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  $stateMatches = $false
  if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
      $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      $stateMatches = ([string]$state.fingerprint -eq $fingerprint -and [string]$state.root -eq 'node_modules')
    } catch {}
  }
  if ($tree.ready -and ($stateMatches -or -not (Test-Path -LiteralPath $statePath -PathType Leaf))) {
    Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
    $mode = if ($stateMatches) { 'reused' } else { 'adopted_repo_existing' }
    Write-WaddleDependencyState -WorkRoot $WorkRoot -Fingerprint $fingerprint -Electron $tree.electron -Mode $mode | Out-Null
    Write-Host "WADDLE_DEPENDENCIES=PASS mode=$mode target=$target electron=$($tree.electron) fingerprint=$fingerprint layout=repo_physical runtime_isolated=true"
    return [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$tree.electron; fingerprint=$fingerprint; mode=$mode }
  }
  Write-Host "WADDLE_DEPENDENCIES=INSTALL reason=$($tree.reason) fingerprint_changed=$(-not $stateMatches) target=$target layout=repo_physical no_visual_studio_required=true"
  $null = Install-WaddleDependencies -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  $final = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  if (-not $final.ready) { throw "WADDLE_DEPENDENCIES=FAIL post_install_tree=$($final.reason)" }
  Write-WaddleDependencyState -WorkRoot $WorkRoot -Fingerprint $fingerprint -Electron $final.electron -Mode 'installed' | Out-Null
  Write-Host "WADDLE_DEPENDENCIES=PASS mode=installed target=$target electron=$($final.electron) fingerprint=$fingerprint layout=repo_physical no_visual_studio_required=true runtime_isolated=true"
  [pscustomobject]@{ status='PASS'; node_modules=$target; electron=$final.electron; fingerprint=$fingerprint; mode='installed' }
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
  if ([string]$manifest.schema -ne 'waddle-runtime-deployment/v4-repo-deps') { return [pscustomobject]@{ ready=$false; reason='legacy_runtime_layout' } }
  if ([string]$manifest.source_sha -ne $SourceSha) { return [pscustomobject]@{ ready=$false; reason='source_sha_mismatch' } }
  if ([string]$manifest.dependency_fingerprint -ne $DependencyFingerprint) { return [pscustomobject]@{ ready=$false; reason='fingerprint_mismatch' } }
  if ([string]$manifest.electron_version -ne $ElectronVersion) { return [pscustomobject]@{ ready=$false; reason='electron_version_mismatch' } }
  $electron = Join-Path $VersionRoot 'electron\electron.exe'
  $icu = Join-Path $VersionRoot 'electron\icudtl.dat'
  $flash = Join-Path $VersionRoot ('flash\' + [string]$manifest.flash_file)
  $appRoot = Join-Path $VersionRoot 'app'
  $entry = Join-Path $appRoot 'compiled\client\main.js'
  foreach ($required in @($electron,$icu,$flash,$entry)) { if (-not (Test-Path -LiteralPath $required)) { return [pscustomobject]@{ ready=$false; reason="file_missing:$required" } } }
  if ((Get-FileHash -LiteralPath $electron -Algorithm SHA256).Hash -ne [string]$manifest.electron_sha256) { return [pscustomobject]@{ ready=$false; reason='electron_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $icu -Algorithm SHA256).Hash -ne [string]$manifest.icudtl_sha256) { return [pscustomobject]@{ ready=$false; reason='icudtl_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $flash -Algorithm SHA256).Hash -ne [string]$manifest.flash_sha256) { return [pscustomobject]@{ ready=$false; reason='flash_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash -ne [string]$manifest.app_entry_sha256) { return [pscustomobject]@{ ready=$false; reason='app_entry_hash_mismatch' } }
  $repoModules = [IO.Path]::GetFullPath([string]$manifest.repo_node_modules)
  if (-not (Test-Path -LiteralPath $repoModules -PathType Container)) { return [pscustomobject]@{ ready=$false; reason='repo_node_modules_missing' } }
  [pscustomobject]@{ ready=$true; reason='valid'; manifest=$manifest; manifest_path=$manifestPath; root=$VersionRoot; electron=$electron; flash=$flash; app_root=$appRoot; app_entry=$entry; runtime_node_modules=$repoModules }
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

  $repoModules = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'node_modules'))
  if (-not (Test-Path -LiteralPath $repoModules -PathType Container)) { throw "WADDLE_RUNTIME_DEPLOY=FAIL repo_node_modules_missing=$repoModules" }
  $runtimeHome = Get-WaddleExternalRuntimeHome -AndroidBuildRoot $env:ANDROIDBUILD_ROOT
  $versions = Join-Path $runtimeHome 'Versions'
  New-Item -ItemType Directory -Force -Path $runtimeHome,$versions | Out-Null
  Remove-WaddleInactiveRuntimeDependencyCopies -AndroidBuildRoot $env:ANDROIDBUILD_ROOT

  $shaToken = if ($SourceSha.Length -gt 12) { $SourceSha.Substring(0,12) } else { $SourceSha }
  $fingerToken = if ($DependencyFingerprint.Length -gt 12) { $DependencyFingerprint.Substring(0,12) } else { $DependencyFingerprint }
  $target = Join-Path $versions ("$shaToken-$fingerToken-e$ElectronVersion-repodeps")
  $existing = Test-WaddleExternalRuntimeDeployment -VersionRoot $target -SourceSha $SourceSha -DependencyFingerprint $DependencyFingerprint -ElectronVersion $ElectronVersion
  if ($existing.ready) {
    $current = Set-WaddleExternalRuntimeCurrent -RuntimeHome $runtimeHome -VersionRoot $target
    $statePath = Write-WaddleExternalRuntimeState -WorkRoot $WorkRoot -Validation $existing -CurrentRoot $current -Mode 'reused'
    Remove-WaddleExternalRuntimeVersions -RuntimeHome $runtimeHome -KeepRoot $target
    Write-Host "WADDLE_RUNTIME_DEPLOY=PASS mode=reused root=$target current=$current node_modules=$repoModules dependency_layout=repo_physical work_execution=false"
    return [pscustomobject]@{ status='PASS'; mode='reused'; root=$target; current_root=$current; electron_executable=$existing.electron; ppapi_flash_path=$existing.flash; ppapi_flash_version=$PepperFlashVersion; app_root=$existing.app_root; app_entry=$existing.app_entry; runtime_node_modules=$repoModules; manifest=$statePath }
  }
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop }

  $staging = Join-Path $runtimeHome ('.staging-' + [Guid]::NewGuid().ToString('N'))
  $stagingElectron = Join-Path $staging 'electron'
  $stagingFlash = Join-Path $staging 'flash'
  $stagingCompiled = Join-Path $staging 'app\compiled'
  New-Item -ItemType Directory -Force -Path $stagingElectron,$stagingFlash,$stagingCompiled | Out-Null
  try {
    $sourceDist = Split-Path -Parent ([IO.Path]::GetFullPath($ElectronExecutable))
    $sourceCompiled = Join-Path $RepoRoot 'compiled'
    $sourceEntry = Join-Path $sourceCompiled 'client\main.js'
    foreach ($required in @($ElectronExecutable,(Join-Path $sourceDist 'icudtl.dat'),$PepperFlashPath,$sourceCompiled,$sourceEntry)) {
      if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_RUNTIME_DEPLOY=FAIL source_missing=$required" }
    }
    $robocopy = Get-Command robocopy.exe -ErrorAction Stop
    & $robocopy.Source $sourceDist $stagingElectron /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $electronExit = $LASTEXITCODE; $global:LASTEXITCODE = 0
    if ($electronExit -ge 8) { throw "WADDLE_RUNTIME_DEPLOY=FAIL electron_copy_exit=$electronExit" }
    & $robocopy.Source $sourceCompiled $stagingCompiled /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $compiledExit = $LASTEXITCODE; $global:LASTEXITCODE = 0
    if ($compiledExit -ge 8) { throw "WADDLE_RUNTIME_DEPLOY=FAIL compiled_copy_exit=$compiledExit" }
    $flashFile = [IO.Path]::GetFileName($PepperFlashPath)
    $stagingFlashPath = Join-Path $stagingFlash $flashFile
    Copy-Item -LiteralPath $PepperFlashPath -Destination $stagingFlashPath -Force
    $stagedElectron = Join-Path $stagingElectron 'electron.exe'
    $stagedIcu = Join-Path $stagingElectron 'icudtl.dat'
    $stagedEntry = Join-Path $stagingCompiled 'client\main.js'
    $manifest = [ordered]@{
      schema='waddle-runtime-deployment/v4-repo-deps'; status='PASS'; platform='windows-x64'; runtime_mode='external_deployment';
      runtime_home=$runtimeHome; source_sha=$SourceSha; dependency_fingerprint=$DependencyFingerprint; electron_version=$ElectronVersion;
      flash_file=$flashFile; ppapi_flash_version=$PepperFlashVersion; repo_node_modules=$repoModules;
      electron_sha256=(Get-FileHash -LiteralPath $stagedElectron -Algorithm SHA256).Hash;
      icudtl_sha256=(Get-FileHash -LiteralPath $stagedIcu -Algorithm SHA256).Hash;
      flash_sha256=(Get-FileHash -LiteralPath $stagingFlashPath -Algorithm SHA256).Hash;
      app_entry_sha256=(Get-FileHash -LiteralPath $stagedEntry -Algorithm SHA256).Hash;
      created_utc=[DateTime]::UtcNow.ToString('o')
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $staging 'runtime-deployment.json') -Encoding UTF8
    Move-Item -LiteralPath $staging -Destination $target -ErrorAction Stop
  } catch {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    throw
  }

  $validation = Test-WaddleExternalRuntimeDeployment -VersionRoot $target -SourceSha $SourceSha -DependencyFingerprint $DependencyFingerprint -ElectronVersion $ElectronVersion
  if (-not $validation.ready) { throw "WADDLE_RUNTIME_DEPLOY=FAIL validation=$($validation.reason) root=$target" }
  $current = Set-WaddleExternalRuntimeCurrent -RuntimeHome $runtimeHome -VersionRoot $target
  $statePath = Write-WaddleExternalRuntimeState -WorkRoot $WorkRoot -Validation $validation -CurrentRoot $current -Mode 'created'
  Remove-WaddleExternalRuntimeVersions -RuntimeHome $runtimeHome -KeepRoot $target
  Write-Host "WADDLE_RUNTIME_DEPLOY=PASS mode=created root=$target current=$current node_modules=$repoModules dependency_layout=repo_physical work_execution=false"
  [pscustomobject]@{ status='PASS'; mode='created'; root=$target; current_root=$current; electron_executable=$validation.electron; ppapi_flash_path=$validation.flash; ppapi_flash_version=$PepperFlashVersion; app_root=$validation.app_root; app_entry=$validation.app_entry; runtime_node_modules=$repoModules; manifest=$statePath }
}
