[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string]$WorkRoot,
  [string]$RuntimeLog,
  [ValidateRange(100,100000)][int]$MaxRuntimeEvents = 20000,
  [switch]$FailOnCritical
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')) }
else { $RepoRoot = [IO.Path]::GetFullPath($RepoRoot) }
if (-not $WorkRoot) { $WorkRoot = Join-Path $RepoRoot '.work' }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)

$diagnosticRoot = Join-Path $WorkRoot 'diagnostics'
$runId = 'run-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$runRoot = Join-Path $diagnosticRoot $runId
$latestRoot = Join-Path $diagnosticRoot 'latest'
New-Item -ItemType Directory -Force -Path $diagnosticRoot,$runRoot,$latestRoot | Out-Null

function Get-PropertyValue {
  param([object]$Object,[string]$Name,[object]$Default=$null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Read-JsonFile {
  param([string]$Path,[object]$Default=$null)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Default }
  try { return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json }
  catch { return $Default }
}

function Write-JsonFile {
  param([object]$Value,[string]$Path,[int]$Depth=16)
  $json = ConvertTo-Json -InputObject $Value -Depth $Depth
  Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-LatestRuntimeLog {
  if ($RuntimeLog) {
    $candidate = [IO.Path]::GetFullPath($RuntimeLog)
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    throw "WADDLE_DIAGNOSTICS=FAIL runtime_log_missing path=$candidate"
  }
  if ($env:WADDLE_RUNTIME_DIAGNOSTIC_LOG -and (Test-Path -LiteralPath $env:WADDLE_RUNTIME_DIAGNOSTIC_LOG -PathType Leaf)) {
    return [IO.Path]::GetFullPath($env:WADDLE_RUNTIME_DIAGNOSTIC_LOG)
  }
  $runtimeRoot = Join-Path $WorkRoot 'logs\runtime'
  if (Test-Path -LiteralPath $runtimeRoot -PathType Container) {
    $candidate = Get-ChildItem -LiteralPath $runtimeRoot -File -Filter 'client-*.stderr.log' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    $fallback = Join-Path $runtimeRoot 'application-errors.log'
    if (Test-Path -LiteralPath $fallback -PathType Leaf) { return $fallback }
  }
  return $null
}

$runtimeLogPath = Get-LatestRuntimeLog
$events = New-Object System.Collections.Generic.List[object]
if ($runtimeLogPath) {
  foreach ($line in Get-Content -LiteralPath $runtimeLogPath -ErrorAction SilentlyContinue) {
    if ($events.Count -ge $MaxRuntimeEvents) { break }
    $text = ([string]$line).Trim()
    if (-not $text.StartsWith('{')) { continue }
    try { $event = $text | ConvertFrom-Json }
    catch { continue }
    if ([string](Get-PropertyValue -Object $event -Name 'schema' -Default '') -ne 'waddle-runtime-event/v1') { continue }
    $events.Add($event)
  }
}

$issues = New-Object System.Collections.Generic.List[object]
$resourceFailures = New-Object System.Collections.Generic.List[object]
$slowResources = New-Object System.Collections.Generic.List[object]
$liveTraceEvents = New-Object System.Collections.Generic.List[object]
$liveTraceErrors = New-Object System.Collections.Generic.List[object]

function Add-Issue {
  param([ValidateSet('critical','error','warning','info')][string]$Severity,[string]$Code,[string]$Message,[string]$Source,[object]$Evidence=$null)
  $issues.Add([pscustomobject]@{
    severity=$Severity
    code=$Code
    message=$Message
    source=$Source
    evidence=$Evidence
  })
}

$criticalEvents = @('uncaught-exception','flash-runtime-missing','services-start-failed','runtime-lease-acquire-failed')
$warningEvents = @('window-unresponsive','mods-failed','runtime-lease-heartbeat-failed','renderer-console-warning')
$criticalRendererReasons = @('abnormal-exit','crashed','oom','launch-failed','integrity-failure')
$actionTraceErrorStatuses = @('unhandled-action','unhandled-context','invalid-signature','send-failed','handler-threw')

foreach ($event in $events) {
  $name = [string](Get-PropertyValue -Object $event -Name 'event' -Default '')
  if ($criticalEvents -contains $name) {
    Add-Issue -Severity critical -Code $name -Message "Critical runtime event: $name" -Source 'runtime' -Evidence $event
  } elseif ($warningEvents -contains $name) {
    Add-Issue -Severity warning -Code $name -Message "Runtime warning event: $name" -Source 'runtime' -Evidence $event
  }

  if ($name -eq 'renderer-console-error') {
    $rendererMessage = [string](Get-PropertyValue -Object $event -Name 'message' -Default '')
    if ($rendererMessage -match 'Electron Security Warning') {
      # Electron 10 emits these at console error level even for the intentional
      # localhost/offline Flash runtime. Keep them visible without letting them
      # drown out actual renderer/game errors.
      Add-Issue -Severity info -Code 'electron-security-warning' -Message 'Electron emitted a security advisory for the legacy/offline renderer.' -Source 'runtime-security' -Evidence $event
    } else {
      Add-Issue -Severity error -Code 'renderer-console-error' -Message 'Renderer console emitted an error.' -Source 'runtime' -Evidence $event
    }
  }

  if ($name -eq 'live-trace') {
    $trace = Get-PropertyValue -Object $event -Name 'trace'
    if ($null -ne $trace -and [string](Get-PropertyValue -Object $trace -Name 'schema' -Default '') -eq 'waddle-live-trace/v1') {
      $liveTraceEvents.Add($trace)
      $phase = [string](Get-PropertyValue -Object $trace -Name 'phase' -Default '')
      $category = [string](Get-PropertyValue -Object $trace -Name 'category' -Default '')
      $traceStatus = [string](Get-PropertyValue -Object $trace -Name 'status' -Default '')
      if ($phase -eq 'error') {
        $liveTraceErrors.Add($trace)
        if (($category -eq 'XT' -or $category -eq 'XML') -and $actionTraceErrorStatuses -contains $traceStatus) {
          Add-Issue -Severity error -Code ('live-action-' + $traceStatus) -Message "Live $category action trace failed: $traceStatus" -Source 'live-trace' -Evidence $trace
        }
      }
    }
  }

  if ($name -eq 'render-process-gone') {
    $reason = [string](Get-PropertyValue -Object $event -Name 'reason' -Default '')
    if ($criticalRendererReasons -contains $reason) {
      Add-Issue -Severity critical -Code 'render-process-gone' -Message "Renderer terminated abnormally: $reason" -Source 'runtime' -Evidence $event
    } elseif ($reason -and $reason -ne 'clean-exit') {
      Add-Issue -Severity warning -Code 'render-process-gone-nonfatal' -Message "Renderer terminated with non-clean reason: $reason" -Source 'runtime' -Evidence $event
    }
  }

  if ($name -eq 'window-did-fail-load') {
    $errorCode = [int](Get-PropertyValue -Object $event -Name 'errorCode' -Default 0)
    $description = [string](Get-PropertyValue -Object $event -Name 'errorDescription' -Default '')
    if ($errorCode -eq -3 -or $description -match 'ERR_ABORTED') {
      Add-Issue -Severity info -Code 'window-load-aborted' -Message 'A navigation was intentionally/benignly aborted during reload or redirect.' -Source 'runtime' -Evidence $event
    } else {
      Add-Issue -Severity error -Code 'window-did-fail-load' -Message "Window load failed: $description ($errorCode)" -Source 'runtime' -Evidence $event
    }
  }

  if ($name -eq 'resource-load-failed') {
    $resourceError = [string](Get-PropertyValue -Object $event -Name 'error' -Default '')
    if ($resourceError -match 'ERR_ABORTED') {
      Add-Issue -Severity info -Code 'resource-load-aborted' -Message 'A resource request was aborted during navigation/reload.' -Source 'runtime-network' -Evidence $event
    } else {
      $resourceFailures.Add($event)
      Add-Issue -Severity error -Code 'resource-load-failed' -Message "Resource load failed: $resourceError" -Source 'runtime-network' -Evidence $event
    }
  } elseif ($name -eq 'resource-response') {
    $statusCode = [int](Get-PropertyValue -Object $event -Name 'statusCode' -Default 0)
    # 304 is a successful cache validation. Only actual HTTP failures belong in
    # resource-failures; 4xx/5xx stay actionable.
    if ($statusCode -ge 400) {
      $resourceFailures.Add($event)
      Add-Issue -Severity error -Code 'resource-http-error' -Message "Resource returned HTTP $statusCode" -Source 'runtime-network' -Evidence $event
    }
  } elseif ($name -eq 'resource-slow') {
    $slowResources.Add($event)
  }
}

# Do not use @($genericList) on Windows PowerShell 5.1. Its dynamic binder can
# throw System.ArgumentException ("Argument types do not match") for
# System.Collections.Generic.List[T]. ToArray() is deterministic on both 5.1
# and newer PowerShell versions and preserves an explicit JSON [] when empty.
$eventArray = $events.ToArray()
$resourceFailureArray = $resourceFailures.ToArray()
$slowResourceArray = $slowResources.ToArray()
$liveTraceArray = $liveTraceEvents.ToArray()
$liveTraceErrorArray = $liveTraceErrors.ToArray()

$bootCount = @($eventArray | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'main-process-boot' }).Count
$readyCount = @($eventArray | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'main-window-ready' }).Count
$flashReadyCount = @($eventArray | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'flash-runtime-ready' }).Count
$liveTraceConsoleReadyCount = @($eventArray | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'live-trace-console-ready' }).Count
$liveTraceCategories = @($liveTraceArray | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'category' -Default '') } | Where-Object { $_ } | Sort-Object -Unique)

