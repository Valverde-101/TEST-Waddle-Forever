#!/usr/bin/env python3
"""Inventory SWFs linked by nine games referenced in The Fair 2015 archive."""
from collections import defaultdict
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
    for swf, resolved in assets.values():
        print(f"WADDLE_FAIR2015_GAME_ASSET game={name!r} name={swf} url={resolved}", flush=True)
