-- Questicus flight paths: the route flies when it's faster than running.
-- Flight masters and flight times come from ForeverDB (spf.TaxiNodes / spf.TaxiPaths from Shortest
-- Path Forever, plus the client's taxi table). Which ones this character knows is read every time
-- a flight map opens. Unknown flight masters of your faction close to the route become a "get the
-- flight path" step. With auto fly on, talking to the flight master of a fly step takes the flight.
local Q = Questicus
local D = Q.Data
local F = {}
Q.Flight = F

F.version = 0
local nodes, byId, byName, paths

-- ------------------------------------------------------------------ data
local function load()
  if nodes then return nodes end
  nodes, byId, byName, paths = {}, {}, {}, {}
  local db = D.db or {}
  local spf = db.spf or {}
  local function add(id, name, inst, x, y, faction)
    if not (id and name and inst and x and y) then return end
    -- leftovers in the client data ("zzOLD...", test nodes) aren't real flight masters
    local low = name:lower()
    if low:find("^zz") or low:find("test") or low:find("programmer") or low:find("%[dnt%]") then return end
    local n = byId[id]
    if not n then
      n = { id = id, name = name, i = inst, x = x, y = y, key = "taxi" .. id }
      byId[id] = n
      nodes[#nodes + 1] = n
      byName[name:lower()] = n
      local short = name:match("^(.-),") -- "Crossroads, The Barrens" -> "crossroads"
      if short then byName[short:lower()] = byName[short:lower()] or n end
    end
    if faction and faction ~= "" and faction ~= "?" then n.faction = faction end
  end
  for id, t in pairs(spf.TaxiNodes or {}) do add(tonumber(id), t.name, t.map, t.x, t.y, t.faction) end
  -- client table: {name, continent, x, y, z, flags, Horde mount, Alliance mount}. Flags 1 = on the
  -- Alliance flight map, 2 = on the Horde map: a node on neither isn't a flight master you can use
  -- (Powderfuse Port 3274 / 3275 in Riverglades)
  for id, t in pairs(db.taxi or {}) do
    local fl = t[6] or 0
    local fa, fh = fl % 2 == 1, math.floor(fl / 2) % 2 == 1
    if (fa or fh) and not (spf.TaxiNodes and spf.TaxiNodes[id]) then
      add(id, t[1], t[2], t[3], t[4], (fa and fh) and "Neutral" or (fh and "Horde" or "Alliance"))
    end
  end
  for _, p in pairs(spf.TaxiPaths or {}) do
    local a, b = tonumber(p.from), tonumber(p.to)
    if a and b and p.seconds then
      paths[a] = paths[a] or {}
      paths[a][b] = p.seconds
    end
  end
  -- flights you took yourself, timed (QuesticusCollect.ftime, below): the real time beats the table's
  for k, e in pairs(QuesticusCollect and QuesticusCollect.ftime or {}) do
    local a, b = tostring(k):match("^(%d+)>(%d+)$")
    a, b = tonumber(a), tonumber(b)
    if a and b and type(e) == "table" and tonumber(e.s) then
      paths[a] = paths[a] or {}
      paths[a][b] = tonumber(e.s)
    end
  end
  return nodes
end
function F:Node(id) load(); return byId[id] end
function F:Nodes() return load() end

local FULL = { H = "Horde", A = "Alliance" }
local function mine(n)
  local f = n.faction
  local pf = Q.player.faction
  return not f or f == "Neutral" or f == pf or f == FULL[pf]
end

-- ------------------------------------------------------------------ what you know
local function known() Q.char.taxi = Q.char.taxi or {}; return Q.char.taxi end
function F:Known(id) return Q.char and known()[id] == true end
function F:SetKnown(id)
  if not id or known()[id] then return end
  known()[id] = true
  F.version = F.version + 1
  F.cache = {}
end

-- the flight map is open: note every flight master you can fly to (and the one you stand at)
function F:ReadTaxiMap()
  load()
  local seen = 0
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
    local map = (GetTaxiMapID and GetTaxiMapID()) or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, map)
    for _, t in ipairs(ok and list or {}) do
      local n = byId[t.nodeID] or (t.name and byName[t.name:lower()])
      -- Enum.FlightPathState: 0 current, 1 reachable, 2 unreachable
      if n and (t.state == 0 or t.state == 1) then F:SetKnown(n.id); seen = seen + 1 end
      if n then n.slot = t.slotIndex end
    end
  end
  if seen == 0 and NumTaxiNodes then
    for i = 1, NumTaxiNodes() do
      local name = TaxiNodeName(i)
      local n = name and (byName[name:lower()] or byName[(name:match("^(.-),") or name):lower()])
      local tp = TaxiNodeGetType and TaxiNodeGetType(i)
      if n and (tp == "CURRENT" or tp == "REACHABLE") then F:SetKnown(n.id); seen = seen + 1 end
      if n then n.slot = i end
    end
  end
  return seen
end

-- ------------------------------------------------------------------ flight times
-- shortest flight between two known flight masters (hops only through known ones); nil = can't
function F:FlyTime(a, b)
  if a == b then return 0 end
  F.cache = F.cache or {}
  local c = F.cache[a.id]
  if not c then
    load()
    c = { [a.id] = 0 }
    local open = { a.id }
    while #open > 0 do
      table.sort(open, function(x, y) return c[x] > c[y] end)
      local u = table.remove(open)
      for v, sec in pairs(paths[u] or {}) do
        if F:Known(v) then
          local d = c[u] + sec
          if not c[v] or d < c[v] then
            if not c[v] then open[#open + 1] = v end
            c[v] = d
          end
        end
      end
    end
    F.cache[a.id] = c
  end
  local t = c[b.id]
  if t then return t end
  -- no path data between them (WoW Forever's new flight masters): straight line at flight speed
  if a.i == b.i and not paths[a.id] and not paths[b.id] then return D.Dist(a, b) / 28 + 15 end
end

-- nearest known flight master of your faction on the same continent
function F:Nearest(p)
  if not (p and Q.char) then return end
  if p._fv == F.version then return p._fn or nil end
  local best, bd
  for _, n in ipairs(load()) do
    if n.i == p.i and F:Known(n.id) and mine(n) then
      local d = D.Dist(p, n)
      if not bd or d < bd then best, bd = n, d end
    end
  end
  p._fv, p._fn = F.version, best or false
  return best, bd
end

-- the few known flight masters closest to a point (the nearest isn't always the best start)
function F:NearestN(p, n)
  if not (p and Q.char) then return {} end
  if p._fnv == F.version and p._fnl then return p._fnl end
  local l = {}
  for _, x in ipairs(load()) do
    if x.i == p.i and F:Known(x.id) and mine(x) then l[#l + 1] = { x, D.Dist(p, x) } end
  end
  -- the closest few in a straight line, then by the real walk (a flight master over a cliff isn't close)
  table.sort(l, function(u, v) return u[2] < v[2] end)
  for k = 1, math.min(#l, 8) do l[k][2] = D.WalkDist(p, l[k][1]) end
  for k = #l, 9, -1 do l[k] = nil
  end
  table.sort(l, function(u, v) return u[2] < v[2] end)
  local out = {}
  for k = 1, math.min(n or 3, #l) do out[k] = l[k] end
  p._fnv, p._fnl = F.version, out
  return out
end

-- flying from a to b: { from, to, t } when it beats running (speed = yd/s on the ground).
-- Tries the 3 closest flight masters at each end; `eager` (dungeon mode) flies whenever it's any faster.
function F:Leg(a, b, speed, eager)
  if not (a and b) or a.i ~= b.i or Q.prefs.flights == false then return end
  if F.noFlyUntil and (GetTime and GetTime() or 0) < F.noFlyUntil then return end
  local walk = D.WalkDist(a, b) / speed
  if walk < (eager and 60 or 90) then return end
  local best
  for _, A in ipairs(F:NearestN(a, 3)) do
    for _, Bn in ipairs(F:NearestN(b, 3)) do
      local fa, fb = A[1], Bn[1]
      if fa ~= fb then
        local fly = F:FlyTime(fa, fb)
        if fly then
          local t = A[2] / speed + 20 + fly + Bn[2] / speed
          if not best or t < best.t then best = { from = fa, to = fb, t = t, walk = walk, fly = fly } end
        end
      end
    end
  end
  if best and best.t < walk - (eager and 5 or 30) then return best end
end

-- ------------------------------------------------------------------ boats and zeppelins
-- The ships between the continents (ForeverDB's spf.Docks has where they land; which goes where is
-- the classic network). t = typical wait + ride in seconds.
local RIDE = 230
F.ROUTES = {
  -- the Orgrimmar tower platforms (Durotar map spots, checked in game): Undercity 50.8, 13.7; Grom'gol 50.6, 12.7
  { id = "z-og-uc", kind = "zeppelin", faction = "H", a = { 1, 1360, -4632, "the zeppelin tower outside Orgrimmar (Durotar 50.8, 13.7)", map = 1411, mx = 0.508, my = 0.137 },
    b = { 0, 2062, 235, "the zeppelin tower in Tirisfal Glades (Undercity)" }, aName = "Orgrimmar", bName = "Undercity" },
  { id = "z-og-gg", kind = "zeppelin", faction = "H", a = { 1, 1318, -4658, "the zeppelin tower outside Orgrimmar (Durotar 50.6, 12.7)", map = 1411, mx = 0.506, my = 0.127 },
    b = { 0, -12407, 211, "the zeppelin tower at Grom'gol (Stranglethorn Vale)" }, aName = "Orgrimmar", bName = "Grom'gol" },
  { id = "b-bb-ra", kind = "boat", a = { 0, -14278, 582, "the docks of Booty Bay (Stranglethorn Vale)" },
    b = { 1, -1006, -3842, "the docks of Ratchet (The Barrens)" }, aName = "Booty Bay", bName = "Ratchet" },
  { id = "b-mh-th", kind = "boat", faction = "A", a = { 0, -3906, -586, "the docks of Menethil Harbor (Wetlands)" },
    b = { 1, -4017, -4741, "the docks of Theramore (Dustwallow Marsh)" }, aName = "Menethil Harbor", bName = "Theramore" },
  { id = "b-mh-au", kind = "boat", faction = "A", a = { 0, -3710, -576, "the docks of Menethil Harbor (Wetlands)" },
    b = { 1, 6594, 759, "the docks of Auberdine (Darkshore)" }, aName = "Menethil Harbor", bName = "Auberdine" },
}
local function dockPt(d, r)
  local p = { i = d[1], x = d[2], y = d[3], place = d[4], dock = r.id }
  -- a map spot checked in game wins over the database's dock position
  if d.map and D.WorldPos then
    local i, x, y = D:WorldPos(d.map, d.mx, d.my)
    if i then p.i, p.x, p.y = i, x, y end
  end
  return p
end
local function docks()
  if F.docksReady then return end
  F.docksReady = true
  for _, r in ipairs(F.ROUTES) do r.A, r.B = dockPt(r.a, r), dockPt(r.b, r) end
end
for _, r in ipairs(F.ROUTES) do r.A, r.B = dockPt(r.a, r), dockPt(r.b, r) end
Q:On("QC_READY", function() F.docksReady = nil; docks() end)
local function usable(r)
  local f = Q.player and Q.player.faction
  return not r.faction or not f or r.faction == f
end
-- getting from a to b on another continent: walk / fly to the best dock, take the ship, then on
-- from where it lands. { route, from, to, toName, t, ride } or nil
function F:Cross(a, b, speed, eager)
  if not (a and b) or a.i == b.i then return end
  local best
  -- the legs to and from the docks: one dock is reached from many places, so keep them per point
  local function leg(p, q)
    local key = (q.dock or ("r" .. tostring(p.dock))) .. (eager and "e" or "") .. speed
    if not q.dock then p, q = q, p end      -- keep the cache on the place, not on the dock
    p._dk = (p._dv == F.version) and p._dk or {}
    p._dv = F.version
    local v = p._dk[key]
    if v then return v end
    local walk = D.Dist(p, q) / speed
    local l = F:Leg(p, q, speed, eager)
    v = l and math.min(l.t, walk) or walk
    p._dk[key] = v
    return v
  end
  for _, r in ipairs(F.ROUTES) do
    if usable(r) then
      for _, dir in ipairs({ { r.A, r.B, r.bName }, { r.B, r.A, r.aName } }) do
        local from, to = dir[1], dir[2]
        if from.i == a.i and to.i == b.i then
          local t = leg(a, from) + RIDE + leg(to, b)
          if not best or t < best.t then best = { route = r, from = from, to = to, toName = dir[3], t = t, ride = RIDE } end
        end
      end
    end
  end
  return best
end

-- unknown flight masters of your faction near a point (for "get the flight path")
function F:Unknown(p, radius)
  local out = {}
  if not (p and Q.char) then return out end
  for _, n in ipairs(load()) do
    if n.i == p.i and not F:Known(n.id) and mine(n) and not (Q.char.noFP and Q.char.noFP[n.id]) then
      if D.Dist(p, n) <= radius then out[#out + 1] = n end
    end
  end
  return out
end

-- ------------------------------------------------------------------ in game
local flyingTo
function F:FlyingTo() return flyingTo end

-- Timing your flights: from the flight master you take off at to the one you land at, measured once
-- per route and kept in QuesticusCollect.ftime["from>to"] = { s = seconds, at = when } (sent with your
-- recordings for the shared database; off with "Help fill the database", like the rest). The route
-- uses it straight away instead of the table's time.
local takeoff
local function nearestNode(here, within)
  local n, d
  for _, x in ipairs(load()) do
    if x.i == here.i then local dd = D.Dist(here, x); if not d or dd < d then n, d = x, dd end end
  end
  if n and d <= within then return n end
end
local function noteTakeoff(dest)
  if not dest then return end
  local here = D:PlayerPos()
  local from = here and nearestNode(here, 80)
  if from and from.id ~= dest.id then takeoff = { from = from, to = dest, t = GetTime() } end
end
local function noteLanding()
  local f = takeoff
  takeoff = nil
  if not f or not QuesticusCollect or (Q.db and Q.db.collect == false) then return end
  local here = D:PlayerPos()
  local at = here and nearestNode(here, 150)
  if not at or at.id ~= f.to.id then return end             -- (landed somewhere else / got off early)
  local secs = math.floor(GetTime() - f.t + 0.5)
  if secs < 5 or secs > 1800 then return end
  QuesticusCollect.ftime = type(QuesticusCollect.ftime) == "table" and QuesticusCollect.ftime or {}
  local key = f.from.id .. ">" .. f.to.id
  if QuesticusCollect.ftime[key] then return end            -- (each route is timed once)
  QuesticusCollect.ftime[key] = { s = secs, at = time and time() or nil }
  load()
  paths[f.from.id] = paths[f.from.id] or {}
  paths[f.from.id][f.to.id] = secs
  F.cache = {}
  F.version = F.version + 1
  Q:Print(("flight %s -> %s took %d:%02d (recorded for the route)"):format(f.from.name, f.to.name, math.floor(secs / 60), secs % 60))
end
F.NoteLanding = noteLanding

Q:On("TAXIMAP_OPENED", function()
  F:ReadTaxiMap()
  -- you're talking to this flight master, so you know it (even if the map didn't name it)
  local here = D:PlayerPos()
  if here then
    local n, d
    for _, x in ipairs(load()) do
      if x.i == here.i then local dd = D.Dist(here, x); if not d or dd < d then n, d = x, dd end end
    end
    if n and d < 60 and not F:Known(n.id) then F:SetKnown(n.id) end
  end
  if Q.Planner then Q.Planner:Replan(0.2) end
  -- auto fly: the current step is a flight from here
  local s = Q.Planner and Q.Planner.steps and Q.Planner.steps[1]
  if s and s.type == "fly" and s.to and Q.prefs.autoFly ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) then
    local n = byId[s.to.id]
    if n and n.slot and TakeTaxiNode then
      Q.After(0.3, function()
        flyingTo = n
        noteTakeoff(n)
        pcall(TakeTaxiNode, n.slot)
        Q:Print("flying to " .. n.name)
      end)
    end
  end
end)
-- flights you start yourself: remember where to
if hooksecurefunc and TakeTaxiNode then
  hooksecurefunc("TakeTaxiNode", function(slot)
    for _, n in ipairs(load()) do if n.slot == slot then flyingTo = n end end
    if not takeoff or takeoff.to ~= flyingTo then noteTakeoff(flyingTo) end
    -- the flight step is done: plan from where it lands
    if Q.Planner then Q.Planner.taxiPlanned = nil; Q.Planner:Replan(1.2) end
  end)
end
local function landed()
  if flyingTo then pcall(noteLanding) end
  flyingTo = nil
  local P = Q.Planner
  if P then P.taxiPlanned, P.afterTaxi, P.wasTaxi = nil, nil, nil; P:Replan(0.5) end
  if Q.Pins then Q.After(0.3, function() Q.Pins:RefreshMinimap(true); Q.Pins:RefreshWorld(true) end) end
end
Q:On("PLAYER_CONTROL_GAINED", function()
  if flyingTo and not (UnitOnTaxi and UnitOnTaxi("player")) then landed() end
end)
-- landing, watched directly: PLAYER_CONTROL_GAINED can come while the game still says you're on the
-- flight, and then nothing replanned (the "fly" step stayed after you'd landed)
do
  local wasOn, acc = false, 0
  local w = CreateFrame("Frame")
  w:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.5 then return end
    acc = 0
    local on = Q.OnTaxi()
    if wasOn and not on then landed() end
    wasOn = on
  end)
end
-- "New flight path discovered!"
Q:On("UI_INFO_MESSAGE", function(_, msg)
  if type(msg) == "string" and not Q.Secret(msg) and msg:lower():find("flight path") then
    local here = D:PlayerPos()
    local n, d = nil, nil
    for _, x in ipairs(load()) do
      if here and x.i == here.i then
        local dd = D.Dist(here, x)
        if not d or dd < d then n, d = x, dd end
      end
    end
    if n and d < 80 then F:SetKnown(n.id); if Q.Planner then Q.Planner:Replan(0.5) end end
  end
end)

-- standing at a "get the flight path" spot for a while without learning one: nobody is there
local waited = {}
local watch = CreateFrame("Frame")
local acc2 = 0
watch:SetScript("OnUpdate", function(_, el)
  acc2 = acc2 + el
  if acc2 < 2 then return end
  local dt = acc2
  acc2 = 0
  local s = Q.Planner and Q.Planner.steps and Q.Planner.steps[1]
  if not (s and s.type == "fp" and s.node) or F:Known(s.node.id) then return end
  local here = D:PlayerPos()
  if not (here and here.i == s.node.i and D.Dist(here, s.node) <= 25) then return end
  waited[s.node.id] = (waited[s.node.id] or 0) + dt
  if waited[s.node.id] >= 30 then
    Q.char.noFP = Q.char.noFP or {}
    Q.char.noFP[s.node.id] = true
    if QuesticusCollect and Q.db.collect ~= false then
      QuesticusCollect.nofp = QuesticusCollect.nofp or {}
      QuesticusCollect.nofp[s.node.id] = true
    end
    Q:Print("no flight master at " .. s.node.name .. " - left out of routes from now on")
    if Q.Planner then Q.Planner:Replan(0.2) end
  end
end)

Q:Command("flights", "flight masters this character knows", function()
  local t = {}
  for id in pairs(known()) do local n = byId[id] or F:Node(id); t[#t + 1] = n and n.name or tostring(id) end
  table.sort(t)
  Q:Print(#t == 0 and "no flight paths known yet - open a flight master's map once" or (#t .. " known: " .. table.concat(t, ", ")))
end)
