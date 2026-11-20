-- Questicus map pin: puts the game's own waypoint on the current objective, so it shows on the
-- world map, the minimap and (with tracking on) in the world. Follows the route automatically.
local Q = Questicus
local D = Q.Data
local W = {}
Q.Waypoint = W

local last

local function canPin(map)
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
  if C_Map.CanSetUserWaypointOnMap then
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, map)
    return ok and can
  end
  return true
end

-- pin a point (from Data: world point with or without map position). Returns true when pinned.
function W:Pin(pt, track)
  if not pt then return false end
  local map, mx, my = D:MapPos(pt)
  if not map or not canPin(map) then return false end
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, mx, my))
  -- (super tracking set again makes the game rebuild its quest log - every header shut and opened -
  -- so only when it isn't on already)
  local on = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
  if ok and track ~= false and not on and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
  if ok then last = pt end
  return ok, map
end

function W:Clear()
  if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
  last = nil
end

-- automatic: re-pin when the route moves on to another step (or its spots are far apart). Not each
-- time the nearest spot of the same step changes: every new pin makes the game redo its quest log
-- (all headers shut and open again) and its map pins.
local lastStep
local function stepKey(s)
  return s and ((s.type or "") .. ":" .. table.concat(s.quests or {}, ",")) or nil
end
function W:Follow()
  if not (Q.db.pins.autoPin ~= false and Q.char and Q.char.surveyDone) then return end
  if Q.CollectOnly and Q.CollectOnly() then return end
  local p, s = Q.Guide:Target()
  if not p then return end
  local key = stepKey(s)
  if last and last.i == p.i then
    local d = D.Dist(last, p)
    if d < 60 or (key == lastStep and d < 400) then return end
  end
  if W:Pin(p) then lastStep = key end
end

Q:On("QC_TARGET_CHANGED", function() Q.Throttle("autopin", 0.5, function() W:Follow() end) end)
Q:On("QC_PLAN_UPDATED", function() Q.Throttle("autopin", 0.5, function() W:Follow() end) end)
