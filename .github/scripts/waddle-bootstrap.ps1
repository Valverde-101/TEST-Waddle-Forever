[CmdletBinding()]
param(
  [string]$AndroidBuildRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')

$ctx = @{}
if ($AndroidBuildRoot) { $ctx.androidbuild_root = $AndroidBuildRoot }
$repo = Resolve-WaddleRepoRoot -Context $ctx
$root = Resolve-WaddleAndroidBuildRoot -Context $ctx
Import-WaddleCore -AndroidBuildRoot $root
$workspace = Initialize-WaddleWorkspace -RepoRoot $repo -AndroidBuildRoot $root
$toolchain = Test-WaddleToolchain -AndroidBuildRoot $root

Write-Host "WADDLE_BOOTSTRAP=PASS repo=$repo work=$($workspace.work_root)"
Write-Host "WADDLE_NODE=$($toolchain.node)"
Write-Host "WADDLE_YARN=$($toolchain.yarn)"
Write-Host "WADDLE_FFDEC=$($toolchain.ffdec)"
Write-Host 'NEXT=Invoke-AndroidBuildBuild or .github/scripts/waddle-build.ps1 through Core'
