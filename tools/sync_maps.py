#!/usr/bin/env python3
"""Questicus Maps: build Questicus/WorldMap from an OpenMap release.

Questicus Maps is OpenMap (MIT, Ji and the OpenMap contributors) built into Questicus, under
Questicus' own name. This script turns a pristine OpenMap checkout into that, the same way every
time, so a new OpenMap release never brings the "OpenMap" name, its slash commands or its
settings page back:

  python3 tools/sync_maps.py code <openmap-checkout>   # WorldMap/, Bindings.xml block, toc block
  python3 tools/sync_maps.py art  <openmap-checkout>   # Media/Textures (the map art; at release time)
  python3 tools/sync_maps.py check                     # fails if anything slipped through

It always starts from the upstream files (never from its own earlier output), and stops with an
error - leaving the last good WorldMap/ in place - when OpenMap changed a part it has to edit.
"""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Questicus")
OUT = os.path.join(ADDON, "WorldMap")

GUARD_LINE = ("if Questicus and Questicus.mapStandalone then return end   "
              "-- (the standalone OpenMap addon is on: it runs the map)\n")
TOC_START = "# >>> Questicus Maps files (tools/sync_maps.py - do not edit by hand) >>>"
TOC_END = "# <<< Questicus Maps files <<<"
BIND_START = "<!-- >>> Questicus Maps bindings (tools/sync_maps.py) >>> -->"
BIND_END = "<!-- <<< Questicus Maps bindings <<< -->"
# the only places "OpenMap" may appear: the credit, the licence, and the code that steps aside for
# (or stays compatible with) the standalone OpenMap addon
ALLOW = (
    re.compile(r"^Credits\.lua$"),
    re.compile(r"^Guard\.lua$"),
    re.compile(r"^LICENSE"),
    re.compile(r"^Libs/"),
)
ALLOW_LINES = (GUARD_LINE.strip(), "_G.OpenMapAPI = _G.OpenMapAPI or API")


class SyncError(Exception):
    pass


# ------------------------------------------------------------------ the rename (Lua-aware)
WORD = re.compile(r"OpenMap(s?)(\w*)")


def sub_text(s):
    """Inside strings and comments: OpenMapX -> QuesticusMapX, the name itself -> Questicus Maps."""
    def f(m):
        plural, rest = m.group(1), m.group(2)
        return ("QuesticusMap" + plural + rest) if rest else "Questicus Maps"
    s = WORD.sub(f, s)
    s = s.replace("Questicus Maps's", "Questicus Maps'")
    return s.replace("OPENMAP", "QUESTICUSMAP")


def sub_code(s):
    """In code: identifiers only, never a space."""
    return re.sub(r"OpenMap(\w*)", r"QuesticusMap\1", s).replace("OPENMAP", "QUESTICUSMAP")


def rebrand_lua(src):
    out, i, n, start = [], 0, len(src), 0

    def flush(j):
        out.append(sub_code(src[start:j]))

    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            flush(i)
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
            out.append(sub_text(src[i:end])); i = start = end
            continue
        if c == "[":
            m = re.match(r"\[(=*)\[", src[i:])
            if m:
                flush(i)
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
                out.append(sub_text(src[i:end])); i = start = end
                continue
        if c in "\"'":
            flush(i)
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                elif src[j] == "\n":
                    break
                j += 1
            out.append(sub_text(src[i:j + 1])); i = start = j + 1
            continue
        i += 1
    flush(n)
    return "".join(out)


# ------------------------------------------------------------------ Questicus' own edits
def must(s, old, new, what, count=1):
    if s.count(old) != count:
        raise SyncError("OpenMap changed %s (expected %d x %r) - update tools/sync_maps.py" % (what, count, old[:70]))
    return s.replace(old, new)


INIT_BLOCK = re.compile(r"\t\t-- a page in Blizzard's settings that opens the options window\n.*?\t\tSlashCmdList\.QUESTICUSMAP = Slash\n", re.S)
INIT_NEW = """\t\t-- the map's settings live in Questicus: Questicus' options window and settings page have the
\t\t-- "Map settings" button, and the commands are /qc map ... (and /qmap)
\t\tSLASH_QUESTICUSMAP1 = "/qmap"
\t\tSlashCmdList.QUESTICUSMAP = Slash
\t\tns.Slash = Slash
\t\tlocal Q = _G.Questicus
\t\tif Q and Q.Command then
\t\t\tQ:Command("map", "Questicus Maps: /qc map (settings), status, notes, pins, draw, news, dungeons, bench, reset", function(rest) Slash(rest) end)
\t\tend
"""
CREDIT = """\t{ "Built on OpenMap", {
\t\t{ "OpenMap", "Questicus Maps is OpenMap (MIT licence) built into Questicus. Thank you to Ji and everyone below for OpenMap - github.com/openmap-world/openmap" },
\t} },
"""
GUARD_FILE = """-- Questicus Maps: the world map, built from OpenMap (MIT, by Ji and the OpenMap contributors - see
-- WorldMap\\LICENSE.txt and the map's Credits page). No separate addon needed. If the standalone OpenMap
-- addon is still installed and on, it loaded first (OptionalDeps) and runs the map; Questicus' copy
-- then stays out of the way.
local Q = Questicus
if _G.OpenMapAPI or _G.OpenMap then          -- (the standalone OpenMap addon loaded first)
  Q.mapStandalone = true
  Q.After(8, function()
    Q:Print("Questicus Maps (the world map) is built into Questicus now - disable or delete the OpenMap addon to use it")
  end)
end
"""
ICON = "Interface\\\\AddOns\\\\Questicus\\\\Media\\\\icon"


