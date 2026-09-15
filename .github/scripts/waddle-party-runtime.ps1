[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-N([string]$Path) {
  return ([IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}
function Write-N([string]$Path,[string]$Text) {
  [IO.File]::WriteAllText($Path,($Text -replace "`r`n", "`n"),$utf8)
}
function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
  if ($Text.Contains($New)) { return $Text }
  if (-not $Text.Contains($Old)) { throw "WADDLE_PARTY_RUNTIME=FAIL anchor=$Label" }
  return $Text.Replace($Old,$New)
}

# Persistence schema shared by every modern party.
$dbPath = Join-Path $repo 'src/server/database/database.ts'
$db = Read-N $dbPath
$db = [regex]::Replace($db,'(?m)^import \{ MASCOTS \} from \\\s*$','import { MASCOTS } from "@server/game-data/mascots";`nimport { PartyProgressStoreData } from "@server/game-data/party";')
if (-not $db.Contains('PartyProgressStoreData')) {
  $db = Replace-Once $db 'import { MASCOTS } from "@server/game-data/mascots";' @'
import { MASCOTS } from "@server/game-data/mascots";
import { PartyProgressStoreData } from "@server/game-data/party";
'@.TrimEnd() 'database-import'
}
if (-not $db.Contains('partyProgress?: PartyProgressStoreData;')) {
  $db = Replace-Once $db @'
// MEDIEVAL PARTY 2012
  medieval2012Message?: number;
'@ @'
// MEDIEVAL PARTY 2012
  medieval2012Message?: number;

// MODERN PARTY PROGRESS
  partyProgress?: PartyProgressStoreData;
'@ 'database-state'
}
Write-N $dbPath $db

# Penguin entity owns one generic store keyed by party id.
$worldPath = Join-Path $repo 'src/server/socket-server/world/world-penguin.ts'
$world = Read-N $worldPath
$world = [regex]::Replace($world,'(?m)^import \{ CardJitsuFireProgress, CardJitsuProgress \} from \\\s*$','import { CardJitsuFireProgress, CardJitsuProgress } from "@server/game-logic/ninja-progress";`nimport { PartyProgressStore } from "@server/game-logic/party-progress";')
if (-not $world.Contains('import { PartyProgressStore } from "@server/game-logic/party-progress";')) {
  $world = Replace-Once $world 'import { CardJitsuFireProgress, CardJitsuProgress } from "@server/game-logic/ninja-progress";' @'
import { CardJitsuFireProgress, CardJitsuProgress } from "@server/game-logic/ninja-progress";
import { PartyProgressStore } from "@server/game-logic/party-progress";
'@.TrimEnd() 'world-import'
}
if ($world.Contains('class Halloween2015Status {')) {
  $world = [regex]::Replace($world,'(?s)\nclass Halloween2015Status \{.*?\n\}\n\nclass UserPreference \{',"`nclass UserPreference {",1)
}
$world = $world.Replace('  private _halloween2015: Halloween2015Status;', '  private _partyProgress: PartyProgressStore;')
$world = $world.Replace('    this._halloween2015 = new Halloween2015Status(json);', '    this._partyProgress = new PartyProgressStore(json.partyProgress);')
$world = $world.Replace("  public get halloween2015() {`n    return this._halloween2015;`n  }", "  public get partyProgress() {`n    return this._partyProgress;`n  }")
$world = $world.Replace('      halloween2015: this._halloween2015.cookie,', '      partyProgress: this._partyProgress.data,')
Write-N $worldPath $world

# Timeline schema declares behavior instead of hardcoding a party in handlers.
$updatesPath = Join-Path $repo 'src/server/updates/index.ts'
$updates = Read-N $updatesPath
$updates = [regex]::Replace($updates,'(?m)^import \{ RoomName \} from \\\s*$','import { RoomName } from "../game-data/rooms";`nimport { PartyProgressConfig } from "../game-data/party";')
if (-not $updates.Contains('import { PartyProgressConfig } from "../game-data/party";')) {
  $updates = Replace-Once $updates 'import { RoomName } from "../game-data/rooms";' @'
import { RoomName } from "../game-data/rooms";
import { PartyProgressConfig } from "../game-data/party";
'@.TrimEnd() 'updates-import'
}
if (-not $updates.Contains('gameStringChanges?: Record<string, string>;')) {
  $updates = Replace-Once $updates '  gameStrings?: Record<string, string>;' @'
  gameStrings?: Record<string, string>;
  /** Merge-only localization overlay, useful for temporary parties. */
  gameStringChanges?: Record<string, string>;

  /** Shared modern party-cookie protocol configuration. */
  partyProgress?: PartyProgressConfig;
'@.TrimEnd() 'updates-schema'
}
Write-N $updatesPath $updates

# GameData activates the config for the selected timeline date and merges party strings.
$gameDataPath = Join-Path $repo 'src/server/timelines/game-data.ts'
$gameData = Read-N $gameDataPath
$gameData = [regex]::Replace($gameData,'(?m)^import \{ WaddleRoomInfo \} from \\\s*$','import { WaddleRoomInfo } from "@server/game-logic/waddles";`nimport { PartyProgressConfig } from "@server/game-data/party";')
if (-not $gameData.Contains('import { PartyProgressConfig } from "@server/game-data/party";')) {
  $gameData = Replace-Once $gameData 'import { WaddleRoomInfo } from "@server/game-logic/waddles";' @'
import { WaddleRoomInfo } from "@server/game-logic/waddles";
import { PartyProgressConfig } from "@server/game-data/party";
'@.TrimEnd() 'game-data-import'
}
if (-not $gameData.Contains('partyProgress: PartyProgressConfig | null;')) {
  $gameData = Replace-Once $gameData '  gameStrings: Map<string, string>;' "  gameStrings: Map<string, string>;`n  partyProgress: PartyProgressConfig | null;" 'game-data-state'
}
if (-not $gameData.Contains('partyProgress: null,')) {
  $gameData = Replace-Once $gameData '    gameStrings: new Map<string, string>(),' "    gameStrings: new Map<string, string>(),`n    partyProgress: null," 'game-data-default'
}
if (-not $gameData.Contains("'gameStringChanges': (v) =>")) {
  $gameData = Replace-Once $gameData @'
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
  $gameData = Replace-Once $gameData @'
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
Write-N $gameDataPath $gameData

# Generic packet handlers. The active timeline config chooses storage key and sizes.
$partyPath = Join-Path $repo 'src/server/socket-server/handlers/party.ts'
$party = Read-N $partyPath
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
  if (config !== null && penguin.partyProgress.setMessageViewed(config, messageIndex)) prst(penguin);
}

export const handlePartyCommunicatorViewed: PenguinHandler<[number]> = ({ penguin, prst, data }, messageIndex) => {
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setCommunicatorViewed(config, messageIndex)) prst(penguin);
}

export const handlePartyTaskComplete: PenguinHandler<[number]> = ({ penguin, prst, data }, taskIndex) => {
  const config = data.getPartyProgress();
  if (config !== null && penguin.partyProgress.setTaskComplete(config, taskIndex)) prst(penguin);
}

export const handlePartyTaskUpdate: PenguinHandler<[number]> = ({ penguin, msg, prst, data }, coins) => {
  const config = data.getPartyProgress();
  if (config === null) return;
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
Write-N $partyPath $party

$handlersPath = Join-Path $repo 'src/server/socket-server/world-handlers.ts'
$handlers = Read-N $handlersPath
$handlers = $handlers.Replace('handleHalloween2015CommunicatorViewed, handleHalloween2015MessageViewed, handleHalloween2015TaskComplete, handleHalloween2015TaskUpdate, handleRetrieveHalloween2015', 'handlePartyCommunicatorViewed, handlePartyMessageViewed, handlePartyTaskComplete, handlePartyTaskUpdate, handleRetrievePartyCookie')
$handlers = $handlers.Replace('handleRetrieveHalloween2015)', 'handleRetrievePartyCookie)')
$handlers = $handlers.Replace('handleHalloween2015MessageViewed)', 'handlePartyMessageViewed)')
$handlers = $handlers.Replace('handleHalloween2015CommunicatorViewed)', 'handlePartyCommunicatorViewed)')
$handlers = $handlers.Replace('handleHalloween2015TaskComplete)', 'handlePartyTaskComplete)')
$handlers = $handlers.Replace('handleHalloween2015TaskUpdate)', 'handlePartyTaskUpdate)')
Write-N $handlersPath $handlers

$required = @(
  @{ path=$dbPath; token='import { PartyProgressStoreData } from "@server/game-data/party";' },
  @{ path=$worldPath; token='import { PartyProgressStore } from "@server/game-logic/party-progress";' },
  @{ path=$updatesPath; token='partyProgress?: PartyProgressConfig;' },
  @{ path=$gameDataPath; token='public getPartyProgress()' },
  @{ path=$partyPath; token='handleRetrievePartyCookie' },
  @{ path=$handlersPath; token="party#qtaskcomplete" }
)
foreach ($check in $required) {
  $text = Read-N $check.path
  if (-not $text.Contains($check.token)) { throw "WADDLE_PARTY_RUNTIME=FAIL missing=$($check.token) file=$($check.path)" }
  if ($text -match '(?m)^import .* from \\\s*$') { throw "WADDLE_PARTY_RUNTIME=FAIL malformed_import file=$($check.path)" }
}
if ((Read-N $worldPath).Contains('Halloween2015Status')) { throw 'WADDLE_PARTY_RUNTIME=FAIL one_off_status_remains' }
if ((Read-N $partyPath).Contains('handleRetrieveHalloween2015')) { throw 'WADDLE_PARTY_RUNTIME=FAIL one_off_handler_remains' }

& git -C $repo add -- `
  'src/server/game-data/party.ts' `
  'src/server/game-logic/party-progress.ts' `
  'src/server/database/database.ts' `
  'src/server/socket-server/world/world-penguin.ts' `
  'src/server/updates/index.ts' `
  'src/server/timelines/game-data.ts' `
  'src/server/socket-server/handlers/party.ts' `
  'src/server/socket-server/world-handlers.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY_RUNTIME=FAIL git_add_exit=$LASTEXITCODE" }

Write-Host 'WADDLE_PARTY_RUNTIME=PASS architecture=data_driven persistence=per_party_id packets=5 localization=merge staged=true'
