#!/usr/bin/env python3
"""Acquire the missing May 2015 party runtime and standalone intro modules.

Unlike visual assets listed on The Fair 2015 article, these are preserved in the
archive's Client index. Their MediaWiki static paths are determined from MD5 of
the normalized archival filename, NOT from a later party or unverified alias.
Never modify the canonical game; the caller commits only to the Fair branch.
"""
import hashlib
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "media/default/fair2015/client"
MIRRORS = (
    "https://toolbox.solero.me/cparchives/static/images/archives/",
    "https://archives.clubpenguinwiki.info/images/",
    "https://archives.clubpenguinwiki.info/w/images/",
)
FILES = (
    ("ClientParty-Fair2015_2.swf", "party", 30000, 150000),
    ("ClientIntro_to_cp-06102015.swf", "intro", 100000, 1250000),
)

def download_exact(title, minimum, maximum):
    # The archive category displays spaces while MediaWiki's storage may have
    # imported filenames before normalization. Probe each documented spelling
    # and both hash spellings; no arbitrary remote URL or party substitution.
    names = tuple(dict.fromkeys((title, title.replace("_", " "), title.replace(" ", "_"))))
    attempts = []
    for origin in MIRRORS:
      for hash_name in names:
       digest = hashlib.md5(hash_name.encode("utf-8")).hexdigest()
       for target_name in names:
        location = digest[:1] + "/" + digest[:2] + "/" + quote(target_name, safe="-_.")
        url = origin + location
        try:
            with urlopen(Request(url, headers={"User-Agent": "Waddle-Forever-Fair2015/1.0"}), timeout=40) as response:
                data = response.read(maximum + 1)
                source = response.geturl()
            if (not minimum <= len(data) <= maximum or data[:3] not in (b"FWS", b"CWS", b"ZWS")):
                attempts.append(f"{url}:invalid_swf length={len(data)} magic={data[:3]!r}")
                continue
            print(f"WADDLE_FAIR2015_SOURCE=PASS title={title} bytes={len(data)} url={source}", flush=True)
            return data, source
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            attempts.append(f"{url}:{type(exc).__name__}:{exc}")
    raise RuntimeError(f"WADDLE_FAIR2015_SOURCE=FAIL title={title} attempts={attempts}")

def main():
    if not (ROOT / ".git").exists():
        raise RuntimeError("WADDLE_FAIR2015_SOURCE=FAIL no_git_checkout")
    DEST.mkdir(parents=True, exist_ok=True)
    assets = []
    for filename, role, minimum, maximum in FILES:
        blob, url = download_exact(filename, minimum, maximum)
        path = DEST / filename
        if path.exists() and path.read_bytes() != blob:
            raise RuntimeError("WADDLE_FAIR2015_SOURCE=FAIL existing_asset_mismatch=" + str(path))
        path.write_bytes(blob)
        assets.append({
            "role": role, "relativePath": "client/" + filename, "url": url,
            "sha256": hashlib.sha256(blob).hexdigest(), "bytes": len(blob)
        })
    manifest = {"schema": "waddle-fair-2015-client-runtime/v1", "assets": assets}
    path = ROOT / "media/default/fair2015/client-runtime-manifest.json"
    if path.exists():
        previous = json.loads(path.read_text(encoding="utf-8"))
        if previous != manifest:
            raise RuntimeError("WADDLE_FAIR2015_SOURCE=FAIL pinned_manifest_mismatch")
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("WADDLE_FAIR2015_CLIENT_IMPORT=PASS assets=2 sha256_pinned=true", flush=True)

if __name__ == "__main__":
    main()
