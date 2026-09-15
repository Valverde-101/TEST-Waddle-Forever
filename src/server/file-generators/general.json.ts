import { GameData } from "@server/timelines/game-data";

const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';

export function getGeneralJson(d: GameData): string {
  const hunt = d.getHunt();
  const fair = d.getFair();
  // Modern interfaces gate their party button on party_options.party_icon_active.
  // Derive it from the canonical routed asset instead of a party-specific flag so
  // any modern party that supplies content/party_icon.swf activates the UI.
  const modernPartyIconActive = d.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined;

  return JSON.stringify({
    "mascot_options": {
      "migrator_active": d.getMigrator()
    },
    "party_options": {
      "fair_ticket_active": d.getFair(),
      "hunt_active": hunt !== null || fair || d.getPartyIcon(),
      "itemRewardID": hunt?.global.reward ?? 0,
      "isMapNoteActive": d.getMapNote(),
      "showPartyAnnouncement": false,
      "party_icon_active": modernPartyIconActive,
      unlockedDay: d.getUnlockedDay()
    },
    "igloo_options": {
      "contestRunning": false
    },
    "oops_test": {
      "testEnabled": true
    },
    "island_options": {
      "isDaytime": true
    },
    "party_dates": {
      "20170201": "2017-01-30"
    }
  })
}
