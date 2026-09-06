param(
  [Parameter(Mandatory=$false)][string]$ContextPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-local-runtime.ps1')
. (Join-Path $PSScriptRoot 'waddle-workspace-resilience.ps1')

$ctx = Get-WaddleContext -ContextPath $ContextPath
$repo = Resolve-WaddleRepoRoot -Context $ctx
$androidBuildRoot = Resolve-WaddleAndroidBuildRoot -Context $ctx
Import-WaddleCore -AndroidBuildRoot $androidBuildRoot
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $androidBuildRoot
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $androidBuildRoot
Enable-WaddleLocalNodeTooling -WorkRoot $workspace.work_root | Out-Null
$dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root

if ($ctx.ContainsKey('expected_sha') -and $ctx.expected_sha) {
  Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha ([string]$ctx.expected_sha) -AndroidBuildRoot $androidBuildRoot | Out-Null
}

$logDir = Join-Path $workspace.work_root 'logs\build'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "build-$stamp.log"
$summaryPath = Join-Path $workspace.work_root 'state\waddle-build-summary.json'

function Invoke-WaddleCommand {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  Write-Host "WADDLE_STEP=START name=$Name"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & yarn.cmd @Arguments
  $code = $LASTEXITCODE
  $sw.Stop()
  if ($code -ne 0) { throw "WADDLE_STEP=FAIL name=$Name exit=$code duration_ms=$($sw.ElapsedMilliseconds)" }
  Write-Host "WADDLE_STEP=PASS name=$Name duration_ms=$($sw.ElapsedMilliseconds)"
}

function Get-WaddlePackageManifest {
  param([Parameter(Mandatory)][string]$PackageName)
  $packageRoot = Join-Path (Join-Path $repo 'node_modules') $PackageName
  $manifestPath = Join-Path $packageRoot 'package.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "PACKAGE_MANIFEST=FAIL package=$PackageName reason=missing path=$manifestPath"
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  [pscustomobject]@{ package=$PackageName; root=$packageRoot; path=$manifestPath; version=[string]$manifest.version; manifest=$manifest }
}

function Get-WaddlePackageBin {
  param(
    [Parameter(Mandatory)][string]$PackageName,
    [Parameter(Mandatory)][string]$BinName
  )
  $packageInfo = Get-WaddlePackageManifest -PackageName $PackageName
  $relative = $null
  if ($packageInfo.manifest.bin -is [string]) {
    $relative = [string]$packageInfo.manifest.bin
  } elseif ($packageInfo.manifest.bin) {
    $property = $packageInfo.manifest.bin.PSObject.Properties | Where-Object { $_.Name -eq $BinName } | Select-Object -First 1
    if ($property) { $relative = [string]$property.Value }
  }
  if ([string]::IsNullOrWhiteSpace($relative)) {
    throw "PACKAGE_BIN=FAIL package=$PackageName bin=$BinName reason=bin_not_declared version=$($packageInfo.version)"
  }
  $path = [IO.Path]::GetFullPath((Join-Path $packageInfo.root $relative))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "PACKAGE_BIN=FAIL package=$PackageName bin=$BinName reason=target_missing version=$($packageInfo.version) path=$path"
  }
  Write-Host "PACKAGE_BIN=PASS package=$PackageName version=$($packageInfo.version) bin=$BinName path=$path"
  [pscustomobject]@{ package=$PackageName; version=$packageInfo.version; bin=$BinName; path=$path }
}

function Invoke-WaddleNodePackageBin {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$PackageName,
    [Parameter(Mandatory)][string]$BinName,
    [string[]]$Arguments = @()
  )
  $resolved = Get-WaddlePackageBin -PackageName $PackageName -BinName $BinName
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $node) { $node = Get-Command node -ErrorAction Stop }
  Write-Host "WADDLE_STEP=START name=$Name package=$PackageName package_version=$($resolved.version)"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & $node.Source $resolved.path @Arguments
  $code = $LASTEXITCODE
  $sw.Stop()
  if ($code -ne 0) { throw "WADDLE_STEP=FAIL name=$Name package=$PackageName exit=$code duration_ms=$($sw.ElapsedMilliseconds)" }
  Write-Host "WADDLE_STEP=PASS name=$Name package=$PackageName duration_ms=$($sw.ElapsedMilliseconds)"
}