def edit_file(rel, s):
    """Questicus' edits after the rename, per file."""
    s = s.replace("Interface\\\\AddOns\\\\OpenMap\\\\", "Interface\\\\AddOns\\\\Questicus\\\\")
    s = s.replace('"|cff" .. ns.ACCENT .. "Open|rMap"', '"|cff" .. ns.ACCENT .. "Questicus|r Maps"')
    s = s.replace("/openmap", "/qc map").replace("/omap", "/qc map")
    s = re.sub(r"Interface\\\\AddOns\\\\Questicus\\\\Media\\\\Textures\\\\QuesticusMapIcon(Round)?", lambda m: ICON, s)
    if rel == "Init.lua":
        s, n = INIT_BLOCK.subn(INIT_NEW.replace("\\", "\\\\"), s)
        if n != 1:
            raise SyncError("OpenMap changed Init.lua's settings page / slash command block - update tools/sync_maps.py")
    if rel == "API.lua":
        s = must(s, "QuesticusMapAPI = API\n",
                 "QuesticusMapAPI = API\n_G.OpenMapAPI = _G.OpenMapAPI or API      -- (addons written for OpenMap keep working)\n",
                 "API.lua's global")
    if rel == "Map/WorldMap.lua":
        s = s.replace('if caller and caller ~= "Questicus Maps" and', "if caller and caller ~= ns.name and")
    return s


def edit_credits(s):
    s = s.replace("/openmap", "/qc map")
    s = must(s, "ns.Credits = {\n", "ns.Credits = {\n" + CREDIT, "Credits.lua")
    s = s.replace('L["Made by"]', '"OpenMap made by"')
    return s


# ------------------------------------------------------------------ build
def toc_files(upstream):
    lines = []
    with open(os.path.join(upstream, "OpenMap.toc"), encoding="utf-8-sig") as f:
        for line in f:
            l = line.strip()
            if not l or l.startswith("#"):
                continue
            m = re.match(r"^(\S+)(\s+\[.*\])?$", l)
            lines.append("WorldMap\\" + m.group(1) + (m.group(2) or ""))
    return lines


def replace_block(path, start, end, body):
    s = open(path, encoding="utf-8").read()
    block = start + "\n" + body + ("\n" if body and not body.endswith("\n") else "") + end
    if start in s and end in s:
        s = s[:s.index(start)] + block + s[s.index(end) + len(end):]
    else:
        raise SyncError("markers missing in " + path)
    open(path, "w", encoding="utf-8", newline="\n").write(s)


PATCHES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "map_patches")


def apply_patches(tmp):
    """Questicus' own changes to the map code (tools/map_patches/*.patch, paths a/Questicus/WorldMap/...),
    applied again after every sync so an OpenMap update doesn't undo them. A patch that no longer fits
    is skipped with a warning (the sync still goes through) - fix or drop it by hand."""
    import subprocess
    if not os.path.isdir(PATCHES):
        return
    for name in sorted(os.listdir(PATCHES)):
        if not name.endswith(".patch"):
            continue
        path = os.path.join(PATCHES, name)
        args = ["patch", "-d", tmp, "-p3", "--forward", "--batch", "--no-backup-if-mismatch", "-r", "-", "-i", path]
        dry = subprocess.run(args + ["--dry-run"], capture_output=True, text=True)
        if dry.returncode != 0:
            print("WARNING: map patch", name, "no longer fits - skipped:\n" + dry.stdout + dry.stderr, file=sys.stderr)
            continue
        subprocess.run(args, check=True, capture_output=True, text=True)
        print("map patch applied:", name)


