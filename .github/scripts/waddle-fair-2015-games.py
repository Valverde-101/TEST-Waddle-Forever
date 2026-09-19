#!/usr/bin/env python3
"""Inventory SWFs linked by nine games referenced in The Fair 2015 archive."""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
from urllib.parse import urljoin, urlsplit

source = runpy.run_path(str(Path(__file__).with_name("waddle-fair-2015-import.py")))
IndexLinks = source["IndexLinks"]
read_url = source["read_url"]
normalized_name = source["normalized_name"]
BASE = "https://toolbox.solero.me/cparchives/wiki/"
GAMES = {
    "Balloon Pop": "Balloon_Pop.html",
    "Daily Spin": "Daily_Spin.html",
    "Feed-A-Puffle": "Feed-A-Puffle.html",
    "Lunar Launch": "Lunar_Launch.html",
    "Memory Card Game": "Memory_Card_Game.html",
    "Puffle Paddle": "Puffle_Paddle.html",
    "Puffle Shuffle": "Puffle_Shuffle.html",
    "Puffle Soaker": "Puffle_Soaker.html",
    "Super Hero Bounce": "Super_Hero_Bounce.html",
}
ap = argparse.ArgumentParser()
ap.add_argument("--repo-root", default=".")
ap.add_argument("--import-assets", action="store_true")
args = ap.parse_args()
root = Path(args.repo_root).resolve()
assets_root = root / "media" / "default" / "fair2015" / "minigames"
manifest = []
for name, relative in GAMES.items():
    url = urljoin(BASE, relative)
    parser = IndexLinks()
    parser.feed(read_url(url).decode("utf-8", "replace"))
    assets = {}
    for link in parser.links:
        resolved = urljoin(url, link["href"])
        if "/static/images/archives/" not in urlsplit(resolved).path.lower():
            continue
        swf = normalized_name(link)
        if swf:
            assets.setdefault(swf.lower(), (swf, resolved))
    print(f"WADDLE_FAIR2015_GAME source={name!r} count={len(assets)} url={url}", flush=True)
    slug = relative.removesuffix(".html").lower().replace("-", "_")
    if not assets:
        raise RuntimeError(f"WADDLE_FAIR2015_GAME=FAIL game={name!r} source_no_assets={url}")
    for swf, resolved in assets.values():
        print(f"WADDLE_FAIR2015_GAME_ASSET game={name!r} name={swf} url={resolved}", flush=True)
        if args.import_assets:
            target = (assets_root / slug / swf).resolve()
            if assets_root not in target.parents:
                raise RuntimeError("WADDLE_FAIR2015_GAME=FAIL path_traversal")
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                raw = read_url(resolved)
                if raw[:3] not in (b"FWS", b"CWS", b"ZWS") or len(raw) < 100:
                    raise RuntimeError(f"WADDLE_FAIR2015_GAME=FAIL invalid_swf={resolved}")
                tmp = target.with_suffix(".swf.part")
                tmp.write_bytes(raw)
                tmp.replace(target)
            data = target.read_bytes()
            if data[:3] not in (b"FWS", b"CWS", b"ZWS") or len(data) < 100:
                raise RuntimeError(f"WADDLE_FAIR2015_GAME=FAIL local_invalid_swf={target}")
            entry = {
                "game": name, "filePage": url, "name": swf,
                "relativePath": "minigames/" + slug + "/" + swf,
                "url": resolved, "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
            manifest.append(entry)
            print(f"WADDLE_FAIR2015_GAME_VERIFIED name={swf} bytes={len(data)} sha256={entry['sha256']}", flush=True)
if args.import_assets:
    if len(manifest) < 50:
        raise RuntimeError(f"WADDLE_FAIR2015_GAME=FAIL incomplete_count={len(manifest)}")
    manifest_path = assets_root / "manifest.json"
    manifest_path.write_text(json.dumps({
        "schema": "waddle-fair-2015-minigames/v1",
        "description": "All SWFs directly linked by nine minigame pages cited by The Fair 2015 archive; availability alone does not prove 2015 compatibility.",
        "count": len(manifest), "assets": manifest,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"WADDLE_FAIR2015_GAMES_IMPORT=PASS files={len(manifest)} manifest={manifest_path}", flush=True)
