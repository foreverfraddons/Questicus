-- Questicus data layer: reads the shared ForeverDB addon (LoadOnDemand) and turns its spawn data
-- into points with world coordinates (yards, for routing) and map positions (for pins).
local Q = Questicus
local L = Q.L
local D = {}
Q.Data = D

local DB                      -- the ForeverDB global
local pointCache = {}         -- key ("c123" / "o45") -> list of points
local MAX_POINTS = 60

local function loadAddon(name)
  if C_AddOns and C_AddOns.LoadAddOn then return C_AddOns.LoadAddOn(name) end
  if LoadAddOn then return LoadAddOn(name) end
end

function D:Load()
  if not _G.ForeverDB then pcall(loadAddon, "ForeverDB") end
  DB = _G.ForeverDB
  if not DB or not DB.quest then
    Q:Print(L["ForeverDB is missing - install it (CurseForge: ForeverDB). Questicus needs it for quest data."])
    return false
  end
  if not (DB.qx and DB.nfac and DB.qe) then
    Q:Print(L["Your ForeverDB is too old for Questicus (it has no quest details). Update ForeverDB on CurseForge."])
    D.old = true
    return false
  end
  D.db = DB
  if Q.SecretsPatch then pcall(Q.SecretsPatch, DB) end      -- (Secrets.lua: hidden quest chains)
  D:Index()
  return true
end

function D:Ready() return DB ~= nil end
function D:Meta() return DB and DB.meta end