if ($bootCount -gt 0 -and $readyCount -eq 0) {
  Add-Issue -Severity critical -Code 'main-window-never-ready' -Message 'Runtime booted but no main-window-ready event was observed.' -Source 'runtime'
}
if ($readyCount -gt 0 -and $flashReadyCount -eq 0) {
  Add-Issue -Severity error -Code 'flash-ready-event-missing' -Message 'Main window became ready without a flash-runtime-ready event in the selected runtime log.' -Source 'runtime'
}
if ($readyCount -gt 0 -and $liveTraceConsoleReadyCount -eq 0) {
  Add-Issue -Severity critical -Code 'live-trace-console-missing' -Message 'Main window became ready but the WADDLE-LIVE DevTools console bridge was not installed.' -Source 'live-trace'
}
if ($readyCount -gt 0 -and $liveTraceArray.Count -eq 0) {
  Add-Issue -Severity critical -Code 'live-trace-empty' -Message 'Main window became ready but no waddle-live-trace/v1 events were captured.' -Source 'live-trace'
}
if (-not $runtimeLogPath) {
  Add-Issue -Severity warning -Code 'runtime-log-missing' -Message 'No runtime diagnostic log is available yet.' -Source 'runtime'
}

$swfRoot = Join-Path $WorkRoot 'swf-analysis'
$swfSummary = Read-JsonFile -Path (Join-Path $swfRoot 'summary.json')
$missingSwfs = @(Read-JsonFile -Path (Join-Path $swfRoot 'missing-swfs.json') -Default @())
$runtimeTrace = Read-JsonFile -Path (Join-Path $swfRoot 'runtime-trace.json')

