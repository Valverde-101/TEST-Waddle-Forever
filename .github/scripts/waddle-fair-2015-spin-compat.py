#!/usr/bin/env python3
"""Build a Fair-only loopback-compatible copy of the archived Daily Spin bootstrap.

The archive SWF remains byte-for-byte intact. FFDec edits only its first-frame
domain check; all other origins keep the original archived domain policy.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "media/default/fair2015/minigames/daily_spin/GamesSpinBootstrap.swf"
TARGET = ROOT / "media/default/fair2015/compat/GamesSpinBootstrapLocal.swf"
MANIFEST = ROOT / "media/default/fair2015/compat/spin_bootstrap_local.json"
SOURCE_SHA = "ada970a377e945e1e0dc69a30f14f563e49cd8fe08a20897a2464ea58a1b72dc"
ORIGINAL_CHECK = "com.clubpenguin.security.Security.doSecurityCheck(this._url,this._parent);"
LOCAL_CHECK = (
    'if (this._url.indexOf("http://127.0.0.1:") != 0 && '
    'this._url.indexOf("http://localhost:") != 0) { '
    + ORIGINAL_CHECK + " }"
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(ffdec: Path, *args: str) -> str:
    result = subprocess.run([str(ffdec), "-cli", "-onerror", "abort", *map(str, args)],
                            capture_output=True, text=True, errors="replace", timeout=100)
    if result.returncode != 0:
        raise RuntimeError(f"FFDec exit {result.returncode}: {(result.stdout + result.stderr)[-3500:]}")
    return result.stdout + result.stderr


def build(ffdec: Path) -> None:
    source = SOURCE.read_bytes()
    if len(source) != 6364 or digest(source) != SOURCE_SHA:
        raise RuntimeError("WADDLE_FAIR_SPIN_PATCH=FAIL source_sha_mismatch")
    if not ffdec.is_file():
        raise RuntimeError(f"WADDLE_FAIR_SPIN_PATCH=FAIL ffdec_missing={ffdec}")

    with tempfile.TemporaryDirectory(prefix="waddle-fair-spin-") as folder:
        work = Path(folder)
        names = run(ffdec, "-dumpAS2", "-exportNames", SOURCE)
        if r"\frame_1\DoAction" not in names:
            raise RuntimeError("WADDLE_FAIR_SPIN_PATCH=FAIL frame1_script_missing")
        exported = work / "export"
        run(ffdec, "-export", "script", exported, SOURCE)
        action = exported / "scripts/frame_1/DoAction.as"
        script = action.read_text(encoding="utf-8-sig")
        if script.count(ORIGINAL_CHECK) != 1:
            raise RuntimeError("WADDLE_FAIR_SPIN_PATCH=FAIL unexpected_security_contract")
        action.write_text(script.replace(ORIGINAL_CHECK, LOCAL_CHECK), encoding="utf-8")
        output = work / "spin-local.swf"
        run(ffdec, "-replace", SOURCE, output, r"\frame_1\DoAction", action)
        data = output.read_bytes()
        if data[:3] not in (b"FWS", b"CWS", b"ZWS") or len(data) < 100:
            raise RuntimeError("WADDLE_FAIR_SPIN_PATCH=FAIL output_invalid")
        checked = work / "checked"
        run(ffdec, "-export", "script", checked, output)
        result = (checked / "scripts/frame_1/DoAction.as").read_text(encoding="utf-8-sig")
        if result.count(LOCAL_CHECK) != 1 or result.count("movieLocations.push") != 3:
            raise RuntimeError("WADDLE_FAIR_SPIN_PATCH=FAIL replacement_not_verified")
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        TARGET.write_bytes(data)
        MANIFEST.write_text(json.dumps({
            "schema": "waddle-fair-2015-spin-compat/v1",
            "archivedSource": "minigames/daily_spin/GamesSpinBootstrap.swf",
            "sourceSha256": SOURCE_SHA,
            "derivedPath": "compat/GamesSpinBootstrapLocal.swf",
            "derivedSha256": digest(data),
            "scope": "Fair 2015 only; local 127.0.0.1 and localhost bypass archived remote-only domain gate",
        }, indent=2) + "\n", encoding="utf-8")
        print(f"WADDLE_FAIR_SPIN_PATCH=PASS source={SOURCE_SHA} derived={digest(data)} size={len(data)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffdec", type=Path, required=True)
    build(parser.parse_args().ffdec)
