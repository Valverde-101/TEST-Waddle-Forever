[CmdletBinding()]
param(
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
$flash = Test-WaddlePepperFlash -RepoRoot $repo

# Never launch Electron through node_modules\.bin\electron.cmd. On mapped/network
# repositories cmd.exe /s /c can reinterpret the quoted V: command line and fail
# before Electron starts. The Electron package already ships the real Windows
# executable; validate that exact runtime during Setup and persist it for Start.
$electronExe = Join-Path $workspace.work_root 'dependencies\node_modules\electron\dist\electron.exe'
if (-not (Test-Path -LiteralPath $electronExe -PathType Leaf)) {
  throw "WADDLE_ELECTRON_RUNTIME=FAIL executable_missing=$electronExe run=yarn_install"
}

# electron.exe is a Windows GUI subsystem executable, so plain `--version` is not
# guaranteed to attach stdout to PowerShell. ELECTRON_RUN_AS_NODE makes the same
# binary execute as Node, giving us a deterministic direct-executable probe while
# still proving that the mapped-drive executable itself can start.
$previousRunAsNode = [Environment]::GetEnvironmentVariable('ELECTRON_RUN_AS_NODE','Process')
$previousErrorActionPreference = $ErrorActionPreference
$electronVersionOutput = @()
$electronExit = -1
try {
  [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE','1','Process')
  $ErrorActionPreference = 'Continue'
  $electronVersionOutput = @(& $electronExe -p "process.versions.electron" 2>&1)
  $electronExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
  if ($null -eq $previousRunAsNode) {
    Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
  } else {
    [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$previousRunAsNode,'Process')
  }
}
$electronVersion = (($electronVersionOutput | ForEach-Object { [string]$_ }) -join '').Trim().TrimStart('v')
if ($electronExit -ne 0) {
  throw "WADDLE_ELECTRON_RUNTIME=FAIL executable_exit=$electronExit path=$electronExe output=$($electronVersionOutput -join ' | ')"
}
if ([string]::IsNullOrWhiteSpace($electronVersion)) {
  throw "WADDLE_ELECTRON_RUNTIME=FAIL version_empty path=$electronExe mode=run_as_node"
}
if ($electronVersion -ne [string]$dependencies.electron) {
  throw "WADDLE_ELECTRON_RUNTIME=FAIL version_mismatch manifest=$($dependencies.electron) executable=$electronVersion path=$electronExe"
}
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_EXE' -Value ([IO.Path]::GetFullPath($electronExe))
[Environment]::SetEnvironmentVariable('WADDLE_ELECTRON_EXE',[IO.Path]::GetFullPath($electronExe),'Process')
Write-Host "WADDLE_ELECTRON_RUNTIME=PASS version=$electronVersion executable=$electronExe launch_mode=direct_exe probe_mode=run_as_node"

Write-Host "WADDLE_BOOTSTRAP=PASS repo=$repo work=$($workspace.work_root)"
Write-Host "WADDLE_NODE=$($toolchain.node)"
Write-Host "WADDLE_NODE_HOME=$($managedNode.home)"
Write-Host "WADDLE_YARN=$($toolchain.yarn)"
Write-Host "WADDLE_FFDEC=$($toolchain.ffdec)"
Write-Host "WADDLE_ELECTRON=$($dependencies.electron)"
Write-Host "WADDLE_ELECTRON_EXE=$electronExe"
Write-Host "WADDLE_DEPENDENCY_MODE=$($dependencies.mode)"
Write-Host "WADDLE_FLASH=$($flash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host 'NEXT=yarn start or Waddle-Start.cmd'
