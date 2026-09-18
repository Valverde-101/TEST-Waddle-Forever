[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$FFDecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedBaseBytes = 39406
$ExpectedBaseSha256 = 'd30fcd85c2f4a6b9ef6d1b81aac3a6d2f592af5f68ae13bb9d1564cb5b115cf7'
$CompatMarker = 'WADDLE_HALLOWEEN_2015_ROBOT_RAMPAGE_V1'

function Test-Swf([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $stream = [IO.File]::OpenRead($Path)
  try {
    if ($stream.Length -lt 8) { return $false }
    $b = New-Object byte[] 3
    if ($stream.Read($b,0,3) -ne 3) { return $false }
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($b)
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
  throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL ffdec_missing'
}

function Stop-FFDecTree($Process) {
  if ($null -eq $Process) { return }
  try { & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null }
  catch { try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch {} }
}

function Invoke-FFDec([string]$FFDec,[string[]]$ArgumentList,[string]$Label,[string]$WorkRoot,[int]$TimeoutMs = 180000) {
  $stdout = Join-Path $WorkRoot ($Label + '.stdout.txt')
  $stderr = Join-Path $WorkRoot ($Label + '.stderr.txt')
  $proc = $null
  try {
    if ([string]::IsNullOrWhiteSpace($FFDec) -or -not (Test-Path -LiteralPath $FFDec -PathType Leaf)) {
      throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL ffdec_invalid label=$Label path=$FFDec"
    }
    $nullArgs = @($ArgumentList | Where-Object { $null -eq $_ -or [string]::IsNullOrWhiteSpace([string]$_) })
    if ($ArgumentList.Count -eq 0 -or $nullArgs.Count -gt 0) {
      throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL ffdec_arguments_invalid label=$Label count=$($ArgumentList.Count) null_or_empty=$($nullArgs.Count)"
    }
    Write-Host "WADDLE_PARTY2015_RUNTIME_PATCH_FFDEC label=$Label exe=$FFDec args=$($ArgumentList -join ' ')"
    $proc = Start-Process -FilePath $FFDec -ArgumentList $ArgumentList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit($TimeoutMs)) {
      Stop-FFDecTree $proc
      throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL ffdec_timeout label=$Label"
    }
    $proc.Refresh()
    if ([int]$proc.ExitCode -ne 0) {
      $err = if (Test-Path -LiteralPath $stderr) { (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) } else { '' }
      throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL ffdec_exit=$($proc.ExitCode) label=$Label stderr=$err"
    }
  } finally {
    if ($null -ne $proc -and -not $proc.HasExited) { Stop-FFDecTree $proc }
  }
}

function Export-Scripts([string]$FFDec,[string]$Swf,[string]$Out,[string]$WorkRoot,[string]$Label) {
  if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Out | Out-Null
  $ffdecArgs = @('-cli','-onerror','abort','-exportTimeout','90','-exportFileTimeout','30','-export','script',('"' + $Out + '"'),('"' + $Swf + '"'))
  Invoke-FFDec -FFDec $FFDec -ArgumentList $ffdecArgs -Label $Label -WorkRoot $WorkRoot
}

function Find-NovemberParty([string]$ScriptsRoot) {
  $candidates = @(Get-ChildItem -LiteralPath $ScriptsRoot -Filter 'NovemberParty.as' -File -Recurse -ErrorAction SilentlyContinue)
  foreach ($candidate in $candidates) {
    $text = [IO.File]::ReadAllText($candidate.FullName)
    if ($text -match 'class\s+com\.clubpenguin\.world\.rooms2015\.automated\.party\.NovemberParty') { return $candidate.FullName }
  }
  throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL november_party_source_missing'
}

function Test-PatchedRuntime([string]$FFDec,[string]$Swf,[string]$WorkRoot,[string]$Label) {
  if (-not (Test-Swf $Swf)) { return $false }
  $probe = Join-Path $WorkRoot ($Label + '-scripts')
  Export-Scripts -FFDec $FFdec -Swf $Swf -Out $probe -WorkRoot $WorkRoot -Label ($Label + '-export')
  $partyPath = Find-NovemberParty $probe
  $text = [IO.File]::ReadAllText($partyPath)
  foreach ($needle in @(
    $CompatMarker,
    'static function configureHalloweenRobotRampage',
    'static function pickupItem',
    'static function displayItemPickupInstructions',
    'static function showRobotInstructionsPopup',
    'static function loadMiniGame',
    'static function gameCompleted',
    'activeMiniGameTaskIndex',
    'CONSTANTS.SET_TRANSFORM',
    'static function activateEngineOverrides',
    'static function deactivateEngineOverrides',
    'CONSTANTS.COFFEE_CUP',
    'CONSTANTS.SPELLING_TEST',
    'CONSTANTS.PINK_FLAMINGO',
    'CONSTANTS.INSECTS',
    'CONSTANTS.UGLY_SWEATER',
    'CONSTANTS.BEARD_TRIMMER',
    'CONSTANTS.UFO',
    'CONSTANTS.CLOWN'
  )) {
    if (-not $text.Contains($needle)) { return $false }
  }
  return $true
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$partyRoot = Join-Path $repo 'media\default\party2015'
$base = Join-Path $partyRoot 'content\party-runtime-2015-base.swf'
$live = Join-Path $partyRoot 'content\party-runtime-2015.swf'
if (-not (Test-Swf $base)) { throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL base_missing_or_invalid=$base" }
if ([long](Get-Item -LiteralPath $base).Length -ne $ExpectedBaseBytes) { throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL base_bytes=$((Get-Item -LiteralPath $base).Length)" }
$baseSha = (Get-FileHash -LiteralPath $base -Algorithm SHA256).Hash.ToLowerInvariant()
if ($baseSha -ne $ExpectedBaseSha256) { throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL base_sha256=$baseSha" }

$ffdec = Resolve-FFDec $FFDecPath
$work = Join-Path $repo '.work\halloween2015-runtime-patch'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

if (Test-PatchedRuntime -FFDec $ffdec -Swf $live -WorkRoot $work -Label 'existing-live') {
  Write-Host "WADDLE_PARTY2015_RUNTIME_PATCH=PASS mode=reused marker=$CompatMarker base_sha256=$baseSha live_bytes=$((Get-Item -LiteralPath $live).Length)"
  exit 0
}

$scriptsRoot = Join-Path $work 'base-scripts'
Export-Scripts -FFDec $ffdec -Swf $base -Out $scriptsRoot -WorkRoot $work -Label 'base-export'
$partyPath = Find-NovemberParty $scriptsRoot
$source = [IO.File]::ReadAllText($partyPath)
if ($source.Contains($CompatMarker)) { throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL base_already_patched' }

$className = 'com.clubpenguin.world.rooms2015.automated.party.NovemberParty'

$ctorPattern = '(?m)^(?<indent>\s*)function\s+NovemberParty\s*\(\s*\)\s*\{'
$ctorMatch = [regex]::Match($source,$ctorPattern)
if (-not $ctorMatch.Success) {
  $preview = ($source -replace '\s+',' ')
  if ($preview.Length -gt 1000) { $preview = $preview.Substring(0,1000) }
  throw "WADDLE_PARTY2015_RUNTIME_PATCH=FAIL constructor_anchor_missing preview=$preview"
}
$declIndent = $ctorMatch.Groups['indent'].Value
$compatDecls = @(
  ($declIndent + 'static var WADDLE_HALLOWEEN_2015_COMPAT = "' + $CompatMarker + '";'),
  ($declIndent + 'static var collectedItem = null;'),
  ($declIndent + 'static var collectedItemTaskId = -1;'),
  ($declIndent + 'static var activeMiniGameTaskIndex = -1;')
) -join [Environment]::NewLine
$source = [regex]::Replace(
  $source,
  $ctorPattern,
  [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    return $compatDecls + [Environment]::NewLine + $m.Value
  },
  1
)

$initPattern = '(?m)^(?<line>\s*(?:com\.clubpenguin\.world\.rooms2015\.automated\.party\.NovemberParty\.)?_party\s*=\s*_global\.getCurrentParty\(\);\s*)$'
$initMatch = [regex]::Match($source,$initPattern)
if (-not $initMatch.Success) {
  throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL init_party_anchor_missing'
}
$initIndent = [regex]::Match($initMatch.Groups['line'].Value,'^\s*').Value
$source = [regex]::Replace(
  $source,
  $initPattern,
  [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    return $m.Groups['line'].Value + [Environment]::NewLine + $initIndent + $className + '.configureHalloweenRobotRampage();'
  },
  1
)

$methodPattern = '(?m)^(?<indent>\s*)static\s+function\s+sendBI\s*\('
$methodMatch = [regex]::Match($source,$methodPattern)
if (-not $methodMatch.Success) {
  throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL sendBI_anchor_missing'
}
$methodIndent = $methodMatch.Groups['indent'].Value
$compatMethods = @'
static function configureHalloweenRobotRampage()
{
   if(com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS == undefined)
   {
      return undefined;
   }
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.SET_TRANSFORM = "transform";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.COFFEE_CUP = "h15_coffee_cup";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.SPELLING_TEST = "h15_spelling_test";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.PINK_FLAMINGO = "h15_pink_flamingo";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.INSECTS = "h15_insects";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.UGLY_SWEATER = "h15_ugly_sweater";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.BEARD_TRIMMER = "h15_beard_trimmer";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.UFO = "h15_ufo";
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.CONSTANTS.CLOWN = "h15_clown";
}
static function pickupItem(itemID,taskID)
{
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.collectedItem = itemID;
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.collectedItemTaskId = Number(taskID);
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.sendBI("pickup_" + String(taskID),"halloween2015_quest_item",String(itemID));
   return itemID;
}
static function displayItemPickupInstructions()
{
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.showRobotInstructionsPopup(com.clubpenguin.world.rooms2015.automated.party.NovemberParty.collectedItemTaskId);
}
static function showRobotInstructionsPopup(taskID)
{
   var prompts = ["w.app.p2015.halloween.dialogue_Gary_instruct","w.app.p2015.halloween.dialogue_AA_instruct","w.app.p2015.halloween.dialogue_RH_instruct","w.app.p2015.halloween.dialogue_Cad_instruct","w.app.p2015.halloween.dialogue_Dot_instruct","w.app.p2015.halloween.dialogue_Sen_instruct","w.app.p2015.halloween.dialogue_PH_instruct","w.app.p2015.halloween.dialogue_Rook_instruct"];
   var index = Number(taskID);
   if(index >= 0 && index < prompts.length)
   {
      com.clubpenguin.world.rooms2015.automated.party.NovemberParty._interface.showContent(prompts[index]);
   }
   else
   {
      com.clubpenguin.world.rooms2015.automated.party.NovemberParty._interface.showContent("w.app.generic.partyinterface");
   }
}
static function loadMiniGame(taskIndex)
{
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.activeMiniGameTaskIndex = Number(taskIndex);
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty._interface.showContent("w.app.p2015.halloween.tiles" + String(taskIndex));
}
static function gameCompleted(isWon)
{
   var taskIndex = com.clubpenguin.world.rooms2015.automated.party.NovemberParty.activeMiniGameTaskIndex;
   if(taskIndex == undefined || isNaN(taskIndex) || taskIndex < 0)
   {
      taskIndex = com.clubpenguin.world.rooms2015.automated.party.NovemberParty.partyCookie.getNextAvailableTask();
   }
   if(isWon && taskIndex != undefined)
   {
      com.clubpenguin.world.rooms2015.automated.party.NovemberParty.partyCookie.sendTaskComplete(taskIndex);
      com.clubpenguin.world.rooms2015.automated.party.NovemberParty.collectedItem = null;
      com.clubpenguin.world.rooms2015.automated.party.NovemberParty.collectedItemTaskId = -1;
   }
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty.activeMiniGameTaskIndex = -1;
   com.clubpenguin.world.rooms2015.automated.party.NovemberParty._interface.closeContent();
}
static function activateEngineOverrides()
{
   return true;
}
static function deactivateEngineOverrides()
{
   return true;
}
'@
$compatMethods = (($compatMethods -split '\r?\n') | ForEach-Object { if ($_.Length -gt 0) { $methodIndent + $_ } else { $_ } }) -join [Environment]::NewLine
$source = [regex]::Replace(
  $source,
  $methodPattern,
  [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    return $compatMethods + [Environment]::NewLine + $m.Value
  },
  1
)

[IO.File]::WriteAllText($partyPath,$source,(New-Object System.Text.UTF8Encoding($false)))

$tmp = Join-Path $work 'party-runtime-2015.swf'
$ffdecArgs = @('-cli','-onerror','abort','-importScript',('"' + $base + '"'),('"' + $tmp + '"'),('"' + $scriptsRoot + '"'))
Invoke-FFDec -FFDec $ffdec -ArgumentList $ffdecArgs -Label 'import-script' -WorkRoot $work -TimeoutMs 240000
if (-not (Test-Swf $tmp)) { throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL generated_invalid_swf' }
if (-not (Test-PatchedRuntime -FFDec $ffdec -Swf $tmp -WorkRoot $work -Label 'generated-live')) {
  throw 'WADDLE_PARTY2015_RUNTIME_PATCH=FAIL generated_contract_missing'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $live) | Out-Null
Move-Item -LiteralPath $tmp -Destination $live -Force
$liveSha = (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "WADDLE_PARTY2015_RUNTIME_PATCH=PASS mode=generated marker=$CompatMarker base_sha256=$baseSha live_sha256=$liveSha live_bytes=$((Get-Item -LiteralPath $live).Length)"
