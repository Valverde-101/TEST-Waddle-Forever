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

export const createCommands = getPopupCreator(
  'commands',
  ['open-commands-list'],
  (mainWindow, settings, server, wins) => {
    const commandsWindow = new BrowserWindow({
      width: 470,
      height: 720,
      minWidth: 420,
      minHeight: 520,
      title: "Command Center",
      webPreferences: {
        preload: path.join(__dirname, 'commands-preload.js')
      },
      resizable: true,
      parent: mainWindow
    });

    commandsWindow.setMenu(null);
    instrumentRuntimeWindow(commandsWindow, 'commands');

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
        activePenguinId: player ? player.id : null
      });
    });

    commandsWindow.once('closed', () => {
      ipcMain.removeHandler(GET_DATA_CHANNEL);
      ipcMain.removeHandler(GET_STATE_CHANNEL);
      ipcMain.removeHandler(SEARCH_CATALOG_CHANNEL);
      ipcMain.removeHandler(RUN_COMMAND_CHANNEL);
    });

    commandsWindow.loadFile(path.join(__dirname, 'commands.html'));

    return commandsWindow;
  }
);
