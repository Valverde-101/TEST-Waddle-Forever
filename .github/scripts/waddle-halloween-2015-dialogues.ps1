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
  if (Test-Path -LiteralPath $root -PathType Container) {
    $exe = Get-ChildItem -LiteralPath $root -Filter 'ffdec-cli.exe' -File -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
  }
  throw 'WADDLE_PARTY2015_DIALOGUES=FAIL ffdec_missing'
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$partyRoot = Join-Path $repo 'media\default\party2015'
$dialogueRoot = Join-Path $partyRoot 'close_ups'
if (-not (Test-Path -LiteralPath $dialogueRoot -PathType Container)) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL closeups_missing=$dialogueRoot"
}
$dialogues = @(Get-ChildItem -LiteralPath $dialogueRoot -Filter 'Hallo15_dialogue_*.swf' -File | Sort-Object Name)
if ($dialogues.Count -lt 30) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL dialogue_inventory_too_small=$($dialogues.Count)"
}

$ffdec = Resolve-FFDec $FFDecPath
$work = Join-Path $repo '.work\halloween2015-dialogues'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($dialogue in $dialogues) {
  $out = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($dialogue.Name))
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  & $ffdec -cli -onerror ignore -exportTimeout 60 -exportFileTimeout 20 -export script $out $dialogue.FullName | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "WADDLE_PARTY2015_DIALOGUES=FAIL ffdec_exit=$LASTEXITCODE file=$($dialogue.Name)"
  }
  foreach ($file in @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue)) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    foreach ($match in @([regex]::Matches($text,'w\.app\.p2015\.halloween(?:\.[A-Za-z0-9_]+)+'))) {
      [void]$tokens.Add($match.Value)
    }
  }
}

$sorted = @($tokens | Sort-Object)
foreach ($token in $sorted) { Write-Host "WADDLE_PARTY2015_DIALOGUE_TOKEN=$token" }
if ($sorted.Count -lt 10) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL token_inventory_too_small=$($sorted.Count) dialogues=$($dialogues.Count)"
}

$updatesPath = Join-Path $repo 'src\server\updates\2015.ts'
$updates = Get-Content -LiteralPath $updatesPath -Raw
$missing = @($sorted | Where-Object { -not $updates.Contains($_) })
foreach ($token in $missing) { Write-Host "WADDLE_PARTY2015_DIALOGUE_MISSING=$token" }
if ($missing.Count -gt 0) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL missing_localizations=$($missing.Count) tokens=$($sorted.Count) dialogues=$($dialogues.Count)"
}

Write-Host "WADDLE_PARTY2015_DIALOGUES=PASS dialogues=$($dialogues.Count) tokens=$($sorted.Count) missing=0"
