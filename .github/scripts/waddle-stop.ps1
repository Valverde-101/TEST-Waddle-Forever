[CmdletBinding()]
param(
  [string]$AndroidBuildRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'waddle-common.ps1')

$repo = Resolve-WaddleRepoRoot -Context @{}
$work = Join-Path $repo '.work'
$stateDir = Join-Path $work 'state'
$repoElectron = [IO.Path]::GetFullPath((Join-Path $repo 'node_modules\electron\dist\electron.exe'))
$repoEntry = [IO.Path]::GetFullPath((Join-Path $repo 'compiled\client\main.js'))
$machine = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { 'unknown-machine' } else { [string]$env:COMPUTERNAME }
$safeMachine = $machine -replace '[^A-Za-z0-9_.-]','_'

function Test-WaddleNetworkBackedPath {
  param([Parameter(Mandatory)][string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\')) { return $true }
  $root = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($root)) { return $false }
  try {
    $device = $root.TrimEnd('\').Replace("'","''")
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$device'" -ErrorAction Stop
    return [bool]($disk -and [int]$disk.DriveType -eq 4)
  } catch {
    return $false
  }
}

$networkBacked = Test-WaddleNetworkBackedPath -Path $repo
$statePath = if ($networkBacked) {
  Join-Path $stateDir ("clients\$safeMachine.json")
} else {
  Join-Path $stateDir 'waddle-client.json'
}

$legacyExternal = $null
if ($AndroidBuildRoot) {
  $legacyExternal = [IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Runtime\Waddle-Forever'))
} else {
  try {
    $repoInfo = [IO.DirectoryInfo]$repo
    if ($repoInfo.Parent -and $repoInfo.Parent.Name -ieq 'Repositories' -and $repoInfo.Parent.Parent) {
      $legacyExternal = [IO.Path]::GetFullPath((Join-Path $repoInfo.Parent.Parent.FullName 'Runtime\Waddle-Forever'))
    }
  } catch {}
}

$localElectronCache = $null
$localBase = [string]$env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($localBase)) { $localBase = [IO.Path]::GetTempPath() }
try { $localElectronCache = [IO.Path]::GetFullPath((Join-Path $localBase 'WaddleForever\electron-cache')).TrimEnd('\') + '\' } catch {}

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

function Test-WaddleProcessOwnedByRepo {
  param([Parameter(Mandatory)][int]$ProcessId)
  try {
    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
    if (-not $candidate) { return $false }
    $cmd = [string]$candidate.CommandLine
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
    return $cmd.IndexOf($repoEntry,[StringComparison]::OrdinalIgnoreCase) -ge 0
  } catch {
    return $false
  }
}

$state = $null
$stateProcessId = 0
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
  try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $stateMachine = if ($state.PSObject.Properties['machine']) { [string]$state.machine } else { '' }
    if ($networkBacked -and ([string]::IsNullOrWhiteSpace($stateMachine) -or -not $stateMachine.Equals($machine,[StringComparison]::OrdinalIgnoreCase))) {
      Write-Host "WADDLE_STOP_STATE=SKIP path=$statePath reason=machine_mismatch state_machine=$stateMachine current_machine=$machine"
    } else {
      $stateProcessId = [int]$state.pid
      if ($stateProcessId -gt 0 -and (Test-WaddleProcessOwnedByRepo -ProcessId $stateProcessId)) {
        Stop-WaddleProcessTree -ProcessId $stateProcessId -Reason 'state_client' | Out-Null
      } elseif ($stateProcessId -gt 0 -and (Get-Process -Id $stateProcessId -ErrorAction SilentlyContinue)) {
        Write-Host "WADDLE_STOP_STATE=SKIP pid=$stateProcessId reason=pid_not_owned_by_repo"
      }
    }
  } catch {
    Write-Host "WADDLE_STOP_STATE=WARN path=$statePath error=$($_.Exception.Message)"
  }
}

# Recovery is local-process only. A client on another PC is not visible through
# Win32_Process, so this cannot terminate another machine. Match the exact repo
# entry in the command line before accepting repo, old .work, retired external,
# or the per-machine LocalAppData Electron cache as an owned executable.
$workPrefix = [IO.Path]::GetFullPath($work).TrimEnd('\') + '\'
$legacyPrefix = if ($legacyExternal) { $legacyExternal.TrimEnd('\') + '\' } else { $null }
$recovered = 0
foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
  $exe = [string]$candidate.ExecutablePath
  $cmd = [string]$candidate.CommandLine
  if ([string]::IsNullOrWhiteSpace($exe) -or [string]::IsNullOrWhiteSpace($cmd)) { continue }
  if ($cmd.IndexOf($repoEntry,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
  try { $full = [IO.Path]::GetFullPath($exe) } catch { continue }
  $repoDirect = $full -ieq $repoElectron
  $insideWork = $full.StartsWith($workPrefix,[StringComparison]::OrdinalIgnoreCase)
  $insideLegacyExternal = $legacyPrefix -and $full.StartsWith($legacyPrefix,[StringComparison]::OrdinalIgnoreCase)
  $insideLocalCache = $localElectronCache -and $full.StartsWith($localElectronCache,[StringComparison]::OrdinalIgnoreCase)
  if (-not ($repoDirect -or $insideWork -or $insideLegacyExternal -or $insideLocalCache)) { continue }
  if (Stop-WaddleProcessTree -ProcessId ([int]$candidate.ProcessId) -Reason 'recovery_scan') { $recovered++ }
}

if ($state) {
  $state.status = 'STOPPED'
  $state | Add-Member -NotePropertyName stopped_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

Write-Host "WADDLE_STOP=PASS machine=$machine state=$statePath state_process_id=$stateProcessId recovered=$recovered repo=$repo network_backed=$networkBacked local_electron_cache=$localElectronCache core_not_required=true"
