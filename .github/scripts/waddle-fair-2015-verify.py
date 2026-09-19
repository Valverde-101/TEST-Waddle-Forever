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
# A green inventory check is not proof of a working party. The May 2015
# controller and original intro must be pinned and available before this PR
# can be considered integration-ready. They cannot be substituted with Ghosts,
# Halloween or world.swf without launching incompatible/duplicate clients.
runtime_manifest_path = assets / "client-runtime-manifest.json"
assert runtime_manifest_path.is_file(), (
    "WADDLE_FAIR2015_RUNTIME_READY=FAIL original May party runtime and intro "
    "not imported; the party icon/minigames cannot be declared functional"
)
runtime_manifest = json.loads(runtime_manifest_path.read_text(encoding="utf-8"))
assert runtime_manifest.get("schema") == "waddle-fair-2015-client-runtime/v1"
runtime_assets = runtime_manifest.get("assets", [])
assert {entry.get("role") for entry in runtime_assets} == {"party", "intro"}, (
    "WADDLE_FAIR2015_RUNTIME_READY=FAIL original client roles incomplete"
)
required_client_paths = {
    "client/ClientParty-Fair2015_2.swf",
    "client/ClientIntro_to_cp-06102015.swf",
}
assert {entry.get("relativePath") for entry in runtime_assets} == required_client_paths
for entry in runtime_assets:
    client_file = (assets / entry["relativePath"]).resolve()
    assert assets.resolve() in client_file.parents and client_file.is_file()
    original = client_file.read_bytes()
    assert original[:3] in (b"FWS", b"CWS", b"ZWS")
    assert len(original) == entry["bytes"]
    assert hashlib.sha256(original).hexdigest().lower() == entry["sha256"].lower(), (
        "WADDLE_FAIR2015_RUNTIME_READY=FAIL original client checksum mismatch"
    )
assert len(list(assets.rglob("*.swf"))) == 194 + len(runtime_assets)
print("WADDLE_FAIR2015_RUNTIME_READY=PASS originals=2 pinned=true")

code = (repo / "src/server/updates/2015.ts").read_text(encoding="utf-8")
registry = (repo / "src/server/game-data/files.ts").read_text(encoding="utf-8")
assert "const FAIR2015 = 'fair2015';" in registry and "  FAIR2015," in registry
assert "date: '2015-05-20'" in code and "date: '2015-06-11', end: ['party']" in code
assert "date:'2015-10-21'" in code and "partyName:'Halloween Party 2015'" in code
fair = code[code.index("date: '2015-05-20'"):code.index("date: '2015-06-11'")]
assert "party2015:" not in fair and "halloween-2015" not in fair
references = set(re.findall(r"fairRef\('([^']+)'\)", code))
assert references and references.issubset(seen), f"missing refs {sorted(references - seen)}"
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
for ui_key in ("w.p2015.may.partyinterface", "w.p2015.may.login",
               "w.p2015.may.rideprompt", "w.p2015.may.partymap"):
    assert ui_key in fair, f"original Fair showContent key not mapped: {ui_key}"
minigame_changes = code[code.index("const FAIR_2015_MINIGAME_FILES = {"):code.index("\n};", code.index("const FAIR_2015_MINIGAME_FILES = {"))]
for route in ("spin/bootstrap.swf", "spin/main.swf", "bell/bootstrap.swf",
              "paddle/bootstrap.swf", "shuffle/bootstrap.swf", "bounce/main.swf"):
    assert "play/v2/games/cp_party_games/" + route in minigame_changes, "missing game route: " + route
assert "minigames/daily_spin/GamesSpinBootstrap.swf" in minigame_changes
assert "minigames/daily_spin/GamesSpinMain.swf" in minigame_changes
print("WADDLE_FAIR2015_CONTRACT=PASS first_login=fmsgviewed interactive_keys=4 game_routes=6")
print(f"WADDLE_FAIR2015_VERIFY=PASS main=141 minigames=53 total={len(seen)} rooms={len(room_names)} music={len(music_names)} paths={len(references)} halloween=preserved timeline=scoped")
