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
$errorEvents = @('renderer-console-error')
$warningEvents = @('window-unresponsive','mods-failed','runtime-lease-heartbeat-failed','renderer-console-warning')
$criticalRendererReasons = @('abnormal-exit','crashed','oom','launch-failed','integrity-failure')

foreach ($event in $events) {
  $name = [string](Get-PropertyValue -Object $event -Name 'event' -Default '')
  if ($criticalEvents -contains $name) {
    Add-Issue -Severity critical -Code $name -Message "Critical runtime event: $name" -Source 'runtime' -Evidence $event
  } elseif ($errorEvents -contains $name) {
    Add-Issue -Severity error -Code $name -Message "Runtime error event: $name" -Source 'runtime' -Evidence $event
  } elseif ($warningEvents -contains $name) {
    Add-Issue -Severity warning -Code $name -Message "Runtime warning event: $name" -Source 'runtime' -Evidence $event
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
    if ($statusCode -ge 400) {
      $resourceFailures.Add($event)
      Add-Issue -Severity error -Code 'resource-http-error' -Message "Resource returned HTTP $statusCode" -Source 'runtime-network' -Evidence $event
    }
  } elseif ($name -eq 'resource-slow') {
    $slowResources.Add($event)
  }
}

$bootCount = @($events | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'main-process-boot' }).Count
$readyCount = @($events | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'main-window-ready' }).Count
$flashReadyCount = @($events | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'event' -Default '') -eq 'flash-runtime-ready' }).Count
if ($bootCount -gt 0 -and $readyCount -eq 0) {
  Add-Issue -Severity critical -Code 'main-window-never-ready' -Message 'Runtime booted but no main-window-ready event was observed.' -Source 'runtime'
}
if ($readyCount -gt 0 -and $flashReadyCount -eq 0) {
  Add-Issue -Severity error -Code 'flash-ready-event-missing' -Message 'Main window became ready without a flash-runtime-ready event in the selected runtime log.' -Source 'runtime'
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
foreach ($failure in $resourceFailures) {
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

$severityCounts = [ordered]@{ critical=0; error=0; warning=0; info=0 }
foreach ($issue in $issues) {
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
  schema='waddle-diagnostics/v1'
  status=$status
  repository_root=$RepoRoot
  git_sha=$gitSha
  runtime_log=$runtimeLogPath
  runtime_event_count=$events.Count
  runtime_boot_count=$bootCount
  main_window_ready_count=$readyCount
  flash_runtime_ready_count=$flashReadyCount
  resource_failure_count=$resourceFailures.Count
  slow_resource_count=$slowResources.Count
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
$report.Add("Runtime events: $($events.Count); main ready: $readyCount; flash ready: $flashReadyCount")
$report.Add("Resource failures: $($resourceFailures.Count); slow resources: $($slowResources.Count); unresolved SWF refs: $($missingSwfs.Count)")
$report.Add("Issues: critical=$($severityCounts.critical) error=$($severityCounts.error) warning=$($severityCounts.warning) info=$($severityCounts.info)")
$report.Add('')
foreach ($issue in @($issues | Sort-Object @{Expression={ switch ($_.severity) { 'critical' {0} 'error' {1} 'warning' {2} default {3} } }},code)) {
  $report.Add("[$([string]$issue.severity).ToUpperInvariant())] $($issue.code) - $($issue.message)")
}

Write-JsonFile -Value $summary -Path (Join-Path $runRoot 'summary.json') -Depth 12
Write-JsonFile -Value @($issues) -Path (Join-Path $runRoot 'issues.json') -Depth 20
Write-JsonFile -Value @($events) -Path (Join-Path $runRoot 'runtime-events.json') -Depth 20
Write-JsonFile -Value @($resourceFailures) -Path (Join-Path $runRoot 'resource-failures.json') -Depth 20
Write-JsonFile -Value @($slowResources) -Path (Join-Path $runRoot 'slow-resources.json') -Depth 20
Write-JsonFile -Value @($missingSwfs) -Path (Join-Path $runRoot 'swf-unresolved.json') -Depth 20
$report | Set-Content -LiteralPath (Join-Path $runRoot 'report.txt') -Encoding UTF8

foreach ($file in Get-ChildItem -LiteralPath $runRoot -File) {
  Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $latestRoot $file.Name) -Force
}
Get-ChildItem -LiteralPath $diagnosticRoot -Directory -Filter 'run-*' -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending | Select-Object -Skip 3 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "WADDLE_DIAGNOSTICS=$status sha=$gitSha events=$($events.Count) critical=$($severityCounts.critical) errors=$($severityCounts.error) warnings=$($severityCounts.warning) resource_failures=$($resourceFailures.Count) slow_resources=$($slowResources.Count) unresolved_swfs=$($missingSwfs.Count) report=$latestRoot"
if ($FailOnCritical -and [int]$severityCounts.critical -gt 0) { exit 2 }
exit 0
