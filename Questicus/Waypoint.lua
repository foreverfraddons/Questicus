-- Questicus map pin: puts the game's own waypoint on the current objective, so it shows on the
-- world map, the minimap and in the world (Beacon.lua). Follows the route automatically.
-- Your own pins win: a pin you put on the map or the minimap, /way, or a map link in chat is
-- followed until you get there or clear it, then the route's pin comes back.
local Q = Questicus
local D = Q.Data
local W = {}
Q.Waypoint = W

local last                  -- the route point Questicus pinned
local setAt                 -- { m, x, y } of the last waypoint Questicus put down itself
local cfg = function() return Q.db.beacon end

local function canPin(map)
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
  if C_Map.CanSetUserWaypointOnMap then
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, map)
    return ok and can
  end
  return true
end
local function track()
  local on = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
  if not on and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
end
local function setRaw(map, mx, my)
  if not canPin(map) then return false end
  setAt = { m = map, x = mx, y = my, t = GetTime() }
  return pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, mx, my))
end
local function current()
  local wp = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
  if not wp then return end
  local x, y = wp.position.x, wp.position.y
  if wp.position.GetXY then x, y = wp.position:GetXY() end
  return wp.uiMapID, x, y
end
local function same(m, x, y, m2, x2, y2)
  return m and m == m2 and math.abs(x - x2) < 0.0005 and math.abs(y - y2) < 0.0005
end
-- is the waypoint on the map the one Questicus put there?
function W:IsOurs()
  if W.manual then return false end
  local m, x, y = current()
  return m and setAt and same(m, x, y, setAt.m, setAt.x, setAt.y) or false
end

-- pin a point (from Data: world point with or without map position). Returns true when pinned.
function W:Pin(pt, trackIt)
  if not pt then return false end
  local map, mx, my = D:MapPos(pt)
  if not map or not canPin(map) then return false end
  if Q.Trace then Q.Trace("Questicus pins the waypoint") end
  local ok = setRaw(map, mx, my)
  -- (super tracking set again makes the game rebuild its quest log - every header shut and opened -
  -- so only when it isn't on already)
  if ok and trackIt ~= false then track() end
  if ok then last = pt end
  return ok, map
end

function W:Clear()
  if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
  last = nil
end

-- ------------------------------------------------------------------ your own pins
-- W.manual = { name, m, x, y, i, wx, wy } while one of yours is followed; W.queue: more from /way
W.queue = {}
local function worldOf(m, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos) then return end
  local i, wx, wy = D:WorldPos(m, x, y)
  return i, wx, wy
end
-- put down one of your own pins (from /way, the minimap, ...): followed until you're there
function W:PinUser(m, x, y, name, quiet)
  if not canPin(m) then
    if not quiet then Q:Print("Can't put a waypoint on that map.") end
    return false
  end
  local i, wx, wy = worldOf(m, x, y)
  W.manual = { name = name, m = m, x = x, y = y, i = i, wx = wx, wy = wy }
  local ok = setRaw(m, x, y)
  if ok then track() end
  if Q.Beacon then Q.Beacon.Play("show") end
  return ok
end
-- the next one from a /way list, or back to the route
function W:NextUser()
  W.manual = nil
  local n = table.remove(W.queue, 1)
  if n then return W:PinUser(n.m, n.x, n.y, n.name, true) end
  W:Clear()
  W:Follow(true)
end
-- right-click on the in-world marker / /way clear
function W:Dismiss()
  if W.manual then W.queue = {}; W:NextUser(); return end
  if W.onCorpse then return end
  local _, s = Q.Guide:Target()
  W.dismissed = W.stepKey(s) or "?"
  W:Clear()
end

-- ------------------------------------------------------------------ following the route
local lastStep
function W.stepKey(s)
  return s and ((s.type or "") .. ":" .. table.concat(s.quests or {}, ",")) or nil
end
local stepKey = W.stepKey
function W:Follow(force)
  if not (Q.db.pins.autoPin ~= false and Q.char and Q.char.surveyDone) then return end
  if Q.CollectOnly and Q.CollectOnly() then return end
  -- a ghost: the waypoint goes on your corpse (once), and back on the step when you're alive
  local body = Q.Arrow and Q.Arrow.Corpse and Q.Arrow.Corpse()
  if body then
    if W.onCorpse and W.onCorpse.i == body.i and D.Dist(W.onCorpse, body) < 5 then return end
    if W:Pin(body) then W.onCorpse = body; lastStep = nil end
    return
  end
  if W.onCorpse then W.onCorpse = nil; last = nil; lastStep = nil end
  if W.manual then return end                      -- one of your own pins: that first
  local p, s = Q.Guide:Target()
  if not p then return end
  local key = stepKey(s)
  -- cleared by hand: not again until the route moves on to another step
  if W.dismissed then
    if W.dismissed == key then return end
    W.dismissed = nil
  end
  if force then last, lastStep = nil, nil end
  -- the arrow moved off a spot that's on cooldown (used / empty): follow it, at most every 5 s
  local cooled = last and Q.Spots and Q.Spots.OnCooldown(last) and GetTime() - (W.lastCooled or 0) > 5
  if last and last.i == p.i and not cooled then
    local d = D.Dist(last, p)
    if d < 60 or (key == lastStep and d < 400) then return end
  end
  if cooled then W.lastCooled = GetTime() end
  if W:Pin(p) then lastStep = key end
end

Q:On("QC_TARGET_CHANGED", function() Q.Throttle("autopin", 0.5, function() W:Follow() end) end)
Q:On("QC_PLAN_UPDATED", function() Q.Throttle("autopin", 0.5, function() W:Follow() end) end)
-- released / alive again: the waypoint moves to your corpse / back to the step
for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
  Q:On(ev, function() Q.After(0.5, function() W:Follow() end) end)
end

-- ------------------------------------------------------------------ pins put down some other way
-- (the world map, a map link in chat): yours - followed (and tracked, if you want that)
local linkAt = 0
if hooksecurefunc and SetItemRef then
  hooksecurefunc("SetItemRef", function(link)
    if type(link) == "string" and link:find("^worldmap") then linkAt = GetTime() end
  end)
end
Q:On("USER_WAYPOINT_UPDATED", function()
  Q.After(0, function()
    local m, x, y = current()
    if not m then
      -- cleared (by you, or the game on arrival): back to the route
      if W.manual then W.manual = nil; W.queue = {}; Q.After(0.3, function() W:Follow(true) end) end
      return
    end
    if setAt and same(m, x, y, setAt.m, setAt.x, setAt.y) then return end   -- Questicus' own
    local fromLink = GetTime() - linkAt < 2
    local i, wx, wy = worldOf(m, x, y)
    W.manual = { name = fromLink and "Linked pin" or "Map pin", m = m, x = x, y = y, i = i, wx = wx, wy = wy }
    local c = cfg()
    if (fromLink and c.trackLinks ~= false) or (not fromLink and c.trackPlaced ~= false) then track() end
  end)
end)

-- your own pin reached: the next one from the list, or back to the route
local acc = 0
local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.5 then return end
  acc = 0
  local man = W.manual
  if not (man and man.wx) then return end
  local here = D:PlayerPos()
  if here and here.i == man.i and D.Dist(here, { x = man.wx, y = man.wy }) <= math.max(5, (cfg().hideAt or 4) + 2) then
    Q:Print(("Reached %s."):format(man.name or "your waypoint"))
    W:NextUser()
  end
end)
