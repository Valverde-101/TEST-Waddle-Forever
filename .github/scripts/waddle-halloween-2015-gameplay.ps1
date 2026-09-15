[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$path = Join-Path $repo 'src\server\socket-server\handlers\puffle.ts'
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
  throw "WADDLE_PARTY2015_GAMEPLAY=FAIL puffle_handler_missing=$path"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [IO.File]::ReadAllText($path) -replace "`r`n", "`n"

$old = @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    (data.isVanillaEngine() && category !== PuffleCategory.Creature) ? 400 : 800;

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);
'@

$new = @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);

  // Creature puffles have event-specific prices in the canonical puffle table.
  // In particular Halloween 2015's Ghost Puffle (1022) is free, while the
  // permanent dog/cat/wild creatures remain 800 coins. Keep the historical
  // normal-puffle pricing behavior unchanged.
  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    category === PuffleCategory.Creature ? puffleInfo.cost :
    data.isVanillaEngine() ? 400 : 800;
'@

if ($text.Contains($old)) {
  $text = $text.Replace($old,$new)
  [IO.File]::WriteAllText($path,$text,$utf8)
} elseif (-not $text.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) {
  throw 'WADDLE_PARTY2015_GAMEPLAY=FAIL creature_price_patch_anchor_missing'
}

$verify = [IO.File]::ReadAllText($path)
if (-not $verify.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) {
  throw 'WADDLE_PARTY2015_GAMEPLAY=FAIL creature_price_patch_missing'
}
if (-not $verify.Contains('const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;')) {
  throw 'WADDLE_PARTY2015_GAMEPLAY=FAIL puffle_type_resolution_missing'
}

Write-Host 'WADDLE_PARTY2015_GAMEPLAY=PASS ghost_puffle=1022 creature_price_source=PUFFLES normal_price_behavior=preserved'
