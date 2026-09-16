[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$FFDecPath,
  [switch]$RequireComplete
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
$preservedStringsPath = Join-Path $partyRoot 'game_configs\game_strings.json'
if (-not (Test-Path -LiteralPath $dialogueRoot -PathType Container)) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL closeups_missing=$dialogueRoot"
}
if (-not (Test-Path -LiteralPath $preservedStringsPath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL preserved_game_strings_missing=$preservedStringsPath"
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
$fileTokenMap = [ordered]@{}
foreach ($dialogue in $dialogues) {
  $out = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($dialogue.Name))
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  & $ffdec -cli -onerror ignore -exportTimeout 60 -exportFileTimeout 20 -export script $out $dialogue.FullName | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "WADDLE_PARTY2015_DIALOGUES=FAIL ffdec_exit=$LASTEXITCODE file=$($dialogue.Name)"
  }
  $fileTokens = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($file in @(Get-ChildItem -LiteralPath $out -File -Recurse -ErrorAction SilentlyContinue)) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    foreach ($match in @([regex]::Matches($text,'w\.app\.p2015\.halloween(?:\.[A-Za-z0-9_]+)+'))) {
      [void]$tokens.Add($match.Value)
      [void]$fileTokens.Add($match.Value)
    }
  }
  $fileTokenMap[$dialogue.Name] = @($fileTokens | Sort-Object)
}

$sorted = @($tokens | Sort-Object)
foreach ($token in $sorted) { Write-Host "WADDLE_PARTY2015_DIALOGUE_TOKEN=$token" }
if ($sorted.Count -lt 10) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL token_inventory_too_small=$($sorted.Count) dialogues=$($dialogues.Count)"
}

# The original dialogue SWFs are authoritative for which localization keys are
# required. Their values are sourced from the byte-verified preserved
# game_configs/game_strings.json, not reconstructed by hand in TypeScript.
$preserved = Get-Content -LiteralPath $preservedStringsPath -Raw | ConvertFrom-Json
if ($null -eq $preserved.lang) {
  throw 'WADDLE_PARTY2015_DIALOGUES=FAIL preserved_lang_missing'
}
$available = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$empty = New-Object 'System.Collections.Generic.List[string]'
foreach ($entry in @($preserved.lang)) {
  if ($null -eq $entry -or $entry.Count -lt 2) { continue }
  $key = [string]$entry[0]
  if (-not $key.StartsWith('w.app.p2015.halloween.',[StringComparison]::Ordinal)) { continue }
  $value = [string]$entry[1]
  [void]$available.Add($key)
  if ([string]::IsNullOrWhiteSpace($value)) { $empty.Add($key) | Out-Null }
}
if ($empty.Count -gt 0) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL empty_localizations=$($empty.Count) keys=$($empty -join ',')"
}

$missing = @($sorted | Where-Object { -not $available.Contains($_) })
foreach ($token in $missing) { Write-Host "WADDLE_PARTY2015_DIALOGUE_MISSING=$token" }

$report = [ordered]@{
  schema = 'waddle-party-dialogue-audit/v3'
  party = 'Halloween Party 2015'
  dialogues = $dialogues.Count
  requiredTokens = $sorted
  preservedLocalizationCount = $available.Count
  localizationSource = 'party2015/game_configs/game_strings.json'
  missingTokens = $missing
  files = $fileTokenMap
  complete = ($missing.Count -eq 0)
}
$reportPath = Join-Path $work 'localization-audit.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($RequireComplete -and $missing.Count -gt 0) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL missing_localizations=$($missing.Count) tokens=$($sorted.Count) dialogues=$($dialogues.Count) report=$reportPath"
}

$status = if ($missing.Count -eq 0) { 'PASS' } else { 'INCOMPLETE' }
Write-Host "WADDLE_PARTY2015_DIALOGUES=$status dialogues=$($dialogues.Count) tokens=$($sorted.Count) preserved=$($available.Count) missing=$($missing.Count) require_complete=$RequireComplete source=canonical-game-strings report=$reportPath"
