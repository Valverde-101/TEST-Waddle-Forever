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
  $files = @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') } | Sort-Object FullName)
  $chunks = @()
  foreach ($file in $files) {
    $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($body)) {
      $chunks += "// FILE: $($file.FullName.Substring($out.Length).TrimStart('\\'))`n$body"
    }
  }
  return [pscustomobject]@{ name=$Name; path=$Swf; bytes=[int64](Get-Item -LiteralPath $Swf).Length; scriptFiles=$files.Count; text=($chunks -join "`n") }
}

function Evidence([string]$Text) {
  return [ordered]@{
    selector20150501 = $Text.Contains('20150501')
    mayParty = $Text -match '(?i)MayParty'
    activeFeatures = $Text -match '(?i)activefeatures'
    featuresPath = $Text -match '(?i)FEATURES_SWF_PATH|content/features\.swf|features\.swf'
    configurePartyJson = $Text -match '(?i)configurePartyJSON'
    loadPartyFeatures = $Text -match '(?i)loadPartyFeatures'
    showContent = $Text -match '(?i)showContent'
    currentParty = $Text -match '(?i)getCurrentParty|currentParty'
    partyService = $Text -match '(?i)PARTY_SERVICE|partyservice'
    baseParty = $Text -match '(?i)BaseParty'
    questCommunicator = $Text -match '(?i)QuestCommunicator'
    questInterface = $Text -match '(?i)quest_interface|partyinterface'
    partyIcon = $Text -match '(?i)party_icon|PartyIcon'
    halloLogin = $Text -match '(?i)halloLogin|w\.p2015\.may\.login'
  }
}

function Get-SwfLoaders([string]$Text) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($Text,'(?i)(?:play/v2/)?(?:close_ups/|content/|music/|membership/|client/)[A-Za-z0-9_./-]+\.swf')) {
    [void]$set.Add($m.Value.Replace('\\','/'))
  }
  return @($set | Sort-Object)
}

function Get-BootstrapSnippets([string]$Text) {
  $pattern = '(?i)20150501|MayParty|FEATURES_SWF_PATH|features\.swf|configurePartyJSON|loadPartyFeatures|showContent|getCurrentParty|QuestCommunicator|quest_interface|partyinterface|party_icon|halloLogin|PARTY_SERVICE|activefeatures'
  $lines = @($Text -split "`r?`n")
  $hits = New-Object System.Collections.Generic.List[string]
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) {
      $start = [Math]::Max(0,$i-2)
      $end = [Math]::Min($lines.Count-1,$i+2)
      $block = ($lines[$start..$end] -join ' ').Trim()
      $block = [regex]::Replace($block,'\s+',' ')
      if ($block.Length -gt 700) { $block = $block.Substring(0,700) }
      if (-not $hits.Contains($block)) { [void]$hits.Add($block) }
      if ($hits.Count -ge 30) { break }
    }
  }
  return @($hits)
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$ffdec = Resolve-FFDec $FFDecPath
$partyRoot = Join-Path $repo 'media\default\party2015'
$current = Join-Path $repo 'media\default\svanilla\media\play\v2\content\global\content\party.swf'
$candidate = Join-Path $partyRoot 'content\party-base-2015.swf'
$targets = [ordered]@{
  'svanilla-party' = $current
  'party-base-2015' = $candidate
  'client-interface-2015' = (Join-Path $partyRoot 'client\ClientInterface-HalloweenParty2015.swf')
  'features-2015' = (Join-Path $partyRoot 'content\ContentFeatures-HalloweenParty2015.swf')
  'party-icon-2015' = (Join-Path $partyRoot 'content\ContentParty_icon-HalloweenParty2015.swf')
  'quest-communicator' = (Join-Path $partyRoot 'client\QuestCommunicator.swf')
  'quest-interface-2015' = (Join-Path $partyRoot 'close_ups\Close_upsQuest_interface-HalloweenParty2015.swf')
}
$work = Join-Path $repo '.work\halloween2015-runtime-probe'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$reports = [ordered]@{}
foreach ($entry in $targets.GetEnumerator()) {
  $report = Export-Scripts -FFDec $ffdec -Swf $entry.Value -Name $entry.Key -WorkRoot $work
  $reports[$entry.Key] = [ordered]@{
    bytes=$report.bytes
    scripts=$report.scriptFiles
    evidence=(Evidence $report.text)
    loaders=(Get-SwfLoaders $report.text)
    snippets=(Get-BootstrapSnippets $report.text)
  }
}

