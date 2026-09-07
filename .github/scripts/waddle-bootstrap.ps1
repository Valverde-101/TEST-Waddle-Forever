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
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_EXE' -Value ''
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_RUNTIME_ROOT' -Value ''
Import-WaddleLocalEnv -Path $envPath
$dependencies = Invoke-WaddleDependencyBootstrap -RepoRoot $repo -WorkRoot $workspace.work_root
$flash = Test-WaddlePepperFlash -RepoRoot $repo
$electronSource = Test-WaddleElectronRuntime -WorkRoot $workspace.work_root -ExpectedVersion $dependencies.electron
Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_ELECTRON_SOURCE_EXE' -Value $electronSource.executable
[Environment]::SetEnvironmentVariable('WADDLE_ELECTRON_SOURCE_EXE',$electronSource.executable,'Process')

Write-Host "WADDLE_BOOTSTRAP=PASS platform=windows-x64 repo=$repo work=$($workspace.work_root)"
Write-Host "WADDLE_NODE=$($toolchain.node)"
Write-Host "WADDLE_NODE_HOME=$($managedNode.home)"
Write-Host "WADDLE_YARN=$($toolchain.yarn)"
Write-Host "WADDLE_FFDEC=$($toolchain.ffdec)"
Write-Host "WADDLE_ELECTRON=$($electronSource.version)"
Write-Host "WADDLE_ELECTRON_SOURCE_EXE=$($electronSource.executable)"
Write-Host "WADDLE_DEPENDENCY_ROOT=$($dependencies.node_modules)"
Write-Host "WADDLE_DEPENDENCY_MODE=$($dependencies.mode)"
Write-Host "WADDLE_RUNTIME_MODE=immutable_snapshot"
Write-Host "WADDLE_FLASH_SOURCE=$($flash.path)"
Write-Host 'WADDLE_VISUAL_STUDIO=NOT_REQUIRED'
Write-Host 'NEXT=yarn start or Waddle-Start.cmd'
