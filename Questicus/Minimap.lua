-- Questicus minimap button: left-click the guide, shift-click the arrow, right-click options.
-- Drag it around the minimap edge; the spot is saved in QuesticusDB.minimap.angle.
local Q = Questicus
local L = Q.L
local MM = {}
Q.Minimap = MM

local btn

local function place()
  if not btn then return end
  local deg = Q.db.minimap.angle or 200
  local CC = _G.CommandCenter
  local x, y
  if CC and CC.MinimapEdge then
    x, y = CC.MinimapEdge(deg, 10)   -- Command Center's minimap: follows its shape (square / rounded / round)
  else
    local a, r = math.rad(deg), (Minimap:GetWidth() / 2) + 10
    x, y = math.cos(a) * r, math.sin(a) * r
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  cx, cy = cx / s, cy / s
  Q.db.minimap.angle = math.deg((math.atan2 or math.atan)(cy - my, cx - mx)) % 360
  place()
end

local function build()
  btn = CreateFrame("Button", "QuesticusMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(Q.MEDIA .. "icon")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  btn.icon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if Q.ShowOptions then Q:ShowOptions() end
    elseif button == "MiddleButton" or IsShiftKeyDown() then
      if Q.ToggleArrow then Q:ToggleArrow() end
    else
      if Q.ToggleGuide then Q:ToggleGuide() end
    end
  end)
  btn:SetScript("OnDragStart", function(s) s:SetScript("OnUpdate", dragUpdate) end)
  btn:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
  btn:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_LEFT")
    GameTooltip:AddLine("Questicus", 0.25, 0.82, 0.79)
    GameTooltip:AddLine(L["Left-click: show / hide the guide"], 1, 1, 1)
    GameTooltip:AddLine(L["Shift-click: show / hide the arrow"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag to move"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local CC = _G.CommandCenter
  if CC and CC.OnMinimapChange then CC:OnMinimapChange(place) end
  place()
end

function MM:Refresh()
  if Q.db.minimap.hide then
    if btn then btn:Hide() end
    return
  end
  if not btn then build() end
  place()
  btn:Show()
end

Q:On("PLAYER_LOGIN", function() MM:Refresh() end)
Q:Command("minimap", "show / hide the minimap button", function()
  Q.db.minimap.hide = not Q.db.minimap.hide
  MM:Refresh()
end)
