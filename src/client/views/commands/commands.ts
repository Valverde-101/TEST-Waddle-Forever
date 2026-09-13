import { BrowserWindow, ipcMain } from "electron";
import path from "path";
import { getPopupCreator } from "@client/popups";
import { instrumentRuntimeWindow, writeRuntimeDiagnostic } from "@client/runtime-diagnostics";
import { createCommandsList } from "../commandslist/commandslist";
import { getCommandsList } from "@server/commands/commands";
import { ITEMS } from "@server/game-logic/items";
import { FURNITURE } from "@server/game-logic/furniture";
import { ROOMS } from "@server/game-data/rooms";

const GET_DATA_CHANNEL = 'command-center:get-data';
const GET_STATE_CHANNEL = 'command-center:get-state';
const SEARCH_CATALOG_CHANNEL = 'command-center:search-catalog';
const RUN_COMMAND_CHANNEL = 'command-center:run-command';

type LivePenguin = {
  id: number;
  name: string;
};

type CommandServer = {
  getAllPlayersInfo: () => Array<{ name: string; id: number }>;
  runCommand: (penguinId: number, name: string, args: string[]) => boolean;
};

const getLivePenguins = (server: CommandServer): LivePenguin[] => {
  return server.getAllPlayersInfo()
    .filter(player => Number.isInteger(player.id) && player.id > 0 && typeof player.name === 'string' && player.name.trim() !== '')
    .map(player => ({ id: player.id, name: player.name.trim() }));
};

/**
 * Waddle is a single-player client. Commands therefore target the penguin that
 * is currently connected to the local WorldServer. The renderer never chooses
 * a name or id; target resolution happens again at dispatch time so stale UI
 * state cannot send a command to the wrong profile.
 */
const getActivePenguin = (server: CommandServer): LivePenguin | null => {
  const players = getLivePenguins(server);
  if (players.length === 0) return null;
  return players[0];
};

const getCommandCenterData = () => ({
  commands: getCommandsList()
});

const matchesCatalogQuery = (id: number, name: string, query: string) => {
  if (query === '') return true;
  return String(id).includes(query) || name.toLowerCase().includes(query);
};

const searchCatalog = (kind: string, rawQuery: string, rawLimit: number) => {
  const query = typeof rawQuery === 'string' ? rawQuery.trim().toLowerCase() : '';
  const limit = Number.isInteger(rawLimit) ? Math.max(1, Math.min(rawLimit, 60)) : 30;

  if (kind === 'items') {
    return ITEMS.rows
      .filter(item => matchesCatalogQuery(item.id, item.name, query))
      .slice(0, limit)
      .map(item => ({
        id: item.id,
        name: item.name,
        type: item.type,
        cost: item.cost,
        member: item.isMember
      }));
  }

  if (kind === 'furniture') {
    return FURNITURE.rows
      .filter(item => matchesCatalogQuery(item.id, item.name, query))
      .slice(0, limit)
      .map(item => ({
        id: item.id,
        name: item.name,
        type: item.type,
        cost: item.cost,
        member: item.member
      }));
  }

  if (kind === 'rooms') {
    return Object.entries(ROOMS)
      .map(([name, info]) => ({ name, id: info.id }))
      .filter(room => matchesCatalogQuery(room.id, room.name, query))
      .slice(0, limit);
  }

  return [];
};

type WindowBounds = { x: number; y: number; width: number; height: number };

/**
 * The Command Center is an auxiliary tool, not a second full application.
 * Keep it at roughly one third of the game's visible area: one third of the
 * game width and about 82% of its height. This leaves most of Club Penguin
 * visible while still providing enough vertical room for command controls.
 * Electron bounds are expressed in DIP, so the ratio stays correct on Windows
 * display scaling (125%, 150%, 175%, etc.).
 */
const getCommandCenterBounds = (mainWindow: BrowserWindow): WindowBounds => {
  const parent = mainWindow.getBounds();
  const margin = 10;
  const availableWidth = Math.max(180, parent.width - margin * 2);
  const availableHeight = Math.max(260, parent.height - margin * 2);

  const width = Math.min(availableWidth, Math.max(220, Math.round(parent.width / 3)));
  const height = Math.min(availableHeight, Math.max(360, Math.round(parent.height * 0.82)));
  const x = parent.x + Math.max(margin, parent.width - width - margin);
  const y = parent.y + Math.max(margin, Math.round((parent.height - height) / 2));

  return { x, y, width, height };
};

