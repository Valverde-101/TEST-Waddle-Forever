param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [int]$RequiredThroughYear = 2017,
  [string[]]$RequiredDates = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Reason) {
  throw "WADDLE_MODERN_TIMELINE=FAIL $Reason"
}

function Test-TimelineFiles([string]$Timeline,[string]$Html,[string]$Scope) {
  if ($Timeline -match 'new Date\(2013\s*,\s*0\s*,\s*1\)') { Fail "$Scope fixed_2013_calendar_cutoff" }
  foreach ($marker in @(
    'Array.from(yearElement.options)',
    'const payloadYears = days',
    'const lastSelectableYear = Math.max',
    'new Date(lastSelectableYear, 11, 31)',
    'yearElement.dataset.timelineYears'
  )) {
    if (-not $Timeline.Contains($marker)) { Fail "$Scope missing_marker=$marker" }
  }

  $years = @([regex]::Matches($Html, '<option(?:\s+value="\d{4}")?>(20\d{2})</option>') | ForEach-Object { [int]$_.Groups[1].Value })
  if ($years.Count -eq 0) { Fail "$Scope no_year_options" }
  $minYear = ($years | Measure-Object -Minimum).Minimum
  $maxYear = ($years | Measure-Object -Maximum).Maximum
  if ($maxYear -lt $RequiredThroughYear) { Fail "$Scope picker_horizon=$maxYear required=$RequiredThroughYear" }
  foreach ($year in ($minYear..$RequiredThroughYear)) {
    if ($years -notcontains $year) { Fail "$Scope picker_gap=$year" }
  }
  return [pscustomobject]@{ min=$minYear; max=$maxYear }
}

$timelinePath = Join-Path $RepoRoot 'src/client/views/timeline/timeline-static.ts'
$htmlPath = Join-Path $RepoRoot 'src/client/views/timeline/timeline.html'
$timelineBackendPath = Join-Path $RepoRoot 'src/client/views/timeline/timeline.ts'
$updatesRoot = Join-Path $RepoRoot 'src/server/updates'
$updatesIndexPath = Join-Path $updatesRoot 'updates.ts'
foreach ($required in @($timelinePath,$htmlPath,$timelineBackendPath,$updatesRoot,$updatesIndexPath)) {
  if (-not (Test-Path -LiteralPath $required)) { Fail "missing=$required" }
}

$timeline = [IO.File]::ReadAllText($timelinePath)
$html = [IO.File]::ReadAllText($htmlPath)
$backend = [IO.File]::ReadAllText($timelineBackendPath)
$sourceRange = Test-TimelineFiles -Timeline $timeline -Html $html -Scope 'source'

if (-not $backend.Contains("addEvent(map, update.date, 'A new client version is available', 'other');")) {
  Fail 'source client_transition_event_missing'
}
if (-not $backend.Contains('partyName')) { Fail 'source party_timeline_generation_missing' }

$updatesIndex = [IO.File]::ReadAllText($updatesIndexPath)
foreach ($needle in @('UPDATES_2013','UPDATES_2014','UPDATES_2015','UPDATES_2016')) {
  if (-not $updatesIndex.Contains($needle)) { Fail "updates_registry_missing=$needle" }
}

$updateText = (Get-ChildItem -LiteralPath $updatesRoot -Filter '*.ts' -File | ForEach-Object {
  [IO.File]::ReadAllText($_.FullName)
}) -join "`n"
foreach ($date in $RequiredDates) {
  if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { Fail "invalid_required_date=$date" }
  if ($updateText -notmatch [regex]::Escape("date: '$date'")) { Fail "missing_required_date=$date" }
}
if ($updateText -notmatch [regex]::Escape("partyName: 'Halloween Party 2015'")) { Fail 'halloween_party_name_missing' }

$legacyAs3Footer = $timeline -match "updateVersion\('2016-01-01'\)"
if ($legacyAs3Footer) { Fail 'legacy_as3_footer_present' }

$compiledHtml = Join-Path $RepoRoot 'compiled\client\views\timeline\timeline.html'
$compiledJs = Join-Path $RepoRoot 'compiled\client\views\timeline\timeline-static.js'
$compiledChecked = $false
if ((Test-Path -LiteralPath (Join-Path $RepoRoot 'compiled') -PathType Container) -and
    ((Test-Path -LiteralPath $compiledHtml -PathType Leaf) -or (Test-Path -LiteralPath $compiledJs -PathType Leaf))) {
  if (-not (Test-Path -LiteralPath $compiledHtml -PathType Leaf)) { Fail "compiled missing=$compiledHtml" }
  if (-not (Test-Path -LiteralPath $compiledJs -PathType Leaf)) { Fail "compiled missing=$compiledJs" }
  $compiledHtmlText = [IO.File]::ReadAllText($compiledHtml)
  $compiledJsText = [IO.File]::ReadAllText($compiledJs)
  $compiledRange = Test-TimelineFiles -Timeline $compiledJsText -Html $compiledHtmlText -Scope 'compiled'
  if ($compiledRange.max -lt $RequiredThroughYear) { Fail "compiled picker_horizon=$($compiledRange.max)" }
  $compiledChecked = $true
}

Write-Host "WADDLE_MODERN_TIMELINE=PASS picker_min=$($sourceRange.min) picker_max=$($sourceRange.max) required_through=$RequiredThroughYear required_dates=$($RequiredDates.Count) payload_cannot_shrink=true selectable_horizon=true compiled_checked=$($compiledChecked.ToString().ToLowerInvariant()) legacy_as3_footer=false"
