[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$launcher = Join-Path $PSScriptRoot 'waddle-launcher.ps1'
$summaryPath = Join-Path $repo '.work\state\waddle-build-summary.json'
$clientStatePath = Join-Path $repo '.work\state\waddle-client.json'
$compiledEntry = Join-Path $repo 'compiled\client\main.js'
$compiledServer = Join-Path $repo 'compiled\server\file-server\index.js'
$reuse = $false
$reason = 'build_state_missing'
$currentSha = ''
$currentFingerprint = ''

function Get-WaddleSmartStartFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($name in @('package.json','yarn.lock')) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $parts.Add((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant())
  }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join '|'))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Get-WaddleRuntimeEvents {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][int]$ProcessId
  )

  $events = @()
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

  foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
    $text = [string]$line
    if ([string]::IsNullOrWhiteSpace($text) -or -not $text.TrimStart().StartsWith('{')) { continue }
    try {
      $item = $text | ConvertFrom-Json -ErrorAction Stop
      $pidProperty = $item.PSObject.Properties['pid']
      $eventProperty = $item.PSObject.Properties['event']
      if (-not $pidProperty -or -not $eventProperty) { continue }
      if ([int]$pidProperty.Value -ne $ProcessId) { continue }
      $events += $item
    } catch {}
  }
  return $events
}

function Get-WaddleRuntimeFailure {
  param($Events)

  foreach ($event in @($Events)) {
    $name = [string]$event.event
    if ($name -eq 'uncaught-exception' -or $name -eq 'unhandled-rejection' -or $name -eq 'render-process-gone' -or $name -eq 'window-unresponsive') {
      return $event
    }
    if ($name -eq 'window-did-fail-load') {
      $mainFrame = $event.PSObject.Properties['isMainFrame']
      if (-not $mainFrame -or [bool]$mainFrame.Value) { return $event }
    }
  }
  return $null
}

function Stop-WaddleRuntimeAfterHealthFailure {
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action stop | Out-Host
    $global:LASTEXITCODE = 0
  } catch {}
}

function Assert-WaddleRuntimeHealthy {
  param([Parameter(Mandatory)][string]$ExpectedSha)

  $stateDeadline = [DateTime]::UtcNow.AddSeconds(10)
  $state = $null
  do {
    if (Test-Path -LiteralPath $clientStatePath -PathType Leaf) {
      try {
        $candidate = Get-Content -LiteralPath $clientStatePath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ([string]$candidate.status -eq 'RUNNING' -and [int]$candidate.pid -gt 0) {
          $state = $candidate
          break
        }
      } catch {}
    }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $stateDeadline)

  if (-not $state) {
    Stop-WaddleRuntimeAfterHealthFailure
    throw "WADDLE_RUNTIME_HEALTH=FAIL reason=running_state_missing path=$clientStatePath"
  }

  $clientPid = [int]$state.pid
  $stateSha = ([string]$state.source_sha).Trim().ToLowerInvariant()
  $expected = ([string]$ExpectedSha).Trim().ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($stateSha) -or $stateSha -ne $expected) {
    Stop-WaddleRuntimeAfterHealthFailure
    throw "WADDLE_RUNTIME_HEALTH=FAIL reason=state_sha_mismatch expected=$expected actual=$stateSha pid=$clientPid"
  }

  $stderr = [string]$state.stderr
  if ([string]::IsNullOrWhiteSpace($stderr)) {
    Stop-WaddleRuntimeAfterHealthFailure
    throw "WADDLE_RUNTIME_HEALTH=FAIL reason=diagnostic_path_missing pid=$clientPid"
  }

  $deadline = [DateTime]::UtcNow.AddSeconds(45)
  $lastEvent = 'none'
  do {
    $process = Get-Process -Id $clientPid -ErrorAction SilentlyContinue
    if (-not $process) {
      $tail = if (Test-Path -LiteralPath $stderr -PathType Leaf) { (@(Get-Content -LiteralPath $stderr -Tail 8 -ErrorAction SilentlyContinue) -join ' | ') } else { 'diagnostic_file_missing' }
      Stop-WaddleRuntimeAfterHealthFailure
      throw "WADDLE_RUNTIME_HEALTH=FAIL reason=process_exited_before_ready pid=$clientPid last_event=$lastEvent diagnostic=$stderr tail=$tail"
    }

    $events = @(Get-WaddleRuntimeEvents -Path $stderr -ProcessId $clientPid)
    if ($events.Count -gt 0) {
      $lastEvent = [string]$events[$events.Count - 1].event
    }

    $failure = Get-WaddleRuntimeFailure -Events $events
    if ($failure) {
      $failureJson = $failure | ConvertTo-Json -Compress -Depth 8
      Stop-WaddleRuntimeAfterHealthFailure
      throw "WADDLE_RUNTIME_HEALTH=FAIL reason=runtime_event pid=$clientPid diagnostic=$stderr event=$failureJson"
    }

    $ready = @($events | Where-Object { [string]$_.event -eq 'main-window-ready' } | Select-Object -Last 1)
    if ($ready.Count -gt 0) {
      Start-Sleep -Seconds 2
      $process = Get-Process -Id $clientPid -ErrorAction SilentlyContinue
      if (-not $process) {
        Stop-WaddleRuntimeAfterHealthFailure
        throw "WADDLE_RUNTIME_HEALTH=FAIL reason=process_exited_after_ready pid=$clientPid diagnostic=$stderr"
      }

      $events = @(Get-WaddleRuntimeEvents -Path $stderr -ProcessId $clientPid)
      $failure = Get-WaddleRuntimeFailure -Events $events
      if ($failure) {
        $failureJson = $failure | ConvertTo-Json -Compress -Depth 8
        Stop-WaddleRuntimeAfterHealthFailure
        throw "WADDLE_RUNTIME_HEALTH=FAIL reason=runtime_event_after_ready pid=$clientPid diagnostic=$stderr event=$failureJson"
      }

      $readyEvent = @($events | Where-Object { [string]$_.event -eq 'main-window-ready' } | Select-Object -Last 1)[0]
      $urlProperty = $readyEvent.PSObject.Properties['url']
      $url = if ($urlProperty) { [string]$urlProperty.Value } else { '' }
      if ([string]::IsNullOrWhiteSpace($url) -or $url -notmatch '^https?://') {
        Stop-WaddleRuntimeAfterHealthFailure
        throw "WADDLE_RUNTIME_HEALTH=FAIL reason=main_window_url_invalid pid=$clientPid url=$url diagnostic=$stderr"
      }

      Write-Host "WADDLE_RUNTIME_HEALTH=PASS pid=$clientPid sha=$expected event=main-window-ready url=$url diagnostic=$stderr"
      return
    }

    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)

  $tail = if (Test-Path -LiteralPath $stderr -PathType Leaf) { (@(Get-Content -LiteralPath $stderr -Tail 12 -ErrorAction SilentlyContinue) -join ' | ') } else { 'diagnostic_file_missing' }
  Stop-WaddleRuntimeAfterHealthFailure
  throw "WADDLE_RUNTIME_HEALTH=FAIL reason=main_window_ready_timeout pid=$clientPid last_event=$lastEvent diagnostic=$stderr tail=$tail"
}

