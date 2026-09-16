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
  if ($proc.ExitCode -ne 0) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_exit=$($proc.ExitCode) swf=$Swf" }
  $files = @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') } | Sort-Object FullName)
  $chunks = @()
  foreach ($file in $files) {
    $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($body)) { $chunks += $body }
  }
  return [pscustomobject]@{ files=$files.Count; text=($chunks -join "`n`n") }
}

function Add-ProtocolEvidence(
  [string]$Text,
  [System.Collections.Generic.HashSet[string]]$Pairs,
  [System.Collections.Generic.HashSet[string]]$Packets,
  [System.Collections.Generic.HashSet[string]]$Localizations,
  [System.Collections.Generic.HashSet[string]]$Classes
) {
  foreach ($m in [regex]::Matches($Text,'(?m)\bclass\s+([A-Za-z_][A-Za-z0-9_.$]*)')) {
    [void]$Classes.Add($m.Groups[1].Value)
  }
  foreach ($m in [regex]::Matches($Text,'w\.app\.p2015\.halloween(?:\.[A-Za-z0-9_]+)+')) {
    [void]$Localizations.Add($m.Value)
  }
  foreach ($m in [regex]::Matches($Text,'(?i)["'']([a-z0-9_]{1,40})#([a-z0-9_]{1,48})["'']')) {
    [void]$Pairs.Add($m.Groups[1].Value + '#' + $m.Groups[2].Value)
  }
  foreach ($m in [regex]::Matches($Text,'(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']')) {
    [void]$Pairs.Add($m.Groups[1].Value.Trim() + '#' + $m.Groups[2].Value.Trim())
  }
  foreach ($m in [regex]::Matches($Text,'["''](partycookie|partyservice|msgviewed|qcmsgviewed|qtaskcomplete|qtupdate|activefeatures|spts)["'']',[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    [void]$Packets.Add($m.Groups[1].Value.ToLowerInvariant())
  }
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

# These are the exact Git-owned SWFs served by the Halloween timeline. Do not use
# a vanilla party.swf or download a moving external reference as protocol proof.
$canonicalRuntime = @(
  @{ role='runtime-party'; path='content\party.swf' },
  @{ role='runtime-map'; path='content\map.swf' },
  @{ role='quest-communicator'; path='client\QuestCommunicator.swf' },
  @{ role='ghost-adopt'; path='close_ups\ghostAdopt.swf' },
  @{ role='skip-dialogue'; path='close_ups\skipDialogue.swf' },
  @{ role='hallo-login'; path='close_ups\halloLogin.swf' }
)
$targets = @($canonicalRuntime) + @(
  @{ role='client-interface'; path='client\ClientInterface-HalloweenParty2015.swf' },
  @{ role='features'; path='content\ContentFeatures-HalloweenParty2015.swf' },
  @{ role='quest-interface'; path='close_ups\Close_upsQuest_interface-HalloweenParty2015.swf' },
  @{ role='robot-avatar'; path='avatar\PenguinRobot.swf' }
)
foreach ($dialogue in @(Get-ChildItem -LiteralPath (Join-Path $partyRoot 'close_ups') -Filter 'Hallo15_dialogue_*.swf' -File | Sort-Object Name)) {
  $targets += @{ role=('dialogue-' + ([IO.Path]::GetFileNameWithoutExtension($dialogue.Name) -replace '^Hallo15_dialogue_','').ToLowerInvariant()); path=('close_ups\' + $dialogue.Name) }
}
foreach ($i in 0..8) { $targets += @{ role="tiles-$i"; path="close_ups\Close_upsTiles_minigame$i-HalloweenParty2015.swf" } }

$work = Join-Path $repo '.work\halloween2015-protocol'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$pairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$packets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$localizations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$classes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$reports = @()
$scripted = 0
$canonicalScripted = 0
$runtimeCombined = ''

foreach ($target in $targets) {
  $swf = Join-Path $partyRoot ([string]$target.path)
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ([string]$target.role -replace '[^A-Za-z0-9_.-]','_')
  $evidence = Export-Scripts -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$evidence.text
  if ($evidence.files -gt 0) { $scripted++ }
  if (@($canonicalRuntime | Where-Object { $_.role -eq $target.role }).Count -gt 0) {
    if ($evidence.files -gt 0) { $canonicalScripted++ }
    $runtimeCombined += "`n" + $text
  }
  Add-ProtocolEvidence -Text $text -Pairs $pairs -Packets $packets -Localizations $localizations -Classes $classes
  $reports += [pscustomobject]@{
    role=[string]$target.role
    file=[string]$target.path
    bytes=[int64](Get-Item -LiteralPath $swf).Length
    scriptFiles=[int]$evidence.files
  }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) bytes=$((Get-Item -LiteralPath $swf).Length) script_files=$($evidence.files)"
}

if ($canonicalRuntime.Count -ne 6) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL canonical_runtime_count=$($canonicalRuntime.Count) expected=6" }
if ($canonicalScripted -lt 3) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL canonical_runtime_scripted=$canonicalScripted expected_at_least=3" }
if ($localizations.Count -ne 38) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL localization_tokens=$($localizations.Count) expected=38" }
if ($runtimeCombined -notmatch '(?i)(party|quest|halloween|october|CURRENT_PARTY)') {
  throw 'WADDLE_PARTY2015_PROTOCOL=FAIL canonical_runtime_has_no_party_evidence'
}

# Close the client/server half of the contract too. These handlers are the routes
# required by the modern party cookie/task model and must stay wired whenever the
# preserved runtime is served.
$worldHandlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$partyHandlerPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$worldHandlers = [IO.File]::ReadAllText($worldHandlersPath)
$partyHandler = [IO.File]::ReadAllText($partyHandlerPath)
foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $worldHandlers.Contains($route)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL server_route_missing=$route" }
}
foreach ($token in @('getPartyServiceConfig','sendCurrentPartyCookie','partyservice','partycookie','activefeatures','qtupdate')) {
  if (-not $partyHandler.Contains($token)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_handler_missing=$token" }
}

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v6'
  party='Halloween Party 2015'
  evidence='git-owned-served-runtime-only'
  targetCount=$targets.Count
  canonicalRuntimeCount=$canonicalRuntime.Count
  canonicalRuntimeScripted=$canonicalScripted
  scriptedTargetCount=$scripted
  pairs=@($pairs | Sort-Object)
  packetTokens=@($packets | Sort-Object)
  localizationTokens=@($localizations | Sort-Object)
  relevantClasses=@($classes | Sort-Object | Where-Object { $_ -match '(?i)(party|quest|october|halloween|robot)' })
  files=$reports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR=$pair" }
foreach ($packet in @($packets | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET=$packet" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS targets=$($targets.Count) canonical_runtime=6 canonical_scripted=$canonicalScripted scripted_targets=$scripted localization_tokens=$($localizations.Count) server_routes=5 evidence=git-owned-served-runtime-only summary=$summaryPath"
