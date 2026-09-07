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
Test-WaddlePepperFlash -RepoRoot $repo | Out-Null

# The launcher lives in the repository root. Heavy/generated state remains under
# .work by design and is surfaced back at the root through junctions.
Write-Host "WADDLE_LAYOUT=PASS launcher_root=$repo mutable_root=$($workspace.work_root) node_modules=repo_junction swf_analysis=.work\swf-analysis"

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

# Validate the packaged runtime itself and its direct Windows process-creation
# path. This deliberately avoids `.bin\electron.cmd`, `cmd.exe /s /c`, and their
# mapped-drive quoting/canonicalization behavior.
$electronRuntime = Test-WaddleElectronRuntime -WorkRoot $workspace.work_root -ExpectedVersion $dependencies.electron
$electron = $electronRuntime.executable
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_EXE' -Value $electron
[Environment]::SetEnvironmentVariable('WADDLE_ELECTRON_EXE',$electron,'Process')

$flash = Test-WaddlePepperFlash -RepoRoot $repo
$runtimeLogs = Join-Path $workspace.work_root 'logs\runtime'
New-Item -ItemType Directory -Force -Path $runtimeLogs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$stamp.stderr.log"
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

$env:NODE_ENV = 'dev'
# A stale host variable would turn the desktop app back into Node mode. Never
# inherit it into the real Waddle client process.
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
  schema = 'waddle-client-state/v4'
  status = 'RUNNING'
  pid = $process.Id
  source_sha = $sha
  repo_root = $repo
  work_root = $workspace.work_root
  managed_node_home = $managedNode.home
  managed_node_exe = $managedNode.node
  electron_executable = $electron
  electron_version = $electronRuntime.version
  electron_launch_mode = 'direct_exe'
  electron_direct_process_probe = $electronRuntime.direct_process_probe
  dependency_mode = $dependencies.mode
  ppapi_flash_path = $flash.path
  ppapi_flash_version = $flash.version
  ffdec_path = $toolchain.ffdec
  stdout = $stdout
  stderr = $stderr
  started_utc = [DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "WADDLE_START=PASS pid=$($process.Id) sha=$sha node=$($managedNode.node) electron=$($electronRuntime.version) launch_mode=direct_exe dependencies=$($dependencies.mode)"
Write-Host "WADDLE_PPAPI_FLASH=PASS path=$($flash.path) version=$($flash.version)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host "WADDLE_RUNTIME_STDOUT=$stdout"
Write-Host "WADDLE_RUNTIME_STDERR=$stderr"
