import { DataFolder, PenguinRepository } from './database/database';
import { ensurePortablePenguinStorage } from './database/storage-layout';
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
  // Repair/create the portable storage hierarchy before DatabaseMigrator or
  // PenguinRepository touch it. This also imports a legacy <repo>/data tree
  // into <repo>/user-data/data without deleting the old copy.
  const storage = ensurePortablePenguinStorage();

  const data = new DataFolder(USER_DATA_FOLDER);
  data.init(VERSION);

  // DataFolder migrations can create/update files, so assert the penguin
  // directory once more before constructing the repository used by login/world.
  ensurePortablePenguinStorage();

  const gameData = new GameData(settingsManager);

  const db = new PenguinRepository(data.getPath());

  console.log(`WADDLE_DATABASE_READY=PASS data=${storage.dataRoot} penguins=${storage.penguinsRoot} legacy=${storage.legacyDataRoot ?? 'none'}`);

  await setupLoginServer(settingsManager, db, gameData);

  const world = await setupWorldServer(settingsManager, db, gameData);

  await (new HttpServer(gameData, settingsManager, db)).setupServer();

  return world;
}
