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
$localizationPath = Join-Path $partyRoot 'game_configs\halloween2015_dialogue_strings.json'
if (-not (Test-Path -LiteralPath $dialogueRoot -PathType Container)) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL closeups_missing=$dialogueRoot"
}
if (-not (Test-Path -LiteralPath $localizationPath -PathType Leaf)) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL localization_contract_missing=$localizationPath"
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
if ($sorted.Count -ne 38) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL token_inventory=$($sorted.Count) expected=38 dialogues=$($dialogues.Count)"
}

# The SWFs define the required key set. The versioned localization contract is the
# single runtime source of values; the original CPImagined game_strings remains
# untouched and is separately checked for its nine custom finale values.
$contract = Get-Content -LiteralPath $localizationPath -Raw | ConvertFrom-Json
if ($null -eq $contract.strings) { throw 'WADDLE_PARTY2015_DIALOGUES=FAIL strings_missing' }
$available = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$empty = New-Object 'System.Collections.Generic.List[string]'
foreach ($property in @($contract.strings.PSObject.Properties)) {
  $key = [string]$property.Name
  $value = [string]$property.Value
  [void]$available.Add($key)
  if ([string]::IsNullOrWhiteSpace($value)) { $empty.Add($key) | Out-Null }
}
if ($empty.Count -gt 0) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL empty_localizations=$($empty.Count) keys=$($empty -join ',')"
}

$missing = @($sorted | Where-Object { -not $available.Contains($_) })
$extra = @($available | Where-Object { $sorted -cnotcontains $_ } | Sort-Object)
foreach ($token in $missing) { Write-Host "WADDLE_PARTY2015_DIALOGUE_MISSING=$token" }
foreach ($token in $extra) { Write-Host "WADDLE_PARTY2015_DIALOGUE_EXTRA=$token" }

$report = [ordered]@{
  schema = 'waddle-party-dialogue-audit/v4'
  party = 'Halloween Party 2015'
  dialogues = $dialogues.Count
  requiredTokens = $sorted
  localizationCount = $available.Count
  localizationSource = 'party2015/game_configs/halloween2015_dialogue_strings.json'
  missingTokens = $missing
  extraTokens = $extra
  files = $fileTokenMap
  complete = ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $available.Count -eq 38)
}
$reportPath = Join-Path $work 'localization-audit.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($RequireComplete -and ($missing.Count -gt 0 -or $extra.Count -gt 0 -or $available.Count -ne 38)) {
  throw "WADDLE_PARTY2015_DIALOGUES=FAIL missing=$($missing.Count) extra=$($extra.Count) available=$($available.Count) tokens=$($sorted.Count) dialogues=$($dialogues.Count) report=$reportPath"
}

$status = if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $available.Count -eq 38) { 'PASS' } else { 'INCOMPLETE' }
Write-Host "WADDLE_PARTY2015_DIALOGUES=$status dialogues=$($dialogues.Count) tokens=$($sorted.Count) localization=$($available.Count) missing=$($missing.Count) extra=$($extra.Count) require_complete=$RequireComplete source=versioned-contract report=$reportPath"
