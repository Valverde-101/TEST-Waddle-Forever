Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$core = Join-Path $PSScriptRoot 'waddle-workspace-resilience-core.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
  throw "WADDLE_WORKSPACE_CORE=FAIL missing=$core"
}
. $core

$externalRuntime = Join-Path $PSScriptRoot 'waddle-external-runtime.ps1'
if (-not (Test-Path -LiteralPath $externalRuntime -PathType Leaf)) {
  throw "WADDLE_RUNTIME_OVERRIDE=FAIL missing=$externalRuntime"
}
. $externalRuntime
Write-Host "WADDLE_RUNTIME_OVERRIDE=PASS mode=external_deployment script=$externalRuntime"