function Test-WaddleInstalledCompilerContract {
  $typescriptLint = Get-WaddlePackageBin -PackageName 'typescript' -BinName 'tsc'
  if ([string]$typescriptLint.version -ne '6.0.3') { throw "TYPESCRIPT_LINT_CONTRACT=FAIL expected=6.0.3 actual=$($typescriptLint.version)" }
  $typescript7 = Get-WaddlePackageBin -PackageName 'typescript-7' -BinName 'tsc'
  if ([string]$typescript7.version -ne '7.0.2') { throw "TYPESCRIPT_BUILD_CONTRACT=FAIL expected=7.0.2 actual=$($typescript7.version)" }
  if ($env:OS -eq 'Windows_NT' -and [Environment]::Is64BitOperatingSystem) {
    $nativeManifest = Join-Path $repo 'node_modules\@typescript\typescript-win32-x64\package.json'
    if (-not (Test-Path -LiteralPath $nativeManifest -PathType Leaf)) { throw "TYPESCRIPT_NATIVE=FAIL platform=win32-x64 missing=$nativeManifest" }
    $native = Get-Content -LiteralPath $nativeManifest -Raw | ConvertFrom-Json
    if ([string]$native.version -ne [string]$typescript7.version) { throw "TYPESCRIPT_NATIVE=FAIL platform=win32-x64 compiler=$($typescript7.version) native=$($native.version)" }
    Write-Host "TYPESCRIPT_NATIVE=PASS platform=win32-x64 version=$($native.version)"
  }
  $eslint = Get-WaddlePackageBin -PackageName 'eslint' -BinName 'eslint'
  if ([string]$eslint.version -ne '8.57.1') { throw "ESLINT_CONTRACT=FAIL expected=8.57.1 actual=$($eslint.version)" }
  foreach ($packageName in @('@typescript-eslint/parser','@typescript-eslint/eslint-plugin')) {
    $info = Get-WaddlePackageManifest -PackageName $packageName
    if ([string]$info.version -ne '8.63.0') { throw "TYPESCRIPT_ESLINT_CONTRACT=FAIL package=$packageName expected=8.63.0 actual=$($info.version)" }
    Write-Host "PACKAGE_VERSION=PASS package=$packageName version=$($info.version)"
  }
  $alias = Get-WaddlePackageBin -PackageName 'tsc-alias' -BinName 'tsc-alias'
  $tsx = Get-WaddlePackageBin -PackageName 'tsx' -BinName 'tsx'
  Write-Host "COMPILER_CONTRACT=PASS build_typescript=$($typescript7.version) lint_typescript=$($typescriptLint.version) eslint=$($eslint.version) typescript_eslint=8.63.0 tsc_alias=$($alias.version) tsx=$($tsx.version) direct_package_bins=true"
}

function Reset-WaddleCompiledOutput {
  $link = Join-Path $repo 'compiled'
  $target = Join-Path $workspace.work_root 'build\compiled'
  if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      & cmd.exe /d /c "rmdir `"$link`"" | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "COMPILED_RESET=FAIL remove_junction exit=$LASTEXITCODE" }
    } else {
      Remove-Item -LiteralPath $link -Recurse -Force
    }
  }
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Ensure-WaddleJunction -LinkPath $link -TargetPath $target
  Write-Host "COMPILED_RESET=PASS target=$target"
}

Start-Transcript -LiteralPath $transcript -Force | Out-Null
try {
  Push-Location $repo
  try {
    Write-Host "WADDLE_DEPENDENCY_GATE=PASS mode=$($dependencies.mode) fingerprint=$($dependencies.fingerprint) no_visual_studio_required=true"
    Test-WaddleInstalledCompilerContract
    Invoke-WaddleNodePackageBin -Name 'build-packages' -PackageName 'tsx' -BinName 'tsx' -Arguments @('scripts/build-packages.ts')
    Reset-WaddleCompiledOutput
    Invoke-WaddleNodePackageBin -Name 'tsc' -PackageName 'typescript-7' -BinName 'tsc'
    Invoke-WaddleNodePackageBin -Name 'tsc-alias' -PackageName 'tsc-alias' -BinName 'tsc-alias'
    Invoke-WaddleNodePackageBin -Name 'build-browser' -PackageName 'typescript-7' -BinName 'tsc' -Arguments @('--project','tsconfig.esm.json')
    Invoke-WaddleCommand -Name 'copy-files' -Arguments @('copy-files')
    Invoke-WaddleNodePackageBin -Name 'lint' -PackageName 'eslint' -BinName 'eslint' -Arguments @('-c','.eslintrc','--ext','.ts','./src')
  } finally {
    Pop-Location
  }

  $summary = [ordered]@{
    schema='waddle-build-summary/v2'
    status='PASS'
    source_sha=if ($ctx.ContainsKey('expected_sha')) { [string]$ctx.expected_sha } else { '' }
    repo_root=$repo
    work_root=$workspace.work_root
    node_modules=(Join-Path $workspace.work_root 'dependencies\node_modules')
    compiled=(Join-Path $workspace.work_root 'build\compiled')
    dist=(Join-Path $workspace.work_root 'dist\package')
    yarn_cache=$env:YARN_CACHE_FOLDER
    node_path=$env:NODE_PATH
    dependency_fingerprint=$dependencies.fingerprint
    dependency_mode=$dependencies.mode
    visual_studio='NOT_REQUIRED'
    optional_register_scheme='NOT_EXECUTED_WHEN_DEPENDENCY_FINGERPRINT_VALID'
    build_typescript='7.0.2'
    lint_typescript='6.0.3'
    eslint='8.57.1'
    typescript_eslint='8.63.0'
    transcript=$transcript
    completed_utc=[DateTime]::UtcNow.ToString('o')
    android='NOT_APPLICABLE'
    physical_adb='NOT_APPLICABLE'
  }
  $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  Write-Host "WADDLE_BUILD_SUMMARY=$summaryPath"
  Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
  Write-Host 'WADDLE_BUILD=PASS'
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
