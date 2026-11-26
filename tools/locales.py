#!/usr/bin/env python3
"""Questicus translation keys.

  python3 tools/locales.py keys            list every English phrase the addon shows
  python3 tools/locales.py check [code]    which phrases each language pack is missing / has extra
  python3 tools/locales.py stub <code>     print a Lua table of the missing phrases for a pack
  python3 tools/locales.py news [code]     which patch-note lines (Questicus/Changelog.lua) each pack is missing
  python3 tools/locales.py release         fails when a line of the coming release ("next") isn't translated in every pack

Phrases are found in Questicus/*.lua:
  L["..."]  and  L("...", ...)
  the first text argument of the UI helpers (T.Button, T.Check, T.Card, T.Window, page, group, check,
  choice, sizeRow, header, label, add, stepper, wnote, note)
  tip = "..."  /  .tip = "..."
  plus tools/locale_extra.txt: phrases kept in data tables and shown through a translating label
Language packs live in Locales/Questicus_<code>/<code>.lua as  ["English"] = "translation", and the patch
notes (What's new) in Locales/Questicus_<code>/news.lua the same way, one entry per Changelog.lua line.
"""
import os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Questicus")
PACKS = os.path.join(ROOT, "Locales")
CODES = ["deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"]
SKIP_FILES = {"Author.lua", "Relay.lua", "AuthorNotes.lua", "Changelog.lua", "Secrets.lua"}  # author-only / data
HELPERS = ["T.Button", "T.Check", "T.Card", "T.Window", "page", "group", "check", "choice", "sizeRow",
           "header", "label", "add", "stepper", "wnote", "T.Segments", "row", "Q.CopyBox"]
# helpers that only take text in some files (Details' add() takes finished lines - not scanned there)
NOSCAN = {("Details.lua", "add"), ("Bosses.lua", "add"), ("Cleanup.lua", "row"), ("Tracker.lua", "row"), ("Zones.lua", "row")}

STR = r'"((?:[^"\\\n]|\\.)*)"'


def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")


def looks_like_text(s):
    if not re.search(r"[A-Za-z]{3}", s) and " " not in s: return False
    if len(s) < 2 or not re.search(r"[a-z]", s): return False
    if re.match(r"^(Questicus\w*|Interface\\|Fonts\\|[A-Z_]+|[a-z]+[A-Z]\w*|[a-z_]+)$", s): return False
    if s.startswith(("|T", "|c", "Interface", "%")) and " " not in s: return False
    return True


def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("--[[", i):
            j = src.find("]]", i); i = n if j < 0 else j + 2; continue
        if src.startswith("--", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src[i] in "\"'":
            q = src[i]; j = i + 1
            while j < n and src[j] != q:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1]); i = j + 1; continue
        out.append(src[i]); i += 1
    return "".join(out)


def call_args(src, start):
    """the top-level argument text of the call whose '(' is at start"""
    depth, i = 0, start
    while i < len(src):
        ch = src[i]
        if ch == '"':
            i += 1
            while i < len(src) and src[i] != '"': i += 2 if src[i] == "\\" else 1
        elif ch in "({[": depth += 1
        elif ch in ")}]":
            depth -= 1
            if depth == 0: return src[start + 1:i]
        i += 1
    return ""


def keys():
    found = {}
    for path in sorted(glob.glob(os.path.join(SRC, "*.lua"))):
        name = os.path.basename(path)
        if name in SKIP_FILES: continue
        src = strip_comments(open(path, encoding="utf-8").read())
        def put(s):
            s = unescape(s)
            if s and s.strip(): found.setdefault(s, name)
        for m in re.finditer(r'\bL\[' + STR + r'\]', src): put(m.group(1))
        for m in re.finditer(r'\bL\(' + STR, src): put(m.group(1))
        for m in re.finditer(r'\btip\s*=\s*' + STR, src):
            if looks_like_text(m.group(1)): put(m.group(1))
        for h in HELPERS:
            if (name, h) in NOSCAN: continue
            for m in re.finditer(r'(?<![\w.:])' + re.escape(h) + r'\s*\(', src):
                args = call_args(src, m.end() - 1)
                # every literal at the top level of the call (and inside {} option lists)
                for s in re.findall(STR, args):
                    if looks_like_text(s): put(s)
    extra = os.path.join(ROOT, "tools", "locale_extra.txt")
    if os.path.exists(extra):
        for line in open(extra, encoding="utf-8"):
            line = line.rstrip("\n")
            if line and not line.startswith("#"): found.setdefault(unescape(line), "locale_extra.txt")
    return found


def load_pack(code, part=None):
    d = os.path.join(PACKS, "Questicus_" + code)
    if not os.path.isdir(d): return None
    out = {}
    for f in ([part] if part else [code + ".lua", "news.lua"]):
        path = os.path.join(d, f)
        if not os.path.exists(path): continue
        src = open(path, encoding="utf-8").read()
        out.update({unescape(k): unescape(v) for k, v in re.findall(r'\[' + STR + r'\]\s*=\s*' + STR, src)})
    return out


def news(only_next=False):
    """the patch-note lines of Changelog.lua (only the coming release's with only_next)"""
    src = open(os.path.join(SRC, "Changelog.lua"), encoding="utf-8").read()
    out = []
    for e in re.split(r'\n  \{ v = ', src)[1:]:
        if only_next and not e.startswith('"next"'): continue
        out += [unescape(l) for l in re.findall(r'^\s+' + STR + r',?\s*$', e, re.M)]
    return out


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    k = keys()
    if cmd == "keys":
        for s, f in sorted(k.items(), key=lambda x: (x[1], x[0])): print(f"{f}\t{s}")
        print(len(k), "phrases", file=sys.stderr)
    elif cmd == "check":
        bad = 0
        for code in ([sys.argv[2]] if len(sys.argv) > 2 else CODES):
            p = load_pack(code, code + ".lua")
            if p is None: print(f"{code}: no pack"); bad += 1; continue
            miss = [s for s in k if s not in p]
            extra = [s for s in p if s not in k]
            fmt = [s for s in k if s in p and re.findall(r"%[\d.]*[sd]", s).__len__() != re.findall(r"%[\d.]*[sd]", p[s]).__len__()]
            print(f"{code}: {len(p)} phrases, {len(miss)} missing, {len(extra)} unused, {len(fmt)} with a different %s/%d count")
            for s in fmt: print("   format:", s)
            bad += len(miss) + len(fmt)
        sys.exit(1 if bad else 0)
    elif cmd in ("news", "release"):
        lines = news(cmd == "release"); bad = 0
        for code in ([sys.argv[2]] if len(sys.argv) > 2 else CODES):
            p = load_pack(code, "news.lua") or {}
            miss = [l for l in lines if l not in p]
            print(f"{code}: {len(lines) - len(miss)}/{len(lines)} patch-note lines translated")
            for l in miss[:5]: print("   missing:", l[:90])
            bad += len(miss)
        if cmd == "release" and bad:
            print("Translate the coming release's patch notes in every Locales/Questicus_<code>/news.lua first.")
        sys.exit(1 if bad else 0)
    elif cmd == "stub":
        p = load_pack(sys.argv[2]) or {}
        for s in k:
            if s not in p: print(f"  [{lua(s)}] = {lua(s)},")


if __name__ == "__main__":
    main()
