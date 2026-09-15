param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [int]$RequiredThroughYear = 2016,
  [string[]]$RequiredDates = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail([string]$Reason) {
  throw "WADDLE_MODERN_TIMELINE=FAIL $Reason"
}

$timelinePath = Join-Path $RepoRoot 'src/client/views/timeline/timeline-static.ts'
$htmlPath = Join-Path $RepoRoot 'src/client/views/timeline/timeline.html'
$updatesRoot = Join-Path $RepoRoot 'src/server/updates'

if (-not (Test-Path -LiteralPath $timelinePath -PathType Leaf)) { Fail "missing=$timelinePath" }
if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) { Fail "missing=$htmlPath" }
if (-not (Test-Path -LiteralPath $updatesRoot -PathType Container)) { Fail "missing=$updatesRoot" }

$timeline = [IO.File]::ReadAllText($timelinePath)
$html = [IO.File]::ReadAllText($htmlPath)

# The calendar must derive its end from update data. A fixed historical cutoff is a
# regression for every future party, regardless of which party introduced it.
if ($timeline -match 'new Date\(2013\s*,\s*0\s*,\s*1\)') {
  Fail 'fixed_2013_calendar_cutoff'
}
if ($timeline -notmatch 'days\[days\.length\s*-\s*1\]') {
  Fail 'calendar_end_not_data_driven'
}

# Modern years must be reachable from the normal picker. This deliberately checks a
# minimum horizon rather than a Halloween-specific year list.
$years = @([regex]::Matches($html, '<option>(20\d{2})</option>') | ForEach-Object { [int]$_.Groups[1].Value })
if ($years.Count -eq 0) { Fail 'no_year_options' }
$maxYear = ($years | Measure-Object -Maximum).Maximum
if ($maxYear -lt $RequiredThroughYear) {
  Fail "picker_horizon=$maxYear required=$RequiredThroughYear"
}
foreach ($year in (($years | Measure-Object -Minimum).Minimum..$RequiredThroughYear)) {
  if ($years -notcontains $year) { Fail "picker_gap=$year" }
}

# A separate AS3 escape hatch is obsolete once modern dates are part of the same
# timeline. Keep this as evidence for cleanup without blocking existing deployments
# until the legacy footer is removed from source.
$legacyAs3Footer = $timeline -match "updateVersion\('2016-01-01'\)"
if ($legacyAs3Footer) {
  Write-Warning 'WADDLE_MODERN_TIMELINE legacy_as3_footer=true cleanup_pending=true'
}

# Required dates are supplied by party integrations. The verifier itself stays generic:
# any future party can assert that its activation date is represented by update data.
$updateText = (Get-ChildItem -LiteralPath $updatesRoot -Filter '*.ts' -File | ForEach-Object {
  [IO.File]::ReadAllText($_.FullName)
}) -join "`n"
foreach ($date in $RequiredDates) {
  if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { Fail "invalid_required_date=$date" }
  if ($updateText -notmatch [regex]::Escape("date: '$date'")) {
    Fail "missing_required_date=$date"
  }
}

Write-Host "WADDLE_MODERN_TIMELINE=PASS picker_min=$(($years | Measure-Object -Minimum).Minimum) picker_max=$maxYear required_through=$RequiredThroughYear required_dates=$($RequiredDates.Count) data_driven_end=true legacy_as3_footer=$($legacyAs3Footer.ToString().ToLowerInvariant())"
