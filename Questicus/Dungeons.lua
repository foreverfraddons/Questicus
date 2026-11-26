-- Questicus dungeons: every dungeon in the game with its levels, bosses, quests, XP and clear time,
-- and "Get all quests": dungeon mode routes you to every quest of that dungeon (with the chains
-- that unlock them), then into the dungeon. Clear times are learned from your own runs.
local Q = Questicus
local L = Q.L
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local DG = {}
Q.Dungeons = DG

local list, detail
local GOLD, DIM = T.HEX.gold, T.HEX.dim
local function c(hex, s) return Q.Color(hex, s) end
local function mins(sec) sec = math.floor((sec or 0) / 60 + 0.5); return sec >= 60 and ("%dh %dm"):format(math.floor(sec / 60), sec % 60) or (sec .. " min") end

-- ------------------------------------------------------------------ data
-- mobs inside each dungeon: levels, spawn count, bosses (from the spawn data of its instance map)
local info
local function mobsOf()
  if info then return info end
  DG.Extras()
  info = {}
  local DB = D.db
  local function add(area, key, count)
    local nid = tonumber(key:sub(2))
    local n = nid and D:NPC(nid)
    if not n then return end
    local e = info[area]
    if not e then e = { lo = 999, hi = 0, spawns = 0, elites = 0, bosses = {}, xpw = {} }; info[area] = e end
    local lo, hi, rank = n[3] or n[4] or 1, n[4] or n[3] or 1, n[5] or 0
    if D:Faction(nid) then return end                    -- friendly npcs inside (quest givers, prisoners)
    if hi <= 1 then return end                             -- critters, triggers
    e.spawns = e.spawns + count
    if rank == 1 or rank == 2 then e.elites = e.elites + count end
    -- bosses: boss rank, or a named elite with a single spawn
    if rank == 3 or ((rank == 1 or rank == 2) and count == 1) then e.bosses[#e.bosses + 1] = { n[1], hi, nid } end
    e.xpw[#e.xpw + 1] = { hi, count, rank, lo, nid }
  end
  for key, groups in pairs(DB.spw or {}) do
    if key:sub(1, 1) == "c" then
      for _, g in ipairs(groups) do
        local area = D.INSTANCE_AREA[g[1]]
        if area then add(area, key, math.max(1, math.floor((#g - 1) / 2))) end
      end
    end
  end
  -- level range from the bulk of the mobs (a stray low-level add doesn't count)
  local function range(e)
    local top = 0
    for _, w in ipairs(e.xpw) do top = math.max(top, w[1]) end
    local lo, hi = 999, 0
    for _, w in ipairs(e.xpw) do
      if w[1] >= top - 15 then lo, hi = math.min(lo, w[4] or w[1]), math.max(hi, w[1]) end
    end
    e.lo, e.hi = lo, hi
    table.sort(e.bosses, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    e.bossList = {}
    for i, b in ipairs(e.bosses) do e.bossList[i] = { name = b[1], lvl = b[2], nid = b[3] }; e.bosses[i] = b[1] end
  end
  for _, e in pairs(info) do e.fromSpawns = true; range(e) end
  -- dungeons without spawn data: the npcs known to be inside (levels and bosses, no counts)
  for key, areas in pairs(DB.ind or {}) do
    if key:sub(1, 1) == "c" then
      for _, area in ipairs(areas) do
        if not D.RAID_AREA[area] and not (info[area] and info[area].fromSpawns) then add(area, key, 1); info[area].ind = true end
      end
    end
  end
  for _, e in pairs(info) do if e.ind then range(e) end end
  return info
end

-- every dungeon worth listing: the classic ones and any with quests for you; no raids
local PVP = { [3277] = true, [3358] = true, [2597] = true, [16606] = true }
-- WoW Forever's own dungeons (Blizzard's list: levels and where they are); the later ones show up
-- as soon as ForeverDB has them
DG.FOREVER = {
  ["The Hall of Thanes"] = { 13, 18, "Beneath Ironforge, Dun Morogh" },
  ["Ruins of Lordaeron"] = { 15, 20, "Ruins above the Undercity, Tirisfal Glades" },
  ["Excavation Site: Wetlands"] = { 24, 29, "Above Whelgar's Excavation, Wetlands" },
  ["City of Dalaran"] = { 28, 33, "Alterac Mountains" },
  ["The Drowned City"] = { 35, 42, "The Vile Reef, Stranglethorn Vale" }, ["Krol'dok Stronghold"] = { 40, 47, "The Riverglades" },
  ["Alcaz Prison"] = { 48, 55, "Alcaz Island, Dustwallow Marsh" }, ["Blackmaw Hold"] = { 55, 60, "Azshara" },
  ["Shaper's Terrace"] = { 58, 60, "Un'Goro Crater" },
}
-- ------------------------------------------------------------------ Questicus Maps' place data
-- The map (WorldMap\Data\Forever\Places.lua) knows every dungeon in the game's tables: entrance,
-- Group Finder levels and the bosses in the game's order - WoW Forever's own dungeons included.
-- Used for the boss lists (only real bosses, no quest NPCs) and for dungeons ForeverDB doesn't have yet.
local function norm(n)
  n = (n or ""):lower():gsub("^the ", ""):gsub("[^%w]", "")
  return n
end
DG.ALIAS = { stormwindstockade = "stockade", templeofatalhakkar = "sunkentemple", deadmines = "deadmines",
  lowerblackrockspire = "blackrockspire", upperblackrockspire = "blackrockspire" }
local function key(n) n = norm(n); return DG.ALIAS[n] or n end
DG.Key = key
local places
-- [instance mapID] = { id, name, lo, hi, raid, bosses = {...}, map, mx, my | i, x, y }, plus .byKey[key] = entry
function DG.Places()
  if places then return places end
  local MP = _G.QuesticusMap and _G.QuesticusMap.MapPlaces
  places = { byKey = {} }
  if not MP then return places end
  for _, inst in ipairs(MP.instances or {}) do
    for _, d in ipairs(inst[4] or {}) do
      local id, name = d[1], d[2]
      local e = places[id]
      if not e then
        e = { id = id, name = name, lo = d[4], hi = d[5], raid = d[3], bosses = (MP.bosses or {})[id] or {} }
        if inst[1] then e.i, e.x, e.y = inst[1], inst[2], inst[3] else e.map, e.mx, e.my = inst.map, inst[2], inst[3] end
        places[id] = e
      else
        e.lo, e.hi = math.min(e.lo or 99, d[4] or 99), math.max(e.hi or 0, d[5] or 0)   -- wings: the whole range
      end
      places.byKey[key(name)] = places.byKey[key(name)] or e
      local base = name:match("^(.-) %- ")                    -- "Scarlet Monastery - Library" -> the dungeon
      if base then places.byKey[key(base)] = places.byKey[key(base)] or e end
    end
  end
  return places
end
-- the place entry for a dungeon (by its instance map, else its name)
local areaInstance
function DG.PlaceOf(area, name)
  local pl = DG.Places()
  if not areaInstance then
    areaInstance = {}
    for inst, a in pairs(D.INSTANCE_AREA) do areaInstance[a] = inst end
  end
  local inst = areaInstance[area] or (type(area) == "number" and area < 0 and -area) or nil
  return (inst and pl[inst]) or pl.byKey[key(name)]
end
-- the real bosses of a dungeon, in the game's order (nil when the map has no list for it)
function DG.BossNames(e)
  local p = e and DG.PlaceOf(e.area, e.name)
  if p and p.bosses and #p.bosses > 0 then return p.bosses end
end
-- dungeons the map knows that ForeverDB doesn't (yet): added as area -mapID, with their entrance, and
-- their bosses' quests (a quest that has one of its bosses as an objective is that dungeon's)
local extrasDone
DG.bossArea = {}
function DG.Extras()
  if extrasDone then return end
  local pl = DG.Places()
  if not D:Ready() then return end
  extrasDone = true
  local have = {}
  for _, a in pairs(D.INSTANCE_AREA) do local d = D:Dungeon(a); if d then have[key(d[1])] = a end end
  for a, d in pairs(D.db.dng or {}) do if not D.RAID_AREA[a] then have[key(d[1])] = have[key(d[1])] or a end end
  for id, p in pairs(pl) do
    if type(id) == "number" and not p.raid then
      local k = key(p.name)
      -- WoW Forever dungeons ForeverDB has by area: their instance map too (spawns inside, the boss tracker)
      if have[k] and not D.INSTANCE_AREA[id] and DG.FOREVER[(D:Dungeon(have[k]) or {})[1] or ""] then D.INSTANCE_AREA[id] = have[k] end
      if not have[k] and not D.INSTANCE_AREA[id] then
        local area = -id
        local spots = {}
        if p.map then spots = { p.map, math.floor(p.mx * 1000 + 0.5), math.floor(p.my * 1000 + 0.5) }
        elseif p.i then
          local m, mx, my = D:MapPos({ i = p.i, x = p.x, y = p.y })
          if m then spots = { m, math.floor(mx * 1000 + 0.5), math.floor(my * 1000 + 0.5) } end
        end
        D.EXTRA_DNG[area] = { p.name, nil, spots }
        D.INSTANCE_AREA[id] = area
        have[k] = true
        for _, bn in ipairs(p.bosses or {}) do
          for _, nid in ipairs(D:NPCByName(bn) or {}) do DG.bossArea[nid] = area end
        end
      end
    end
  end
end

local isInstance = {}
local listCache, listKey
function DG:List()
  DG.Extras()
  for _, a in pairs(D.INSTANCE_AREA) do isInstance[a] = true end
  local idx = P.DungeonIndex()
  local key = tostring(QS.pool) .. ":" .. (QS.logCount or 0) .. ":" .. (Q.player.level or 0)
  if listCache and listKey == key then return listCache end
  local seen, out, byName, pendingQ = {}, {}, {}, {}
  local function add(area)
    if seen[area] or D.RAID_AREA[area] or PVP[area] then return end
    local d = D:Dungeon(area)
    if not d then return end
    seen[area] = true
    local m = mobsOf()[area]
    -- the same dungeon under two area ids (zone + instance): one line with both lists of quests
    local same = byName[d[1]]
    if same then
      for _, id in ipairs(idx[area] or {}) do same.quests[#same.quests + 1] = id end
      if not (same.mobs and same.mobs.fromSpawns) and m and m.fromSpawns then same.mobs, same.lo, same.hi = m, m.lo, m.hi end
      if isInstance[area] then same.area = area end
      return
    end
    -- a real dungeon: a classic instance, a WoW Forever dungeon, or one with elite mobs inside
    local fv = DG.FOREVER[d[1]]
    if not isInstance[area] and not fv and not (m and m.spawns > 0 and m.elites > 0) then
      pendingQ[d[1]] = pendingQ[d[1]] or {}
      for _, id in ipairs(idx[area] or {}) do table.insert(pendingQ[d[1]], id) end
      return
    end
    local qs = {}
    for _, id in ipairs(idx[area] or {}) do qs[#qs + 1] = id end
    for _, id in ipairs(pendingQ[d[1]] or {}) do qs[#qs + 1] = id end
    pendingQ[d[1]] = nil
    local qlo, qhi = 999, 0
    for _, id in ipairs(qs) do
      local i = QS:Info(id)
      if i then qlo, qhi = math.min(qlo, i.min or i.level), math.max(qhi, i.level) end
    end
    local lo = (fv and fv[1]) or ((m and m.lo < 999) and m.lo) or (qlo < 999 and qlo) or nil
    local hi = (fv and fv[2]) or ((m and m.hi > 0) and m.hi) or (qhi > 0 and qhi) or nil
    local pl = DG.PlaceOf(area, d[1])
    if pl and not (m and m.fromSpawns) then lo, hi = pl.lo or lo, pl.hi or hi end
    if pl and fv then lo, hi = pl.lo or lo, pl.hi or hi end      -- the game's Group Finder levels
    local e = { area = area, name = d[1], lo = lo, hi = hi, quests = qs, mobs = m, forever = fv ~= nil or area < 0,
      where = fv and fv[3], instance = pl and pl.id }
    byName[d[1]] = e
    out[#out + 1] = e
  end
  for _, area in pairs(D.INSTANCE_AREA) do add(area) end
  for area in pairs(idx) do add(area) end
  for area, d in pairs(D.db.dng or {}) do if DG.FOREVER[d[1]] then add(area) end end
  for area in pairs(D.EXTRA_DNG) do add(area) end
  table.sort(out, function(a, b) return (a.lo or 99) < (b.lo or 99) or ((a.lo or 99) == (b.lo or 99) and a.name < b.name) end)
  listCache, listKey = out, key
  return out
end

-- your own clear times (learned) or an estimate from the number of mobs and bosses
function DG:ClearTime(e)
  local av = Q.Runs and Q.Runs:Averages(e.area)
  if av and av.time then return av.time, av.timed end
  local runs = QuesticusCollect and QuesticusCollect.dclear and QuesticusCollect.dclear[e.area]
  if runs and #runs > 0 then
    local s = 0
    for _, r in ipairs(runs) do s = s + r end
    return s / #runs, #runs
  end
  local m = e.mobs
  if not m then return nil end
  return (m.spawns or 0) * 7 + #(m.bosses or {}) * 45 + 120, 0
end

-- XP for one run at your level: mob kills (elites give double, split in a group of 5)
function DG:MobXP(e, lv)
  local m = e.mobs
  if not (m and m.fromSpawns) then return nil end
  local xp = 0
  for _, w in ipairs(m.xpw) do
    local k = QS.KillXP(w[1], lv)
    if w[3] == 1 or w[3] == 2 or w[3] == 3 then k = k * 2 end
    xp = xp + k * w[2]
  end
  return xp / 5
end

function DG:QuestStatus(id, lv)
  if QS.done[id] then return "done", 0 end
  if QS.log[id] then return QS.log[id].complete and L["ready to hand in"] or L["in your log"], 1 end
  local i = QS:Info(id)
  if i and lv < (i.min or 1) then return L("needs level %d", i.min), 3 end
  if QS:Available(id) then return L["can get now"], 2 end
  return L["needs an earlier quest"], 2
end

-- ------------------------------------------------------------------ pictures
-- the Dungeon Journal's button / background art when the client has it, else the dungeon finder's
-- icon, else a castle
DG.LFG = {
  ["Ragefire Chasm"] = "RagefireChasm", ["The Deadmines"] = "Deadmines", ["Deadmines"] = "Deadmines",
  ["Wailing Caverns"] = "WailingCaverns", ["Shadowfang Keep"] = "ShadowFangKeep", ["Blackfathom Deeps"] = "BlackfathomDeeps",
  ["The Stockade"] = "StormwindStockades", ["Stormwind Stockade"] = "StormwindStockades", ["Gnomeregan"] = "Gnomeregan",
  ["Razorfen Kraul"] = "RazorfenKraul", ["Scarlet Monastery"] = "ScarletMonastery", ["Razorfen Downs"] = "RazorfenDowns",
  ["Uldaman"] = "Uldaman", ["Zul'Farrak"] = "ZulFarak", ["Maraudon"] = "Maraudon", ["Sunken Temple"] = "SunkenTemple",
  ["The Temple of Atal'Hakkar"] = "SunkenTemple", ["Blackrock Depths"] = "BlackrockDepths",
  ["Blackrock Spire"] = "BlackrockSpire", ["Lower Blackrock Spire"] = "BlackrockSpire", ["Upper Blackrock Spire"] = "BlackrockSpire",
  ["Dire Maul"] = "DireMaul", ["Scholomance"] = "Scholomance", ["Stratholme"] = "Stratholme",
}
DG.CASTLE = "Interface\\Icons\\INV_Misc_Key_14"
local journal
local function journalArt()
  if journal then return journal end
  journal = {}
  if not (EJ_GetInstanceByIndex and EJ_GetNumTiers and EJ_SelectTier) then return journal end
  pcall(function()
    for tier = 1, EJ_GetNumTiers() do
      EJ_SelectTier(tier)
      for _, raid in ipairs({ false, true }) do
        local i = 1
        while true do
          local id, name, _, bg, button, _, _, _, _, _, small = EJ_GetInstanceByIndex(i, raid)
          if not id then break end
          if name and not journal[name] then journal[name] = { button = button, bg = bg, small = small } end
          i = i + 1
        end
      end
    end
  end)
  return journal
end
-- the Group Finder's own picture names (GetLFGDungeonInfo's textureFilename): the client's real files,
-- WoW Forever's dungeons included when the client has them
local lfgTex
local function lfgArt()
  if lfgTex then return lfgTex end
  lfgTex = {}
  if not GetLFGDungeonInfo then return lfgTex end
  for id = 1, 3200 do
    local ok, name, _, _, _, _, _, _, _, _, _, tex = pcall(GetLFGDungeonInfo, id)
    if ok and type(name) == "string" and type(tex) == "string" and tex ~= "" then
      local k = DG.Key(name)
      if not lfgTex[k] then lfgTex[k] = tex end
      local base = name:match("^(.-) %- ") or name:match("^(.-) %(")
      if base and not lfgTex[DG.Key(base)] then lfgTex[DG.Key(base)] = tex end
    end
  end
  return lfgTex
end
-- WoW Forever's dungeons the game has no picture for: their map, drawn for Questicus Maps (12 tiles, 4 x 3)
function DG.DrawnMap(name, area)
  local M = _G.QuesticusMap
  local drawn = M and M.MapDungeonDrawn
  if not drawn then return end
  local p = DG.PlaceOf(area, name)
  local floors = (p and drawn[p.id]) or drawn[name or ""]
  local f = floors and floors[1]
  return f and f.tiles
end

-- no picture anywhere (Alcaz Prison): the piece of the zone's own map around the entrance
function DG.ZoneTile(area)
  if not (area and C_Map and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayers) then return end
  local ent = D:Entrance(area)[1]
  local d = D:Dungeon(area)
  local map, mx, my = ent and ent.m, ent and ent.mx, ent and ent.my
  if not map and d and d[3] and d[3][1] then map, mx, my = d[3][1], d[3][2] / 1000, d[3][3] / 1000 end
  if not (map and mx) then return end
  local ok, layers = pcall(C_Map.GetMapArtLayers, map)
  local lay = ok and layers and layers[1]
  local ok2, tex = pcall(C_Map.GetMapArtLayerTextures, map, 1)
  if not (lay and ok2 and tex and #tex > 0) then return end
  local cols = math.ceil((lay.layerWidth or 1002) / (lay.tileWidth or 256))
  local rows = math.ceil((lay.layerHeight or 668) / (lay.tileHeight or 256))
  local cx = math.min(cols - 1, math.floor(mx * (lay.layerWidth or 1002) / (lay.tileWidth or 256)))
  local cy = math.min(rows - 1, math.floor(my * (lay.layerHeight or 668) / (lay.tileHeight or 256)))
  return tex[cy * cols + cx + 1]
end

-- (icon, background) textures for a dungeon
function DG.Art(name)
  local j = journalArt()[name or ""]
  local lfg = lfgArt()[DG.Key(name)] or DG.LFG[name or ""]
  local icon = (j and (j.small or j.button)) or (lfg and ("Interface\\LFGFrame\\LFGIcon-" .. lfg)) or DG.CASTLE
  local bg = (j and (j.button or j.bg)) or (lfg and ("Interface\\LFGFrame\\UI-LFG-BACKGROUND-" .. lfg)) or nil
  return icon, bg
end

-- ------------------------------------------------------------------ gold per run
-- Your own runs when there are some (the money you gained inside, learned below), else an estimate:
-- coin drops (a level based average for the mobs inside) + what the drops sell for (drop chances x the
-- vendor price, for items the game has loaded)
local function coin(lvl) return 0.025 * (lvl ^ 2.5) * 0.55 end   -- copper, the average kill (not all drop coins)
function DG:GoldPerRun(e)
  local av = Q.Runs and Q.Runs:Averages(e.area)
  if av and av.gold > 0 then return av.gold, av.runs end
  local runs = QuesticusCollect and QuesticusCollect.dgold and QuesticusCollect.dgold[e.area]
  if runs and #runs > 0 then
    local sum = 0
    for _, g in ipairs(runs) do sum = sum + g end
    return sum / #runs, #runs
  end
  local m = e.mobs
  if not (m and m.xpw and #m.xpw > 0) then return nil end
  local coins, goods, missing = 0, 0, 0
  local drops = Q.Bosses and Q.Bosses.NpcDrops
  for _, w in ipairs(m.xpw) do
    local lvl, count, rank, _, nid = w[1], w[2] or 1, w[3] or 0, w[4], w[5]
    coins = coins + coin(lvl) * count * ((rank == 1 or rank == 2) and 1.6 or (rank == 3 and 4 or 1))
    for _, d in ipairs((drops and nid) and drops(nid) or {}) do
      local price = select(11, Q.GetItemInfo(d[1]))
      if type(price) == "number" then goods = goods + price * d[2] * count
      else
        missing = missing + 1
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, d[1]) end
      end
    end
  end
  return coins + goods, 0, coins, goods, missing
end
-- money gained inside a dungeon: the difference between entering and leaving (see "learn clear times")
function DG.MoneyText(cp)
  cp = math.floor(cp or 0)
  local g, si, co = math.floor(cp / 10000), math.floor(cp / 100) % 100, cp % 100
  if g > 0 then return L("%dg %ds", g, si) end
  if si > 0 then return L("%ds %dc", si, co) end
  return co .. "c"
end

-- ------------------------------------------------------------------ a quest's status and its chain
DG.STATUS_COLOR = { done = T.HEX.good, log = T.HEX.white, can = "ffd100", locked = "ff4040" }
function DG:QuestState(id, lv)
  if QS.done[id] then return "done", "done" end
  if QS.log[id] then return "log", QS.log[id].complete and "ready to hand in" or "in your log" end
  local i = QS:Info(id)
  if QS:Available(id) then return "can", "can get now" end
  if i and lv < (i.min or 1) then
    -- too low, but is the chain open?
    return "locked", L("needs level %d", i.min)
  end
  return "locked", "needs an earlier quest"
end
local function factionName(id)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and d and d.name then return d.name end
  end
  if GetFactionInfoByID then local ok, n = pcall(GetFactionInfoByID, id); if ok and n then return n end end
  return "faction " .. tostring(id)
end
DG.SKILL = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
  [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing",
  [393] = "Skinning", [755] = "Jewelcrafting", [633] = "Lockpicking" }
local STANDING = { [0] = "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local function repText(v)
  -- QuestieDB's requiredMinRep value: reputation points from Neutral (0); show the standing it means
  if type(v) ~= "number" then return "" end
  local tiers = { { 42000, "Exalted" }, { 21000, "Revered" }, { 9000, "Honored" }, { 3000, "Friendly" }, { 0, "Neutral" } }
  for _, t in ipairs(tiers) do if v >= t[1] then return L[t[2]] end end
  return L["Unfriendly"]
end
DG.STANDING = STANDING
-- where a locked quest's chain starts: the earliest quests of it you can't skip, with giver, zone,
-- level and what else they need (reputation, profession)
function DG:ChainStart(id)
  local need = P.NeedChain and P.NeedChain(id) or { [id] = true }
  local starts = {}
  for q in pairs(need) do
    if q ~= id and not QS.done[q] and not QS.log[q] then
      local x = D:QuestExtra(q) or {}
      local blocked
      for _, pre in ipairs(x[4] or {}) do if need[pre] and not QS.done[pre] then blocked = true end end
      for _, pre in ipairs(x[3] or {}) do if need[pre] and not QS.done[pre] then blocked = true end end
      if not blocked then starts[#starts + 1] = q end
    end
  end
  table.sort(starts)
  local lines = {}
  for _, q in ipairs(starts) do
    local inf = QS:Info(q)
    local dq = D:Quest(q)
    local title = (inf and inf.title) or (dq and dq[1]) or (L["Quest "] .. q)
    local giver, zone = "", ""
    local gk = inf and inf.givers and inf.givers[1]
    if gk then
      giver = D:Name(gk)
      local z = P.QuestZone and P.QuestZone(q)
      local mi = z and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(z)
      if mi then zone = mi.name end
    end
    local minLv = (inf and inf.min) or (dq and dq[3]) or 1
    local x = D:QuestExtra(q) or {}
    local extra = {}
    if x[19] and x[19][1] then extra[#extra + 1] = factionName(x[19][1]) .. " " .. repText(x[19][2]) end
    if x[14] and x[14][1] then
      extra[#extra + 1] = ("%s %d"):format(L[DG.SKILL[x[14][1]] or ("skill " .. x[14][1])], x[14][2] or 0)
    end
    local avail = QS:Available(q)
    lines[#lines + 1] = { id = q, text = L("%s%s%s, level %d%s", 
      title, giver ~= "" and (" - " .. L("from %s", giver)) or "", zone ~= "" and (" " .. L("in %s", zone)) or "", minLv,
      #extra > 0 and (", " .. L("needs %s", table.concat(extra, ", "))) or ""), can = avail }
  end
  return lines, need
end

-- ------------------------------------------------------------------ list window
local rows = {}
local function listRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, list.body)
  r:SetHeight(34)
  r.pic = r:CreateTexture(nil, "ARTWORK")
  r.pic:SetSize(30, 30)
  r.pic:SetPoint("LEFT", 4, 0)
  r.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.07) end
  r.name = T.Text(r, 12, T.c.text)
  r.name:SetPoint("LEFT", 42, 0)
  r.lv = T.Text(r, 11, T.c.dim)
  r.lv:SetPoint("LEFT", 250, 0)
  r.q = T.Text(r, 11, T.c.dim)
  r.q:SetPoint("RIGHT", -6, 0)
  r.done = r:CreateTexture(nil, "OVERLAY")
  r.done:SetSize(16, 16)
  r.done:SetPoint("RIGHT", r.q, "LEFT", -4, 0)
  r.done:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  r.done:Hide()
  r:SetScript("OnClick", function(self) if self.e then DG:ShowDungeon(self.e) end end)
  rows[i] = r
  return r
end
DG.rows = rows

function DG:Show()
  if not list then
    list = T.Window("QuesticusDungeons", 430, 200, "Dungeons", nil)
    list:SetFrameStrata("HIGH")
    list.note = T.Text(list, 11, T.c.dim)
    list.note:SetPoint("TOPLEFT", 14, -32)
    list.note:SetText(L["Click a dungeon for levels, quests, XP and clear time."])
    list.scroll = CreateFrame("ScrollFrame", nil, list)
    list.scroll:SetPoint("TOPLEFT", 8, -50)
    list.scroll:SetPoint("BOTTOMRIGHT", -8, 10)
    list.body = CreateFrame("Frame", nil, list.scroll)
    list.body:SetSize(414, 1)
    list.scroll:SetScrollChild(list.body)
    if list.scroll.EnableMouseWheel then list.scroll:EnableMouseWheel(true) end
    list.scroll:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, (list.body:GetHeight() or 0) - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
  end
  local lv = Q.player.level or 1
  local all = DG:List()
  local y = 0
  for i, e in ipairs(all) do
    local r = listRow(i)
    r.e = e
    local inRange = e.lo and lv >= e.lo - 2 and lv <= (e.hi or e.lo) + 2
    local active = Q.char.dmode == e.area
    local pic = DG.Art(e.name)
    local tiles = (pic == DG.CASTLE) and DG.DrawnMap(e.name, e.area)
    local zt = (pic == DG.CASTLE and not tiles) and DG.ZoneTile(e.area)
    r.pic:SetTexture((tiles and tiles[6]) or zt or pic)
    r.pic:SetDesaturated(not inRange)
    local total, doneN, logN = #e.quests, 0, 0
    for _, id in ipairs(e.quests) do
      if QS.done[id] then doneN = doneN + 1 elseif QS.log[id] then logN = logN + 1 end
    end
    local complete = total > 0 and doneN == total
    r.name:SetText((active and c(GOLD, "> ") or "") .. (complete and c(T.HEX.good, e.name) or (inRange and c(T.HEX.white, e.name) or c(DIM, e.name))) ..
      (e.forever and c(T.HEX.good, L["  new"]) or ""))
    r.done:SetShown(complete)
    r.lv:SetText(e.lo and (e.lo == e.hi and tostring(e.lo) or (e.lo .. "-" .. (e.hi or e.lo))) or "?")
    -- done of all, and how many you're carrying now
    r.q:SetText(total > 0 and (complete and c(T.HEX.good, L("%d/%d quests", doneN, total))
      or (L("%d/%d done", doneN, total) .. (logN > 0 and c(T.HEX.white, L("  %d in log", logN)) or ""))) or "")
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
    y = y + 34
  end
  for i = #all + 1, #rows do rows[i]:Hide() end
  list.body:SetHeight(math.max(1, y))
  list:SetHeight(math.min(700, 60 + y + 12))
  if Q.Bosses then Q.Bosses.Front(list) else list:Show() end
  return all
end

-- ------------------------------------------------------------------ dungeon window: quest rows
-- each quest in its colour (done green, can get now yellow, in your log white, locked red); a locked one
-- says where its chain starts and has a button that puts the whole chain on your route
local qrows = {}
DG.qrows = qrows
DG.qdata = {}
local ICON = {
  done = "Interface\\RaidFrame\\ReadyCheck-Ready",
  log = "Interface\\GossipFrame\\ActiveQuestIcon",
  can = "Interface\\GossipFrame\\AvailableQuestIcon",
  locked = "Interface\\GossipFrame\\AvailableQuestIcon",
}
DG.INSIDE_ICON = Q.MEDIA .. "i_dungeon"
local function qrow(i)
  local r = qrows[i]
  if r then return r end
  r = CreateFrame("Button", nil, detail.qbody)
  r:SetFrameLevel(detail.qbody:GetFrameLevel() + 3)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("TOPLEFT", 6, -2)
  r.text = T.Text(r, 12, T.c.text)
  r.text:SetPoint("TOPLEFT", 26, -2)
  r.text:SetPoint("RIGHT", -190, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.status = T.Text(r, 11, T.c.dim)
  r.status:SetPoint("TOPRIGHT", -74, -3)
  r.status:SetWidth(112)
  r.status:SetJustifyH("RIGHT")
  r.status:SetWordWrap(false)
  r.chain = T.Text(r, 10, T.c.dim)
  r.chain:SetPoint("TOPLEFT", 26, -18)
  r.chain:SetPoint("RIGHT", -74, 0)
  r.chain:SetJustifyH("LEFT")
  r.chain:SetWordWrap(false)                 -- one line (the tooltip has all of it)
  r.add = T.Button(r, L["+ Route"], 66, 18)
  r.add:SetPoint("TOPRIGHT", -2, 0)
  r:SetScript("OnEnter", function(self)
    local d = DG.qdata[self]
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for k, l in ipairs(QS:QuestTip(d.id, nil, nil)) do
      if k == 1 then GameTooltip:AddLine(l, 1, 0.82, 0.3) else GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
    end
    if d.inside then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Picked up inside the dungeon"], 0.75, 0.5, 1)
    end
    if d.reason then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Not eligible yet: "] .. d.reason, 1, 0.4, 0.4, true)
      if d.starts and #d.starts > 0 then
        GameTooltip:AddLine(L["+ Route puts the start of its chain on your route."], 0.7, 0.7, 0.7, true)
      end
    end
    if d.starts and #d.starts > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Start the chain with:"], 1, 0.25, 0.25)
      for _, st in ipairs(d.starts) do GameTooltip:AddLine(st.text .. (st.can and L["  (you can get it now)"] or ""), 0.9, 0.9, 0.9, true) end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  qrows[i] = r
  return r
end
-- section headings and the inside box
local heads = {}
local function head(i)
  local h = heads[i]
  if h then return h end
  h = CreateFrame("Frame", nil, detail.qbody)
  h:SetFrameLevel(detail.qbody:GetFrameLevel() + 1)        -- (under the quest rows: the box sits behind them)
  h.box = h:CreateTexture(nil, "BACKGROUND")
  h.icon = h:CreateTexture(nil, "ARTWORK")
  h.icon:SetSize(16, 16)
  h.icon:SetPoint("TOPLEFT", 4, -3)

  h.text = T.Text(h, 12, T.c.text)
  h.text:SetPoint("TOPLEFT", 4, -4)
  h.text:SetPoint("RIGHT", -4, 0)
  h.text:SetJustifyH("LEFT")
  h.line = h:CreateTexture(nil, "ARTWORK")
  h.line:SetColorTexture(T.c.line[1], T.c.line[2], T.c.line[3], 0.6)
  h.line:SetHeight(1)
  h.line:SetPoint("BOTTOMLEFT", 0, 0)
  h.line:SetPoint("BOTTOMRIGHT", 0, 0)
  heads[i] = h
  return h
end
local SHORT = {
  ["done"] = "Done", ["ready to hand in"] = "Ready to hand in", ["in your log"] = "In your log",
  ["can get now"] = "Eligible",
}
function DG:QuestRows(e, lv, textH)
  local outside, inside = {}, {}
  for _, id in ipairs(e.quests) do
    if QS:Info(id) then
      if P.InsideStart and P.InsideStart(id) then inside[#inside + 1] = id else outside[#outside + 1] = id end
    end
  end
  local order = { log = 1, can = 2, locked = 3, done = 4 }
  local function sort(t)
    table.sort(t, function(a, b)
      local sa, sb = DG:QuestState(a, lv), DG:QuestState(b, lv)
      if sa ~= sb then return order[sa] < order[sb] end
      return (QS:Info(a).level or 0) < (QS:Info(b).level or 0)
    end)
  end
  sort(outside); sort(inside)
  local y, n, hn = 0, 0, 0
  local W = detail.qbody:GetWidth() or 410
  local function heading(text, icon, boxColor)
    hn = hn + 1
    local h = head(hn)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", detail.qbody, "TOPLEFT", 0, -y)
    h:SetPoint("RIGHT", detail.qbody, "RIGHT", 0, 0)
    h:SetHeight(22)
    h.icon:SetShown(icon ~= nil)
    if icon then h.icon:SetTexture(icon) end
    h.text:ClearAllPoints()
    h.text:SetPoint("TOPLEFT", icon and 26 or 4, -5)
    h.text:SetPoint("RIGHT", -4, 0)
    h.text:SetText(text)
    h.box:Hide()
    h:Show()
    y = y + 26
    return h
  end
  local function rows(list, isInside)
    for _, id in ipairs(list) do
      n = n + 1
      local r = qrow(n)
      local inf = QS:Info(id)
      local st, word = DG:QuestState(id, lv)
      local d = { id = id, inside = isInside }
      DG.qdata[r] = d
      r.icon:SetTexture(ICON[st])
      r.icon:SetDesaturated(st == "locked" or (st == "log" and word ~= "ready to hand in"))
      r.icon:SetAlpha(st == "locked" and 0.5 or 1)
      r.text:SetText(c(DG.STATUS_COLOR[st], inf.title) .. c(DIM, ("  %d"):format(inf.level)))
      -- eligible or not (why not: on hover, and the chain's start under it)
      r.status:SetText(st == "locked" and c("ff6060", L["Not eligible"]) or L[SHORT[word] or word])
      d.reason = st == "locked" and word or nil
      local hgt = 20
      if st == "locked" then
        local starts = DG:ChainStart(id)
        d.starts = starts
        local first = starts[1]
        r.chain:SetText(first and (c("ff8080", L["Starts with "]) .. first.text .. (#starts > 1 and c(DIM, L("  +%d more", #starts - 1)) or "")) or "")
        r.chain:Show()
        if first then hgt = 36 end
      else
        r.chain:Hide()
      end
      local forced = Q.char.forced and Q.char.forced[id]
      r.add:SetShown(st ~= "done" and st ~= "log")
      r.add:SetText(forced and L["On route"] or L["+ Route"])
      r.add.tip = forced and "Take this quest (and its chain) off your route" or "Put this quest on your route, with every earlier quest of its chain it needs"
      r.add:SetScript("OnClick", function()
        if Q.Tracker then Q.Tracker:Force(id, not (Q.char.forced and Q.char.forced[id])) end
        DG:ShowDungeon(e)
      end)
      r:SetHeight(hgt)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", detail.qbody, "TOPLEFT", 0, -y)
      r:SetPoint("RIGHT", detail.qbody, "RIGHT", 0, 0)
      r:Show()
      y = y + hgt + 2
    end
  end
  -- the heading: how far along you are
  local total = #outside + #inside
  if total == 0 then
    heading(c(DIM, L["No quests for your character here."]))
  else
    local dn, ln = 0, 0
    for _, id in ipairs(e.quests) do if QS.done[id] then dn = dn + 1 elseif QS.log[id] then ln = ln + 1 end end
    heading(c(GOLD, L["Quests"]) .. c(DIM, L("     %d of %d done", dn, total)) .. (ln > 0 and c(T.HEX.white, L("     %d in your log", ln)) or ""))
    if #inside > 0 then
      if #outside > 0 then
        heading(c(T.HEX.white, L["Picked up outside"]) .. c(DIM, ("   %d"):format(#outside)))
        rows(outside, false)
        y = y + 6
      end
      -- the ones you can only get in there, in their own tinted box
      local top = y
      local h = heading(c("c080ff", L["Picked up inside the dungeon"]) .. c(DIM, L("   %d  -  you get these on the run", #inside)), DG.INSIDE_ICON)
      rows(inside, true)
      h.box:ClearAllPoints()
      h.box:SetPoint("TOPLEFT", h, "TOPLEFT", -2, 2)
      h.box:SetPoint("RIGHT", h, "RIGHT", 2, 0)
      h.box:SetHeight(y - top + 4)
      h.box:SetColorTexture(0.55, 0.3, 0.85, 0.12)
      h.box:Show()
    else
      rows(outside, false)
    end
  end
  for i = n + 1, #qrows do qrows[i]:Hide(); DG.qdata[qrows[i]] = nil end
  for i = hn + 1, #heads do heads[i]:Hide() end
  detail.qbody:SetHeight(math.max(1, y))
  return y
end

-- ------------------------------------------------------------------ dungeon window
function DG:ShowDungeon(e)
  if not detail then
    detail = T.Window("QuesticusDungeon", 440, 300, "Dungeon", nil)
    detail:SetFrameStrata("HIGH")
    -- the dungeon's picture across the top
    detail.banner = detail:CreateTexture(nil, "ARTWORK")
    detail.banner:SetPoint("TOPLEFT", 10, -30)
    detail.banner:SetPoint("TOPRIGHT", -10, -30)
    detail.banner:SetHeight(90)
    detail.icon = detail:CreateTexture(nil, "OVERLAY")
    detail.icon:SetSize(48, 48)
    detail.icon:SetPoint("BOTTOMLEFT", detail.banner, "BOTTOMLEFT", 8, 8)
    detail.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detail.text = T.Text(detail, 12, T.c.text)
    detail.text:SetPoint("TOPLEFT", detail.banner, "BOTTOMLEFT", 4, -8)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetSpacing(4)
    detail.text:SetWidth(96)
    detail.text:SetWordWrap(false)
    -- (the values, lined up beside their labels)
    detail.vals = T.Text(detail, 12, T.c.text)
    detail.vals:SetPoint("TOPLEFT", detail.text, "TOPLEFT", 100, 0)
    detail.vals:SetPoint("RIGHT", -14, 0)
    detail.vals:SetJustifyH("LEFT")
    detail.vals:SetSpacing(4)
    detail.vals:SetWordWrap(false)
    -- the quests scroll in their own area between the details and the buttons
    detail.qscroll = CreateFrame("ScrollFrame", nil, detail)
    detail.qscroll:SetPoint("BOTTOMRIGHT", -12, 44)
    detail.qbody = CreateFrame("Frame", nil, detail.qscroll)
    detail.qbody:SetSize(410, 1)
    detail.qscroll:SetScrollChild(detail.qbody)
    if detail.qscroll.EnableMouseWheel then detail.qscroll:EnableMouseWheel(true) end
    detail.qscroll:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, (detail.qbody:GetHeight() or 0) - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 36)))
    end)
    detail.go = T.Button(detail, L["Get all quests"], 140, 24)
    detail.go:SetPoint("BOTTOMRIGHT", -14, 12)
    detail.back = T.Button(detail, L["All dungeons"], 110, 24)
    detail.back:SetPoint("RIGHT", detail.go, "LEFT", -8, 0)
    detail.bosses = T.Button(detail, L["Bosses"], 80, 24)
    detail.bosses:SetPoint("RIGHT", detail.back, "LEFT", -8, 0)
    detail.bosses:SetScript("OnClick", function() if Q.Bosses and detail.e then Q.Bosses:Show(detail.e) end end)
    detail.back:SetScript("OnClick", function() detail:Hide(); DG:Show() end)
    detail.hist = T.Button(detail, L["Runs"], 60, 24)
    detail.hist:SetPoint("RIGHT", detail.bosses, "LEFT", -8, 0)
    detail.hist.tip = L["Your runs of this dungeon: times, gold, XP, loot and averages"]
    detail.hist:SetScript("OnClick", function() if Q.Runs and detail.e then Q.Runs:ShowHistory(detail.e.area) end end)
  end
  if list and list:IsShown() and detail.ClearAllPoints then
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
  end
  local lv = Q.player.level or 1
  detail.title:SetText(Q.Color(T.HEX.accent, e.name))
  local icon, bg = DG.Art(e.name)
  local tiles = DG.DrawnMap(e.name, e.area)
  local zt = (icon == DG.CASTLE and not tiles) and DG.ZoneTile(e.area)
  detail.icon:SetTexture((icon == DG.CASTLE and tiles) and tiles[6] or zt or icon)
  if not bg and not tiles and zt then bg = zt end
  DG.bannerTiles = DG.bannerTiles or {}
  local btiles = DG.bannerTiles
  for _, t in ipairs(btiles) do t:Hide() end
  if not bg and tiles then
    -- the dungeon's drawn map (4 x 3 tiles) as its picture, centred in the banner
    local w, h = 135, 90
    for k = 1, 12 do
      local t = btiles[k]
      if not t then t = detail:CreateTexture(nil, "ARTWORK", nil, 1); btiles[k] = t end
      t:SetTexture(tiles[k])
      t:SetSize(w / 4, h / 3)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", detail.banner, "TOP", -w / 2 + ((k - 1) % 4) * w / 4, -math.floor((k - 1) / 4) * h / 3)
      t:Show()
    end
  end
  if bg then
    detail.banner:SetTexture(bg)
    detail.banner:SetTexCoord(0, 1, 0.15, 0.85)
    detail.banner:SetVertexColor(1, 1, 1, 1)
  else
    detail.banner:SetTexture("Interface\\Buttons\\WHITE8x8")
    detail.banner:SetVertexColor(T.c.line[1], T.c.line[2], T.c.line[3], 0.35)
  end
  -- the facts, as a tidy two-column table: what on the left, the value on the right
  local labels, values = {}, {}
  local function row(label, value)
    labels[#labels + 1] = c(DIM, L[label])
    values[#values + 1] = value
    L[#L + 1] = label .. "  " .. value
  end
  local function note(s) return c(DIM, s) end   -- (s is put together already)
  local ent = D:Entrance(e.area)[1]
  local mi = ent and ent.m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ent.m)
  if e.forever then row(L["New"], c(T.HEX.good, L["in WoW Forever"]) .. (e.where and note("  -  " .. e.where) or "")) end
  if mi then row(L["Entrance"], mi.name .. (ent.mx and note(("   %.1f, %.1f"):format(ent.mx * 100, ent.my * 100)) or "")) end
  if e.lo then row(e.forever and "Levels" or "Mob levels", e.lo == e.hi and tostring(e.lo) or (e.lo .. " - " .. e.hi)) end
  local qlo, qhi = 999, 0
  for _, id in ipairs(e.quests) do local i = QS:Info(id); if i then qlo, qhi = math.min(qlo, i.min or 1), math.max(qhi, i.level) end end
  if qhi > 0 then row(L["Quests"], L("level %d - %d", qlo, qhi) .. note("   " .. L("you can pick them up from level %d", qlo))) end
  local m = e.mobs
  if m and m.fromSpawns and m.spawns > 0 then row(L["Mobs"], m.spawns .. note("   " .. L("%d elite", m.elites))) end
  local bossNames = DG.BossNames(e)
  if bossNames then
    row(L["Bosses"], table.concat(bossNames, ", "))
  elseif m and #m.bosses > 0 then
    local b = {}
    for i = 1, math.min(6, #m.bosses) do b[i] = m.bosses[i] end
    row(L["Named elites"], table.concat(b, ", ") .. (#m.bosses > 6 and (" +%d"):format(#m.bosses - 6) or ""))
  end
  local ct, runs = DG:ClearTime(e)
  if ct then
    row("Clear time", mins(ct) .. note("   " .. ((runs and runs > 0) and (runs == 1 and L["your average, 1 run"] or L("your average, %d runs", runs)) or L["estimate"])))
  end
  local mx = DG:MobXP(e, lv)
  local qxp, todo, can = 0, 0, 0
  for _, id in ipairs(e.quests) do
    if not QS.done[id] then
      todo = todo + 1
      qxp = qxp + (QS.RewardXP(id, lv) or 0)
      if QS.log[id] or QS:Available(id) then can = can + 1 end
    end
  end
  local function num(n) n = math.floor(n + 0.5); local s2 = tostring(n); while true do local r2, k2 = s2:gsub("^(%d+)(%d%d%d)", "%1,%2"); s2 = r2; if k2 == 0 then break end end return s2 end
  if mx and mx >= 1 then row(L["XP per clear"], "~" .. num(mx) .. note("   " .. L["each, group of 5, from mobs"])) end
  if qxp > 0 then row("Quest XP left", num(qxp) .. note("   " .. (todo == 1 and L("1 quest, %d you can do now", can) or L("%d quests, %d you can do now", todo, can)))) end
  if ct and ct > 0 and ((mx or 0) + qxp) > 0 then
    row(L["XP per hour"], "~" .. num(((mx or 0) + qxp) / ct * 3600) .. note("   " .. L["one run plus its quests"]))
  end
  local gold, gruns, coins, goods, missing = DG:GoldPerRun(e)
  if gold and gold > 0 then
    if gruns and gruns > 0 then
      row("Gold per run", c(GOLD, DG.MoneyText(gold)) .. note("   " .. (gruns == 1 and L["your average, 1 run"] or L("your average, %d runs", gruns))))
    else
      local est = "   " .. ((goods or 0) > 0 and L("estimate: %s coin + %s in drops", DG.MoneyText(coins), DG.MoneyText(goods))
        or L["estimate, coin only"])
      row(L["Gold per run"], c(GOLD, "~" .. DG.MoneyText(gold)) .. note(est .. ((missing or 0) > 0 and (" " .. L["(more once items load)"]) or "")))
    end
  end
  detail.text:SetText(table.concat(labels, "\n"))
  detail.vals:SetText(table.concat(values, "\n"))
  local h = (detail.text.GetStringHeight and detail.text:GetStringHeight()) or (#labels * 17)
  if type(h) ~= "number" or h < #labels * 10 then h = #labels * 17 end
  h = h + 8
  local qh = DG:QuestRows(e, lv, h)
  -- the window grows with the quests up to 300 px of them; more than that scroll
  detail.qscroll:ClearAllPoints()
  detail.qscroll:SetPoint("TOPLEFT", detail.text, "TOPLEFT", 0, -(h + 4))
  detail.qscroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -12, 44)
  detail.qscroll:SetVerticalScroll(0)
  detail:SetHeight(34 + 98 + h + math.min(qh, 300) + 8 + 48)
  local active = Q.char.dmode == e.area
  detail.go:SetText(active and L["Stop dungeon mode"] or L["Get all quests"])
  detail.go:SetShown(active or todo > 0)
  detail.go.tip = active and "Back to your normal route" or
    "Dungeon mode: routes you to every quest of this dungeon (and the chains that unlock them), then into it"
  detail.go:SetScript("OnClick", function()
    if Q.char.dmode == e.area then
      P:DungeonMode(nil)
      Q:Print(L["dungeon mode off"])
    else
      P:DungeonMode(e.area)
      Q:Print(L("dungeon mode: getting every quest for %s", e.name))
    end
    DG:ShowDungeon(e)
    if list and list:IsShown() then DG:Show() end
  end)
  detail.e = e
  if Q.Bosses then Q.Bosses.Front(detail) else detail:Show() end
  return L
end

-- ------------------------------------------------------------------ learn clear times
local run
local function where()
  if not GetInstanceInfo then return end
  local _, itype, _, _, _, _, _, mapID = GetInstanceInfo()
  if itype ~= "party" then return end
  if mapID and D.INSTANCE_AREA[mapID] then return D.INSTANCE_AREA[mapID] end
  local e = Q.Bosses and Q.Bosses:Current()           -- WoW Forever's dungeons: by name
  return e and e.area
end
local function check()
  local area = where()
  local now = GetTime and GetTime() or 0
  if area and not run then
    run = { area = area, start = now, money = GetMoney and GetMoney() or 0 }
  elseif run and area ~= run.area then
    local dur = now - run.start
    if dur >= 300 and dur <= 4 * 3600 and QuesticusCollect and Q.db.collect ~= false then
      QuesticusCollect.dclear = QuesticusCollect.dclear or {}
      local t = QuesticusCollect.dclear[run.area] or {}
      t[#t + 1] = math.floor(dur)
      while #t > 10 do table.remove(t, 1) end
      QuesticusCollect.dclear[run.area] = t
      -- the money you made in there (coins and loot sold by the next visit count from the next run)
      local gained = (GetMoney and GetMoney() or 0) - (run.money or 0)
      if gained > 0 then
        QuesticusCollect.dgold = QuesticusCollect.dgold or {}
        local g = QuesticusCollect.dgold[run.area] or {}
        g[#g + 1] = gained
        while #g > 10 do table.remove(g, 1) end
        QuesticusCollect.dgold[run.area] = g
      end
    end
    run = area and { area = area, start = now, money = GetMoney and GetMoney() or 0 } or nil
  end
end
Q:On("PLAYER_ENTERING_WORLD", check)
Q:On("ZONE_CHANGED_NEW_AREA", check)

Q:Command("dungeons", "every dungeon: levels, quests, XP, clear time - and dungeon mode (get all its quests)", function() DG:Show() end)
Q:Command("dungeonoff", "leave dungeon mode", function() if Q.char.dmode then P:DungeonMode(nil); Q:Print(L["dungeon mode off"]) end end)
