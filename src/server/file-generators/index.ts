import fs from "fs";
import path from "path";

import { iterateEntries, MEDIA_DIRECTORY } from "@common/utils";
import { SettingsManager } from "@server/settings";
import { GameData } from "@server/timelines/game-data";
import { getChunkingMapJson } from "./chunking_map.json";
import getDependenciesJson from "./dependencies.json";
import { getEnvironmentDataXml } from "./environment_data.xml";
import { getGamesJson } from "./games.json";
import { getGameStrings } from "./game_strings.json";
import { getGeneralJson } from "./general.json";
import { getGlobalCrumbsSwf } from "./global_crumbs.swf";
import { getIglooMusicXml } from "./igloo_music.xml";
import { getLocalCrumbsSwf } from "./local_crumbs.swf";
import { getNewsTxt } from "./news.txt";
import { getNewspapersJson } from "./newspapers.json";
import { getNewsCrumbsSwf } from "./news_crumbs.swf";
import { getPaperItemsJson } from "./paper_items.json";
import { getPathsJson } from "./paths.json";
import { getPenguinActionFramesJson } from "./penguin_action_frames.json";
import { getRoomsJson } from "./rooms.json";
import { getSetupTxt } from "./setup.txt";
import { getSetupXml } from "./setup.xml";
import getStageScriptMessagesJson from "./stage_script_messages.json";
import { getStampsJson } from "./stamps.json";
import { getStartscreenXML } from "./startscreen.xml";
import { getVersionTxt } from "./version.txt";
import { getWorldAchievementsXml } from "./worldachievements.xml";

export type FileGenerator = (d: GameData, s: SettingsManager) => Buffer | string;

/**
 * paths.json historically merged timeline `localChanges` but silently ignored
 * `globalChanges`. Late-AS3 party code resolves most party UI through
 * SHELL.getPath() against the global table, so an asset could be routable by URL
 * yet impossible for the client to discover. Merge the generated global paths at
 * the generator boundary so this works for every modern party, not just Halloween.
 */
const getRuntimePathsJson: FileGenerator = (d) => {
  const paths = JSON.parse(getPathsJson(d)) as {
    global?: Record<string, string>;
    [key: string]: unknown;
  };

  paths.global = {
    ...(paths.global ?? {}),
    ...Object.fromEntries(d.getGlobalPaths())
  };

  return JSON.stringify(paths);
};

const HALLOWEEN_2015_LOCALIZATION_PREFIX = 'w.app.p2015.halloween.';
const MODERN_CONFIG_BUNDLE_ROUTE = 'play/en/web_service/game_configs.bin';

/**
 * Waddle historically generated game_strings.json from its own timeline. Modern
 * parties can additionally ship an immutable game_configs.bin together with the
 * exact game_strings.json that their SWFs were authored against. Serving the
 * bundle while discarding those strings leaves dialogue SWFs technically loaded
 * but with empty/missing text and can prevent dialogue-driven progression.
 *
 * When a preserved modern config bundle is active, read only its sibling
 * Halloween-2015 localization namespace and merge it over Waddle's generated
 * strings. The config-bundle route is temporary, so the overlay automatically
 * disappears when the party ends. Unrelated CPImagined strings are intentionally
 * not imported.
 */
