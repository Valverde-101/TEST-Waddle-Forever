param(
  [Parameter(Mandatory=$false)][string]$ContextPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')
. (Join-Path $PSScriptRoot 'waddle-managed-node.ps1')

$ctx = Get-WaddleContext -ContextPath $ContextPath
$repo = Resolve-WaddleRepoRoot -Context $ctx
$androidBuildRoot = Resolve-WaddleAndroidBuildRoot -Context $ctx
$env:ANDROIDBUILD_ROOT = $androidBuildRoot
Import-WaddleCore -AndroidBuildRoot $androidBuildRoot
$managedNode = Enable-WaddleManagedNodeToolchain -AndroidBuildRoot $androidBuildRoot

# Build replaces compiled output and may update generated package metadata. On a
# shared SMB repository it must never run underneath an Electron client on this
# or another machine. The lease layer cleans dead/stale owners automatically.
. (Join-Path $PSScriptRoot 'waddle-workspace-resilience.ps1')
Assert-WaddleRuntimeMutationAllowed -RepoRoot $repo -Reason 'build_compiled_and_generated_content'

Write-Host "WADDLE_BUILD_ENTRY=PASS managed_node=$($managedNode.node) managed_yarn=$($managedNode.yarn) host_node_isolated=true runtime_mutation_guard=cross_machine"

$buildScript = Join-Path $PSScriptRoot 'waddle-build.ps1'
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
  throw "WADDLE_BUILD_ENTRY=FAIL build_script_missing=$buildScript"
}

& $buildScript -ContextPath $ContextPath
