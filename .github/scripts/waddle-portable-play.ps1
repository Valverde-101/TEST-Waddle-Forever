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

New-Item -ItemType Directory -Force -Path $stateDir,$runtimeLogs | Out-Null

function Stop-WaddlePortableProcess {
  param([int]$ProcessId,[string]$Reason)
  if ($ProcessId -le 0) { return }
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $process) { return }
  & taskkill.exe /PID $ProcessId /T /F | Out-Null
  $code = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($code -ne 0 -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    throw "WADDLE_PLAY=FAIL stop_existing pid=$ProcessId reason=$Reason taskkill_exit=$code"
  }
  Write-Host "WADDLE_PLAY_CLEANUP=PASS pid=$ProcessId reason=$Reason"
}

function Stop-WaddlePriorState {
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
  try {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -ErrorAction Stop
    $pidProperty = $prior.PSObject.Properties['pid']
    if ($pidProperty) { Stop-WaddlePortableProcess -ProcessId ([int]$pidProperty.Value) -Reason 'replace_previous_client' }
  } catch {
    Write-Host "WADDLE_PLAY_CLEANUP=WARN reason=invalid_previous_state error=$($_.Exception.Message)"
  }
}

function Get-WaddleCurrentSha {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if (-not $git) { return '' }
  try {
    $safe = $repo.Replace('"','\"')
    $value = & $git.Source -c "safe.directory=$safe" -C $repo rev-parse HEAD 2>$null
    $global:LASTEXITCODE = 0
    if ($value) { return ([string]$value).Trim().ToLowerInvariant() }
  } catch {}
  return ''
}

