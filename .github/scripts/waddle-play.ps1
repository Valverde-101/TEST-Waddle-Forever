[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$work = Join-Path $repo '.work'
$stateDir = Join-Path $work 'state'
$runtimeLogs = Join-Path $work 'logs\runtime'
$statePath = Join-Path $stateDir 'waddle-client.json'
$electronCanonical = Join-Path $repo 'node_modules\electron\dist\electron.exe'
$electronManifest = Join-Path $repo 'node_modules\electron\package.json'
$entryCanonical = Join-Path $repo 'compiled\client\main.js'
$flashCanonical = Join-Path $repo 'assets\flash\pepflashplayer64_32_0_0_303.dll'
$modulesCanonical = Join-Path $repo 'node_modules'
$machine = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { 'unknown-machine' } else { [string]$env:COMPUTERNAME }

New-Item -ItemType Directory -Force -Path $stateDir,$runtimeLogs | Out-Null

$nativeProcessScript = Join-Path $PSScriptRoot 'waddle-win32-process.ps1'
if (-not (Test-Path -LiteralPath $nativeProcessScript -PathType Leaf)) {
  throw "WADDLE_PLAY=FAIL native_process_helper_missing=$nativeProcessScript"
}
. $nativeProcessScript

function Get-WaddleProcessExecutable {
  param([int]$ProcessId)
  if ($ProcessId -le 0) { return '' }
  try {
    $item = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
    if ($item -and -not [string]::IsNullOrWhiteSpace([string]$item.ExecutablePath)) {
      return [IO.Path]::GetFullPath([string]$item.ExecutablePath)
    }
  } catch {}
  return ''
}

function Stop-WaddleOwnedProcess {
  param([int]$ProcessId,[string]$ExpectedExecutable,[string]$Reason)
  if ($ProcessId -le 0) { return }
  if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }

  $actual = Get-WaddleProcessExecutable -ProcessId $ProcessId
  if ([string]::IsNullOrWhiteSpace($actual)) {
    Write-Host "WADDLE_PLAY_CLEANUP=SKIP pid=$ProcessId reason=unverified_process owner=$Reason"
    return
  }

  $expected = ''
  try { if (-not [string]::IsNullOrWhiteSpace($ExpectedExecutable)) { $expected = [IO.Path]::GetFullPath($ExpectedExecutable) } } catch {}
  if ([string]::IsNullOrWhiteSpace($expected) -or -not $actual.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "WADDLE_PLAY_CLEANUP=SKIP pid=$ProcessId reason=pid_not_owned actual=$actual expected=$expected"
    return
  }

  & taskkill.exe /PID $ProcessId /T /F | Out-Null
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ne 0 -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    throw "WADDLE_PLAY=FAIL stop_owned_client pid=$ProcessId reason=$Reason taskkill_exit=$code"
  }
  Write-Host "WADDLE_PLAY_CLEANUP=PASS pid=$ProcessId reason=$Reason"
}

function Stop-WaddlePriorState {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
  try {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -ErrorAction Stop
    $pidProp = $prior.PSObject.Properties['pid']
    if (-not $pidProp) { return }

    $machineProp = $prior.PSObject.Properties['machine']
    if (-not $machineProp -or [string]::IsNullOrWhiteSpace([string]$machineProp.Value)) {
      Write-Host "WADDLE_PLAY_CLEANUP=SKIP pid=$($pidProp.Value) reason=legacy_shared_state_has_no_machine current_machine=$machine"
      return
    }
    if (-not ([string]$machineProp.Value).Equals($machine,[StringComparison]::OrdinalIgnoreCase)) {
      Write-Host "WADDLE_PLAY_CLEANUP=SKIP pid=$($pidProp.Value) reason=state_owned_by_other_machine state_machine=$($machineProp.Value) current_machine=$machine"
      return
    }

    $launchProp = $prior.PSObject.Properties['electron_launch_executable']
    $expected = if ($launchProp) { [string]$launchProp.Value } else { $electronCanonical }
    Stop-WaddleOwnedProcess -ProcessId ([int]$pidProp.Value) -ExpectedExecutable $expected -Reason 'replace_previous_client'
  } catch {
    Write-Host "WADDLE_PLAY_CLEANUP=WARN reason=state_parse_or_cleanup error=$($_.Exception.Message)"
  }
}