if ($null -eq $swfSummary) {
  Add-Issue -Severity warning -Code 'swf-analysis-missing' -Message 'No SWF analysis summary is available yet. Run Waddle-Setup.cmd or the SWF analyzer first.' -Source 'swf-analysis'
} else {
  $unresolved = [int](Get-PropertyValue -Object $swfSummary -Name 'unresolved_literal_refs' -Default 0)
  $pending = [int](Get-PropertyValue -Object $swfSummary -Name 'pending_unique_hash_count' -Default 0)
  if ($unresolved -gt 0) {
    Add-Issue -Severity warning -Code 'swf-unresolved-references' -Message "$unresolved literal SWF references are unresolved and need correlation with runtime requests." -Source 'swf-analysis' -Evidence $missingSwfs
  }
  if ($pending -gt 0) {
    Add-Issue -Severity info -Code 'swf-deep-analysis-pending' -Message "$pending unique SWF hashes are still pending deep FFDec analysis." -Source 'swf-analysis'
  }
}

$networkFailuresByLeaf = @{}
foreach ($failure in $resourceFailureArray) {
  $url = [string](Get-PropertyValue -Object $failure -Name 'url' -Default '')
  if (-not $url) { continue }
  try { $leaf = [IO.Path]::GetFileName(([Uri]$url).AbsolutePath).ToLowerInvariant() }
  catch { $leaf = [IO.Path]::GetFileName(($url.Split('?')[0])).ToLowerInvariant() }
  if ($leaf) { $networkFailuresByLeaf[$leaf] = $failure }
}
foreach ($missing in $missingSwfs) {
  $leaf = [string](Get-PropertyValue -Object $missing -Name 'leaf' -Default '')
  if ($leaf -and $networkFailuresByLeaf.ContainsKey($leaf.ToLowerInvariant())) {
    Add-Issue -Severity critical -Code 'swf-static-runtime-correlation' -Message "A statically unresolved SWF reference also failed at runtime: $leaf" -Source 'correlation' -Evidence ([pscustomobject]@{ static=$missing; runtime=$networkFailuresByLeaf[$leaf.ToLowerInvariant()] })
  }
}

# Refresh after all correlation/gate issues have been added.
$issueArray = $issues.ToArray()
$severityCounts = [ordered]@{ critical=0; error=0; warning=0; info=0 }
foreach ($issue in $issueArray) {
  $severity = [string]$issue.severity
  $severityCounts[$severity] = [int]$severityCounts[$severity] + 1
}

