[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$CanonicalRoot = 'V:\AndroidBuild\Repositories\TEST-Waddle-Forever',
  [string]$FFDecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    $buf = New-Object byte[] 3
    if ($stream.Read($buf,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($buf)
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
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_missing'
}

function Export-Scripts([string]$FFDec,[string]$Swf,[string]$SafeName,[string]$WorkRoot) {
  $out = Join-Path $WorkRoot ($SafeName + '-scripts')
  if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  $stdout = Join-Path $WorkRoot ($SafeName + '.stdout.txt')
  $stderr = Join-Path $WorkRoot ($SafeName + '.stderr.txt')
  $args = @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',('"' + $out + '"'),('"' + $Swf + '"'))
  $proc = Start-Process -FilePath $FFDec -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit(90000)) {
    try { $proc.Kill() } catch {}
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_timeout swf=$Swf"
  }
  $proc.Refresh()
  $exitText = [string]$proc.ExitCode
  if (-not [string]::IsNullOrWhiteSpace($exitText) -and [int]$exitText -ne 0) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_exit=$exitText swf=$Swf"
  }
  $files = @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') } | Sort-Object FullName)
  $chunks = @()
  foreach ($file in $files) {
    $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($body)) { $chunks += $body }
  }
  return [pscustomobject]@{ files=$files.Count; text=($chunks -join "`n`n"); exit=$exitText }
}

