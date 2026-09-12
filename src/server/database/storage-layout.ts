import fs from 'fs';
import path from 'path';
import { USER_DATA_FOLDER } from '@common/paths';

export type PenguinStorageLayout = {
  userDataRoot: string;
  dataRoot: string;
  penguinsRoot: string;
  legacyDataRoot: string | null;
  migratedLegacyData: boolean;
};

const TRANSIENT_STORAGE_ERRORS = new Set(['ENOENT', 'ENOTDIR']);

function isTransientStorageError(error: unknown): boolean {
  const code = (error as NodeJS.ErrnoException | undefined)?.code;
  return typeof code === 'string' && TRANSIENT_STORAGE_ERRORS.has(code);
}

function sleepSync(milliseconds: number): void {
  // Atomics.wait is available in the Node 12 runtime bundled with Electron 10
  // and gives us a tiny synchronous backoff without adding another dependency.
  const buffer = new SharedArrayBuffer(4);
  const view = new Int32Array(buffer);
  Atomics.wait(view, 0, 0, milliseconds);
}

function ensureDirectorySync(directory: string): void {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      fs.mkdirSync(directory, { recursive: true });
      const stat = fs.statSync(directory);
      if (!stat.isDirectory()) throw new Error(`Storage path is not a directory: ${directory}`);
      return;
    } catch (error) {
      lastError = error;
      if (!isTransientStorageError(error) || attempt === 4) throw error;
      sleepSync(50 * attempt);
    }
  }
  throw lastError;
}

function directoryHasUserPenguins(directory: string): boolean {
  try {
    return fs.readdirSync(directory).some(file => /^(?:10[1-9]|1[1-9]\d|[2-9]\d{2,}|\d{4,})\.json$/.test(file));
  } catch (error) {
    if (isTransientStorageError(error)) return false;
    throw error;
  }
}

function copyMissingTreeSync(source: string, destination: string): number {
  if (!fs.existsSync(source)) return 0;
  ensureDirectorySync(destination);

  let copied = 0;
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    const sourcePath = path.join(source, entry.name);
    const destinationPath = path.join(destination, entry.name);

    if (entry.isDirectory()) {
      copied += copyMissingTreeSync(sourcePath, destinationPath);
      continue;
    }

    if (!entry.isFile() || fs.existsSync(destinationPath)) continue;
    fs.copyFileSync(sourcePath, destinationPath);
    copied++;
  }
  return copied;
}

function resolveLegacyDataRoot(): string | null {
  // Portable runtime intentionally stores mutable Waddle state under
  // <repo>/user-data. Older dev builds stored it directly under <repo>/data.
  // Only consider that legacy sibling when the active user-data root is really
  // named user-data; this avoids guessing paths for normal OS installs.
  if (path.basename(USER_DATA_FOLDER).toLowerCase() !== 'user-data') return null;
  const candidate = path.join(path.dirname(USER_DATA_FOLDER), 'data');
  const current = path.join(USER_DATA_FOLDER, 'data');
  return path.resolve(candidate) === path.resolve(current) ? null : candidate;
}

export function ensurePortablePenguinStorage(): PenguinStorageLayout {
  const dataRoot = path.join(USER_DATA_FOLDER, 'data');
  const penguinsRoot = path.join(dataRoot, 'penguins');
  const legacyDataRoot = resolveLegacyDataRoot();

  ensureDirectorySync(USER_DATA_FOLDER);

  let migratedLegacyData = false;
  if (legacyDataRoot !== null && fs.existsSync(legacyDataRoot)) {
    const legacyPenguins = path.join(legacyDataRoot, 'penguins');
    const portableHasUsers = directoryHasUserPenguins(penguinsRoot);
    const legacyHasUsers = directoryHasUserPenguins(legacyPenguins);

    if (!portableHasUsers && legacyHasUsers) {
      const copied = copyMissingTreeSync(legacyDataRoot, dataRoot);
      migratedLegacyData = copied > 0;
      console.log(`WADDLE_USER_DATA_MIGRATION=PASS source=${legacyDataRoot} destination=${dataRoot} copied=${copied} mode=copy_missing_preserve_legacy`);
    }
  }

  ensureDirectorySync(dataRoot);
  ensureDirectorySync(penguinsRoot);

  console.log(`WADDLE_PENGUIN_STORAGE=PASS user_data=${USER_DATA_FOLDER} data=${dataRoot} penguins=${penguinsRoot} migrated_legacy=${migratedLegacyData}`);

  return {
    userDataRoot: USER_DATA_FOLDER,
    dataRoot,
    penguinsRoot,
    legacyDataRoot,
    migratedLegacyData
  };
}

export async function withPenguinStorageRecovery<T>(label: string, operation: () => Promise<T>): Promise<T> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      ensurePortablePenguinStorage();
      return await operation();
    } catch (error) {
      lastError = error;
      if (!isTransientStorageError(error) || attempt === 4) throw error;
      console.warn(`WADDLE_PENGUIN_STORAGE=WARN operation=${label} attempt=${attempt} error=${error instanceof Error ? error.message : String(error)}`);
      await new Promise(resolve => setTimeout(resolve, 75 * attempt));
    }
  }

  throw lastError;
}
