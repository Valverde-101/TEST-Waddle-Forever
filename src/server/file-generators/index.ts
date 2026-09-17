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

const LATE_AS3_FEATURES_ROUTE = 'play/v2/content/global/content/features.swf';
const LATE_AS3_FEATURES_CRUMB = 'w.app.generic.features';

/**
 * paths.json historically merged timeline `localChanges` but silently ignored
 * `globalChanges`. Late-AS3 party code resolves most party UI through
 * SHELL.getPath() against the global table, so an asset could be routable by URL
 * yet impossible for the client to discover. Merge the generated global paths at
 * the generator boundary so this works for every modern party, not just Halloween.
 *
 * Templated late-AS3 party runtimes additionally discover the PartyJSON feature
 * payload through the hard-coded `w.app.generic.features` crumb. Some preserved
 * party definitions mount Features as a direct runtime file rather than a crumb
 * overlay, so synthesize the crumb whenever the selected timeline has a Features
 * route. Without this, the party icon can load but quests/transformations never
 * bootstrap because the runtime cannot find `features.swf`.
 */
const getRuntimePathsJson: FileGenerator = (d) => {
  const paths = JSON.parse(getPathsJson(d)) as {
    global?: Record<string, string>;
    [key: string]: unknown;
  };

  paths.global = {
    ...(paths.global ?? {}),
    ...(d.lookupFile(LATE_AS3_FEATURES_ROUTE) !== undefined
      ? { [LATE_AS3_FEATURES_CRUMB]: 'content/features.swf' }
      : {}),
    ...Object.fromEntries(d.getGlobalPaths())
  };

  return JSON.stringify(paths);
};

const HALLOWEEN_2015_SOLO_ROOM_ROUTE = 'play/v2/content/global/rooms/partysolo1.swf';

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
 * Halloween 2015 also introduces a private event room, partysolo1, with canonical
 * room id 891. Its SWF was already preserved and routed, but the base Waddle room
 * snapshot predates the room metadata. Without the 891 entry the Mine Shack
 * hotspot can emit a join for a room the late-AS3 client cannot resolve/load.
 * Mount the room only while the exact timeline route is active so it cannot leak
 * into other dates or parties.
 */
const getRuntimeRoomsJson: FileGenerator = (d, s) => {
  const rooms = JSON.parse(getRoomsJson(d, s)) as Record<string, {
    room_id?: number;
    room_key?: string;
    name?: string;
    display_name?: string;
    music_id?: number;
    is_member?: number;
    path?: string;
    max_users?: number;
    jump_enabled?: boolean;
    jump_disabled?: boolean;
    required_item?: number | null;
    short_name?: string;
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

  if (d.lookupFile(HALLOWEEN_2015_SOLO_ROOM_ROUTE) !== undefined) {
    rooms['891'] = {
      room_id: 891,
      room_key: 'partysolo1',
      name: 'partysolo1',
      display_name: 'Secret Lab',
      // The preserved Halloween SWF controls its own event audio. Do not import
      // the later recreation's 2055 soundtrack into the exact 2015 stack.
      music_id: 0,
      is_member: 0,
      path: 'partysolo1.swf',
      max_users: 800,
      jump_enabled: true,
      jump_disabled: false,
      required_item: null,
      short_name: 'partysolo1'
    };
  } else {
    delete rooms['891'];
  }

  return JSON.stringify(rooms);
};

const HALLOWEEN_2015_LOCALIZATION_PREFIX = 'w.app.p2015.halloween.';
const HALLOWEEN_2015_LOCALIZATION_COUNT = 38;
const HALLOWEEN_2015_LOCALIZATION_FILE = 'halloween2015_dialogue_strings.json';
const MODERN_CONFIG_BUNDLE_ROUTE = 'play/en/web_service/game_configs.bin';

type RuntimeGameStringsJson = {
  lang?: unknown[];
  [key: string]: unknown;
};

const mergeRuntimeStringEntries = (
  base: RuntimeGameStringsJson,
  entries: Iterable<readonly [string, string]>
): Map<string, string> => {
  const merged = new Map<string, string>();

  for (const entry of base.lang ?? []) {
    if (Array.isArray(entry) && entry.length >= 2 && typeof entry[0] === 'string' && typeof entry[1] === 'string') {
      merged.set(entry[0], entry[1]);
    }
  }

  for (const [key, value] of entries) {
    if (typeof key === 'string' && typeof value === 'string') {
      merged.set(key, value);
    }
  }

  base.lang = Array.from(merged.entries());
  return merged;
};

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
  const base = JSON.parse(getGameStrings(d)) as RuntimeGameStringsJson;
  const merged = mergeRuntimeStringEntries(base, d.getGameStrings());
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