export const createCommands = getPopupCreator(
  'commands',
  ['open-commands-list'],
  (mainWindow, settings, server, wins) => {
    const initialBounds = getCommandCenterBounds(mainWindow);
    const commandsWindow = new BrowserWindow({
      ...initialBounds,
      minWidth: Math.min(220, initialBounds.width),
      minHeight: Math.min(360, initialBounds.height),
      maxWidth: Math.max(initialBounds.width, Math.round(mainWindow.getBounds().width * 0.42)),
      maxHeight: Math.max(initialBounds.height, Math.round(mainWindow.getBounds().height * 0.92)),
      title: "Command Center",
      webPreferences: {
        preload: path.join(__dirname, 'commands-preload.js')
      },
      resizable: true,
      parent: mainWindow
    });

    commandsWindow.setMenu(null);
    instrumentRuntimeWindow(commandsWindow, 'commands');

    // Keep the popup proportional when the game is resized/maximized and pin it
    // to the right side instead of allowing it to cover the whole game again.
    const syncWindowToGame = () => {
      if (commandsWindow.isDestroyed() || mainWindow.isDestroyed()) return;
      const next = getCommandCenterBounds(mainWindow);
      commandsWindow.setMaximumSize(
        Math.max(next.width, Math.round(mainWindow.getBounds().width * 0.42)),
        Math.max(next.height, Math.round(mainWindow.getBounds().height * 0.92))
      );
      commandsWindow.setBounds(next, false);
    };
    mainWindow.on('resize', syncWindowToGame);
    mainWindow.on('move', syncWindowToGame);

    ipcMain.removeHandler(GET_DATA_CHANNEL);
    ipcMain.removeHandler(GET_STATE_CHANNEL);
    ipcMain.removeHandler(SEARCH_CATALOG_CHANNEL);
    ipcMain.removeHandler(RUN_COMMAND_CHANNEL);

    ipcMain.handle(GET_DATA_CHANNEL, () => getCommandCenterData());

    ipcMain.handle(GET_STATE_CHANNEL, () => {
      const players = getLivePenguins(server);
      const player = players.length > 0 ? players[0] : null;
      return {
        online: player !== null,
        player,
        onlineCount: players.length
      };
    });

    ipcMain.handle(SEARCH_CATALOG_CHANNEL, (_, arg) => {
      const kind = arg && typeof arg.kind === 'string' ? arg.kind : '';
      const query = arg && typeof arg.query === 'string' ? arg.query : '';
      const limit = arg && typeof arg.limit === 'number' ? arg.limit : 30;
      return searchCatalog(kind, query, limit);
    });

    ipcMain.handle(RUN_COMMAND_CHANNEL, async (_, arg) => {
      const rawCommand = arg && arg.command;

      if (typeof rawCommand !== 'string' || rawCommand.trim() === '') {
        return {
          ok: false,
          message: 'Choose an action or enter a command first.'
        };
      }

      const player = getActivePenguin(server);
      if (player === null) {
        writeRuntimeDiagnostic('command-center-command-rejected', {
          reason: 'no-active-penguin'
        });
        return {
          ok: false,
          message: 'No penguin is currently in the game. Log in first; no name or ID needs to be selected.'
        };
      }

      const command = rawCommand.trim();
      const commandMatch = command.match(/^(\w+)(.*)$/);
      if (commandMatch === null) {
        return {
          ok: false,
          command,
          message: 'The command format is invalid.'
        };
      }

      const name = commandMatch[1];
      const argString = commandMatch[2].trim();
      const args = argString === '' ? [] : argString.split(/\s+/);
      const known = getCommandsList().some(info => info.name === name);
      if (!known) {
        return {
          ok: false,
          command,
          message: `Unknown command: ${name}`
        };
      }

      try {
        const dispatched = server.runCommand(player.id, name, args);
        if (!dispatched) {
          writeRuntimeDiagnostic('command-center-command-rejected', {
            target: player.id,
            command: name,
            reason: 'active-penguin-disconnected'
          });
          return {
            ok: false,
            command,
            message: 'The active penguin disconnected before the command was applied.'
          };
        }

        console.log(`WADDLE_COMMAND_CENTER_COMMAND=PASS target=${player.id} player=${player.name} command=${name} mode=active-session`);
        writeRuntimeDiagnostic('command-center-command-dispatched', {
          target: player.id,
          player: player.name,
          command: name,
          argCount: args.length,
          mode: 'active-session'
        });
        return {
          ok: true,
          command,
          player,
          message: `Applied to ${player.name}: ${command}`
        };
      } catch (error) {
        const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
        writeRuntimeDiagnostic('command-center-command-failed', {
          target: player.id,
          player: player.name,
          command: name,
          error: message
        });
        return {
          ok: false,
          command,
          player,
          message
        };
      }
    });

    ipcMain.on('open-commands-list', () => {
      createCommandsList(mainWindow, wins, settings, server);
    });

    commandsWindow.webContents.once('did-finish-load', () => {
      const player = getActivePenguin(server);
      writeRuntimeDiagnostic('command-center-ready', {
        preload: path.join(__dirname, 'commands-preload.js'),
        activePenguinId: player ? player.id : null,
        width: commandsWindow.getBounds().width,
        height: commandsWindow.getBounds().height,
        sizingMode: 'one-third-game-width'
      });
    });

    commandsWindow.once('closed', () => {
      mainWindow.removeListener('resize', syncWindowToGame);
      mainWindow.removeListener('move', syncWindowToGame);
      ipcMain.removeHandler(GET_DATA_CHANNEL);
      ipcMain.removeHandler(GET_STATE_CHANNEL);
      ipcMain.removeHandler(SEARCH_CATALOG_CHANNEL);
      ipcMain.removeHandler(RUN_COMMAND_CHANNEL);
    });

    commandsWindow.loadFile(path.join(__dirname, 'commands.html'));

    return commandsWindow;
  }
);
