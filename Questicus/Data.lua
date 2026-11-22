-- Questicus data layer: reads the shared ForeverDB addon (LoadOnDemand) and turns its spawn data
-- into points with world coordinates (yards, for routing) and map positions (for pins).
local Q = Questicus
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
    Q:Print("ForeverDB is missing - install it (CurseForge: ForeverDB). Questicus needs it for quest data.")
    return false
  end
  if not (DB.qx and DB.nfac and DB.qe) then
    Q:Print("Your ForeverDB is too old for Questicus (it has no quest details). Update ForeverDB on CurseForge.")
    D.old = true
    return false
  end
  D.db = DB
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
  D.flightMasters = {}           -- npc ids whose title is Flight Master
  for id, n in pairs(DB.npc or {}) do
    if n[2] == "Flight Master" then D.flightMasters[#D.flightMasters + 1] = id end
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

function D:Name(key)
  if key:sub(1, 4) == "taxi" then
    local n = Q.Flight and Q.Flight:Node(tonumber(key:sub(5)))
    return n and (n.name .. " (flight master)") or "Flight master"
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
function D.WalkDist(a, b)
  local s = D.Dist(a, b)
  if not (a and b) or a.i ~= b.i or s < 150 then return s end
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
  Q:Print(("removed a spot of %s - gone from your map and routes, and from ForeverDB once your recordings are synced (/qc spots undo puts it back)"):format(D:Name(key)))
  if Q.Planner then Q.Planner:Reset(); Q.Planner:Replan(0.2) end
  if Q.Pins and Q.Pins.RefreshWorld then Q.Pins:RefreshWorld(true) end
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
    Q:Print(key and ("put back a spot of " .. D:Name(key)) or "nothing to undo")
    return
  elseif arg == "reset" then
    if QuesticusCollect then QuesticusCollect.removed = nil end
    wipe(pointCache)
    if Q.Planner then Q.Planner:Reset(); Q.Planner:Replan(0.2) end
    Q:Print("all removed spots are back")
    return
  end
  local n = 0
  for k, list in pairs(r) do n = n + #list; Q:Print(("%s: %d spot(s) removed"):format(D:Name(k), #list)) end
  if n == 0 then Q:Print("no spots removed - Ctrl-click a wrong map or minimap icon to remove it") end
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
