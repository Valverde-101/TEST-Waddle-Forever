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
let legacyMigrationChecked = false;
let legacyMigrationOccurred = false;
let lastPrepareLog = '';
let lastStorageLog = '';

function isTransientStorageError(error: unknown): boolean {
  const code = (error as NodeJS.ErrnoException | undefined)?.code;
  return typeof code === 'string' && TRANSIENT_STORAGE_ERRORS.has(code);
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
    }
  }
  throw lastError;
}

function readDirectorySync(directory: string): fs.Dirent[] {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      return fs.readdirSync(directory, { withFileTypes: true });
    } catch (error) {
      lastError = error;
      if (!isTransientStorageError(error) || attempt === 4) throw error;
    }
  }
  throw lastError;
}

function directoryHasUserPenguins(directory: string): boolean {
  if (!fs.existsSync(directory)) return false;
  return readDirectorySync(directory).some(entry => entry.isFile() && /^(?:10[1-9]|1[1-9]\d|[2-9]\d{2,}|\d{4,})\.json$/.test(entry.name));
}

function copyMissingTreeSync(source: string, destination: string): number {
  if (!fs.existsSync(source)) return 0;
  ensureDirectorySync(destination);

  let copied = 0;
  for (const entry of readDirectorySync(source)) {
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

function getLayout(): PenguinStorageLayout {
  const dataRoot = path.join(USER_DATA_FOLDER, 'data');
  return {
    userDataRoot: USER_DATA_FOLDER,
    dataRoot,
    penguinsRoot: path.join(dataRoot, 'penguins'),
    legacyDataRoot: resolveLegacyDataRoot(),
    migratedLegacyData: legacyMigrationOccurred
  };
}

function logOnceOrChanged(kind: 'prepare' | 'storage', message: string): void {
  if (kind === 'prepare') {
    if (message === lastPrepareLog) return;
    lastPrepareLog = message;
  } else {
    if (message === lastStorageLog) return;
    lastStorageLog = message;
  }
  console.log(message);
}

/**
 * Prepare portable storage before DataFolder.init().
 *
 * Important: when there is no legacy database, this deliberately does NOT
 * create <user-data>/data. DataFolder uses existence of that directory to
 * distinguish a brand-new database from an old database that needs migrations.
 */
export function preparePortablePenguinStorage(): PenguinStorageLayout {
  ensureDirectorySync(USER_DATA_FOLDER);

  let layout = getLayout();
  const legacyDataRoot = layout.legacyDataRoot;

  if (!legacyMigrationChecked) {
    if (legacyDataRoot === null || !fs.existsSync(legacyDataRoot)) {
      legacyMigrationChecked = true;
    } else {
      const legacyPenguins = path.join(legacyDataRoot, 'penguins');
      const portableHasUsers = directoryHasUserPenguins(layout.penguinsRoot);
      const legacyHasUsers = directoryHasUserPenguins(legacyPenguins);

      if (!portableHasUsers && legacyHasUsers) {
        const copied = copyMissingTreeSync(legacyDataRoot, layout.dataRoot);
        legacyMigrationOccurred = copied > 0;
        console.log(`WADDLE_USER_DATA_MIGRATION=PASS source=${legacyDataRoot} destination=${layout.dataRoot} copied=${copied} mode=copy_missing_preserve_legacy`);
      }
      // A successful inspection is authoritative for this process. If storage
      // later disappears, ensurePortablePenguinStorage repairs the active tree;
      // it does not repeatedly traverse the legacy database every 1.5 seconds.
      legacyMigrationChecked = true;
    }
    layout = getLayout();
  }

  logOnceOrChanged('prepare', `WADDLE_USER_DATA_PREPARE=PASS user_data=${layout.userDataRoot} data_exists=${fs.existsSync(layout.dataRoot)} legacy=${layout.legacyDataRoot ?? 'none'} migrated_legacy=${layout.migratedLegacyData}`);
  return layout;
}

/** Ensure the final data/penguins hierarchy exists after DataFolder.init(). */
export function ensurePortablePenguinStorage(): PenguinStorageLayout {
  const prepared = preparePortablePenguinStorage();
  ensureDirectorySync(prepared.dataRoot);
  ensureDirectorySync(prepared.penguinsRoot);

  logOnceOrChanged('storage', `WADDLE_PENGUIN_STORAGE=PASS user_data=${prepared.userDataRoot} data=${prepared.dataRoot} penguins=${prepared.penguinsRoot} migrated_legacy=${prepared.migratedLegacyData}`);
  return prepared;
}

/**
 * Retry an individual repository operation when SMB briefly reports a directory
 * as missing. This is the exact failure observed during XML login (ENOENT from
 * scandir .../data/penguins).
 */
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
