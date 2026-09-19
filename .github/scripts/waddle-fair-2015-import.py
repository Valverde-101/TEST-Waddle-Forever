#!/usr/bin/env python3
"""Import historical The Fair 2015 SWFs from Club Penguin Archives mirror.

This is intentionally a fail-closed source acquisition stage: it never borrows
2009/2014 Fair assets or fabricates missing SWFs, and never edits the live game.
"""
import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import Request, urlopen

PAGE = "https://toolbox.solero.me/cparchives/wiki/The_Fair_2015.html"
CATEGORIES = {
    "rooms": "rooms", "party rooms": "rooms", "regular": "rooms",
    "effects": "effects", "avatar sprites": "avatar",
    "avatar": "avatar", "client": "client", "close ups": "close_ups",
    "close-ups": "close_ups", "content": "content",
    "membership notice": "membership", "minigames": "minigames",
    "minigame": "minigames", "music": "music",
}
HEADERS = {"User-Agent": "Waddle-Forever-TheFair2015/1.0 (historical archival integration)"}

class IndexLinks(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.heading = None
        self.heading_parts = []
        self.section = "other"
        self.section_title = "Other"
        self.links = []
        self.anchor = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ("h2", "h3", "h4"):
            self.heading = tag
            self.heading_parts = []
        if tag == "a" and "href" in attrs:
            self.anchor = [attrs["href"], [], self.section, self.section_title]

    def handle_data(self, data):
        if self.heading:
            self.heading_parts.append(data)
        if self.anchor:
            self.anchor[1].append(data)

    def handle_endtag(self, tag):
        if tag == self.heading:
            label = re.sub(r"\s+", " ", "".join(self.heading_parts)).replace("[edit]", "").strip()
            key = label.lower()
            if key in CATEGORIES:
                self.section = CATEGORIES[key]
                self.section_title = label
            self.heading = None
            self.heading_parts = []
        if tag == "a" and self.anchor:
            href, parts, category, section = self.anchor
            label = re.sub(r"\s+", " ", "".join(parts)).strip()
            self.links.append({"href": href, "label": label, "category": category, "section": section})
            self.anchor = None

def read_url(url, retries=3):
    last = None
    for attempt in range(retries):
        try:
            req = Request(url, headers=HEADERS)
            with urlopen(req, timeout=65) as response:
                return response.read()
        except (HTTPError, URLError, TimeoutError) as exc:
            last = exc
            if attempt + 1 < retries:
                time.sleep(attempt + 1)
    raise RuntimeError(f"WADDLE_FAIR2015_FETCH=FAIL url={url} error={last}")

def normalized_name(link):
    href = unquote(link["href"])
    # Mirror uses either File%3AName.swf.html or wiki/File:Name.swf.
    direct = urlsplit(href).path
    if "/static/images/archives/" in direct.lower() and direct.lower().endswith(".swf"):
        name = Path(direct).name
    else:
        file_match = re.search(r"(?:File:|File%3A)([^/?#]+?\.swf)(?:\.html)?(?:[?#]|$)", href, re.I)
        if not file_match:
            return None
        name = unquote(file_match.group(1))
    if not name.lower().endswith(".swf") or "/" in name or "\\" in name or name in (".", ".."):
        return None
    return name

def media_url(file_page, filename):
    parser = IndexLinks()
    parser.feed(read_url(file_page).decode("utf-8", "replace"))
    matches = []
    for link in parser.links:
        href = urljoin(file_page, link["href"])
        path = unquote(urlsplit(href).path)
        if "/static/images/" not in path.lower() and "/images/archives/" not in path.lower():
            continue
        if not path.lower().endswith(".swf"):
            continue
        if Path(path).name.lower().replace("_", " ") == filename.lower().replace("_", " "):
            matches.append(href)
    unique = sorted(set(matches), key=lambda u: ("/static/images/archives/" not in u, len(u)))
    if not unique:
        raise RuntimeError(f"WADDLE_FAIR2015_MEDIA=FAIL source_page={file_page} file={filename}")
    return unique[0]

def category_for(link, filename):
    if filename.lower().startswith("music"):
        return "music"
    if link["category"] != "other":
        return link["category"]
    name = filename.lower()
    for prefix, category in (
        ("rooms", "rooms"), ("client", "client"), ("close_ups", "close_ups"),
        ("content", "content"), ("membership", "membership"),
        ("penguin", "avatar"), ("music", "music")):
        if name.startswith(prefix):
            return category
    return "other"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", required=True)
    ap.add_argument("--discover-only", action="store_true")
    ap.add_argument("--manifest-only", action="store_true")
    args = ap.parse_args()
    root = Path(args.repo_root).resolve()
    dest = root / "media" / "default" / "fair2015"
    if not (root / ".git").exists():
        raise RuntimeError("WADDLE_FAIR2015=FAIL expected_git_checkout")
    html = read_url(PAGE).decode("utf-8", "replace")
    parser = IndexLinks()
    parser.feed(html)
    entries = {}
    for link in parser.links:
        name = normalized_name(link)
        if not name:
            continue
        category = category_for(link, name)
        relative = category + "/" + name
        file_page = urljoin(PAGE, link["href"])
        entries.setdefault(relative.lower(), {
            "category": category, "name": name, "relativePath": relative,
            "filePage": file_page, "section": link["section"],
        })
    ordered = sorted(entries.values(), key=lambda e: e["relativePath"].lower())
    print("WADDLE_FAIR2015_DISCOVERY page={} links={} candidates={}".format(PAGE, len(parser.links), len(ordered)), flush=True)
    for entry in ordered:
        print("WADDLE_FAIR2015_CANDIDATE category={} filename={} source={}".format(
            entry["category"], entry["name"], entry["filePage"]), flush=True)
    if len(ordered) < 20:
        sample = [{"label": x["label"], "href": x["href"], "section": x["section"]}
                  for x in parser.links if ".swf" in (x["href"] + x["label"]).lower()][:30]
        print("WADDLE_FAIR2015_SOURCE_DEBUG " + json.dumps(sample, ensure_ascii=False), flush=True)
        raise RuntimeError("WADDLE_FAIR2015_DISCOVERY=FAIL too_few_candidates; never publish incomplete event")
    if args.discover_only:
        return

    dest.mkdir(parents=True, exist_ok=True)
    historical = []
    for entry in ordered:
        entry["url"] = (entry["filePage"] if "/static/images/archives/" in urlsplit(entry["filePage"]).path.lower() else media_url(entry["filePage"], entry["name"]))
        target = (dest / entry["relativePath"]).resolve()
        if dest not in target.parents:
            raise RuntimeError("WADDLE_FAIR2015=FAIL path_traversal")
        target.parent.mkdir(parents=True, exist_ok=True)
        if args.manifest_only and not target.exists():
            raise RuntimeError("WADDLE_FAIR2015=FAIL manifest_only_missing=" + str(target))
        if not target.exists():
            raw = read_url(entry["url"])
            if len(raw) < 100 or raw[:3] not in (b"FWS", b"CWS", b"ZWS"):
                raise RuntimeError("WADDLE_FAIR2015=FAIL invalid_swf=" + entry["url"])
            tmp = target.with_suffix(".swf.part")
            tmp.write_bytes(raw)
            tmp.replace(target)
        raw = target.read_bytes()
        if len(raw) < 100 or raw[:3] not in (b"FWS", b"CWS", b"ZWS"):
            raise RuntimeError("WADDLE_FAIR2015=FAIL local_invalid_swf=" + str(target))
        entry["bytes"] = len(raw)
        entry["sha256"] = hashlib.sha256(raw).hexdigest()
        entry["required"] = True
        historical.append(entry)
        print("WADDLE_FAIR2015_ASSET=PASS file={} bytes={} sha256={}".format(
            entry["relativePath"], entry["bytes"], entry["sha256"]), flush=True)
    manifest = {
        "schema": "waddle-fair-2015-assets/v1",
        "party": "The Fair 2015",
        "sourcePage": PAGE,
        "count": len(historical),
        "assets": historical,
    }
    (dest / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("WADDLE_FAIR2015_IMPORT=PASS files={} root={} manifest=sha256_pinned".format(len(historical), dest), flush=True)

if __name__ == "__main__":
    main()
