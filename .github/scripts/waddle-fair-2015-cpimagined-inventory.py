#!/usr/bin/env python3
"""Read-only inventory of the public CPImagined The Fair 2015 mediaserver ZIP.

This archive is a *candidate source*, not evidence that its files are compatible
with Waddle's May 2015 client. No files are mounted or committed by this scan.
"""
import hashlib
import io
import json
import re
from pathlib import Path
from urllib.request import Request, urlopen
from zipfile import ZipFile, BadZipFile

SOURCE_REPO = "CPImagined/CPImagined-Archive"
SOURCE_COMMIT = "main"
SOURCE_PATH = "hadnlers/The Fair 2015 Mediaserver.zip"
SOURCE_URL = ("https://raw.githubusercontent.com/" + SOURCE_REPO + "/" +
              SOURCE_COMMIT + "/hadnlers/The%20Fair%202015%20Mediaserver.zip")
MAX_ARCHIVE = 45 * 1024 * 1024
MAX_ENTRY = 20 * 1024 * 1024
MAX_UNCOMPRESSED = 450 * 1024 * 1024
INTERESTING = re.compile(
    r"party(?:_icon)?\\.swf|intro[_ ]to[_ ]cp|questcommunicator|"
    r"game_strings|party_map|dialog|(?:cp_party_games)|"
    r"(?:spin|paddle|shuffle|bounce|bell|soaker|balloon|tickets|fair)",
    re.I,
)
SWF = {".swf"}
TEXT = {".xml", ".json", ".txt", ".csv", ".bin"}

def main():
    request = Request(SOURCE_URL, headers={"User-Agent": "Waddle-Forever-Archive-Audit/1.0"})
    with urlopen(request, timeout=90) as response:
        raw = response.read(MAX_ARCHIVE + 1)
    if len(raw) > MAX_ARCHIVE:
        raise ValueError("WADDLE_FAIR_CPIMAGINED=FAIL oversized_archive")
    print("WADDLE_FAIR_CPIMAGINED_ARCHIVE bytes=" + str(len(raw)) +
          " sha256=" + hashlib.sha256(raw).hexdigest() + " source=" + SOURCE_URL, flush=True)
    try:
        with ZipFile(io.BytesIO(raw)) as archive:
            files = [f for f in archive.infolist() if not f.is_dir()]
            total = sum(f.file_size for f in files)
            if total > MAX_UNCOMPRESSED or len(files) > 20000:
                raise ValueError("WADDLE_FAIR_CPIMAGINED=FAIL expansion_limit")
            collected = []
            for info in files:
                name = info.filename.replace("\\", "/")
                parts = Path(name).parts
                if (info.file_size > MAX_ENTRY or
                    name.startswith("/") or
                    any(part in (".", "..") for part in parts)):
                    raise ValueError("WADDLE_FAIR_CPIMAGINED=FAIL unsafe_member=" + name)
                suffix = Path(name).suffix.lower()
                if suffix not in SWF | TEXT:
                    continue
                record = {"path": name, "size": info.file_size, "archiveCrc32": f"{info.CRC:08x}"}
                if INTERESTING.search(name):
                    blob = archive.read(info)
                    record["sha256"] = hashlib.sha256(blob).hexdigest()
                    record["swfMagic"] = blob[:3].decode("ascii", "replace") if suffix == ".swf" else None
                    print("WADDLE_FAIR_CPIMAGINED_ASSET " + json.dumps(record, ensure_ascii=False), flush=True)
                collected.append(record)
            summary = {
                "schema": "waddle-fair-cpimagined-inventory/v1",
                "sourceRepo": SOURCE_REPO,
                "sourcePath": SOURCE_PATH,
                "sourceUrl": SOURCE_URL,
                "archiveSha256": hashlib.sha256(raw).hexdigest(),
                "archiveBytes": len(raw),
                "totalEntries": len(files),
                "totalBytes": total,
                "files": collected
            }
            target = Path(".work/fair2015/cpimagined-inventory.json")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print("WADDLE_FAIR_CPIMAGINED_INVENTORY=PASS files=" + str(len(files)) +
                  " relevant=" + str(sum("sha256" in x for x in collected)) +
                  " totalBytes=" + str(total) + " output=" + str(target), flush=True)
    except BadZipFile as error:
        raise ValueError("WADDLE_FAIR_CPIMAGINED=FAIL not_zip") from error

if __name__ == "__main__":
    main()
