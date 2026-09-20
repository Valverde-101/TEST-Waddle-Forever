#!/usr/bin/env python3
"""Validate unchanged Fair source SWFs and the exact local-domain rewrite slot.

The runtime patch is constrained to the standalone AVM1 checkDomain string.
This check fails closed if a future archive SWF changes bytecode layout.
"""
from pathlib import Path
import json
import zlib

root = Path(__file__).resolve().parents[2]
assets = root / "media/default/fair2015"
manifest = json.loads((assets / "minigames/manifest.json").read_text(encoding="utf-8"))
by_path = {e["relativePath"]: e for e in manifest["assets"]}
needle = b"clubpenguin.com\0"
for rel in (
    "minigames/daily_spin/GamesSpinBootstrap.swf",
    "minigames/daily_spin/GamesSpinMain.swf",
):
    raw = (assets / rel).read_bytes()
    assert len(raw) == by_path[rel]["bytes"], f"original bytes changed: {rel}"
    import hashlib
    assert hashlib.sha256(raw).hexdigest() == by_path[rel]["sha256"], f"original hash changed: {rel}"
    compression = raw[:3]
    assert compression in (b"CWS", b"FWS"), f"unsupported compression: {rel}"
    body = zlib.decompress(raw[8:]) if compression == b"CWS" else raw[8:]
    assert len(body) + 8 == int.from_bytes(raw[4:8], "little"), f"bad SWF length: {rel}"
    matches = []
    index = 0
    while True:
        index = body.find(needle, index)
        if index == -1:
            break
        before = body[index-1] if index else 0
        if not (chr(before).isascii() and (chr(before).isalnum() or chr(before) in "./:*_-")):
            matches.append(index)
        index += len(needle)
    print(f"WADDLE_FAIR2015_LOCAL_DOMAIN_AS2 file={rel} candidates={len(matches)} offsets={matches}")
    assert len(matches) == 1, f"not exactly one standalone Security.checkDomain literal: {rel}: {matches}"
    patched = bytearray(body)
    patched[matches[0]:matches[0]+len(needle)-1] = b"127.0.0.1:24105"
    assert len(patched) == len(body)
    assert body[:matches[0]] == patched[:matches[0]]
    assert body[matches[0]+len(needle):] == patched[matches[0]+len(needle):]
code = (root / "src/server/updates/2015.ts").read_text(encoding="utf-8")
assert "'play/v2/content/global/content/map.swf': 'approximation:modern_map.swf'" in code
assert (root / "media/default/approximation/modern_map.swf").is_file()
assert code.count("'play/v2/games/cp_party_games/spin/spin.swf':") == 1
server = (root / "src/server/file-server/index.ts").read_text(encoding="utf-8")
assert "patchFair2015GameSecurity" in server and "default/fair2015/minigames/daily_spin/" in server
print("WADDLE_FAIR2015_MAP_SPIN_SOURCE=PASS map_exists=true routes=unique fair_runtime=isolated")