$currentEvidence = $reports['svanilla-party'].evidence
$candidateEvidence = $reports['party-base-2015'].evidence
$currentSupportsSelector = [bool]($currentEvidence.selector20150501 -and $currentEvidence.mayParty)
$candidateSupportsSelector = [bool]($candidateEvidence.selector20150501 -and $candidateEvidence.mayParty)
$candidateSupportsFeatureBootstrap = [bool]($candidateEvidence.featuresPath -or $candidateEvidence.configurePartyJson -or $candidateEvidence.loadPartyFeatures)

if (-not $candidateSupportsSelector) {
  throw 'WADDLE_PARTY2015_RUNTIME_PROBE=FAIL candidate_missing_20150501_mayparty_selector'
}

$forbiddenCandidateLoaders = @(
  'content/party_map_note.swf','close_ups/party_map_note.swf',
  'music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf'
)
$badCandidateLoaders = @()
foreach ($bad in $forbiddenCandidateLoaders) {
  if ($reports['party-base-2015'].loaders -contains $bad -or $reports['party-base-2015'].loaders -contains ('play/v2/content/global/' + $bad)) { $badCandidateLoaders += $bad }
}
if ($badCandidateLoaders.Count -gt 0) {
  throw "WADDLE_PARTY2015_RUNTIME_PROBE=FAIL candidate_mixed_loader=$($badCandidateLoaders -join ',')"
}

$featureDefinesParty = [bool]($reports['features-2015'].evidence.baseParty -or $reports['features-2015'].evidence.partyService)
$interfaceCanLoadFeatures = [bool]($reports['client-interface-2015'].evidence.featuresPath -or $reports['client-interface-2015'].evidence.loadPartyFeatures -or $reports['client-interface-2015'].evidence.configurePartyJson)
$questChainVisible = [bool]($reports['client-interface-2015'].evidence.questCommunicator -or $reports['quest-communicator'].evidence.questInterface -or $reports['client-interface-2015'].evidence.questInterface)

$summary = [ordered]@{
  schema='waddle-halloween2015-runtime-probe/v3'
  reports=$reports
  conclusions=[ordered]@{
    currentSupportsSelector=$currentSupportsSelector
    candidateSupportsSelector=$candidateSupportsSelector
    candidateSupportsFeatureBootstrap=$candidateSupportsFeatureBootstrap
    interfaceCanLoadFeatures=$interfaceCanLoadFeatures
    featureDefinesParty=$featureDefinesParty
    questChainVisible=$questChainVisible
    forbiddenCandidateLoaders=$badCandidateLoaders
  }
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

foreach ($name in $reports.Keys) {
  $r = $reports[$name]
  $e = $r.evidence
  Write-Host ("WADDLE_PARTY2015_RUNTIME_COMPONENT name={0} bytes={1} scripts={2} selector={3} mayParty={4} featuresPath={5} configure={6} loadFeatures={7} showContent={8} currentParty={9} questCommunicator={10} questInterface={11} partyIcon={12} halloLogin={13}" -f $name,$r.bytes,$r.scripts,$e.selector20150501,$e.mayParty,$e.featuresPath,$e.configurePartyJson,$e.loadPartyFeatures,$e.showContent,$e.currentParty,$e.questCommunicator,$e.questInterface,$e.partyIcon,$e.halloLogin)
  foreach ($loader in $r.loaders) { Write-Host "WADDLE_PARTY2015_RUNTIME_LOADER component=$name path=$loader" }
  $n = 0
  foreach ($snippet in $r.snippets) {
    $n++
    Write-Host "WADDLE_PARTY2015_RUNTIME_EVIDENCE component=$name hit=$n text=$snippet"
  }
}
Write-Host "WADDLE_PARTY2015_RUNTIME_PROBE=PASS current_selector=$currentSupportsSelector candidate_selector=$candidateSupportsSelector candidate_feature_bootstrap=$candidateSupportsFeatureBootstrap interface_can_load_features=$interfaceCanLoadFeatures feature_defines_party=$featureDefinesParty quest_chain_visible=$questChainVisible forbidden_candidate_loaders=$($badCandidateLoaders.Count) summary=$summaryPath"
