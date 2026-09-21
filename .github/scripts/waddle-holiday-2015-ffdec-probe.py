#!/usr/bin/env python3
"""Read-only FFDec probe of archived Holiday 2015 AVM1 scripts.

Downloads a SHA256-pinned upstream FFDec release to a temporary directory.
Original SWFs are never modified, and no exported sources are committed.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / "media/default/holiday2015/party"
FFDEC_URL = "https://github.com/jindrapetrik/jpexs-decompiler/releases/download/version26.3.0/ffdec_26.3.0.zip"
FFDEC_SHA256 = "35f4930eb7c380afe66f2117f90b006deac0631473ad7500bb39c78f68645ecd"
ORIGINALS = [
    ARCHIVE / "client/ClientParty-HolidayParty2015.swf",
    ARCHIVE / "content/ContentParty_icon-HolidayParty2015.swf",
    ARCHIVE / "close_ups/Close_upsCharacter_dialogue_december_login-HolidayParty2015.swf",
]
CLASS_NAMES = re.compile(r"DecemberParty|BaseParty|Party_icon|PartyIcon|DecemberQuest|Character_Dialogue_Login|TemplatePartyCookieVO|Party_InterfaceOverrides|TemplatedPartyConstants|ServerCookieService", re.I)
TOKENS = re.compile(r"partyIconVisible|showPartyIcon|hidePartyIcon|QUEST_UI_PATH|PARTY_MAP_PATH|partymap|LOGIN_PROMPT_PATH|setConditionalPartyIconVisibility|checkDisplayLoginPrompt|configurePartyJSON|loadPartyFeatures|showPartyMap", re.I)

with tempfile.TemporaryDirectory(prefix="holiday2015-ffdec-") as tmp:
    temp = Path(tmp)
    zip_path = temp / "ffdec.zip"
    with urllib.request.urlopen(FFDEC_URL, timeout=90) as response:
        with zip_path.open("wb") as out:
            while chunk := response.read(1024 * 1024):
                out.write(chunk)
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    if digest != FFDEC_SHA256:
        raise ValueError("FFDec upstream ZIP checksum mismatch")
    print("HOLIDAY2015_FFDEC_ARCHIVE verified_sha256=" + digest, flush=True)
    with zipfile.ZipFile(zip_path) as archive:
        jar_names = [name for name in archive.namelist() if Path(name).name == "ffdec.jar"]
        if len(jar_names) != 1:
            raise ValueError("FFDec jar not found in signed release ZIP")
        # FFDec depends on sibling lib/*.jar files. Extract the complete pinned
        # distribution, not just ffdec.jar (otherwise NoClassDefFoundError).
        ffdec_dir = temp / "ffdec"
        archive.extractall(ffdec_dir)
        jar_path = ffdec_dir / jar_names[0]
    for original in ORIGINALS:
        destination = temp / original.stem
        cmd = ["java", "-Djava.awt.headless=true", "-Xmx1536m", "-jar", str(jar_path), "-export", "script", str(destination), str(original)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=200, check=False)
        print("HOLIDAY2015_FFDEC_EXPORT " + json.dumps({"asset":original.name,"returncode":result.returncode,"stdout_tail":result.stdout[-700:],"stderr_tail":result.stderr[-700:]},ensure_ascii=True),flush=True)
        if result.returncode:
            continue
        source_paths = sorted(destination.rglob("*.as"))
        print("HOLIDAY2015_FFDEC_SOURCE_COUNT " + json.dumps({"asset":original.name,"count":len(source_paths)}),flush=True)
        matched = 0
        for script in source_paths:
            source = script.read_text(encoding="utf-8",errors="replace")
            if not (CLASS_NAMES.search(script.name) or (original.name.startswith("ContentParty_icon") and TOKENS.search(source))):
                continue
            lines = source.splitlines()
            selected = [i for i,line in enumerate(lines) if TOKENS.search(line)]
            spans = []
            for ix in selected[:24]:
                spans.append([max(0,ix-7),min(len(lines),ix+14)])
            seen = set()
            excerpt = []
            for start,end in spans:
                for ix in range(start,end):
                    if ix not in seen:
                        excerpt.append(str(ix+1)+": "+lines[ix])
                        seen.add(ix)
            if not excerpt and CLASS_NAMES.search(script.name):
                excerpt = [str(i+1)+": "+line for i,line in enumerate(lines[:50])]
            # Exact conditional logic and protocol are needed to fix the icon
            # disappearing after the first dialogue, not only URL inventory.
            if script.name in ("DecemberParty.as", "TemplatePartyCookieVO.as", "Party_InterfaceOverrides.as", "TemplatedPartyConstants.as", "Character_Dialogue_Login.as"):
                print("HOLIDAY2015_AS2_FULL " + json.dumps({"asset":original.name,"class":str(script.relative_to(destination)),"source":source[:44000]},ensure_ascii=True),flush=True)
            if excerpt:
                print("HOLIDAY2015_AS2_SCRIPT " + json.dumps({"asset":original.name,"class":str(script.relative_to(destination)),"lines":len(lines),"excerpt":"\n".join(excerpt)[:14000]},ensure_ascii=True),flush=True)
                matched += 1
            if matched >= 8:
                break
        print("HOLIDAY2015_FFDEC_PROBE=PASS asset="+original.name+" matched_classes="+str(matched),flush=True)
