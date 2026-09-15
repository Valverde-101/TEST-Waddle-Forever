[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Normalized([string]$Path) {
  return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Write-Normalized([string]$Path,[string]$Text) {
  [IO.File]::WriteAllText($Path,($Text -replace "`r`n", "`n"),$utf8)
}

function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  if ($Text.Contains($New)) { return $Text }
  if (-not $Text.Contains($Old)) { throw "WADDLE_PARTY2015_GAMEPLAY=FAIL patch_anchor_missing=$Label" }
  return $Text.Replace($Old,$New)
}

$pufflePath = Join-Path $repo 'src\server\socket-server\handlers\puffle.ts'
$puffle = Read-Normalized $pufflePath
$puffleOld = @'
  const isFreeBrownPuffle = puffleType === 9 && data.isBrownPuffleFree();

  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    (data.isVanillaEngine() && category !== PuffleCategory.Creature) ? 400 : 800;

  const puffleTypeId = puffleSubtype === 0 ? puffleType : puffleSubtype;
  const puffleInfo = PUFFLES.getStrict(puffleTypeId);
'@
$puffleNew = @'
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
$puffle = Replace-Once $puffle $puffleOld $puffleNew 'ghost-puffle-price'
Write-Normalized $pufflePath $puffle

$databasePath = Join-Path $repo 'src\server\database\database.ts'
$database = Read-Normalized $databasePath
$databaseOld = @'
// MEDIEVAL PARTY 2012
  medieval2012Message?: number;

// USER PREFERENCE
'@
$databaseNew = @'
// MEDIEVAL PARTY 2012
  medieval2012Message?: number;

// HALLOWEEN PARTY 2015
  halloween2015?: {
    msgViewedArray: number[];
    communicatorMsgArray: number[];
    questTaskStatus: number[];
  };

// USER PREFERENCE
'@
$database = Replace-Once $database $databaseOld $databaseNew 'penguin-json-halloween2015'
Write-Normalized $databasePath $database

$worldPath = Join-Path $repo 'src\server\socket-server\world\world-penguin.ts'
$world = Read-Normalized $worldPath
$world = Replace-Once $world @'
class UserPreference {
'@ @'
class Halloween2015Status {
  private _messages: number[];
  private _communicator: number[];
  private _tasks: number[];

  constructor(data: PenguinJson) {
    const state = data.halloween2015;
    this._messages = Halloween2015Status.normalize(state?.msgViewedArray, 10);
    this._communicator = Halloween2015Status.normalize(state?.communicatorMsgArray, 5);
    this._tasks = Halloween2015Status.normalize(state?.questTaskStatus, 10);
  }

  private static normalize(values: number[] | undefined, length: number): number[] {
    return Array.from({ length }, (_, index) => values?.[index] === 1 ? 1 : 0);
  }

  private setFlag(values: number[], index: number) {
    if (Number.isInteger(index) && index >= 0 && index < values.length) {
      values[index] = 1;
    }
  }

  public setMessageViewed(index: number) {
    this.setFlag(this._messages, index);
  }

  public setCommunicatorViewed(index: number) {
    this.setFlag(this._communicator, index);
  }

  public setTaskComplete(index: number) {
    this.setFlag(this._tasks, index);
  }

  public get cookie() {
    return {
      msgViewedArray: [...this._messages],
      communicatorMsgArray: [...this._communicator],
      questTaskStatus: [...this._tasks]
    };
  }
}

class UserPreference {
'@ 'world-status-class'
$world = Replace-Once $world @'
  private _medieval2012: Medieval2012Status;
  private _preference: UserPreference;
'@ @'
  private _medieval2012: Medieval2012Status;
  private _halloween2015: Halloween2015Status;
  private _preference: UserPreference;
'@ 'world-private-status'
$world = Replace-Once $world @'
    this._medieval2012 = new Medieval2012Status(json);
    this._preference = new UserPreference(json);
'@ @'
    this._medieval2012 = new Medieval2012Status(json);
    this._halloween2015 = new Halloween2015Status(json);
    this._preference = new UserPreference(json);
'@ 'world-status-constructor'
$world = Replace-Once $world @'
  public get medieval2012() {
    return this._medieval2012;
  }

  public get igloo() {
'@ @'
  public get medieval2012() {
    return this._medieval2012;
  }

  public get halloween2015() {
    return this._halloween2015;
  }

  public get igloo() {
'@ 'world-status-getter'
$world = Replace-Once $world @'
      medieval2012Message: this._medieval2012.message,

      noSave: !this._preference.canSave,
'@ @'
      medieval2012Message: this._medieval2012.message,

      halloween2015: this._halloween2015.cookie,

      noSave: !this._preference.canSave,
'@ 'world-status-json'
Write-Normalized $worldPath $world

$partyPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$party = Read-Normalized $partyPath
if (-not $party.Contains('handleRetrieveHalloween2015')) {
  $party += @'


export const handleRetrieveHalloween2015: PenguinHandler<[]> = ({ penguin, msg }) => {
  msg.send(penguin, 'partycookie', JSON.stringify(penguin.halloween2015.cookie));
}

export const handleHalloween2015MessageViewed: PenguinHandler<[number]> = ({ penguin, prst }, messageIndex) => {
  penguin.halloween2015.setMessageViewed(messageIndex);
  prst(penguin);
}

export const handleHalloween2015CommunicatorViewed: PenguinHandler<[number]> = ({ penguin, prst }, messageIndex) => {
  penguin.halloween2015.setCommunicatorViewed(messageIndex);
  prst(penguin);
}

export const handleHalloween2015TaskComplete: PenguinHandler<[number]> = ({ penguin, prst }, taskIndex) => {
  penguin.halloween2015.setTaskComplete(taskIndex);
  prst(penguin);
}

export const handleHalloween2015TaskUpdate: PenguinHandler<[number]> = ({ penguin, msg, prst }, coins) => {
  const awarded = Math.max(0, Math.min(coins, 10));
  penguin.currency.add(awarded);
  msg.send(penguin, 'qtupdate', penguin.currency.coins);
  prst(penguin);
}
'@
}
Write-Normalized $partyPath $party

$handlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$handlers = Read-Normalized $handlersPath
$handlers = Replace-Once $handlers @'
import { handleDonateCoins, handleGetBakeryState, handleGetCookieInventory, handleRetrieveMedieval2012, handleSendEnterHopper, handleViewedMedieval2012 } from "./handlers/party";
'@ @'
import { handleDonateCoins, handleGetBakeryState, handleGetCookieInventory, handleHalloween2015CommunicatorViewed, handleHalloween2015MessageViewed, handleHalloween2015TaskComplete, handleHalloween2015TaskUpdate, handleRetrieveHalloween2015, handleRetrieveMedieval2012, handleSendEnterHopper, handleViewedMedieval2012 } from "./handlers/party";
'@ 'world-handlers-party-import'
$handlers = Replace-Once $handlers @'
    p.xt('s', 'mdvl#retrieve', [], handleRetrieveMedieval2012),
    p.xt('s', 'mdvl#msgviewed', ['number'], handleViewedMedieval2012),

    p.xt('s', 'ba#barsu', [], handleGetBakeryState),
'@ @'
    p.xt('s', 'mdvl#retrieve', [], handleRetrieveMedieval2012),
    p.xt('s', 'mdvl#msgviewed', ['number'], handleViewedMedieval2012),

    p.xt('s', 'party#partycookie', [], handleRetrieveHalloween2015),
    p.xt('s', 'party#msgviewed', ['number'], handleHalloween2015MessageViewed),
    p.xt('s', 'party#qcmsgviewed', ['number'], handleHalloween2015CommunicatorViewed),
    p.xt('s', 'party#qtaskcomplete', ['number'], handleHalloween2015TaskComplete),
    p.xt('s', 'party#qtupdate', ['number'], handleHalloween2015TaskUpdate),

    p.xt('s', 'ba#barsu', [], handleGetBakeryState),
'@ 'world-handlers-party-routes'
Write-Normalized $handlersPath $handlers

$checks = @(
  @{ path=$pufflePath; token='category === PuffleCategory.Creature ? puffleInfo.cost' },
  @{ path=$databasePath; token='halloween2015?: {' },
  @{ path=$worldPath; token='class Halloween2015Status' },
  @{ path=$partyPath; token='handleRetrieveHalloween2015' },
  @{ path=$handlersPath; token="party#qtaskcomplete" }
)
foreach ($check in $checks) {
  if (-not ([IO.File]::ReadAllText($check.path).Contains($check.token))) {
    throw "WADDLE_PARTY2015_GAMEPLAY=FAIL verification_missing=$($check.token) file=$($check.path)"
  }
}

# The self-hosted PR publisher commits every gameplay file atomically with the
# versioned party assets. `git add` is a no-op when this script is later reused
# as an idempotence gate on already-integrated source.
& git -C $repo add -- `
  'src/server/socket-server/handlers/puffle.ts' `
  'src/server/database/database.ts' `
  'src/server/socket-server/world/world-penguin.ts' `
  'src/server/socket-server/handlers/party.ts' `
  'src/server/socket-server/world-handlers.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY2015_GAMEPLAY=FAIL git_add_exit=$LASTEXITCODE" }

Write-Host 'WADDLE_PARTY2015_GAMEPLAY=PASS ghost_puffle=1022 partycookie=persistent quest_tasks=10 messages=10 communicator=5 packets=5 staged=true'
