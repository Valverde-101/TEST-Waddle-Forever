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

Write-Host "WADDLE_LAYOUT=PASS platform=windows-x64 launcher_root=$repo mutable_root=$($workspace.work_root) node_modules=.work\dependencies\current\node_modules runtime=.work\runtime\interactive swf_analysis=.work\swf-analysis"

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

$entry = Join-Path $repo 'compiled\client\main.js'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "WADDLE_START=FAIL compiled_entry_missing=$entry" }

$sourceElectron = Test-WaddleElectronRuntime -WorkRoot $workspace.work_root -ExpectedVersion $dependencies.electron
$snapshot = New-WaddleRuntimeSnapshot `
  -RepoRoot $repo `
  -WorkRoot $workspace.work_root `
  -ElectronExecutable $sourceElectron.executable `
  -ElectronVersion $sourceElectron.version `
  -PepperFlashPath $sourceFlash.path `
  -PepperFlashVersion $sourceFlash.version `
  -SourceSha $sha `
  -DependencyFingerprint $dependencies.fingerprint

$electron = $snapshot.electron_executable
$flashPath = $snapshot.ppapi_flash_path
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_EXE' -Value $electron
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_RUNTIME_ROOT' -Value $snapshot.root
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_PPAPI_FLASH_PATH' -Value $flashPath
[Environment]::SetEnvironmentVariable('WADDLE_ELECTRON_EXE',$electron,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_RUNTIME_ROOT',$snapshot.root,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_PPAPI_FLASH_PATH',$flashPath,'Process')
[Environment]::SetEnvironmentVariable('WADDLE_PPAPI_FLASH_VERSION',$snapshot.ppapi_flash_version,'Process')

$dependencyRoot = Get-WaddleNodeModulesPath -WorkRoot $workspace.work_root
if ($electron.StartsWith($dependencyRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "WADDLE_START=FAIL runtime_not_isolated electron=$electron dependencies=$dependencyRoot" }
if ($flashPath.StartsWith($dependencyRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "WADDLE_START=FAIL flash_not_isolated flash=$flashPath dependencies=$dependencyRoot" }
Write-Host "WADDLE_RUNTIME_ISOLATION=PASS snapshot=$($snapshot.root) electron=$electron flash=$flashPath mutable_dependencies=$dependencyRoot"

$runtimeLogs = Join-Path $workspace.work_root 'logs\runtime'
New-Item -ItemType Directory -Force -Path $runtimeLogs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$stamp.stderr.log"
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

$env:NODE_ENV = 'dev'
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
$entryArgument = '"' + $entry + '"'
try {
  $process = Start-Process -FilePath $electron -ArgumentList $entryArgument -WorkingDirectory $repo -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
} catch {
  throw "WADDLE_START=FAIL process_create executable=$electron entry=$entry error=$($_.Exception.Message)"
}
Start-Sleep -Seconds 3
$process.Refresh()
if ($process.HasExited) {
  $tail = if (Test-Path -LiteralPath $stderr) { (Get-Content -LiteralPath $stderr -Tail 30 -ErrorAction SilentlyContinue) -join ' | ' } else { '' }
  throw "WADDLE_START=FAIL process_exited code=$($process.ExitCode) stderr=$tail"
}

$state = [ordered]@{
  schema = 'waddle-client-state/v5'
  status = 'RUNNING'
  platform = 'windows-x64'
  pid = $process.Id
  source_sha = $sha
  repo_root = $repo
  work_root = $workspace.work_root
  dependency_root = $dependencyRoot
  dependency_fingerprint = $dependencies.fingerprint
  dependency_mode = $dependencies.mode
  managed_node_home = $managedNode.home
  managed_node_exe = $managedNode.node
  runtime_mode = 'immutable_snapshot'
  runtime_snapshot_root = $snapshot.root
  runtime_snapshot_manifest = $snapshot.manifest
  electron_source_executable = $sourceElectron.executable
  electron_executable = $electron
  electron_version = $sourceElectron.version
  electron_launch_mode = 'immutable_snapshot_direct_exe'
  electron_direct_process_probe = $sourceElectron.direct_process_probe
  ppapi_flash_source_path = $sourceFlash.path
  ppapi_flash_path = $flashPath
  ppapi_flash_version = $snapshot.ppapi_flash_version
  ffdec_path = $toolchain.ffdec
  stdout = $stdout
  stderr = $stderr
  started_utc = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "WADDLE_START=PASS pid=$($process.Id) sha=$sha platform=windows-x64 node=$($managedNode.node) electron=$($sourceElectron.version) launch_mode=immutable_snapshot dependencies=$($dependencies.mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$flashPath version=$($snapshot.ppapi_flash_version) source=$($sourceFlash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
