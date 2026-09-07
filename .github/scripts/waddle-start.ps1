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
$dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
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

  $existing = @{}
  foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    $exe = [string]$candidate.ExecutablePath
    $cmd = [string]$candidate.CommandLine
    if ([string]::IsNullOrWhiteSpace($exe)) { continue }
    try {
      if ([IO.Path]::GetFullPath($exe) -ieq [IO.Path]::GetFullPath($Electron) -and $cmd -like ('*' + $Entry + '*')) {
        $existing[[int]$candidate.ProcessId] = $true
      }
    } catch {}
  }

  $escapedElectron = $Electron.Replace('"','""')
  $escapedEntry = $Entry.Replace('"','""')
  $escapedStdout = $Stdout.Replace('"','""')
  $escapedStderr = $Stderr.Replace('"','""')
  $launch = 'start "" /b "' + $escapedElectron + '" "' + $escapedEntry + '" 1>>"' + $escapedStdout + '" 2>>"' + $escapedStderr + '"'
  $launchWatch = [Diagnostics.Stopwatch]::StartNew()
  Push-Location $WorkingDirectory
  try {
    & cmd.exe /d /s /c $launch
    $launchExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  $global:LASTEXITCODE = 0
  if ($launchExit -ne 0) {
    throw "WADDLE_START=FAIL detached_launcher_exit=$launchExit executable=$Electron entry=$Entry"
  }

  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  $found = $null
  do {
    Start-Sleep -Milliseconds 250
    $matches = @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue | Where-Object {
      $candidateProcessId = [int]$_.ProcessId
      if ($existing.ContainsKey($candidateProcessId)) { return $false }
      $exe = [string]$_.ExecutablePath
      $cmd = [string]$_.CommandLine
      if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
      try {
        return ([IO.Path]::GetFullPath($exe) -ieq [IO.Path]::GetFullPath($Electron)) -and $cmd -like ('*' + $Entry + '*')
      } catch { return $false }
    } | Sort-Object CreationDate -Descending)
    if ($matches.Count -gt 0) { $found = $matches[0]; break }
  } while ([DateTime]::UtcNow -lt $deadline)

  if (-not $found) {
    $tail = if (Test-Path -LiteralPath $Stderr) { (Get-Content -LiteralPath $Stderr -Tail 40 -ErrorAction SilentlyContinue) -join ' | ' } else { '' }
    throw "WADDLE_START=FAIL detached_process_not_found executable=$Electron entry=$Entry stderr=$tail"
  }

  $process = Get-Process -Id ([int]$found.ProcessId) -ErrorAction Stop
  Start-Sleep -Seconds 3
  $process.Refresh()
  if ($process.HasExited) {
    $tail = if (Test-Path -LiteralPath $Stderr) { (Get-Content -LiteralPath $Stderr -Tail 40 -ErrorAction SilentlyContinue) -join ' | ' } else { '' }
    throw "WADDLE_START=FAIL process_exited code=$($process.ExitCode) stderr=$tail"
  }
  $launchWatch.Stop()
  return [pscustomobject]@{ process=$process; return_ms=$launchWatch.ElapsedMilliseconds }
}

Write-Host "WADDLE_LAYOUT=PASS platform=windows-x64 launcher_root=$repo mutable_build_root=$($workspace.work_root) runtime_home=$runtimeHome runtime_execution_outside_work=true swf_analysis=.work\swf-analysis"

# Single-client invariant. State-based cleanup handles the normal path; the two
# process scans recover old/pre-migration or orphaned Waddle instances without
# touching unrelated Electron applications.
Stop-WaddleExistingClient
Stop-WaddleLegacyWorkRuntimes
Stop-WaddleExternalManagedRuntimes

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

Write-Host "WADDLE_RUNTIME_ISOLATION=PASS runtime=$runtimeRoot current=$($runtime.current_root) electron=$electron app_entry=$entry runtime_node_modules=$runtimeModules mutable_build_root=$($workspace.work_root) work_execution=false"

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
    schema = 'waddle-client-state/v8'
    status = 'RUNNING'
    platform = 'windows-x64'
    pid = $process.Id
    source_sha = $sha
    repo_root = $repo
    work_root = $workspace.work_root
    dependency_build_root = $dependencies.node_modules
    dependency_fingerprint = $dependencies.fingerprint
    dependency_mode = $dependencies.mode
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
    electron_launch_mode = 'external_runtime_detached_cmd_start'
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

Write-Host "WADDLE_START=PASS process_id=$($process.Id) sha=$sha platform=windows-x64 node=$($managedNode.node) electron=$($sourceElectron.version) launch_mode=external_runtime_detached_cmd_start launcher_return_ms=$($launch.return_ms) runtime=$runtimeRoot work_execution=false dependencies=$($dependencies.mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$flashPath version=$($runtime.ppapi_flash_version) source=$($sourceFlash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
