[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$FFDecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FFDec([string]$Explicit) {
  if ($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Leaf)) { return (Resolve-Path -LiteralPath $Explicit).Path }
  foreach ($candidate in @($env:FFDEC_PATH,$env:WADDLE_FFDEC)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $root = 'V:\AndroidBuild\Tools\FFDec'
  $exe = Get-ChildItem -LiteralPath $root -Filter 'ffdec-cli.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($exe) { return $exe.FullName }
  throw 'WADDLE_PARTY2015_ARCHIVE_RUNTIME=FAIL ffdec_missing'
}

function Resolve-ArchiveFileUrl([string]$FileName) {
  $encoded = [Uri]::EscapeDataString('File:' + $FileName)
  $apis = @(
    "https://archives.clubpenguinwiki.info/api.php?action=query&format=json&prop=imageinfo&iiprop=url&titles=$encoded",
    "https://toolbox.solero.me/cparchives/api.php?action=query&format=json&prop=imageinfo&iiprop=url&titles=$encoded"
  )
  foreach ($api in $apis) {
    try {
      $response = Invoke-RestMethod -Uri $api -Method Get -TimeoutSec 30 -Headers @{ 'User-Agent'='Waddle-Forever-Halloween2015-Probe/1.0' }
      $pages = @($response.query.pages.PSObject.Properties.Value)
      foreach ($page in $pages) {
        if ($page.imageinfo -and $page.imageinfo.Count -gt 0 -and $page.imageinfo[0].url) {
          return [string]$page.imageinfo[0].url
        }
      }
    } catch {
      Write-Host "WADDLE_PARTY2015_ARCHIVE_RUNTIME_API_WARN file=$FileName api=$api error=$($_.Exception.Message)"
    }
  }
  return $null
}

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    $header = New-Object byte[] 3
    if ($stream.Read($header,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($header)
  } finally { $stream.Dispose() }
}

function Export-Scripts([string]$FFDec,[string]$Swf,[string]$Name,[string]$Work) {
  $out = Join-Path $Work ($Name + '-scripts')
  if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  $stdout = Join-Path $Work ($Name + '.stdout.txt')
  $stderr = Join-Path $Work ($Name + '.stderr.txt')
  $args = @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',('"' + $out + '"'),('"' + $Swf + '"'))
  $proc = Start-Process -FilePath $FFDec -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit(120000)) { try { $proc.Kill() } catch {}; throw "WADDLE_PARTY2015_ARCHIVE_RUNTIME=FAIL ffdec_timeout name=$Name" }
  $proc.Refresh()
  if ([int]$proc.ExitCode -ne 0) { throw "WADDLE_PARTY2015_ARCHIVE_RUNTIME=FAIL ffdec_exit=$($proc.ExitCode) name=$Name" }
  $parts = @()
  $files = @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') })
  foreach ($file in $files) {
    $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($body) { $parts += $body }
  }
  return [pscustomobject]@{ files=$files.Count; text=($parts -join "`n") }
}

function Bool([string]$Text,[string]$Pattern) { return [bool]($Text -match $Pattern) }

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$ffdec = Resolve-FFDec $FFDecPath
$work = Join-Path $repo '.work\halloween2015-archive-runtime-probe'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$candidates = @(
  'ClientParty-06112015.swf',
  'ClientParty-Fair2015 2.swf',
  'ClientParty-FrozenFever2015.swf',
  'ClientParty-OperationCrustacean.swf',
  'ClientParty-HolidayParty2015.swf'
)

$reports = @()
foreach ($fileName in $candidates) {
  $url = Resolve-ArchiveFileUrl $fileName
  if (-not $url) {
    Write-Host "WADDLE_PARTY2015_ARCHIVE_RUNTIME_CANDIDATE file=$fileName status=url-not-found"
    continue
  }
  $safe = ($fileName -replace '[^A-Za-z0-9._-]','_')
  $target = Join-Path $work $safe
  try {
    Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='Waddle-Forever-Halloween2015-Probe/1.0' }
  } catch {
    Write-Host "WADDLE_PARTY2015_ARCHIVE_RUNTIME_CANDIDATE file=$fileName status=download-failed url=$url error=$($_.Exception.Message)"
    continue
  }
  if (-not (Test-Swf $target)) {
    Write-Host "WADDLE_PARTY2015_ARCHIVE_RUNTIME_CANDIDATE file=$fileName status=invalid-swf url=$url"
    continue
  }
  $export = Export-Scripts $ffdec $target $safe $work
  $text = $export.text
  $report = [ordered]@{
    file=$fileName
    url=$url
    bytes=[int64](Get-Item -LiteralPath $target).Length
    sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    scripts=$export.files
    selector20150501=(Bool $text '20150501')
    mayParty=(Bool $text '(?i)MayParty')
    configurePartyJSON=(Bool $text '(?i)configurePartyJSON')
    loadPartyFeatures=(Bool $text '(?i)loadPartyFeatures')
    getLengthOfQuestVOs=(Bool $text '(?i)getLengthOfQuestVOs')
    getQuestVOByIndex=(Bool $text '(?i)getQuestVOByIndex')
    getTransformationVOs=(Bool $text '(?i)getTransformationVOs')
    getPuffleAdoptionVOs=(Bool $text '(?i)getPuffleAdoptionVOs')
    partyJsonParser=(Bool $text '(?i)PartyJSON_Parser')
    featuresPath=(Bool $text '(?i)FEATURES_SWF_PATH|content/features\.swf|w\.app\.generic\.features')
    partyMapNote=(Bool $text '(?i)party_map_note\.swf')
  }
  $reports += [pscustomobject]$report
  Write-Host ("WADDLE_PARTY2015_ARCHIVE_RUNTIME_CANDIDATE file={0} bytes={1} sha256={2} scripts={3} selector={4} mayParty={5} configure={6} loadFeatures={7} questLen={8} questByIndex={9} transformations={10} puffles={11} parser={12} featuresPath={13} partyMapNote={14}" -f $report.file,$report.bytes,$report.sha256,$report.scripts,$report.selector20150501,$report.mayParty,$report.configurePartyJSON,$report.loadPartyFeatures,$report.getLengthOfQuestVOs,$report.getQuestVOByIndex,$report.getTransformationVOs,$report.getPuffleAdoptionVOs,$report.partyJsonParser,$report.featuresPath,$report.partyMapNote)
}

$complete = @($reports | Where-Object {
  $_.selector20150501 -and $_.mayParty -and $_.configurePartyJSON -and $_.loadPartyFeatures -and
  $_.getLengthOfQuestVOs -and $_.getQuestVOByIndex -and $_.getTransformationVOs -and $_.getPuffleAdoptionVOs -and
  -not $_.partyMapNote
})

$summary = [ordered]@{
  schema='waddle-halloween2015-archive-runtime-probe/v1'
  reports=$reports
  completeCandidates=@($complete | ForEach-Object { $_.file })
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "WADDLE_PARTY2015_ARCHIVE_RUNTIME=PASS analyzed=$($reports.Count) complete=$($complete.Count) candidates=$($complete.file -join ',') summary=$summaryPath"
