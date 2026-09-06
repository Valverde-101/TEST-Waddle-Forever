[CmdletBinding()]
param(
  [string]$AndroidBuildRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')
. (Join-Path $PSScriptRoot 'waddle-local-runtime.ps1')

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
$dependencies = Install-WaddleDependencies -RepoRoot $repo -WorkRoot $workspace.work_root
$flash = Test-WaddlePepperFlash -RepoRoot $repo

Write-Host "WADDLE_BOOTSTRAP=PASS repo=$repo work=$($workspace.work_root)"
Write-Host "WADDLE_NODE=$($toolchain.node)"
Write-Host "WADDLE_NODE_HOME=$($managedNode.home)"
Write-Host "WADDLE_YARN=$($toolchain.yarn)"
Write-Host "WADDLE_FFDEC=$($toolchain.ffdec)"
Write-Host "WADDLE_ELECTRON=$($dependencies.electron)"
Write-Host "WADDLE_FLASH=$($flash.path)"
Write-Host 'NEXT=yarn start or Waddle-Start.cmd'
