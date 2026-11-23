-- Questicus waypoint arrow: points at the current step's target, shows the distance and the step.
local Q = Questicus
local T, D = Q.T, Q.Data
local A = {}
Q.Arrow = A

local atan2 = math.atan2 or math.atan
local frame

local function build()
  local cfg = Q.db.arrow
  frame = CreateFrame("Button", "QuesticusArrow", UIParent)
  frame:SetSize(64, 64)
  frame:SetScale(cfg.scale or 1)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("RightButtonUp")
  if cfg.at then frame:SetPoint(cfg.at[1], UIParent, cfg.at[1], cfg.at[2], cfg.at[3])
  else frame:SetPoint("TOP", 0, -140) end
  frame:SetScript("OnDragStart", function(s) if not cfg.locked then s:StartMoving() end end)
  frame:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    local p, _, _, x, y = s:GetPoint()
    cfg.at = { p, x, y }
  end)
  frame:SetScript("OnClick", function() if Q.ShowOptions then Q:ShowOptions() end end)
  frame.glow = frame:CreateTexture(nil, "BACKGROUND")
  frame.glow:SetTexture(Q.MEDIA .. "glow")
  frame.glow:SetPoint("CENTER")
  frame.glow:SetSize(92, 92)
  frame.glow:SetVertexColor(Q.T.c.accent[1], Q.T.c.accent[2], Q.T.c.accent[3], 0.35)
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetTexture(Q.MEDIA .. "arrow")
  frame.arrow:SetAllPoints()
  frame.here = frame:CreateTexture(nil, "ARTWORK")
  frame.here:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  frame.here:SetSize(40, 40)
  frame.here:SetPoint("CENTER")
  frame.here:Hide()
  frame.dist = T.Text(frame, 13, T.c.text, "OUTLINE")
  frame.dist:SetPoint("TOP", frame, "BOTTOM", 0, -2)
  frame.dist:SetJustifyH("CENTER")
  frame.label = T.Text(frame, 11, T.c.gold, "OUTLINE")
  frame.label:SetPoint("TOP", frame.dist, "BOTTOM", 0, -2)
  frame.label:SetJustifyH("CENTER")
  frame.label:SetWidth(240)
  frame.label:SetWordWrap(false)
  frame:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Questicus arrow", 0.25, 0.82, 0.79)
    GameTooltip:AddLine("Drag to move. Right-click for options.", 1, 1, 1)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local acc = 0
  frame:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.05 then return end
    acc = 0
    -- on a flight path nothing is measured: "in flight" once, back to normal the moment you land
    if Q.OnTaxi() then
      if not frame.inFlight then
        frame.inFlight = true
        frame.arrow:Hide(); frame.here:Hide()
        frame.dist:SetText("in flight")
      end
      return
    end
    frame.inFlight = nil
    A:Update()
  end)
end

local function shortText(s)
  if not s then return "" end
  if s.type == "accept" then return "Accept: " .. (s.title or "")
  elseif s.type == "turnin" then return "Turn in: " .. (s.title or "")
  elseif s.type == "complete" then
    -- name what the arrow points at: the objective and its quest ("Young Paletusk - Drive Them Back")
    local t = Q.Guide.targetOf
    if t and t.id then
      local info = Q.Quests:Info(t.id)
      local m = Q.Planner.Meta(t.id)
      local l = m and m.lines and m.lines[t.li]
      local what = (l and l.name) or (t.key and t.key:sub(1, 1) ~= "t" and D:Name(t.key)) or nil
      local title = (info and info.title) or ""
      local more = (s.titles and #s.titles > 1) and (" +" .. (#s.titles - 1)) or ""
      return (what and (what .. " - ") or "") .. title .. more
    end
    return (s.titles and s.titles[1] or "Objectives") .. ((s.titles and #s.titles > 1) and (" +" .. (#s.titles - 1)) or "")
  elseif s.type == "buy" then return "Buy at " .. (s.npc or "vendor") end
  return ""
end

function A:Update()
  local p, s = Q.Guide:Target()
  local here = D:PlayerPos()
  if not p or not here or not Q.db.arrow.shown or (Q.CollectOnly and Q.CollectOnly()) then frame:Hide(); return end
  frame:Show()
  frame.label:SetText(shortText(s))
  if p.i ~= here.i then
    frame.arrow:Hide(); frame.here:Hide()
    frame.dist:SetText("other continent")
    return
  end
  local d = D.Dist(here, p)
  -- the step's mob is right in front of you: no direction to a marker, just say so
  local v = s and s.type == "complete" and Q.Guide.inView
  if v and v.close then
    frame.arrow:Hide(); frame.here:Show()
    frame.dist:SetText((D:Name(v.src) or "target") .. " - right here")
    return
  end
  -- aim along the less obstructed path (Nav.lua), not straight through walls and water
  local wp = (Q.Nav and Q.Nav:Next(here, p)) or p
  local dx, dy = wp.x - here.x, wp.y - here.y
  -- "here" only when you're really on it (the spot's own check starts there: Spots.lua)
  if d < 5 then
    frame.arrow:Hide(); frame.here:Show()
    frame.dist:SetText("here")
    return
  end
  frame.here:Hide(); frame.arrow:Show()
  local facing = GetPlayerFacing and GetPlayerFacing()
  if not facing then
    frame.arrow:SetRotation(0)
    frame.dist:SetText(("%d yd"):format(math.floor(d)))
    return
  end
  local rel = atan2(dy, dx) - facing
  frame.arrow:SetRotation(rel)
  -- green straight ahead, gold to the side, red behind
  local a = math.abs(((rel + math.pi) % (2 * math.pi)) - math.pi)
  local f = a / math.pi
  if f < 0.5 then frame.arrow:SetVertexColor(0.3 + f * 1.4, 1, 0.45 - f * 0.5)
  else frame.arrow:SetVertexColor(1, 1 - (f - 0.5) * 1.4, 0.2) end
  frame.dist:SetText(("%d yd"):format(math.floor(d)))
end

function A:Refresh()
  if not frame then build() end
  frame:SetScale(Q.db.arrow.scale or 1)
  A:Update()
end

Q:On("QC_TARGET_CHANGED", function() if Q.char and Q.char.surveyDone then A:Refresh() end end)
Q:On("QC_PLAN_UPDATED", function() if Q.char and Q.char.surveyDone and Q.db.arrow.shown then A:Refresh() end end)
function Q:ToggleArrow()
  Q.db.arrow.shown = not Q.db.arrow.shown
  A:Refresh()
end
Q:Command("arrow", "show / hide the arrow", function()
  Q.db.arrow.shown = not Q.db.arrow.shown
  A:Refresh()
end)
