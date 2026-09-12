import { BrowserWindow, ipcMain } from "electron";
import path from "path";
import { getPopupCreator } from "@client/popups";
import { createCommandsList } from "../commandslist/commandslist";
import { getCommandsList } from "@server/commands/commands";
import { ITEMS } from "@server/game-logic/items";
import { FURNITURE } from "@server/game-logic/furniture";
import { ROOMS } from "@server/game-data/rooms";

const GET_PLAYERS_CHANNEL = 'command-center:get-players';
const GET_DATA_CHANNEL = 'command-center:get-data';
const RUN_COMMAND_CHANNEL = 'command-center:run-command';

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
  ['open-commands-list'],
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

    // Command Center used to send an IPC request and then wait for a second
    // event on the same channel. That design could silently lose the player
    // response while other Command Center data still arrived. Use Electron's
    // request/response IPC contract instead so every refresh resolves with a
    // value or rejects with a visible error.
    ipcMain.removeHandler(GET_PLAYERS_CHANNEL);
    ipcMain.removeHandler(GET_DATA_CHANNEL);
    ipcMain.removeHandler(RUN_COMMAND_CHANNEL);

    let lastPlayerSignature = '';

    ipcMain.handle(GET_PLAYERS_CHANNEL, () => {
      const players = server.getAllPlayersInfo();
      const signature = players.map(player => `${player.id}:${player.name}`).join('|');
      if (signature !== lastPlayerSignature) {
        console.log(`WADDLE_COMMAND_CENTER_PLAYERS=STATE count=${players.length} players=${signature || 'none'}`);
        lastPlayerSignature = signature;
      }
      return players;
    });

    ipcMain.handle(GET_DATA_CHANNEL, () => getCommandCenterData());

    ipcMain.handle(RUN_COMMAND_CHANNEL, (_, arg) => {
      const id = arg && arg.id;
      const rawCommand = arg && arg.command;

      if (typeof id !== 'number' || !Number.isFinite(id)) {
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
      const known = getCommandsList().some(info => info.name === name);
      if (!known) {
        return {
          ok: false,
          command,
          message: `Unknown command: ${name}`
        };
      }

      try {
        const dispatched = server.runCommand(id, name, argString === '' ? [] : argString.split(/\s+/));
        if (!dispatched) {
          return {
            ok: false,
            command,
            refreshPlayers: true,
            message: 'That penguin is no longer online. Refreshing the player list.'
          };
        }

        console.log(`WADDLE_COMMAND_CENTER_COMMAND=PASS target=${id} command=${name}`);
        return {
          ok: true,
          command,
          message: `Command dispatched: ${command}`
        };
      } catch (error) {
        return {
          ok: false,
          command,
          message: error instanceof Error ? error.message : String(error)
        };
      }
    });

    ipcMain.on('open-commands-list', () => {
      createCommandsList(mainWindow, wins, settings, server);
    });

    commandsWindow.once('closed', () => {
      ipcMain.removeHandler(GET_PLAYERS_CHANNEL);
      ipcMain.removeHandler(GET_DATA_CHANNEL);
      ipcMain.removeHandler(RUN_COMMAND_CHANNEL);
    });

    commandsWindow.loadFile(path.join(__dirname, 'commands.html'));

    return commandsWindow;
  }
);