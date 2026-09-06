param(
  [Parameter(Mandatory=$false)][string]$ContextPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')

$ctx = Get-WaddleContext -ContextPath $ContextPath
$androidBuildRoot = Resolve-WaddleAndroidBuildRoot -Context $ctx
Import-WaddleCore -AndroidBuildRoot $androidBuildRoot
$managedNode = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $androidBuildRoot

Write-Host "WADDLE_BUILD_ENTRY=PASS managed_node=$($managedNode.node) managed_yarn=$($managedNode.yarn) host_node_isolated=true"

$buildScript = Join-Path $PSScriptRoot 'waddle-build.ps1'
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
  throw "WADDLE_BUILD_ENTRY=FAIL build_script_missing=$buildScript"
}

& $buildScript -ContextPath $ContextPath