def code(upstream_root):
    up = os.path.join(upstream_root, "OpenMap")
    if not os.path.exists(os.path.join(up, "OpenMap.toc")):
        raise SyncError("no OpenMap/OpenMap.toc in " + upstream_root)
    tmp = OUT + ".new"
    shutil.rmtree(tmp, ignore_errors=True)
    for dp, dirs, files in os.walk(up):
        rel_dir = os.path.relpath(dp, up).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
        if rel_dir.startswith(("Media", "Data/Retail")):
            continue
        for f in files:
            rel = (rel_dir + "/" + f).lstrip("/")
            if rel.endswith(".toc") or rel == "Bindings.xml":
                continue
            src = os.path.join(dp, f)
            dst = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if rel.endswith(".lua") and not rel.startswith("Libs/"):
                s = open(src, encoding="utf-8-sig").read()
                s = s.replace("Interface\\\\AddOns\\\\OpenMap\\\\", "Interface\\\\AddOns\\\\Questicus\\\\")
                if rel == "Credits.lua":
                    s = edit_credits(s)
                else:
                    s = edit_file(rel, rebrand_lua(s))
                open(dst, "w", encoding="utf-8", newline="\n").write(GUARD_LINE + s)
            elif rel.endswith(".xml") and not rel.startswith("Libs/"):
                s = sub_text(open(src, encoding="utf-8-sig").read())
                open(dst, "w", encoding="utf-8", newline="\n").write(s)
            else:
                shutil.copyfile(src, dst)
    open(os.path.join(tmp, "Guard.lua"), "w", encoding="utf-8", newline="\n").write(GUARD_FILE)
    apply_patches(tmp)
    problems = check(tmp)
    if problems:
        raise SyncError("the new Questicus Maps still says OpenMap:\n  " + "\n  ".join(problems[:20]))
    # all good: swap it in, then the toc and the bindings
    shutil.rmtree(OUT, ignore_errors=True)
    os.rename(tmp, OUT)
    replace_block(os.path.join(ADDON, "Questicus.toc"), TOC_START, TOC_END,
                  "WorldMap\\Guard.lua\n" + "\n".join(toc_files(up)))
    b = open(os.path.join(up, "Bindings.xml"), encoding="utf-8-sig").read()
    binds = "\n".join("\t" + l.strip() for l in sub_text(b).splitlines() if l.strip().startswith("<Binding "))
    replace_block(os.path.join(ADDON, "Bindings.xml"), "\t" + BIND_START, "\t" + BIND_END, binds)
    print("Questicus Maps rebuilt from", upstream_root)


def art(upstream_root):
    src = os.path.join(upstream_root, "OpenMap", "Media", "Textures")
    dst = os.path.join(ADDON, "Media", "Textures")
    if not os.path.isdir(os.path.join(src, "Forever")):
        raise SyncError("no OpenMap/Media/Textures/Forever in " + upstream_root)
    shutil.rmtree(os.path.join(dst, "Forever"), ignore_errors=True)
    os.makedirs(dst, exist_ok=True)
    shutil.copytree(os.path.join(src, "Forever"), os.path.join(dst, "Forever"))
    for f in ("GroupRing.tga",):
        if os.path.exists(os.path.join(src, f)):
            shutil.copyfile(os.path.join(src, f), os.path.join(dst, f))
    n = sum(len(fs) for _, _, fs in os.walk(os.path.join(dst, "Forever")))
    print("map art copied:", n, "files")


def check(base=OUT):
    problems = []
    for dp, _, files in os.walk(base):
        for f in files:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, base).replace("\\", "/")
            if not rel.endswith((".lua", ".xml")) or any(a.search(rel) for a in ALLOW):
                continue
            for k, line in enumerate(open(p, encoding="utf-8"), 1):
                if ("OpenMap" in line or "/openmap" in line.lower() or "/omap" in line) and line.strip() not in ALLOW_LINES \
                        and not line.startswith(GUARD_LINE.strip()) and "_G.OpenMapAPI = _G.OpenMapAPI or API" not in line:
                    problems.append("%s:%d: %s" % (rel, k, line.strip()[:100]))
    for root_file in ("Questicus.toc", "Bindings.xml"):
        for k, line in enumerate(open(os.path.join(ADDON, root_file), encoding="utf-8"), 1):
            if re.search(r"OPENMAP|OpenMap_Binding|/openmap", line):
                problems.append("%s:%d: %s" % (root_file, k, line.strip()[:100]))
    return problems


if __name__ == "__main__":
    try:
        what = sys.argv[1]
        if what == "code":
            code(sys.argv[2])
        elif what == "art":
            art(sys.argv[2])
        elif what == "check":
            p = check()
            if p:
                print("\n".join(p)); sys.exit(1)
            print("Questicus Maps: no OpenMap name left outside the credits")
        else:
            raise SyncError("usage: sync_maps.py code|art <openmap checkout> | check")
    except SyncError as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(2)
