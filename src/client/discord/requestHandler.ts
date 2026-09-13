import { BrowserWindow } from "electron";
import { promises as fs } from "fs";
import path from "path";
import { Store } from "../store";
import { ROOMS_JSONP_NAME, ROOMS_PATH, SWF_MIME_FILE } from "./constants";
import { getLanguageInStore } from "./localization/localization";
import { parseAndUpdateLocation } from "./parsers/locationParser";
import { parseAndUpdateRooms } from "./parsers/roomParser";

export type RoomsJson = Record<string, Record<string, unknown>>;

export const parseJSONP = <T = unknown>(jsonp: string, name: string): T => {
  const prefix = `${name}(`;
  const trimmed = jsonp.trim();
  if (!trimmed.startsWith(prefix) || !trimmed.endsWith(');')) {
    throw new Error(`Invalid JSONP payload for ${name}`);
  }

  return JSON.parse(trimmed.slice(prefix.length, -2)) as T;
};

export type RoomsResponse = {
  roomsJson: RoomsJson,
  localizedJson?: RoomsJson,
}

let portugueseRoomsPromise: Promise<RoomsJson | undefined> | undefined;

const loadPortugueseRooms = async (): Promise<RoomsJson | undefined> => {
  if (portugueseRoomsPromise) {
    return portugueseRoomsPromise;
  }

  portugueseRoomsPromise = (async () => {
    const candidates = [
      // Packaged/external runtime: compiled/client/discord -> compiled/assets.
      path.join(__dirname, '../../assets/default/rooms-pt.jsonp'),
      // Source/development fallback. The external runtime deliberately keeps cwd
      // at the source root, so this is also a stable fallback for local builds.
      path.join(process.cwd(), 'assets/default/rooms-pt.jsonp'),
    ];

    for (const candidate of candidates) {
      try {
        const jsonp = await fs.readFile(candidate, 'utf8');
        return parseJSONP<RoomsJson>(jsonp, ROOMS_JSONP_NAME);
      } catch (error) {
        if ((error as NodeJS.ErrnoException)?.code !== 'ENOENT') {
          console.warn(`Could not load localized rooms from ${candidate}:`, error);
        }
      }
    }

    return undefined;
  })();

  return portugueseRoomsPromise;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const getRoomsJsonFromParams = async (store: Store, mainWindow: BrowserWindow, params: any): Promise<RoomsResponse> => {
  const response = await mainWindow.webContents.debugger.sendCommand('Network.getResponseBody', { requestId: params.requestId });
  const plainResponseBody = response.base64Encoded
    ? Buffer.from(response.body, 'base64').toString('utf8')
    : response.body;

  // Never overwrite the persisted language merely because rooms.jsonp was
  // observed. The network payload is the canonical room structure; when the
  // selected UI/RPC language is Portuguese we overlay names from the bundled
  // Portuguese room table so every subsequent network refresh stays localized.
  const localizedJson = getLanguageInStore(store) === 'pt'
    ? await loadPortugueseRooms()
    : undefined;

  return {
    roomsJson: parseJSONP<RoomsJson>(plainResponseBody, ROOMS_JSONP_NAME),
    localizedJson,
  };
};

export const startRequestListener = (store: Store, mainWindow: BrowserWindow) => {
  try {
    mainWindow.webContents.debugger.attach('1.3');
  } catch (err) {
    console.log('Debugger attach failed: ', err);
  }

  mainWindow.webContents.debugger.on('detach', (_, reason) => {
    console.log('Debugger detached due to: ', reason);
  });

  mainWindow.webContents.debugger.on('message', async (_, method, params) => {
    if (method === 'Network.responseReceived') {

      if (params.response.url.includes(ROOMS_PATH)) {
        await parseAndUpdateRooms(store, mainWindow, params);
      }

      if (params.response.url.includes(SWF_MIME_FILE)) {
        await parseAndUpdateLocation(store, params);
      }
    }
  });

  void mainWindow.webContents.debugger.sendCommand('Network.enable').catch(error => {
    console.error('Could not enable network debugger tracking:', error);
  });
};
