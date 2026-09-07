[CmdletBinding()]
param(
  [string]$AndroidBuildRoot,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')
. (Join-Path $PSScriptRoot 'waddle-local-runtime.ps1')
. (Join-Path $PSScriptRoot 'waddle-workspace-resilience.ps1')
. (Join-Path $PSScriptRoot 'waddle-git.ps1')

$ctx = @{}
if ($AndroidBuildRoot) { $ctx.androidbuild_root = $AndroidBuildRoot }
$repo = Resolve-WaddleRepoRoot -Context $ctx
$root = Resolve-WaddleAndroidBuildRoot -Context $ctx
Assert-WaddleWindowsOnly
Import-WaddleCore -AndroidBuildRoot $root
$managedNode = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $root
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $root
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $root
$envPath = Update-WaddleLocalEnv -RepoRoot $repo -AndroidBuildRoot $root -WorkRoot $workspace.work_root -FFDecPath $toolchain.ffdec
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_HOME' -Value $managedNode.home
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_EXE' -Value $managedNode.node
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NPM_CMD' -Value $managedNode.npm
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_YARN_CMD' -Value $managedNode.yarn
Import-WaddleLocalEnv -Path $envPath
$sourceFlash = Test-WaddlePepperFlash -RepoRoot $repo
$runtimeHome = Get-WaddleExternalRuntimeHome -AndroidBuildRoot $root
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

function Stop-WaddleProcessTree {
  param(
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$Reason
  )
  if ($ProcessId -le 0) { return $false }
  $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $proc) { return $false }
  & taskkill.exe /PID $ProcessId /T /F | Out-Null
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ne 0 -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    throw "WADDLE_PROCESS_CLEANUP=FAIL process_id=$ProcessId reason=$Reason taskkill_exit=$code"
  }
  Write-Host "WADDLE_PROCESS_CLEANUP=PASS process_id=$ProcessId reason=$Reason"
  return $true
}

function Stop-WaddleExistingClient {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
  try {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $priorProcessId = [int]$prior.pid
    if ($priorProcessId -gt 0) {
      Stop-WaddleProcessTree -ProcessId $priorProcessId -Reason 'replace_existing_client' | Out-Null
    }
    $prior.status = 'REPLACED'
    $prior | Add-Member -NotePropertyName replaced_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $prior | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
  } catch {
    $invalid = "$statePath.invalid-$(Get-Date -Format 'yyyyMMddHHmmss')"
    try { Move-Item -LiteralPath $statePath -Destination $invalid -Force } catch {}
    Write-Host "WADDLE_EXISTING_CLIENT_STATE=WARN action=quarantined path=$invalid error=$($_.Exception.Message)"
  }
}

function Stop-WaddleLegacyWorkRuntimes {
  $workPrefix = [IO.Path]::GetFullPath($workspace.work_root).TrimEnd('\') + '\'
  $killed = 0
  foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    $exe = [string]$candidate.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($exe)) { continue }
    try { $full = [IO.Path]::GetFullPath($exe) } catch { continue }
    if (-not $full.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)) { continue }
    if (Stop-WaddleProcessTree -ProcessId ([int]$candidate.ProcessId) -Reason 'legacy_runtime_inside_work') { $killed++ }
  }
  Write-Host "WADDLE_LEGACY_RUNTIME_CLEANUP=PASS killed=$killed work=$($workspace.work_root)"
}

