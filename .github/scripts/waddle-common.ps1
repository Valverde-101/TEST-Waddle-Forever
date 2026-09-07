Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-WaddleWindowsOnly {
  if ($env:OS -ne 'Windows_NT') { throw "WADDLE_PLATFORM=FAIL windows_required actual=$($env:OS)" }
  if (-not [Environment]::Is64BitOperatingSystem) { throw 'WADDLE_PLATFORM=FAIL windows_x64_required' }
  if (-not [Environment]::Is64BitProcess) { throw 'WADDLE_PLATFORM=FAIL powershell_x64_required' }
  Write-Host "WADDLE_PLATFORM=PASS os=Windows arch=x64 powershell=$($PSVersionTable.PSVersion)"
}

function Get-WaddleContext {
  param([string]$ContextPath)
  if ([string]::IsNullOrWhiteSpace($ContextPath)) { return @{} }
  if (-not (Test-Path -LiteralPath $ContextPath -PathType Leaf)) {
    throw "WADDLE_CONTEXT=FAIL missing=$ContextPath"
  }
  $raw = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
  $ctx = @{}
  foreach ($p in $raw.PSObject.Properties) { $ctx[$p.Name] = $p.Value }
  return $ctx
}

function Resolve-WaddleRepoRoot {
  param([hashtable]$Context)
  if ($Context.ContainsKey('repo_root') -and $Context.repo_root) {
    return [IO.Path]::GetFullPath([string]$Context.repo_root)
  }
  return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Resolve-WaddleAndroidBuildRoot {
  param([hashtable]$Context)

  $candidates = New-Object System.Collections.Generic.List[string]
  if ($Context.ContainsKey('androidbuild_root') -and $Context.androidbuild_root) {
    $candidates.Add([string]$Context.androidbuild_root)
  }
  if ($env:ANDROIDBUILD_ROOT -and -not $candidates.Contains([string]$env:ANDROIDBUILD_ROOT)) {
    $candidates.Add([string]$env:ANDROIDBUILD_ROOT)
  }

  try {
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $repoInfo = [IO.DirectoryInfo]$repoRoot
    if ($repoInfo.Parent -and $repoInfo.Parent.Name -ieq 'Repositories' -and $repoInfo.Parent.Parent) {
      $inferred = $repoInfo.Parent.Parent.FullName
      if (-not $candidates.Contains($inferred)) { $candidates.Add($inferred) }
    }
  } catch {}

  foreach ($drive in [IO.DriveInfo]::GetDrives()) {
    try {
      if (-not $drive.IsReady) { continue }
      $candidate = [IO.Path]::Combine($drive.RootDirectory.FullName, 'AndroidBuild')
      if (-not $candidates.Contains($candidate)) { $candidates.Add($candidate) }
    } catch {}
  }

  foreach ($candidate in $candidates) {
    try { $full = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path } catch { continue }
    $module = Join-Path $full 'Core\Current\AndroidBuild.psd1'
    if (Test-Path -LiteralPath $module -PathType Leaf) {
      return [IO.Path]::GetFullPath($full)
    }
  }
  throw 'ANDROIDBUILD_ROOT=FAIL current_core_not_found'
}

function Get-WaddleRequiredCoreVersion {
  $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  $configPath = Join-Path $repoRoot '.androidbuild.json'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "ANDROIDBUILD_CONFIG=FAIL missing=$configPath"
  }
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $required = [string]$config.core.minimum_version
  if ([string]::IsNullOrWhiteSpace($required)) {
    throw 'ANDROIDBUILD_CONFIG=FAIL core.minimum_version_missing'
  }
  try { [void][version]$required } catch { throw "ANDROIDBUILD_CONFIG=FAIL invalid_core_minimum=$required" }
  return $required
}

function Import-WaddleCore {
  param([string]$AndroidBuildRoot)
  $module = Join-Path $AndroidBuildRoot 'Core\Current\AndroidBuild.psd1'
  if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw "ANDROIDBUILD_CORE=FAIL missing=$module"
  }
  Import-Module $module -Force
  $version = [string](Get-AndroidBuildCoreVersion)
  $required = Get-WaddleRequiredCoreVersion
  if ([version]$version -lt [version]$required) {
    throw "ANDROIDBUILD_CORE=FAIL required=$required actual=$version"
  }
  Write-Host "ANDROIDBUILD_CORE=PASS version=$version required=$required root=$AndroidBuildRoot"
}

