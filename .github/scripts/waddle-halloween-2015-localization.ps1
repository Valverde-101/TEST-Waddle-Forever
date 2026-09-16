[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$stringsPath = Join-Path $repo 'media\default\party2015\game_configs\game_strings.json'
$generatorPath = Join-Path $repo 'src\server\file-generators\index.ts'

foreach ($path in @($stringsPath,$generatorPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL missing=$path"
  }
}

$strings = Get-Content -LiteralPath $stringsPath -Raw | ConvertFrom-Json
if ($null -eq $strings.lang) {
  throw 'WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL lang_missing'
}

$prefix = 'w.app.p2015.halloween.'
$partyStrings = [ordered]@{}
foreach ($entry in @($strings.lang)) {
  if ($null -eq $entry -or $entry.Count -lt 2) { continue }
  $key = [string]$entry[0]
  $value = [string]$entry[1]
  if ($key.StartsWith($prefix,[StringComparison]::Ordinal)) {
    if ($partyStrings.Contains($key)) {
      throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL duplicate_key=$key"
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL empty_value=$key"
    }
    $partyStrings[$key] = $value
  }
}

# FFDec evidence from the 34 original Halloween dialogue SWFs yields exactly these
# 38 localization tokens. Keeping this count strict makes loss/corruption of the
# preserved bundle fail before the expensive protocol-analysis job.
if ($partyStrings.Count -ne 38) {
  throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL party_string_count=$($partyStrings.Count) expected=38"
}

$generator = ([IO.File]::ReadAllText($generatorPath) -replace "`r`n", "`n")
foreach ($contract in @(
  "const HALLOWEEN_2015_LOCALIZATION_PREFIX = 'w.app.p2015.halloween.';",
  "const MODERN_CONFIG_BUNDLE_ROUTE = 'play/en/web_service/game_configs.bin';",
  "const getRuntimeGameStringsJson: FileGenerator",
  "path.join(path.dirname(configBundle), 'game_strings.json')",
  'key.startsWith(HALLOWEEN_2015_LOCALIZATION_PREFIX)',
  "'play/en/web_service/game_configs/game_strings.json': getRuntimeGameStringsJson"
)) {
  if (-not $generator.Contains($contract)) {
    throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL generator_contract=$contract"
  }
}

Write-Host "WADDLE_HALLOWEEN2015_LOCALIZATION=PASS preserved_strings=$($partyStrings.Count) prefix=$prefix overlay=runtime-sibling strict=true"