function Stop-WaddleExternalManagedRuntimes {
  $runtimePrefix = [IO.Path]::GetFullPath((Join-Path $runtimeHome 'Versions')).TrimEnd('\') + '\'
  $killed = 0
  foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    $exe = [string]$candidate.ExecutablePath
    $cmd = [string]$candidate.CommandLine
    if ([string]::IsNullOrWhiteSpace($exe) -or [string]::IsNullOrWhiteSpace($cmd)) { continue }
    try { $full = [IO.Path]::GetFullPath($exe) } catch { continue }
    if (-not $full.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($cmd -notmatch '[\\/]app[\\/]compiled[\\/]client[\\/]main\.js') { continue }
    if (Stop-WaddleProcessTree -ProcessId ([int]$candidate.ProcessId) -Reason 'replace_external_managed_client') { $killed++ }
  }
  Write-Host "WADDLE_EXTERNAL_CLIENT_CLEANUP=PASS killed=$killed runtime_home=$runtimeHome"
}

function Start-WaddleDetachedElectron {
  param(
    [Parameter(Mandatory)][string]$Electron,
    [Parameter(Mandatory)][string]$Entry,
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][string]$Stdout,
    [Parameter(Mandatory)][string]$Stderr
  )

  # The Electron GUI process must be completely independent from the launcher.
  # Windows PowerShell 5.1 can keep redirected Start-Process pipes alive until the
  # child exits; a long-lived Electron client then prevents Waddle-Start.cmd and
  # the self-hosted Actions step from returning even after WADDLE_START=PASS.
  # Do not redirect OS stdio here. The child receives an exact diagnostics path
  # through its inherited environment and writes structured runtime events there.
  Set-Content -LiteralPath $Stdout -Encoding UTF8 -Value 'WADDLE_RUNTIME_STDIO=DETACHED stream=stdout source=electron_application_logging'
  Set-Content -LiteralPath $Stderr -Encoding UTF8 -Value 'WADDLE_RUNTIME_STDIO=DETACHED stream=stderr source=electron_structured_diagnostics'

  $launchWatch = [Diagnostics.Stopwatch]::StartNew()
  $started = $null
  $previousDiagnosticLog = [Environment]::GetEnvironmentVariable('WADDLE_RUNTIME_DIAGNOSTIC_LOG','Process')
  try {
    [Environment]::SetEnvironmentVariable('WADDLE_RUNTIME_DIAGNOSTIC_LOG',$Stderr,'Process')
    Write-Host "WADDLE_RUNTIME_DIAGNOSTIC_BINDING=PASS path=$Stderr mode=child_environment"
    try {
      $started = Start-Process `
        -FilePath $Electron `
        -ArgumentList @($Entry) `
        -WorkingDirectory $WorkingDirectory `
        -PassThru `
        -ErrorAction Stop
    } catch {
      throw "WADDLE_START=FAIL process_start executable=$Electron entry=$Entry error=$($_.Exception.Message)"
    }
  } finally {
    [Environment]::SetEnvironmentVariable('WADDLE_RUNTIME_DIAGNOSTIC_LOG',$previousDiagnosticLog,'Process')
  }

  if (-not $started -or $started.Id -le 0) {
    throw "WADDLE_START=FAIL process_id_missing executable=$Electron entry=$Entry"
  }

  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  $process = $null
  $cim = $null
  do {
    Start-Sleep -Milliseconds 250
    $process = Get-Process -Id $started.Id -ErrorAction SilentlyContinue
    if (-not $process) { break }
    try {
      $process.Refresh()
      if ($process.HasExited) { break }
      $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($started.Id)" -ErrorAction SilentlyContinue
      if ($cim) {
        $actualExe = [string]$cim.ExecutablePath
        $commandLine = [string]$cim.CommandLine
        if (-not [string]::IsNullOrWhiteSpace($actualExe) -and
            [IO.Path]::GetFullPath($actualExe) -ieq [IO.Path]::GetFullPath($Electron) -and
            $commandLine -like ('*' + $Entry + '*')) {
          break
        }
      }
    } catch {
      $cim = $null
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  if (-not $process -or $process.HasExited -or -not $cim) {
    throw "WADDLE_START=FAIL process_not_stable process_id=$($started.Id) executable=$Electron entry=$Entry"
  }

  $actualExe = [string]$cim.ExecutablePath
  $commandLine = [string]$cim.CommandLine
  if ([IO.Path]::GetFullPath($actualExe) -ine [IO.Path]::GetFullPath($Electron) -or $commandLine -notlike ('*' + $Entry + '*')) {
    try { Stop-WaddleProcessTree -ProcessId $started.Id -Reason 'unexpected_started_process' | Out-Null } catch {}
    throw "WADDLE_START=FAIL process_identity process_id=$($started.Id) executable=$actualExe expected=$Electron command_line=$commandLine entry=$Entry"
  }

  Start-Sleep -Seconds 3
  $process.Refresh()
  if ($process.HasExited) {
    throw "WADDLE_START=FAIL process_exited code=$($process.ExitCode)"
  }

  $launchWatch.Stop()
  return [pscustomobject]@{ process=$process; return_ms=$launchWatch.ElapsedMilliseconds; stdio_mode='detached_no_runner_pipes' }
}

Write-Host "WADDLE_LAYOUT=PASS platform=windows-x64 launcher_root=$repo mutable_build_root=$($workspace.work_root) runtime_home=$runtimeHome runtime_execution_outside_work=true swf_analysis=.work\swf-analysis"

# The canonical dependency tree may need to be installed when package inputs
# change. Always stop every managed Waddle client before dependency bootstrap so
# Yarn never mutates repo\node_modules while Electron is resolving modules from
# that same physical tree. This is the single-tree no-lock invariant.
Stop-WaddleExistingClient
Stop-WaddleLegacyWorkRuntimes
Stop-WaddleExternalManagedRuntimes
$dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
Write-Host "WADDLE_DEPENDENCY_MUTATION_GATE=PASS clients_stopped_before_bootstrap=true mode=$($dependencies.mode) node_modules=$($dependencies.node_modules)"

$gitState = $null
try {
  $gitState = Get-WaddleRepositoryHead -RepoRoot $repo -AndroidBuildRoot $root
  $sha = [string]$gitState.sha
  if ([string]::IsNullOrWhiteSpace($sha)) { throw 'WADDLE_START=FAIL head_unresolved' }

  if (-not $SkipBuild) {
    Invoke-AndroidBuildBuild `
      -RepoRoot $repo `
      -AndroidBuildRoot $root `
      -ExpectedSha $sha `
      -Repository 'Valverde-101/TEST-Waddle-Forever' `
      -RunId ("manual-" + (Get-Date -Format 'yyyyMMddHHmmss')) `
      -JobId 'interactive-start' `
      -RunnerName $env:COMPUTERNAME `
      -LeaseWaitSeconds 1200 | Out-Host
  }
} finally {
  Restore-WaddleGitSafeDirectoryScope -State $gitState
}

$sourceEntry = Join-Path $repo 'compiled\client\main.js'
if (-not (Test-Path -LiteralPath $sourceEntry -PathType Leaf)) { throw "WADDLE_START=FAIL compiled_entry_missing=$sourceEntry" }

$sourceElectron = Test-WaddleElectronRuntime -WorkRoot $workspace.work_root -ExpectedVersion $dependencies.electron
$runtime = New-WaddleRuntimeSnapshot `
  -RepoRoot $repo `
  -WorkRoot $workspace.work_root `
  -ElectronExecutable $sourceElectron.executable `
  -ElectronVersion $sourceElectron.version `
  -PepperFlashPath $sourceFlash.path `
  -PepperFlashVersion $sourceFlash.version `
  -SourceSha $sha `
  -DependencyFingerprint $dependencies.fingerprint

$electron = [IO.Path]::GetFullPath([string]$runtime.electron_executable)
$flashPath = [IO.Path]::GetFullPath([string]$runtime.ppapi_flash_path)
$entry = [IO.Path]::GetFullPath([string]$runtime.app_entry)
$runtimeModules = [IO.Path]::GetFullPath([string]$runtime.runtime_node_modules)
$runtimeRoot = [IO.Path]::GetFullPath([string]$runtime.root)
$workPrefix = [IO.Path]::GetFullPath($workspace.work_root).TrimEnd('\') + '\'
foreach ($runtimePath in @($electron,$flashPath,$entry,$runtimeModules,$runtimeRoot)) {
  if ($runtimePath.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw "WADDLE_START=FAIL runtime_inside_work path=$runtimePath work=$($workspace.work_root)"
  }
}
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "WADDLE_START=FAIL external_entry_missing=$entry" }
if (-not (Test-Path -LiteralPath $runtimeModules -PathType Container)) { throw "WADDLE_START=FAIL external_modules_missing=$runtimeModules" }
if ([IO.Path]::GetFullPath($runtimeModules) -ne [IO.Path]::GetFullPath((Join-Path $repo 'node_modules'))) {
  throw "WADDLE_START=FAIL runtime_modules_not_canonical actual=$runtimeModules expected=$(Join-Path $repo 'node_modules')"
}

Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_EXE' -Value $electron
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_RUNTIME_ROOT' -Value $runtimeRoot
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_RUNTIME_HOME' -Value $runtimeHome
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_PPAPI_FLASH_PATH' -Value $flashPath
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_RUNTIME_NODE_MODULES' -Value $runtimeModules
[Environment]::SetEnvironmentVariable('WADDLE_ELECTRON_EXE',$electron,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_RUNTIME_ROOT',$runtimeRoot,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_RUNTIME_HOME',$runtimeHome,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_PPAPI_FLASH_PATH',$flashPath,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_PPAPI_FLASH_VERSION',$runtime.ppapi_flash_version,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_RUNTIME_NODE_MODULES',$runtimeModules,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_NODE_MODULES',$runtimeModules,'Process')
[Environment]::SetEnvironmentVariable('NODE_PATH',$runtimeModules,'Process')

Write-Host "WADDLE_RUNTIME_ISOLATION=PASS runtime=$runtimeRoot current=$($runtime.current_root) electron=$electron app_entry=$entry runtime_node_modules=$runtimeModules mutable_build_root=$($workspace.work_root) work_execution=false dependency_mutation_while_running=false"

$runtimeLogs = Join-Path $workspace.work_root 'logs\runtime'
New-Item -ItemType Directory -Force -Path $runtimeLogs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$stamp.stderr.log"

$env:NODE_ENV = 'dev'
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
$launch = $null
try {
  $launch = Start-WaddleDetachedElectron -Electron $electron -Entry $entry -WorkingDirectory $repo -Stdout $stdout -Stderr $stderr
  $process = $launch.process
  $state = [ordered]@{
    schema = 'waddle-client-state/v10'
    status = 'RUNNING'
    platform = 'windows-x64'
    pid = $process.Id
    source_sha = $sha
    repo_root = $repo
    work_root = $workspace.work_root
    dependency_build_root = $dependencies.node_modules
    dependency_fingerprint = $dependencies.fingerprint
    dependency_mode = $dependencies.mode
    dependency_mutation_while_running = $false
    stdio_mode = [string]$launch.stdio_mode
    managed_node_home = $managedNode.home
    managed_node_exe = $managedNode.node
    runtime_mode = 'external_deployment'
    runtime_home = $runtimeHome
    runtime_root = $runtimeRoot
    runtime_current_root = $runtime.current_root
    runtime_manifest = $runtime.manifest
    runtime_app_entry = $entry
    runtime_node_modules = $runtimeModules
    electron_source_executable = $sourceElectron.executable
    electron_executable = $electron
    electron_version = $sourceElectron.version
    electron_launch_mode = 'external_runtime_start_process'
    launcher_return_ms = [int64]$launch.return_ms
    ppapi_flash_source_path = $sourceFlash.path
    ppapi_flash_path = $flashPath
    ppapi_flash_version = $runtime.ppapi_flash_version
    ffdec_path = $toolchain.ffdec
    stdout = $stdout
    stderr = $stderr
    started_utc = [DateTime]::UtcNow.ToString('o')
  }
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
} catch {
  if ($launch -and $launch.process) {
    try { Stop-WaddleProcessTree -ProcessId ([int]$launch.process.Id) -Reason 'start_state_failure' | Out-Null } catch {}
  }
  throw
}

Write-Host "WADDLE_START=PASS process_id=$($process.Id) sha=$sha platform=windows-x64 node=$($managedNode.node) electron=$($sourceElectron.version) launch_mode=external_runtime_start_process launcher_return_ms=$($launch.return_ms) runtime=$runtimeRoot work_execution=false dependencies=$($dependencies.mode) live_dependency_mutation=false stdio=$($launch.stdio_mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$flashPath version=$($runtime.ppapi_flash_version) source=$($sourceFlash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout mode=marker_only"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr mode=structured_runtime_events"