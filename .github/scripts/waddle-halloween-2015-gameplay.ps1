[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$scripts = Join-Path $repo '.github\scripts'

# Compatibility wrapper: all mechanics live in reusable party scripts; this
# party contributes only its own timeline/data configuration.
& (Join-Path $scripts 'waddle-party-runtime.ps1') -RepoRoot $repo
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY2015_GAMEPLAY=FAIL runtime_exit=$LASTEXITCODE" }

& (Join-Path $scripts 'waddle-party-hardening.ps1') -RepoRoot $repo
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY2015_GAMEPLAY=FAIL hardening_exit=$LASTEXITCODE" }

& (Join-Path $scripts 'waddle-halloween-2015-data.ps1') -RepoRoot $repo
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY2015_GAMEPLAY=FAIL data_exit=$LASTEXITCODE" }

Write-Host 'WADDLE_PARTY2015_GAMEPLAY=PASS runtime=generic hardening=generic party_data=halloween-2015'
