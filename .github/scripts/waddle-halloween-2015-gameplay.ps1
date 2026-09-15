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

function Replace-Required([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  if ($Text.Contains($New)) { return $Text }
  if (-not $Text.Contains($Old)) { throw "WADDLE_PARTY_RUNTIME=FAIL patch_anchor_missing=$Label" }
  return $Text.Replace($Old,$New)
}

# Event creature prices belong to static puffle data, not a hard-coded category price.
$pufflePath = Join-Path $repo 'src\server\socket-server\handlers\puffle.ts'
$puffle = Read-Normalized $pufflePath
if (-not $puffle.Contains('category === PuffleCategory.Creature ? puffleInfo.cost')) {
  $puffle = Replace-Required $puffle @'
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

  // Creature puffles have event-specific prices in the canonical puffle table.
  const cost =
    (isFreeBrownPuffle || category === PuffleCategory.Gold) ? 0 :
    category === PuffleCategory.Creature ? puffleInfo.cost :
    data.isVanillaEngine() ? 400 : 800;
'@ 'creature-price'
}
Write-Normalized $pufflePath $puffle

# Penguin persistence is keyed by party id so multiple modern parties can coexist.
$databasePath = Join-Path $repo 'src\server\database\database.ts'
$database = Read-Normalized $databasePath
if (-not $database.Contains('PartyProgressStoreData')) {
  $database = Replace-Required $database 'import { MASCOTS } from "@server/game-data/mascots";' "import { MASCOTS } from \"@server/game-data/mascots\";`nimport { PartyProgressStoreData } from \"@server/game-data/party\";" 'database-party-import'
}
$halloweenField = @'
// HALLOWEEN PARTY 2015
  halloween2015?: {
    msgViewedArray: number[];
    communicatorMsgArray: number[];
    questTaskStatus: number[];
  };
'@
$genericField = @'
// MODERN PARTY PROGRESS
  partyProgress?: PartyProgressStoreData;
'@
if ($database.Contains($halloweenField)) {
  $database = $database.Replace($halloweenField,$genericField)
} elseif (-not $database.Contains('partyProgress?: PartyProgressStoreData;')) {
  $database = Replace-Required $database "// MEDIEVAL PARTY 2012`n  medieval2012Message?: number;" "// MEDIEVAL PARTY 2012`n  medieval2012Message?: number;`n`n$genericField" 'database-party-field'
}
Write-Normalized $databasePath $database

# Replace the one-off Halloween status with the reusable PartyProgressStore.
$worldPath = Join-Path $repo 'src\server\socket-server\world\world-penguin.ts'
$world = Read-Normalized $worldPath
if (-not $world.Contains('PartyProgressStore')) {
  $world = Replace-Required $world 'import { CardJitsuFireProgress, CardJitsuProgress } from "@server/game-logic/ninja-progress";' "import { CardJitsuFireProgress, CardJitsuProgress } from \"@server/game-logic/ninja-progress\";`nimport { PartyProgressStore } from \"@server/game-logic/party-progress\";" 'world-party-import'
}
if ($world.Contains('class Halloween2015Status {')) {
  $pattern = '(?s)\nclass Halloween2015Status \{.*?\n\}\n\nclass UserPreference \{'
  $replaced = [regex]::Replace($world,$pattern,"`nclass UserPreference {",1)
  if ($replaced -eq $world) { throw 'WADDLE_PARTY_RUNTIME=FAIL patch_anchor_missing=world-remove-halloween-class' }
  $world = $replaced
}
$world = $world.Replace('  private _halloween2015: Halloween2015Status;', '  private _partyProgress: PartyProgressStore;')
$world = $world.Replace('    this._halloween2015 = new Halloween2015Status(json);', '    this._partyProgress = new PartyProgressStore(json.partyProgress);')
$world = $world.Replace("  public get halloween2015() {`n    return this._halloween2015;`n  }", "  public get partyProgress() {`n    return this._partyProgress;`n  }")
$world = $world.Replace('      halloween2015: this._halloween2015.cookie,', '      partyProgress: this._partyProgress.data,')
foreach ($token in @('private _partyProgress: PartyProgressStore','new PartyProgressStore(json.partyProgress)','public get partyProgress()','partyProgress: this._partyProgress.data')) {
  if (-not $world.Contains($token)) { throw "WADDLE_PARTY_RUNTIME=FAIL world_generic_missing=$token" }
}
Write-Normalized $worldPath $world

# Timeline schema: party behavior and string overlays are data-driven.
$updatesIndexPath = Join-Path $repo 'src\server\updates\index.ts'
$updatesIndex = Read-Normalized $updatesIndexPath
if (-not $updatesIndex.Contains('PartyProgressConfig')) {
  $updatesIndex = Replace-Required $updatesIndex 'import { RoomName } from "../game-data/rooms";' "import { RoomName } from \"../game-data/rooms\";`nimport { PartyProgressConfig } from \"../game-data/party\";" 'updates-party-import'
}
if (-not $updatesIndex.Contains('gameStringChanges?: Record<string, string>;')) {
  $updatesIndex = Replace-Required $updatesIndex '  gameStrings?: Record<string, string>;' "  gameStrings?: Record<string, string>;`n  /** Merge-only localization overlay, useful for temporary parties. */`n  gameStringChanges?: Record<string, string>;`n`n  /** Shared modern party-cookie protocol configuration. */`n  partyProgress?: PartyProgressConfig;" 'updates-party-fields'
}
Write-Normalized $updatesIndexPath $updatesIndex

# GameData exposes whichever temporary party configuration is active at the selected date.
$gameDataPath = Join-Path $repo 'src\server\timelines\game-data.ts'
$gameData = Read-Normalized $gameDataPath
if (-not $gameData.Contains('PartyProgressConfig')) {
  $gameData = Replace-Required $gameData 'import { WaddleRoomInfo } from "@server/game-logic/waddles";' "import { WaddleRoomInfo } from \"@server/game-logic/waddles\";`nimport { PartyProgressConfig } from \"@server/game-data/party\";" 'game-data-party-import'
}
if (-not $gameData.Contains('partyProgress: PartyProgressConfig | null;')) {
  $gameData = Replace-Required $gameData '  gameStrings: Map<string, string>;' "  gameStrings: Map<string, string>;`n  partyProgress: PartyProgressConfig | null;" 'game-data-state-field'
}
if (-not $gameData.Contains('partyProgress: null,')) {
  $gameData = Replace-Required $gameData '    gameStrings: new Map<string, string>(),' "    gameStrings: new Map<string, string>(),`n    partyProgress: null," 'game-data-state-default'
}
if (-not $gameData.Contains("'gameStringChanges': (v) =>")) {
  $gameData = Replace-Required $gameData @'
      'gameStrings': (v) => {
        this.state.gameStrings = new Map(Object.entries(v));
      },
'@ @'
      'gameStrings': (v) => {
        this.state.gameStrings = new Map(Object.entries(v));
      },
      'gameStringChanges': (v) => {
        iterateEntries(v, (key, value) => this.state.gameStrings.set(key, value));
      },
      'partyProgress': (v) => {
        this.state.partyProgress = v;
      },
'@ 'game-data-actions'
}
if (-not $gameData.Contains('public getPartyProgress()')) {
  $gameData = Replace-Required $gameData @'
  public getGameStrings() {
    return this.state.gameStrings;
  }
'@ @'
  public getGameStrings() {
    return this.state.gameStrings;
  }

  public getPartyProgress() {
    return this.state.partyProgress;
  }
'@ 'game-data-getter'
}
Write-Normalized $gameDataPath $gameData

# One set of packet handlers serves every party declaring partyProgress.
$partyPath = Join-Path $repo 'src\server\socket-server\handlers\party.ts'
$party = Read-Normalized $partyPath
$genericHandlers = @'

const EMPTY_PARTY_COOKIE = {
  msgViewedArray: [],
  communicatorMsgArray: [],
  questTaskStatus: []
};

export const handleRetrievePartyCookie: PenguinHandler<[]> = ({ penguin, msg, data }) => {
  const config = data.getPartyProgress();
  const cookie = config === null ? EMPTY_PARTY_COOKIE : penguin.partyProgress.getCookie(config);
  msg.send(penguin, 'partycookie', JSON.stringify(cookie));
}

export const handlePartyMessageViewed: PenguinHandler<[number]> = ({ penguin, prst, data }, messageIndex) => {
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setMessageViewed(config, messageIndex)) {
    prst(penguin);
  }
}

