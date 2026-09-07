[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ExpectedSha,
  [string]$Repository = 'Valverde-101/TEST-Waddle-Forever',
  [string]$RunId = 'manual-certification',
  [string]$JobId = 'certification',
  [string]$RunnerName = $env:COMPUTERNAME,
  [string]$AndroidBuildRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')
. (Join-Path $PSScriptRoot 'waddle-local-runtime.ps1')
. (Join-Path $PSScriptRoot 'waddle-workspace-resilience.ps1')

$ctx = @{}
if ($AndroidBuildRoot) { $ctx.androidbuild_root = $AndroidBuildRoot }
$repo = Resolve-WaddleRepoRoot -Context $ctx
$root = Resolve-WaddleAndroidBuildRoot -Context $ctx
Assert-WaddleWindowsOnly
Import-WaddleCore -AndroidBuildRoot $root
$managedNode = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $root
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $root
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $root
Enable-WaddleLocalNodeTooling -WorkRoot $workspace.work_root | Out-Null
$env:ANDROIDBUILD_ROOT = $root

Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha $ExpectedSha -AndroidBuildRoot $root | Out-Null
Write-Host "WADDLE_CERT_EXACT_HEAD=PASS sha=$ExpectedSha core=$(Get-AndroidBuildCoreVersion) repo=$repo"

$envPath = Update-WaddleLocalEnv -RepoRoot $repo -AndroidBuildRoot $root -WorkRoot $workspace.work_root -FFDecPath $toolchain.ffdec
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_HOME' -Value $managedNode.home
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_EXE' -Value $managedNode.node
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NPM_CMD' -Value $managedNode.npm
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_YARN_CMD' -Value $managedNode.yarn
Import-WaddleLocalEnv -Path $envPath

$certStateDir = Join-Path $workspace.work_root 'state'
$certLogDir = Join-Path $workspace.work_root 'logs\certification'
New-Item -ItemType Directory -Force -Path $certStateDir,$certLogDir | Out-Null
$certStatePath = Join-Path $certStateDir 'waddle-certification.json'
$clientStatePath = Join-Path $certStateDir 'waddle-client.json'
$summaryPath = Join-Path $certStateDir 'waddle-build-summary.json'
$runtimeStatePath = Join-Path $certStateDir 'runtime-snapshot.json'
$workPrefix = [IO.Path]::GetFullPath($workspace.work_root).TrimEnd('\') + '\'
$runtimeHome = Get-WaddleExternalRuntimeHome -AndroidBuildRoot $root
$runtimePrefix = [IO.Path]::GetFullPath($runtimeHome).TrimEnd('\') + '\'
$env:WADDLE_NONINTERACTIVE = '1'
$startedClientId = 0
$certWatch = [Diagnostics.Stopwatch]::StartNew()

function Assert-WaddleExternalPath {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "WADDLE_CERT=FAIL empty_path label=$Label" }
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_CERT=FAIL runtime_inside_work label=$Label path=$full"
  }
  return $full
}

function Invoke-WaddlePinnedYarnInstall {
  param([Parameter(Mandatory)][string]$Phase)
  $yarn = [string]$env:WADDLE_YARN_CMD
  if ([string]::IsNullOrWhiteSpace($yarn) -or -not (Test-Path -LiteralPath $yarn -PathType Leaf)) {
    $resolved = Get-Command yarn.cmd -ErrorAction Stop
    $yarn = $resolved.Source
  }
  Push-Location $repo
  try {
    & $yarn install --frozen-lockfile --non-interactive
    $code = $LASTEXITCODE
  } finally { Pop-Location }
  $global:LASTEXITCODE = 0
  if ($code -ne 0) { throw "WADDLE_CERT=FAIL yarn_install phase=$Phase exit=$code yarn=$yarn" }
  Write-Host "WADDLE_CERT_YARN=PASS phase=$Phase yarn=$yarn"
}

function Stop-WaddleClientBestEffort {
  Push-Location $repo
  try {
    & cmd.exe /d /c 'Waddle-Stop.cmd' | Out-Host
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { Write-Host "WADDLE_CERT_STOP=WARN exit=$code" }
  } catch {
    Write-Host "WADDLE_CERT_STOP=WARN error=$($_.Exception.Message)"
  } finally { Pop-Location }
}

try {
  # 1) Real human setup contract: managed Node/Yarn, dependency bootstrap,
  # Pepper Flash, Electron and package index regeneration.
  Push-Location $repo
  try {
    & cmd.exe /d /c 'Waddle-Setup.cmd' | Out-Host
    $setupExit = $LASTEXITCODE
  } finally { Pop-Location }
  $global:LASTEXITCODE = 0
  if ($setupExit -ne 0) { throw "WADDLE_CERT=FAIL setup_exit=$setupExit" }
  $packageInfo = Join-Path $repo 'src\server\game-data\package-info.ts'
  if (-not (Test-Path -LiteralPath $packageInfo -PathType Leaf)) { throw "WADDLE_CERT=FAIL package_info_missing=$packageInfo" }
  if ((Get-Item -LiteralPath $packageInfo).Length -le 20) { throw "WADDLE_CERT=FAIL package_info_empty=$packageInfo" }
  Write-Host "WADDLE_CERT_SETUP=PASS package_info=$packageInfo"

  # 2) Prove upstream-style direct Yarn install remains valid outside wrappers.
  Invoke-WaddlePinnedYarnInstall -Phase 'before_build'
  foreach ($required in @(
    (Join-Path $repo 'node_modules\electron\package.json'),
    (Join-Path $repo 'node_modules\.bin\copyfiles.cmd'),
    (Join-Path $repo 'node_modules\tsx\package.json')
  )) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "WADDLE_CERT=FAIL dependency_missing=$required" }
  }

  # 3) Canonical Core build. This includes build-packages, TypeScript 7,
  # tsc-alias, browser build, asset/view copying and lint on one exact SHA.
  $build = Invoke-AndroidBuildBuild `
    -RepoRoot $repo `
    -AndroidBuildRoot $root `
    -ExpectedSha $ExpectedSha `
    -Repository $Repository `
    -RunId $RunId `
    -JobId "$JobId-build" `
    -RunnerName $RunnerName `
    -LeaseWaitSeconds 1200
  if ([string]$build.status -ne 'PASS') { throw "WADDLE_CERT=FAIL build_status=$($build.status)" }
  if ([string]$build.provenance.source_sha -ne $ExpectedSha) { throw "WADDLE_CERT=FAIL build_sha=$($build.provenance.source_sha) expected=$ExpectedSha" }
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "WADDLE_CERT=FAIL build_summary_missing=$summaryPath" }
  $buildSummary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
  if ([string]$buildSummary.status -ne 'PASS' -or [string]$buildSummary.source_sha -ne $ExpectedSha) {
    throw "WADDLE_CERT=FAIL build_summary status=$($buildSummary.status) sha=$($buildSummary.source_sha)"
  }
  Write-Host "WADDLE_CERT_BUILD=PASS sha=$ExpectedSha duration_ms=$($build.provenance.duration_ms)"

  # 4) External immutable runtime deployment and Flash production probe.
  $dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
  $sourceElectron = Test-WaddleElectronRuntime -WorkRoot $workspace.work_root -ExpectedVersion $dependencies.electron
  $sourceFlash = Test-WaddlePepperFlash -RepoRoot $repo
  $runtime = New-WaddleRuntimeSnapshot `
    -RepoRoot $repo `
    -WorkRoot $workspace.work_root `
    -ElectronExecutable $sourceElectron.executable `
    -ElectronVersion $sourceElectron.version `
    -PepperFlashPath $sourceFlash.path `
    -PepperFlashVersion $sourceFlash.version `
    -SourceSha $ExpectedSha `
    -DependencyFingerprint $dependencies.fingerprint

  $runtimeRoot = Assert-WaddleExternalPath -Path ([string]$runtime.root) -Label 'runtime_root'
  $runtimeElectron = Assert-WaddleExternalPath -Path ([string]$runtime.electron_executable) -Label 'electron'
  $runtimeFlash = Assert-WaddleExternalPath -Path ([string]$runtime.ppapi_flash_path) -Label 'flash'
  $runtimeEntry = Assert-WaddleExternalPath -Path ([string]$runtime.app_entry) -Label 'app_entry'
  $runtimeModules = Assert-WaddleExternalPath -Path ([string]$runtime.runtime_node_modules) -Label 'runtime_node_modules'
  if (-not $runtimeRoot.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "WADDLE_CERT=FAIL runtime_home=$runtimeRoot expected=$runtimeHome" }

  $probe = Join-Path $repo 'scripts\flash-runtime-probe.js'
  if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw "WADDLE_CERT=FAIL flash_probe_missing=$probe" }
  $probeState = Join-Path $certStateDir 'flash-runtime-probe.json'
  $probeOut = Join-Path $certLogDir 'flash-runtime-probe.stdout.log'
  $probeErr = Join-Path $certLogDir 'flash-runtime-probe.stderr.log'
  Remove-Item -LiteralPath $probeState,$probeOut,$probeErr -Force -ErrorAction SilentlyContinue
  Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
  $env:WADDLE_FLASH_PROBE_RESULT = $probeState
  $env:WADDLE_SOURCE_ROOT = $repo
  $env:WADDLE_RUNTIME_APP_ROOT = [string]$runtime.app_root
  $env:WADDLE_PPAPI_FLASH_PATH = $runtimeFlash
  $env:WADDLE_PPAPI_FLASH_VERSION = [string]$runtime.ppapi_flash_version
  $env:WADDLE_RUNTIME_ROOT = $runtimeRoot
  $env:WADDLE_RUNTIME_NODE_MODULES = $runtimeModules
  $env:WADDLE_NODE_MODULES = $runtimeModules
  $env:NODE_PATH = $runtimeModules
  $probeProcess = Start-Process -FilePath $runtimeElectron -ArgumentList ('"'+$probe+'"') -WorkingDirectory $repo -RedirectStandardOutput $probeOut -RedirectStandardError $probeErr -PassThru
  if (-not $probeProcess.WaitForExit(40000)) {
    try { $probeProcess.Kill() } catch {}
    throw "WADDLE_CERT=FAIL flash_probe_timeout stdout=$probeOut stderr=$probeErr"
  }
  $probeProcess.Refresh()
  if (-not (Test-Path -LiteralPath $probeState -PathType Leaf)) { throw "WADDLE_CERT=FAIL flash_probe_state_missing=$probeState" }
  $probeResult = Get-Content -LiteralPath $probeState -Raw | ConvertFrom-Json
  if ([int]$probeProcess.ExitCode -ne 0 -or [string]$probeResult.status -ne 'PASS') { throw "WADDLE_CERT=FAIL flash_probe exit=$($probeProcess.ExitCode) status=$($probeResult.status) reason=$($probeResult.reason)" }
  if ([string]$probeResult.schema -ne 'waddle-flash-runtime-probe/v4') { throw "WADDLE_CERT=FAIL flash_schema=$($probeResult.schema)" }
  if ([int]$probeResult.root_status -ne 200 -or [int]$probeResult.boots_status -ne 200) { throw "WADDLE_CERT=FAIL flash_http root=$($probeResult.root_status) boots=$($probeResult.boots_status)" }
  if ([string]$probeResult.boots_content_type -notmatch 'application/x-shockwave-flash') { throw "WADDLE_CERT=FAIL flash_mime=$($probeResult.boots_content_type)" }
  if (-not [bool]$probeResult.renderer.mimePresent -or -not [bool]$probeResult.renderer.mimeEnabledPlugin -or -not [bool]$probeResult.renderer.objectPresent) { throw 'WADDLE_CERT=FAIL flash_renderer_contract' }
  if ([bool]$probeResult.fallback_visible -or -not [bool]$probeResult.scriptable_flash_object -or -not [bool]$probeResult.production_instantiated) { throw 'WADDLE_CERT=FAIL flash_not_instantiated' }
  if ([IO.Path]::GetFullPath([string]$probeResult.plugin_path) -ne $runtimeFlash) { throw "WADDLE_CERT=FAIL flash_plugin actual=$($probeResult.plugin_path) expected=$runtimeFlash" }
  Write-Host "WADDLE_CERT_FLASH=PASS runtime=$runtimeRoot plugin=$runtimeFlash boots=200 instantiated=true"

  # 5) User-facing Start must build, deploy, launch a detached external client,
  # write RUNNING state and return control while the client stays alive.
  $startWatch = [Diagnostics.Stopwatch]::StartNew()
  Push-Location $repo
  try {
    & cmd.exe /d /c 'Waddle-Start.cmd' | Out-Host
    $startExit = $LASTEXITCODE
  } finally { Pop-Location }
  $global:LASTEXITCODE = 0
  $startWatch.Stop()
  if ($startExit -ne 0) { throw "WADDLE_CERT=FAIL actual_start_exit=$startExit" }
  if (-not (Test-Path -LiteralPath $clientStatePath -PathType Leaf)) { throw "WADDLE_CERT=FAIL client_state_missing=$clientStatePath" }
  $clientState = Get-Content -LiteralPath $clientStatePath -Raw | ConvertFrom-Json
  if ([string]$clientState.schema -ne 'waddle-client-state/v8') { throw "WADDLE_CERT=FAIL client_schema=$($clientState.schema)" }
  if ([string]$clientState.status -ne 'RUNNING' -or [string]$clientState.source_sha -ne $ExpectedSha) { throw "WADDLE_CERT=FAIL client_state status=$($clientState.status) sha=$($clientState.source_sha)" }
  if ([string]$clientState.runtime_mode -ne 'external_deployment' -or [string]$clientState.electron_launch_mode -ne 'external_runtime_detached_cmd_start') { throw "WADDLE_CERT=FAIL client_runtime mode=$($clientState.runtime_mode) launch=$($clientState.electron_launch_mode)" }
  foreach ($pair in @(
    @{name='runtime_root'; value=[string]$clientState.runtime_root},
    @{name='app_entry'; value=[string]$clientState.runtime_app_entry},
    @{name='node_modules'; value=[string]$clientState.runtime_node_modules},
    @{name='electron'; value=[string]$clientState.electron_executable},
    @{name='flash'; value=[string]$clientState.ppapi_flash_path}
  )) { Assert-WaddleExternalPath -Path $pair.value -Label $pair.name | Out-Null }
  if (-not ([IO.Path]::GetFullPath([string]$clientState.runtime_root)).StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "WADDLE_CERT=FAIL client_runtime_home=$($clientState.runtime_root)" }
  $startedClientId = [int]$clientState.pid
  $clientProcess = Get-Process -Id $startedClientId -ErrorAction Stop
  $clientProcess.Refresh()
  if ($clientProcess.HasExited) { throw "WADDLE_CERT=FAIL client_exited process_id=$startedClientId" }
  $clientCim = Get-CimInstance Win32_Process -Filter "ProcessId=$startedClientId" -ErrorAction Stop
  if ([IO.Path]::GetFullPath([string]$clientCim.ExecutablePath) -ne [IO.Path]::GetFullPath([string]$clientState.electron_executable)) { throw "WADDLE_CERT=FAIL client_executable actual=$($clientCim.ExecutablePath) expected=$($clientState.electron_executable)" }
  if ($startWatch.Elapsed.TotalMinutes -ge 3) { throw "WADDLE_CERT=FAIL launcher_return_too_slow duration_ms=$($startWatch.ElapsedMilliseconds)" }
  Write-Host "WADDLE_CERT_START=PASS process_id=$startedClientId launcher_return_ms=$($startWatch.ElapsedMilliseconds) runtime=$($clientState.runtime_root)"

  # 6) Prove the live external client cannot lock the mutable Yarn tree.
  Invoke-WaddlePinnedYarnInstall -Phase 'while_client_running'
  $clientProcess.Refresh()
  if ($clientProcess.HasExited) { throw "WADDLE_CERT=FAIL client_died_during_yarn process_id=$startedClientId" }
  Write-Host "WADDLE_CERT_RUNTIME_ISOLATION=PASS process_id=$startedClientId yarn_while_client_running=true"

  # 7) Stop must not need Core/workspace junction initialization and must clean
  # both state-owned and recoverable Waddle process trees.
  Stop-WaddleClientBestEffort
  Start-Sleep -Seconds 1
  if (Get-Process -Id $startedClientId -ErrorAction SilentlyContinue) { throw "WADDLE_CERT=FAIL stop_left_client process_id=$startedClientId" }
  $postState = Get-Content -LiteralPath $clientStatePath -Raw | ConvertFrom-Json
  if ([string]$postState.status -ne 'STOPPED') { throw "WADDLE_CERT=FAIL stop_state=$($postState.status)" }

  # 8) No executable Waddle runtime may remain under .work after certification.
  $legacy = @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $exe = [string]$_.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try { return ([IO.Path]::GetFullPath($exe)).StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase) } catch { return $false }
  })
  if ($legacy.Count -gt 0) { throw "WADDLE_CERT=FAIL legacy_electron_inside_work count=$($legacy.Count) ids=$((@($legacy.ProcessId) -join ','))" }

  Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha $ExpectedSha -AndroidBuildRoot $root | Out-Null
  $certWatch.Stop()
  $final = [ordered]@{
    schema='waddle-certification/v1'
    status='PASS'
    source_sha=$ExpectedSha
    repository=$Repository
    core_version=[string](Get-AndroidBuildCoreVersion)
    node='20.19.0'
    yarn='1.22.22'
    electron=[string]$dependencies.electron
    flash=[string]$sourceFlash.version
    package_index='PASS'
    direct_yarn='PASS'
    build='PASS'
    flash_runtime='PASS'
    actual_start='PASS'
    runtime_isolation='PASS'
    stop='PASS'
    legacy_work_runtime_count=0
    runtime_home=$runtimeHome
    launcher_return_ms=[int64]$startWatch.ElapsedMilliseconds
    duration_ms=[int64]$certWatch.ElapsedMilliseconds
    completed_utc=[DateTime]::UtcNow.ToString('o')
  }
  $final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $certStatePath -Encoding UTF8
  Write-Host "WADDLE_CERTIFICATION=PASS sha=$ExpectedSha duration_ms=$($certWatch.ElapsedMilliseconds) state=$certStatePath"
} catch {
  try { Stop-WaddleClientBestEffort } catch {}
  $certWatch.Stop()
  [ordered]@{
    schema='waddle-certification/v1'
    status='FAIL'
    source_sha=$ExpectedSha
    repository=$Repository
    error=$_.Exception.Message
    duration_ms=[int64]$certWatch.ElapsedMilliseconds
    failed_utc=[DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $certStatePath -Encoding UTF8
  Write-Host "WADDLE_CERTIFICATION=FAIL sha=$ExpectedSha error=$($_.Exception.Message) state=$certStatePath"
  throw
} finally {
  Remove-Item Env:WADDLE_NONINTERACTIVE -ErrorAction SilentlyContinue
}
