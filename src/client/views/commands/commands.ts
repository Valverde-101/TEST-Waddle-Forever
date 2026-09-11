import { BrowserWindow, ipcMain } from "electron";
import path from "path";
import { getPopupCreator } from "@client/popups";
import { getCommandsList } from "@server/commands/commands";
import { ITEMS } from "@server/game-logic/items";
import { FURNITURE } from "@server/game-logic/furniture";
import { ROOMS } from "@server/game-data/rooms";

export const createCommands = getPopupCreator(
  'commands',
  ['get-players', 'get-command-center-data', 'run-command'],
  (mainWindow, settings, server) => {
    const commandsWindow = new BrowserWindow({
      width: 1040,
      height: 760,
      minWidth: 820,
      minHeight: 620,
      title: "Command Center",
      backgroundColor: "#062744",
      webPreferences: {
        preload: path.join(__dirname, 'commands-preload.js')
      },
      resizable: true,
      parent: mainWindow
    });

    commandsWindow.setMenu(null);
    commandsWindow.loadFile(path.join(__dirname, 'commands.html'));

    const commands = getCommandsList();
    const commandNames = new Set(commands.map(command => command.name));

    const sendPlayers = () => {
      commandsWindow.webContents.send('get-players', server.getAllPlayersInfo());
    };

    const sendCommandCenterData = () => {
      commandsWindow.webContents.send('command-center-data', {
        commands,
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
          member: item.member,
          maxAmount: item.maxAmount
        })),
        rooms: Object.entries(ROOMS).map(([name, room]) => ({
          name,
          id: room.id
        }))
      });
    };

    ipcMain.on('get-players', sendPlayers);
    ipcMain.on('get-command-center-data', sendCommandCenterData);

    ipcMain.on('run-command', (_, arg) => {
      const id = arg && arg.id;
      const rawCommand = arg && arg.command;
      const reply = (accepted: boolean, message: string) => {
        commandsWindow.webContents.send('command-result', {
          accepted,
          message,
          command: typeof rawCommand === 'string' ? rawCommand.trim() : ''
        });
      };

      if (typeof id !== 'number' || !Number.isFinite(id)) {
        reply(false, 'Select an online player before running a command.');
        return;
      }

      if (typeof rawCommand !== 'string' || rawCommand.trim() === '') {
        reply(false, 'Choose a command or type one in Advanced mode.');
        return;
      }

      const command = rawCommand.trim();
      const commandMatch = command.match(/^(\w+)(?:\s+(.*))?$/);
      if (commandMatch === null) {
        reply(false, 'The command format is invalid.');
        return;
      }

      const name = commandMatch[1];
      if (!commandNames.has(name)) {
        reply(false, `Unknown command: ${name}`);
        return;
      }

      const argString = (commandMatch[2] || '').trim();
      server.runCommand(id, name, argString === '' ? [] : argString.split(/\s+/));
      reply(true, `Command sent: ${command}`);
    });

    commandsWindow.webContents.on('did-finish-load', () => {
      sendPlayers();
      sendCommandCenterData();
    });

    return commandsWindow;
  }
);
