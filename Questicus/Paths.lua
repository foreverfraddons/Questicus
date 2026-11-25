-- Questicus path learning: every walk to a route target is compared with the line the guide showed.
--  * how much longer the real walk was than a straight line, per zone -> the planner's travel times
--    (QuesticusCollect.pathk[uiMap] = { r = sum of ratios, n = walks })
--  * where the line went but you didn't (you had to go round: a wall, a cliff, water) -> those
--    spots cost more in the pathing next time (QuesticusCollect.avoid[continent][cell] = count)
-- Ground only: flights, taxis, swimming detours across water are left out; deaths cancel the walk.
local Q = Questicus
local D = Q.Data
local PL = {}
Q.Paths = PL

local CELL = 40                 -- same grid as Nav.lua
local OFF = 100000
local MIN_LEG = 80              -- yards: shorter walks say nothing
-- yards: line spots this far from anywhere you walked = you went round. (Was 70: a detour round a city
-- wall or through a gate is much tighter than that, so cities never learned anything. 30 still keeps
-- every pathing cell you walked through yourself - your trail points are 20 yards apart)
local OFF_LINE = 30
local DETOUR = 1.12             -- your walk this much longer than the line = the line was wrong somewhere (was 1.25)
local MAX_TRAIL = 400

local leg                       -- the walk in progress
local function now() return GetTime and GetTime() or 0 end
local function cellKey(x, y) return (math.floor(x / CELL) + OFF) * 1000000 + (math.floor(y / CELL) + OFF) end
local function store()
  if not QuesticusCollect or Q.db.collect == false then return nil end
  QuesticusCollect.pathk = QuesticusCollect.pathk or {}
  QuesticusCollect.avoid = QuesticusCollect.avoid or {}
  return QuesticusCollect
end
local function grounded()
  if Q.OnTaxi() then return false end
  if IsFlying and IsFlying() then return false end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
  return true
end

-- ------------------------------------------------------------------ what the planner reads
-- how much longer walking in a zone really is than the straight line (1.0 - 2.0; 1.15 until known)
function PL.Factor(map)
  local c = QuesticusCollect and QuesticusCollect.pathk
  local e = map and c and c[map]
  if not e or (e.n or 0) < 2 then return 1.15 end
  return math.max(1.0, math.min(2.0, e.r / e.n))
end
-- extra cost of a pathing cell where the line failed before (Nav.lua)
function PL.Avoid(inst, key)
  local a = QuesticusCollect and QuesticusCollect.avoid and QuesticusCollect.avoid[inst]
  local n = a and a[key]
  if not n then return 1 end
  -- grows with every walk that had to go round it: once could be chance, four times is a wall
  return n >= 4 and 50 or n == 3 and 20 or n == 2 and 8 or 3
end

