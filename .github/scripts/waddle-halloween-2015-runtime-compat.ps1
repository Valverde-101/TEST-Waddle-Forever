[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$FFDecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    $header = New-Object byte[] 3
    if ($stream.Read($header,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($header)
  } finally { $stream.Dispose() }
}

function Resolve-FFDec([string]$Explicit) {
  if ($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Leaf)) { return (Resolve-Path -LiteralPath $Explicit).Path }
  foreach ($candidate in @($env:FFDEC_PATH,$env:WADDLE_FFDEC)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $root = 'V:\AndroidBuild\Tools\FFDec'
  if (Test-Path -LiteralPath $root -PathType Container) {
    $exe = Get-ChildItem -LiteralPath $root -Filter 'ffdec-cli.exe' -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
  }
  throw 'WADDLE_PARTY2015_RUNTIME_PROBE=FAIL ffdec_missing'
}

function Export-Scripts([string]$FFDec,[string]$Swf,[string]$Name,[string]$WorkRoot) {
  if (-not (Test-Swf $Swf)) { throw "WADDLE_PARTY2015_RUNTIME_PROBE=FAIL invalid_swf name=$Name path=$Swf" }
  $out = Join-Path $WorkRoot ($Name + '-scripts')
  if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  $stdout = Join-Path $WorkRoot ($Name + '.stdout.txt')
  $stderr = Join-Path $WorkRoot ($Name + '.stderr.txt')
  $args = @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',('"' + $out + '"'),('"' + $Swf + '"'))
  $proc = Start-Process -FilePath $FFDec -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit(120000)) {
    try { $proc.Kill() } catch {}
    throw "WADDLE_PARTY2015_RUNTIME_PROBE=FAIL ffdec_timeout name=$Name"
  }
  $proc.Refresh()
  if ([int]$proc.ExitCode -ne 0) { throw "WADDLE_PARTY2015_RUNTIME_PROBE=FAIL ffdec_exit=$($proc.ExitCode) name=$Name" }
  $files = @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') })
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }) -join "`n"
  return [pscustomobject]@{ name=$Name; path=$Swf; bytes=[int64](Get-Item -LiteralPath $Swf).Length; scriptFiles=$files.Count; text=$text }
}

function Evidence([string]$Text) {
  return [ordered]@{
    selector20150501 = $Text.Contains('20150501')
    mayParty = $Text -match '(?i)MayParty'
    activeFeatures = $Text -match '(?i)activefeatures'
    featuresPath = $Text -match '(?i)FEATURES_SWF_PATH|content/features\.swf|features\.swf'
    configurePartyJson = $Text -match '(?i)configurePartyJSON'
    loadPartyFeatures = $Text -match '(?i)loadPartyFeatures'
    partyService = $Text -match '(?i)PARTY_SERVICE'
    baseParty = $Text -match '(?i)BaseParty'
  }
}

function Get-SwfLoaders([string]$Text) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($Text,'(?i)(?:play/v2/)?(?:close_ups/|content/|music/|membership/)[A-Za-z0-9_./-]+\.swf')) {
    [void]$set.Add($m.Value.Replace('\\','/'))
  }
  return @($set | Sort-Object)
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$ffdec = Resolve-FFDec $FFDecPath
$current = Join-Path $repo 'media\default\svanilla\media\play\v2\content\global\content\party.swf'
$candidate = Join-Path $repo 'media\default\party2015\content\party-base-2015.swf'
$work = Join-Path $repo '.work\halloween2015-runtime-probe'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$currentReport = Export-Scripts -FFDec $ffdec -Swf $current -Name 'svanilla-party' -WorkRoot $work
$candidateReport = Export-Scripts -FFDec $ffdec -Swf $candidate -Name 'party-base-2015' -WorkRoot $work
$currentEvidence = Evidence $currentReport.text
$candidateEvidence = Evidence $candidateReport.text
$currentLoaders = Get-SwfLoaders $currentReport.text
$candidateLoaders = Get-SwfLoaders $candidateReport.text

