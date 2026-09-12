import { BrowserWindow, ipcMain } from "electron";
import path from "path";
import { getPopupCreator } from "@client/popups";
import { instrumentRuntimeWindow, writeRuntimeDiagnostic } from "@client/runtime-diagnostics";
import { createCommandsList } from "../commandslist/commandslist";
import { getCommandsList } from "@server/commands/commands";
import { ITEMS } from "@server/game-logic/items";
import { FURNITURE } from "@server/game-logic/furniture";
import { ROOMS } from "@server/game-data/rooms";

// Player discovery intentionally uses the original event/push contract. The
// live World registry is the authoritative source for a command target; command
// availability must never depend on portable storage, SMB latency or a saved
// JSON profile being readable.
const GET_PLAYERS_CHANNEL = 'get-players';
const GET_DATA_CHANNEL = 'command-center:get-data';
const RUN_COMMAND_CHANNEL = 'command-center:run-command';

type CommandTarget = {
  id: number;
  name: string;
  online: boolean;
  saved: boolean;
};

const getCommandCenterData = () => ({
  commands: getCommandsList(),
  catalog: {
    items: ITEMS.rows.map(item => ({
      id: item.id,
      name: item.name,
      type: item.type,
      cost: item.cost,
      member: item.isMember
    })),
    furniture: FURNITURE.rows.map(item => ({
      id: item.id,
      name: item.name,
      type: item.type,
      cost: item.cost,
      member: item.member
    })),
    rooms: Object.entries(ROOMS).map(([name, info]) => ({
      name,
      id: info.id
    }))
  }
});

const getLiveTargets = (server: { getAllPlayersInfo: () => Array<{ name: string; id: number }> }): CommandTarget[] => {
  return server.getAllPlayersInfo()
    .filter(player => Number.isInteger(player.id) && player.id > 0 && typeof player.name === 'string' && player.name.trim() !== '')
    .map(player => ({
      id: player.id,
      name: player.name,
      online: true,
      saved: false
    }))
    .sort((a, b) => a.name.localeCompare(b.name) || a.id - b.id);
};

export const createCommands = getPopupCreator(
  'commands',
  [GET_PLAYERS_CHANNEL, 'open-commands-list'],
  (mainWindow, settings, server, wins) => {
    const commandsWindow = new BrowserWindow({
      width: 1040,
      height: 720,
      minWidth: 860,
      minHeight: 620,
      title: "Command Center",
      webPreferences: {
        preload: path.join(__dirname, 'commands-preload.js')
      },
      resizable: true,
      parent: mainWindow
    });

    commandsWindow.setMenu(null);
    instrumentRuntimeWindow(commandsWindow, 'commands');

    // getPopupCreator removes event listeners when the popup closes. The invoke
    // handlers are global in Electron, so explicitly replace and remove only
    // the two Command Center handlers owned by this popup.
    ipcMain.removeHandler(GET_DATA_CHANNEL);
    ipcMain.removeHandler(RUN_COMMAND_CHANNEL);

    let lastPlayerSignature = '';

    const publishPlayers = () => {
      if (commandsWindow.isDestroyed() || commandsWindow.webContents.isDestroyed()) return;

      try {
        const players = getLiveTargets(server);
        const signature = players.map(player => `${player.id}:${player.name}`).join('|');
        if (signature !== lastPlayerSignature) {
          console.log(`WADDLE_COMMAND_CENTER_PLAYERS=STATE count=${players.length} online=${players.length} source=world players=${signature || 'none'}`);
          writeRuntimeDiagnostic('command-center-players', {
            count: players.length,
            source: 'world',
            ids: players.map(player => player.id)
          });
          lastPlayerSignature = signature;
        }
        commandsWindow.webContents.send(GET_PLAYERS_CHANNEL, players);
      } catch (error) {
        const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
        console.error(`WADDLE_COMMAND_CENTER_PLAYERS=FAIL source=world error=${message}`);
        writeRuntimeDiagnostic('command-center-player-query-failed', { error: message });
        if (!commandsWindow.isDestroyed() && !commandsWindow.webContents.isDestroyed()) {
          commandsWindow.webContents.send('command-center-player-error', message);
        }
      }
    };

    ipcMain.on(GET_PLAYERS_CHANNEL, publishPlayers);

    ipcMain.handle(GET_DATA_CHANNEL, () => getCommandCenterData());

    ipcMain.handle(RUN_COMMAND_CHANNEL, async (_, arg) => {
      const id = arg && arg.id;
      const rawCommand = arg && arg.command;

      if (typeof id !== 'number' || !Number.isInteger(id) || id <= 0) {
        return {
          ok: false,
          message: 'Select an online penguin before running a command.'
        };
      }

      if (typeof rawCommand !== 'string' || rawCommand.trim() === '') {
        return {
          ok: false,
          message: 'Enter or choose a command first.'
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
        const dispatched = server.runCommand(id, name, args);
        if (!dispatched) {
          publishPlayers();
          writeRuntimeDiagnostic('command-center-command-rejected', {
            target: id,
            command: name,
            reason: 'target-not-online'
          });
          return {
            ok: false,
            command,
            refreshPlayers: true,
            message: `Penguin #${id} is no longer online. Refresh the target and try again.`
          };
        }

        console.log(`WADDLE_COMMAND_CENTER_COMMAND=PASS target=${id} command=${name} mode=online`);
        writeRuntimeDiagnostic('command-center-command-dispatched', {
          target: id,
          command: name,
          argCount: args.length,
          mode: 'online'
        });
        return {
          ok: true,
          command,
          refreshPlayers: true,
          message: `Command dispatched to ${id}: ${command}`
        };
      } catch (error) {
        const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
        writeRuntimeDiagnostic('command-center-command-failed', {
          target: id,
          command: name,
          error: message
        });
        return {
          ok: false,
          command,
          refreshPlayers: true,
          message
        };
      }
    });

    ipcMain.on('open-commands-list', () => {
      createCommandsList(mainWindow, wins, settings, server);
    });

    commandsWindow.webContents.once('did-finish-load', () => {
      writeRuntimeDiagnostic('command-center-ready', {
        preload: path.join(__dirname, 'commands-preload.js')
      });
      publishPlayers();
    });

    commandsWindow.once('closed', () => {
      ipcMain.removeHandler(GET_DATA_CHANNEL);
      ipcMain.removeHandler(RUN_COMMAND_CHANNEL);
    });

    commandsWindow.loadFile(path.join(__dirname, 'commands.html'));

    return commandsWindow;
  }
);