$gitSha = ''
try {
  $gitSha = (& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
} catch {}

$status = 'PASS'
if ([int]$severityCounts.critical -gt 0) { $status = 'FAIL' }
elseif ([int]$severityCounts.error -gt 0 -or [int]$severityCounts.warning -gt 0) { $status = 'WARN' }

$summary = [ordered]@{
  schema='waddle-diagnostics/v2'
  status=$status
  repository_root=$RepoRoot
  git_sha=$gitSha
  runtime_log=$runtimeLogPath
  runtime_event_count=$eventArray.Count
  runtime_boot_count=$bootCount
  main_window_ready_count=$readyCount
  flash_runtime_ready_count=$flashReadyCount
  live_trace_console_ready_count=$liveTraceConsoleReadyCount
  live_trace_event_count=$liveTraceArray.Count
  live_trace_error_count=$liveTraceErrorArray.Count
  live_trace_categories=$liveTraceCategories
  resource_failure_count=$resourceFailureArray.Count
  slow_resource_count=$slowResourceArray.Count
  severity=$severityCounts
  swf_analysis_available=($null -ne $swfSummary)
  swf_runtime_trace_available=$(if ($null -eq $runtimeTrace) { $false } else { [bool](Get-PropertyValue -Object $runtimeTrace -Name 'available' -Default $false) })
  swf_unresolved_count=$missingSwfs.Count
  generated_utc=[DateTime]::UtcNow.ToString('o')
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("Waddle diagnostics: $status")
$report.Add("SHA: $gitSha")
$report.Add("Runtime log: $runtimeLogPath")
$report.Add("Runtime events: $($eventArray.Count); main ready: $readyCount; flash ready: $flashReadyCount")
$report.Add("Live trace: console ready=$liveTraceConsoleReadyCount events=$($liveTraceArray.Count) errors=$($liveTraceErrorArray.Count) categories=$($liveTraceCategories -join ',')")
$report.Add("Resource failures: $($resourceFailureArray.Count); slow resources: $($slowResourceArray.Count); unresolved SWF refs: $($missingSwfs.Count)")
$report.Add("Issues: critical=$($severityCounts.critical) error=$($severityCounts.error) warning=$($severityCounts.warning) info=$($severityCounts.info)")
$report.Add('')
foreach ($issue in ($issueArray | Sort-Object @{Expression={ switch ($_.severity) { 'critical' {0} 'error' {1} 'warning' {2} default {3} } }},code)) {
  $report.Add("[$([string]$issue.severity).ToUpperInvariant()] $($issue.code) - $($issue.message)")
}

Write-JsonFile -Value $summary -Path (Join-Path $runRoot 'summary.json') -Depth 12
Write-JsonFile -Value $issueArray -Path (Join-Path $runRoot 'issues.json') -Depth 20
Write-JsonFile -Value $eventArray -Path (Join-Path $runRoot 'runtime-events.json') -Depth 20
Write-JsonFile -Value $liveTraceArray -Path (Join-Path $runRoot 'live-trace.json') -Depth 20
Write-JsonFile -Value $liveTraceErrorArray -Path (Join-Path $runRoot 'live-trace-errors.json') -Depth 20
Write-JsonFile -Value $resourceFailureArray -Path (Join-Path $runRoot 'resource-failures.json') -Depth 20
Write-JsonFile -Value $slowResourceArray -Path (Join-Path $runRoot 'slow-resources.json') -Depth 20
Write-JsonFile -Value $missingSwfs -Path (Join-Path $runRoot 'swf-unresolved.json') -Depth 20
$report.ToArray() | Set-Content -LiteralPath (Join-Path $runRoot 'report.txt') -Encoding UTF8

foreach ($file in Get-ChildItem -LiteralPath $runRoot -File) {
  Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $latestRoot $file.Name) -Force
}
Get-ChildItem -LiteralPath $diagnosticRoot -Directory -Filter 'run-*' -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending | Select-Object -Skip 3 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "WADDLE_DIAGNOSTICS=$status sha=$gitSha events=$($eventArray.Count) live_trace=$($liveTraceArray.Count) live_console=$liveTraceConsoleReadyCount live_errors=$($liveTraceErrorArray.Count) critical=$($severityCounts.critical) errors=$($severityCounts.error) warnings=$($severityCounts.warning) resource_failures=$($resourceFailureArray.Count) slow_resources=$($slowResourceArray.Count) unresolved_swfs=$($missingSwfs.Count) report=$latestRoot"
if ($FailOnCritical -and [int]$severityCounts.critical -gt 0) { exit 2 }
exit 0