function Ensure-WaddleDirectory {
  param([Parameter(Mandatory)][string]$Path)
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Ensure-WaddleJunction {
  param(
    [Parameter(Mandatory)][string]$LinkPath,
    [Parameter(Mandatory)][string]$TargetPath
  )
  $target = [IO.Path]::GetFullPath($TargetPath)
  Ensure-WaddleDirectory $target

  if (Test-Path -LiteralPath $LinkPath) {
    $item = Get-Item -LiteralPath $LinkPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      $actualTargetRaw = $null
      try { $actualTargetRaw = @($item.Target)[0] } catch {}
      if (-not $actualTargetRaw) { throw "WORK_JUNCTION=FAIL target_unreadable=$LinkPath" }
      if ([IO.Path]::IsPathRooted([string]$actualTargetRaw)) {
        $actual = [IO.Path]::GetFullPath([string]$actualTargetRaw)
      } else {
        $actual = [IO.Path]::GetFullPath((Join-Path $item.Parent.FullName ([string]$actualTargetRaw)))
      }
      if ($actual.TrimEnd('\') -ieq $target.TrimEnd('\')) {
        Write-Host "WORK_JUNCTION=PASS path=$LinkPath target=$target mode=existing"
        return
      }
      & cmd.exe /d /c "rmdir `"$LinkPath`"" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "WORK_JUNCTION=FAIL remove_wrong_target=$LinkPath exit=$LASTEXITCODE" }
    } else {
      $hasEntries = @(Get-ChildItem -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue).Count -gt 0
      if ($hasEntries) {
        $robocopy = Get-Command robocopy.exe -ErrorAction Stop
        & $robocopy.Source $LinkPath $target /E /MOVE /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Host
        if ($LASTEXITCODE -ge 8) { throw "WORK_JUNCTION=FAIL migrate=$LinkPath robocopy_exit=$LASTEXITCODE" }
        $global:LASTEXITCODE = 0
      }
      Remove-Item -LiteralPath $LinkPath -Force -Recurse -ErrorAction SilentlyContinue
    }
  }

  New-Item -ItemType Junction -Path $LinkPath -Target $target | Out-Null
  Write-Host "WORK_JUNCTION=PASS path=$LinkPath target=$target mode=created"
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
    'dependencies\current\node_modules',
    'cache\yarn',
    'runtime\interactive',
    'downloads',
    'content',
    'swf-analysis',
    'diagnostics',
    'logs\build',
    'logs\runtime',
    'dist\package',
    'tmp'
  )) {
    Ensure-WaddleDirectory (Join-Path $work $relative)
  }

  $legacyDependencies = Join-Path $work 'dependencies\node_modules'
  if (Test-Path -LiteralPath $legacyDependencies) {
    Write-Host "WADDLE_LEGACY_DEPENDENCIES=INFO path=$legacyDependencies action=preserved_lock_safe_migration"
  }

  $currentModules = Join-Path $work 'dependencies\current\node_modules'
  Ensure-WaddleJunction -LinkPath (Join-Path $RepoRoot 'node_modules') -TargetPath $currentModules
  Ensure-WaddleJunction -LinkPath (Join-Path $RepoRoot 'compiled') -TargetPath (Join-Path $work 'build\compiled')
  Ensure-WaddleJunction -LinkPath (Join-Path $RepoRoot 'dist') -TargetPath (Join-Path $work 'dist\package')

  $envPath = Join-Path $RepoRoot '.env'
  $templatePath = Join-Path $RepoRoot 'template.env'
  if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'WADDLE_ENV=FAIL template.env_missing' }
    Copy-Item -LiteralPath $templatePath -Destination $envPath
    Write-Host 'WADDLE_ENV=PASS mode=created_from_template'
  } else {
    Write-Host 'WADDLE_ENV=PASS mode=existing'
  }

  $env:YARN_CACHE_FOLDER = Join-Path $work 'cache\yarn'
  $env:WADDLE_WORK_ROOT = $work
  $env:WADDLE_REPO_ROOT = $RepoRoot
  $env:WADDLE_NODE_MODULES = $currentModules
  $env:ANDROIDBUILD_ROOT = $AndroidBuildRoot

  [pscustomobject]@{
    status = 'PASS'
    repo_root = $RepoRoot
    work_root = $work
    node_modules = $currentModules
    yarn_cache = $env:YARN_CACHE_FOLDER
  }
}

function Test-WaddleToolchain {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)
  Assert-WaddleWindowsOnly

  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $node) { throw 'NODE=FAIL missing' }
  $nodeVersion = (& $node.Source --version).Trim().TrimStart('v')
  if ($nodeVersion -ne '20.19.0') { throw "NODE=FAIL required=20.19.0 actual=$nodeVersion" }

  $yarn = Get-Command yarn.cmd -ErrorAction SilentlyContinue
  if (-not $yarn) { throw 'YARN=FAIL missing' }
  $yarnVersion = (& $yarn.Source --version).Trim()
  if ($yarnVersion -ne '1.22.22') { throw "YARN=FAIL required=1.22.22 actual=$yarnVersion" }

  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  $npmVersion = if ($npm) { (& $npm.Source --version).Trim() } else { 'missing' }

  Write-Host "NODE=PASS version=$nodeVersion"
  Write-Host "YARN=PASS version=$yarnVersion"
  Write-Host "NPM=INFO version=$npmVersion"

  $ffdec = Ensure-AndroidBuildFFDec -AndroidBuildRoot $AndroidBuildRoot -Version '26.2.1'
  Write-Host "FFDEC=PASS version=26.2.1 path=$($ffdec.path)"

  [pscustomobject]@{
    status = 'PASS'
    node = $nodeVersion
    yarn = $yarnVersion
    npm = $npmVersion
    ffdec = $ffdec.path
  }
}
