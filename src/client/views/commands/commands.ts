import { BrowserWindow, ipcMain } from "electron";
import fs from "fs";
import path from "path";
import { getPopupCreator } from "@client/popups";
import { createCommandsList } from "../commandslist/commandslist";
import { ensurePortablePenguinStorage, withPenguinStorageRecovery } from "@server/database/storage-layout";
import { getCommandsList } from "@server/commands/commands";
import { ITEMS } from "@server/game-logic/items";
import { FURNITURE } from "@server/game-logic/furniture";
import { ROOMS } from "@server/game-data/rooms";

const GET_PLAYERS_CHANNEL = 'command-center:get-players';
const GET_DATA_CHANNEL = 'command-center:get-data';
const RUN_COMMAND_CHANNEL = 'command-center:run-command';

type CommandTarget = {
  id: number;
  name: string;
  online: boolean;
  saved: boolean;
};

type StoredPenguin = {
  name: string;
  coins: number;
  inventory: number[];
  furniture: Record<string, number>;
  is_member: boolean;
  safeChat?: boolean;
  noSave?: boolean;
  [key: string]: unknown;
};

type StoredCommandResult = {
  supported: boolean;
  ok: boolean;
  message: string;
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

const getPenguinsDirectory = (): string => ensurePortablePenguinStorage().penguinsRoot;
const getStoredPenguinPath = (id: number): string => path.join(getPenguinsDirectory(), `${id}.json`);

const readStoredPenguin = async (id: number): Promise<StoredPenguin | null> => {
  return withPenguinStorageRecovery(`command-center.read:${id}`, async () => {
    const filePath = getStoredPenguinPath(id);
    try {
      const raw = await fs.promises.readFile(filePath, 'utf-8');
      return JSON.parse(raw) as StoredPenguin;
    } catch (error) {
      // Missing profile is a valid result. Missing parent storage is repaired by
      // withPenguinStorageRecovery before each attempt.
      if ((error as NodeJS.ErrnoException).code === 'ENOENT' && fs.existsSync(getPenguinsDirectory())) return null;
      throw error;
    }
  });
};

const writeStoredPenguin = async (id: number, data: StoredPenguin): Promise<void> => {
  await withPenguinStorageRecovery(`command-center.write:${id}`, async () => {
    const penguinsDirectory = getPenguinsDirectory();
    const filePath = path.join(penguinsDirectory, `${id}.json`);
    const temporaryPath = path.join(penguinsDirectory, `.${id}.command-center.tmp`);
    await fs.promises.writeFile(temporaryPath, JSON.stringify(data), 'utf-8');
    await fs.promises.rename(temporaryPath, filePath);
  });
};

const listStoredPenguins = async (): Promise<CommandTarget[]> => {
  return withPenguinStorageRecovery('command-center.list', async () => {
    const penguinsDirectory = getPenguinsDirectory();
    const files = await fs.promises.readdir(penguinsDirectory);
    const targets: CommandTarget[] = [];

    for (const file of files) {
      const match = file.match(/^(\d+)\.json$/);
      if (match === null) continue;

      const id = Number(match[1]);
      // User-created penguins start at 101. Lower IDs are reserved for mascots.
      if (!Number.isInteger(id) || id < 101) continue;

      try {
        const data = JSON.parse(await fs.promises.readFile(path.join(penguinsDirectory, file), 'utf-8')) as Partial<StoredPenguin>;
        if (typeof data.name !== 'string' || data.name.trim() === '') continue;
        targets.push({ id, name: data.name, online: false, saved: true });
      } catch (error) {
        console.warn(`WADDLE_COMMAND_CENTER_PROFILE=WARN id=${id} file=${file} error=${error instanceof Error ? error.message : String(error)}`);
      }
    }

    return targets.sort((a, b) => a.name.localeCompare(b.name) || a.id - b.id);
  });
};

const getCommandTargets = async (server: { getAllPlayersInfo: () => Array<{ name: string; id: number }> }): Promise<CommandTarget[]> => {
  const saved = await listStoredPenguins();
  const byId = new Map<number, CommandTarget>(saved.map(target => [target.id, target]));

  for (const player of server.getAllPlayersInfo()) {
    const existing = byId.get(player.id);
    if (existing !== undefined) {
      existing.online = true;
      existing.name = player.name;
    } else {
      byId.set(player.id, {
        id: player.id,
        name: player.name,
        online: true,
        saved: false
      });
    }
  }

  return Array.from(byId.values()).sort((a, b) => {
    if (a.online !== b.online) return a.online ? -1 : 1;
    return a.name.localeCompare(b.name) || a.id - b.id;
  });
};

const parseInteger = (value: string | undefined): number | null => {
  if (value === undefined || value.trim() === '') return null;
  const number = Number(value);
  return Number.isInteger(number) ? number : null;
};

const runStoredCommand = async (id: number, name: string, args: string[]): Promise<StoredCommandResult> => {
  const penguin = await readStoredPenguin(id);
  if (penguin === null) {
    return {
      supported: true,
      ok: false,
      message: `Saved penguin #${id} was not found on disk.`
    };
  }

  let message = '';

  switch (name) {
    case 'ac': {
      const amount = parseInteger(args[0]);
      if (amount === null) {
        return { supported: true, ok: false, message: 'Coins requires an integer amount.' };
      }
      const current = Number.isFinite(penguin.coins) ? penguin.coins : 0;
      penguin.coins = Math.max(0, current + amount);
      message = `${penguin.name}: coins saved at ${penguin.coins}.`;
      break;
    }
    case 'ai': {
      const requested = args[0];
      if (requested === 'all') {
        const owned = new Set(Array.isArray(penguin.inventory) ? penguin.inventory : []);
        for (const item of ITEMS.rows) owned.add(item.id);
        penguin.inventory = Array.from(owned);
        message = `${penguin.name}: all clothing items were saved to the profile.`;
        break;
      }

      const itemId = parseInteger(requested);
      if (itemId === null || !ITEMS.rows.some(item => item.id === itemId)) {
        return { supported: true, ok: false, message: `Unknown clothing item ID: ${requested ?? ''}` };
      }
      const owned = new Set(Array.isArray(penguin.inventory) ? penguin.inventory : []);
      owned.add(itemId);
      penguin.inventory = Array.from(owned);
      message = `${penguin.name}: item ${itemId} saved to inventory.`;
      break;
    }
    case 'af': {
      const furnitureId = parseInteger(args[0]);
      const quantity = args[1] === undefined ? 1 : parseInteger(args[1]);
      if (furnitureId === null || !FURNITURE.rows.some(item => item.id === furnitureId)) {
        return { supported: true, ok: false, message: `Unknown furniture ID: ${args[0] ?? ''}` };
      }
      if (quantity === null || quantity < 1) {
        return { supported: true, ok: false, message: 'Furniture quantity must be a positive integer.' };
      }
      if (penguin.furniture === null || typeof penguin.furniture !== 'object') penguin.furniture = {};
      const key = String(furnitureId);
      const current = Number(penguin.furniture[key] ?? 0);
      penguin.furniture[key] = Math.min(99, Math.max(0, current) + quantity);
      message = `${penguin.name}: furniture ${furnitureId} saved (${penguin.furniture[key]} owned).`;
      break;
    }
    case 'rename': {
      const newName = args.join(' ').trim();
      if (newName === '') {
        return { supported: true, ok: false, message: 'Rename requires a penguin name.' };
      }
      penguin.name = newName;
      message = `Penguin #${id} renamed to ${newName}.`;
      break;
    }
    case 'member': {
      penguin.is_member = !penguin.is_member;
      message = `${penguin.name}: membership ${penguin.is_member ? 'enabled' : 'disabled'}.`;
      break;
    }
    case 'safechat': {
      penguin.safeChat = !penguin.safeChat;
      message = `${penguin.name}: safe chat ${penguin.safeChat ? 'enabled' : 'disabled'}.`;
      break;
    }
    case 'nosave': {
      penguin.noSave = true;
      message = `${penguin.name}: saving disabled in stored profile.`;
      break;
    }
    case 'enablesave': {
      penguin.noSave = false;
      message = `${penguin.name}: saving enabled in stored profile.`;
      break;
    }
    default:
      return {
        supported: false,
        ok: false,
        message: `Command ${name} requires the penguin to be online.`
      };
  }

  await writeStoredPenguin(id, penguin);
  console.log(`WADDLE_COMMAND_CENTER_STORED_COMMAND=PASS target=${id} command=${name} path=${getStoredPenguinPath(id)}`);
  return {
    supported: true,
    ok: true,
    message: `${message} The change will be present on the next login.`
  };
};

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

    ipcMain.handle(GET_PLAYERS_CHANNEL, async () => {
      const players = await getCommandTargets(server);
      const signature = players.map(player => `${player.id}:${player.name}:${player.online ? 'online' : 'saved'}`).join('|');
      if (signature !== lastPlayerSignature) {
        const online = players.filter(player => player.online).length;
        const saved = players.filter(player => player.saved).length;
        console.log(`WADDLE_COMMAND_CENTER_PLAYERS=STATE count=${players.length} online=${online} saved=${saved} storage=${getPenguinsDirectory()} players=${signature || 'none'}`);
        lastPlayerSignature = signature;
      }
      return players;
    });

    ipcMain.handle(GET_DATA_CHANNEL, () => getCommandCenterData());

    ipcMain.handle(RUN_COMMAND_CHANNEL, async (_, arg) => {
      const id = arg && arg.id;
      const rawCommand = arg && arg.command;

      if (typeof id !== 'number' || !Number.isFinite(id)) {
        return {
          ok: false,
          message: 'Select a penguin before running a command.'
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
        if (dispatched) {
          console.log(`WADDLE_COMMAND_CENTER_COMMAND=PASS target=${id} command=${name} mode=online`);
          return {
            ok: true,
            command,
            refreshPlayers: true,
            message: `Command dispatched to online penguin: ${command}`
          };
        }

        const stored = await runStoredCommand(id, name, args);
        return {
          ok: stored.ok,
          command,
          refreshPlayers: true,
          message: stored.message
        };
      } catch (error) {
        return {
          ok: false,
          command,
          refreshPlayers: true,
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