#!/usr/bin/env python3
"""Import only independently audited missing Fair assets, never global files.

CPImagined's Fair 2015 ZIP duplicates many original assets already pinned in
fair2015/manifest.json. Reuse them by existing fairRef, and import only a
separate, SHA-pinned party controller plus two event-specific missing files.
"""
import hashlib
import io
import json
from pathlib import Path
from urllib.request import urlopen, Request
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FAIR = ROOT / "media/default/fair2015"
PREFIX = "The Fair 2015 Mediaserver/play/v2/content/global/"
SOURCE_URL = "https://raw.githubusercontent.com/CPImagined/CPImagined-Archive/main/hadnlers/The%20Fair%202015%20Mediaserver.zip"
SOURCE_SHA256 = "0b29689a639b26f9c7fbfb23f0cd8c0f3f18136ebb79fbf4abab62994168b58d"
# Never replace the existing 194 archive assets: their identical SHA is
# already documented in the independent Club Penguin Archives manifest.
MISSING = {
    "content/party.swf": ("content/party.swf", 61387,
                          "3b104a8dfc44980e98d68e9a4e2b05988ddf0dca44e3ec719ec8d939855b99a0"),
    "content/map.swf": ("content/map.swf", 231306,
                        "2e8c90fcd3243542b75441d64c9688b8e66975e7c7a62dd5dd70fbc7d4b5fd78"),
    "content/room_pin/7236.swf": ("content/room_pin/7236.swf", 1653,
                                  "293bed9433d7bbcb9858f8ac140157633b10169a7e0f42ed0537857cc928b216"),
}
SHARED_EXPECTED = {
    "content/interface.swf": "d843ee914e6afb66a1061d3fc2757021c497234e78a8432de5707e24433fd2b8",
    "content/party_icon.swf": "33b6907e4d1938e465a98a47edeb0f32da66692312507b39b5ece8c874b8b4dd",
    "close_ups/quest_interface.swf": "6c8c8708ffe6174772efe4cb04ad7df3fdde8d771cb6f459169e043f84b9d44d",
}
# The close-ups path is under content/global in the archive, like the game map.
def main():
    with urlopen(Request(SOURCE_URL, headers={"User-Agent":"Waddle-Forever-Fair2015/1.0"}),timeout=90) as response:
        raw = response.read(45 * 1024 * 1024 + 1)
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError("WADDLE_FAIR_CPIMAGINED_IMPORT=FAIL source_archive_changed")
    archive = ZipFile(io.BytesIO(raw))
    paths = {}
    for original, (target_name, byte_count, digest) in MISSING.items():
        source_path = PREFIX + original
        blob = archive.read(source_path)
        if len(blob) != byte_count or hashlib.sha256(blob).hexdigest() != digest or blob[:3] not in (b"FWS",b"CWS",b"ZWS"):
            raise ValueError("WADDLE_FAIR_CPIMAGINED_IMPORT=FAIL bad_asset=" + source_path)
        output = FAIR / "cpimagined" / target_name
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists() and output.read_bytes() != blob:
            raise ValueError("WADDLE_FAIR_CPIMAGINED_IMPORT=FAIL would_overwrite=" + str(output))
        output.write_bytes(blob)
        paths[target_name] = {"relativePath":"cpimagined/" + target_name,"sourcePath":source_path,
                              "sha256":digest,"bytes":byte_count}
        print("WADDLE_FAIR_CPIMAGINED_IMPORTED=PASS name="+target_name+" sha256="+digest,flush=True)
    for common, expected in SHARED_EXPECTED.items():
        actual=hashlib.sha256(archive.read(PREFIX+common)).hexdigest()
        if actual!=expected: raise ValueError("WADDLE_FAIR_CPIMAGINED_IMPORT=FAIL shared_asset_diverged="+common)
        print("WADDLE_FAIR_CPIMAGINED_REUSED=PASS name="+common+" sha256="+actual,flush=True)
    manifest={"schema":"waddle-fair-2015-cpimagined/v1","archive":SOURCE_URL,
              "archiveSha256":SOURCE_SHA256,"assets":list(paths.values()),
              "sharedExistingAssets":SHARED_EXPECTED}
    dest=FAIR/"cpimagined/manifest.json"
    if dest.exists() and json.loads(dest.read_text(encoding="utf-8"))!=manifest:
        raise ValueError("WADDLE_FAIR_CPIMAGINED_IMPORT=FAIL manifest_mismatch")
    dest.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("WADDLE_FAIR_CPIMAGINED_IMPORT=PASS new=3 reused=3 isolated=true",flush=True)
if __name__=="__main__":
    main()