function Get-WaddleCurrentSha {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) {
    try {
      $safe = $repo.Replace('"','\"')
      $value = & $git.Source -c "safe.directory=$safe" -C $repo rev-parse HEAD 2>$null
      $global:LASTEXITCODE = 0
      if ($value) { return ([string]$value).Trim().ToLowerInvariant() }
    } catch {}
  }
  $summaryPath = Join-Path $work 'state\waddle-build-summary.json'
  if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
    try {
      $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
      if ($summary.source_sha) { return ([string]$summary.source_sha).Trim().ToLowerInvariant() }
    } catch {}
  }
  return ''
}

function Get-WaddleDependencyFingerprint {
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($name in @('package.json','yarn.lock')) {
    $path = Join-Path $repo $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $parts.Add((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant())
  }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join '|'))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Get-WaddleNetworkMapping {
  param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\')) {
    return [pscustomobject]@{ source_root=[IO.Path]::GetPathRoot($full); provider_root=[IO.Path]::GetPathRoot($full) }
  }
  $sourceRoot = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($sourceRoot)) { return $null }
  try {
    $device = $sourceRoot.TrimEnd('\').Replace("'","''")
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$device'" -ErrorAction Stop
    if ($disk -and [int]$disk.DriveType -eq 4 -and -not [string]::IsNullOrWhiteSpace([string]$disk.ProviderName)) {
      return [pscustomobject]@{ source_root=$sourceRoot; provider_root=([string]$disk.ProviderName).TrimEnd('\') }
    }
  } catch {}
  return $null
}

function Resolve-WaddleLaunchRoot {
  param([string]$RepoRoot)
  $mapping = Get-WaddleNetworkMapping -Path $RepoRoot
  if (-not $mapping) {
    return [pscustomobject]@{ repo=$RepoRoot; network_backed=$false; mode='local'; provider=''; host='' }
  }

  $provider = [string]$mapping.provider_root
  $sourceRoot = [string]$mapping.source_root
  $match = [regex]::Match($provider.TrimEnd('\'),'^\\\\([^\\]+)\\([^\\]+)')
  if (-not $match.Success) {
    Write-Host "WADDLE_SMB_ALIAS=WARN provider=$provider reason=provider_parse fallback=direct_mapped_path"
    return [pscustomobject]@{ repo=$RepoRoot; network_backed=$true; mode='mapped_direct'; provider=$provider; host='' }
  }

  $server = [string]$match.Groups[1].Value
  $share = [string]$match.Groups[2].Value
  $relativeRepo = ([IO.Path]::GetFullPath($RepoRoot)).Substring($sourceRoot.Length).TrimStart('\')
  $candidates = New-Object System.Collections.Generic.List[string]

  if ($server -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $candidates.Add($server) }
  if ($server -match '^\d{1,3}(\.\d{1,3}){3}$') {
    try {
      $nbt = & nbtstat.exe -A $server 2>$null
      $global:LASTEXITCODE = 0
      foreach ($line in @($nbt)) {
        if ([string]$line -match '^\s*([^\s<]{1,15})\s+<00>\s+UNIQUE') {
          $candidate = [string]$Matches[1]
          if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidates.Contains($candidate)) { $candidates.Add($candidate) }
        }
      }
    } catch {}
  }

  foreach ($hostName in $candidates) {
    $aliasRoot = "\\$hostName\$share"
    if (-not (Test-Path -LiteralPath $aliasRoot -PathType Container)) { continue }
    $aliasRepo = if ([string]::IsNullOrWhiteSpace($relativeRepo)) { $aliasRoot } else { Join-Path $aliasRoot $relativeRepo }
    if (-not (Test-Path -LiteralPath $aliasRepo -PathType Container)) { continue }
    Write-Host "WADDLE_SMB_ALIAS=PASS provider=$provider host=$hostName launch_repo=$aliasRepo mode=optional_hostname_alias"
    return [pscustomobject]@{ repo=[IO.Path]::GetFullPath($aliasRepo); network_backed=$true; mode='hostname_alias'; provider=$provider; host=$hostName }
  }

  Write-Host "WADDLE_SMB_ALIAS=WARN provider=$provider server=$server candidates=$($candidates -join ',') fallback=direct_existing_mapping create_process=true shell_execute=false"
  return [pscustomobject]@{ repo=$RepoRoot; network_backed=$true; mode='mapped_or_ip_direct'; provider=$provider; host='' }
}

function Get-WaddleRuntimeEvents {
  param([string]$Path,[int]$ProcessId)
  $events = @()
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
    $text = [string]$line
    if ([string]::IsNullOrWhiteSpace($text) -or -not $text.TrimStart().StartsWith('{')) { continue }
    try {
      $item = $text | ConvertFrom-Json -ErrorAction Stop
      if (-not $item.PSObject.Properties['pid'] -or -not $item.PSObject.Properties['event']) { continue }
      if ([int]$item.pid -ne $ProcessId) { continue }
      $events += $item
    } catch {}
  }
  return $events
}

function Get-WaddleFatalRuntimeEvent {
  param($Events)
  foreach ($event in @($Events)) {
    $name = [string]$event.event
    if ($name -in @('uncaught-exception','unhandled-rejection','render-process-gone','window-unresponsive','media-start-failed','services-start-failed','runtime-lease-acquire-failed')) { return $event }
    if ($name -eq 'window-did-fail-load') {
      $mainFrame = $event.PSObject.Properties['isMainFrame']
      if (-not $mainFrame -or [bool]$mainFrame.Value) { return $event }
    }
  }
  return $null
}

foreach ($required in @($electronCanonical,$electronManifest,$entryCanonical,$flashCanonical,$modulesCanonical)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_PLAY=FAIL required_missing=$required hint=run_Waddle-Setup.cmd_once" }
}
$manifest = Get-Content -LiteralPath $electronManifest -Raw | ConvertFrom-Json -ErrorAction Stop
if ([string]$manifest.version -ne '10.4.7') { throw "WADDLE_PLAY=FAIL electron_expected=10.4.7 actual=$($manifest.version)" }
if ((Get-Item -LiteralPath $flashCanonical).Length -lt 1048576) { throw "WADDLE_PLAY=FAIL flash_invalid=$flashCanonical" }

Stop-WaddlePriorState

$launchRoot = Resolve-WaddleLaunchRoot -RepoRoot $repo
$launchRepo = [string]$launchRoot.repo
$launchElectron = Join-Path $launchRepo 'node_modules\electron\dist\electron.exe'
$launchEntry = Join-Path $launchRepo 'compiled\client\main.js'
$launchFlash = Join-Path $launchRepo 'assets\flash\pepflashplayer64_32_0_0_303.dll'
$launchModules = Join-Path $launchRepo 'node_modules'
foreach ($required in @($launchElectron,$launchEntry,$launchFlash,$launchModules)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_PLAY=FAIL launch_path_missing=$required mode=$($launchRoot.mode)" }
}

try { Unblock-File -LiteralPath $launchElectron -ErrorAction Stop } catch {}

$portableUserData = Join-Path $repo 'user-data'
$profileRoot = Join-Path $work ("runtime-profiles\$machine")
$chromiumProfile = Join-Path $profileRoot 'chromium'
New-Item -ItemType Directory -Force -Path $portableUserData,$chromiumProfile | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$machine-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$machine-$stamp.stderr.log"
Set-Content -LiteralPath $stdout -Encoding UTF8 -Value 'WADDLE_RUNTIME_STDIO=DETACHED stream=stdout source=play'
Set-Content -LiteralPath $stderr -Encoding UTF8 -Value 'WADDLE_RUNTIME_STDIO=DETACHED stream=stderr source=play'

$env:NODE_ENV = 'dev'
$env:WADDLE_PORTABLE = '1'
$env:WADDLE_USER_DATA_DIR = $portableUserData
$env:WADDLE_RUNTIME_MODE = 'repo_local_direct'
$env:WADDLE_RUNTIME_ROOT = $repo
$env:WADDLE_RUNTIME_HOME = $repo
$env:WADDLE_NODE_MODULES = $launchModules
$env:WADDLE_RUNTIME_NODE_MODULES = $launchModules
$env:NODE_PATH = $launchModules
$env:WADDLE_PPAPI_FLASH_PATH = $launchFlash
$env:WADDLE_PPAPI_FLASH_VERSION = '32.0.0.303'
$env:WADDLE_RUNTIME_DIAGNOSTIC_LOG = $stderr
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue

$sha = Get-WaddleCurrentSha
$fingerprint = Get-WaddleDependencyFingerprint
$launchWatch = [Diagnostics.Stopwatch]::StartNew()
$process = $null
try {
  $processId = Start-WaddleWin32DetachedProcess -FilePath $launchElectron -ArgumentList @("--user-data-dir=$chromiumProfile",$launchEntry) -WorkingDirectory $repo
  $process = Get-Process -Id $processId -ErrorAction Stop
} catch {
  throw "WADDLE_PLAY=FAIL process_start executable=$launchElectron mode=$($launchRoot.mode) shell_execute=false inherit_handles=false error=$($_.Exception.Message)"
}
if (-not $process -or $process.Id -le 0) { throw 'WADDLE_PLAY=FAIL process_id_missing' }

$state = [ordered]@{
  schema='waddle-client-state/v11'; status='STARTING'; platform='windows-x64'; machine=$machine; pid=$process.Id; source_sha=$sha
  repo_root=$repo; work_root=$work; dependency_build_root=$modulesCanonical; dependency_fingerprint=$fingerprint
  dependency_mode='reused'; dependency_mutation_while_running=$false; stdio_mode='win32_detached_no_inherited_handles'
  managed_node_home='NOT_REQUIRED_FOR_PLAY'; managed_node_exe='NOT_REQUIRED_FOR_PLAY'; runtime_mode='repo_local_direct'
  runtime_home=$repo; runtime_root=$repo; runtime_current_root=$repo; runtime_manifest=(Join-Path $stateDir 'runtime-snapshot.json')
  runtime_app_entry=$entryCanonical; runtime_node_modules=$modulesCanonical; electron_source_executable=$electronCanonical
  electron_executable=$electronCanonical; electron_launch_executable=$launchElectron; electron_version='10.4.7'
  electron_launch_mode='repo_direct_start_process'; electron_network_backed=[bool]$launchRoot.network_backed; launcher_return_ms=0
  smb_launch_mode=[string]$launchRoot.mode; smb_provider=[string]$launchRoot.provider; ppapi_flash_source_path=$flashCanonical
  ppapi_flash_path=$flashCanonical; ppapi_flash_version='32.0.0.303'; ffdec_path='NOT_REQUIRED_FOR_PLAY'
  portable_user_data=$portableUserData; chromium_profile=$chromiumProfile; stdout=$stdout; stderr=$stderr; started_utc=[DateTime]::UtcNow.ToString('o')
}
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

$healthSeconds = if ($launchRoot.network_backed) { 90 } else { 45 }
$deadline = [DateTime]::UtcNow.AddSeconds($healthSeconds)
$lastEvent = 'none'
try {
  do {
    Start-Sleep -Milliseconds 250
    if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
      $tail = if (Test-Path -LiteralPath $stderr) { (@(Get-Content -LiteralPath $stderr -Tail 12 -ErrorAction SilentlyContinue) -join ' | ') } else { 'diagnostic_missing' }
      throw "WADDLE_PLAY=FAIL process_exited_before_ready pid=$($process.Id) last_event=$lastEvent tail=$tail"
    }
    $events = @(Get-WaddleRuntimeEvents -Path $stderr -ProcessId $process.Id)
    if ($events.Count -gt 0) { $lastEvent = [string]$events[$events.Count - 1].event }
    $fatal = Get-WaddleFatalRuntimeEvent -Events $events
    if ($fatal) { throw "WADDLE_PLAY=FAIL runtime_event pid=$($process.Id) event=$($fatal | ConvertTo-Json -Compress -Depth 8)" }
    $ready = @($events | Where-Object { [string]$_.event -eq 'main-window-ready' } | Select-Object -Last 1)
    if ($ready.Count -gt 0) {
      $launchWatch.Stop()
      $url = if ($ready[0].PSObject.Properties['url']) { [string]$ready[0].url } else { '' }
      $state['status']='RUNNING'; $state['ready_utc']=[DateTime]::UtcNow.ToString('o'); $state['launcher_return_ms']=[int64]$launchWatch.ElapsedMilliseconds; $state['main_window_url']=$url
      $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
      Write-Host "WADDLE_PLAY=PASS pid=$($process.Id) machine=$machine electron=10.4.7 event=main-window-ready url=$url launch_ms=$($launchWatch.ElapsedMilliseconds) runtime=$repo node_modules=$modulesCanonical flash=$flashCanonical network_backed=$($launchRoot.network_backed) smb_mode=$($launchRoot.mode) shell_execute=false inherit_handles=false files_copied=0 local_install=0"
      exit 0
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  $tail = if (Test-Path -LiteralPath $stderr) { (@(Get-Content -LiteralPath $stderr -Tail 16 -ErrorAction SilentlyContinue) -join ' | ') } else { 'diagnostic_missing' }
  throw "WADDLE_PLAY=FAIL main_window_ready_timeout pid=$($process.Id) timeout_seconds=$healthSeconds last_event=$lastEvent diagnostic=$stderr tail=$tail"
} catch {
  try { Stop-WaddleOwnedProcess -ProcessId $process.Id -ExpectedExecutable $launchElectron -Reason 'health_failure' } catch {}
  $state['status']='FAILED'; $state['failure']=[string]$_.Exception.Message; $state['failed_utc']=[DateTime]::UtcNow.ToString('o')
  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
  throw
}
