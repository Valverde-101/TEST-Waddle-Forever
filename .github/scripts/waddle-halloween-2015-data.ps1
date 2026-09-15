[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-N([string]$Path) { return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n") }
function Write-N([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,($Text -replace "`r`n", "`n"),$utf8) }
function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  if ($Text.Contains($New)) { return $Text }
  if (-not $Text.Contains($Old)) { throw "WADDLE_HALLOWEEN2015_DATA=FAIL anchor=$Label" }
  return $Text.Replace($Old,$New)
}

# The party's Ghost Puffle is a creature subtype with canonical price 0.
# Generic creature pricing must respect PUFFLES so other event creatures can
# declare their own price without another handler special case.
$pufflePath = Join-Path $repo 'src/server/socket-server/handlers/puffle.ts'
$puffle = Read-N $pufflePath
if (-not $puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) {
  $puffle = Replace-Once $puffle @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    (data.isVanillaEngine() && category !== PuffleCategory.Creature) ? 400 : 800;

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);
'@ @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);

  // Event creature prices are data-driven by PUFFLES (Ghost 1022 is free).
  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    category === PuffleCategory.Creature ? puffleInfo.cost :
    data.isVanillaEngine() ? 400 : 800;
'@ 'creature-price'
}
Write-N $pufflePath $puffle

$updatesPath = Join-Path $repo 'src/server/updates/2015.ts'
$updates = Read-N $updatesPath
if (-not $updates.Contains("id: 'halloween-2015'")) {
  $updates = Replace-Once $updates "        partyName: 'Halloween Party 2015'," @'
        partyName: 'Halloween Party 2015',
        partyProgress: {
          id: 'halloween-2015',
          messageCount: 10,
          communicatorMessageCount: 5,
          taskCount: 10,
          maxCoinUpdate: 10
        },
'@.TrimEnd() 'party-progress'
}
Write-N $updatesPath $updates

if (-not (Read-N $updatesPath).Contains("id: 'halloween-2015'")) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL party_progress_missing' }
if (-not (Read-N $pufflePath).Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL ghost_puffle_price_missing' }

& git -C $repo add -- 'src/server/updates/2015.ts' 'src/server/socket-server/handlers/puffle.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_HALLOWEEN2015_DATA=FAIL git_add_exit=$LASTEXITCODE" }
Write-Host 'WADDLE_HALLOWEEN2015_DATA=PASS party=halloween-2015 tasks=10 ghost_puffle=1022 staged=true'
