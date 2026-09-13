Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Compatibility shim retained for older scripts/branches that still dot-source
# this filename. The external AndroidBuild runtime was retired: all runtime
# functions now come from the repository-local direct policy.
$repoRuntime = Join-Path $PSScriptRoot 'waddle-repo-runtime.ps1'
if (-not (Test-Path -LiteralPath $repoRuntime -PathType Leaf)) {
  throw "WADDLE_RUNTIME_SHIM=FAIL repo_runtime_missing=$repoRuntime"
}
. $repoRuntime
Write-Host "WADDLE_RUNTIME_SHIM=PASS legacy_name=waddle-external-runtime.ps1 actual_mode=repo_local_direct external_runtime=false"
