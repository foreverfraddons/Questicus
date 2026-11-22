-- Questicus pathing: a less obstructed way to the target than a straight line.
-- Addons can't read the game's terrain, so Questicus builds its own walk map: every spot where an
-- NPC, a mob or an object stands (ForeverDB spawns) is ground you can stand on, and so is every
-- place you have walked (recorded as you play). A* over that grid prefers known ground and goes
-- around the empty gaps (water, cliffs, walls) where a straight line would run into them.
local Q = Questicus
local D = Q.Data
local N = {}
Q.Nav = N

local CELL = 40                 -- yards per grid cell
local UNKNOWN_COST = 2.2        -- crossing ground nobody has stood on costs this much more
local WALKED_COST = 0.7         -- ground YOU walked (QuesticusCollect.trail) costs less than ground only known
                                -- from spawns: routes follow your own roads, gates and ramps, and keep
                                -- learning as you play
local MAX_EXPAND = 7000
local MARGIN = 30               -- cells around start / goal the search may use
local OFF = 100000
local FAR = 2500                -- yards: no path search further than this
-- ForeverDB zone borders (Data.lua D:ZoneAt): ground nobody stood on is likelier a wall where it's a
-- zone's edge, and open sea / off the map where it's in no zone at all
local VOID_COST = 2.6           -- unknown ground in no zone costs this much more again
local BORDER_COST = 2.0         -- stepping over a zone border onto ground nobody stood on
local OTHER_ZONE = 1.3          -- unknown ground in a third zone (start and goal share one)

local walk = {}                 -- [instance] = { [cellKey] = true }
local built = {}                -- [instance] = true / [ "m" .. uiMap ] = true

local function cellOf(x, y) return math.floor(x / CELL), math.floor(y / CELL) end
local function keyOf(cx, cy) return (cx + OFF) * 1000000 + (cy + OFF) end

local function mark(inst, x, y)
  local w = walk[inst]
  if not w then w = {}; walk[inst] = w end
  local cx, cy = cellOf(x, y)
  for dx = -1, 1 do                 -- a spawn means the ground around it is walkable too
    for dy = -1, 1 do w[keyOf(cx + dx, cy + dy)] = true end
  end
end

-- world-coordinate spawns of a continent (ForeverDB spw), once per continent
local function buildInstance(inst)
  if built[inst] then return end
  built[inst] = true
  local db = D.db
  for _, groups in pairs(db.spw or {}) do
    for _, g in ipairs(groups) do
      if g[1] == inst then
        for j = 2, #g - 1, 2 do mark(inst, g[j], g[j + 1]) end
      end
    end
  end
  -- places you walked before (recorded by Collect.lua)
  local tr = QuesticusCollect and QuesticusCollect.trail and QuesticusCollect.trail[inst]
  if tr then
    local w = walk[inst] or {}
    walk[inst] = w
    for k in pairs(tr) do w[k] = true end
  end
end

