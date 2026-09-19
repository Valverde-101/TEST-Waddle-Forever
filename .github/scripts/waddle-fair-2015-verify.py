#!/usr/bin/env python3
"""Fail-closed, read-only Fair archive and timeline verification."""
import hashlib
import json
from pathlib import Path
import re
import sys

repo = Path(__file__).resolve().parents[2]
assets = repo / "media/default/fair2015"
main = json.loads((assets / "manifest.json").read_text(encoding="utf-8"))
games = json.loads((assets / "minigames/manifest.json").read_text(encoding="utf-8"))
assert main["schema"] == "waddle-fair-2015-assets/v1" and main["count"] == 141
assert games["schema"] == "waddle-fair-2015-minigames/v1" and games["count"] == 53
assert len(main["assets"]) == 141 and len(games["assets"]) == 53
all_assets = main["assets"] + games["assets"]
seen = set()
for asset in all_assets:
    relative = asset["relativePath"]
    assert relative not in seen, f"duplicate {relative}"
    seen.add(relative)
    path = (assets / relative).resolve()
    assert assets.resolve() in path.parents, f"unsafe path {relative}"
    blob = path.read_bytes()
    assert len(blob) == asset["bytes"] and len(blob) >= 100, f"wrong bytes {relative}"
    assert blob[:3] in (b"FWS", b"CWS", b"ZWS"), f"invalid SWF {relative}"
    assert hashlib.sha256(blob).hexdigest().lower() == asset["sha256"].lower(), f"wrong sha {relative}"
    assert asset["url"].startswith("https://toolbox.solero.me/cparchives/static/images/archives/"), f"untrusted archive URL {relative}"
# The event controller is preserved in CPImagined's independently pinned Fair
# mediaserver archive. Verify the isolated supplement instead of requiring
# guessed archive filenames for a separate ClientParty/intro module.
cp_manifest_path = assets / "cpimagined/manifest.json"
assert cp_manifest_path.is_file(), "WADDLE_FAIR2015_RUNTIME_READY=FAIL CPImagined Fair supplement missing"
cp_manifest = json.loads(cp_manifest_path.read_text(encoding="utf-8"))
assert cp_manifest.get("schema") == "waddle-fair-2015-cpimagined/v1"
cp_assets = cp_manifest.get("assets", [])
assert {entry.get("relativePath") for entry in cp_assets} == {
    "cpimagined/content/party.swf",
    "cpimagined/content/map.swf",
    "cpimagined/content/room_pin/7236.swf",
}
cp_seen = set()
for entry in cp_assets:
    relative = entry["relativePath"]
    path = (assets / relative).resolve()
    assert assets.resolve() in path.parents and path.is_file(), f"missing CPImagined asset {relative}"
    blob = path.read_bytes()
    assert blob[:3] in (b"FWS", b"CWS", b"ZWS")
    assert len(blob) == entry["bytes"]
    assert hashlib.sha256(blob).hexdigest().lower() == entry["sha256"].lower()
    cp_seen.add(relative)

# These three files are deliberately isolated from the 194 archive originals;
# no Halloween asset is copied into the Fair namespace.
assert not (seen & cp_seen), "Fair supplement collides with archive originals"
assert len(list(assets.rglob("*.swf"))) == 197
print("WADDLE_FAIR2015_RUNTIME_READY=PASS controller=cpimagined_party pinned=true isolated=true")

