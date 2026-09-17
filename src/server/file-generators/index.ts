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

/**
 * rooms.json contains a small amount of late-game static metadata that was
 * originally captured from one particular 2017 snapshot. That metadata must not
 * leak backwards through Waddle's historical timeline.
 *
 * Community Pin 7308 existed in the Coffee Shop only from 2017-01-31 through
 * 2017-03-29 (the next pin period starts 2017-03-30). Outside that interval the
 * room must not advertise the pin, otherwise older clients request
 * content/room_pin/7308.swf while replaying unrelated years such as 2015.
 *
 * Keep the canonical room table unchanged and normalize only the generated view;
 * this makes the fix date-driven and avoids hiding the symptom with a future SWF.
 */
const getRuntimeRoomsJson: FileGenerator = (d, s) => {
  const rooms = JSON.parse(getRoomsJson(d, s)) as Record<string, {
    pin_id?: number;
    pin_x?: number;
    pin_y?: number;
    [key: string]: unknown;
  }>;
  const version = s.settings.version;
  const communityPinActive = version >= '2017-01-31' && version < '2017-03-30';
  const coffee = rooms['110'];

  if (!communityPinActive && coffee?.pin_id === 7308) {
    delete coffee.pin_id;
    delete coffee.pin_x;
    delete coffee.pin_y;
  }

  return JSON.stringify(rooms);
};

const HALLOWEEN_2015_LOCALIZATION_PREFIX = 'w.app.p2015.halloween.';
const HALLOWEEN_2015_LOCALIZATION_COUNT = 38;
const HALLOWEEN_2015_LOCALIZATION_FILE = 'halloween2015_dialogue_strings.json';
const MODERN_CONFIG_BUNDLE_ROUTE = 'play/en/web_service/game_configs.bin';

/**
 * Waddle historically generated game_strings.json from its own timeline. Modern
 * parties can additionally ship an immutable game_configs.bin. Halloween 2015's
 * preserved bundle contains only the custom finale subset of the localization
 * namespace, while the original dialogue SWFs require 38 keys in total.
 *
 * Keep the preserved bundle byte-for-byte intact and mount the complete,
 * versioned localization contract stored beside it. The config-bundle route is
 * temporary, so the overlay automatically disappears when the party ends. Only
 * the Halloween namespace is imported; unrelated strings can never leak into
 * other dates or parties.
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

  const localizationRelativePath = path.join(path.dirname(configBundle), HALLOWEEN_2015_LOCALIZATION_FILE);
  const localizationPath = path.join(MEDIA_DIRECTORY, localizationRelativePath);
  if (!fs.existsSync(localizationPath)) {
    throw new Error(`Halloween 2015 config bundle is active but localization contract is missing: ${localizationPath}`);
  }

  const localization = JSON.parse(fs.readFileSync(localizationPath, 'utf8')) as {
    namespace?: unknown;
    strings?: Record<string, unknown>;
    totalKeys?: unknown;
  };
  if (localization.namespace !== HALLOWEEN_2015_LOCALIZATION_PREFIX || localization.totalKeys !== HALLOWEEN_2015_LOCALIZATION_COUNT || localization.strings === null || typeof localization.strings !== 'object') {
    throw new Error(`Invalid Halloween 2015 localization contract: ${localizationPath}`);
  }

  const entries = Object.entries(localization.strings);
  if (entries.length !== HALLOWEEN_2015_LOCALIZATION_COUNT) {
    throw new Error(`Halloween 2015 localization contract expected ${HALLOWEEN_2015_LOCALIZATION_COUNT} keys but found ${entries.length}: ${localizationPath}`);
  }

  const merged = new Map<string, string>();
  for (const entry of base.lang ?? []) {
    if (Array.isArray(entry) && entry.length >= 2 && typeof entry[0] === 'string' && typeof entry[1] === 'string') {
      merged.set(entry[0], entry[1]);
    }
  }

  for (const [key, value] of entries) {
    if (!key.startsWith(HALLOWEEN_2015_LOCALIZATION_PREFIX) || typeof value !== 'string' || value.trim().length === 0) {
      throw new Error(`Invalid Halloween 2015 localization entry: ${key}`);
    }
    merged.set(key, value);
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
  'play/en/web_service/game_configs/rooms.json': getRuntimeRoomsJson,
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
