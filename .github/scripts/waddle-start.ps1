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

Write-Host "WADDLE_LAYOUT=PASS platform=windows-x64 launcher_root=$repo mutable_build_root=$($workspace.work_root) runtime_home=$runtimeHome runtime_execution_outside_work=true swf_analysis=.work\swf-analysis"

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
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

$env:NODE_ENV = 'dev'
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
$entryArgument = '"' + $entry + '"'
try {
  # Keep the historical user-data/media working directory at the repository root,
  # but execute all program binaries, compiled JS and runtime dependencies from
  # the external deployed runtime.
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
  schema = 'waddle-client-state/v6'
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
  electron_launch_mode = 'external_runtime_direct_exe'
  ppapi_flash_source_path = $sourceFlash.path
  ppapi_flash_path = $flashPath
  ppapi_flash_version = $runtime.ppapi_flash_version
  ffdec_path = $toolchain.ffdec
  stdout = $stdout
  stderr = $stderr
  started_utc = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "WADDLE_START=PASS pid=$($process.Id) sha=$sha platform=windows-x64 node=$($managedNode.node) electron=$($sourceElectron.version) launch_mode=external_runtime runtime=$runtimeRoot work_execution=false dependencies=$($dependencies.mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$flashPath version=$($runtime.ppapi_flash_version) source=$($sourceFlash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
