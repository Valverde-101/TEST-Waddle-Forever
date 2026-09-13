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
$dependencyStatePath = Join-Path $certStateDir 'dependencies.json'
$workPrefix = [IO.Path]::GetFullPath($workspace.work_root).TrimEnd('\') + '\'
$runtimeHome = Get-WaddleExternalRuntimeHome -AndroidBuildRoot $root
$repoRuntimeRoot = [IO.Path]::GetFullPath($repo).TrimEnd('\')
$repoModules = [IO.Path]::GetFullPath((Join-Path $repo 'node_modules'))
$repoElectron = [IO.Path]::GetFullPath((Join-Path $repoModules 'electron\dist\electron.exe'))
$repoFlash = [IO.Path]::GetFullPath((Join-Path $repo 'assets\flash\pepflashplayer64_32_0_0_303.dll'))
$repoEntry = [IO.Path]::GetFullPath((Join-Path $repo 'compiled\client\main.js'))
$env:WADDLE_NONINTERACTIVE = '1'
$startedClientId = 0
$certWatch = [Diagnostics.Stopwatch]::StartNew()

function Assert-WaddleRepoRuntimePath {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "WADDLE_CERT=FAIL empty_path label=$Label" }
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_CERT=FAIL runtime_inside_work label=$Label path=$full"
  }
  $repoPrefix = $repoRuntimeRoot + '\'
  if ($full.TrimEnd('\') -ine $repoRuntimeRoot -and -not $full.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_CERT=FAIL runtime_outside_repo label=$Label path=$full repo=$repoRuntimeRoot"
  }
  return $full
}

function Invoke-WaddleCommandWithTimeout {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)][string]$Phase,
    [int]$TimeoutSeconds = 60
  )

  $stdout = Join-Path $certLogDir ("$Phase.stdout.log")
  $stderr = Join-Path $certLogDir ("$Phase.stderr.log")
  Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue

  $proc = Start-Process `
    -FilePath $env:ComSpec `
    -ArgumentList @('/d','/s','/c',$Command) `
    -WorkingDirectory $repo `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru `
    -ErrorAction Stop

  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { & taskkill.exe /PID $proc.Id /T /F | Out-Null } catch {}
    throw "WADDLE_CERT=FAIL command_timeout phase=$Phase timeout_seconds=$TimeoutSeconds command=$Command stdout=$stdout stderr=$stderr"
  }
  $proc.WaitForExit()
  $proc.Refresh()
  if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue | Out-Host }
  if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue | Out-Host }
  $exitCode = [int]$proc.ExitCode
  if ($exitCode -ne 0) { throw "WADDLE_CERT=FAIL command_exit phase=$Phase exit=$exitCode command=$Command stdout=$stdout stderr=$stderr" }
  Write-Host "WADDLE_CERT_COMMAND=PASS phase=$Phase exit=0 timeout_seconds=$TimeoutSeconds"
}

function Stop-WaddleClientBestEffort {
  try { Invoke-WaddleCommandWithTimeout -Command 'Waddle-Stop.cmd' -Phase 'stop' -TimeoutSeconds 30 }
  catch { Write-Host "WADDLE_CERT_STOP=WARN error=$($_.Exception.Message)" }
}

function Assert-WaddleDependencyTreeReadOnly {
  param([Parameter(Mandatory)]$Dependencies)
  if ([IO.Path]::GetFullPath([string]$Dependencies.node_modules) -ne $repoModules) { throw "WADDLE_CERT=FAIL dependency_root actual=$($Dependencies.node_modules) expected=$repoModules" }
  if ([string]$Dependencies.electron -ne '10.4.7') { throw "WADDLE_CERT=FAIL dependency_electron actual=$($Dependencies.electron) expected=10.4.7" }
  if ([string]$Dependencies.mode -notin @('reused','adopted_repo_existing')) { throw "WADDLE_CERT=FAIL dependency_not_reused_after_setup mode=$($Dependencies.mode)" }
  if (-not (Test-Path -LiteralPath $dependencyStatePath -PathType Leaf)) { throw "WADDLE_CERT=FAIL dependency_state_missing=$dependencyStatePath" }
  $dependencyState = Get-Content -LiteralPath $dependencyStatePath -Raw | ConvertFrom-Json
  if ([string]$dependencyState.root -ne 'node_modules') { throw "WADDLE_CERT=FAIL dependency_state_root actual=$($dependencyState.root)" }
  if ([string]$dependencyState.fingerprint -ne [string]$Dependencies.fingerprint) { throw "WADDLE_CERT=FAIL dependency_fingerprint state=$($dependencyState.fingerprint) runtime=$($Dependencies.fingerprint)" }
  foreach ($required in @('electron\package.json','express\package.json','electron-log\package.json','tsx\package.json','.bin\copyfiles.cmd','.bin\electron.cmd')) {
    $path = Join-Path $repoModules $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "WADDLE_CERT=FAIL dependency_missing=$path" }
  }
  Write-Host "WADDLE_CERT_DEPENDENCIES=PASS mode=$($Dependencies.mode) root=$repoModules fingerprint=$($Dependencies.fingerprint) live_mutation=false"
}

function Get-WaddleDependencySentinelHashes {
  param([Parameter(Mandatory)][string]$ModulesRoot)
  $sentinels = @('electron\package.json','express\package.json','electron-log\package.json','typescript\package.json')
  $result = [ordered]@{}
  foreach ($relative in $sentinels) {
    $path = Join-Path $ModulesRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "WADDLE_CERT=FAIL dependency_sentinel_missing=$path" }
    $result[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  }
  return $result
}

function Assert-WaddleDependencySentinelsUnchanged {
  param([Parameter(Mandatory)][string]$ModulesRoot,[Parameter(Mandatory)]$Before)
  foreach ($relative in @($Before.Keys)) {
    $path = Join-Path $ModulesRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "WADDLE_CERT=FAIL dependency_sentinel_disappeared=$path" }
    $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($after -ne [string]$Before[$relative]) { throw "WADDLE_CERT=FAIL dependency_mutated_while_running file=$relative before=$($Before[$relative]) after=$after" }
  }
}

try {
  Invoke-WaddleCommandWithTimeout -Command 'Waddle-Setup.cmd' -Phase 'setup' -TimeoutSeconds 180
  $packageInfo = Join-Path $repo 'src\server\game-data\package-info.ts'
  if (-not (Test-Path -LiteralPath $packageInfo -PathType Leaf)) { throw "WADDLE_CERT=FAIL package_info_missing=$packageInfo" }
  if ((Get-Item -LiteralPath $packageInfo).Length -le 20) { throw "WADDLE_CERT=FAIL package_info_empty=$packageInfo" }
  Write-Host "WADDLE_CERT_SETUP=PASS package_info=$packageInfo"

  $dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
  Assert-WaddleDependencyTreeReadOnly -Dependencies $dependencies

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
  if ([string]$buildSummary.status -ne 'PASS' -or [string]$buildSummary.source_sha -ne $ExpectedSha) { throw "WADDLE_CERT=FAIL build_summary status=$($buildSummary.status) sha=$($buildSummary.source_sha)" }
  if ([IO.Path]::GetFullPath([string]$buildSummary.node_modules) -ne $repoModules) { throw "WADDLE_CERT=FAIL build_node_modules actual=$($buildSummary.node_modules) expected=$repoModules" }
  Write-Host "WADDLE_CERT_BUILD=PASS sha=$ExpectedSha duration_ms=$($build.provenance.duration_ms)"

  $dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
  Assert-WaddleDependencyTreeReadOnly -Dependencies $dependencies
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

  $runtimeRoot = Assert-WaddleRepoRuntimePath -Path ([string]$runtime.root) -Label 'runtime_root'
  $runtimeElectron = Assert-WaddleRepoRuntimePath -Path ([string]$runtime.electron_executable) -Label 'electron'
  $runtimeFlash = Assert-WaddleRepoRuntimePath -Path ([string]$runtime.ppapi_flash_path) -Label 'flash'
  $runtimeEntry = Assert-WaddleRepoRuntimePath -Path ([string]$runtime.app_entry) -Label 'app_entry'
  $runtimeModules = Assert-WaddleRepoRuntimePath -Path ([string]$runtime.runtime_node_modules) -Label 'runtime_node_modules'
  if ($runtimeRoot.TrimEnd('\') -ine $repoRuntimeRoot) { throw "WADDLE_CERT=FAIL runtime_not_repo actual=$runtimeRoot expected=$repoRuntimeRoot" }
  if ([IO.Path]::GetFullPath($runtimeElectron) -ne $repoElectron) { throw "WADDLE_CERT=FAIL electron_not_repo actual=$runtimeElectron expected=$repoElectron" }
  if ([IO.Path]::GetFullPath($runtimeFlash) -ne $repoFlash) { throw "WADDLE_CERT=FAIL flash_not_repo actual=$runtimeFlash expected=$repoFlash" }
  if ([IO.Path]::GetFullPath($runtimeEntry) -ne $repoEntry) { throw "WADDLE_CERT=FAIL app_entry_not_repo actual=$runtimeEntry expected=$repoEntry" }
  if ([IO.Path]::GetFullPath($runtimeModules) -ne $repoModules) { throw "WADDLE_CERT=FAIL runtime_modules_not_canonical actual=$runtimeModules expected=$repoModules" }
  if ([string]$runtime.mode -ne 'repo_local_direct') { throw "WADDLE_CERT=FAIL runtime_mode actual=$($runtime.mode) expected=repo_local_direct" }
  Write-Host "WADDLE_CERT_RUNTIME_LAYOUT=PASS mode=repo_local_direct root=$runtimeRoot electron=$runtimeElectron flash=$runtimeFlash app_entry=$runtimeEntry node_modules=$runtimeModules copies=0"

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
    try { & taskkill.exe /PID $probeProcess.Id /T /F | Out-Null } catch {}
    throw "WADDLE_CERT=FAIL flash_probe_timeout stdout=$probeOut stderr=$probeErr"
  }
  $probeProcess.WaitForExit()
  $probeProcess.Refresh()
  if (-not (Test-Path -LiteralPath $probeState -PathType Leaf)) { throw "WADDLE_CERT=FAIL flash_probe_state_missing=$probeState" }
  $probeResult = Get-Content -LiteralPath $probeState -Raw | ConvertFrom-Json
  if ([int]$probeProcess.ExitCode -ne 0 -or [string]$probeResult.status -ne 'PASS') { throw "WADDLE_CERT=FAIL flash_probe exit=$($probeProcess.ExitCode) status=$($probeResult.status) reason=$($probeResult.reason)" }
  if ([string]$probeResult.schema -ne 'waddle-flash-runtime-probe/v4') { throw "WADDLE_CERT=FAIL flash_schema=$($probeResult.schema)" }
  if ([int]$probeResult.root_status -ne 200 -or [int]$probeResult.boots_status -ne 200) { throw "WADDLE_CERT=FAIL flash_http root=$($probeResult.root_status) boots=$($probeResult.boots_status)" }
  if ([string]$probeResult.boots_content_type -notmatch 'application/x-shockwave-flash') { throw "WADDLE_CERT=FAIL flash_mime=$($probeResult.boots_content_type)" }
  if (-not [bool]$probeResult.renderer.mimePresent -or -not [bool]$probeResult.renderer.mimeEnabledPlugin -or -not [bool]$probeResult.renderer.objectPresent) { throw 'WADDLE_CERT=FAIL flash_renderer_contract' }
  if ([bool]$probeResult.fallback_visible -or -not [bool]$probeResult.scriptable_flash_object -or -not [bool]$probeResult.production_instantiated) { throw 'WADDLE_CERT=FAIL flash_not_instantiated' }
  if ([IO.Path]::GetFullPath([string]$probeResult.runtime_node_modules) -ne $repoModules) { throw "WADDLE_CERT=FAIL flash_modules actual=$($probeResult.runtime_node_modules) expected=$repoModules" }
  if ([IO.Path]::GetFullPath([string]$probeResult.plugin_path) -ne $runtimeFlash) { throw "WADDLE_CERT=FAIL flash_plugin actual=$($probeResult.plugin_path) expected=$runtimeFlash" }
  Write-Host "WADDLE_CERT_FLASH=PASS runtime=$runtimeRoot plugin=$runtimeFlash boots=200 instantiated=true"

  $dependencySentinelsBeforeStart = Get-WaddleDependencySentinelHashes -ModulesRoot $runtimeModules

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
  if ([string]$clientState.schema -ne 'waddle-client-state/v11') { throw "WADDLE_CERT=FAIL client_schema=$($clientState.schema)" }
  if ([string]$clientState.status -ne 'RUNNING' -or [string]$clientState.source_sha -ne $ExpectedSha) { throw "WADDLE_CERT=FAIL client_state status=$($clientState.status) sha=$($clientState.source_sha)" }
  if ([string]$clientState.runtime_mode -ne 'repo_local_direct' -or [string]$clientState.electron_launch_mode -ne 'repo_direct_start_process') { throw "WADDLE_CERT=FAIL client_runtime mode=$($clientState.runtime_mode) launch=$($clientState.electron_launch_mode)" }
  if ($null -eq $clientState.PSObject.Properties['dependency_mutation_while_running'] -or [bool]$clientState.dependency_mutation_while_running) { throw "WADDLE_CERT=FAIL client_dependency_mutation_contract value=$($clientState.dependency_mutation_while_running)" }
  if ([string]$clientState.dependency_mode -notin @('reused','adopted_repo_existing')) { throw "WADDLE_CERT=FAIL start_reinstalled_dependencies mode=$($clientState.dependency_mode)" }
  if ([IO.Path]::GetFullPath([string]$clientState.runtime_node_modules) -ne $repoModules) { throw "WADDLE_CERT=FAIL client_modules_not_canonical actual=$($clientState.runtime_node_modules) expected=$repoModules" }
  if ([IO.Path]::GetFullPath([string]$clientState.runtime_root).TrimEnd('\') -ine $repoRuntimeRoot) { throw "WADDLE_CERT=FAIL client_runtime_not_repo actual=$($clientState.runtime_root) expected=$repoRuntimeRoot" }
  if ([IO.Path]::GetFullPath([string]$clientState.electron_executable) -ne $repoElectron) { throw "WADDLE_CERT=FAIL client_electron_not_repo actual=$($clientState.electron_executable) expected=$repoElectron" }
  if ([IO.Path]::GetFullPath([string]$clientState.runtime_app_entry) -ne $repoEntry) { throw "WADDLE_CERT=FAIL client_entry_not_repo actual=$($clientState.runtime_app_entry) expected=$repoEntry" }
  if ([IO.Path]::GetFullPath([string]$clientState.ppapi_flash_path) -ne $repoFlash) { throw "WADDLE_CERT=FAIL client_flash_not_repo actual=$($clientState.ppapi_flash_path) expected=$repoFlash" }
  foreach ($pair in @(
    @{name='runtime_root'; value=[string]$clientState.runtime_root},
    @{name='app_entry'; value=[string]$clientState.runtime_app_entry},
    @{name='node_modules'; value=[string]$clientState.runtime_node_modules},
    @{name='electron'; value=[string]$clientState.electron_executable},
    @{name='flash'; value=[string]$clientState.ppapi_flash_path}
  )) { Assert-WaddleRepoRuntimePath -Path $pair.value -Label $pair.name | Out-Null }

  $startedClientId = [int]$clientState.pid
  $clientProcess = Get-Process -Id $startedClientId -ErrorAction Stop
  $clientProcess.Refresh()
  if ($clientProcess.HasExited) { throw "WADDLE_CERT=FAIL client_exited process_id=$startedClientId" }
  $clientCim = Get-CimInstance Win32_Process -Filter "ProcessId=$startedClientId" -ErrorAction Stop
  if ([IO.Path]::GetFullPath([string]$clientCim.ExecutablePath) -ne $repoElectron) { throw "WADDLE_CERT=FAIL client_executable actual=$($clientCim.ExecutablePath) expected=$repoElectron" }
  Write-Host "WADDLE_CERT_START=PASS process_id=$startedClientId launcher_return_ms=$($startWatch.ElapsedMilliseconds) runtime_mode=repo_local_direct runtime=$($clientState.runtime_root) dependency_mode=$($clientState.dependency_mode)"

  Start-Sleep -Seconds 2
  $clientProcess.Refresh()
  if ($clientProcess.HasExited) { throw "WADDLE_CERT=FAIL client_died_after_start process_id=$startedClientId" }
  Assert-WaddleDependencySentinelsUnchanged -ModulesRoot $runtimeModules -Before $dependencySentinelsBeforeStart
  Write-Host "WADDLE_CERT_RUNTIME_DIRECT=PASS process_id=$startedClientId dependency_tree=repo_physical live_mutation=false sentinels_unchanged=true external_runtime=false"

  Invoke-WaddleCommandWithTimeout -Command 'Waddle-Stop.cmd' -Phase 'stop' -TimeoutSeconds 30
  Start-Sleep -Seconds 1
  if (Get-Process -Id $startedClientId -ErrorAction SilentlyContinue) { throw "WADDLE_CERT=FAIL stop_left_client process_id=$startedClientId" }
  $postState = Get-Content -LiteralPath $clientStatePath -Raw | ConvertFrom-Json
  if ([string]$postState.status -ne 'STOPPED') { throw "WADDLE_CERT=FAIL stop_state=$($postState.status)" }

  $legacy = @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $exe = [string]$_.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try { return ([IO.Path]::GetFullPath($exe)).StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase) } catch { return $false }
  })
  if ($legacy.Count -gt 0) { throw "WADDLE_CERT=FAIL legacy_electron_inside_work count=$($legacy.Count) ids=$((@($legacy.ProcessId) -join ','))" }

  Test-AndroidBuildExactHead -RepoRoot $repo -ExpectedSha $ExpectedSha -AndroidBuildRoot $root | Out-Null
  $certWatch.Stop()
  $final = [ordered]@{
    schema='waddle-certification/v4'
    status='PASS'
    source_sha=$ExpectedSha
    repository=$Repository
    core_version=[string](Get-AndroidBuildCoreVersion)
    node='20.19.0'
    yarn='1.22.22'
    electron=[string]$dependencies.electron
    flash=[string]$sourceFlash.version
    package_index='PASS'
    dependency_setup='PASS'
    dependency_reuse_after_setup='PASS'
    live_dependency_mutation='DISABLED'
    build='PASS'
    flash_runtime='PASS'
    actual_start='PASS'
    runtime_mode='repo_local_direct'
    runtime_copies=0
    stop='PASS'
    legacy_work_runtime_count=0
    runtime_home=$runtimeHome
    node_modules=$repoModules
    launcher_return_ms=[int64]$startWatch.ElapsedMilliseconds
    duration_ms=[int64]$certWatch.ElapsedMilliseconds
    completed_utc=[DateTime]::UtcNow.ToString('o')
  }
  $final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $certStatePath -Encoding UTF8
  Write-Host "WADDLE_CERTIFICATION=PASS sha=$ExpectedSha duration_ms=$($certWatch.ElapsedMilliseconds) state=$certStatePath runtime_mode=repo_local_direct runtime_copies=0 live_dependency_mutation=false"
} catch {
  try { Stop-WaddleClientBestEffort } catch {}
  $certWatch.Stop()
  [ordered]@{
    schema='waddle-certification/v4'
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
