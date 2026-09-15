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
$htmlPath = Join-Path $RepoRoot 'src/client/views/timeline/timeline.html'
$updatesPath = Join-Path $RepoRoot 'src/server/updates/updates.ts'
$party2015Path = Join-Path $RepoRoot 'src/server/updates/2015.ts'
$updates2016Path = Join-Path $RepoRoot 'src/server/updates/2016.ts'

foreach ($required in @($timelinePath,$htmlPath,$updatesPath,$party2015Path,$updates2016Path)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "WADDLE_TIMELINE_MODERN=FAIL missing=$required"
  }
}

$timeline = Read-Normalized $timelinePath

$oldYearLine = @'
  const yearStr = (year === undefined && useYear) ? '' : `, ${year}`;
'@.TrimEnd()
$newYearLine = @'
  const yearStr = useYear && year !== undefined ? `, ${year}` : '';
'@.TrimEnd()
$timeline = Replace-Required $timeline $oldYearLine $newYearLine 'date-year-format'

$selectAnchor = @'
function setSelectElements(month: number, year: number) {
  monthElement.value = MONTHS[month - 1];
  yearElement.value = String(year);
}
'@
$selectWithYears = @'
function setSelectElements(month: number, year: number) {
  monthElement.value = MONTHS[month - 1];
  yearElement.value = String(year);
}

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
$timeline = Replace-Required $timeline $selectAnchor $selectWithYears 'dynamic-years'

$timeline = Replace-Required $timeline `
  '            if (year !== undefined && month !== undefined)' `
  '            if (year !== undefined && monthNumber !== undefined)' `
  'scroll-select-guard'

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

$timeline = Replace-Required $timeline `
  "    const selected = document.querySelectorAll('.selected-day')[0];" `
  "    const selected = document.querySelectorAll('.selected-list-day')[0];" `
  'list-selected-scroll'

$eventAnchor = @'
  currentVersion = settings.version;
  const dateInfo = getDateInfo(currentVersion);
'@
$eventWithYears = @'
  currentVersion = settings.version;
  syncYearOptions(days);
  const dateInfo = getDateInfo(currentVersion);
'@
$timeline = Replace-Required $timeline $eventAnchor $eventWithYears 'timeline-event-years'

Write-Utf8 $timelinePath $timeline

$html = Read-Normalized $htmlPath
$html = $html -replace '(?m)^\s*<option>2017</option>\s*\n?', ''
if (-not $html.Contains('<option>2016</option>')) {
  throw 'WADDLE_TIMELINE_MODERN=FAIL year_2016_missing_from_fallback_html'
}
Write-Utf8 $htmlPath $html

$updates = Read-Normalized $updatesPath
$party2015 = Read-Normalized $party2015Path
$updates2016 = Read-Normalized $updates2016Path

foreach ($needle in @(
  'import { UPDATES_2015 } from "./2015";',
  'import { UPDATES_2016 } from "./2016";',
  '...UPDATES_2015',
  '...UPDATES_2016'
)) {
  if (-not $updates.Contains($needle)) { throw "WADDLE_TIMELINE_MODERN=FAIL updates_missing=$needle" }
}
if (-not $party2015.Contains("date: '2015-10-21'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL halloween_2015_date_missing' }
if (-not $party2015.Contains("partyName: 'Halloween Party 2015'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL halloween_2015_party_missing' }
if (-not $updates2016.Contains("date: '2016-01-01'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL year_2016_update_missing' }
if (-not $updates2016.Contains("indexHtml: 'modern-as3'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL modern_as3_entry_missing' }

# Engine cutovers are generic timeline facts: Halloween 2015 must be after both
# AS3 (2010-11-19) and the vanilla-engine transition (2011-06-27).
$updates2010 = Read-Normalized (Join-Path $RepoRoot 'src/server/updates/2010.ts')
$updates2011 = Read-Normalized (Join-Path $RepoRoot 'src/server/updates/2011.ts')
if (-not $updates2010.Contains("dateReference: 'as3'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL as3_cutover_missing' }
if (-not $updates2011.Contains("dateReference: 'vanilla-engine'")) { throw 'WADDLE_TIMELINE_MODERN=FAIL vanilla_engine_cutover_missing' }

Write-Host 'WADDLE_TIMELINE_MODERN=PASS years=data-driven current_max=2016 halloween=2015-10-21 as3=true vanilla_engine=true legacy_footer=false'
