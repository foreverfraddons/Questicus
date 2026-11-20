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
local MAX_EXPAND = 7000
local MARGIN = 30               -- cells around start / goal the search may use
local OFF = 100000

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

-- note a place you walked (called by Collect.lua every couple of seconds)
function N:Walked(pos)
  if not pos then return end
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
  if not w or dist < CELL * 2 or lineClear(w, from.x, from.y, to.x, to.y) then return { to } end
  local sx, sy = cellOf(from.x, from.y)
  local gx, gy = cellOf(to.x, to.y)
  local minx, maxx = math.min(sx, gx) - MARGIN, math.max(sx, gx) + MARGIN
  local miny, maxy = math.min(sy, gy) - MARGIN, math.max(sy, gy) + MARGIN
  local start, goal = keyOf(sx, sy), keyOf(gx, gy)
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
            if not w[nk] then step = step * UNKNOWN_COST end
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

-- cached path for the guide target; recomputed when the target changes or you leave the path
local cache = { key = nil, path = nil, at = 0 }
function N:Forget() cache.key, cache.path = nil, nil end
function N:Route(here, to)
  if not here or not to then return nil end
  local key = ("%d:%d:%d"):format(to.i or 0, math.floor(to.x), math.floor(to.y))
  local now = GetTime and GetTime() or 0
  local p = cache.path
  local stale = cache.key ~= key or not p or now - cache.at > 8
  if not stale and p[1] and D.Dist(here, p[1]) > 260 then stale = true end
  if stale then
    cache.key, cache.at = key, now
    local ok, res = pcall(N.Path, N, here, to)
    cache.path = ok and res or { to }
    p = cache.path
  end
  -- drop waypoints you reached
  while p and #p > 1 and D.Dist(here, p[1]) < 25 do table.remove(p, 1) end
  return p
end

-- the point the arrow should aim at right now
function N:Next(here, to)
  local p = N:Route(here, to)
  return p and p[1] or to
end
