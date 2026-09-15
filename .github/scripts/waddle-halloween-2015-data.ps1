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

# Creature puffle prices are canonical game data, not party-handler special cases.
# This makes Ghost Puffle 1022 free because PUFFLES declares cost 0 while the
# permanent dog/cat/wild creature prices continue to come from the same table.
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

# Halloween 2015 only declares configuration consumed by the reusable modern
# party runtime. Future parties can provide a different id/counts without new
# status classes or packet handlers.
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

# Modern interface.swf does two independent things for its party button:
# general.json enables party_icon_active, then showPartyIcon("party_icon") asks
# the shell/global crumbs for the path named party_icon. A bare fileChanges route
# satisfies only the first half. Materialize the icon through Waddle's reusable
# globalChanges/CrumbIndicator mechanism so any equivalent modern party can use
# the same runtime behavior without event-specific interface code.
$iconAsset = "P + 'content/ContentParty_icon-HalloweenParty2015.swf'"
$iconCrumb = "          'content/party_icon.swf': [$iconAsset, 'party_icon']"
$legacyIconLine = "          'play/v2/content/global/content/party_icon.swf': $iconAsset,`n"
if ($updates.Contains($legacyIconLine)) {
  $updates = $updates.Replace($legacyIconLine,'')
}
if (-not $updates.Contains($iconCrumb)) {
  $globalBlock = @'
        globalChanges: {
          'content/party_icon.swf': [P + 'content/ContentParty_icon-HalloweenParty2015.swf', 'party_icon']
        },
'@
  if ($updates.Contains('        globalChanges: {')) {
    $updates = [regex]::Replace(
      $updates,
      [regex]::Escape('        globalChanges: {'),
      [System.Text.RegularExpressions.MatchEvaluator]{ param($m) "        globalChanges: {`n$iconCrumb," },
      1
    )
  } else {
    $updates = Replace-Once $updates '        localChanges: {' ($globalBlock + '        localChanges: {') 'party-icon-global-crumb'
  }
}

# A previous iteration inserted reconstructed/later-fan game strings and treated
# them as original 2015 localization. Remove that block. The generic
# gameStringChanges capability remains available, but this party must only use
# values backed by an archived 2015 game_strings source.
$unverifiedOverlay = '(?s)\n        gameStringChanges: \{\n(?:(?!\n        \},).)*w\.app\.p2015\.halloween(?:(?!\n        \},).)*\n        \},'
if ([regex]::IsMatch($updates,$unverifiedOverlay)) {
  $updates = [regex]::Replace($updates,$unverifiedOverlay,'',1)
}
Write-N $updatesPath $updates

$verifyUpdates = Read-N $updatesPath
if (-not $verifyUpdates.Contains("id: 'halloween-2015'")) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL party_progress_missing' }
if (-not $verifyUpdates.Contains($iconCrumb)) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL party_icon_global_crumb_missing' }
if ($verifyUpdates.Contains("'play/v2/content/global/content/party_icon.swf': $iconAsset")) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL party_icon_legacy_route_remains' }
if ($verifyUpdates -match 'gameStringChanges:\s*\{(?s:.*?)w\.app\.p2015\.halloween') {
  throw 'WADDLE_HALLOWEEN2015_DATA=FAIL unverified_halloween_strings_remain'
}
if (-not (Read-N $pufflePath).Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) { throw 'WADDLE_HALLOWEEN2015_DATA=FAIL ghost_puffle_price_missing' }

& git -C $repo add -- 'src/server/updates/2015.ts' 'src/server/socket-server/handlers/puffle.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_HALLOWEEN2015_DATA=FAIL git_add_exit=$LASTEXITCODE" }
Write-Host 'WADDLE_HALLOWEEN2015_DATA=PASS party=halloween-2015 tasks=10 localization=evidence-required ghost_puffle=1022 party_icon=global_crumb staged=true'