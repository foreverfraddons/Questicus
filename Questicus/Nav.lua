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
  if #list < CROSS_KEEP * 2 then
    list[#list + 1] = mx; list[#list + 1] = my
    if D.CrossingsChanged then D:CrossingsChanged() end
  end
end

-- note a place you walked (called by Collect.lua every couple of seconds)
function N:Walked(pos)
  if not pos then return end
  -- along a path set by hand: nothing recorded (it's settled)
  if N.NearFixed(pos) then return end
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
-- ------------------------------------------------------------------ walls (drawn by hand)
-- Lines nobody can walk through (a cliff edge, a fence, a canyon wall), drawn with the author's dev
-- tools: QuesticusCollect.walls[continent][id] = { n = { x, y, ... }, t } (or { del = true } once removed),
-- and ForeverDB's walls (everyone's). The path search never steps across one; a straight line that
-- crosses one goes round its nearer end.
local wallSegs, wallVer = {}, 0          -- [continent] = { buckets [bx..":"..by] = { {ax, ay, bx, by}, ... } }
local WB = 200
function N.WallsChanged() wallVer = wallVer + 1; wipe(wallSegs); N:Forget() end
local function wallList(i)
  local out = {}
  local function add(t, own)
    for id, wl in pairs(type(t) == "table" and t or {}) do
      if type(wl) == "table" and wl.n and not wl.del and #wl.n >= 4 then
        if own or not (out[id]) then out[id] = wl end
      end
    end
  end
  add(D.db and D.db.walls and D.db.walls[i], false)
  local own = QuesticusCollect and type(QuesticusCollect.walls) == "table" and QuesticusCollect.walls[i]
  add(own, true)
  -- (removed by you: gone even if ForeverDB still has it)
  for id, wl in pairs(type(own) == "table" and own or {}) do if type(wl) == "table" and wl.del then out[id] = nil end end
  return out
end
N.WallList = wallList
-- the author's dev tools: save / remove a wall (sent to ForeverDB with the recordings)
function N.SetWall(i, id, pts)
  QuesticusCollect.walls = type(QuesticusCollect.walls) == "table" and QuesticusCollect.walls or {}
  local ci = QuesticusCollect.walls[i] or {}
  QuesticusCollect.walls[i] = ci
  if pts and #pts >= 2 then
    local n = {}
    for _, p in ipairs(pts) do n[#n + 1] = math.floor(p[1] + 0.5); n[#n + 1] = math.floor(p[2] + 0.5) end
    ci[id] = { n = n, t = time and time() or 0 }
  else
    ci[id] = { del = true, t = time and time() or 0 }
  end
  N.WallsChanged()
  if Q.Planner then Q.Planner:Replan(1) end
end
local WALL_PAD = 3              -- yards past each end of a wall piece that still count as wall
local function segsOf(i)
  local s = wallSegs[i]
  if s then return s end
  s = {}
  wallSegs[i] = s
  for _, wl in pairs(wallList(i)) do
    local n = wl.n
    for j = 1, #n - 3, 2 do
      -- (each piece a little longer at both ends: a way can't slip past a wall's end or a joint by a hair)
      local ax, ay, bx2, by2 = n[j], n[j + 1], n[j + 2], n[j + 3]
      local l = math.sqrt((bx2 - ax) ^ 2 + (by2 - ay) ^ 2)
      local seg
      if l > 0 then
        local ux, uy = (bx2 - ax) / l * WALL_PAD, (by2 - ay) / l * WALL_PAD
        seg = { ax - ux, ay - uy, bx2 + ux, by2 + uy }
      else
        seg = { ax, ay, bx2, by2 }
      end
      local x0, x1 = math.floor(math.min(seg[1], seg[3]) / WB), math.floor(math.max(seg[1], seg[3]) / WB)
      local y0, y1 = math.floor(math.min(seg[2], seg[4]) / WB), math.floor(math.max(seg[2], seg[4]) / WB)
      for bx = x0, x1 do
        for by = y0, y1 do
          local k = bx .. ":" .. by
          s[k] = s[k] or {}
          table.insert(s[k], seg)
        end
      end
    end
  end
  return s
end
local function cross(ax, ay, bx, by, cx, cy, dx, dy)
  local function o(px, py, qx, qy, rx, ry) return (qx - px) * (ry - py) - (qy - py) * (rx - px) end
  local d1, d2 = o(cx, cy, dx, dy, ax, ay), o(cx, cy, dx, dy, bx, by)
  local d3, d4 = o(ax, ay, bx, by, cx, cy), o(ax, ay, bx, by, dx, dy)
  return ((d1 > 0) ~= (d2 > 0)) and ((d3 > 0) ~= (d4 > 0))
end
-- does the line a-b go through a wall? (returns the wall segment)
local function hitsWall(i, ax, ay, bx, by)
  local s = segsOf(i)
  if not next(s) then return nil end
  local x0, x1 = math.floor(math.min(ax, bx) / WB), math.floor(math.max(ax, bx) / WB)
  local y0, y1 = math.floor(math.min(ay, by) / WB), math.floor(math.max(ay, by) / WB)
  if (x1 - x0 + 1) * (y1 - y0 + 1) > 400 then
    for _, list in pairs(s) do
      for _, g in ipairs(list) do if cross(ax, ay, bx, by, g[1], g[2], g[3], g[4]) then return g end end
    end
    return nil
  end
  for bxx = x0, x1 do
    for byy = y0, y1 do
      for _, g in ipairs(s[bxx .. ":" .. byy] or {}) do
        if cross(ax, ay, bx, by, g[1], g[2], g[3], g[4]) then return g end
      end
    end
  end
end
N.HitsWall = hitsWall
-- a way between hand-drawn walls that keeps to the middle of the passages: a fine grid (5 yards) round
-- you and the target, the walls drawn into it, every square's distance to the nearest wall worked out,
-- and a search that pays extra for squares close to a wall - so in a corridor the way runs down the
-- middle instead of bouncing from one wall's corner to the other's.
local FG_MAX = 420              -- squares a side at most (the square size grows past that)
local FG_NEAR = 5               -- squares: closer than this to a wall costs extra
-- pcall that a background search can still pause inside (the game's Lua can't pause across a pcall,
-- so in the background it's a plain call - the background job itself catches errors)
local function softcall(f, ...)
  local co, isMain = coroutine.running()
  if co and not isMain then return true, f(...) end
  return pcall(f, ...)
end
N.softcall = softcall
-- in the background: pause once this frame's few ms are used up
local sliceT0
local function tick()
  local co, isMain = coroutine.running()
  if not co or isMain or not debugprofilestop then return end
  local now = debugprofilestop()
  if not sliceT0 then sliceT0 = now; return end
  if now - sliceT0 > 3 then coroutine.yield(); sliceT0 = debugprofilestop() end
end
N.tick = tick
function N.SliceStart() sliceT0 = debugprofilestop and debugprofilestop() end
-- any hand-drawn wall within the box?
function N.WallsNear(i, x0, x1, y0, y1)
  local segs = segsOf(i)
  if not next(segs) then return false end
  for bxx = math.floor(x0 / WB), math.floor(x1 / WB) do
    for byy = math.floor(y0 / WB), math.floor(y1 / WB) do
      if segs[bxx .. ":" .. byy] then return true end
    end
  end
  return false
end
function N.WallGrid(from, to)
  local i = from.i
  local margin = 160
  local x0, x1 = math.min(from.x, to.x) - margin, math.max(from.x, to.x) + margin
  local y0, y1 = math.min(from.y, to.y) - margin, math.max(from.y, to.y) + margin
  -- (no wall anywhere near: nothing to do)
  local segs, any = segsOf(i), false
  for bxx = math.floor(x0 / WB), math.floor(x1 / WB) do
    for byy = math.floor(y0 / WB), math.floor(y1 / WB) do
      if segs[bxx .. ":" .. byy] then any = true; break end
    end
    if any then break end
  end
  if not any then return nil end
  local co, isMain = coroutine.running()
  local sliced = co and not isMain
  local function pause() if sliced then coroutine.yield() end end
  local c = math.max(5, math.max(x1 - x0, y1 - y0) / FG_MAX)
  local W, H = math.floor((x1 - x0) / c) + 1, math.floor((y1 - y0) / c) + 1
  local function idx(cx, cy) return cy * W + cx end
  local block = {}
  -- the walls into the grid (each piece walked in half-square steps)
  for _, wl in pairs(wallList(i)) do
    local n = wl.n
    for j = 1, #n - 3, 2 do
      local ax, ay, bx, by = n[j], n[j + 1], n[j + 2], n[j + 3]
      if not ((ax < x0 and bx < x0) or (ax > x1 and bx > x1) or (ay < y0 and by < y0) or (ay > y1 and by > y1)) then
        local l = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local steps = math.max(1, math.ceil(l / (c * 0.5)))
        tick()
        for k = 0, steps do
          local px, py = ax + (bx - ax) * k / steps, ay + (by - ay) * k / steps
          local cx, cy = math.floor((px - x0) / c), math.floor((py - y0) / c)
          if cx >= 0 and cx < W and cy >= 0 and cy < H then block[idx(cx, cy)] = true end
        end
      end
    end
  end
  if not next(block) then return nil end
  pause()
  -- distance (in squares) to the nearest wall square, up to FG_NEAR
  local near, q, head = {}, {}, 1
  for k in pairs(block) do near[k] = 0; q[#q + 1] = k end
  while head <= #q do
    local k = q[head]; head = head + 1
    if head % 3000 == 0 then pause() end
    local d = near[k]
    if d < FG_NEAR then
      local cx, cy = k % W, math.floor(k / W)
      for dx = -1, 1 do
        for dy = -1, 1 do
          local nx, ny = cx + dx, cy + dy
          if nx >= 0 and nx < W and ny >= 0 and ny < H then
            local nk = idx(nx, ny)
            if near[nk] == nil then near[nk] = d + 1; q[#q + 1] = nk end
          end
        end
      end
    end
  end
  local sx, sy = math.floor((from.x - x0) / c), math.floor((from.y - y0) / c)
  local gx, gy = math.floor((to.x - x0) / c), math.floor((to.y - y0) / c)
  local start, goal = idx(sx, sy), idx(gx, gy)
  block[start], block[goal] = nil, nil
  local g, came, open = { [start] = 0 }, {}, {}
  heapPush(open, start, 0)
  local found, expanded = false, 0
  pause()
  local t0 = sliced and debugprofilestop and debugprofilestop()
  while #open > 0 and expanded < (sliced and 80000 or 20000) do
    local cur = heapPop(open)
    if cur == goal then found = true; break end
    expanded = expanded + 1
    -- (worked out in the background: a few ms a frame, never a stutter)
    if sliced and expanded % 200 == 0 and (not t0 or debugprofilestop() - t0 > 3) then
      coroutine.yield()
      t0 = debugprofilestop and debugprofilestop()
    end
    local cx, cy = cur % W, math.floor(cur / W)
    local gc = g[cur]
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local nx, ny = cx + dx, cy + dy
          if nx >= 0 and nx < W and ny >= 0 and ny < H then
            local nk = idx(nx, ny)
            -- (no squeezing diagonally between two wall squares)
            if not block[nk] and not (dx ~= 0 and dy ~= 0 and block[idx(cx + dx, cy)] and block[idx(cx, cy + dy)]) then
              local d = near[nk]
              local pen = d and (FG_NEAR + 1 - d) * 0.6 or 0
              local ng = gc + ((dx ~= 0 and dy ~= 0) and 1.414 or 1) * (1 + pen)
              if not g[nk] or ng < g[nk] then
                g[nk] = ng
                came[nk] = cur
                heapPush(open, nk, ng + math.sqrt((nx - gx) ^ 2 + (ny - gy) ^ 2))
              end
            end
          end
        end
      end
    end
  end
  if not found then return nil end
  local cells = {}
  local k = goal
  while k do
    table.insert(cells, 1, { i = i, x = x0 + (k % W + 0.5) * c, y = y0 + (math.floor(k / W) + 0.5) * c })
    k = came[k]
  end
  cells[1] = { i = i, x = from.x, y = from.y }
  cells[#cells] = to
  -- fewer points, same shape (within a couple of yards, never over a wall)
  local out = {}
  local function simp(a, b)
    tick()
    local A, B = cells[a], cells[b]
    local dx, dy = B.x - A.x, B.y - A.y
    local l2 = dx * dx + dy * dy
    local best, bi = 0, nil
    for m = a + 1, b - 1 do
      local P = cells[m]
      local t = l2 > 0 and math.max(0, math.min(1, ((P.x - A.x) * dx + (P.y - A.y) * dy) / l2)) or 0
      local d = (P.x - A.x - dx * t) ^ 2 + (P.y - A.y - dy * t) ^ 2
      if d > best then best, bi = d, m end
    end
    if bi and (best > (c * 0.6) ^ 2 or hitsWall(i, A.x, A.y, B.x, B.y)) then
      simp(a, bi); simp(bi, b)
    else
      out[#out + 1] = B
    end
  end
  simp(1, #cells)
  out.fine = true                 -- (already the shape to draw: the map's smoothing only rounds it)
  return out
end

-- the fine wall search: only inside a background route search (N.Background) - on the spot it's too slow
-- for a frame. (N.syncWalls: tests, all at once.)
local wgDone = {}
function N.WallGridFor(from, to)
  local co, isMain = coroutine.running()
  if (co and not isMain) or N.syncWalls then return N.WallGrid(from, to) end
  return nil
end
-- the shortest way round hand-drawn walls: points just past each wall's ends and off both sides of its
-- bends, joined where nothing's in the way (a visibility graph), searched from you to the target.
-- Only walls near the way count (at most 160 points).
local WALL_OFF = 7              -- yards off a wall's end / bend (past the 3-yard pad)
function N.WallWay(from, to)
  local i = from.i
  local pad = 350
  local minx, maxx = math.min(from.x, to.x) - pad, math.max(from.x, to.x) + pad
  local miny, maxy = math.min(from.y, to.y) - pad, math.max(from.y, to.y) + pad
  local nodes = { { x = from.x, y = from.y }, { x = to.x, y = to.y } }
  local cand = {}
  local sx, sy = to.x - from.x, to.y - from.y
  local sl2 = sx * sx + sy * sy
  local function add(x, y)
    if x >= minx and x <= maxx and y >= miny and y <= maxy then
      -- (how far off the straight way: the nearest ones are kept when there are too many)
      local t = sl2 > 0 and math.max(0, math.min(1, ((x - from.x) * sx + (y - from.y) * sy) / sl2)) or 0
      local d = (x - from.x - sx * t) ^ 2 + (y - from.y - sy * t) ^ 2
      cand[#cand + 1] = { x = x, y = y, d = d }
    end
  end
  for _, wl in pairs(wallList(i)) do
    local n = wl.n
    local m = #n / 2
    for k = 1, m do
      local x, y = n[2 * k - 1], n[2 * k]
      if x >= minx and x <= maxx and y >= miny and y <= maxy then
        if k == 1 or k == m then
          -- past the end, along the wall
          local ox, oy = (k == 1) and n[3] or n[2 * k - 3], (k == 1) and n[4] or n[2 * k - 2]
          local dx, dy = x - ox, y - oy
          local l = math.sqrt(dx * dx + dy * dy)
          if l > 0 then add(x + dx / l * WALL_OFF, y + dy / l * WALL_OFF) end
        else
          -- off both sides of a bend
          local ax, ay = n[2 * k - 3], n[2 * k - 2]
          local bx, by = n[2 * k + 1], n[2 * k + 2]
          local u1x, u1y = x - ax, y - ay
          local u2x, u2y = bx - x, by - y
          local l1, l2 = math.sqrt(u1x * u1x + u1y * u1y), math.sqrt(u2x * u2x + u2y * u2y)
          if l1 > 0 and l2 > 0 then
            local nx, ny = -(u1y / l1 + u2y / l2), (u1x / l1 + u2x / l2)
            local nl = math.sqrt(nx * nx + ny * ny)
            if nl > 0.05 then
              nx, ny = nx / nl, ny / nl
              add(x + nx * WALL_OFF, y + ny * WALL_OFF)
              add(x - nx * WALL_OFF, y - ny * WALL_OFF)
            end
          end
        end
      end
    end
  end
  if #cand > 160 then table.sort(cand, function(p, q) return p.d < q.d end) end
  for k = 1, math.min(160, #cand) do nodes[#nodes + 1] = cand[k] end
  -- Dijkstra over the points, edges checked lazily
  local n = #nodes
  local dist, prev, done = { [1] = 0 }, {}, {}
  for _ = 1, n do
    local u, ud
    for k = 1, n do
      if not done[k] and dist[k] and (not ud or dist[k] < ud) then u, ud = k, dist[k] end
    end
    if not u or u == 2 then break end
    done[u] = true
    local a = nodes[u]
    for v = 1, n do
      if not done[v] then
        local b = nodes[v]
        local d = ud + math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
        if (not dist[v] or d < dist[v]) and not hitsWall(i, a.x, a.y, b.x, b.y) then dist[v], prev[v] = d, u end
      end
    end
  end
  if not dist[2] then return nil end
  local out, k = {}, 2
  while k and k ~= 1 do
    table.insert(out, 1, { i = i, x = nodes[k].x, y = nodes[k].y })
    k = prev[k]
  end
  out[#out] = to
  return out
end
-- round a wall: the end of the whole wall line nearer the way (a little past it)
local function roundWall(i, from, to)
  local best, bd
  for _, wl in pairs(wallList(i)) do
    local n = wl.n
    local hit
    for j = 1, #n - 3, 2 do
      if cross(from.x, from.y, to.x, to.y, n[j], n[j + 1], n[j + 2], n[j + 3]) then hit = true; break end
    end
    if hit then
      for _, e in ipairs({ { n[1], n[2], n[3], n[4] }, { n[#n - 1], n[#n], n[#n - 3], n[#n - 2] } }) do
        local ex, ey, px, py = e[1], e[2], e[3], e[4]
        local dx, dy = ex - px, ey - py
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then ex, ey = ex + dx / len * 15, ey + dy / len * 15 end
        local d = math.sqrt((from.x - ex) ^ 2 + (from.y - ey) ^ 2) + math.sqrt((to.x - ex) ^ 2 + (to.y - ey) ^ 2)
        if not bd or d < bd then best, bd = { i = i, x = ex, y = ey }, d end
      end
    end
  end
  return best
end

local function lineClear(w, ax, ay, bx, by)
  if curInst and hitsWall(curInst, ax, ay, bx, by) then return false end
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
function N:Path(from, to, oneLeg)
  if not from or not to then return nil end
  if from.i ~= to.i then return { to } end
  N:Prepare(from)
  curInst = from.i
  local w = walk[from.i]
  local dist = D.Dist(from, to)
  -- (further than this a search covers thousands of cells - 50 ms and more - for a way that will be
  -- worked out again long before you get there: a straight line until you're closer)
  -- into another zone: only through the crossings between zones (no straight line over a zone line)
  -- (each leg between crossings is worked out on its own, so it still goes round walls and the like)
  if D.ZoneWalkPath and not oneLeg then
    local cp = D.ZoneWalkPath(from, to)
    if cp then
      local out, at = {}, from
      local stops = {}
      for _, q in ipairs(cp) do
        if D.Dist(from, q) > 12 or #stops > 0 then stops[#stops + 1] = q end
      end
      stops[#stops + 1] = to
      for _, q in ipairs(stops) do
        local ok, leg = softcall(N.Path, N, at, q, true)
        if ok and leg and #leg > 0 then
          for j = 1, #leg - 1 do out[#out + 1] = leg[j] end
        end
        out[#out + 1] = q
        at = q
      end
      return out
    end
  end
  local walled = hitsWall(from.i, from.x, from.y, to.x, to.y)
  local hasWalls = next(segsOf(from.i)) ~= nil
  if dist > FAR then
    -- far, into another zone: through the border's pass people walked (the path is worked out from there)
    local via = D.BorderVia and D:BorderVia(from, to)
    if via and D.Dist(from, via) > 60 then return { via, to } end
    -- a wall in the way: round its nearer end
    local r = walled and roundWall(from.i, from, to)
    if r then return { r, to } end
    return { to }
  end
  if not walled and (not w or dist < CELL * 2 or lineClear(w, from.x, from.y, to.x, to.y)) then return { to } end
  local function grid()
    w = w or {}
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
    local co, isMain = coroutine.running()
    local sliced = co and not isMain
    local t0 = sliced and debugprofilestop and debugprofilestop()
    while #open > 0 and expanded < MAX_EXPAND do
      local cur = heapPop(open)
      if cur == goal then found = true; break end
      expanded = expanded + 1
      if sliced and expanded % 100 == 0 and (not t0 or debugprofilestop() - t0 > 3) then
        coroutine.yield()
        t0 = debugprofilestop and debugprofilestop()
      end
      local cx, cy = cxOf[cur], cyOf[cur]
      for dx = -1, 1 do
        for dy = -1, 1 do
          if dx ~= 0 or dy ~= 0 then
            local nx, ny = cx + dx, cy + dy
            if nx >= minx and nx <= maxx and ny >= miny and ny <= maxy then
              local nk = keyOf(nx, ny)
              local step = (dx ~= 0 and dy ~= 0) and 1.414 or 1
              -- (never through a wall drawn by hand)
              if hasWalls and hitsWall(from.i, (cx + 0.5) * CELL, (cy + 0.5) * CELL, (nx + 0.5) * CELL, (ny + 0.5) * CELL) then
                step = math.huge
              end
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
              if step < math.huge and (not g[nk] or ng < g[nk]) then
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
        tick()
        if lineClear(w, anchor.x, anchor.y, cells[j].x, cells[j].y)
        and not (hasWalls and hitsWall(from.i, anchor.x, anchor.y, cells[j].x, cells[j].y)) then far = j; break end
      end
      out[#out + 1] = cells[far]
      anchor = cells[far]
      idx = far + 1
    end
    return out
  end
  -- hand-drawn walls about: also the shortest way round the walls themselves (through the openings
  -- between them, past their ends) - the grid's 20-yard squares can't see a narrow opening, so its way
  -- can go far round or (corners joined up) over a wall
  if hasWalls then
    -- (WallWay's visibility graph is far too slow with many walls - seconds - so only the grid; in
    -- the game it's worked out in the background and used once it's there)
    local vis = N.WallGridFor and N.WallGridFor(from, to)
    local ok, a = softcall(grid)
    a = ok and a or nil
    if vis then
      local function len(list)
        local d, px, py = 0, from.x, from.y
        for _, q in ipairs(list) do d = d + math.sqrt((q.x - px) ^ 2 + (q.y - py) ^ 2); px, py = q.x, q.y end
        return d
      end
      local function crossesWall(list)
        local px, py = from.x, from.y
        for _, q in ipairs(list) do
          if hitsWall(from.i, px, py, q.x, q.y) then return true end
          px, py = q.x, q.y
        end
        return false
      end
      if not a or (#a == 1 and a[1] == to) or crossesWall(a) or len(a) > len(vis) * 1.25 then return vis end
    end
    return a or { to }
  end
  return grid()
end

-- cached paths, one per target (the arrow and the minimap ask for different targets: with a single
-- cached path each one threw the other's away and the whole search ran again, 25 times a second -
-- most of Questicus' lag while guiding). A target is keyed to 10 yards; the path's last point is
-- always the exact target. Recomputed when the target changes, after 8 s, or when you leave the path
local cache, cacheN = {}, 0
function N:Forget() wipe(cache); cacheN = 0; wipe(zcell); wipe(wallSegs); wipe(wgDone) end
function N.ForgetRoutes() wipe(cache); cacheN = 0 end
-- route searches in the background, one at a time, a few ms a frame
local bgQueue, bgJob = {}, nil
function N.Background(key, e, from, to)
  if bgJob and bgJob.key == key then return end
  bgQueue[key] = { key = key, e = e, from = from, to = to }
end
if CreateFrame then
  N.bgFrame = CreateFrame("Frame")
  N.bgFrame:SetScript("OnUpdate", function()
    if not bgJob then
      local k, j = next(bgQueue)
      if not k then return end
      bgQueue[k] = nil
      j.co = coroutine.create(function() return N:Path(j.from, j.to) end)
      bgJob = j
    end
    N.SliceStart()
    local ok, res = coroutine.resume(bgJob.co)
    if not ok or coroutine.status(bgJob.co) == "dead" then
      local j = bgJob
      bgJob = nil
      if cache[j.key] == j.e then
        j.e.path = (ok and res) or j.e.path or { j.to }
        j.e.from = j.from
      end
    end
  end)
end
local function airborne()
  return (Q.OnTaxi and Q.OnTaxi()) or (IsFlying and IsFlying()) or false
end

-- ------------------------------------------------------------------ fixed paths (set by hand)
-- A route step's walk drawn by hand on the map (the author's dev tools): used as it is from then on -
-- no path search, no learning or trail recording along it. [stepKey] = { i = continent, n = {x, y, ...},
-- t = time }. This account's own (QuesticusCollect.fpath, sent to ForeverDB with the recordings) win
-- over ForeverDB's (D.db.fpath, everyone's).
function N.StepKey(s)
  if not s then return nil end
  if s.type == "buy" then return "buy:" .. tostring(s.npc or s.title or "") end
  local q = s.quests and s.quests[1]
  return q and (s.type .. ":" .. q) or nil
end
function N.FixedOf(key)
  if not key then return nil end
  local own = QuesticusCollect and QuesticusCollect.fpath and QuesticusCollect.fpath[key]
  if type(own) == "table" and own.n then return own end
  local db = D.db and D.db.fpath and D.db.fpath[key]
  if type(db) == "table" and db.n then return db end
end
function N.SetFixed(key, inst, nodes)
  if not (key and inst and nodes) then return end
  QuesticusCollect = QuesticusCollect or {}
  QuesticusCollect.fpath = QuesticusCollect.fpath or {}
  local n = {}
  for _, p in ipairs(nodes) do n[#n + 1] = math.floor(p.x * 10 + 0.5) / 10; n[#n + 1] = math.floor(p.y * 10 + 0.5) / 10 end
  QuesticusCollect.fpath[key] = { i = inst, n = n, t = time and time() or 0 }
  N:Forget()
  N.fixedVer = (N.fixedVer or 0) + 1
  if Q.Pins and Q.Pins.RefreshWorld then pcall(Q.Pins.RefreshWorld, Q.Pins, true) end
end
function N.ClearFixed(key)
  if QuesticusCollect and QuesticusCollect.fpath then QuesticusCollect.fpath[key] = nil end
  N:Forget()
  N.fixedVer = (N.fixedVer or 0) + 1
  if Q.Pins and Q.Pins.RefreshWorld then pcall(Q.Pins.RefreshWorld, Q.Pins, true) end
end
-- the fixed path that leads to `to`: the focused step's own when `to` is near its end, else any path
-- ending within 60 yd of `to` on that continent
local FIX_END = 60
local function fixedFor(to)
  local function ends(f, r)
    local n = f.n
    return f.i == to.i and #n >= 2 and (n[#n - 1] - to.x) ^ 2 + (n[#n] - to.y) ^ 2 <= r * r
  end
  local key = N.focusKey
  local f = N.FixedOf(key)
  if f and ends(f, 300) then return f end
  for _, src in ipairs({ QuesticusCollect and QuesticusCollect.fpath, D.db and D.db.fpath }) do
    for _, g in pairs(src or {}) do
      if type(g) == "table" and g.n and ends(g, FIX_END) then return g end
    end
  end
end
N.FixedFor = fixedFor
-- the rest of a fixed path from where you are: from the node you're nearest (the one after it once
-- you're at it), then the target itself when it isn't the path's last node
local function fixedRoute(f, here, to)
  local n = f.n
  local best, bd
  for j = 1, #n - 1, 2 do
    local d = (n[j] - here.x) ^ 2 + (n[j + 1] - here.y) ^ 2
    if not bd or d < bd then best, bd = j, d end
  end
  -- (between two nodes: heading on to the next one, not back to the one behind you)
  if best and best + 2 <= #n - 1 then
    local ax, ay, bx, by = n[best], n[best + 1], n[best + 2], n[best + 3]
    local seg = (bx - ax) ^ 2 + (by - ay) ^ 2
    local t = seg > 0 and ((here.x - ax) * (bx - ax) + (here.y - ay) * (by - ay)) / seg or 0
    if t > 0 or bd < 25 * 25 then best = best + 2 end
  end
  local out = {}
  for j = best or 1, #n - 1, 2 do out[#out + 1] = { i = f.i, x = n[j], y = n[j + 1], fixed = true } end
  local last = out[#out]
  if not last or D.Dist(last, to) > 10 then out[#out + 1] = to end
  return out
end
N.FixedRoute = fixedRoute
-- within r yards of a fixed path's line?
function N.OnFixed(f, pos, r)
  local n = f.n
  if f.i ~= pos.i or not n then return false end
  if #n < 4 then return #n >= 2 and (n[1] - pos.x) ^ 2 + (n[2] - pos.y) ^ 2 <= r * r end
  for j = 1, #n - 3, 2 do
    local ax, ay, bx, by = n[j], n[j + 1], n[j + 2], n[j + 3]
    local seg = (bx - ax) ^ 2 + (by - ay) ^ 2
    local t = seg > 0 and math.max(0, math.min(1, ((pos.x - ax) * (bx - ax) + (pos.y - ay) * (by - ay)) / seg)) or 0
    local px, py = ax + (bx - ax) * t, ay + (by - ay) * t
    if (pos.x - px) ^ 2 + (pos.y - py) ^ 2 <= r * r then return true end
  end
  return false
end
-- near a fixed path (its walk isn't learned or recorded any more)?
function N.NearFixed(pos, r)
  r = r or 30
  for _, src in ipairs({ QuesticusCollect and QuesticusCollect.fpath, D.db and D.db.fpath }) do
    for _, f in pairs(src or {}) do
      local n = type(f) == "table" and f.n
      if n and f.i == pos.i then
        for j = 1, #n - 3, 2 do
          local ax, ay, bx, by = n[j], n[j + 1], n[j + 2], n[j + 3]
          local seg = (bx - ax) ^ 2 + (by - ay) ^ 2
          local t = seg > 0 and math.max(0, math.min(1, ((pos.x - ax) * (bx - ax) + (pos.y - ay) * (by - ay)) / seg)) or 0
          local px, py = ax + (bx - ax) * t, ay + (by - ay) * t
          if (pos.x - px) ^ 2 + (pos.y - py) ^ 2 <= r * r then return true end
        end
      end
    end
  end
  return false
end

function N:Route(here, to)
  if not here or not to then return nil end
  -- in the air (flight path, flying mount) the ground's walls don't matter: straight at the target, no
  -- search (moving that fast made a new search every half second: the stutters while flying)
  if airborne() then return { to } end
  -- a path set by hand for this walk: that, as it is
  local f = here.i == to.i and fixedFor(to)
  -- (only once you're on it or close: a path drawn for another walk to the same person - from
  -- somewhere else - would otherwise be a straight line from you to its end, over every wall)
  if f and not N.OnFixed(f, here, 200) then f = nil end
  if f then
    local p = fixedRoute(f, here, to)
    local reach = N.precise and 8 or 15
    while #p > 1 and D.Dist(here, p[1]) < reach do table.remove(p, 1) end
    return p
  end
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
      -- (room for every leg of the route on the map: with only 8 they pushed each other out and were
      -- all searched again on every redraw)
      if cacheN >= 48 then
        local oldK, oldAt
        for k2, e2 in pairs(cache) do if not oldAt or e2.at < oldAt then oldK, oldAt = k2, e2.at end end
        cache[oldK] = nil; cacheN = cacheN - 1
      end
      e = {}; cache[key] = e; cacheN = cacheN + 1
    end
    e.at, e.from = now, { i = here.i, x = here.x, y = here.y }
    local pad = 200
    local near = N.WallsNear and here.i == to.i and N.WallsNear(here.i, math.min(here.x, to.x) - pad, math.max(here.x, to.x) + pad,
      math.min(here.y, to.y) - pad, math.max(here.y, to.y) + pad)
    if near and N.bgFrame then
      -- walls about: worked out in the background (a few ms a frame); the old way, or straight, till then
      N.Background(key, e, { i = here.i, x = here.x, y = here.y }, to)
      e.path = e.path or { to }
    else
      local t0 = debugprofilestop and debugprofilestop()
      local ok, res = pcall(N.Path, N, here, to)
      -- (a slow search - a long way - is kept longer before it's worked out again)
      local took = t0 and (debugprofilestop() - t0) or 0
      if took > 15 then e.at = now + math.min(30, took / 2) end
      e.path = ok and res or { to }
    end
    p = e.path
  end
  if p and #p > 0 then p[#p] = to end            -- (exactly the target, not the one 10 yards off)
  -- drop waypoints you reached (walking to a person / object / place: only once you're really at the
  -- corner, so the arrow doesn't turn early; mobs wander, so those keep the looser radius)
  local reach = (N.precise or (UnitIsGhost and UnitIsGhost("player"))) and 8 or 25
  -- (and only once the way on to the next one is clear: never cut a corner round a wall's end)
  while p and #p > 1 and D.Dist(here, p[1]) < reach and not hitsWall(here.i, here.x, here.y, p[2].x, p[2].y) do
    table.remove(p, 1)
  end
  -- corners already behind you (the way was worked out a little way back - in the background, or before
  -- you moved on): dropped once you're nearer the next one than they are, and the way to it is clear,
  -- so the line doesn't loop back behind you and the arrow doesn't point back at them
  while p and #p > 1 do
    local a, b = p[1], p[2]
    if D.Dist(here, b) < D.Dist(a, b) and D.Dist(here, a) < 120
      and not hitsWall(here.i, here.x, here.y, b.x, b.y) then
      table.remove(p, 1)
    else
      break
    end
  end
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
