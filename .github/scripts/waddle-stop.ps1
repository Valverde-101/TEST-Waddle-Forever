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
$statePath = Join-Path $workspace.work_root 'state\waddle-client.json'

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
  Write-Host 'WADDLE_STOP=PASS state=not-running'
  exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$pidToStop = [int]$state.pid
if ($pidToStop -gt 0) {
  $proc = Get-Process -Id $pidToStop -ErrorAction SilentlyContinue
  if ($proc) {
    & taskkill.exe /PID $pidToStop /T /F | Out-Host
    if ($LASTEXITCODE -ne 0 -and (Get-Process -Id $pidToStop -ErrorAction SilentlyContinue)) {
      throw "WADDLE_STOP=FAIL pid=$pidToStop taskkill_exit=$LASTEXITCODE"
    }
  }
}

$state.status = 'STOPPED'
$state | Add-Member -NotePropertyName stopped_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
$state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Host "WADDLE_STOP=PASS pid=$pidToStop"