const getRuntimeGameStringsJson: FileGenerator = (d) => {
  const base = JSON.parse(getGameStrings(d)) as {
    lang?: unknown[];
    [key: string]: unknown;
  };
  const configBundle = d.lookupFile(MODERN_CONFIG_BUNDLE_ROUTE);

  if (typeof configBundle !== 'string') {
    return JSON.stringify(base);
  }

  const sibling = path.join(path.dirname(configBundle), 'game_strings.json');
  const sourcePath = path.join(MEDIA_DIRECTORY, sibling);
  if (!fs.existsSync(sourcePath)) {
    throw new Error(`Modern config bundle is active but sibling game_strings.json is missing: ${sourcePath}`);
  }

  const preserved = JSON.parse(fs.readFileSync(sourcePath, 'utf8')) as {
    lang?: unknown[];
    [key: string]: unknown;
  };
  if (!Array.isArray(preserved.lang)) {
    throw new Error(`Invalid preserved game_strings.json: missing lang array at ${sourcePath}`);
  }

  const merged = new Map<string, string>();
  for (const entry of base.lang ?? []) {
    if (Array.isArray(entry) && entry.length >= 2 && typeof entry[0] === 'string' && typeof entry[1] === 'string') {
      merged.set(entry[0], entry[1]);
    }
  }

  let imported = 0;
  for (const entry of preserved.lang) {
    if (!Array.isArray(entry) || entry.length < 2 || typeof entry[0] !== 'string' || typeof entry[1] !== 'string') {
      continue;
    }
    const [key, value] = entry;
    if (!key.startsWith(HALLOWEEN_2015_LOCALIZATION_PREFIX)) {
      continue;
    }
    merged.set(key, value);
    imported++;
  }

  if (imported === 0) {
    throw new Error(`Preserved Halloween 2015 game_strings.json contains no ${HALLOWEEN_2015_LOCALIZATION_PREFIX} entries: ${sourcePath}`);
  }

  base.lang = Array.from(merged.entries());
  return JSON.stringify(base);
};

const GET_GENERATORS: Record<string, FileGenerator> = {
  'en/web_service/stamps.json': getStampsJson,
  'play/en/web_service/game_configs/stamps.json': getStampsJson,
  'play/en/web_service/game_configs/chunking_map.json': getChunkingMapJson,
  'play/en/web_service/game_configs/general.json': getGeneralJson,
  'play/v2/client/dependencies.json': getDependenciesJson,
  'play/v2/content/local/en/crumbs/local_crumbs.swf': getLocalCrumbsSwf,
  'play/en/web_service/game_configs/stage_script_messages.json': getStageScriptMessagesJson,
  'play/en/web_service/game_configs/paths.json': getRuntimePathsJson,
  'play/v2/content/global/crumbs/global_crumbs.swf': getGlobalCrumbsSwf,
  'play/en/web_service/game_configs/games.json': getGamesJson,
  'en/web_service/games.json': getGamesJson,
  'play/en/web_service/game_configs/paper_items.json': getPaperItemsJson,
  'play/en/web_service/game_configs/rooms.json': getRoomsJson,
  'setup.xml': getSetupXml,
  'play/v2/content/local/en/news/news_crumbs.swf': getNewsCrumbsSwf,
  'play/v2/content/local/en/login/startscreen.xml': getStartscreenXML,
  'playstart/xml/start_module_config.xml': getStartscreenXML,
  'web_service/worldachievements.xml': getWorldAchievementsXml,
  'play/v2/content/global/stampbook/world_stamps.xml': getWorldAchievementsXml,
  'play/en/web_service/game_configs/game_strings.json': getRuntimeGameStringsJson,
  'play/en/web_service/game_configs/newspapers.json': getNewspapersJson,
  'play/en/web_service/game_configs/penguin_action_frames.json': getPenguinActionFramesJson,
  'version.txt': getVersionTxt,
  'play/web_service/environment_data.xml': getEnvironmentDataXml,
  'play/v2/content/global/en/igloo_music.xml': getIglooMusicXml
};

const POST_GENERATORS: Record<string, FileGenerator> = {
  'setup.txt': getSetupTxt,
  'news.txt': getNewsTxt
};

function createGeneratorsMap(obj: Record<string, FileGenerator>): Map<string, FileGenerator> {
  const map = new Map<string, FileGenerator>();
  iterateEntries(obj, (key, value) => map.set(key, value));
  return map;
}

export function getGeneratorsMap(): Map<string, FileGenerator> {
  return createGeneratorsMap(GET_GENERATORS);
}

export function postGeneratorsMap(): Map<string, FileGenerator> {
  return createGeneratorsMap(POST_GENERATORS);
}
