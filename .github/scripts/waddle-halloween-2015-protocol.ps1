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

function Invoke-Dump([string]$FFDec,[string]$Swf,[string]$Out,[string]$Err) {
  Remove-Item -LiteralPath $Out,$Err -Force -ErrorAction SilentlyContinue
  $quoted = '"' + $Swf.Replace('"','\"') + '"'
  $proc = Start-Process -FilePath $FFDec -ArgumentList @('-cli','-dumpAS3',$quoted) -RedirectStandardOutput $Out -RedirectStandardError $Err -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit(45000)) {
    try { $proc.Kill() } catch {}
    try { [void]$proc.WaitForExit(3000) } catch {}
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_timeout swf=$Swf"
  }
  $proc.Refresh()
  if ($proc.ExitCode -ne 0) {
    $message = if (Test-Path -LiteralPath $Err) { (Get-Content -LiteralPath $Err -Raw -ErrorAction SilentlyContinue) } else { '' }
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_exit=$($proc.ExitCode) swf=$Swf error=$message"
  }
  if (-not (Test-Path -LiteralPath $Out -PathType Leaf) -or (Get-Item -LiteralPath $Out).Length -eq 0) {
    throw "WADDLE_PARTY2015_PROTOCOL=FAIL ffdec_empty swf=$Swf"
  }
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$canonical = (Resolve-Path -LiteralPath $CanonicalRoot).Path
$partyRoot = Join-Path $canonical 'media\default\party2015'
if (-not (Test-Path -LiteralPath $partyRoot -PathType Container)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL party_root_missing=$partyRoot" }
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
New-Item -ItemType Directory -Force -Path $work | Out-Null
$pairSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$tokenSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$reports = New-Object System.Collections.Generic.List[object]

$networkRegexes = @(
  '(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']',
  '(?is)send(?:Extension)?Message\s*\(\s*["'']([^"'']+)["'']\s*,\s*["'']([^"'']+)["'']',
  '(?is)sendXtMessage\s*\(\s*["'']([^"'']+)["'']'
)
$keyword = '(?i)(quest|robot|herbert|herbot|tile|party|masc|bot|progress|state|mission|maze|login|reward|unlock|complete|item|sendXt|extension|packet|message)'

foreach ($target in $targets) {
  $swf = Join-Path $partyRoot $target.path
  if (-not (Test-Swf $swf)) { throw "WADDLE_PARTY2015_PROTOCOL=FAIL invalid_target role=$($target.role) path=$swf" }
  $safe = ($target.role -replace '[^A-Za-z0-9_.-]','_')
  $out = Join-Path $work ($safe + '.as3.txt')
  $err = Join-Path $work ($safe + '.err.txt')
  Invoke-Dump -FFDec $ffdec -Swf $swf -Out $out -Err $err
  $text = Get-Content -LiteralPath $out -Raw

  $pairs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($rx in $networkRegexes) {
    foreach ($m in [regex]::Matches($text,$rx)) {
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
  foreach ($m in [regex]::Matches($text,'["'']([^"''\r\n]{2,100})["'']')) {
    $value = $m.Groups[1].Value.Trim()
    if ($value -match $keyword -or $value -match '^[a-z]{1,12}#[a-z0-9_]{1,32}$') {
      [void]$tokens.Add($value); [void]$tokenSet.Add($value)
    }
  }

  $lines = @($text -split "`r?`n" | Where-Object { $_ -match $keyword } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique -First 80)
  $evidencePath = Join-Path $work ($safe + '.evidence.txt')
  $lines | Set-Content -LiteralPath $evidencePath -Encoding UTF8
  $report = [pscustomobject]@{
    role = $target.role
    file = $target.path
    bytes = [int64](Get-Item -LiteralPath $swf).Length
    pairs = @($pairs | Sort-Object)
    tokens = @($tokens | Sort-Object)
    evidence = $lines
  }
  $reports.Add($report)
  Write-Host "WADDLE_PARTY2015_PROTOCOL_FILE=PASS role=$($target.role) pairs=$(@($pairs).Count) tokens=$(@($tokens).Count) evidence=$($lines.Count)"
  foreach ($pair in @($pairs | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR role=$($target.role) value=$pair" }
  foreach ($line in @($lines | Select-Object -First 12)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_LINE role=$($target.role) value=$line" }
}

$summary = [ordered]@{
  schema = 'waddle-halloween2015-protocol/v1'
  party = 'Halloween Party 2015'
  targetCount = $targets.Count
  ffdec = $ffdec
  pairs = @($pairSet | Sort-Object)
  tokens = @($tokenSet | Sort-Object)
  files = $reports
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "WADDLE_PARTY2015_PROTOCOL=PASS targets=$($targets.Count) pairs=$(@($pairSet).Count) tokens=$(@($tokenSet).Count) summary=$summaryPath"
foreach ($pair in @($pairSet | Sort-Object)) { Write-Host "WADDLE_PARTY2015_PROTOCOL_PAIR_ALL=$pair" }
