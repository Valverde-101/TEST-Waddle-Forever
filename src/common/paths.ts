import path from 'path';
import os from 'os';
import fs from 'fs';
import { IS_DEV } from './constants';

/**
 * Portable/runtime-aware data location.
 *
 * WADDLE_USER_DATA_DIR is authoritative when the launcher provides it. This
 * keeps settings/mods/state on the shared Waddle repository instead of relying
 * on machine-local %APPDATA%. The historical .uselocal and dev behavior remain
 * valid fallbacks for manual development.
 */
const explicitUserData = process.env.WADDLE_USER_DATA_DIR?.trim();
const portableRuntime = process.env.WADDLE_PORTABLE === '1' || process.env.WADDLE_RUNTIME_MODE === 'repo_local_direct';
const useGameFolder = IS_DEV || portableRuntime || fs.existsSync(path.join(process.cwd(), '.uselocal'));

/** Get the data folder location for each OS */
function getOsDataFolder() {
  switch (process.platform) {
    case 'win32':
      return path.join(process.env.APPDATA ?? '', 'WaddleForever');
    case 'linux': {
      // in sudo, os.homedir() returns the root, which we don't want
      const home = process.env.SUDO_USER === undefined
        ? os.homedir()
        : `/home/${process.env.SUDO_USER}`;
      return path.join(home, '.waddleforever');
    }
    case 'darwin':
      return path.join(os.homedir(), '.waddleforever');
    default:
      throw new Error(`Unsupported OS: ${process.platform}`);
  }
}

/** Folder where all the WF user data is kept */
export const USER_DATA_FOLDER = explicitUserData
  ? path.resolve(explicitUserData)
  : useGameFolder
    ? process.cwd()
    : getOsDataFolder();

export const MODS_DIRECTORY = path.join(USER_DATA_FOLDER, 'mods');
/** name of the file that contains custom items in a mod */
export const MOD_ITEMS_FILE = 'items.json';
export const MOD_HACKS_FILE = 'frames.json';
export const MOD_MUSIC_FILE = 'music.json';
export const SETTINGS_PATH = path.join(USER_DATA_FOLDER, 'settings.json');

fs.mkdirSync(USER_DATA_FOLDER, { recursive: true });
