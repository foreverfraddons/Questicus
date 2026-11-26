# Questicus

Step-by-step questing guide for **WoW: Forever**: plans the fastest route through quests (Questie-style
map data, RestedXP-style steps, gear upgrades), with a quest tracker, dungeon mode, boss tracker - and
**Questicus Maps**, one seamless world map (built from [OpenMap](https://github.com/openmap-world/openmap), MIT).
Needs [ForeverDB](https://www.curseforge.com/wow/addons/forever-db). Author: Fatedfr.

## Layout
- `Questicus/` - the addon. `Questicus/WorldMap/` is **generated** - never edit it by hand.
- `tools/sync_maps.py` - turns an OpenMap release into Questicus Maps: renames OpenMap to Questicus Maps
  everywhere (globals `QuesticusMapAPI`, `QuesticusMap`, bindings `QUESTICUSMAP_*`, saved variables
  `QuesticusMapDB` / `QuesticusMapCharDB`, commands `/qc map` and `/qmap`, settings inside Questicus),
  keeps the credit, and **fails** (keeping the last good version) if OpenMap changed a part it edits or
  if any "OpenMap" is left outside the credits. Always starts from the pristine upstream files.
- `upstream.json` - the OpenMap release Questicus Maps is built from.
- `Locales/Questicus_<code>/` - the language packs (deDE, frFR, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN,
  zhTW). Each is its own small addon: `<code>.lua` holds `["English phrase"] = "translation"`. They are
  not in the Questicus zip; every release uploads them to the Questicus files page as additional files
  and attaches them to the GitHub release. To fix a translation, edit the line in `<code>.lua`.
  `python3 tools/locales.py check` lists phrases a pack is missing (they show in English until then),
  `python3 tools/locales.py stub <code>` prints them ready to translate, `keys` lists every phrase.
  In the addon code, text goes through `L["phrase"]` or `L("text with %s", value)` (`Questicus/Locale.lua`).

## Automation
- **Questicus Maps update** (`.github/workflows/maps.yml`, daily 09:37 UTC + by hand): when OpenMap has a new
  release (stable `vX.Y.Z` tags), rebuild `Questicus/WorldMap`, check it, commit, then start a release.
- **Release** (`.github/workflows/release.yml`, daily 10:07 UTC, by hand, or after a maps update): when the addon
  changed since the last tag, bump the version (`Questicus.toc` and `Core.lua`), tag, copy the map art from the
  pinned OpenMap release, check, package with the BigWigsMods packager and upload to CurseForge + GitHub releases.
- **Checks** (`.github/workflows/checks.yml`, every push / PR): Lua 5.1 syntax of every file, the Questicus Maps
  name check, and that `tools/sync_maps.py` reproduces `Questicus/WorldMap` exactly from the pinned release.

### Setup (once)
- Repository variable `CF_PROJECT_ID` = the Questicus CurseForge project id (without it, releases go to GitHub only).
- Repository secret `CF_API_KEY` = a CurseForge API token (https://authors.curseforge.com/account/api-tokens).
