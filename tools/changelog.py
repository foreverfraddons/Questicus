#!/usr/bin/env python3
"""Patch notes (Questicus/Changelog.lua) for the release workflow.

  changelog.py stamp <version> [--maps]   the "next" entry becomes <version>; a fresh empty "next" goes on top.
                                          An empty "next" gets a short line (--maps: the world map was updated;
                                          --silent: no line, nothing in the in-game What's new).
  changelog.py md <version>               CHANGELOG.md text for CurseForge: that version's notes.
  changelog.py count [--maps]             how many changes the "next" entry holds (--maps: +1, the map was updated).
  changelog.py check                      the file parses and has a "next" entry.

One line per change. Several tries at the same fix are one change: the line is reworded, not added to.
"""
import re
import sys

PATH = "Questicus/Changelog.lua"
SECTIONS = [("added", "New"), ("changed", "Changed"), ("fixed", "Fixed")]
ENTRY = re.compile(r'^  \{ v = "([^"]+)"', re.M)
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')


def blocks(s):
    """[(version, start, end)] for each entry, in file order."""
    starts = [(m.group(1), m.start()) for m in ENTRY.finditer(s)]
    tail = s.rindex("\n}")
    out = []
    for i, (v, a) in enumerate(starts):
        b = starts[i + 1][1] if i + 1 < len(starts) else tail + 1
        out.append((v, a, b))
    return out


def sections(block):
    res = {}
    for key, _ in SECTIONS:
        m = re.search(r"\b" + key + r" = \{(.*?)\n    \}", block, re.S)
        if m:
            res[key] = [x.replace('\\"', '"').replace("\\'", "'") for x in STR.findall(m.group(1))]
    return res


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    s = open(PATH, encoding="utf-8").read()
    bl = blocks(s)
    nxt = [b for b in bl if b[0] == "next"]
    if cmd == "check":
        if not nxt:
            sys.exit("Changelog.lua: no \"next\" entry")
        for v, a, b in bl:
            if v != "next" and not re.match(r"^\d+\.\d+\.\d+$", v):
                sys.exit("Changelog.lua: odd version " + v)
        print("changelog ok: %d versions" % len(bl))
        return
    if cmd == "count":
        n = sum(len(v) for v in sections(s[nxt[0][1]:nxt[0][2]]).values()) if nxt else 0
        print(n + (1 if "--maps" in sys.argv else 0))
        return
    ver = sys.argv[2]
    if cmd == "stamp":
        if any(v == ver for v, _, _ in bl):
            print("already stamped", ver)
            return
        if nxt:
            _, a, b = nxt[0]
            block = s[a:b]
        else:
            a = b = bl[0][1] if bl else s.rindex("\n}") + 1
            block = ""
        if any(sections(block).values()):
            new = block.replace('{ v = "next"', '{ v = "%s"' % ver, 1)
        elif "--silent" in sys.argv:
            new = '  { v = "%s" },\n' % ver          # nothing in the in-game What's new
        else:
            line = ("The world map (Questicus Maps) was updated with the latest map data."
                    if "--maps" in sys.argv else "Small fixes and improvements.")
            new = '  { v = "%s",\n    changed = {\n      "%s",\n    },\n  },\n' % (ver, line)
        s = s[:a] + '  { v = "next" },\n' + new + s[b:]
        open(PATH, "w", encoding="utf-8").write(s)
        print("stamped", ver)
        return
    if cmd == "md":
        for v, a, b in bl:
            if v == ver:
                sec = sections(s[a:b])
                out = ["# Questicus %s" % ver, ""]
                for key, title in SECTIONS:
                    if sec.get(key):
                        out.append("### " + title)
                        out += ["- " + x for x in sec[key]]
                        out.append("")
                print("\n".join(out))
                return
        print("# Questicus %s\n\nSmall fixes and improvements." % ver)
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