code = (repo / "src/server/updates/2015.ts").read_text(encoding="utf-8")
registry = (repo / "src/server/game-data/files.ts").read_text(encoding="utf-8")
assert "const FAIR2015 = 'fair2015';" in registry and "  FAIR2015," in registry
assert "date: '2015-05-20'" in code and "date: '2015-06-11', end: ['party']" in code
assert "date:'2015-10-21'" in code and "partyName:'Halloween Party 2015'" in code
fair = code[code.index("date: '2015-05-20'"):code.index("date: '2015-06-11'")]
assert "party2015:" not in fair and "halloween-2015" not in fair
references = set(re.findall(r"fairRef\('([^']+)'\)", code))
known_refs = seen | cp_seen
assert references and references.issubset(known_refs), f"missing refs {sorted(references - known_refs)}"
rooms = re.search(r"const FAIR_2015_ROOMS = \{(.*?)\n\};", code, re.S).group(1)
music = re.search(r"const FAIR_2015_MUSIC = \{(.*?)\n\};", code, re.S).group(1)
room_names = re.findall(r"^\s*'([^']+)': fairRef", rooms, re.M)
music_names = re.findall(r"^\s*'([^']+)': \d+", music, re.M)
assert len(room_names) == 46 and len(set(room_names)) == 46, "room map invalid"
assert set(room_names) == set(music_names), "room / music divergence"
assert set(range(1, 13)).issubset({int(x[5:]) for x in room_names if re.fullmatch(r"party\d+", x)}), "party rooms missing"
# Static source-contract regression checks are not a substitute for a live
# click/game test. They prevent reintroducing the specific broken routes seen
# in the first Fair diagnostics and the native MayParty first-login handshake.
fair_xt = (repo / "src/server/socket-server/xt-handler.ts").read_text(encoding="utf-8")
assert "['s%fair#fmsgviewed', 's%party#msgviewed']" in fair_xt, "native Fair first-login message is unhandled"
world_handlers = (repo / "src/server/socket-server/world-handlers.ts").read_text(encoding="utf-8")
fair_handler = (repo / "src/server/socket-server/handlers/fair.ts").read_text(encoding="utf-8")
party_store = (repo / "src/server/game-logic/party-progress.ts").read_text(encoding="utf-8")
assert "fair#fsilverjr" in world_handlers and "handleFairSilverJoin" in fair_handler
assert "spendFairSilverTicket" in party_store, "Fair silver-ticket state is not isolated"
for ui_key in ("w.p2015.may.partyinterface", "w.p2015.may.login",
               "w.p2015.may.rideprompt", "w.p2015.may.partymap",
               "w.avatarSprite.coyote", "w.avatarSprite.crab",
               "w.avatarSprite.dragon", "w.avatarSprite.robo"):
    assert ui_key in fair, f"original Fair showContent key not mapped: {ui_key}"
minigame_changes = code[code.index("const FAIR_2015_MINIGAME_FILES = {"):code.index("\n};", code.index("const FAIR_2015_MINIGAME_FILES = {"))]
for route in ("spin/bootstrap.swf", "spin/main.swf", "bell/bootstrap.swf",
              "paddle/bootstrap.swf", "shuffle/bootstrap.swf", "bounce/main.swf"):
    assert "play/v2/games/cp_party_games/" + route in minigame_changes, "missing game route: " + route
assert "minigames/daily_spin/GamesSpinBootstrap.swf" in minigame_changes
assert "minigames/daily_spin/GamesSpinMain.swf" in minigame_changes
runtime_generators = (repo / "src/server/file-generators/index.ts").read_text(encoding="utf-8")
assert "getRuntimeGamesJson" in runtime_generators
for game_path in (
    "cp_party_games/balloon_pop/main.swf",
    "cp_party_games/bell/bootstrap.swf",
    "cp_party_games/feed_a_puffle/main.swf",
    "cp_party_games/memory_card_game/main.swf",
    "cp_party_games/paddle/bootstrap.swf",
    "cp_party_games/shuffle/bootstrap.swf",
    "cp_party_games/spin/bootstrap.swf",
    "cp_party_games/bounce/launcher.swf",
    "cp_party_games/puffle_soaker/main.swf",
):
    assert game_path in runtime_generators, "Fair games.json route not scoped: " + game_path
assert "'play/v2/content/global/content/party.swf': fairRef('cpimagined/content/party.swf')" in fair
assert "intro_to_cp.swf': 'svanilla:media/play/v2/client/world.swf" not in fair
print("WADDLE_FAIR2015_CONTRACT=PASS first_login=fmsgviewed interactive_keys=8 silver_join=fsilverjr game_routes=9")
print(f"WADDLE_FAIR2015_VERIFY=PASS main=141 minigames=53 total={len(seen)} rooms={len(room_names)} music={len(music_names)} paths={len(references)} halloween=preserved timeline=scoped")