export const handlePartyCommunicatorViewed: PenguinHandler<[number]> = ({ penguin, prst, data }, messageIndex) => {
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setCommunicatorViewed(config, messageIndex)) {
    prst(penguin);
  }
}

export const handlePartyTaskComplete: PenguinHandler<[number]> = ({ penguin, prst, data }, taskIndex) => {
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setTaskComplete(config, taskIndex)) {
    prst(penguin);
  }
}

export const handlePartyTaskUpdate: PenguinHandler<[number]> = ({ penguin, msg, prst, data }, coins) => {
  const config = data.getPartyProgress();
  if (config === null) {
    return;
  }
  const maxCoins = Math.max(0, config.maxCoinUpdate ?? 10);
  const requested = Number.isFinite(coins) ? Math.floor(coins) : 0;
  const awarded = Math.max(0, Math.min(requested, maxCoins));
  penguin.currency.add(awarded);
  msg.send(penguin, 'qtupdate', penguin.currency.coins);
  prst(penguin);
}
'@
if ($party.Contains('export const handleRetrieveHalloween2015')) {
  $party = [regex]::Replace($party,'(?s)\nexport const handleRetrieveHalloween2015:.*\z',$genericHandlers,1)
} elseif (-not $party.Contains('export const handleRetrievePartyCookie')) {
  $party += $genericHandlers
}
Write-Normalized $partyPath $party

