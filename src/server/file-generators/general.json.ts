import { GameData } from "@server/timelines/game-data";

const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';

export function getGeneralJson(d: GameData): string {
  const hunt = d.getHunt();
  const fair = d.getFair();
  // Late-AS3 interfaces use both flags. `party_icon_active` controls loading the
  // icon module while `hunt_active` enables its scavenger/quest interaction path.
  // Derive both from the canonical modern party icon route so a party cannot end
  // up in the broken state where party_icon.swf downloads successfully but its
  // UI remains inert. Legacy scavenger hunts/fairs keep their existing signals.
  const modernPartyIconActive = d.lookupFile(MODERN_PARTY_ICON_ROUTE) !== undefined;

  return JSON.stringify({
    "mascot_options": {
      "migrator_active": d.getMigrator()
    },
    "party_options": {
      "fair_ticket_active": d.getFair(),
      "hunt_active": hunt !== null || fair || d.getPartyIcon() || modernPartyIconActive,
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
