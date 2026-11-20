#!/usr/bin/env python3
"""Copy the author's in-game notes / route rules (QuesticusAuthor in
WTF/Account/<acct>/SavedVariables/Questicus.lua) into AuthorNotes.lua, which ships with the addon.
Usage: merge_author_notes.py <SavedVariables/Questicus.lua> <AuthorNotes.lua>"""
import re, sys

def block(text, name):
    m = re.search(r'^%s\s*=\s*\{.*?^\}\s*$' % name, text, re.S | re.M)
    return m.group(0) if m else None

def pairs(sub):
    out = {}
    for k, v in re.findall(r'\["([^"]+)"\]\s*=\s*("(?:[^"\\]|\\.)*"|false)', sub or ""):
        out[k] = None if v == "false" else v
    return out

def section(text, name):
    m = re.search(r'\["%s"\]\s*=\s*\{(.*?)\n\t?\}' % name, text, re.S)
    return m.group(1) if m else ""

sv, ship = open(sys.argv[1], encoding="utf-8").read(), open(sys.argv[2], encoding="utf-8").read()
b = block(sv, "QuesticusAuthor")
if not b:
    sys.exit("no QuesticusAuthor block - nothing to merge")
cur = {n: pairs(section(ship, n) if False else re.search(r'%s = \{(.*?)\n  \},' % n, ship, re.S).group(1)) for n in ("notes", "hints")}
new = {n: pairs(section(b, n)) for n in ("notes", "hints")}
for n in ("notes", "hints"):
    for k, v in new[n].items():
        if v is None: cur[n].pop(k, None)
        else: cur[n][k] = v
def body(d): return "".join('    ["%s"] = %s,\n' % (k, d[k]) for k in sorted(d))
head = ship.split("Questicus.AuthorData = {")[0]
open(sys.argv[2], "w", encoding="utf-8").write(head + "Questicus.AuthorData = {\n  v = 1,\n  notes = {\n" + body(cur["notes"]) +
    "  },\n  hints = {\n" + body(cur["hints"]) + "  },\n}\n")
print("notes %d, hints %d" % (len(cur["notes"]), len(cur["hints"])))