-- map-only spawns (WoW Forever's new zones) of the map you are on
local spmIndex
local function buildMap(map)
  if not map or built["m" .. map] then return end
  built["m" .. map] = true
  if not spmIndex then
    spmIndex = {}
    for key, maps in pairs(D.db.spm or {}) do
      for m in pairs(maps) do
        local t = spmIndex[m]
        if not t then t = {}; spmIndex[m] = t end
        t[#t + 1] = key
      end
    end
  end
  for _, key in ipairs(spmIndex[map] or {}) do
    local pts = D.db.spm[key][map]
    for j = 1, #pts - 1, 2 do
      local inst, x, y = D:WorldPos(map, pts[j] / 1000, pts[j + 1] / 1000)
      if inst then mark(inst, x, y) end
    end
  end
end

function N:Prepare(pos)
  if not (pos and D:Ready()) then return end
  buildInstance(pos.i)
  local map = pos.m or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
  buildMap(map)
end

-- zone of a pathing cell (its centre), remembered per continent
local zcell, zcellN = {}, 0
local function zoneOfCell(inst, k, cx, cy)
  local t = zcell[inst]
  if not t then t = {}; zcell[inst] = t end
  local z = t[k]
  if z == nil then
    z = D:ZoneAt(inst, (cx + 0.5) * CELL, (cy + 0.5) * CELL) or false
    if zcellN >= 80000 then wipe(t); zcellN = 0 end
    t[k] = z
    zcellN = zcellN + 1
  end
  return z
end
N.ZoneOfCell = zoneOfCell

-- where you walk from one zone into the next is a pass through its border: remembered for the pathing
-- and the route's travel times (QuesticusCollect.zcross, sent to ForeverDB with the recordings)
local lastZ
local CROSS_KEEP = 12
local function noteCrossing(pos)
  local z = D:ZoneAt(pos.i, pos.x, pos.y)
  if not z or z == 0 then return end
  local l = lastZ
  lastZ = { i = pos.i, x = pos.x, y = pos.y, z = z }
  if not l or l.i ~= pos.i or l.z == z or D.Dist(l, pos) > 90 then return end
  if not QuesticusCollect or Q.db.collect == false then return end
  local zc = QuesticusCollect.zcross or {}
  QuesticusCollect.zcross = zc
  local ci = zc[pos.i] or {}
  zc[pos.i] = ci
  local k = D.ZonePair(l.z, z)
  local list = ci[k] or {}
  ci[k] = list
  local mx, my = math.floor((l.x + pos.x) / 2 + 0.5), math.floor((l.y + pos.y) / 2 + 0.5)
  for j = 1, #list - 1, 2 do
    if (list[j] - mx) ^ 2 + (list[j + 1] - my) ^ 2 < 40 * 40 then return end   -- (known already)
  end
  if #list < CROSS_KEEP * 2 then list[#list + 1] = mx; list[#list + 1] = my end
end

-- note a place you walked (called by Collect.lua every couple of seconds)
function N:Walked(pos)
  if not pos then return end
  pcall(noteCrossing, pos)
  local cx, cy = cellOf(pos.x, pos.y)
  local k = keyOf(cx, cy)
  local w = walk[pos.i]
  if w then w[k] = true end
  return k
end

-- ------------------------------------------------------------------ A*
local function heapPush(h, node, f)
  h[#h + 1] = { node, f }
  local i = #h
  while i > 1 do
    local p = math.floor(i / 2)
    if h[p][2] <= h[i][2] then break end
    h[p], h[i] = h[i], h[p]
    i = p
  end
end
local function heapPop(h)
  local top = h[1]
  local last = table.remove(h)
  if #h > 0 then
    h[1] = last
    local i = 1
    while true do
      local l, r, s = i * 2, i * 2 + 1, i
      if h[l] and h[l][2] < h[s][2] then s = l end
      if h[r] and h[r][2] < h[s][2] then s = r end
      if s == i then break end
      h[s], h[i] = h[i], h[s]
      i = s
    end
  end
  return top and top[1]
end

-- spots where the line failed before (Paths.lua): cost more, and a straight line through them isn't clear
local curInst
local function avoidCost(k) return (Q.Paths and curInst) and Q.Paths.Avoid(curInst, k) or 1 end
local function lineClear(w, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local steps = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy) / (CELL * 0.5)))
  for s = 1, steps - 1 do
    local cx, cy = cellOf(ax + dx * s / steps, ay + dy * s / steps)
    local k = keyOf(cx, cy)
    if not w[k] or avoidCost(k) > 1 then return false end
  end
  return true
end

-- list of waypoints {i, x, y} from `from` to `to` (the last one is `to`)
function N:Path(from, to)
  if not from or not to then return nil end
  if from.i ~= to.i then return { to } end
  N:Prepare(from)
  curInst = from.i
  local w = walk[from.i]
  local dist = D.Dist(from, to)
  -- (further than this a search covers thousands of cells - 50 ms and more - for a way that will be
  -- worked out again long before you get there: a straight line until you're closer)
  if dist > FAR then
    -- far, into another zone: through the border's pass people walked (the path is worked out from there)
    local via = D.BorderVia and D:BorderVia(from, to)
    if via and D.Dist(from, via) > 60 then return { via, to } end
    return { to }
  end
  if not w or dist < CELL * 2 or lineClear(w, from.x, from.y, to.x, to.y) then return { to } end
  local zones = D:HasBorders(from.i)
  local zgoal = zones and D:ZoneAt(from.i, to.x, to.y)
  local zstart = zones and D:ZoneAt(from.i, from.x, from.y)
  local oneZone = zgoal and zgoal ~= 0 and zgoal == zstart
  local sx, sy = cellOf(from.x, from.y)
  local gx, gy = cellOf(to.x, to.y)
  local minx, maxx = math.min(sx, gx) - MARGIN, math.max(sx, gx) + MARGIN
  local miny, maxy = math.min(sy, gy) - MARGIN, math.max(sy, gy) + MARGIN
  local start, goal = keyOf(sx, sy), keyOf(gx, gy)
  local tr = QuesticusCollect and QuesticusCollect.trail and QuesticusCollect.trail[from.i]
  local g, came, open = { [start] = 0 }, {}, {}
  local cxOf, cyOf = { [start] = sx }, { [start] = sy }
  heapPush(open, start, 0)
  local expanded, found = 0, false
  while #open > 0 and expanded < MAX_EXPAND do
    local cur = heapPop(open)
    if cur == goal then found = true; break end
    expanded = expanded + 1
    local cx, cy = cxOf[cur], cyOf[cur]
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local nx, ny = cx + dx, cy + dy
          if nx >= minx and nx <= maxx and ny >= miny and ny <= maxy then
            local nk = keyOf(nx, ny)
            local step = (dx ~= 0 and dy ~= 0) and 1.414 or 1
            if not w[nk] then
              step = step * UNKNOWN_COST
              if zones then
                local zn = zoneOfCell(from.i, nk, nx, ny)
                if zn == 0 then step = step * VOID_COST
                elseif zn then
                  local zc = zoneOfCell(from.i, cur, cx, cy)
                  if zc and zc ~= 0 and zc ~= zn then step = step * BORDER_COST end
                  if oneZone and zn ~= zgoal then step = step * OTHER_ZONE end
                end
              end
            elseif tr and tr[nk] then step = step * WALKED_COST end
            step = step * avoidCost(nk)
            local ng = g[cur] + step
            if not g[nk] or ng < g[nk] then
              g[nk], came[nk], cxOf[nk], cyOf[nk] = ng, cur, nx, ny
              local hx, hy = gx - nx, gy - ny
              heapPush(open, nk, ng + math.sqrt(hx * hx + hy * hy))
            end
          end
        end
      end
    end
  end
  if not found then return { to } end
  -- cells back to front -> world points (cell centres)
  local cells = {}
  local k = goal
  while k do
    table.insert(cells, 1, { i = from.i, x = (cxOf[k] + 0.5) * CELL, y = (cyOf[k] + 0.5) * CELL })
    k = came[k]
  end
  cells[#cells] = { i = to.i, x = to.x, y = to.y }
  -- string pulling: keep only the corners
  local out, anchor, idx = {}, from, 1
  while idx <= #cells do
    local far = idx
    for j = #cells, idx, -1 do
      if lineClear(w, anchor.x, anchor.y, cells[j].x, cells[j].y) then far = j; break end
    end
    out[#out + 1] = cells[far]
    anchor = cells[far]
    idx = far + 1
  end
  return out
end

-- cached paths, one per target (the arrow and the minimap ask for different targets: with a single
-- cached path each one threw the other's away and the whole search ran again, 25 times a second -
-- most of Questicus' lag while guiding). A target is keyed to 10 yards; the path's last point is
-- always the exact target. Recomputed when the target changes, after 8 s, or when you leave the path
local cache, cacheN = {}, 0
function N:Forget() wipe(cache); cacheN = 0; wipe(zcell) end
local function airborne()
  return (Q.OnTaxi and Q.OnTaxi()) or (IsFlying and IsFlying()) or false
end
function N:Route(here, to)
  if not here or not to then return nil end
  -- in the air (flight path, flying mount) the ground's walls don't matter: straight at the target, no
  -- search (moving that fast made a new search every half second: the stutters while flying)
  if airborne() then return { to } end
  local key = (to.i or 0) * 1e8 + math.floor(to.x / 10) * 1e4 + math.floor(to.y / 10)
  local now = GetTime and GetTime() or 0
  local e = cache[key]
  local p = e and e.path
  local stale = not p or now - e.at > 8
  -- (left the path: moved far from where it was worked out - the first corner itself can be 260+ yards
  -- away, which made the old check search again on every call)
  if not stale and e.from and D.Dist(here, e.from) > math.max(80, D.Dist(e.from, to) * 0.15) then stale = true end
  if stale then
    if not e then
      if cacheN >= 8 then wipe(cache); cacheN = 0 end
      e = {}; cache[key] = e; cacheN = cacheN + 1
    end
    e.at, e.from = now, { i = here.i, x = here.x, y = here.y }
    local ok, res = pcall(N.Path, N, here, to)
    e.path = ok and res or { to }
    p = e.path
  end
  if p and #p > 0 then p[#p] = to end            -- (exactly the target, not the one 10 yards off)
  -- drop waypoints you reached
  while p and #p > 1 and D.Dist(here, p[1]) < 25 do table.remove(p, 1) end
  return p
end

-- the point the arrow should aim at right now
function N:Next(here, to)
  local p = N:Route(here, to)
  return p and p[1] or to
end

Q:Command("zone", "the zone / sub-zone ForeverDB's borders put you in, and the border crossings known", function()
  local pos = D:PlayerPos()
  if not pos then Q:Print("no position here."); return end
  local z, s = D:ZoneAt(pos.i, pos.x, pos.y), D:SubZoneAt(pos.i, pos.x, pos.y)
  if z == nil then Q:Print("ForeverDB has no zone borders for this continent (update ForeverDB)."); return end
  local function nm(id)
    local n = id and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
    return (n or "?") .. " (" .. tostring(id) .. ")"
  end
  local mine, all = 0, 0
  for _, l in pairs(QuesticusCollect and QuesticusCollect.zcross and QuesticusCollect.zcross[pos.i] or {}) do mine = mine + #l / 2 end
  for _, l in pairs(D.db.zcross and D.db.zcross[pos.i] or {}) do all = all + #l / 2 end
  Q:Print(("zone %s%s. Border crossings on this continent: %d you walked, %d from ForeverDB."):format(
    z == 0 and "none (outside every zone)" or nm(z), s and (", sub-zone " .. nm(s)) or "", mine, all))
end)
