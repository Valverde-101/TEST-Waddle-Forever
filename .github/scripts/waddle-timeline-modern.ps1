param([string]$RepoRoot = $env:GITHUB_WORKSPACE)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Read-Normalized([string]$Path) {
  return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Write-Utf8([string]$Path,[string]$Text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path,($Text -replace "`r`n", "`n"),$enc)
}

function Replace-Required([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  if ($Text.Contains($New)) { return $Text }
  if (-not $Text.Contains($Old)) { throw "WADDLE_TIMELINE_MODERN=FAIL patch_not_found=$Label" }
  return $Text.Replace($Old,$New)
}

$timelinePath = Join-Path $RepoRoot 'src/client/views/timeline/timeline-static.ts'
$timelineBackendPath = Join-Path $RepoRoot 'src/client/views/timeline/timeline.ts'
$htmlPath = Join-Path $RepoRoot 'src/client/views/timeline/timeline.html'
$updatesPath = Join-Path $RepoRoot 'src/server/updates/updates.ts'
$party2015Path = Join-Path $RepoRoot 'src/server/updates/2015.ts'
$updates2016Path = Join-Path $RepoRoot 'src/server/updates/2016.ts'
$verifyPath = Join-Path $PSScriptRoot 'waddle-modern-timeline-verify.ps1'

foreach ($required in @($timelinePath,$timelineBackendPath,$htmlPath,$updatesPath,$party2015Path,$updates2016Path,$verifyPath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "WADDLE_TIMELINE_MODERN=FAIL missing=$required"
  }
}

$timeline = Read-Normalized $timelinePath
$html = Read-Normalized $htmlPath

$newSyncMarker = 'const configuredYears = Array.from(yearElement.options)'
$newRangeMarker = 'const lastSelectableYear = Math.max(...selectableYears, payloadEndDate.getFullYear());'
$needsMaterialization = (-not $timeline.Contains($newSyncMarker)) -or (-not $timeline.Contains($newRangeMarker)) -or (-not $html.Contains('<option>2017</option>'))
$isGitHubHosted = ($env:GITHUB_ACTIONS -eq 'true') -and (($env:RUNNER_ENVIRONMENT -eq 'github-hosted') -or ($env:RUNNER_NAME -like 'GitHub Actions*'))

if ($needsMaterialization -and $isGitHubHosted) {
  if (-not $timeline.Contains('function syncYearOptions(days: DateInfo[])')) { throw 'WADDLE_TIMELINE_MODERN=FAIL bootstrap_sync_function_missing' }
  if (-not $timeline.Contains('const endDate = getDateFromDateInfo(days[days.length - 1]);')) { throw 'WADDLE_TIMELINE_MODERN=FAIL bootstrap_calendar_end_missing' }
  if (-not $html.Contains('<option>2016</option>')) { throw 'WADDLE_TIMELINE_MODERN=FAIL bootstrap_2016_missing' }
  Write-Host 'WADDLE_TIMELINE_MODERN=MATERIALIZATION_PENDING authority=self_hosted reason=generator_revision picker_through=2017'
  return
}

$oldYearLine = @'
  const yearStr = (year === undefined && useYear) ? '' : `, ${year}`;
'@.TrimEnd()
$newYearLine = @'
  const yearStr = useYear && year !== undefined ? `, ${year}` : '';
'@.TrimEnd()
if ($timeline.Contains($oldYearLine)) { $timeline = $timeline.Replace($oldYearLine,$newYearLine) }

$currentSync = @'
/** Keep the year picker in lockstep with the actual timeline data. */
function syncYearOptions(days: DateInfo[]) {
  const years = Array.from(new Set(days.map((day) => day.year)))
    .filter((year) => year > 0)
    .sort((a, b) => a - b);

  if (years.length === 0) {
    throw new Error('Timeline contains no selectable years');
  }

  yearElement.innerHTML = years
    .map((year) => `<option value="${year}">${year}</option>`)
    .join('');
  yearElement.dataset.timelineYears = years.join(',');
}
'@
$newSync = @'
/** Keep configured years visible while allowing future timeline data to extend the range. */
function syncYearOptions(days: DateInfo[]) {
  const configuredYears = Array.from(yearElement.options)
    .map((option) => Number(option.value || option.text))
    .filter((year) => Number.isFinite(year) && year > 0);
  const payloadYears = days
    .map((day) => day.year)
    .filter((year) => Number.isFinite(year) && year > 0);
  const allYears = [...configuredYears, ...payloadYears];

  if (allYears.length === 0) {
    throw new Error('Timeline contains no selectable years');
  }

  const minYear = Math.min(...allYears);
  const maxYear = Math.max(...allYears);
  const years = Array.from({ length: maxYear - minYear + 1 }, (_, index) => minYear + index);

  yearElement.innerHTML = years
    .map((year) => `<option value="${year}">${year}</option>`)
    .join('');
  yearElement.dataset.timelineYears = years.join(',');
}
'@
if (-not $timeline.Contains($newSync)) {
  if (-not $timeline.Contains($currentSync)) { throw 'WADDLE_TIMELINE_MODERN=FAIL patch_not_found=defensive_years' }
  $timeline = $timeline.Replace($currentSync,$newSync)
}

$currentEnd = @'
  const endDate = getDateFromDateInfo(days[days.length - 1]);
  endDate.setDate(endDate.getDate() + 1);
'@
$newEnd = @'
  const payloadEndDate = getDateFromDateInfo(days[days.length - 1]);
  const selectableYears = Array.from(yearElement.options)
    .map((option) => Number(option.value || option.text))
    .filter((year) => Number.isFinite(year) && year > 0);
  const lastSelectableYear = Math.max(...selectableYears, payloadEndDate.getFullYear());
  const endDate = new Date(lastSelectableYear, 11, 31);
  endDate.setDate(endDate.getDate() + 1);
'@
if (-not $timeline.Contains($newEnd)) {
  if (-not $timeline.Contains($currentEnd)) { throw 'WADDLE_TIMELINE_MODERN=FAIL patch_not_found=calendar_selectable_horizon' }
  $timeline = $timeline.Replace($currentEnd,$newEnd)
}

$timeline = Replace-Required $timeline '            if (year !== undefined && month !== undefined)' '            if (year !== undefined && monthNumber !== undefined)' 'scroll-select-guard'

$oldFooter = @'
  const as3Footer = document.getElementById('as3-footer')!;
  as3Footer.innerHTML = `
    <button>
      Click here to play in a 2016/2017 version (still in development)
    </button>
  `;

  as3Footer.onclick = (e) => {
    updateVersion('2016-01-01');
  }
'@
if ($timeline.Contains($oldFooter)) {
  $timeline = $timeline.Replace($oldFooter,'')
} elseif ($timeline.Contains('Click here to play in a 2016/2017 version')) {
  throw 'WADDLE_TIMELINE_MODERN=FAIL legacy_as3_footer_shape_changed'
}

$timeline = Replace-Required $timeline "    const selected = document.querySelectorAll('.selected-day')[0];" "    const selected = document.querySelectorAll('.selected-list-day')[0];" 'list-selected-scroll'

$eventAnchor = @'
  currentVersion = settings.version;
  const dateInfo = getDateInfo(currentVersion);
'@
$eventWithYears = @'
  currentVersion = settings.version;
  syncYearOptions(days);
  const dateInfo = getDateInfo(currentVersion);
'@
if (-not $timeline.Contains('syncYearOptions(days);')) {
  $timeline = Replace-Required $timeline $eventAnchor $eventWithYears 'timeline-event-years'
}
Write-Utf8 $timelinePath $timeline

$timelineBackend = Read-Normalized $timelineBackendPath
$backendAnchor = @'
  UPDATES.forEach(update => {
    if (update.update.gameRelease !== undefined) {
'@
$backendWithClientVersion = @'
  UPDATES.forEach(update => {
    if (update.update.indexHtml !== undefined || update.update.websiteFolder !== undefined) {
      addEvent(map, update.date, 'A new client version is available', 'other');
    }
    if (update.update.gameRelease !== undefined) {
'@
if (-not $timelineBackend.Contains("addEvent(map, update.date, 'A new client version is available', 'other');")) {
  $timelineBackend = Replace-Required $timelineBackend $backendAnchor $backendWithClientVersion 'client-version-days'
}
Write-Utf8 $timelineBackendPath $timelineBackend

$html = Read-Normalized $htmlPath
if (-not $html.Contains('<option>2017</option>')) {
  if (-not $html.Contains('<option>2016</option>')) { throw 'WADDLE_TIMELINE_MODERN=FAIL year_2016_missing_from_fallback_html' }
  $html = $html.Replace('              <option>2016</option>', "              <option>2016</option>`n              <option>2017</option>")
}
Write-Utf8 $htmlPath $html

$updates = Read-Normalized $updatesPath
$party2015 = Read-Normalized $party2015Path
$updates2016 = Read-Normalized $updates2016Path
foreach ($needle in @('import { UPDATES_2015 } from "./2015";','import { UPDATES_2016 } from "./2016";','...UPDATES_2015','...UPDATES_2016')) {
  if (-not $updates.Contains($needle)) { throw "WADDLE_TIMELINE_MODERN=FAIL updates_missing=$needle" }
}
if ($party2015 -notmatch "date\s*:\s*'2015-10-21'") { throw 'WADDLE_TIMELINE_MODERN=FAIL halloween_2015_date_missing' }
if ($party2015 -notmatch "partyName\s*:\s*'Halloween Party 2015'") { throw 'WADDLE_TIMELINE_MODERN=FAIL halloween_2015_party_missing' }
if ($party2015 -notmatch "date\s*:\s*'2015-11-05'") { throw 'WADDLE_TIMELINE_MODERN=FAIL halloween_2015_exclusive_end_missing' }
# The 2016 placeholder can begin after a cross-year temporary party finishes.
# Never require Jan 1 if Holiday is still active then: that reset hides its
# rooms/icon/music before the historical January 6 final day.
$jan1=$updates2016.Contains("date: '2016-01-01'")
$holidayJan7=$updates2016.Contains("date: '2016-01-07'") -and
  ($updates2016 -match "end\\s*:\\s*\\['party'\\]") -and
  ($party2015 -match "date\\s*:\\s*'2015-12-17'") -and
  ($party2015 -match "partyName\\s*:\\s*'Holiday Party 2015'")
if (-not ($jan1 -or $holidayJan7)) { throw 'WADDLE_TIMELINE_MODERN=FAIL year_2016_update_missing_or_holiday_end_invalid' }
if (-not $updates2016.Contains("indexHtml: 'modern-as3'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL modern_as3_entry_missing' }

$updates2010 = Read-Normalized (Join-Path $RepoRoot 'src/server/updates/2010.ts')
$updates2011 = Read-Normalized (Join-Path $RepoRoot 'src/server/updates/2011.ts')
if (-not $updates2010.Contains("dateReference: 'as3'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL as3_cutover_missing' }
if (-not $updates2011.Contains("dateReference: 'vanilla-engine'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL vanilla_engine_cutover_missing' }

& $verifyPath -RepoRoot $RepoRoot -RequiredThroughYear 2017 -RequiredDates @('2015-10-21','2015-11-05')
Write-Host 'WADDLE_TIMELINE_MODERN=PASS years=configured_plus_payload picker_through=2017 halloween=2015-10-21 exclusive_end=2015-11-05 client_transitions=selectable as3=true vanilla_engine=true legacy_footer=false'
