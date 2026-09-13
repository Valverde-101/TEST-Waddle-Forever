import { DataFolder, PenguinRepository } from './database/database';
import { ensurePortablePenguinStorage, preparePortablePenguinStorage } from './database/storage-layout';
import { VERSION } from '@common/constants';
import { USER_DATA_FOLDER } from '@common/paths';
import settingsManager from './settings';
import { GameData } from './timelines/game-data';

import { HttpServer } from './http';
import { setupWorldServer } from './socket-server/world-server';
import { setupLoginServer } from './socket-server/login-server';


/** Initialize the mods. Returns a list of any that failed to start. */
export function startMods(): string[] {
  return settingsManager.mods.initializeMods();
}

/** Initialize the db, game data, and the 3 services (http, login, world). Returns the world server. */
export async function startServices() {
  // First recover legacy <repo>/data if it exists, but do not create a brand
  // new data directory here. DataFolder.init() owns the new-vs-migrate decision.
  preparePortablePenguinStorage();

  const data = new DataFolder(USER_DATA_FOLDER);
  data.init(VERSION);

  // Once DataFolder has initialized/migrated the database, enforce the complete
  // portable hierarchy used by login, world and Command Center.
  const storage = ensurePortablePenguinStorage();

  const gameData = new GameData(settingsManager);

  const db = new PenguinRepository(data.getPath());

  console.log(`WADDLE_DATABASE_READY=PASS data=${storage.dataRoot} penguins=${storage.penguinsRoot} legacy=${storage.legacyDataRoot ?? 'none'}`);

  await setupLoginServer(settingsManager, db, gameData);

  const world = await setupWorldServer(settingsManager, db, gameData);

  await (new HttpServer(gameData, settingsManager, db)).setupServer();

  return world;
}
