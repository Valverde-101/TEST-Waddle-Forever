#!/usr/bin/env python3
"""Produce an isolated May 2015 island map that defers to Fair's native map note.

The archived March 2015 map avoids later Puffle icons. Its default onPress
interferes with the original Fair note onRelease; change only that one hook.
Preserve both source SWFs, every other map action and the original party map.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "media/default/fair2015/period/ContentMap-03262015.swf"
SOURCE_SHA = "5cf40f5b683d19d646ca8a8dd9002173c91892c72efe7c8581f17e92f79135f5"
TARGET = ROOT / "media/default/fair2015/compat/FairIslandMap.swf"
MANIFEST = ROOT / "media/default/fair2015/compat/island_map_manifest.json"
NOTE = ROOT / "media/default/fair2015/close_ups/ENCloseUpsPartyMapNote-TheFair2015.swf"
PARTY_MAP = ROOT / "media/default/fair2015/close_ups/ENCloseUpsPartyMap-TheFair2015.swf"
PATTERN = re.compile(r"NOTE\.goThereBtn\.onPress = mapButtonDelegate;")
REPLACEMENT = "NOTE.goThereBtn.onPress = null;"
FAIR_NOTE_ACTION = "noteContainer.goThereBtn.onRelease = function()"

def sha(data):
    return hashlib.sha256(data).hexdigest()

def ffdec(cli, *args):
    result = subprocess.run(
        [str(cli), "-cli", "-onerror", "abort", *map(str, args)],
        capture_output=True, text=True, errors="replace", timeout=160
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"WADDLE_FAIR_MAP_COMPAT=FAIL ffdec_exit={result.returncode} "
            + (result.stdout + result.stderr)[-3000:]
        )
    return result.stdout + result.stderr

def main(cli):
    original = SOURCE.read_bytes()
    note = NOTE.read_bytes()
    party_map = PARTY_MAP.read_bytes()
    assert original[:3] in (b"FWS", b"CWS") and len(original) == 232822 and sha(original) == SOURCE_SHA
    assert note[:3] in (b"FWS", b"CWS") and party_map[:3] in (b"FWS", b"CWS")
    assert cli.is_file(), f"WADDLE_FAIR_MAP_COMPAT=FAIL ffdec_missing={cli}"
    with tempfile.TemporaryDirectory(prefix="waddle-fair-map-") as directory:
        temp = Path(directory)
        exported = temp / "original"
        ffdec(cli, "-export", "script", exported, SOURCE)
        action = exported / "scripts/frame_1/DoAction.as"
        body = action.read_text(encoding="utf-8-sig")
        if body.count("NOTE.goThereBtn.onPress = mapButtonDelegate;") != 1:
            raise RuntimeError("WADDLE_FAIR_MAP_COMPAT=FAIL source_button_contract_changed")
        if "SHELL.getLocalContentPath() + \"close_ups/party_map_note.swf\"" not in body:
            raise RuntimeError("WADDLE_FAIR_MAP_COMPAT=FAIL missing_native_party_note_loader")
        patched, count = PATTERN.subn(REPLACEMENT, body)
        if count != 1:
            raise RuntimeError(f"WADDLE_FAIR_MAP_COMPAT=FAIL ambiguous_button_hook count={count}")
        action.write_text(patched, encoding="utf-8")
        note_dir = temp / "note"
        ffdec(cli, "-export", "script", note_dir, NOTE)
        note_code = (note_dir / "scripts/frame_1/DoAction.as").read_text(encoding="utf-8-sig")
        if FAIR_NOTE_ACTION not in note_code or "CONSTANTS.PARTY_MAP_PATH" not in note_code:
            raise RuntimeError("WADDLE_FAIR_MAP_COMPAT=FAIL original_note_has_no_party_map_action")
        derived = temp / "FairIslandMap.swf"
        ffdec(cli, "-replace", SOURCE, derived, r"\frame_1\DoAction", action)
        blob = derived.read_bytes()
        if blob[:3] not in (b"FWS", b"CWS") or len(blob) < 100:
            raise RuntimeError("WADDLE_FAIR_MAP_COMPAT=FAIL invalid_compiled_map")
        check = temp / "verified"
        ffdec(cli, "-export", "script", check, derived)
        compiled = (check / "scripts/frame_1/DoAction.as").read_text(encoding="utf-8-sig")
        if compiled.count("NOTE.goThereBtn.onPress = null;") != 1:
            raise RuntimeError("WADDLE_FAIR_MAP_COMPAT=FAIL native_note_hook_not_preserved")
        if "NOTE.goThereBtn.onPress = mapButtonDelegate;" in compiled:
            raise RuntimeError("WADDLE_FAIR_MAP_COMPAT=FAIL old_onPress_handler_remains")
        for token in ("close_ups/party_map_note.swf", "SHELL.getPartyOptions()",
                      "clickMap(", "closeButton.onRelease"):
            if token not in compiled:
                raise RuntimeError(f"WADDLE_FAIR_MAP_COMPAT=FAIL unrelated_map_logic_removed={token}")
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        TARGET.write_bytes(blob)
        MANIFEST.write_text(json.dumps({
            "schema": "waddle-fair2015-derived-island-map/v1",
            "originalMap": "fair2015/period/ContentMap-03262015.swf",
            "originalSha256": sha(original),
            "originalFairNoteSha256": sha(note),
            "originalFairPartyMapSha256": sha(party_map),
            "derivedPath": "fair2015/compat/FairIslandMap.swf",
            "derivedSha256": sha(blob),
            "scope": "May 2015 only; original onRelease opens Fair party map"
        }, indent=2) + "\n", encoding="utf-8")
        print(f"WADDLE_FAIR_MAP_COMPAT=PASS source={sha(original)} derived={sha(blob)} bytes={len(blob)} isolated=true")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffdec", type=Path, required=True)
    main(parser.parse_args().ffdec)
