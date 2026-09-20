#!/usr/bin/env python3
"""Read-only ABC string-pool probe of ORIGINAL Holiday 2015 archive SWFs."""
import json
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'media/default/holiday2015'
FILES = (
 'party/client/ClientParty-HolidayParty2015.swf',
 'party/client/ClientInterface-HolidayParty2015.swf',
 'party/content/ContentParty_icon-HolidayParty2015.swf',
 'party/content/ContentFeatures-HolidayParty2015.swf',
 'party/rooms/RoomsTown-HolidayParty2015.swf',
 'party/rooms/RoomsDock-HolidayParty2015.swf',
 'party/close_ups/Close_upsCharacter_dialogue_december_login-HolidayParty2015.swf',
 'party/close_ups/Close_upsQuest_interface-HolidayParty2015.swf',
)
IMPORTANT = re.compile(r'party|holiday|walrus|advent|december|quest|coin|donat|calendar|dialog|close_ups|map|activefeature|2015|2016|room|features|login|cfc|w\.app|w\.p', re.I)

def u30(data, pos):
    value = 0
    for shift in (0, 7, 14, 21, 28):
        if pos >= len(data): raise ValueError('unexpected EOF in ABC u30')
        b = data[pos]; pos += 1
        value |= (b & 127) << shift
        if b < 128: return value, pos
    raise ValueError('oversize ABC u30')

def strings_in_abc(payload):
    pos = 4  # ABC minor/major version
    for width in (0, 0, 8):
        count, pos = u30(payload, pos)
        for _ in range(1, count):
            if width == 8: pos += 8
            else: _, pos = u30(payload, pos)
    count, pos = u30(payload, pos)
    if count > 300000: raise ValueError('unreasonable ABC pool')
    found = []
    for _ in range(1, count):
        n, pos = u30(payload, pos)
        if n > 1000000 or pos + n > len(payload): raise ValueError('bad ABC string length')
        s = payload[pos:pos+n].decode('utf-8', 'replace')
        pos += n
        if s: found.append(s)
    return found

def inspect(path):
    buf = path.read_bytes()
    if len(buf) < 12 or buf[:3] not in (b'FWS', b'CWS'):
        raise ValueError('unsupported SWF signature: ' + str(path))
    data = buf[8:] if buf[:3] == b'FWS' else zlib.decompress(buf[8:])
    if len(data) != struct.unpack_from('<I', buf, 4)[0] - 8:
        raise ValueError('SWF expanded length mismatch: ' + str(path))
    if path.name == 'ContentFeatures-HolidayParty2015.swf':
        needle = b'{"featureSettings":'
        begin = data.find(needle)
        if begin < 0: raise ValueError('Original Holiday features JSON missing')
        candidate = data[begin:begin + 50000].split(b'\0', 1)[0]
        try:
            party_features = json.loads(candidate.decode('utf-8'))
            print('HOLIDAY2015_ORIGINAL_FEATURES ' + json.dumps(party_features, ensure_ascii=True, separators=(',',':')))
        except (ValueError, UnicodeError) as exc:
            # The JSON may be embedded across AVM1 SWF action operands. A raw
            # null-delimited byte scan is not a JSON decoder; log evidence
            # without failing the independently SHA-verified archived files.
            print('HOLIDAY2015_ORIGINAL_FEATURES_FRAGMENT ' + json.dumps({'reason':str(exc), 'prefix':candidate[:700].decode('utf-8','replace')},ensure_ascii=True))
    if path.name == 'ClientParty-HolidayParty2015.swf':
        for m in re.finditer(rb'20[01][0-9]{5}', data):
            needle = m.group()
            if needle in (b'20151100', b'20151200', b'20151201', b'20151217'):
                print('HOLIDAY2015_FEATURE_IDENTIFIER ' + json.dumps({'id':needle.decode('ascii'),'before':data[max(0,m.start()-110):m.start()].decode('ascii','replace'),'after':data[m.end():m.end()+110].decode('ascii','replace')},ensure_ascii=True))
    if path.name == 'ContentFeatures-HolidayParty2015.swf':
        print('HOLIDAY2015_FEATURE_MONTHS ' + json.dumps(sorted(set(re.findall(rb'"month"\\s*:\\s*"[^"]+"', data)).__iter__().__str__()) if False else [s.decode('ascii','replace') for s in sorted(set(re.findall(rb'"month"\\s*:\\s*"[^"]+"', data)))]))
    rect = (5 + 4*(data[0] >> 3) + 7)//8
    pos = rect + 4  # frame rate and count
    strings = []
    abc = 0
    tags = {}
    while pos + 2 <= len(data):
        header = struct.unpack_from('<H', data, pos)[0]; pos += 2
        tag = header >> 6; length = header & 63
        tags[tag] = tags.get(tag, 0) + 1
        if length == 63:
            if pos + 4 > len(data): raise ValueError('truncated tag length')
            length = struct.unpack_from('<I', data, pos)[0]; pos += 4
        if pos + length > len(data): raise ValueError('truncated SWF tag')
        if tag == 82:
            block = data[pos:pos+length]
            sep = block.find(b'\0', 4)
            if sep >= 0:
                strings.extend(strings_in_abc(block[sep+1:]))
                abc += 1
        pos += length
        if tag == 0: break
    # Most 2015 room/content SWFs are AVM1 bytecode, not DoABC. Surface their
    # embedded printable identifiers, not just AS3 constant pools.
    raw_strings = [m.group().decode('ascii', 'replace') for m in re.finditer(rb'[ -~]{6,160}', data)]
    return abc, strings, tags, raw_strings, buf[:4].hex()

for rel in FILES:
    path = ROOT / rel
    if not path.is_file(): raise FileNotFoundError(rel)
    abc, strings, tags, raw_strings, swf_header = inspect(path)
    selected = sorted({s for s in strings + raw_strings if len(s) <= 180 and IMPORTANT.search(s)}, key=lambda x:(x.lower(),x))
    print('HOLIDAY2015_ABC file=' + rel + ' header=' + swf_header + ' blocks=' + str(abc) + ' strings=' + str(len(strings)) + ' raw_strings=' + str(len(raw_strings)) + ' tags=' + json.dumps(tags,sort_keys=True) + ' relevant=' + str(len(selected)))
    for s in selected[:120]:
        print('HOLIDAY2015_STRING ' + json.dumps({'file':rel,'s':s},ensure_ascii=True,separators=(',',':')))
    if len(selected)>120: print('HOLIDAY2015_STRING truncated=' + str(len(selected)-120) + ' file=' + rel)
print('HOLIDAY2015_ORIGINAL_PROBE=PASS original_archived_swf=true read_only=true')
