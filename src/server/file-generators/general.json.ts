import { GameData } from "@server/timelines/game-data";

const MODERN_PARTY_ICON_ROUTE = 'play/v2/content/global/content/party_icon.swf';
const HALLOWEEN_2015_PARTY_ID = 'halloween-2015';

export function getGeneralJson(d: GameData): string {
  // Halloween 2015 uses the preserved 2015 icon/quest stack on top of Waddle's
  // late-AS3 base map. The archived 2015 interaction family does not contain a
  // compatible party_map_note asset; advertising one makes the base map request
  // close_ups/party_map_note.swf and produces a deterministic 404. Keep the
  // quest/icon switches enabled, but explicitly disable only that unsupported
  // map-note surface until an authentic compatible 2015 map-note is preserved.
  if (d.getPartyProgress()?.id === HALLOWEEN_2015_PARTY_ID) {
    return JSON.stringify({
      "mascot_options": {
        "migrator_active": true
      },
      "party_options": {
        "fair_ticket_active": false,
        "hunt_active": true,
        "itemRewardID": 1388,
        "isMapNoteActive": false,
        "showPartyAnnouncement": false,
        "party_icon_active": true
      },
      "igloo_options": {
        "contestRunning": false
      },
      "oops_test": {
        "testEnabled": true
      },
      "island_options": {
        "isDaytime": false
      },
      "party_dates": {
        "20170201": "2017-01-30"
      }
    });
  }

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
