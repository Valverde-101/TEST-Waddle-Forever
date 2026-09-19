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
assert len(list(assets.rglob("*.swf"))) == 194
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
print(f"WADDLE_FAIR2015_VERIFY=PASS main=141 minigames=53 total={len(seen)} rooms={len(room_names)} music={len(music_names)} paths={len(references)} halloween=preserved timeline=scoped")
