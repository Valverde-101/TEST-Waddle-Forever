[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$preservedPath = Join-Path $repo 'media\default\party2015\game_configs\game_strings.json'
$contractPath = Join-Path $repo 'media\default\party2015\game_configs\halloween2015_dialogue_strings.json'
$generatorPath = Join-Path $repo 'src\server\file-generators\index.ts'

foreach ($path in @($preservedPath,$contractPath,$generatorPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL missing=$path"
  }
}

$prefix = 'w.app.p2015.halloween.'
$expected = 38
$preserved = Get-Content -LiteralPath $preservedPath -Raw | ConvertFrom-Json
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

if ($null -eq $preserved.lang) { throw 'WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL preserved_lang_missing' }
if ([string]$contract.namespace -cne $prefix) { throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL namespace=$($contract.namespace) expected=$prefix" }
if ([int]$contract.totalKeys -ne $expected) { throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL declared_total=$($contract.totalKeys) expected=$expected" }
if ($null -eq $contract.strings) { throw 'WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL strings_missing' }

$runtime = [ordered]@{}
foreach ($property in @($contract.strings.PSObject.Properties)) {
  $key = [string]$property.Name
  $value = [string]$property.Value
  if (-not $key.StartsWith($prefix,[StringComparison]::Ordinal)) {
    throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL foreign_key=$key"
  }
  if ($runtime.Contains($key)) { throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL duplicate_key=$key" }
  if ([string]::IsNullOrWhiteSpace($value)) { throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL empty_value=$key" }
  $runtime[$key] = $value
}
if ($runtime.Count -ne $expected) {
  throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL runtime_string_count=$($runtime.Count) expected=$expected"
}

# The preserved CPImagined config owns the customized finale. Those values must
# remain byte-semantically identical inside the complete Waddle contract.
$preservedParty = [ordered]@{}
foreach ($entry in @($preserved.lang)) {
  if ($null -eq $entry -or $entry.Count -lt 2) { continue }
  $key = [string]$entry[0]
  if ($key.StartsWith($prefix,[StringComparison]::Ordinal)) {
    $preservedParty[$key] = [string]$entry[1]
  }
}
$preservedFinaleKeys = @($contract.preservedFinaleKeys)
if ($preservedParty.Count -ne 9 -or $preservedFinaleKeys.Count -ne 9) {
  throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL preserved_finale_count=$($preservedParty.Count) declared=$($preservedFinaleKeys.Count) expected=9"
}
foreach ($key in $preservedFinaleKeys) {
  $k = [string]$key
  if (-not $preservedParty.Contains($k)) { throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL preserved_finale_missing=$k" }
  if (-not $runtime.Contains($k)) { throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL runtime_finale_missing=$k" }
  if ([string]$runtime[$k] -cne [string]$preservedParty[$k]) {
    throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL preserved_finale_drift=$k"
  }
}
if ([int]$contract.restoredMascBotKeys -ne 29) {
  throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL restored_count=$($contract.restoredMascBotKeys) expected=29"
}

$generator = ([IO.File]::ReadAllText($generatorPath) -replace "`r`n", "`n")
foreach ($generatorContract in @(
  "const HALLOWEEN_2015_LOCALIZATION_PREFIX = 'w.app.p2015.halloween.';",
  'const HALLOWEEN_2015_LOCALIZATION_COUNT = 38;',
  "const HALLOWEEN_2015_LOCALIZATION_FILE = 'halloween2015_dialogue_strings.json';",
  "const MODERN_CONFIG_BUNDLE_ROUTE = 'play/en/web_service/game_configs.bin';",
  'const getRuntimeGameStringsJson: FileGenerator',
  'localization.totalKeys !== HALLOWEEN_2015_LOCALIZATION_COUNT',
  "'play/en/web_service/game_configs/game_strings.json': getRuntimeGameStringsJson"
)) {
  if (-not $generator.Contains($generatorContract)) {
    throw "WADDLE_HALLOWEEN2015_LOCALIZATION=FAIL generator_contract=$generatorContract"
  }
}

Write-Host "WADDLE_HALLOWEEN2015_LOCALIZATION=PASS runtime_strings=$($runtime.Count) preserved_finale=$($preservedParty.Count) restored_mascbot=29 overlay=versioned-contract strict=true"
