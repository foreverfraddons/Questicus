-- Questicus zones: pick which zones the route may use. A button in the guide's title bar opens a list
-- of the zones with quests for your level; untick one and its quests stay off the route (quests you
-- already have there still get handed in). Kept per character (Q.char.zoneOff[uiMap] = true).
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local Z = {}
Q.Zones = Z

local win
local rows = {}
Z.rows = rows

local function zoneName(map)
  local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return (info and info.name) or ("Zone " .. tostring(map))
end

-- zones with quests in your level range (and the ones your log quests are in), with counts
function Z:List()
  local lv = Q.player.level or 1
  local lo, hi = QS.GreyLevel(lv) + 1, lv + (Q.prefs.levelRange or 2) + 1
  local count, inLog = {}, {}
  for _, id in ipairs(QS.pool or {}) do
    local info = QS:Info(id)
    if info and info.level >= lo and info.level <= hi and not QS.done[id] then
      local z = P.QuestZone(id)
      if z then count[z] = (count[z] or 0) + 1 end
    end
  end
  for id in pairs(QS.log or {}) do
    local z = P.QuestZone(id)
    if z then inLog[z] = (inLog[z] or 0) + 1; count[z] = count[z] or 0 end
  end
  local off = Q.char.zoneOff or {}
  for z in pairs(off) do count[z] = count[z] or 0 end
  local out = {}
  for z, n in pairs(count) do out[#out + 1] = { map = z, name = zoneName(z), n = n, log = inLog[z] or 0 } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, win.body)
  r:SetHeight(20)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.06) end
  r.box = r:CreateTexture(nil, "ARTWORK")
  r.box:SetSize(14, 14)
  r.box:SetPoint("LEFT", 6, 0)
  r.tick = r:CreateTexture(nil, "OVERLAY")
  r.tick:SetSize(18, 18)
  r.tick:SetPoint("CENTER", r.box, "CENTER", 1, 0)
  r.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  r.name = T.Text(r, 12, T.c.text)
  r.name:SetPoint("LEFT", r.box, "RIGHT", 8, 0)
  r.n = T.Text(r, 11, T.c.dim)
  r.n:SetPoint("RIGHT", -8, 0)
  r:SetScript("OnClick", function(self)
    if not self.z then return end
    Q.char.zoneOff = Q.char.zoneOff or {}
    Q.char.zoneOff[self.z.map] = (not Q.char.zoneOff[self.z.map]) or nil
    Z:Refresh()
    Q.Throttle("zonesReplan", 0.6, function() P:BuildAsync() end)
  end)
  rows[i] = r
  return r
end

function Z:Refresh()
  if not (win and win:IsShown()) then return end
  local list = Z:List()
  local off = Q.char.zoneOff or {}
  local y = 0
  for i, z in ipairs(list) do
    local r = row(i)
    r.z = z
    local on = not off[z.map]
    r.box:SetTexture("Interface\\Buttons\\WHITE8x8")
    r.box:SetVertexColor(0.12, 0.1, 0.08, 1)
    r.tick:SetShown(on)
    r.name:SetText(on and z.name or Q.Color(T.HEX.dim, z.name .. "  (off)"))
    r.n:SetText(z.n .. " quest" .. (z.n == 1 and "" or "s") .. (z.log > 0 and ("  - " .. z.log .. " in your log") or ""))
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
    y = y + 20
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win.body:SetHeight(math.max(1, y))
  win:SetHeight(math.min(700, 62 + y + 40))
  return list
end

function Z:Show()
  if not win then
    win = T.Window("QuesticusZones", 360, 200, "Zones", nil)
    win.note = T.Text(win, 11, T.c.dim)
    win.note:SetPoint("TOPLEFT", 14, -32)
    win.note:SetPoint("RIGHT", -14, 0)
    win.note:SetText("Untick a zone to keep its quests off your route.")
    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", 8, -52)
    win.body:SetPoint("RIGHT", -8, 0)
    win.body:SetHeight(1)
    win.all = T.Button(win, "All zones on", 110, 20)
    win.all:SetPoint("BOTTOMRIGHT", -12, 10)
    win.all:SetScript("OnClick", function()
      Q.char.zoneOff = {}
      Z:Refresh()
      P:BuildAsync()
    end)
  end
  if Q.Bosses then Q.Bosses.Front(win) else win:Show() end
  return Z:Refresh()
end

Q:Command("zones", "choose which zones the route may use", function() Z:Show() end)
