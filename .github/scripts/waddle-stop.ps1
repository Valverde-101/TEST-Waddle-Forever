[CmdletBinding()]
param(
  [string]$AndroidBuildRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')

$repo = Resolve-WaddleRepoRoot -Context @{}
$work = Join-Path $repo '.work'
$statePath = Join-Path $work 'state\waddle-client.json'
$runtimeHome = $null
if ($AndroidBuildRoot) {
  $runtimeHome = [IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Runtime\Waddle-Forever'))
} else {
  try {
    $repoInfo = [IO.DirectoryInfo]$repo
    if ($repoInfo.Parent -and $repoInfo.Parent.Name -ieq 'Repositories' -and $repoInfo.Parent.Parent) {
      $runtimeHome = [IO.Path]::GetFullPath((Join-Path $repoInfo.Parent.Parent.FullName 'Runtime\Waddle-Forever'))
    }
  } catch {}
}

function Stop-WaddleProcessTree {
  param(
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$Reason
  )
  if ($ProcessId -le 0) { return $false }
  $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $proc) { return $false }
  & taskkill.exe /PID $ProcessId /T /F | Out-Null
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ne 0 -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    throw "WADDLE_STOP=FAIL process_id=$ProcessId reason=$Reason taskkill_exit=$code"
  }
  Write-Host "WADDLE_STOP_PROCESS=PASS process_id=$ProcessId reason=$Reason"
  return $true
}

$state = $null
$stateProcessId = 0
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
  try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $stateProcessId = [int]$state.pid
    if ($stateProcessId -gt 0) {
      Stop-WaddleProcessTree -ProcessId $stateProcessId -Reason 'state_client' | Out-Null
    }
  } catch {
    Write-Host "WADDLE_STOP_STATE=WARN path=$statePath error=$($_.Exception.Message)"
  }
}

# Recovery scan: stop only Waddle Electron roots. This covers legacy .work
# runtimes and external deployments even when the state file is stale/missing.
$workPrefix = [IO.Path]::GetFullPath($work).TrimEnd('\') + '\'
$runtimePrefix = if ($runtimeHome) { $runtimeHome.TrimEnd('\') + '\' } else { $null }
$recovered = 0
foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
  $exe = [string]$candidate.ExecutablePath
  $cmd = [string]$candidate.CommandLine
  if ([string]::IsNullOrWhiteSpace($exe) -or [string]::IsNullOrWhiteSpace($cmd)) { continue }
  try { $full = [IO.Path]::GetFullPath($exe) } catch { continue }
  $insideWork = $full.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)
  $insideRuntime = $runtimePrefix -and $full.StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)
  if (-not ($insideWork -or $insideRuntime)) { continue }
  if ($cmd -notmatch '[\\/]compiled[\\/]client[\\/]main\.js') { continue }
  if (Stop-WaddleProcessTree -ProcessId ([int]$candidate.ProcessId) -Reason 'recovery_scan') { $recovered++ }
}

if ($state) {
  $state.status = 'STOPPED'
  $state | Add-Member -NotePropertyName stopped_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

Write-Host "WADDLE_STOP=PASS state_process_id=$stateProcessId recovered=$recovered runtime_home=$runtimeHome core_not_required=true"
