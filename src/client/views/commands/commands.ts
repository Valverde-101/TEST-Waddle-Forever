import { BrowserWindow, ipcMain } from "electron";
import path from "path";
import { getPopupCreator } from "@client/popups";
import { createCommandsList } from "../commandslist/commandslist";
import { getCommandsList } from "@server/commands/commands";
import { ITEMS } from "@server/game-logic/items";
import { FURNITURE } from "@server/game-logic/furniture";
import { ROOMS } from "@server/game-data/rooms";

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

export const createCommands = getPopupCreator(
  'commands',
  ['get-players', 'get-command-center-data', 'run-command', 'open-commands-list'],
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

    const sendPlayers = () => {
      if (commandsWindow.isDestroyed() || commandsWindow.webContents.isDestroyed()) return;
      commandsWindow.webContents.send('get-players', server.getAllPlayersInfo());
    };

    const sendCommandCenterData = () => {
      if (commandsWindow.isDestroyed() || commandsWindow.webContents.isDestroyed()) return;
      commandsWindow.webContents.send('get-command-center-data', getCommandCenterData());
    };

    // Register IPC before loading the renderer. The old ordering allowed the
    // renderer's first fetchPlayers() request to race ahead of ipcMain.on(),
    // leaving the UI permanently stuck on "Loading players...".
    ipcMain.on('get-players', sendPlayers);
    ipcMain.on('get-command-center-data', sendCommandCenterData);

    ipcMain.on('run-command', (_, arg) => {
      const id = arg && arg.id;
      const rawCommand = arg && arg.command;

      if (typeof id !== 'number' || !Number.isFinite(id)) {
        commandsWindow.webContents.send('command-result', {
          ok: false,
          message: 'Select an online penguin before running a command.'
        });
        return;
      }

      if (typeof rawCommand !== 'string' || rawCommand.trim() === '') {
        commandsWindow.webContents.send('command-result', {
          ok: false,
          message: 'Enter or choose a command first.'
        });
        return;
      }

      const command = rawCommand.trim();
      const commandMatch = command.match(/^(\w+)(.*)$/);
      if (commandMatch === null) {
        commandsWindow.webContents.send('command-result', {
          ok: false,
          command,
          message: 'The command format is invalid.'
        });
        return;
      }

      const name = commandMatch[1];
      const argString = commandMatch[2].trim();
      const known = getCommandsList().some(info => info.name === name);
      if (!known) {
        commandsWindow.webContents.send('command-result', {
          ok: false,
          command,
          message: `Unknown command: ${name}`
        });
        return;
      }

      try {
        const dispatched = server.runCommand(id, name, argString === '' ? [] : argString.split(/\s+/));
        if (!dispatched) {
          commandsWindow.webContents.send('command-result', {
            ok: false,
            command,
            message: 'That penguin is no longer online. The player list was refreshed.'
          });
          sendPlayers();
          return;
        }

        commandsWindow.webContents.send('command-result', {
          ok: true,
          command,
          message: `Command dispatched: ${command}`
        });
      } catch (error) {
        commandsWindow.webContents.send('command-result', {
          ok: false,
          command,
          message: error instanceof Error ? error.message : String(error)
        });
      }
    });

    ipcMain.on('open-commands-list', () => {
      createCommandsList(mainWindow, wins, settings, server);
    });

    // Always seed the renderer after its document is ready, then keep targets
    // synchronized while the panel is open. This also picks up a penguin that
    // logs in after Command Center was already opened.
    commandsWindow.webContents.once('did-finish-load', () => {
      sendPlayers();
      sendCommandCenterData();
    });

    const playerPushTimer = setInterval(sendPlayers, 1500);
    commandsWindow.once('closed', () => clearInterval(playerPushTimer));

    commandsWindow.loadFile(path.join(__dirname, 'commands.html'));

    return commandsWindow;
  }
);