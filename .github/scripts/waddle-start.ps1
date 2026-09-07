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
    [Parameter(Mandatory)][int]$Pid,
    [Parameter(Mandatory)][string]$Reason
  )
  if ($Pid -le 0) { return $false }
  $proc = Get-Process -Id $Pid -ErrorAction SilentlyContinue
  if (-not $proc) { return $false }
  & taskkill.exe /PID $Pid /T /F | Out-Null
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ne 0 -and (Get-Process -Id $Pid -ErrorAction SilentlyContinue)) {
    throw "WADDLE_PROCESS_CLEANUP=FAIL pid=$Pid reason=$Reason taskkill_exit=$code"
  }
  Write-Host "WADDLE_PROCESS_CLEANUP=PASS pid=$Pid reason=$Reason"
  return $true
}

function Stop-WaddleExistingClient {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
  try {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $priorPid = [int]$prior.pid
    if ($priorPid -gt 0 -and (Get-Process -Id $priorPid -ErrorAction SilentlyContinue)) {
      Stop-WaddleProcessTree -Pid $priorPid -Reason 'replace_existing_client' | Out-Null
    }
    $prior.status = 'REPLACED'
    $prior | Add-Member -NotePropertyName replaced_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $prior | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
  } catch {
    Write-Host "WADDLE_EXISTING_CLIENT_CLEANUP=WARN error=$($_.Exception.Message)"
  }
}

function Stop-WaddleLegacyWorkRuntimes {
  $workPrefix = [IO.Path]::GetFullPath($workspace.work_root).TrimEnd('\') + '\'
  $killed = 0
  $candidates = @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)
  foreach ($candidate in $candidates) {
    $exe = [string]$candidate.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($exe)) { continue }
    try { $full = [IO.Path]::GetFullPath($exe) } catch { continue }
    if (-not $full.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)) { continue }
    if (Stop-WaddleProcessTree -Pid ([int]$candidate.ProcessId) -Reason 'legacy_runtime_inside_work') { $killed++ }
  }
  Write-Host "WADDLE_LEGACY_RUNTIME_CLEANUP=PASS killed=$killed work=$($workspace.work_root)"
}

function Start-WaddleDetachedElectron {
  param(
    [Parameter(Mandatory)][string]$Electron,
    [Parameter(Mandatory)][string]$Entry,
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [Parameter(Mandatory)][string]$Stdout,
    [Parameter(Mandatory)][string]$Stderr
  )

  # A direct Start-Process with redirected streams can keep the parent PowerShell
  # alive for the lifetime of Electron on Windows. Launch through cmd.exe START
  # instead: START returns immediately, Electron keeps the desired environment,
  # and its stdout/stderr are redirected at the shell boundary rather than by
  # System.Diagnostics.Process stream readers.
  $existing = @{}
  foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    $exe = [string]$p.ExecutablePath
    $cmd = [string]$p.CommandLine
    if (-not [string]::IsNullOrWhiteSpace($exe)) {
      try {
        if ([IO.Path]::GetFullPath($exe) -ieq [IO.Path]::GetFullPath($Electron) -and $cmd -like ('*' + $Entry + '*')) {
          $existing[[int]$p.ProcessId] = $true
        }
      } catch {}
    }
  }

  $launch = 'start "" /b "' + $Electron.Replace('"','""') + '" "' + $Entry.Replace('"','""') + '" 1>>"' + $Stdout.Replace('"','""') + '" 2>>"' + $Stderr.Replace('"','""') + '"'
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
      $pid = [int]$_.ProcessId
      if ($existing.ContainsKey($pid)) { return $false }
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
  return $process
}

Write-Host "WADDLE_LAYOUT=PASS platform=windows-x64 launcher_root=$repo mutable_build_root=$($workspace.work_root) runtime_home=$runtimeHome runtime_execution_outside_work=true swf_analysis=.work\swf-analysis"

# Stop one prior managed client and all pre-migration Electron trees whose
# executable still lives under .work. This is intentionally project-scoped.
Stop-WaddleExistingClient
Stop-WaddleLegacyWorkRuntimes

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

foreach ($runtimePath in @($electron,$flashPath,$entry,$runtimeModules,$runtimeRoot)) {
  if ($runtimePath.StartsWith(([IO.Path]::GetFullPath($workspace.work_root).TrimEnd('\') + '\'),[StringComparison]::OrdinalIgnoreCase)) {
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
try {
  $process = Start-WaddleDetachedElectron -Electron $electron -Entry $entry -WorkingDirectory $repo -Stdout $stdout -Stderr $stderr
} catch {
  throw "WADDLE_START=FAIL process_create executable=$electron entry=$entry error=$($_.Exception.Message)"
}

$state = [ordered]@{
  schema = 'waddle-client-state/v7'
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
  ppapi_flash_source_path = $sourceFlash.path
  ppapi_flash_path = $flashPath
  ppapi_flash_version = $runtime.ppapi_flash_version
  ffdec_path = $toolchain.ffdec
  stdout = $stdout
  stderr = $stderr
  started_utc = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "WADDLE_START=PASS pid=$($process.Id) sha=$sha platform=windows-x64 node=$($managedNode.node) electron=$($sourceElectron.version) launch_mode=external_runtime_detached_cmd_start runtime=$runtimeRoot work_execution=false dependencies=$($dependencies.mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$flashPath version=$($runtime.ppapi_flash_version) source=$($sourceFlash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
