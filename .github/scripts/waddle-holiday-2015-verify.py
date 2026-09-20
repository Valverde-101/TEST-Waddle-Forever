#!/usr/bin/env python3
"""Read-only source/manifest checks for Holiday 2015 timeline and party isolation."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'src/server/updates/2015.ts').read_text(encoding='utf-8')
NEXT = (ROOT / 'src/server/updates/2016.ts').read_text(encoding='utf-8')
FILES = (ROOT / 'src/server/game-data/files.ts').read_text(encoding='utf-8')
VIEW = (ROOT / 'src/client/views/timeline/timeline.ts').read_text(encoding='utf-8')
MANIFEST = json.loads((ROOT / 'media/default/holiday2015/manifest.json').read_text(encoding='utf-8'))
HOLIDAY = SOURCE.split('const holidayRef = ', 1)[1].split('export const UPDATES_2015:', 1)[0]

def require(condition: bool, reason: str) -> None:
    if not condition:
        raise AssertionError('WADDLE_HOLIDAY2015_TIMELINE=FAIL ' + reason)

PARTY_HANDLER = (ROOT / 'src/server/socket-server/handlers/party.ts').read_text(encoding='utf-8')
require("'holiday2015'," in FILES, 'archive_namespace_not_registered')
require('partyName' in VIEW and 'update.end' in VIEW, 'timeline_missing_party_start_end')
for date in ('2015-12-02', '2015-12-17'):
    require(re.search(r"date:\s*'" + date + r"'", SOURCE) is not None, 'start_date_missing=' + date)
require(re.search(r"date:\s*'2016-01-07'", NEXT) is not None, 'end_date_missing')
require("end: ['party']" in NEXT and "'2016-01-01'" not in NEXT, 'jan1_placeholder_masks_party')
require(re.search(r"date:\s*'2015-12-17'\s*,\s*end:\s*\['event'\]", SOURCE) is not None,
        'advent_not_closed_on_party_start')
require("partyName: 'Holiday Party 2015'" in SOURCE, 'holiday_name_missing')
require("partyName: 'Advent Calendar 2015'" in SOURCE, 'advent_name_missing')
require("id: 'holiday-2015'" in HOLIDAY and "id: 'halloween-2015'" not in HOLIDAY,
        'party_state_not_isolated')
require('fair2015:' not in HOLIDAY and 'fair#' not in HOLIDAY and 'halloween#' not in HOLIDAY,
        'cross_party_protocol_or_media')
require("holidayRef('party/client/ClientParty-HolidayParty2015.swf')" in HOLIDAY and
        "ref('client/QuestCommunicator.swf')" in HOLIDAY, 'holiday_runtime_or_shared_transport_missing')
require("ref('content/party-runtime-2015.swf')" not in HOLIDAY, 'halloween_robot_runtime_leaked')
# Source-level regressions that passed earlier SWF inventory checks while the
# genuine late-AS3 party UI stayed inert at runtime. The archived ClientParty
# explicitly resolves these four date-specific dialogue crumbs, QUEST_UI_PATH,
# and ITEM_COLLECT_UI_PATH. The inherited 2012 map did not include 2015 rooms.
require("map: 'approximation:modern_map.swf'" in HOLIDAY, 'old_2012_map_inherited')
require("activeFeatures: '20151100'" in HOLIDAY, 'holiday_feature_selector_missing')
require('getVirtualDate(0)' in PARTY_HANDLER and
        "partyConfig?.id === 'holiday-2015'" in PARTY_HANDLER and
        'unlockDayIndex = Math.min(' in PARTY_HANDLER,
        'holiday_partyservice_not_derived_from_selected_date')
for crumb in ('w.app.december1.loginprompt', 'w.app.december2.loginprompt',
              'w.app.december3.loginprompt', 'w.app.december4.loginprompt',
              'w.app.itemcollect.partyinterface', 'w.app.generic.partyinterface'):
    require(crumb in HOLIDAY, 'original_holiday_crumb_missing=' + crumb)

paths = {a['relativePath'] for a in MANIFEST['assets']}
refs = set(re.findall(r"""holidayRef\((?:'|")([^'"]+)(?:'|")\)""", HOLIDAY))
missing = refs - paths
require(not missing, 'untracked_holiday_refs=' + ','.join(sorted(missing)))
require(not (paths - refs), 'originals_not_mapped=' + ','.join(sorted(paths - refs)))
rooms = [a for a in MANIFEST['assets'] if a['section'] == 'rooms' and a['phase'] == 'party']
require(len(rooms) >= 40, 'room_inventory_incomplete')
for asset in rooms:
    require(asset['relativePath'] in refs, 'room_unmapped=' + asset['name'])
for pair in MANIFEST['roomMusic']:
    require(str(pair['musicId']) in HOLIDAY, 'room_music_unmapped=' + pair['room'])
print('WADDLE_HOLIDAY2015_TIMELINE=PASS advent=2015-12-02 party=2015-12-17'
      ' last_active=2016-01-06 exclusive_end=2016-01-07'
      ' rooms=' + str(len(rooms)) + ' mapped_assets=' + str(len(refs))
      + ' isolated=true bot_push=false')
