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

function Invoke-FFDec {
  param([string]$FFDec,[string[]]$Arguments,[string]$Stdout,[string]$Stderr,[int]$TimeoutSeconds=90)
  Remove-Item -LiteralPath $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
  $proc = Start-Process -FilePath $FFDec -ArgumentList $Arguments -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    try { [void]$proc.WaitForExit(3000) } catch {}
    return [pscustomobject]@{ ok=$false; timeout=$true; exit=$null }
  }
  $proc.Refresh()
  $exitText = [string]$proc.ExitCode
  return [pscustomobject]@{ ok=([string]::IsNullOrWhiteSpace($exitText) -or [int]$exitText -eq 0); timeout=$false; exit=$exitText }
}

function Get-ScriptEvidence {
  param([string]$FFDec,[string]$Swf,[string]$SafeName,[string]$WorkRoot)
  $exportDir = Join-Path $WorkRoot ($SafeName + '-scripts')
  $stdout = Join-Path $WorkRoot ($SafeName + '.export.stdout.txt')
  $stderr = Join-Path $WorkRoot ($SafeName + '.export.stderr.txt')
  if (Test-Path -LiteralPath $exportDir) { Remove-Item -LiteralPath $exportDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
  $quotedOut = '"' + $exportDir.Replace('"','\"') + '"'
  $quotedSwf = '"' + $Swf.Replace('"','\"') + '"'
  $result = Invoke-FFDec -FFDec $FFDec -Arguments @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',$quotedOut,$quotedSwf) -Stdout $stdout -Stderr $stderr -TimeoutSeconds 90
  if ($result.timeout) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_export_timeout swf=$Swf" }
  if (-not $result.ok) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_export_exit=$($result.exit) swf=$Swf" }
  $sourceFiles = @(Get-ChildItem -LiteralPath $exportDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.as','.txt') } | Sort-Object FullName)
  if ($sourceFiles.Count -eq 0) { return [pscustomobject]@{ mode='no-script'; text=''; files=0 } }
  $chunks = @()
  foreach ($file in $sourceFiles) {
    $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($body)) { $chunks += $body }
  }
  return [pscustomobject]@{ mode='export-script'; text=($chunks -join "`n`n"); files=$sourceFiles.Count }
}

function Get-TerminalIdentifier([string]$Expression) {
  if ([string]::IsNullOrWhiteSpace($Expression)) { return '' }
  $parts = $Expression.Trim() -split '\.'
  return [string]$parts[$parts.Count - 1]
}

function Add-ResolvedPairs {
  param(
    [string]$Text,
    [System.Collections.Generic.HashSet[string]]$LocalPairs,
    [System.Collections.Generic.HashSet[string]]$AllPairs,
    [System.Collections.Generic.HashSet[string]]$HandlerNames
  )
  $constants = @{}
  foreach ($m in [regex]::Matches($Text,'(?m)(?:static\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*[A-Za-z0-9_.<>]+)?\s*=\s*["'']([^"''\r\n]*)["'']')) {
    $constants[$m.Groups[1].Value] = $m.Groups[2].Value
  }

  foreach ($m in [regex]::Matches($Text,'(?i)["'']([a-z0-9_]{1,40})#([a-z0-9_]{1,48})["'']')) {
    $pair = $m.Groups[1].Value + '#' + $m.Groups[2].Value
    [void]$LocalPairs.Add($pair); [void]$AllPairs.Add($pair); [void]$HandlerNames.Add($m.Groups[1].Value)
  }

  foreach ($m in [regex]::Matches($Text,'(?i)([A-Za-z_][A-Za-z0-9_.]*)\s*\+\s*["'']#["'']\s*\+\s*([A-Za-z_][A-Za-z0-9_.]*)')) {
    $leftKey = Get-TerminalIdentifier $m.Groups[1].Value
    $rightKey = Get-TerminalIdentifier $m.Groups[2].Value
    if ($constants.ContainsKey($leftKey) -and $constants.ContainsKey($rightKey)) {
      $left = [string]$constants[$leftKey]
      $right = [string]$constants[$rightKey]
      if ($left -match '^[A-Za-z0-9_]{1,40}$' -and $right -match '^[A-Za-z0-9_]{1,48}$') {
        $pair = $left + '#' + $right
        [void]$LocalPairs.Add($pair); [void]$AllPairs.Add($pair); [void]$HandlerNames.Add($left)
      }
    }
  }

  foreach ($entry in $constants.GetEnumerator()) {
    if ($entry.Key -match '(?i)(COOKIE_HANDLER|HANDLER_NAME)$' -and [string]$entry.Value -match '^[A-Za-z0-9_]{1,40}$') {
      [void]$HandlerNames.Add([string]$entry.Value)
    }
  }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$repoPartyRoot = Join-Path $repo 'media\default\party2015'
$partyRoot = $null
if (Test-Path -LiteralPath $repoPartyRoot -PathType Container) { $partyRoot = $repoPartyRoot }
elseif ($CanonicalRoot -and (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
  $candidate = Join-Path (Resolve-Path -LiteralPath $CanonicalRoot).Path 'media\default\party2015'
  if (Test-Path -LiteralPath $candidate -PathType Container) { $partyRoot = $candidate }
}
if (-not $partyRoot) { throw 'WADDLE_PARTY2015_PROTOCOL=FAIL party_root_missing' }
$ffdec = Resolve-FFDec $FFDecPath

$targets = @(
  @{ role='client-interface'; path='client\ClientInterface-HalloweenParty2015.swf' },
  @{ role='features'; path='content\ContentFeatures-HalloweenParty2015.swf' },
  @{ role='quest'; path='close_ups\Close_upsQuest_interface-HalloweenParty2015.swf' },
  @{ role='robot-avatar'; path='avatar\PenguinRobot.swf' }
)
foreach ($dialogue in @(Get-ChildItem -LiteralPath (Join-Path $partyRoot 'close_ups') -Filter 'Hallo15_dialogue_*.swf' -File | Sort-Object Name)) {
  $targets += @{ role=('dialogue-' + ([IO.Path]::GetFileNameWithoutExtension($dialogue.Name) -replace '^Hallo15_dialogue_','').ToLowerInvariant()); path=('close_ups\' + $dialogue.Name) }
}
foreach ($i in 0..8) { $targets += @{ role="tiles-$i"; path="close_ups\Close_upsTiles_minigame$i-HalloweenParty2015.swf" } }

$work = Join-Path $repo '.work\halloween2015-protocol'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

# Inspect the actual Waddle vanilla party bootstrap, because modern room/quest SWFs call
# _global.getCurrentParty().BaseParty.CURRENT_PARTY and therefore compatibility cannot
# be proven from event art alone.
$vanillaCandidates = @(
  (Join-Path $repo 'media\default\svanilla\media\play\v2\content\global\content\party.swf')
)
if ($CanonicalRoot -and (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
  $vanillaCandidates += (Join-Path (Resolve-Path -LiteralPath $CanonicalRoot).Path 'media\default\svanilla\media\play\v2\content\global\content\party.swf')
}
$vanillaParty = $vanillaCandidates | Where-Object { Test-Swf $_ } | Select-Object -First 1
if ($vanillaParty) {
  $targets += @{ role='runtime-vanilla-party'; absolute=[string]$vanillaParty; source='waddle-svanilla' }
} else {
  Write-Host 'WADDLE_PARTY2015_PROTOCOL_RUNTIME=WARN vanilla_party_swf_not_found'
}

# CPImagined preserves a Halloween-2015-derived party bootstrap in its classic-edition
# archive. It is reference evidence only: never publish this file into Waddle from here.
$referenceParty = Join-Path $work 'reference-halloween-party.swf'
$referenceUrl = 'https://raw.githubusercontent.com/CPImagined/CPImagined-Archive/main/parties/2310%202%20halloween%20classic%20edition/party.swf'
try {
  Invoke-WebRequest -UseBasicParsing -Uri $referenceUrl -OutFile $referenceParty -TimeoutSec 45
  if (Test-Swf $referenceParty) {
    $targets += @{ role='reference-halloween-party'; absolute=$referenceParty; source='cpimagined-reference' }
    Write-Host "WADDLE_PARTY2015_PROTOCOL_REFERENCE=PASS source=$referenceUrl bytes=$((Get-Item $referenceParty).Length)"
  } else {
    Write-Host 'WADDLE_PARTY2015_PROTOCOL_REFERENCE=WARN downloaded_reference_not_swf'
  }
} catch {
  Write-Host "WADDLE_PARTY2015_PROTOCOL_REFERENCE=WARN download_failed=$($_.Exception.Message)"
}

$pairSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$tokenSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$packetTokenSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$serviceCallSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$localizationSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$handlerNameSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$classNameSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$reports = @()
$scriptedTargets = 0

$networkRegexes = @(
  '(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']',
  '(?is)send(?:Extension)?Message\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']',
  '(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']'
)
$keyword = '(?i)(quest|robot|herbert|herbot|tile|party|masc|bot|progress|state|mission|maze|login|reward|unlock|complete|item|sendXt|extension|packet|message|cookie|communicator|activefeature|partyservice|CURRENT_PARTY)'
$packetWord = '(?i)^(partycookie|partyservice|msgviewed|qcmsgviewed|qtaskcomplete|qtupdate|spts|partytask|questtask|party)$'

foreach ($target in $targets) {
  $swf = if ($target.ContainsKey('absolute')) { [string]$target.absolute } else { Join-Path $partyRoot $target.path }
  $displayFile = if ($target.ContainsKey('path')) { [string]$target.path } else { [string]$target.source }
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ($target.role -replace '[^A-Za-z0-9_.-]','_')
  $source = Get-ScriptEvidence -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$source.text
  if (-not [string]::IsNullOrWhiteSpace($text)) { $scriptedTargets++ }

  foreach ($m in [regex]::Matches($text,'(?m)\bclass\s+([A-Za-z_][A-Za-z0-9_.$]*)')) {
    [void]$classNameSet.Add($m.Groups[1].Value)
  }

  $pairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($rx in $networkRegexes) {
    foreach ($m in [regex]::Matches($text,$rx)) {
      if ($m.Groups.Count -ge 3 -and $m.Groups[2].Success) {
        $pair = $m.Groups[1].Value.Trim() + '#' + $m.Groups[2].Value.Trim()
        if ($pair.Length -le 160) { [void]$pairs.Add($pair); [void]$pairSet.Add($pair) }
      } elseif ($m.Groups.Count -ge 2) { [void]$tokenSet.Add($m.Groups[1].Value.Trim()) }
    }
  }
  Add-ResolvedPairs -Text $text -LocalPairs $pairs -AllPairs $pairSet -HandlerNames $handlerNameSet

  foreach ($m in [regex]::Matches($text,'(?i)(?:PARTY_SERVICE|partyService)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
    [void]$serviceCallSet.Add($m.Groups[1].Value)
  }
  foreach ($m in [regex]::Matches($text,'w\.app\.p2015\.halloween(?:\.[A-Za-z0-9_]+)+')) {
    [void]$localizationSet.Add($m.Value)
  }

  $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($text,'["'']([^"''\r\n]{2,100})["'']')) {
    $value = $m.Groups[1].Value.Trim()
    if ($value -match $keyword -or $value -match '^[a-z]{1,16}#[a-z0-9_]{1,48}$') { [void]$tokens.Add($value); [void]$tokenSet.Add($value) }
    if ($value -match $packetWord) { [void]$packetTokenSet.Add($value) }
  }

  $lines = @()
  if ($text) { $lines = @($text -split "`r?`n" | Where-Object { $_ -match $keyword } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique -First 180) }
  $reports += [pscustomobject]@{ role=$target.role; file=$displayFile; bytes=[int64](Get-Item $swf).Length; scriptMode=$source.mode; scriptFiles=[int]$source.files; pairs=@($pairs|Sort-Object); tokens=@($tokens|Sort-Object); evidence=$lines }
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) script_mode=$($source.mode) script_files=$($source.files) pairs=$(@($pairs).Count) tokens=$(@($tokens).Count) evidence=$($lines.Count)"
  foreach ($pair in @($pairs|Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE_PAIR role=$($target.role) pair=$pair" }
}

if ($scriptedTargets -lt 1) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL no_script_sources targets=$($targets.Count)" }

$summary = [ordered]@{
  schema='waddle-modern-party-protocol/v5'
  party='Halloween Party 2015'
  targetCount=$targets.Count
  scriptedTargetCount=$scriptedTargets
  ffdec=$ffdec
  partyRoot=$partyRoot
  pairs=@($pairSet|Sort-Object)
  handlerNames=@($handlerNameSet|Sort-Object)
  classNames=@($classNameSet|Sort-Object)
  packetTokens=@($packetTokenSet|Sort-Object)
  partyServiceCalls=@($serviceCallSet|Sort-Object)
  localizationTokens=@($localizationSet|Sort-Object)
  tokens=@($tokenSet|Sort-Object)
  files=$reports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($pair in @($pairSet|Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR_ALL=$pair" }
foreach ($handlerName in @($handlerNameSet|Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_HANDLER=$handlerName" }
foreach ($className in @($classNameSet|Sort-Object | Where-Object { $_ -match '(?i)(party|cookie|october|halloween)' })) { Write-Host "WADDLE_PARTY2015_PROTOCOL_CLASS=$className" }
foreach ($token in @($packetTokenSet|Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PACKET_ALL=$token" }
foreach ($call in @($serviceCallSet|Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_SERVICE_CALL=$call" }
foreach ($key in @($localizationSet|Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LOCALIZATION=$key" }
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS targets=$($targets.Count) scripted_targets=$scriptedTargets pairs=$(@($pairSet).Count) handlers=$(@($handlerNameSet).Count) classes=$(@($classNameSet).Count) packet_tokens=$(@($packetTokenSet).Count) service_calls=$(@($serviceCallSet).Count) localization_tokens=$(@($localizationSet).Count) summary=$summaryPath"