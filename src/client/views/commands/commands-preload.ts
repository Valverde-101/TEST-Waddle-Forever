import { ipcRenderer } from 'electron';
import fs from 'fs';
import path from 'path';

const dispatch = (name: string, detail: unknown) => {
  window.dispatchEvent(new CustomEvent(name, { detail }));
};

type CachedItemIcon = {
  dataUrl: string;
  bytes: number;
};

const ITEM_ICON_CACHE_MAX_BYTES = 24 * 1024 * 1024;
const itemIconCache = new Map<number, CachedItemIcon>();
const itemIconReads = new Map<number, Promise<string | null>>();
let itemIconCacheBytes = 0;
let canonicalIconDirectory: string | null | undefined;

const isDirectory = (candidate: string) => {
  try {
    return fs.statSync(candidate).isDirectory();
  } catch {
    return false;
  }
};

/**
 * Item PNGs have exactly one authoritative location:
 *   <repository>/media/default/iconspng/<id>.png
 *
 * The popup itself may be running from compiled/ or .work/build/compiled/.
 * Never derive media from the renderer URL. Resolve the repository root from
 * the process/runtime filesystem and then stay inside its canonical media tree.
 */
const getCanonicalIconDirectory = (): string | null => {
  if (canonicalIconDirectory !== undefined) return canonicalIconDirectory;

  const starts = [process.cwd(), __dirname];
  const visited = new Set<string>();

  for (const start of starts) {
    let current = path.resolve(start);
    for (let depth = 0; depth < 16; depth += 1) {
      const key = current.toLowerCase();
      if (!visited.has(key)) {
        visited.add(key);
        const gitEntry = path.join(current, '.git');
        const iconDirectory = path.join(current, 'media', 'default', 'iconspng');
        if (fs.existsSync(gitEntry) && isDirectory(iconDirectory)) {
          canonicalIconDirectory = iconDirectory;
          console.log(`WADDLE_COMMAND_CENTER_ICON_ROOT=PASS repository=${current} directory=${iconDirectory} source=canonical-repository`);
          return canonicalIconDirectory;
        }
      }

      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
  }

  canonicalIconDirectory = null;
  console.error('WADDLE_COMMAND_CENTER_ICON_ROOT=FAIL reason=canonical_repository_not_found');
  return null;
};

const touchCachedIcon = (id: number, cached: CachedItemIcon) => {
  itemIconCache.delete(id);
  itemIconCache.set(id, cached);
  return cached.dataUrl;
};

const cacheItemIcon = (id: number, dataUrl: string, bytes: number) => {
  const old = itemIconCache.get(id);
  if (old !== undefined) itemIconCacheBytes -= old.bytes;
  itemIconCache.delete(id);
  itemIconCache.set(id, { dataUrl, bytes });
  itemIconCacheBytes += bytes;

  while (itemIconCacheBytes > ITEM_ICON_CACHE_MAX_BYTES && itemIconCache.size > 1) {
    const oldest = itemIconCache.entries().next();
    if (oldest.done) break;
    const [oldestId, oldestValue] = oldest.value;
    itemIconCache.delete(oldestId);
    itemIconCacheBytes -= oldestValue.bytes;
  }

  return dataUrl;
};

const resolveItemIcon = async (rawId: unknown): Promise<string | null> => {
  const id = Number(rawId);
  if (!Number.isInteger(id) || id <= 0) return null;

  const cached = itemIconCache.get(id);
  if (cached !== undefined) return touchCachedIcon(id, cached);

  const pending = itemIconReads.get(id);
  if (pending !== undefined) return pending;

  const read = (async () => {
    const iconDirectory = getCanonicalIconDirectory();
    if (iconDirectory === null) return null;

    // Numeric validation above means this join cannot escape iconspng.
    const iconPath = path.join(iconDirectory, `${id}.png`);
    try {
      const data = await fs.promises.readFile(iconPath);
      const dataUrl = `data:image/png;base64,${data.toString('base64')}`;
      return cacheItemIcon(id, dataUrl, data.length);
    } catch (error) {
      const code = error && typeof error === 'object' && 'code' in error ? String((error as any).code) : '';
      if (code !== 'ENOENT') {
        console.error(`WADDLE_COMMAND_CENTER_ICON_READ=FAIL id=${id} path=${iconPath} error=${error instanceof Error ? error.message : String(error)}`);
      }
      return null;
    }
  })();

  itemIconReads.set(id, read);
  try {
    return await read;
  } finally {
    itemIconReads.delete(id);
  }
};

const fetchCommandCenterData = async () => {
  try {
    const data = await ipcRenderer.invoke('command-center:get-data');
    dispatch('get-command-center-data', data);
    return data;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    dispatch('command-center-data-error', message);
    return undefined;
  }
};

const fetchState = async () => {
  try {
    const state = await ipcRenderer.invoke('command-center:get-state');
    dispatch('command-center-state', state);
    return state;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    dispatch('command-center-state-error', message);
    return undefined;
  }
};

const searchCatalog = async (obj: any) => {
  try {
    return await ipcRenderer.invoke('command-center:search-catalog', obj);
  } catch (error) {
    dispatch('command-center-catalog-error', error instanceof Error ? error.message : String(error));
    return [];
  }
};

const runCommand = async (obj: any) => {
  try {
    const result = await ipcRenderer.invoke('command-center:run-command', obj);
    dispatch('command-result', result);
    void fetchState();
    return result;
  } catch (error) {
    const result = {
      ok: false,
      message: error instanceof Error ? error.message : String(error)
    };
    dispatch('command-result', result);
    return result;
  }
};

(window as any).api = {
  fetchCommandCenterData,
  fetchState,
  searchCatalog,
  resolveItemIcon,
  openCommandsList: () => ipcRenderer.send('open-commands-list'),
  runCommand
};