try {
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) {
    $safe = $repo.Replace('"','\"')
    $head = & $git.Source -c "safe.directory=$safe" -C $repo rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $head) { $currentSha = ([string]$head).Trim().ToLowerInvariant() }
    $global:LASTEXITCODE = 0
  }

  $currentFingerprint = Get-WaddleSmartStartFingerprint -RepoRoot $repo
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    $reason = 'build_summary_missing'
  } elseif (-not (Test-Path -LiteralPath $compiledEntry -PathType Leaf) -or -not (Test-Path -LiteralPath $compiledServer -PathType Leaf)) {
    $reason = 'compiled_output_missing'
  } elseif ([string]::IsNullOrWhiteSpace($currentSha)) {
    $reason = 'git_head_unresolved'
  } elseif ([string]::IsNullOrWhiteSpace($currentFingerprint)) {
    $reason = 'dependency_fingerprint_unresolved'
  } else {
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    $summarySha = ([string]$summary.source_sha).Trim().ToLowerInvariant()
    $summaryFingerprint = ([string]$summary.dependency_fingerprint).Trim().ToUpperInvariant()
    if ([string]$summary.status -ne 'PASS') {
      $reason = 'previous_build_not_pass'
    } elseif ($summarySha -ne $currentSha) {
      $reason = "source_sha_changed:$summarySha->$currentSha"
    } elseif ($summaryFingerprint -ne $currentFingerprint) {
      $reason = 'dependency_fingerprint_changed'
    } else {
      $reuse = $true
      $reason = 'same_sha_same_dependencies_compiled_present'
    }
  }
} catch {
  $reuse = $false
  $reason = "freshness_probe_error:$($_.Exception.Message)"
}

if ($reuse) {
  Write-Host "WADDLE_FAST_START=PASS mode=reuse_build sha=$currentSha fingerprint=$currentFingerprint reason=$reason"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action start -SkipBuild
} else {
  Write-Host "WADDLE_FAST_START=INFO mode=full_build sha=$currentSha fingerprint=$currentFingerprint reason=$reason"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action start
}
$exit = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($exit -ne 0) { exit $exit }

try {
  Assert-WaddleRuntimeHealthy -ExpectedSha $currentSha
  exit 0
} catch {
  $failureMessage = [string]$_.Exception.Message
  $failureStack = [string]$_.ScriptStackTrace
  $failureStack = $failureStack -replace '\r?\n',' | '
  Write-Host "WADDLE_RUNTIME_HEALTH_GATE=FAIL error=$failureMessage stack=$failureStack"
  exit 1
}