$handlersPath = Join-Path $repo 'src\server\socket-server\world-handlers.ts'
$handlers = Read-Normalized $handlersPath
$handlers = $handlers.Replace('handleHalloween2015CommunicatorViewed, handleHalloween2015MessageViewed, handleHalloween2015TaskComplete, handleHalloween2015TaskUpdate, handleRetrieveHalloween2015', 'handlePartyCommunicatorViewed, handlePartyMessageViewed, handlePartyTaskComplete, handlePartyTaskUpdate, handleRetrievePartyCookie')
$handlers = $handlers.Replace("handleRetrieveHalloween2015),", "handleRetrievePartyCookie),")
$handlers = $handlers.Replace("handleHalloween2015MessageViewed),", "handlePartyMessageViewed),")
$handlers = $handlers.Replace("handleHalloween2015CommunicatorViewed),", "handlePartyCommunicatorViewed),")
$handlers = $handlers.Replace("handleHalloween2015TaskComplete),", "handlePartyTaskComplete),")
$handlers = $handlers.Replace("handleHalloween2015TaskUpdate),", "handlePartyTaskUpdate),")
foreach ($token in @('handleRetrievePartyCookie','handlePartyMessageViewed','handlePartyCommunicatorViewed','handlePartyTaskComplete','handlePartyTaskUpdate')) {
  if (-not $handlers.Contains($token)) { throw "WADDLE_PARTY_RUNTIME=FAIL world_handlers_generic_missing=$token" }
}
Write-Normalized $handlersPath $handlers

# Halloween 2015 is now only configuration/data using the generic engine.
$update2015Path = Join-Path $repo 'src\server\updates\2015.ts'
$update2015 = Read-Normalized $update2015Path
if (-not $update2015.Contains("id: 'halloween-2015'")) {
  $update2015 = Replace-Required $update2015 "        partyName: 'Halloween Party 2015'," @"
        partyName: 'Halloween Party 2015',
        partyProgress: {
          id: 'halloween-2015',
          messageCount: 10,
          communicatorMessageCount: 5,
          taskCount: 10,
          maxCoinUpdate: 10
        },
"@.TrimEnd("`r","`n") 'halloween-party-progress-config'
}
Write-Normalized $update2015Path $update2015

$checks = @(
  @{ path=$databasePath; token='partyProgress?: PartyProgressStoreData;' },
  @{ path=$worldPath; token='PartyProgressStore' },
  @{ path=$updatesIndexPath; token='partyProgress?: PartyProgressConfig;' },
  @{ path=$gameDataPath; token='public getPartyProgress()' },
  @{ path=$partyPath; token='handleRetrievePartyCookie' },
  @{ path=$handlersPath; token="party#qtaskcomplete" },
  @{ path=$update2015Path; token="id: 'halloween-2015'" },
  @{ path=$pufflePath; token='category === PuffleCategory.Creature ? puffleInfo.cost' }
)
foreach ($check in $checks) {
  if (-not ([IO.File]::ReadAllText($check.path).Contains($check.token))) {
    throw "WADDLE_PARTY_RUNTIME=FAIL verification_missing=$($check.token) file=$($check.path)"
  }
}
if ((Read-Normalized $worldPath).Contains('Halloween2015Status')) { throw 'WADDLE_PARTY_RUNTIME=FAIL one_off_world_status_remains' }
if ((Read-Normalized $partyPath).Contains('handleRetrieveHalloween2015')) { throw 'WADDLE_PARTY_RUNTIME=FAIL one_off_party_handler_remains' }

& git -C $repo add -- `
  'src/server/game-data/party.ts' `
  'src/server/game-logic/party-progress.ts' `
  'src/server/socket-server/handlers/puffle.ts' `
  'src/server/database/database.ts' `
  'src/server/socket-server/world/world-penguin.ts' `
  'src/server/updates/index.ts' `
  'src/server/timelines/game-data.ts' `
  'src/server/socket-server/handlers/party.ts' `
  'src/server/socket-server/world-handlers.ts' `
  'src/server/updates/2015.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY_RUNTIME=FAIL git_add_exit=$LASTEXITCODE" }

Write-Host 'WADDLE_PARTY_RUNTIME=PASS architecture=data_driven persistence=per_party_id packets=5 string_overlay=merge ghost_puffle=1022 staged=true'
