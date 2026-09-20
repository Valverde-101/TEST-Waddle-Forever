#!/usr/bin/env python3
"""Inventory and import original Holiday Party 2015 SWFs without cross-party fallback.

Scrape the party's archived HTML page (the direct wiki may be blocked), resolve
file pages or verified MediaWiki SHA paths, and pin every original to SHA-256.
An incomplete import fails before publishing: no Halloween/Fair assets are ever
silently substituted for Holiday-only SWFs.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urljoin, urlparse, urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'media/default/holiday2015'
SOURCE = 'https://toolbox.solero.me/cparchives/wiki/Holiday_Party_2015.html'
API = 'https://archives.clubpenguinwiki.info/w/api.php'
IMAGE_BASE = 'https://toolbox.solero.me/cparchives/static/images/archives/'
AGENT = {'User-Agent': 'Waddle-Forever-Holiday2015-Archive/1.0'}
HEADERS = (b'FWS', b'CWS', b'ZWS')
MAX_BYTES = 24 * 1024 * 1024
CATEGORIES = {
    'rooms': 'rooms', 'avatar': 'avatar', 'client': 'client',
    'close ups': 'close_ups', 'content': 'content', 'membership': 'membership',
    'other': 'other',
}
OTHER_DIRS = ('party2015', 'fair2015')
SWF_NAME = re.compile(r'^[A-Za-z0-9_().&+,% -]{1,160}\.swf$', re.I)


def read(url: str, maximum: int = MAX_BYTES) -> tuple[bytes, str]:
    with urlopen(Request(url, headers=AGENT), timeout=35) as response:
        data = response.read(maximum + 1)
        if len(data) > maximum:
            raise ValueError('asset_too_large')
        return data, response.geturl()


class ArchiveLinks(HTMLParser):
    """Read the MediaWiki section ID, never the adjacent [edit] link text."""
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.section = ''
        self.phase = 'party'
        self.heading = ''
        self.href = ''
        self.entries: list[dict[str, str]] = []

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag in ('h2', 'h3'):
            self.heading = tag
        if tag == 'span' and 'mw-headline' in str(d.get('class') or ''):
            name = re.sub(r'_\d+$', '', str(d.get('id') or '')).replace('_', ' ').lower()
            if self.heading == 'h2':
                self.section = CATEGORIES.get(name, '')
                self.phase = 'party'
            elif self.heading == 'h3' and name in ('pre-party', 'party'):
                self.phase = 'preparty' if name == 'pre-party' else 'party'
            elif self.heading == 'h3' and self.section == 'avatar' and name in ('sprites','effects'):
                self.section = 'avatar/' + name
        if tag == 'a':
            self.href = str(d.get('href') or '')

    def handle_endtag(self, tag):
        if tag in ('h2', 'h3'):
            self.heading = ''
        if tag == 'a' and self.href:
            href = urljoin(SOURCE, self.href)
            decoded = unquote(urlparse(href).path.rsplit('/', 1)[-1])
            name = re.sub(r'\.html$', '', decoded, flags=re.I)
            name = re.sub(r'^File:', '', name, flags=re.I)
            if SWF_NAME.fullmatch(name) and self.section:
                category = 'music' if re.fullmatch(r'Music\d+(?:_\d+)?\.swf', name, re.I) else self.section
                self.entries.append({
                    'name': name, 'section': category,
                    'phase': self.phase, 'filePage': href,
                })
            self.href = ''


def sha(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def allowed_file_url(url: str, name: str) -> bool:
    parsed = urlparse(url)
    actual = unquote(parsed.path.rsplit('/', 1)[-1]).replace('_', ' ').lower()
    return (parsed.scheme == 'https' and
            parsed.hostname in ('toolbox.solero.me', 'archives.clubpenguinwiki.info') and
            actual == name.replace('_', ' ').lower() and
            parsed.path.lower().endswith('.swf'))


def image_candidates(name: str, file_page: str):
    if allowed_file_url(file_page, name):
        yield file_page
    # Imageinfo avoids guessed hashes when files were renamed.
    query = urlencode({
        'action': 'query', 'format': 'json', 'prop': 'imageinfo',
        'iiprop': 'url|size', 'titles': 'File:' + name, 'redirects': '1',
    })
    try:
        raw, _ = read(API + '?' + query, 250000)
        for page in json.loads(raw).get('query', {}).get('pages', {}).values():
            for info in page.get('imageinfo', []):
                url = info.get('url')
                if url and allowed_file_url(url, name):
                    yield url
    except (OSError, ValueError, KeyError, TypeError):
        pass
    if file_page.startswith('https://toolbox.solero.me/cparchives/wiki/'):
        try:
            raw, _ = read(file_page, 1200000)
            html = raw.decode('utf-8', errors='replace')
            # Archive file pages include a direct original media URL.
            for href in re.findall(r"""(?:href|src)\s*=\s*["']([^"']+\.swf(?:\?[^"']*)?)""", html, re.I):
                url = urljoin(file_page, href.replace('&amp;', '&'))
                if allowed_file_url(url, name):
                    yield url
        except (OSError, ValueError):
            pass
    for spelling in dict.fromkeys((name, name.replace(' ', '_'), name.replace('_', ' '))):
        digest = hashlib.md5(spelling.encode('utf-8')).hexdigest()
        for target in dict.fromkeys((name, spelling)):
            yield f'{IMAGE_BASE}{digest[0]}/{digest[:2]}/{quote(target, safe="-_.()&+,")}'


def download(entry: dict[str, str]) -> tuple[dict[str, str], bytes]:
    name = entry['name']
    cached_manifest = DEST / 'manifest.json'
    if cached_manifest.is_file():
        for prior in json.loads(cached_manifest.read_text(encoding='utf-8')).get('assets', []):
            if prior.get('name') != name or prior.get('filePage') != entry['filePage']:
                continue
            cached = DEST / prior['relativePath']
            if cached.is_file():
                blob = cached.read_bytes()
                if blob[:3] in HEADERS and len(blob) == prior['bytes'] and sha(blob) == prior['sha256']:
                    return ({**entry, 'url': prior['url'], 'sha256': prior['sha256'],
                             'bytes': len(blob), 'relativePath': f"{entry['phase']}/{entry['section']}/{name}"}, blob)
    tried = 0
    for url in dict.fromkeys(image_candidates(name, entry['filePage'])):
        if not allowed_file_url(url, name):
            continue
        tried += 1
        try:
            blob, resolved = read(url)
            if not allowed_file_url(resolved, name) or blob[:3] not in HEADERS or len(blob) < 100:
                continue
            item = {**entry, 'url': resolved, 'sha256': sha(blob),
                    'bytes': len(blob), 'relativePath': f"{entry['phase']}/{entry['section']}/{name}"}
            return item, blob
        except (HTTPError, URLError, OSError, TimeoutError, ValueError):
            continue
    raise RuntimeError(f'WADDLE_HOLIDAY2015_IMPORT=FAIL asset={name} candidates={tried}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--inventory-only', action='store_true')
    options = parser.parse_args()
    page, effective = read(SOURCE, 3 * 1024 * 1024)
    if effective != SOURCE:
        raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL archive_redirected')
    document = ArchiveLinks()
    document.feed(page.decode('utf-8', errors='replace'))
    discovered = document.entries
    if not discovered:
        from collections import Counter
        class HrefAudit(HTMLParser):
            def __init__(self):
                super().__init__()
                self.hrefs = []
                self.headings = []
                self.current = ''
            def handle_starttag(self, tag, attrs):
                if tag == 'a':
                    self.hrefs.append(dict(attrs).get('href',''))
                if tag in ('h1','h2','h3'):
                    self.current = tag
            def handle_data(self, data):
                if self.current and data.strip():
                    self.headings.append((self.current,data.strip()[:50]))
            def handle_endtag(self, tag):
                if self.current == tag:self.current = ''
        audit = HrefAudit()
        audit.feed(page.decode('utf-8', errors='replace'))
        print('WADDLE_HOLIDAY2015_HTML_AUDIT=' +
              json.dumps({'bytes':len(page),'headings':audit.headings[:36],
                  'hrefs':audit.hrefs[:45], 'swf_anchors':sum('.swf' in x.lower() for x in audit.hrefs),
                  'sample':page[:700].decode('utf-8',errors='replace')},ensure_ascii=False),
              flush=True)
    unique: dict[str, dict[str, str]] = {}
    for entry in discovered:
        key = f"{entry['phase']}/{entry['section']}/{entry['name']}"
        existing = unique.get(key)
        if existing and existing['filePage'] != entry['filePage']:
            raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL ambiguous_file=' + key)
        unique[key] = entry
    categories = {section: sum(e['section'] == section for e in unique.values()) for section in CATEGORIES.values()}
    print('WADDLE_HOLIDAY2015_ARCHIVE_DISCOVERY=' +
          json.dumps({'total': len(unique), 'categories': categories,
                      'preparty': sum(e['phase'] == 'preparty' for e in unique.values()),
                      'examples': list(unique)[:15]}, ensure_ascii=False), flush=True)
    if len(unique) < 30 or categories['rooms'] < 20 or categories['client'] < 2 or categories['close_ups'] < 2:
        raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL incomplete_archive_discovery')
    if options.inventory_only:
        return

    originals = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(download, entry): key for key, entry in unique.items()}
        for future in as_completed(futures):
            item, blob = future.result()
            originals.append((item, blob))
    originals.sort(key=lambda v: v[0]['relativePath'])
    obsolete = []
    previous_manifest = DEST / 'manifest.json'
    if previous_manifest.is_file():
        previous = json.loads(previous_manifest.read_text(encoding='utf-8'))
        expected = {item['relativePath'] for item, _ in originals}
        for old in previous.get('assets', []):
            if old['relativePath'] not in expected:
                candidate = DEST / old['relativePath']
                if candidate.is_file():
                    if sha(candidate.read_bytes()) != old['sha256']:
                        raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL obsolete_source_modified')
                    obsolete.append((candidate, old['sha256']))
    matches: dict[str, list[str]] = {}
    for origin in OTHER_DIRS:
        base = ROOT / 'media/default' / origin
        if base.is_dir():
            for file in base.rglob('*.swf'):
                if 'compat' in file.relative_to(base).parts:
                    continue
                matches.setdefault(sha(file.read_bytes()), []).append(
                    f"{origin}:{file.relative_to(base).as_posix()}")
    seen = set()
    report = []
    for item, blob in originals:
        relative = item['relativePath']
        if relative in seen:
            raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL duplicate=' + relative)
        seen.add(relative)
        item['sameBytesAs'] = sorted(matches.get(item['sha256'], []))
        # Keep originals under a dedicated Holiday folder. Shared SHA refs may
        # be selected for runtime later; never resolve by matching filenames.
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and sha(target.read_bytes()) != item['sha256']:
            raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL pinned_source_changed=' + relative)
        target.write_bytes(blob)
        report.append(item)
        print('WADDLE_HOLIDAY2015_ASSET=PASS path=' + relative + ' sha256=' + item['sha256'], flush=True)
    manifest = {'schema': 'waddle-holiday-2015-original-assets/v1',
                'sourcePage': SOURCE, 'count': len(report), 'assets': report}
    out = DEST / 'manifest.json'
    if out.exists():
        previous = json.loads(out.read_text(encoding='utf-8'))
        prev_sources = {(i['name'], i['filePage'], i['sha256']) for i in previous['assets']}
        current_sources = {(i['name'], i['filePage'], i['sha256']) for i in report}
        if not prev_sources.issubset(current_sources):
            raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL source_changed_not_just_reorganized')
    for candidate, expected_sha in obsolete:
        if sha(candidate.read_bytes()) != expected_sha:
            raise RuntimeError('WADDLE_HOLIDAY2015_IMPORT=FAIL obsolete_source_modified')
        candidate.unlink()
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('WADDLE_HOLIDAY2015_IMPORT=PASS count=' + str(len(report)) +
          ' shared_sha=' + str(sum(bool(x['sameBytesAs']) for x in report)), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise
