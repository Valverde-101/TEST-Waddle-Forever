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
  param(
    [Parameter(Mandatory)][string]$FFDec,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$Stdout,
    [Parameter(Mandatory)][string]$Stderr,
    [int]$TimeoutSeconds = 90
  )
  Remove-Item -LiteralPath $Stdout,$Stderr -Force -ErrorAction SilentlyContinue
  $proc = Start-Process -FilePath $FFDec -ArgumentList $Arguments -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    try { [void]$proc.WaitForExit(3000) } catch {}
    return [pscustomobject]@{ ok=$false; timeout=$true; exit=$null }
  }
  $proc.Refresh()
  $exitText = [string]$proc.ExitCode
  $ok = [string]::IsNullOrWhiteSpace($exitText) -or [int]$exitText -eq 0
  return [pscustomobject]@{ ok=$ok; timeout=$false; exit=$exitText }
}

function Get-ScriptEvidence {
  param(
    [Parameter(Mandatory)][string]$FFDec,
    [Parameter(Mandatory)][string]$Swf,
    [Parameter(Mandatory)][string]$SafeName,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  # FFDec's `-export script` works for AVM1/AS1-2 and AVM2/AS3. Several
  # archived party/dialogue SWFs are timeline-driven, so a file with no source
  # is evidence in itself rather than a decompiler failure.
  $exportDir = Join-Path $WorkRoot ($SafeName + '-scripts')
  $stdout = Join-Path $WorkRoot ($SafeName + '.export.stdout.txt')
  $stderr = Join-Path $WorkRoot ($SafeName + '.export.stderr.txt')
  if (Test-Path -LiteralPath $exportDir) { Remove-Item -LiteralPath $exportDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

  $quotedOut = '"' + $exportDir.Replace('"','\"') + '"'
  $quotedSwf = '"' + $Swf.Replace('"','\"') + '"'
  $result = Invoke-FFDec -FFDec $FFDec -Arguments @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',$quotedOut,$quotedSwf) -Stdout $stdout -Stderr $stderr -TimeoutSeconds 90
  if ($result.timeout) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_export_timeout swf=$Swf" }
  if (-not $result.ok) {
    $err = if (Test-Path -LiteralPath $stderr) { (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) } else { '' }
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_export_exit=$($result.exit) swf=$Swf error=$err"
  }

  $files = @(Get-ChildItem -LiteralPath $exportDir -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
  $sourceFiles = @($files | Where-Object { $_.Extension -in @('.as','.txt') })
  if (@($sourceFiles).Count -eq 0) {
    return [pscustomobject]@{ mode='no-script'; text=''; files=0 }
  }

  $chunks = New-Object System.Collections.Generic.List[string]
  foreach ($file in @($sourceFiles)) {
    try {
      $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
      if (-not [string]::IsNullOrWhiteSpace($body)) {
        $chunks.Add("// FILE: $($file.FullName.Substring($exportDir.Length).TrimStart('\\'))`n$body")
      }
    } catch {}
  }
  return [pscustomobject]@{
    mode='export-script'
    text=($chunks -join "`n`n")
    files=@($sourceFiles).Count
  }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$repoPartyRoot = Join-Path $repo 'media\default\party2015'
$partyRoot = $null
if (Test-Path -LiteralPath $repoPartyRoot -PathType Container) {
  $partyRoot = $repoPartyRoot
} elseif ($CanonicalRoot -and (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
  $canonical = (Resolve-Path -LiteralPath $CanonicalRoot).Path
  $candidate = Join-Path $canonical 'media\default\party2015'
  if (Test-Path -LiteralPath $candidate -PathType Container) { $partyRoot = $candidate }
}
if (-not $partyRoot) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_root_missing repo=$repo canonical=$CanonicalRoot" }
$ffdec = Resolve-FFDec $FFDecPath

$targets = @(
  @{ role='client-interface'; path='client\ClientInterface-HalloweenParty2015.swf' },
  @{ role='features'; path='content\ContentFeatures-HalloweenParty2015.swf' },
  @{ role='quest'; path='close_ups\Close_upsQuest_interface-HalloweenParty2015.swf' },
  @{ role='robot-avatar'; path='avatar\PenguinRobot.swf' },
  @{ role='rookie-bot'; path='close_ups\Hallo15_dialogue_Rookie_bot.swf' },
  @{ role='herbert-caged'; path='close_ups\Hallo15_dialogue_Herbert_caged.swf' },
  @{ role='herbert-escape'; path='close_ups\Hallo15_dialogue_Herbert_escape.swf' },
  @{ role='herbot'; path='close_ups\Hallo15_dialogue_Herbot.swf' },
  @{ role='herbert-monologue'; path='close_ups\Hallo15_dialogue_Herbert_monologue.swf' },
  @{ role='herbert-monologue-2'; path='close_ups\Hallo15_dialogue_Herbert_monologue_2.swf' },
  @{ role='gary-lair'; path='close_ups\Hallo15_dialogue_Gary_lair.swf' }
)
foreach ($i in 0..8) { $targets += @{ role="tiles-$i"; path="close_ups\Close_upsTiles_minigame$i-HalloweenParty2015.swf" } }

$work = Join-Path $repo '.work\halloween2015-protocol'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null
$pairSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$tokenSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$reports = New-Object System.Collections.Generic.List[object]
$scriptedTargets = 0

$networkRegexes = @(
  '(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']',
  '(?is)send(?:Extension)?Message\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']',
  '(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']'
)
$keyword = '(?i)(quest|robot|herbert|herbot|tile|party|masc|bot|progress|state|mission|maze|login|reward|unlock|complete|item|sendXt|extension|packet|message)'

foreach ($target in @($targets)) {
  $swf = Join-Path $partyRoot $target.path
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ($target.role -replace '[^A-Za-z0-9_.-]','_')
  $source = Get-ScriptEvidence -FFDec $ffdec -Swf $swf -SafeName $safe -WorkRoot $work
  $text = [string]$source.text
  if (-not [string]::IsNullOrWhiteSpace($text)) { $scriptedTargets++ }

  $pairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($rx in @($networkRegexes)) {
    foreach ($m in @([regex]::Matches($text,$rx))) {
      if ($m.Groups.Count -ge 3 -and $m.Groups[2].Success) {
        $pair = ($m.Groups[1].Value.Trim() + '#' + $m.Groups[2].Value.Trim())
        if ($pair.Length -le 160) { [void]$pairs.Add($pair); [void]$pairSet.Add($pair) }
      } elseif ($m.Groups.Count -ge 2) {
        $token = $m.Groups[1].Value.Trim()
        if ($token.Length -le 100) { [void]$tokenSet.Add($token) }
      }
    }
  }

  $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in @([regex]::Matches($text,'["'']([^"''\r\n]{2,100})["'']'))) {
    $value = $m.Groups[1].Value.Trim()
    if ($value -match $keyword -or $value -match '^[a-z]{1,16}#[a-z0-9_]{1,48}$') {
      [void]$tokens.Add($value); [void]$tokenSet.Add($value)
    }
  }

  $lines = @()
  if (-not [string]::IsNullOrWhiteSpace($text)) {
    $lines = @($text -split "`r?`n" | Where-Object { $_ -match $keyword } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique -First 100)
  }
  $lines = @($lines)
  $evidencePath = Join-Path $work ($safe + '.evidence.txt')
  $lines | Set-Content -LiteralPath $evidencePath -Encoding UTF8
  $report = [pscustomobject]@{
    role = $target.role
    file = $target.path
    bytes = [int64](Get-Item -LiteralPath $swf).Length
    scriptMode = $source.mode
    scriptFiles = [int]$source.files
    pairs = @($pairs | Sort-Object)
    tokens = @($tokens | Sort-Object)
    evidence = @($lines)
  }
  [void]$reports.Add($report)
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) script_mode=$($source.mode) script_files=$($source.files) pairs=$(@($pairs).Count) tokens=$(@($tokens).Count) evidence=$(@($lines).Count)"
  foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR role=$($target.role) value=$pair" }
  foreach ($line in @($lines | Select-Object -First 16)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LINE role=$($target.role) value=$line" }
}

if ($scriptedTargets -lt 1) {
  throw "WADDLE_PARTY2015_PROTOCOL=FAIL no_script_sources targets=$(@($targets).Count) ffdec=$ffdec"
}

$summary = [ordered]@{
  schema = 'waddle-halloween2015-protocol/v2'
  party = 'Halloween Party 2015'
  targetCount = @($targets).Count
  scriptedTargetCount = $scriptedTargets
  ffdec = $ffdec
  partyRoot = $partyRoot
  pairs = @($pairSet | Sort-Object)
  tokens = @($tokenSet | Sort-Object)
  files = @($reports)
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS targets=$(@($targets).Count) scripted_targets=$scriptedTargets pairs=$(@($pairSet).Count) tokens=$(@($tokenSet).Count) party_root=$partyRoot summary=$summaryPath"
foreach ($pair in @($pairSet | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR_ALL=$pair" }