function Add-Evidence(
  [string]$Text,
  [System.Collections.Generic.HashSet[string]]$Pairs,
  [System.Collections.Generic.HashSet[string]]$Packets,
  [System.Collections.Generic.HashSet[string]]$Localizations,
  [System.Collections.Generic.HashSet[string]]$Loaders
) {
  foreach ($m in [regex]::Matches($Text,'w\.app\.p2015\.halloween(?:\.[A-Za-z0-9_]+)+')) { [void]$Localizations.Add($m.Value) }
  foreach ($m in [regex]::Matches($Text,'(?i)["'']([a-z0-9_]{1,40})#([a-z0-9_]{1,48})["'']')) { [void]$Pairs.Add($m.Groups[1].Value + '#' + $m.Groups[2].Value) }
  foreach ($m in [regex]::Matches($Text,'(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']')) { [void]$Pairs.Add($m.Groups[1].Value.Trim() + '#' + $m.Groups[2].Value.Trim()) }
  foreach ($m in [regex]::Matches($Text,'["''](partycookie|partyservice|msgviewed|qcmsgviewed|qtaskcomplete|qtupdate|activefeatures|nxquestsettings|nxquestdata|spts)["'']',[Text.RegularExpressions.RegexOptions]::IgnoreCase)) { [void]$Packets.Add($m.Groups[1].Value.ToLowerInvariant()) }
  foreach ($m in [regex]::Matches($Text,'(?i)(?:close_ups/|content/|music/|membership/)[A-Za-z0-9_./-]+\.swf')) { [void]$Loaders.Add($m.Value.Replace('\\','/')) }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$repoPartyRoot = Join-Path $repo 'media\default\party2015'
$partyRoot = $null
if (Test-Path -LiteralPath $repoPartyRoot -PathType Container) {
  $partyRoot = $repoPartyRoot
} elseif ($CanonicalRoot -and (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
  $candidate = Join-Path (Resolve-Path -LiteralPath $CanonicalRoot).Path 'media\default\party2015'
  if (Test-Path -LiteralPath $candidate -PathType Container) { $partyRoot = $candidate }
}
if (-not $partyRoot) { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL party_root_missing' }
$ffdec = Resolve-FFDec $FFDecPath

# Only files selected by the October 2015 stack are protocol evidence. The 2310
# party/map/classic-interface files remain on disk as provenance and are excluded.
$interactionCore = @(
  @{ role='client-interface-2015'; path='client\ClientInterface-HalloweenParty2015.swf' },
  @{ role='quest-interface-2015'; path='close_ups\Close_upsQuest_interface-HalloweenParty2015.swf' },
  @{ role='features-2015'; path='content\ContentFeatures-HalloweenParty2015.swf' },
  @{ role='party-icon-2015'; path='content\ContentParty_icon-HalloweenParty2015.swf' },
  @{ role='quest-communicator'; path='client\QuestCommunicator.swf' },
  @{ role='robot-avatar'; path='avatar\PenguinRobot.swf' }
)
$targets = @($interactionCore)
foreach ($dialogue in @(Get-ChildItem -LiteralPath (Join-Path $partyRoot 'close_ups') -Filter 'Hallo15_dialogue_*.swf' -File | Sort-Object Name)) {
  $targets += @{ role=('dialogue-' + ([IO.Path]::GetFileNameWithoutExtension($dialogue.Name) -replace '^Hallo15_dialogue_','').ToLowerInvariant()); path=('close_ups\' + $dialogue.Name) }
}
foreach ($i in 0..8) { $targets += @{ role="tiles-$i"; path="close_ups\Close_upsTiles_minigame$i-HalloweenParty2015.swf" } }

$dialogueCount = @($targets | Where-Object { $_.role -like 'dialogue-*' }).Count
if ($dialogueCount -ne 34) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL dialogue_targets=$dialogueCount expected=34" }
if ($targets.Count -ne 49) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL target_count=$($targets.Count) expected=49" }

$work = Join-Path $repo '.work\halloween2015-protocol'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$pairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$packets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$localizations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$loaders = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$reports = @()
$scripted = 0
$coreScripted = 0
$interactionText = ''

foreach ($target in $targets) {
  $swf = Join-Path $partyRoot ([string]$target.path)
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ([string]$target.role -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  if ($evidence.files -gt 0) { $scripted++ }
  if (@($interactionCore | Where-Object { $_.role -eq $target.role }).Count -gt 0) {
    if ($evidence.files -gt 0) { $coreScripted++ }
    $interactionText += "`n" + $text
  }
  Add-Evidence -Text $text -Pairs $pairs -Packets $packets -Localizations $localizations -Loaders $loaders
  $reports += [pscustomobject]@{ role=[string]$target.role; file=[string]$target.path; bytes=[int64](Get-Item -LiteralPath $swf).Length; scriptFiles=[int]$evidence.files; ffdecExit=[string]$evidence.exit }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) bytes=$((Get-Item -LiteralPath $swf).Length) script_files=$($evidence.files) ffdec_exit=$($evidence.exit)"
}

if ($coreScripted -lt 4) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL interaction_core_scripted=$coreScripted expected_at_least=4" }
if ($scripted -lt 40) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL scripted_targets=$scripted expected_at_least=40" }
if ($interactionText -notmatch '(?i)(party|quest|halloween|robot|PARTY_ICON|showContent)') {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL historical_interaction_core_has_no_party_evidence'
}
if ($localizations.Count -ne 38) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_tokens=$($localizations.Count) expected=38" }

# Known loaders from the rejected mixed stack must not leak back into the exact
# archive interaction core. Emit every discovered loader so Live Trace gaps can
# be compared directly with static ActionScript evidence.
foreach ($loader in @($loaders | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOADER=$loader" }
foreach ($badLoader in @('content/party_map_note.swf','party_map_note.swf','music/2048.swf','music/2049.swf','music/2050.swf','music/2051.swf','music/2052.swf','music/2053.swf')) {
  if ($loaders.Contains($badLoader)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL mixed_runtime_loader=$badLoader" }
}

$worldHandlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$partyHandlerPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$worldHandlers = [IO.File]::ReadAllText($worldHandlersPath)
$partyHandler = [IO.File]::ReadAllText($partyHandlerPath)
foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $worldHandlers.Contains($route)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL server_route_missing=$route" }
}
foreach ($token in @('getPartyServiceConfig','sendCurrentPartyCookie','partyservice','partycookie','activefeatures','nxquestsettings','nxquestdata','qtupdate')) {
  if (-not $partyHandler.Contains($token)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_handler_missing=$token" }
}

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v8'
  party='Halloween Party 2015'
  evidence='exact-cparchives-2015-served-stack'
  targetCount=$targets.Count
  interactionCoreCount=$interactionCore.Count
  interactionCoreScripted=$coreScripted
  dialogueCount=$dialogueCount
  scriptedTargetCount=$scripted
  pairs=@($pairs | Sort-Object)
  packetTokens=@($packets | Sort-Object)
  localizationTokens=@($localizations | Sort-Object)
  dynamicSwfLoaders=@($loaders | Sort-Object)
  files=$reports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR=$pair" }
foreach ($packet in @($packets | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET=$packet" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS runtime=exact-cparchives-2015 targets=$($targets.Count) core=$($interactionCore.Count) core_scripted=$coreScripted dialogues=34 tiles=9 scripted_targets=$scripted localization_tokens=$($localizations.Count) dynamic_loaders=$($loaders.Count) server_routes=5 mixed_2310=false summary=$summaryPath"
