[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
$work = Join-Path $repo '.work'
$stateDir = Join-Path $work 'state'
$clientStateDir = Join-Path $stateDir 'clients'
$legacyStatePath = Join-Path $stateDir 'waddle-client.json'
$runtimeLogs = Join-Path $work 'logs\runtime'
$electronCanonical = Join-Path $repo 'node_modules\electron\dist\electron.exe'
$electronManifest = Join-Path $repo 'node_modules\electron\package.json'
$entryCanonical = Join-Path $repo 'compiled\client\main.js'
$flashCanonical = Join-Path $repo 'assets\flash\pepflashplayer64_32_0_0_303.dll'
$modulesCanonical = Join-Path $repo 'node_modules'
$machine = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { 'unknown-machine' } else { [string]$env:COMPUTERNAME }
$safeMachine = $machine -replace '[^A-Za-z0-9_.-]','_'

New-Item -ItemType Directory -Force -Path $stateDir,$clientStateDir,$runtimeLogs | Out-Null

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
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  try {
    $prior = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    $pidProp = $prior.PSObject.Properties['pid']
    if (-not $pidProp) { return }

    $machineProp = $prior.PSObject.Properties['machine']
    if (-not $machineProp -or [string]::IsNullOrWhiteSpace([string]$machineProp.Value)) {
      Write-Host "WADDLE_PLAY_CLEANUP=SKIP pid=$($pidProp.Value) reason=legacy_state_has_no_machine current_machine=$machine"
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
    Write-Host "WADDLE_PLAY_CLEANUP=WARN reason=state_parse_or_cleanup path=$Path error=$($_.Exception.Message)"
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

function Get-WaddleStableToken {
  param([Parameter(Mandatory)][string]$Value,[int]$Length = 24)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $valueHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    if ($Length -lt 8) { $Length = 8 }
    if ($Length -gt $valueHash.Length) { $Length = $valueHash.Length }
    return $valueHash.Substring(0,$Length)
  } finally {
    $sha.Dispose()
  }
}

function Get-WaddleNetworkMapping {
  param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\')) {
    $root = [IO.Path]::GetPathRoot($full)
    return [pscustomobject]@{ source_root=$root; provider_root=$root.TrimEnd('\') }
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
  $server = ''
  $match = [regex]::Match($provider.TrimEnd('\'),'^\\\\([^\\]+)\\([^\\]+)')
  if ($match.Success) { $server = [string]$match.Groups[1].Value }

  # Do not translate a valid mapped/UNC path through NetBIOS aliases. The prior
  # alias hunt was nondeterministic for IP-based SMB shares and could report WARN
  # even after CreateProcessW had proved the mapping itself was usable.
  Write-Host "WADDLE_SMB_PATH=PASS provider=$provider server=$server launch_repo=$RepoRoot mode=direct_existing_mapping alias_required=false"
  return [pscustomobject]@{ repo=$RepoRoot; network_backed=$true; mode='direct_existing_mapping'; provider=$provider; host=$server }
}

function Get-WaddleLocalElectronRuntime {
  param(
    [Parameter(Mandatory)][string]$SourceElectron,
    [Parameter(Mandatory)][string]$ElectronVersion,
    [Parameter(Mandatory)][string]$DependencyFingerprint,
    [Parameter(Mandatory)][bool]$NetworkBacked
  )

  $sourceExe = [IO.Path]::GetFullPath($SourceElectron)
  if (-not $NetworkBacked) {
    return [pscustomobject]@{ executable=$sourceExe; mode='repo_direct'; copied=$false; cache_root=''; identity='' }
  }

  $sourceDist = Split-Path -Parent $sourceExe
  foreach ($relative in @('electron.exe','icudtl.dat','resources.pak')) {
    $required = Join-Path $sourceDist $relative
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "WADDLE_ELECTRON_CACHE=FAIL source_missing=$required"
    }
  }

  $sourceInfo = Get-Item -LiteralPath $sourceExe -Force
  $identity = Get-WaddleStableToken -Value ("$ElectronVersion|$DependencyFingerprint|$($sourceInfo.Length)|$($sourceInfo.LastWriteTimeUtc.Ticks)") -Length 32
  $localBase = [string]$env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($localBase)) { $localBase = [IO.Path]::GetTempPath() }
  $versionRoot = Join-Path $localBase ("WaddleForever\electron-cache\$ElectronVersion")
  $target = Join-Path $versionRoot $identity
  $runtimeExe = Join-Path $target 'electron.exe'
  $marker = Join-Path $target 'cache.json'
  New-Item -ItemType Directory -Force -Path $versionRoot | Out-Null

  $valid = $false
  if ((Test-Path -LiteralPath $marker -PathType Leaf) -and (Test-Path -LiteralPath $runtimeExe -PathType Leaf)) {
    try {
      $state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json -ErrorAction Stop
      $runtimeInfo = Get-Item -LiteralPath $runtimeExe -Force
      $valid = ([string]$state.identity -eq $identity) -and
        ([string]$state.electron_version -eq $ElectronVersion) -and
        ([string]$state.dependency_fingerprint -eq $DependencyFingerprint) -and
        ([int64]$runtimeInfo.Length -eq [int64]$sourceInfo.Length)
      if ($valid) {
        foreach ($relative in @('icudtl.dat','resources.pak')) {
          if (-not (Test-Path -LiteralPath (Join-Path $target $relative) -PathType Leaf)) { $valid = $false; break }
        }
      }
    } catch { $valid = $false }
  }

  if ($valid) {
    try { Unblock-File -LiteralPath $runtimeExe -ErrorAction Stop } catch {}
    Write-Host "WADDLE_ELECTRON_CACHE=PASS mode=reused source=$sourceExe runtime=$runtimeExe identity=$identity node_modules_copied=0"
    return [pscustomobject]@{ executable=$runtimeExe; mode='local_cache_reused'; copied=$false; cache_root=$target; identity=$identity }
  }

  if (Test-Path -LiteralPath $target) {
    try { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop }
    catch { throw "WADDLE_ELECTRON_CACHE=FAIL stale_cache_locked=$target error=$($_.Exception.Message)" }
  }

  $staging = Join-Path $versionRoot ('.staging-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $staging | Out-Null
  try {
    $robocopy = Get-Command robocopy.exe -ErrorAction Stop
    & $robocopy.Source $sourceDist $staging /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $copyExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($copyExit -ge 8) { throw "WADDLE_ELECTRON_CACHE=FAIL copy_exit=$copyExit source=$sourceDist staging=$staging" }

    $stagedExe = Join-Path $staging 'electron.exe'
    foreach ($relative in @('electron.exe','icudtl.dat','resources.pak')) {
      $required = Join-Path $staging $relative
      if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "WADDLE_ELECTRON_CACHE=FAIL staged_missing=$required" }
    }
    if ((Get-Item -LiteralPath $stagedExe -Force).Length -ne $sourceInfo.Length) {
      throw "WADDLE_ELECTRON_CACHE=FAIL staged_size_mismatch source=$($sourceInfo.Length) staged=$((Get-Item -LiteralPath $stagedExe -Force).Length)"
    }

    [ordered]@{
      schema='waddle-electron-cache/v1'
      status='PASS'
      identity=$identity
      electron_version=$ElectronVersion
      dependency_fingerprint=$DependencyFingerprint
      source_executable=$sourceExe
      source_length=[int64]$sourceInfo.Length
      source_last_write_ticks=[int64]$sourceInfo.LastWriteTimeUtc.Ticks
      created_utc=[DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $staging 'cache.json') -Encoding UTF8

    Move-Item -LiteralPath $staging -Destination $target -Force
  } finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
  }

  if (-not (Test-Path -LiteralPath $runtimeExe -PathType Leaf)) { throw "WADDLE_ELECTRON_CACHE=FAIL runtime_missing=$runtimeExe" }
  try { Unblock-File -LiteralPath $runtimeExe -ErrorAction Stop } catch {}
  Write-Host "WADDLE_ELECTRON_CACHE=PASS mode=created source=$sourceExe runtime=$runtimeExe identity=$identity node_modules_copied=0"
  return [pscustomobject]@{ executable=$runtimeExe; mode='local_cache_created'; copied=$true; cache_root=$target; identity=$identity }
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

$launchRoot = Resolve-WaddleLaunchRoot -RepoRoot $repo
$launchRepo = [string]$launchRoot.repo
$statePath = if ($launchRoot.network_backed) { Join-Path $clientStateDir "$safeMachine.json" } else { $legacyStatePath }
Stop-WaddlePriorState -Path $statePath

$sourceLaunchElectron = Join-Path $launchRepo 'node_modules\electron\dist\electron.exe'
$launchEntry = Join-Path $launchRepo 'compiled\client\main.js'
$launchFlash = Join-Path $launchRepo 'assets\flash\pepflashplayer64_32_0_0_303.dll'
$launchModules = Join-Path $launchRepo 'node_modules'
foreach ($required in @($sourceLaunchElectron,$launchEntry,$launchFlash,$launchModules)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "WADDLE_PLAY=FAIL launch_path_missing=$required mode=$($launchRoot.mode)" }
}

$sha = Get-WaddleCurrentSha
$fingerprint = Get-WaddleDependencyFingerprint
if ([string]::IsNullOrWhiteSpace($fingerprint)) { throw 'WADDLE_PLAY=FAIL dependency_fingerprint_missing' }
$electronRuntime = Get-WaddleLocalElectronRuntime -SourceElectron $sourceLaunchElectron -ElectronVersion '10.4.7' -DependencyFingerprint $fingerprint -NetworkBacked ([bool]$launchRoot.network_backed)
$launchElectron = [string]$electronRuntime.executable

$portableUserData = Join-Path $repo 'user-data'
if ($launchRoot.network_backed) {
  $localBase = [string]$env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($localBase)) { $localBase = [IO.Path]::GetTempPath() }
  $profileToken = Get-WaddleStableToken -Value (([string]$launchRoot.provider) + '|' + $repo) -Length 24
  $profileRoot = Join-Path $localBase ("WaddleForever\runtime-profiles\$profileToken")
  $profileMode = 'local_per_machine_smb'
} else {
  $profileRoot = Join-Path $work ("runtime-profiles\$safeMachine")
  $profileMode = 'repo_work_local_drive'
}
$chromiumProfile = Join-Path $profileRoot 'chromium'
New-Item -ItemType Directory -Force -Path $portableUserData,$chromiumProfile | Out-Null
Write-Host "WADDLE_CHROMIUM_PROFILE=PASS mode=$profileMode path=$chromiumProfile network_backed=$($launchRoot.network_backed)"

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $runtimeLogs "client-$safeMachine-$stamp.stdout.log"
$stderr = Join-Path $runtimeLogs "client-$safeMachine-$stamp.stderr.log"
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

$launchWatch = [Diagnostics.Stopwatch]::StartNew()
$process = $null
try {
  $processId = Start-WaddleWin32DetachedProcess -FilePath $launchElectron -ArgumentList @("--user-data-dir=$chromiumProfile",$launchEntry) -WorkingDirectory $repo
  $process = Get-Process -Id $processId -ErrorAction Stop
} catch {
  throw "WADDLE_PLAY=FAIL process_start executable=$launchElectron source=$sourceLaunchElectron mode=$($launchRoot.mode) shell_execute=false inherit_handles=false error=$($_.Exception.Message)"
}
if (-not $process -or $process.Id -le 0) { throw 'WADDLE_PLAY=FAIL process_id_missing' }

$state = [ordered]@{
  schema='waddle-client-state/v12'; status='STARTING'; platform='windows-x64'; machine=$machine; pid=$process.Id; source_sha=$sha
  repo_root=$repo; work_root=$work; state_path=$statePath; dependency_build_root=$modulesCanonical; dependency_fingerprint=$fingerprint
  dependency_mode='reused'; dependency_mutation_while_running=$false; stdio_mode='win32_detached_no_inherited_handles'
  managed_node_home='NOT_REQUIRED_FOR_PLAY'; managed_node_exe='NOT_REQUIRED_FOR_PLAY'; runtime_mode='repo_local_direct'
  runtime_home=$repo; runtime_root=$repo; runtime_current_root=$repo; runtime_manifest=(Join-Path $stateDir 'runtime-snapshot.json')
  runtime_app_entry=$entryCanonical; runtime_node_modules=$modulesCanonical; electron_source_executable=$sourceLaunchElectron
  electron_executable=$launchElectron; electron_launch_executable=$launchElectron; electron_version='10.4.7'
  electron_launch_mode=[string]$electronRuntime.mode; electron_cache_root=[string]$electronRuntime.cache_root; electron_cache_identity=[string]$electronRuntime.identity; electron_cache_copied=[bool]$electronRuntime.copied
  electron_network_backed=[bool]$launchRoot.network_backed; launcher_return_ms=0
  smb_launch_mode=[string]$launchRoot.mode; smb_provider=[string]$launchRoot.provider; ppapi_flash_source_path=$flashCanonical
  ppapi_flash_path=$flashCanonical; ppapi_flash_version='32.0.0.303'; ffdec_path='NOT_REQUIRED_FOR_PLAY'
  portable_user_data=$portableUserData; chromium_profile=$chromiumProfile; chromium_profile_mode=$profileMode; stdout=$stdout; stderr=$stderr; started_utc=[DateTime]::UtcNow.ToString('o')
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
      Write-Host "WADDLE_PLAY=PASS pid=$($process.Id) machine=$machine electron=10.4.7 event=main-window-ready url=$url launch_ms=$($launchWatch.ElapsedMilliseconds) runtime=$repo node_modules=$modulesCanonical electron_source=$sourceLaunchElectron electron_runtime=$launchElectron electron_cache=$($electronRuntime.mode) flash=$flashCanonical network_backed=$($launchRoot.network_backed) smb_mode=$($launchRoot.mode) profile_mode=$profileMode state=$statePath shell_execute=false inherit_handles=false node_modules_copied=0 local_install=0"
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
