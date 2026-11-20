-- Questicus patrol recorder: for mobs that walk a path (Ghostmaw ...). Target the mob, press Start
-- and follow it around its route; Stop saves the path. It's used straight away (drawn as a line on
-- the map instead of a cloud of icons) and goes to ForeverDB with your recordings, so everyone gets it.
--   /qc patrol   - open the recorder
local Q = Questicus
local T, D = Q.T, Q.Data
local PT = {}
Q.Patrol = PT

local STEP = 10            -- yards between recorded points
local frame, rec

local function here()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x or x <= 0 or y <= 0 then return end
  return map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

local function targetNPC()
  local kind, id = Q.ParseGUID(Q.UnitGUID("target"))
  if kind == "Creature" or kind == "Vehicle" then return id, Q.UnitName("target") end
end

function PT:Start()
  local id, name = targetNPC()
  if not id then Q:Print("target the mob that patrols first, then press Start"); return false end
  rec = { npc = id, name = name or D:Name("c" .. id), pts = {}, last = nil, map = nil }
  PT:Refresh()
  return true
end

function PT:Tick()
  if not rec then return end
  local p = D:PlayerPos()
  if not p then return end
  if rec.last and rec.last.i == p.i and D.Dist(rec.last, p) < STEP then return end
  local map, x, y = here()
  if not map then return end
  if rec.map and rec.map ~= map then return end     -- one map per path
  rec.map = map
  rec.pts[#rec.pts + 1], rec.pts[#rec.pts + 2] = x, y
  rec.last = p
  PT:Refresh()
end

function PT:Stop(save)
  if not rec then return end
  local n = #rec.pts / 2
  if save and n >= 3 then
    QuesticusCollect = QuesticusCollect or {}
    QuesticusCollect.patrol = QuesticusCollect.patrol or {}
    QuesticusCollect.patrol["c:" .. rec.npc] = { [rec.map] = rec.pts }
    D:ForgetPatrol("c" .. rec.npc)
    Q:Print(("patrol path of %s saved (%d points) - shown on the map and sent to ForeverDB with your recordings"):format(rec.name, n))
    if Q.Pins and Q.Pins.RefreshWorld then Q.Pins:RefreshWorld() end
  elseif save then
    Q:Print("not enough of the path yet - follow the mob a bit longer")
    return
  end
  rec = nil
  PT:Refresh()
end

function PT:Refresh()
  if not frame then return end
  if rec then
    frame.status:SetText(("Recording %s: %d points\nFollow it all the way round, then Stop."):format(rec.name, #rec.pts / 2))
  else
    frame.status:SetText("Target a mob that walks a path, press Start and follow it around its route.")
  end
  frame.start:SetShown(not rec)
  frame.stop:SetShown(rec ~= nil)
  frame.cancel:SetShown(rec ~= nil)
end

function PT:Show()
  if not frame then
    Q.db.patrolWin = Q.db.patrolWin or {}
    frame = T.Window("QuesticusPatrol", 300, 120, "Patrol recorder", Q.db.patrolWin)
    frame.status = T.Text(frame, 12)
    frame.status:SetPoint("TOPLEFT", 12, -34)
    frame.status:SetPoint("RIGHT", -12, 0)
    frame.status:SetJustifyH("LEFT")
    frame.start = T.Button(frame, "Start", 90, 22)
    frame.start:SetPoint("BOTTOMLEFT", 12, 10)
    frame.start:SetScript("OnClick", function() PT:Start() end)
    frame.stop = T.Button(frame, "Stop and save", 120, 22)
    frame.stop:SetPoint("BOTTOMLEFT", 12, 10)
    frame.stop:SetScript("OnClick", function() PT:Stop(true) end)
    frame.cancel = T.Button(frame, "Cancel", 80, 22)
    frame.cancel:SetPoint("LEFT", frame.stop, "RIGHT", 6, 0)
    frame.cancel:SetScript("OnClick", function() PT:Stop(false) end)
  end
  frame:Show()
  PT:Refresh()
end

-- keeps recording even with the window closed
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, el)
  if not rec then return end
  acc = acc + el
  if acc < 0.5 then return end
  acc = 0
  PT:Tick()
end)

Q:Command("patrol", "record the path of a mob that walks around (Ghostmaw ...)", function() PT:Show() end)