function Get-WaddleMappedProvider {
  param([Parameter(Mandatory)][string]$Path)

  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\')) {
    $root = [IO.Path]::GetPathRoot($full)
    return [pscustomobject]@{ source_root=$root; provider_root=$root; mapped=$true }
  }

  $sourceRoot = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($sourceRoot)) { return $null }
  $device = $sourceRoot.TrimEnd('\')
  try {
    $escaped = $device.Replace("'","''")
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$escaped'" -ErrorAction Stop
    if ($disk -and [int]$disk.DriveType -eq 4 -and -not [string]::IsNullOrWhiteSpace([string]$disk.ProviderName)) {
      return [pscustomobject]@{ source_root=$sourceRoot; provider_root=([string]$disk.ProviderName).TrimEnd('\'); mapped=$true }
    }
  } catch {}
  return $null
}

function Add-WaddleHostCandidate {
  param([System.Collections.Generic.List[string]]$List,[string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  $candidate = $Value.Trim().TrimEnd('.')
  if ([string]::IsNullOrWhiteSpace($candidate)) { return }
  if ($candidate -match '^\d{1,3}(\.\d{1,3}){3}$') { return }
  $short = $candidate.Split('.')[0]
  foreach ($item in @($short,$candidate)) {
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    $exists = @($List | Where-Object { $_ -ieq $item }).Count -gt 0
    if (-not $exists) { $List.Add($item) }
  }
}

function Resolve-WaddlePortableLaunchRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $mapping = Get-WaddleMappedProvider -Path $RepoRoot
  if (-not $mapping) {
    return [pscustomobject]@{ repo=$RepoRoot; network_backed=$false; mode='local'; server=''; share='' }
  }

  $provider = ([string]$mapping.provider_root).TrimEnd('\')
  if ($provider -notmatch '^\\\\([^\\]+)\\([^\\]+)') {
    throw "WADDLE_SMB_ALIAS=FAIL provider_parse provider=$provider"
  }
  $server = [string]$Matches[1]
  $share = [string]$Matches[2]
  $sourceRoot = [string]$mapping.source_root
  $relativeRepo = ([IO.Path]::GetFullPath($RepoRoot)).Substring($sourceRoot.Length).TrimStart('\')

  $simpleServer = ($server -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -and $server -notmatch '\.')
  $candidates = New-Object 'System.Collections.Generic.List[string]'
  if ($simpleServer) { Add-WaddleHostCandidate -List $candidates -Value $server }

  try {
    $dns = [Net.Dns]::GetHostEntry($server)
    if ($dns -and $dns.HostName) { Add-WaddleHostCandidate -List $candidates -Value ([string]$dns.HostName) }
  } catch {}

  if ($server -match '^\d{1,3}(\.\d{1,3}){3}$') {
    try {
      $nbt = & nbtstat.exe -A $server 2>$null
      $global:LASTEXITCODE = 0
      foreach ($line in @($nbt)) {
        $text = [string]$line
        if ($text -match '^\s*([^\s<]{1,15})\s+<00>\s+UNIQUE') {
          Add-WaddleHostCandidate -List $candidates -Value ([string]$Matches[1])
        }
      }
    } catch {}
    try {
      $ping = & ping.exe -a -n 1 -w 1000 $server 2>$null
      $global:LASTEXITCODE = 0
      foreach ($line in @($ping)) {
        if ([string]$line -match '(?i)pinging\s+([^\s\[]+)\s+\[') {
          Add-WaddleHostCandidate -List $candidates -Value ([string]$Matches[1])
        }
      }
    } catch {}
  }

  foreach ($hostName in $candidates) {
    $aliasRoot = "\\$hostName\$share"
    if (-not (Test-Path -LiteralPath $aliasRoot -PathType Container)) { continue }
    $aliasRepo = if ([string]::IsNullOrWhiteSpace($relativeRepo)) { $aliasRoot } else { Join-Path $aliasRoot $relativeRepo }
    if (-not (Test-Path -LiteralPath $aliasRepo -PathType Container)) { continue }
    Write-Host "WADDLE_SMB_ALIAS=PASS provider=$provider server=$server intranet_host=$hostName launch_repo=$aliasRepo files_copied=0 registry_changes=0 local_install=0"
    return [pscustomobject]@{ repo=[IO.Path]::GetFullPath($aliasRepo); network_backed=$true; mode='netbios_intranet_alias'; server=$server; share=$share; host=$hostName }
  }

  if ($simpleServer) {
    Write-Host "WADDLE_SMB_ALIAS=PASS provider=$provider server=$server intranet_host=$server launch_repo=$RepoRoot files_copied=0 registry_changes=0 local_install=0 mode=existing_hostname"
    return [pscustomobject]@{ repo=$RepoRoot; network_backed=$true; mode='existing_hostname'; server=$server; share=$share; host=$server }
  }

  throw "WADDLE_SMB_ALIAS=FAIL ip_unc_requires_hostname provider=$provider server=$server candidates=$($candidates -join ',') hint=map_share_with_computer_name_not_ip"
}

function Get-WaddleRuntimeEvents {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int]$ProcessId)
  $events = @()
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
    $text = [string]$line
    if ([string]::IsNullOrWhiteSpace($text) -or -not $text.TrimStart().StartsWith('{')) { continue }
    try {
      $item = $text | ConvertFrom-Json -ErrorAction Stop
      $pidProp = $item.PSObject.Properties['pid']
      $eventProp = $item.PSObject.Properties['event']
      if (-not $pidProp -or -not $eventProp) { continue }
      if ([int]$pidProp.Value -ne $ProcessId) { continue }
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

$launchRoot = Resolve-WaddlePortableLaunchRoot -RepoRoot $repo
$launchRepo = [string]$launchRoot.repo
$launchElectron = Join-Path $launchRepo 'node_modules\electron\dist\electron.exe'
$launchEntry = Join-Path $launchRepo 'compiled\client\main.js'
$launchFlash = Join-Path $launchRepo 'assets\flash\pepflashplayer64_32_0_0_303.dll'
$launchModules = Join-Path $launchRepo 'node_modules'
foreach ($required in @($launchElectron,$launchEntry,$launchFlash,$launchModules)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_PLAY=FAIL launch_alias_missing=$required mode=$($launchRoot.mode)" }
}

# Remove a file-level Mark-of-the-Web stream if one exists. This changes only
# metadata on the shared executable; it does not install or copy Electron.
try { Unblock-File -LiteralPath $electronCanonical -ErrorAction Stop } catch {}
try { if ($launchElectron -ine $electronCanonical) { Unblock-File -LiteralPath $launchElectron -ErrorAction Stop } } catch {}

$machine = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { 'unknown-machine' } else { $env:COMPUTERNAME }
$portableUserData = Join-Path $repo 'user-data'
$profileRoot = Join-Path $work ("runtime-profiles\$machine")
$chromiumProfile = Join-Path $profileRoot 'chromium'
New-Item -ItemType Directory -Force -Path $portableUserData,$chromiumProfile | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$stamp.stderr.log"
Set-Content -LiteralPath $stdout -Encoding UTF8 -Value 'WADDLE_RUNTIME_STDIO=DETACHED stream=stdout source=portable-play'
Set-Content -LiteralPath $stderr -Encoding UTF8 -Value 'WADDLE_RUNTIME_STDIO=DETACHED stream=stderr source=portable-play'

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
$launchWatch = [Diagnostics.Stopwatch]::StartNew()
$process = $null
try {
  $arguments = @("--user-data-dir=$chromiumProfile",$launchEntry)
  $process = Start-Process -FilePath $launchElectron -ArgumentList $arguments -WorkingDirectory $launchRepo -PassThru -ErrorAction Stop
} catch {
  throw "WADDLE_PLAY=FAIL process_start executable=$launchElectron mode=$($launchRoot.mode) error=$($_.Exception.Message)"
}

if (-not $process -or $process.Id -le 0) { throw 'WADDLE_PLAY=FAIL process_id_missing' }

$startingState = [ordered]@{
  schema='waddle-client-state/v12'; status='STARTING'; platform='windows-x64'; pid=$process.Id; source_sha=$sha;
  repo_root=$repo; work_root=$work; runtime_mode='repo_local_direct'; runtime_root=$repo; runtime_home=$repo;
  runtime_app_entry=$entryCanonical; runtime_node_modules=$modulesCanonical; electron_executable=$electronCanonical;
  electron_launch_executable=$launchElectron; electron_version='10.4.7'; electron_network_backed=[bool]$launchRoot.network_backed;
  smb_launch_mode=[string]$launchRoot.mode; ppapi_flash_path=$flashCanonical; portable_user_data=$portableUserData;
  chromium_profile=$chromiumProfile; stdout=$stdout; stderr=$stderr; started_utc=[DateTime]::UtcNow.ToString('o')
}
$startingState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

$healthSeconds = if ($launchRoot.network_backed) { 90 } else { 45 }
$deadline = [DateTime]::UtcNow.AddSeconds($healthSeconds)
$lastEvent = 'none'
try {
  do {
    Start-Sleep -Milliseconds 250
    $live = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $live) {
      $tail = if (Test-Path -LiteralPath $stderr -PathType Leaf) { (@(Get-Content -LiteralPath $stderr -Tail 12 -ErrorAction SilentlyContinue) -join ' | ') } else { 'diagnostic_missing' }
      throw "WADDLE_PLAY=FAIL process_exited_before_ready pid=$($process.Id) last_event=$lastEvent tail=$tail"
    }

    $events = @(Get-WaddleRuntimeEvents -Path $stderr -ProcessId $process.Id)
    if ($events.Count -gt 0) { $lastEvent = [string]$events[$events.Count - 1].event }
    $fatal = Get-WaddleFatalRuntimeEvent -Events $events
    if ($fatal) {
      $fatalJson = $fatal | ConvertTo-Json -Compress -Depth 8
      throw "WADDLE_PLAY=FAIL runtime_event pid=$($process.Id) event=$fatalJson"
    }

    $ready = @($events | Where-Object { [string]$_.event -eq 'main-window-ready' } | Select-Object -Last 1)
    if ($ready.Count -gt 0) {
      $launchWatch.Stop()
      $readyEvent = $ready[0]
      $urlProp = $readyEvent.PSObject.Properties['url']
      $url = if ($urlProp) { [string]$urlProp.Value } else { '' }
      $startingState.status = 'RUNNING'
      $startingState | Add-Member -NotePropertyName ready_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
      $startingState | Add-Member -NotePropertyName launcher_return_ms -NotePropertyValue ([int64]$launchWatch.ElapsedMilliseconds) -Force
      $startingState | Add-Member -NotePropertyName main_window_url -NotePropertyValue $url -Force
      $startingState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
      Write-Host "WADDLE_PLAY=PASS pid=$($process.Id) electron=10.4.7 event=main-window-ready url=$url launch_ms=$($launchWatch.ElapsedMilliseconds) runtime=$repo node_modules=$modulesCanonical flash=$flashCanonical portable_user_data=$portableUserData chromium_profile=$chromiumProfile network_backed=$($launchRoot.network_backed) smb_mode=$($launchRoot.mode) files_copied=0 local_install=0"
      exit 0
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  $tail = if (Test-Path -LiteralPath $stderr -PathType Leaf) { (@(Get-Content -LiteralPath $stderr -Tail 16 -ErrorAction SilentlyContinue) -join ' | ') } else { 'diagnostic_missing' }
  throw "WADDLE_PLAY=FAIL main_window_ready_timeout pid=$($process.Id) timeout_seconds=$healthSeconds last_event=$lastEvent diagnostic=$stderr tail=$tail"
} catch {
  try { Stop-WaddlePortableProcess -ProcessId $process.Id -Reason 'health_failure' } catch {}
  $startingState.status = 'FAILED'
  $startingState | Add-Member -NotePropertyName failure -NotePropertyValue ([string]$_.Exception.Message) -Force
  $startingState | Add-Member -NotePropertyName failed_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
  $startingState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
  throw
}