$currentSupportsSelector = [bool]($currentEvidence.selector20150501 -and $currentEvidence.mayParty)
$candidateSupportsSelector = [bool]($candidateEvidence.selector20150501 -and $candidateEvidence.mayParty)
$candidateSupportsFeatureBootstrap = [bool]($candidateEvidence.featuresPath -or $candidateEvidence.configurePartyJson -or $candidateEvidence.loadPartyFeatures)
$candidatePreferred = [bool]($candidateSupportsSelector -and (-not $currentSupportsSelector -or $candidateSupportsFeatureBootstrap))

if (-not $candidateSupportsSelector) {
  throw 'WADDLE_PARTY2015_RUNTIME_PROBE=FAIL candidate_missing_20150501_mayparty_selector'
}

$forbiddenCandidateLoaders = @(
  'content/party_map_note.swf','close_ups/party_map_note.swf',
  'music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf'
)
$badCandidateLoaders = @()
foreach ($bad in $forbiddenCandidateLoaders) {
  if ($candidateLoaders -contains $bad -or $candidateLoaders -contains ('play/v2/content/global/' + $bad)) { $badCandidateLoaders += $bad }
}
if ($badCandidateLoaders.Count -gt 0) {
  throw "WADDLE_PARTY2015_RUNTIME_PROBE=FAIL candidate_mixed_loader=$($badCandidateLoaders -join ',')"
}

$summary = [ordered]@{
  schema='waddle-halloween2015-runtime-probe/v2'
  current=[ordered]@{ bytes=$currentReport.bytes; scripts=$currentReport.scriptFiles; evidence=$currentEvidence; supportsSelector=$currentSupportsSelector; loaders=$currentLoaders }
  candidate=[ordered]@{ bytes=$candidateReport.bytes; scripts=$candidateReport.scriptFiles; evidence=$candidateEvidence; supportsSelector=$candidateSupportsSelector; supportsFeatureBootstrap=$candidateSupportsFeatureBootstrap; loaders=$candidateLoaders; forbiddenLoaders=$badCandidateLoaders }
  candidatePreferred=$candidatePreferred
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ("WADDLE_PARTY2015_RUNTIME_CURRENT bytes={0} scripts={1} selector20150501={2} mayParty={3} activefeatures={4} featuresPath={5} configurePartyJson={6} loadPartyFeatures={7} partyService={8}" -f $currentReport.bytes,$currentReport.scriptFiles,$currentEvidence.selector20150501,$currentEvidence.mayParty,$currentEvidence.activeFeatures,$currentEvidence.featuresPath,$currentEvidence.configurePartyJson,$currentEvidence.loadPartyFeatures,$currentEvidence.partyService)
Write-Host ("WADDLE_PARTY2015_RUNTIME_CANDIDATE bytes={0} scripts={1} selector20150501={2} mayParty={3} activefeatures={4} featuresPath={5} configurePartyJson={6} loadPartyFeatures={7} partyService={8}" -f $candidateReport.bytes,$candidateReport.scriptFiles,$candidateEvidence.selector20150501,$candidateEvidence.mayParty,$candidateEvidence.activeFeatures,$candidateEvidence.featuresPath,$candidateEvidence.configurePartyJson,$candidateEvidence.loadPartyFeatures,$candidateEvidence.partyService)
foreach ($loader in $candidateLoaders) { Write-Host "WADDLE_PARTY2015_RUNTIME_CANDIDATE_LOADER=$loader" }
Write-Host "WADDLE_PARTY2015_RUNTIME_PROBE=PASS current_selector=$currentSupportsSelector candidate_selector=$candidateSupportsSelector candidate_feature_bootstrap=$candidateSupportsFeatureBootstrap candidate_preferred=$candidatePreferred forbidden_candidate_loaders=$($badCandidateLoaders.Count) summary=$summaryPath"
