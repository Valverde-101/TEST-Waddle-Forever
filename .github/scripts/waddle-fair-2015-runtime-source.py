#!/usr/bin/env python3
"""Acquire the original Fair 2015 party runtime and standalone intro.

Resolve real archive imageinfo URLs instead of guessing a MediaWiki MD5 storage
path. Fail closed on missing, mismatched, or non-SWF bytes. Never fall back to a
different party runtime or a second world.swf client.
"""
import hashlib
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit, unquote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "media/default/fair2015/client"
FILES = (
    ("ClientParty-Fair2015_2.swf", "party", 30000, 150000),
    ("ClientIntro_to_cp-06102015.swf", "intro", 100000, 1250000),
)
ARCHIVE_APIS = (
    "https://archives.clubpenguinwiki.info/w/api.php",
    "https://archives.clubpenguinwiki.info/api.php",
)
DIRECT_MIRRORS = (
    "https://toolbox.solero.me/cparchives/static/images/archives/",
    "https://archives.clubpenguinwiki.info/images/",
    "https://archives.clubpenguinwiki.info/w/images/",
)

def fetch(url, maximum):
    with urlopen(Request(url, headers={"User-Agent": "Waddle-Forever-Fair2015/1.0"}), timeout=35) as response:
        data = response.read(maximum + 1)
        return data, response.geturl()

def allowed_archive_url(url, name):
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in ("archives.clubpenguinwiki.info", "toolbox.solero.me"):
        return False
    if not parsed.path.lower().endswith(".swf"):
        return False
    # A wiki may normalize spaces/underscores, but may not silently substitute a different asset.
    expected = name.replace("_", " ").lower()
    actual = unquote(parsed.path.rsplit("/", 1)[-1]).replace("_", " ").lower()
    return actual == expected

def wiki_image_urls(title):
    urls = []
    spellings = tuple(dict.fromkeys((title, title.replace("_", " "), title.replace(" ", "_"))))
    for api in ARCHIVE_APIS:
        for spelling in spellings:
            query = urlencode({
                "action": "query", "format": "json", "prop": "imageinfo",
                "iiprop": "url|size", "titles": "File:" + spelling,
                "redirects": "1"
            })
            try:
                raw, _ = fetch(api + "?" + query, 250000)
                payload = json.loads(raw)
                for page in payload.get("query", {}).get("pages", {}).values():
                    for info in page.get("imageinfo", []):
                        url = info.get("url")
                        if url and allowed_archive_url(url, title):
                            urls.append(url)
                        elif url:
                            print("WADDLE_FAIR2015_SOURCE=SKIP unexpected_archive_filename " + url, flush=True)
            except (HTTPError, URLError, TimeoutError, OSError, ValueError, KeyError) as exc:
                print("WADDLE_FAIR2015_SOURCE=API_RETRY " + api + " " + type(exc).__name__, flush=True)
    return tuple(dict.fromkeys(urls))

def hashed_mirror_urls(title):
    spellings = tuple(dict.fromkeys((title, title.replace("_", " "), title.replace(" ", "_"))))
    for origin in DIRECT_MIRRORS:
        for hash_name in spellings:
            digest = hashlib.md5(hash_name.encode("utf-8")).hexdigest()
            for target_name in spellings:
                yield origin + digest[0] + "/" + digest[:2] + "/" + quote(target_name, safe="-_.")

def download_exact(title, minimum, maximum):
    candidates = tuple(dict.fromkeys((*wiki_image_urls(title), *hashed_mirror_urls(title))))
    attempts = []
    for url in candidates:
        if not allowed_archive_url(url, title):
            continue
        try:
            data, resolved = fetch(url, maximum)
            if not allowed_archive_url(resolved, title):
                attempts.append(url + ":unexpected_redirect")
                continue
            if not minimum <= len(data) <= maximum or data[:3] not in (b"FWS", b"CWS", b"ZWS"):
                attempts.append(url + ":invalid_swf bytes=" + str(len(data)))
                continue
            print("WADDLE_FAIR2015_SOURCE=PASS title=" + title + " bytes=" + str(len(data)) + " url=" + resolved, flush=True)
            return data, resolved
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            attempts.append(url + ":" + type(exc).__name__)
    raise RuntimeError("WADDLE_FAIR2015_SOURCE=FAIL title=" + title + " attempted=" + str(len(attempts)) + " errors=" + repr(attempts[:12]))

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
    if path.exists() and json.loads(path.read_text(encoding="utf-8")) != manifest:
        raise RuntimeError("WADDLE_FAIR2015_SOURCE=FAIL pinned_manifest_mismatch")
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("WADDLE_FAIR2015_CLIENT_IMPORT=PASS assets=2 sha256_pinned=true", flush=True)

if __name__ == "__main__":
    main()