-- ------------------------------------------------------------------ recording a walk
local function start(target)
  local here = D:PlayerPos()
  if not (here and target and target.i == here.i) then leg = nil; return end
  local straight = D.Dist(here, target)
  if straight < MIN_LEG then leg = nil; return end
  -- a walk with a path set by hand isn't learned from: that path stays as it is
  local fx = Q.Nav and Q.Nav.FixedFor and Q.Nav.FixedFor(target)
  if fx and (not Q.Nav.OnFixed or Q.Nav.OnFixed(fx, here, 200)) then leg = nil; return end
  local line = { { i = here.i, x = here.x, y = here.y } }
  local path = Q.Nav and Q.Nav:Route(here, target) or { target }
  for _, p in ipairs(path or {}) do line[#line + 1] = { i = p.i, x = p.x, y = p.y } end
  leg = { target = { i = target.i, x = target.x, y = target.y }, from = line[1], straight = straight,
    line = line, walked = 0, t0 = now(), last = here, trail = { line[1] }, map = D:MapPos(here) }
end

local function finish()
  local L = leg
  leg = nil
  if not L or L.walked < MIN_LEG then return end
  local c = store()
  if not c then return end
  -- detour factor for the zone
  local ratio = math.max(1, math.min(3, L.walked / L.straight))
  if L.map then
    local e = c.pathk[L.map] or { r = 0, n = 0 }
    e.r, e.n = e.r + ratio, e.n + 1
    if e.n > 40 then e.r, e.n = e.r * 0.5, e.n * 0.5 end      -- recent walks count most
    c.pathk[L.map] = e
  end
  -- the line went where you couldn't: spots on it far from everything you walked
  if ratio < DETOUR then return end
  local av = c.avoid[L.from.i] or {}
  c.avoid[L.from.i] = av
  local marked = 0
  -- a walk much longer than the line is strong evidence (a mountain range, a zone wall): one such walk
  -- is enough for the next route to go round
  local inc = ratio >= 2 and 3 or (ratio >= 1.5 and 2 or 1)
  for k = 1, #L.line - 1 do
    local a, b = L.line[k], L.line[k + 1]
    local segLen = D.Dist(a, b)
    local n = math.max(1, math.floor(segLen / CELL))
    for j = 1, n - 1 do
      local px, py = a.x + (b.x - a.x) * j / n, a.y + (b.y - a.y) * j / n
      local near = false
      for _, w in ipairs(L.trail) do
        local dx, dy = w.x - px, w.y - py
        if dx * dx + dy * dy <= OFF_LINE * OFF_LINE then near = true; break end
      end
      if not near and marked < 120 then
        local key = cellKey(px, py)
        av[key] = math.min(5, (av[key] or 0) + inc)
        marked = marked + 1
      end
    end
  end
  if marked > 0 and Q.Nav and Q.Nav.Forget then Q.Nav:Forget() end
  PL.lastLeg = { ratio = ratio, marked = marked, map = L.map, walked = L.walked, straight = L.straight, at = now() }
  if marked > 0 then
    Q:Print(("learned from that walk: %.1fx longer than the line, %d spots to go round next time"):format(ratio, marked))
  end
end

-- every half second: add the ground you covered; arrived = done
local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.5 then return end
  local dt = acc
  acc = 0
  PL:Tick(dt)
end)
function PL:Tick(dt)
  if not leg then return end
  if not grounded() then leg = nil; return end
  local here = D:PlayerPos()
  -- somewhere without a place on the world (inside Blackrock Mountain, a cave) or another continent /
  -- an instance (Blackrock Depths on the way through): the walk pauses, it isn't thrown away
  if not here or here.i ~= leg.target.i then leg.away = true; return end
  local d = D.Dist(here, leg.last)
  if leg.away then
    leg.away = nil
    leg.walked = leg.walked + d                                    -- (at least the straight hop across)
  elseif d < 60 * (dt or 0.5) + 5 then leg.walked = leg.walked + d end   -- not a teleport
  leg.last = here
  local tl = leg.trail[#leg.trail]
  if D.Dist(here, tl) >= 20 and #leg.trail < MAX_TRAIL then leg.trail[#leg.trail + 1] = { x = here.x, y = here.y } end
  if D.Dist(here, leg.target) <= 30 then finish() return end
  if now() - leg.t0 > 3600 then leg = nil end             -- an hour: you did something else (a long way round can take a while)
end

-- a new target from the guide = a new walk (the old one only counts if you got there)
Q:On("QC_TARGET_CHANGED", function()
  Q.Throttle("pathleg", 0.3, function()
    local p = Q.Guide and Q.Guide.Target and Q.Guide:Target()
    -- the same place give or take (the objective spot moved a little): the same walk
    if leg and p and leg.target.i == p.i and D.Dist(leg.target, p) < 150 then return end
    if leg then
      local here = D:PlayerPos()
      if here and D.Dist(here, leg.target) <= 45 then finish() end
    end
    start(p)
  end)
end)
Q:On("PLAYER_DEAD", function() leg = nil end)

Q:Command("paths", "what Questicus learned about walking vs the route line", function()
  local c = QuesticusCollect or {}
  local n, cells = 0, 0
  for _, e in pairs(c.pathk or {}) do n = n + (e.n or 0) end
  for _, t in pairs(c.avoid or {}) do for _ in pairs(t) do cells = cells + 1 end end
  local here = D:PlayerPos()
  local map = here and D:MapPos(here)
  Q:Print(("learned from %d walks; %d spots where the line didn't work; walking here takes x%.2f the straight line")
    :format(math.floor(n), cells, PL.Factor(map)))
  local L = PL.lastLeg
  if L then
    Q:Print(("last walk learned %d s ago: %d yd walked for %d yd of line (x%.1f), %d spots marked")
      :format(math.floor(now() - (L.at or now())), math.floor(L.walked or 0), math.floor(L.straight or 0), L.ratio or 1, L.marked or 0))
  end
  if leg then
    Q:Print(("walk in progress: %d yd so far, %d yd from the target%s"):format(math.floor(leg.walked),
      math.floor(D.Dist(D:PlayerPos() or leg.last, leg.target)), leg.away and " (paused: not on the map)" or ""))
  end
end)