-- reverse lookups built once
function D:Index()
  D.rewards = {}                 -- quest -> { itemIDs }
  for item, quests in pairs(DB.rew or {}) do
    for _, q in ipairs(quests) do
      local t = D.rewards[q]
      if not t then t = {}; D.rewards[q] = t end
      t[#t + 1] = item
    end
  end
  D.startItem = {}               -- quest -> item that starts it
  for item, q in pairs(DB.start or {}) do D.startItem[q] = item end
  D.flightMasters = {}           -- npc ids whose title is a flight master's (any race's name for it)
  local FM = { ["flight master"] = true, ["wind rider master"] = true, ["gryphon master"] = true,
    ["hippogryph master"] = true, ["bat handler"] = true, ["wind rider keeper"] = true }
  for id, n in pairs(DB.npc or {}) do
    if type(n[2]) == "string" and FM[n[2]:lower()] then D.flightMasters[#D.flightMasters + 1] = id end
  end
end

-- ------------------------------------------------------------------ records
function D:Quest(id) return DB.quest[id] end                 -- {title, level, minLevel}
function D:QuestExtra(id) return DB.qx and DB.qx[id] end      -- see ForeverDB README (qx)
function D:Givers(id) return DB.qg[id] end
function D:Enders(id) return DB.qe and DB.qe[id] end
function D:NPC(id) return DB.npc[id] end                      -- {name, sub, minLv, maxLv, rank}
function D:Object(id) return DB.obj[id] end
function D:Item(id) return DB.item[id] end                    -- {name, quality, reqLevel}
function D:Faction(npcID) return DB.nfac and DB.nfac[npcID] end
function D:Note(key) return key and DB.note and DB.note[(key:gsub(":", ""))] end   -- hand-written tip
function D:Vendors(item) return DB.vend and DB.vend[item] end

-- ------------------------------------------------------------------ the client's language
-- ForeverDB is in English. On a client in another language (German, French, ...) the quest log, the
-- names on screen and the quest window are in that language: names are looked up in it by id
-- (items: the game knows them; NPCs: a tooltip of the creature; quests: the quest log / the game's
-- quest cache; objects: learned when you see them) and kept in QuesticusDB.loc[locale].
local LOCALE = GetLocale and GetLocale() or "enUS"
D.LOCALE = LOCALE
D.ENGLISH = LOCALE == "enUS" or LOCALE == "enGB"
Q.ENGLISH = D.ENGLISH
local function str(v) return type(v) == "string" and not Q.Secret(v) and v ~= "" and v or nil end
function D.Loc()
  if D.ENGLISH or not QuesticusDB then return nil end
  QuesticusDB.loc = QuesticusDB.loc or {}
  local l = QuesticusDB.loc[LOCALE]
  if not l then l = { c = {}, o = {}, q = {} }; QuesticusDB.loc[LOCALE] = l end
  return l
end
-- remember a name seen in the client's language: kind "c" / "o" / "q"
function D.LearnName(kind, id, name)
  local l = D.Loc()
  name = str(name)
  if not (l and l[kind] and id and name) then return end
  if name == UNKNOWNOBJECT or name == UNKNOWN then return end
  l[kind][id] = name
end
local tipTried = {}
-- the name in the client's language (nil on an English client, or not known yet)
function D:LocalName(key)
  if D.ENGLISH or type(key) ~= "string" then return nil end
  local kind, id = key:sub(1, 1), tonumber(key:sub(2))
  if not id then return nil end
  local l = D.Loc()
  if kind == "i" then
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not str(n) and GetItemInfo then n = GetItemInfo(id) end
    return str(n)
  elseif kind == "c" then
    if l and l.c[id] then return l.c[id] end
    -- the creature's tooltip has its name in the client's language (asked once per session)
    if not tipTried[id] and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
      tipTried[id] = true
      local ok, data = pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
      local line = ok and data and data.lines and data.lines[1]
      local n = line and str(line.leftText)
      if n then D.LearnName("c", id, n); return n end
    end
  elseif kind == "o" then
    return l and l.o[id]
  elseif kind == "q" then
    if l and l.q[id] then return l.q[id] end
    local n = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if str(n) then D.LearnName("q", id, n); return n end
    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
  end
  return nil
end
Q:On("QUEST_DATA_LOAD_RESULT", function(id, ok)
  if ok and id and not D.ENGLISH then D:LocalName("q" .. id) end
end)

-- the English name from ForeverDB (for matching against the database's own text)
function D:EName(key)
  local kind, id = key:sub(1, 1), tonumber(key:sub(2))
  if kind == "c" then local n = DB.npc[id]; return n and n[1] end
  if kind == "o" then local o = DB.obj[id]; return o and o[1] end
  if kind == "i" then local it = DB.item[id]; return it and it[1] end
end
function D:Name(key)
  if key:sub(1, 4) == "taxi" then
    local n = Q.Flight and Q.Flight:Node(tonumber(key:sub(5)))
    return n and (n.name .. L[" (flight master)"]) or L["Flight master"]
  end
  if not D.ENGLISH then
    local ln = D:LocalName(key)
    if ln then return ln end
  end
  local kind, id = key:sub(1, 1), tonumber(key:sub(2))
  if kind == "c" then local n = DB.npc[id]; return n and n[1] or ("NPC " .. id) end
  if kind == "o" then local o = DB.obj[id]; return o and o[1] or ("object " .. id) end
  if kind == "i" then local it = DB.item[id]; return it and it[1] or ("item " .. id) end
  return key
end

-- item sources: list of {key, chance (0-1, 0 = unknown)} best first
function D:ItemSources(item, limit)
  local out = {}
  for _, pair in ipairs({ { "drop", "c" }, { "odrop", "o" } }) do
    local t = DB[pair[1]] and DB[pair[1]][item]
    if t then
      for i = 1, #t - 1, 2 do
        local rec = pair[2] == "c" and DB.npc[t[i]]
        -- "[DNT]" npcs are invisible kill-credit helpers, not mobs you can fight
        if not (rec and rec[1] and rec[1]:find("^%[DNT%]")) then
          out[#out + 1] = { key = pair[2] .. t[i], chance = (t[i + 1] or 0) / 10000 }
        end
      end
    end
  end
  -- bought from a vendor
  for _, npc in ipairs(DB.vend and DB.vend[item] or {}) do
    out[#out + 1] = { key = "c" .. npc, chance = 1, vendor = true }
  end
  -- found inside another item (a crate, a satchel ...): that item's sources
  local box = DB.idrop and DB.idrop[item]
  if box and not D.__inBox then
    D.__inBox = true
    for i = 1, #box - 1, 2 do
      for _, s in ipairs(D:ItemSources(box[i], 2)) do
        out[#out + 1] = { key = s.key, chance = s.chance * ((box[i + 1] or 0) > 0 and box[i + 1] / 10000 or 0.5), via = box[i] }
      end
    end
    D.__inBox = nil
  end
  table.sort(out, function(a, b) return a.chance > b.chance end)
  if limit and #out > limit then for i = #out, limit + 1, -1 do out[i] = nil end end
  return out
end

-- ------------------------------------------------------------------ dungeons
-- instance map ids of the classic dungeons -> their area id in ForeverDB's dng table
D.INSTANCE_AREA = { [33] = 209, [34] = 717, [36] = 1581, [43] = 718, [47] = 491, [48] = 719, [70] = 1337, [90] = 721,
  [109] = 1477, [129] = 722, [189] = 796, [209] = 1176, [229] = 1583, [230] = 1584, [289] = 2057, [329] = 2017,
  [349] = 2100, [389] = 2437, [429] = 2557 }
D.RAID_AREA = { [2717] = true, [2677] = true, [3428] = true, [3429] = true, [1977] = true, [2159] = true, [3456] = true }

-- dungeons ForeverDB doesn't have yet (WoW Forever's newest; Questicus Maps' place data, Dungeons.lua):
-- [ -instance mapID ] = the same shape
D.EXTRA_DNG = {}
function D:Dungeon(area) return (DB.dng and DB.dng[area]) or D.EXTRA_DNG[area] end      -- {name, parentArea, {uiMap, x, y, ...}}

-- entrance points of a dungeon (marked with .dungeon = area)
local entranceCache = {}
function D:Entrance(area)
  local c = entranceCache[area]
  if c then return c end
  c = {}
  local d = D:Dungeon(area)
  local spots = d and d[3]
  for j = 1, #(spots or {}) - 2, 3 do
    local map, mx, my = spots[j], spots[j + 1] / 1000, spots[j + 2] / 1000
    local inst, x, y = D:WorldPos(map, mx, my)
    if inst then c[#c + 1] = { i = inst, x = x, y = y, m = map, mx = mx, my = my, dungeon = area } end
  end
  entranceCache[area] = c
  return c
end

-- ------------------------------------------------------------------ coordinates
-- A point: { i = instance (continent) id, x, y = world coords (yards), m = uiMap, mx, my = 0-1 }
-- World coords follow the server databases: x grows to the north, y to the west, which is also
-- what UnitPosition returns (first value = x).
local vec = CreateVector2D or function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
D.vec = vec

local function getXY(v)
  if not v then return nil end
  if v.GetXY then return v:GetXY() end
  return v.x, v.y
end

-- uiMap + 0-1 position for a world point (zone level map if the game knows one)
function D:MapPos(pt)
  if pt.m ~= nil then return pt.m ~= false and pt.m or nil, pt.mx, pt.my end
  pt.m = false
  if not (C_Map and C_Map.GetMapPosFromWorldPos) then return end
  local ok, map, pos = pcall(C_Map.GetMapPosFromWorldPos, pt.i, vec(pt.x, pt.y))
  if not ok or not map then return end
  local mx, my = getXY(pos)
  if C_Map.GetMapInfoAtPosition and mx then
    local ok2, info = pcall(C_Map.GetMapInfoAtPosition, map, mx, my)
    if ok2 and info and info.mapID and info.mapID ~= map then
      local ok3, zm, zpos = pcall(C_Map.GetMapPosFromWorldPos, pt.i, vec(pt.x, pt.y), info.mapID)
      if ok3 and zm then map, mx, my = zm, getXY(zpos) end
    end
  end
  if mx then pt.m, pt.mx, pt.my = map, mx, my end
  return pt.m or nil, pt.mx, pt.my
end

-- ------------------------------------------------------------------ real walking distances
-- ForeverDB's spf.Walks has the real walking distance between flight masters, docks and portals
-- (Shortest Path Forever: around cliffs, mountains and water). From that, a lower bound for the walk
-- between any two points: from the place in each point's own zone nearest it. Freewind Post to
-- Un'Goro is ~1450 yd in a straight line but ~8200 on foot (down through Tanaris).
local walkPlaces            -- [continent] = { { key, i, x, y, map }, ... }
local function places(cont)
  walkPlaces = walkPlaces or {}
  if walkPlaces[cont] ~= nil then return walkPlaces[cont] end
  local spf = DB and DB.spf
  local wp = spf and spf.WalkPlaces and spf.WalkPlaces[cont]
  local out = false
  if wp and spf.Walks and spf.Walks[cont] then
    out = {}
    for key, xy in pairs(wp) do
      local p = { i = cont, x = xy[1], y = xy[2] }
      out[#out + 1] = { key = key, p = p, map = (D:MapPos(p)) }
    end
  end
  walkPlaces[cont] = out
  return out
end
-- the walk place nearest a point in its own zone (cached on the point)
local function placeOf(pt)
  if pt._wpl ~= nil then return pt._wpl or nil, pt._wpd end
  pt._wpl = false
  local list = places(pt.i)
  if not list then return end
  local map = D:MapPos(pt)
  if not map then return end
  local best, bd
  for _, w in ipairs(list) do
    if w.map == map then
      local d = D.Dist(pt, w.p)
      if not bd or d < bd then best, bd = w, d end
    end
  end
  if best then pt._wpl, pt._wpd = best, bd end
  return best, bd
end
local walkMemo = {}
local walkDistPlaces
function D.WalkDist(a, b)
  local s = D.Dist(a, b)
  if not (a and b) or a.i ~= b.i or s < 150 then return s end
  -- through the zone crossings when the two are in different zones (mountains between zones)
  local zw = D.ZoneWalk and D.ZoneWalk(a, b)
  local w0 = walkDistPlaces(a, b, s)
  return zw and zw > w0 and zw or w0
end
function walkDistPlaces(a, b, s)
  local pa, da = placeOf(a)
  local pb, db = placeOf(b)
  if not (pa and pb) or pa == pb then return s end
  local row = walkMemo[pa.key]
  if not row then row = {}; walkMemo[pa.key] = row end
  local w = row[pb.key]
  if w == nil then
    local t = DB.spf.Walks[a.i]
    local e = t[pa.key .. " " .. pb.key] or t[pb.key .. " " .. pa.key]
    w = e and (e[1] or e[2]) or false
    row[pb.key] = w
  end
  if not w then return s end
  local lb = w - 1.25 * (da or 0) - 1.25 * (db or 0)
  return lb > s and lb or s
end

-- world point for a uiMap position (0-1)
function D:WorldPos(map, mx, my)
  if not (C_Map and C_Map.GetWorldPosFromMapPos) then return end
  local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, map, vec(mx, my))
  if not ok or not inst then return end
  local x, y = getXY(pos)
  return inst, x, y
end

-- every known spot of an npc / object, world coords first, else Forever map spots
-- spots you Ctrl-clicked away ("nothing here"): QuesticusCollect.removed[key] = { {i, x, y, m, mx, my}, ... }
-- account-wide; sent to ForeverDB with the recordings so the spot goes for everyone
local REMOVE_NEAR = 12
local function removedList(key)
  return QuesticusCollect and QuesticusCollect.removed and QuesticusCollect.removed[key]
end
function D:IsRemoved(key, p)
  local list = removedList(key)
  if not list then return false end
  for _, r in ipairs(list) do
    if r.i == p.i and math.abs(r.x - p.x) <= REMOVE_NEAR and math.abs(r.y - p.y) <= REMOVE_NEAR then return true end
  end
  return false
end
local undo = {}
function D:RemoveSpot(key, p)
  if not (key and p and p.i) then return end
  QuesticusCollect = QuesticusCollect or {}
  QuesticusCollect.removed = QuesticusCollect.removed or {}
  local list = QuesticusCollect.removed[key] or {}
  QuesticusCollect.removed[key] = list
  local m, mx, my = D:MapPos(p)
  list[#list + 1] = { i = p.i, x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10,
    m = m, mx = mx and math.floor(mx * 1000 + 0.5), my = my and math.floor(my * 1000 + 0.5) }
  undo[#undo + 1] = key
  pointCache[key] = nil
  if D.ForgetPatrol then D:ForgetPatrol(key) end
  Q:Print(L("removed a spot of %s - gone from your map and routes, and from ForeverDB once your recordings are synced (/qc spots undo puts it back)", D:Name(key)))
  if Q.Planner then Q.Planner:Reset(); Q.Planner:Replan(0.2) end
  if Q.Pins and Q.Pins.RefreshWorld then Q.Pins:RefreshWorld(true) end
  return true
end
-- ------------------------------------------------------------------ spawns the database doesn't have
-- A quest mob seen standing (out of combat) more than NEW_SPAWN yards from every spawn ForeverDB knows:
-- that's a spawn point too. Saved in QuesticusCollect.nspawn (ForeverDB adds it to spw for everyone)
-- and used at once by the map, the arrow and the route.
local NEW_SPAWN = 30
-- is p within r yards of a spawn already known (every spawn in the database, not just the first few)?
function D:KnownSpawnNear(key, p, r)
  r = r or NEW_SPAWN
  local r2 = r * r
  for _, g in ipairs(DB.spw and DB.spw[key] or {}) do
    if g[1] == p.i then
      for j = 2, #g - 1, 2 do
        if (g[j] - p.x) ^ 2 + (g[j + 1] - p.y) ^ 2 <= r2 then return true end
      end
    end
  end
  local spm = DB.spm and DB.spm[key]
  if spm then
    for map, pts in pairs(spm) do
      for j = 1, #pts - 1, 2 do
        local inst, x, y = D:WorldPos(map, pts[j] / 1000, pts[j + 1] / 1000)
        if inst == p.i and (x - p.x) ^ 2 + (y - p.y) ^ 2 <= r2 then return true end
      end
    end
  end
  local own = QuesticusCollect and QuesticusCollect.nspawn and QuesticusCollect.nspawn[key]
  for _, q in ipairs(type(own) == "table" and own or {}) do
    if q.i == p.i and (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 <= r2 then return true end
  end
  return false
end
function D:AddSpawn(key, p)
  if not (key and p and p.i) or not QuesticusCollect or (Q.db and Q.db.collect == false) then return end
  if D:KnownSpawnNear(key, p) then return end
  QuesticusCollect.nspawn = type(QuesticusCollect.nspawn) == "table" and QuesticusCollect.nspawn or {}
  local list = QuesticusCollect.nspawn[key] or {}
  QuesticusCollect.nspawn[key] = list
  if #list >= 40 then return end
  local m, mx, my = D:MapPos(p)
  list[#list + 1] = { i = p.i, x = math.floor(p.x + 0.5), y = math.floor(p.y + 0.5), t = time and time() or 0,
    m = m, mx = mx and math.floor(mx * 1000 + 0.5), my = my and math.floor(my * 1000 + 0.5) }
  pointCache[key] = nil
  Q:Print(L("found a new spawn point of %s - added to your map and routes, and to ForeverDB with your recordings", D:Name(key)))
  Q.Throttle("newspawn", 3, function()
    if Q.Planner then Q.Planner:Reset(); Q.Planner:Replan(1) end
    if Q.Pins and Q.Pins.RefreshWorld then Q.Pins:RefreshWorld(true) end
  end)
  return true
end

Q:Command("spots", "spots you removed with Ctrl-click (/qc spots undo puts the last one back, /qc spots reset all)", function(arg)
  local r = QuesticusCollect and QuesticusCollect.removed or {}
  if arg == "undo" then
    local key = table.remove(undo)
    if not key then for k in pairs(r) do key = k end end     -- after a /reload: any one
    if key and r[key] then table.remove(r[key]); if #r[key] == 0 then r[key] = nil end end
    pointCache[key or ""] = nil
    if Q.Planner then Q.Planner:Reset(); Q.Planner:Replan(0.2) end
    Q:Print(key and (L["put back a spot of "] .. D:Name(key)) or L["nothing to undo"])
    return
  elseif arg == "reset" then
    if QuesticusCollect then QuesticusCollect.removed = nil end
    wipe(pointCache)
    if Q.Planner then Q.Planner:Reset(); Q.Planner:Replan(0.2) end
    Q:Print(L["all removed spots are back"])
    return
  end
  local n = 0
  for k, list in pairs(r) do n = n + #list; Q:Print(L("%s: %d spot(s) removed", D:Name(k), #list)) end
  if n == 0 then Q:Print(L["no spots removed - Ctrl-click a wrong map or minimap icon to remove it"]) end
end)

function D:Points(key)
  local c = pointCache[key]
  if c then return c end
  c = {}
  local spw = DB.spw and DB.spw[key]
  local inDungeon = {}
  if spw then
    for _, g in ipairs(spw) do
      local inst = g[1]
      local area = D.INSTANCE_AREA[inst]
      if area then
        inDungeon[area] = true             -- spawns inside a dungeon: route to its entrance
      else
        for j = 2, #g - 1, 2 do
          if #c >= MAX_POINTS then break end
          c[#c + 1] = { i = inst, x = g[j], y = g[j + 1] }
        end
      end
    end
  end
  -- spawns players found that the database didn't have (Spots.lua; ForeverDB merges them into spw)
  local own = QuesticusCollect and QuesticusCollect.nspawn and QuesticusCollect.nspawn[key]
  for _, p in ipairs(type(own) == "table" and own or {}) do
    if #c >= MAX_POINTS then break end
    if p.i and p.x then c[#c + 1] = { i = p.i, x = p.x, y = p.y, found = true } end
  end
  for _, area in ipairs(DB.ind and DB.ind[key] or {}) do inDungeon[area] = true end
  local spm = DB.spm and DB.spm[key]
  if spm and #c == 0 then
    for map, pts in pairs(spm) do
      for j = 1, #pts - 1, 2 do
        if #c >= MAX_POINTS then break end
        local mx, my = pts[j] / 1000, pts[j + 1] / 1000
        local inst, x, y = D:WorldPos(map, mx, my)
        if inst then c[#c + 1] = { i = inst, x = x, y = y, m = map, mx = mx, my = my } end
      end
    end
  end
  if #c == 0 then
    for area in pairs(inDungeon) do
      for _, p in ipairs(D:Entrance(area)) do c[#c + 1] = p end
    end
  end
  if removedList(key) then
    local keep = {}
    for _, p in ipairs(c) do if not D:IsRemoved(key, p) then keep[#keep + 1] = p end end
    c = keep
  end
  pointCache[key] = c
  return c
end

-- quest objective spots players recorded (ForeverDB qsp + this account's own recordings)
function D:QuestSpots(qid)
  local key = "s" .. qid
  if pointCache[key] then return pointCache[key] end
  local c = {}
  local function add(maps)
    for map, pts in pairs(maps or {}) do
      for j = 1, #pts - 1, 2 do
        if #c >= MAX_POINTS then break end
        local mx, my = pts[j] / 1000, pts[j + 1] / 1000
        local inst, x, y = D:WorldPos(tonumber(map) or map, mx, my)
        if inst then c[#c + 1] = { i = inst, x = x, y = y, m = tonumber(map) or map, mx = mx, my = my, key = "q" .. qid } end
      end
    end
  end
  add(DB.qsp and DB.qsp[qid])
  add(QuesticusCollect and QuesticusCollect.qsp and QuesticusCollect.qsp[qid])
  pointCache[key] = c
  return c
end

-- ------------------------------------------------------------------ patrols
-- A mob that walks a path (Ghostmaw) is drawn as its path, not as a cloud of icons. The path comes
-- from your own recording (/qc patrol), ForeverDB's ptl (everyone's recordings), or - for a rare /
-- elite with many spots spread out like a trail - the spots joined in walking order.
local patrolCache = {}
function D:ForgetPatrol(key) patrolCache[key] = nil end
local function mapPath(maps)
  for map, pts in pairs(maps or {}) do
    local out = {}
    for j = 1, #pts - 1, 2 do
      local inst, x, y = D:WorldPos(tonumber(map) or map, pts[j] / 1000, pts[j + 1] / 1000)
      if inst then out[#out + 1] = { i = inst, x = x, y = y, m = tonumber(map) or map, mx = pts[j] / 1000, my = pts[j + 1] / 1000 } end
    end
    if #out >= 3 then return out end
  end
end
function D:Patrol(key)
  if type(key) ~= "string" or key:sub(1, 1) ~= "c" then return nil end
  local c = patrolCache[key]
  if c ~= nil then return c or nil end
  local own = QuesticusCollect and QuesticusCollect.patrol and QuesticusCollect.patrol["c:" .. key:sub(2)]
  c = (own and mapPath(own)) or (DB.ptl and DB.ptl[key] and mapPath(DB.ptl[key]))
  if not c then
    local n = D:NPC(tonumber(key:sub(2)))
    local pts = D:Points(key)
    -- rare / elite (rank 1+) with lots of spots spread like a trail: join them up
    if n and (n[5] or 0) >= 1 and #pts >= 8 and not pts[1].dungeon then
      local maxd = 0
      for _, p in ipairs(pts) do maxd = math.max(maxd, D.Dist(p, pts[1])) end
      if maxd > 150 and maxd < 3000 then
        -- start at one end (the spot farthest from the middle) and always step to the nearest left
        local cx, cy = 0, 0
        for _, p in ipairs(pts) do cx, cy = cx + p.x, cy + p.y end
        cx, cy = cx / #pts, cy / #pts
        local start, sd = 1, -1
        for i, p in ipairs(pts) do
          local d = (p.x - cx) ^ 2 + (p.y - cy) ^ 2
          if d > sd then start, sd = i, d end
        end
        local used, path, cur = { [start] = true }, { pts[start] }, pts[start]
        for _ = 2, #pts do
          local bi, bd
          for i, p in ipairs(pts) do
            if not used[i] then
              local d = (p.x - cur.x) ^ 2 + (p.y - cur.y) ^ 2
              if not bd or d < bd then bi, bd = i, d end
            end
          end
          if not bi then break end
          used[bi] = true
          cur = pts[bi]
          path[#path + 1] = cur
        end
        c = path
      end
    end
  end
  patrolCache[key] = c or false
  return c
end

-- what players looted for a quest (ForeverDB qsrc + own recordings): list of "c123" / "o45"
function D:QuestSources(qid)
  local out, seen = {}, {}
  for _, k in ipairs(DB.qsrc and DB.qsrc[qid] or {}) do if not seen[k] then seen[k] = true; out[#out + 1] = k end end
  local own = QuesticusCollect and QuesticusCollect.qsrc and QuesticusCollect.qsrc[qid]
  for k, n in pairs(own or {}) do
    k = k:gsub(":", "")
    -- (twice at least: one kill that happened to come before some progress isn't a source)
    if n >= 2 and not seen[k] then seen[k] = true; out[#out + 1] = k end
  end
  return out
end

-- npc ids by (lower-case) name, for quest texts like "WANTED: Old Rot-Chum" or "X's Head"
local byName
local byNameOf
function D:NPCByName(name)
  if not name or name == "" then return end
  -- (built once the database is loaded: asked earlier, an empty index stayed empty for the session)
  if not byName or byNameOf ~= DB.npc then
    if not (DB.npc and next(DB.npc)) then return end
    byName, byNameOf = {}, DB.npc
    for id, n in pairs(DB.npc) do
      local k = n[1] and n[1]:lower()
      if k then byName[k] = byName[k] or {}; table.insert(byName[k], id) end
    end
  end
  return byName[name:lower()]
end

-- forget cached points for a quest after new recordings
function D:Forget(qid) pointCache["s" .. qid] = nil end

-- exploration spots of a quest (qx[16]: {[uiMap] = {x, y, ...}})
function D:TriggerPoints(qid)
  local x = D:QuestExtra(qid)
  local spots = x and x[16]
  if not spots then return {} end
  local key = "t" .. qid
  if pointCache[key] then return pointCache[key] end
  local c = {}
  for map, pts in pairs(spots) do
    for j = 1, #pts - 1, 2 do
      local mx, my = pts[j] / 1000, pts[j + 1] / 1000
      local inst, wx, wy = D:WorldPos(tonumber(map) or map, mx, my)
      if inst then c[#c + 1] = { i = inst, x = wx, y = wy, m = tonumber(map) or map, mx = mx, my = my } end
    end
  end
  pointCache[key] = c
  return c
end

-- the game's own waypoint for a quest in your log (modern quest API), as a point
function D:QuestWaypoint(qid)
  if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return end
  local ok, map, x, y = pcall(C_QuestLog.GetNextWaypoint, qid)
  if not ok or not map or not x then return end
  local i, wx, wy = D:WorldPos(map, x, y)
  if i then return { i = i, x = wx, y = wy, m = map, mx = x, my = y, key = "q" .. qid } end
end

-- the player's world position
function D:PlayerPos()
  local x, y, _, inst = UnitPosition("player")
  if x then return { i = inst, x = x, y = y } end
  -- in places where UnitPosition is not allowed, fall back to the map position
  if C_Map and C_Map.GetBestMapForUnit then
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
      local mx, my = getXY(pos)
      local i, wx, wy = D:WorldPos(map, mx, my)
      if i then return { i = i, x = wx, y = wy, m = map, mx = mx, my = my } end
    end
  end
end

-- distance in yards; different continents count as very far
D.FAR = 20000
-- hostile elite mobs (elite, rare elite, boss) by map grid, for "solo only" routing
local eliteGrid
local CELL = 100
local function eliteIndex()
  if eliteGrid then return eliteGrid end
  eliteGrid = {}
  for nid, n in pairs(DB.npc or {}) do
    local rank = n[5] or 0
    -- elite / boss (rare elites wander alone and rarely spawn: not a camp); friendly guards have a faction
    if (rank == 1 or rank == 3) and not D:Faction(nid) then
      local lvl = n[4] or n[3] or 0
      for _, p in ipairs(D:Points("c" .. nid)) do
        if not p.dungeon then
          local k = p.i .. ":" .. math.floor(p.x / CELL) .. ":" .. math.floor(p.y / CELL)
          local t = eliteGrid[k]
          if not t then t = {}; eliteGrid[k] = t end
          t[#t + 1] = { x = p.x, y = p.y, lvl = lvl, nid = nid }
        end
      end
    end
  end
  return eliteGrid
end
-- the first hostile elite of at least minLevel within r yards of pt: npc id, level
function D:EliteNear(pt, r, minLevel)
  if not (pt and pt.x) then return end
  local g = eliteIndex()
  local cx, cy = math.floor(pt.x / CELL), math.floor(pt.y / CELL)
  local reach = math.ceil(r / CELL)
  for ix = cx - reach, cx + reach do
    for iy = cy - reach, cy + reach do
      for _, e in ipairs(g[pt.i .. ":" .. ix .. ":" .. iy] or {}) do
        if e.lvl >= (minLevel or 0) then
          local dx, dy = e.x - pt.x, e.y - pt.y
          if dx * dx + dy * dy <= r * r then return e.nid, e.lvl end
        end
      end
    end
  end
end

function D.Dist(a, b)
  if not a or not b then return D.FAR end
  if a.i ~= b.i then return D.FAR end
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

function D.Nearest(from, pts)
  local best, bd
  for _, p in ipairs(pts) do
    local d = D.Dist(from, p)
    if not bd or d < bd then best, bd = p, d end
  end
  return best, bd or D.FAR
end

-- densest group of points (objective area): returns centre point, radius, members
-- `anchor` (the quest giver) keeps the area local: a dense spot far away scores less than a
-- decent one nearby, so a wolf pelt quest uses the wolves next to the quest giver.
function D.Cluster(pts, radius, anchor)
  radius = radius or 180
  if #pts == 0 then return nil end
  if #pts == 1 then return pts[1], 0, pts end
  local bestN, bestP
  local step = math.max(1, math.floor(#pts / 60))
  for a = 1, #pts, step do
    local n = 0
    for b = 1, #pts do if D.Dist(pts[a], pts[b]) <= radius then n = n + 1 end end
    if anchor then n = n / (1 + D.Dist(pts[a], anchor) / 400) end
    if not bestN or n > bestN then bestN, bestP = n, pts[a] end
  end
  local sx, sy, n, mem = 0, 0, 0, {}
  for _, p in ipairs(pts) do
    if D.Dist(bestP, p) <= radius then sx, sy, n = sx + p.x, sy + p.y, n + 1; mem[#mem + 1] = p end
  end
  local centre = { i = bestP.i, x = sx / n, y = sy / n }
  -- snap to the member nearest the centre so the target is a real spawn spot
  local snap = D.Nearest(centre, mem)
  local r = 0
  for _, p in ipairs(mem) do r = math.max(r, D.Dist(snap, p)) end
  return snap, r, mem
end

-- ------------------------------------------------------------------ zone borders (ForeverDB zbord / agrid / abord)
-- ForeverDB has every zone's (and sub-zone's) outline from the WoW Forever client's own terrain: which
-- zone each 33-yard map chunk belongs to. Zone borders are mostly mountains, walls and sea; the pathing
-- and the route's travel times use them (Nav.lua, Planner.lua). Lookups work one chunk row at a time:
-- the row's zones as y intervals, from ForeverDBFull's agrid when another addon loaded it, else worked out
-- from the zbord outlines (a scan line through the polygons). Zone 0 = no zone (open sea, off the map).
local GO, GC = 17066.67, 33.333          -- agrid origin / chunk size (the same for every continent)
local rows, rowsN = {}, 0                -- [kind .. inst] = { [row] = { ylo, yhi, zone, ... } }
local polys = {}                         -- [kind .. inst] = { { id, minx, maxx, loops }, ... }
local ROWS_MAX = 2500
local function polyList(kind, inst)
  local key = kind .. inst
  local l = polys[key]
  if l then return l end
  l = {}
  polys[key] = l
  local src = kind == "z" and DB and DB.zbord or (_G.ForeverDBFull and _G.ForeverDBFull.abord)
  -- zone outlines redrawn by hand (the author's dev tools: QuesticusCollect.zbord, sent to ForeverDB) win
  local over = kind == "z" and QuesticusCollect and type(QuesticusCollect.zbord) == "table" and QuesticusCollect.zbord
  local merged = src or {}
  if over and next(over) then
    merged = {}
    for id, e in pairs(src or {}) do merged[id] = e end
    for id, e in pairs(over) do if type(e) == "table" and e.w then merged[tonumber(id) or id] = e end end
  end
  for id, e in pairs(merged) do
    if e.c == inst and e.w then
      local minx, maxx = math.huge, -math.huge
      for _, loop in ipairs(e.w) do
        for j = 1, #loop - 1, 2 do
          local x = loop[j]
          if x < minx then minx = x end
          if x > maxx then maxx = x end
        end
      end
      l[#l + 1] = { id, minx, maxx, e.w }
    end
  end
  return l
end
D._polyList = polyList
-- zones along the line x = xr: even-odd fill of each zone's loops -> y intervals
local function scanRow(list, xr)
  local out, ys = {}, {}
  for _, z in ipairs(list) do
    if xr >= z[2] and xr <= z[3] then
      local n = 0
      for _, loop in ipairs(z[4]) do
        local m = #loop
        local px, py = loop[m - 1], loop[m]
        for j = 1, m - 1, 2 do
          local x, y = loop[j], loop[j + 1]
          if (px <= xr) ~= (x <= xr) then
            n = n + 1
            ys[n] = py + (xr - px) * (y - py) / (x - px)
          end
          px, py = x, y
        end
      end
      if n > 1 then
        for j = n + 1, #ys do ys[j] = nil end
        table.sort(ys)
        for j = 1, n - 1, 2 do
          local o = #out
          out[o + 1], out[o + 2], out[o + 3] = ys[j], ys[j + 1], z[1]
        end
      end
    end
  end
  return out
end
-- agrid row string "zone*count,..." (columns from y = o downwards) -> y intervals
local function gridRow(s, o, c)
  local out, col = {}, 0
  for z, n in s:gmatch("(%d+)%*(%d+)") do
    z, n = tonumber(z), tonumber(n)
    if z ~= 0 then
      local o2 = #out
      out[o2 + 1], out[o2 + 2], out[o2 + 3] = o - (col + n) * c, o - col * c, z
    end
    col = col + n
  end
  return out
end
-- outlines redrawn by hand on this continent: the chunk grid (agrid) doesn't know them, use the outlines
local function edited(inst)
  if DB and DB.zbordEd and DB.zbordEd[inst] then return true end
  for _, e in pairs(QuesticusCollect and type(QuesticusCollect.zbord) == "table" and QuesticusCollect.zbord or {}) do
    if type(e) == "table" and e.c == inst then return true end
  end
  return false
end
local function rowOf(kind, inst, x)
  local g = kind == "z" and _G.ForeverDBFull and _G.ForeverDBFull.agrid and _G.ForeverDBFull.agrid[inst]
  if g and edited(inst) then g = nil end
  local o, c = (g and g.o) or GO, (g and g.c) or GC
  local r = math.floor((o - x) / c)
  local key = kind .. inst
  local t = rows[key]
  if not t then t = {}; rows[key] = t end
  local row = t[r]
  if row then return row end
  if rowsN >= ROWS_MAX then wipe(rows); rowsN = 0; t = {}; rows[key] = t end
  local s = g and g.z and g.z[r]
  if s then row = gridRow(s, o, c)
  else row = scanRow(polyList(kind, inst), o - (r + 0.5) * c) end
  t[r] = row
  rowsN = rowsN + 1
  return row
end
local function lookup(kind, i, x, y)
  if not (i and x and y) then return nil end
  local row = rowOf(kind, i, x)
  for j = 1, #row - 2, 3 do
    if y >= row[j] and y < row[j + 1] then return row[j + 2] end
  end
  return 0
end
-- does ForeverDB know this continent's zones?
local hasZones = {}
function D:HasBorders(i)
  if not DB or not DB.zbord or not i then return false end
  local h = hasZones[i]
  if h == nil then h = #polyList("z", i) > 0; hasZones[i] = h end
  return h
end
-- zone (areaID) at a world point: 0 = in no zone (sea, off the map), nil = no border data here
function D:ZoneAt(i, x, y)
  if not D:HasBorders(i) then return nil end
  return lookup("z", i, x, y)
end
-- sub-zone (town, camp, ...) at a world point: needs ForeverDBFull (abord), else nil
function D:SubZoneAt(i, x, y)
  if not (i and _G.ForeverDBFull and _G.ForeverDBFull.abord) then return nil end
  local z = lookup("a", i, x, y)
  return z ~= 0 and z or nil
end
function D:ForgetBorders() wipe(rows); rowsN = 0; wipe(polys); wipe(hasZones); if D.ForgetWalk then D.ForgetWalk() end end

-- zone border crossings: where people really walked from one zone into the next (Nav.lua records yours,
-- QuesticusCollect.zcross; ForeverDB zcross has everyone's; the author's dev tools add and remove them:
-- QuesticusCollect.zcrossDel). [continent][lowZone .. "-" .. highZone] = { x, y, ... }
local function pairKey(a, b) if a > b then a, b = b, a end return a .. "-" .. b end
D.ZonePair = pairKey
local DEL_NEAR = 40
local function deleted(i, k, x, y)
  local del = QuesticusCollect and type(QuesticusCollect.zcrossDel) == "table" and QuesticusCollect.zcrossDel[i]
  local l = del and del[k]
  for j = 1, #(l or {}) - 1, 2 do
    if (l[j] - x) ^ 2 + (l[j + 1] - y) ^ 2 <= DEL_NEAR * DEL_NEAR then return true end
  end
  local dbd = DB and DB.zcrossDel and DB.zcrossDel[i] and DB.zcrossDel[i][k]
  for j = 1, #(dbd or {}) - 1, 2 do
    if (dbd[j] - x) ^ 2 + (dbd[j + 1] - y) ^ 2 <= DEL_NEAR * DEL_NEAR then return true end
  end
  return false
end
-- every crossing of a continent: { x, y, a, b, own } (yours first, then ForeverDB's not near one of
-- yours, minus deleted ones). Rebuilt when D.crossVer changes.
local crossCache = {}
D.crossVer = 0
function D:CrossList(i)
  local c = crossCache[i]
  if c and c.v == D.crossVer then return c end
  c = { v = D.crossVer }
  crossCache[i] = c
  local function add(t, own)
    for k, l in pairs(t or {}) do
      local za, zb = tostring(k):match("^(%d+)%-(%d+)$")
      za, zb = tonumber(za), tonumber(zb)
      if za and type(l) == "table" then
        for j = 1, #l - 1, 2 do
          local x, y = l[j], l[j + 1]
          if not deleted(i, k, x, y) then
            local dup
            for _, q in ipairs(c) do
              if q.a == za and q.b == zb and (q.x - x) ^ 2 + (q.y - y) ^ 2 < 900 then dup = true; break end
            end
            if not dup then c[#c + 1] = { x = x, y = y, a = za, b = zb, own = own } end
          end
        end
      end
    end
  end
  add(QuesticusCollect and QuesticusCollect.zcross and QuesticusCollect.zcross[i], true)
  add(DB and DB.zcross and DB.zcross[i], false)
  c.dist = {}                        -- [from node] = { [node] = walking yards through crossings }
  c.prev = {}                        -- [from node] = { [node] = the node before it on that walk }
  return c
end
-- the author's dev tools: add / remove a crossing, save / drop a zone's outline (all sent to ForeverDB)
function D:AddCrossing(i, za, zb, x, y)
  QuesticusCollect.zcross = QuesticusCollect.zcross or {}
  local ci = QuesticusCollect.zcross[i] or {}
  QuesticusCollect.zcross[i] = ci
  local k = pairKey(za, zb)
  local l = ci[k] or {}
  ci[k] = l
  l[#l + 1] = math.floor(x + 0.5); l[#l + 1] = math.floor(y + 0.5)
  -- (a crossing put back where one was removed: not removed any more)
  local del = type(QuesticusCollect.zcrossDel) == "table" and QuesticusCollect.zcrossDel[i] and QuesticusCollect.zcrossDel[i][k]
  if del then
    for j = #del - 1, 1, -2 do
      if (del[j] - x) ^ 2 + (del[j + 1] - y) ^ 2 <= DEL_NEAR * DEL_NEAR then table.remove(del, j + 1); table.remove(del, j) end
    end
  end
  D:CrossingsChanged()
end
function D:RemoveCrossing(i, za, zb, x, y)
  local k = pairKey(za, zb)
  local own = QuesticusCollect.zcross and QuesticusCollect.zcross[i] and QuesticusCollect.zcross[i][k]
  if own then
    for j = #own - 1, 1, -2 do
      if (own[j] - x) ^ 2 + (own[j + 1] - y) ^ 2 <= 25 then table.remove(own, j + 1); table.remove(own, j) end
    end
  end
  QuesticusCollect.zcrossDel = type(QuesticusCollect.zcrossDel) == "table" and QuesticusCollect.zcrossDel or {}
  local di = QuesticusCollect.zcrossDel[i] or {}
  QuesticusCollect.zcrossDel[i] = di
  local l = di[k] or {}
  di[k] = l
  l[#l + 1] = math.floor(x + 0.5); l[#l + 1] = math.floor(y + 0.5)
  D:CrossingsChanged()
end
function D:SetZoneOutline(zone, inst, loops)
  QuesticusCollect.zbord = type(QuesticusCollect.zbord) == "table" and QuesticusCollect.zbord or {}
  if loops then QuesticusCollect.zbord[zone] = { c = inst, w = loops, t = time and time() or 0 }
  else QuesticusCollect.zbord[zone] = nil end
  D:ForgetBorders()
  D:CrossingsChanged()
  if Q.Nav then Q.Nav:Forget() end
end
-- a zone's outline as the database has it (or yours)
function D:ZoneOutline(zone)
  local o = QuesticusCollect and type(QuesticusCollect.zbord) == "table" and QuesticusCollect.zbord[zone]
  if type(o) == "table" and o.w then return o end
  return DB and DB.zbord and DB.zbord[zone]
end
function D:CrossingsChanged()
  D.crossVer = D.crossVer + 1
  wipe(crossCache)
  D.ForgetWalk()
  if D.ForgetBorderMemo then D.ForgetBorderMemo() end
end
-- the crossings between two zones as a flat { x, y, ... } list (and nil: kept for older callers)
function D:Crossings(i, za, zb)
  local out = {}
  for _, q in ipairs(D:CrossList(i)) do
    if (q.a == za and q.b == zb) or (q.a == zb and q.b == za) then out[#out + 1] = q.x; out[#out + 1] = q.y end
  end
  return out, nil
end
local function bestCrossing(list, ax, ay, bx, by, best, bd)
  for j = 1, #(list or {}) - 1, 2 do
    local cx, cy = list[j], list[j + 1]
    local d = math.sqrt((ax - cx) ^ 2 + (ay - cy) ^ 2) + math.sqrt((bx - cx) ^ 2 + (by - cy) ^ 2)
    if not bd or d < bd then best, bd = j, d; D._cx, D._cy = cx, cy end
  end
  return best, bd
end

-- ------------------------------------------------------------------ walking between zones
-- The crossings make a network: from one crossing you can walk to any other crossing of the zones it
-- joins. A walk from a to b in another zone goes a -> crossings -> b; the shortest one (Dijkstra) is the
-- real distance when the zones only meet through mountains - not the straight line over them.
-- nil when the network doesn't reach (not enough crossings known yet).
local function inZone(q, z) return q.a == z or q.b == z end
local function fromNode(c, s)
  local d = c.dist[s]
  if d then return d, c.prev[s] end
  d = {}
  c.dist[s] = d
  local pv = {}
  c.prev = c.prev or {}
  c.prev[s] = pv
  local n = #c
  local done = {}
  d[s] = 0
  for _ = 1, n do
    local u, ud
    for k = 1, n do
      if not done[k] and d[k] and (not ud or d[k] < ud) then u, ud = k, d[k] end
    end
    if not u then break end
    done[u] = true
    local qu = c[u]
    for k = 1, n do
      if not done[k] then
        local qk = c[k]
        if inZone(qk, qu.a) or inZone(qk, qu.b) then
          local nd = ud + math.sqrt((qu.x - qk.x) ^ 2 + (qu.y - qk.y) ^ 2)
          if not d[k] or nd < d[k] then d[k] = nd; pv[k] = u end
        end
      end
    end
  end
  return d, pv
end
local walkMemo2, walkN = {}, 0
function D.ForgetWalk() wipe(walkMemo2); walkN = 0 end
-- walking yards from a to b through the crossings, and the first crossing on the way (nil: unknown)
function D.ZoneWalk(a, b)
  if not (a and b) or a.i ~= b.i or not D:HasBorders(a.i) then return nil end
  local za, zb = D:ZoneAt(a.i, a.x, a.y), D:ZoneAt(b.i, b.x, b.y)
  if not za or za == 0 or not zb or zb == 0 or za == zb then return nil end
  local f = math.floor
  local key = (((a.i * 1000 + f(a.x / 50) + 500) * 1000 + f(a.y / 50) + 500) * 1000 + f(b.x / 50) + 500) * 1000 + f(b.y / 50) + 500
  local m = walkMemo2[key]
  if m ~= nil then if m then return m[1], m[2], m[3] end return nil end
  local c = D:CrossList(a.i)
  local best, first, bs, bt
  for s = 1, #c do
    local qs = c[s]
    if inZone(qs, za) then
      local ds = math.sqrt((a.x - qs.x) ^ 2 + (a.y - qs.y) ^ 2)
      if not best or ds < best then
        local d = fromNode(c, s)
        for t = 1, #c do
          local qt = c[t]
          if d[t] and inZone(qt, zb) then
            local total = ds + d[t] + math.sqrt((b.x - qt.x) ^ 2 + (b.y - qt.y) ^ 2)
            if not best or total < best then best, first, bs, bt = total, qs, s, t end
          end
        end
      end
    end
  end
  local path
  if best then
    -- the crossings on the way, in order
    local _, pv = fromNode(c, bs)
    local rev, k = {}, bt
    while k do
      rev[#rev + 1] = { i = a.i, x = c[k].x, y = c[k].y }
      if k == bs then break end
      k = pv[k]
    end
    path = {}
    for j = #rev, 1, -1 do path[#path + 1] = rev[j] end
  end
  if walkN >= 5000 then wipe(walkMemo2); walkN = 0 end
  walkMemo2[key] = best and { best, path[1], path } or false
  walkN = walkN + 1
  if best then return best, path[1], path end
end
-- the crossings to walk through from a to b (in order), nil when they're in one zone / unknown
function D.ZoneWalkPath(a, b)
  local key
  local w, first, path = D.ZoneWalk(a, b)
  return w and path or nil
end

-- the straight line from a to b against the zone borders: how many borders it crosses, how much of it
-- runs through no zone (sea), and the extra yards a walk round them is likely to need (through the
-- crossings network where it reaches, else a typical detour per border). Remembered (points to 50 yards).
local BORDER_EXTRA = 140        -- yards: going round to a border's pass nobody recorded yet
local VOID_EXTRA = 0.7          -- a stretch over open sea / off the map costs this much more again
local memo, memoN = {}, 0
D.ForgetBorderMemo = function() wipe(memo); memoN = 0 end
function D.BorderExtra(a, b)
  if not (a and b) or a.i ~= b.i or not D:HasBorders(a.i) then return 0, 0, 0 end
  local s = D.Dist(a, b)
  if s < 60 then return 0, 0, 0 end
  local f = math.floor                -- (a number key: 50-yard cells of both ends; continents up to 9000)
  local key = (((a.i * 1000 + f(a.x / 50) + 500) * 1000 + f(a.y / 50) + 500) * 1000 + f(b.x / 50) + 500) * 1000 + f(b.y / 50) + 500
  local e = memo[key]
  if e then return e[1], e[2], e[3] end
  local n = math.min(80, math.max(2, math.floor(s / 50)))
  local dx, dy = (b.x - a.x) / n, (b.y - a.y) / n
  local prev = D:ZoneAt(a.i, a.x, a.y)
  local lastZone, lastX, lastY = prev ~= 0 and prev or nil, a.x, a.y
  local borders, void, extra = 0, 0, 0
  for k = 1, n do
    local x, y = a.x + dx * k, a.y + dy * k
    local z = D:ZoneAt(a.i, x, y)
    if z == 0 then void = void + s / n
    elseif z ~= lastZone then
      if lastZone then
        borders = borders + 1
        local own = D:Crossings(a.i, lastZone, z)
        local j, bd = bestCrossing(own, lastX, lastY, x, y)
        local straight = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2)
        extra = extra + (bd and math.min(BORDER_EXTRA * 3, bd - straight) or BORDER_EXTRA)
      end
      lastZone = z
    end
    if z ~= 0 then lastX, lastY = x, y end
  end
  extra = extra + void * VOID_EXTRA
  -- the crossings network knows the real way round (it may go through a third zone)
  local zw = borders > 0 and D.ZoneWalk(a, b)
  if zw then extra = math.max(extra, zw - s) end
  extra = math.min(s * 3, extra)
  if memoN >= 5000 then wipe(memo); memoN = 0 end
  memo[key] = { extra, borders, void }
  memoN = memoN + 1
  return extra, borders, void
end

-- a far target in another zone: the crossing to walk through first (nil: none known / not worth it)
function D:BorderVia(from, to)
  if not (from and to) or from.i ~= to.i or not D:HasBorders(from.i) then return nil end
  local zw, first = D.ZoneWalk(from, to)
  if not zw or zw > D.Dist(from, to) * 3 then return nil end
  return first
end
