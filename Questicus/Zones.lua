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

-- every questing zone of the world (ForeverDB's zone table, Questicus Maps' level table and WoW Forever's
-- new zones), with its level range; zones for your level first. [uiMap] = { lo, hi }
Z.FOREVER = {
  [2521] = { 1, 12 },    -- Zephras Isle (Skyborne start)
  [2548] = { 35, 45 },   -- The Riverglades
  [2652] = { 40, 53 },   -- Shen'dralas (sources say 40-45 or 45-53)
  [2482] = { 58, 60 },   -- Mount Hyjal (level 60)
}
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
function Z.Ranges()
  local out = {}
  local spf = D.db and D.db.spf
  for map, z in pairs((spf and spf.Zones) or {}) do out[map] = { z.low, z.high } end
  local ML = _G.QuesticusMap and _G.QuesticusMap.MapLevels
  for map, r in pairs(ML or {}) do out[map] = out[map] or { r[1], r[2] } end
  for map, r in pairs(Z.FOREVER) do out[map] = out[map] or { r[1], r[2] } end
  return out
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
  local ranges = Z.Ranges()
  for z in pairs(ranges) do if not CITY[z] then count[z] = count[z] or 0 end end
  local out = {}
  for z, n in pairs(count) do
    local r = ranges[z]
    local fits = (n > 0) or (inLog[z] or 0) > 0 or (r and lv >= r[1] - 2 and lv <= r[2] + 2)
    out[#out + 1] = { map = z, name = zoneName(z), n = n, log = inLog[z] or 0, lo = r and r[1], hi = r and r[2],
      fits = fits and true or false, new = Z.FOREVER[z] ~= nil }
  end
  table.sort(out, function(a, b)
    if a.fits ~= b.fits then return a.fits end
    if (a.lo or 99) ~= (b.lo or 99) then return (a.lo or 99) < (b.lo or 99) end
    return a.name < b.name
  end)
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
    local lvl = z.lo and Q.Color(T.HEX.dim, (" %d-%d"):format(z.lo, z.hi)) or ""
    local nm = z.name .. (z.new and Q.Color(T.HEX.good, " new") or "")
    r.name:SetText((on and (z.fits and nm or Q.Color(T.HEX.dim, z.name)) or Q.Color(T.HEX.dim, z.name .. "  (off)")) .. lvl)
    r.n:SetText((z.n > 0 and (z.n .. " quest" .. (z.n == 1 and "" or "s")) or "") .. (z.log > 0 and ("  - " .. z.log .. " in your log") or ""))
    if i > 1 and list[i - 1].fits and not z.fits then y = y + 14 end     -- a gap before the zones for other levels
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
    y = y + 20
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  win.body:SetHeight(math.max(1, y))
  win:SetHeight(math.min(640, 62 + y + 40))
  return list
end

function Z:Show()
  if not win then
    win = T.Window("QuesticusZones", 360, 200, "Zones", nil)
    win.note = T.Text(win, 11, T.c.dim)
    win.note:SetPoint("TOPLEFT", 14, -32)
    win.note:SetPoint("RIGHT", -14, 0)
    win.note:SetText("Untick a zone to keep its quests off your route. Zones for your level first.")
    win.scroll = CreateFrame("ScrollFrame", nil, win)
    win.scroll:SetPoint("TOPLEFT", 8, -52)
    win.scroll:SetPoint("BOTTOMRIGHT", -8, 38)
    win.body = CreateFrame("Frame", nil, win.scroll)
    win.body:SetSize(344, 1)
    win.scroll:SetScrollChild(win.body)
    if win.scroll.EnableMouseWheel then win.scroll:EnableMouseWheel(true) end
    win.scroll:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, (win.body:GetHeight() or 0) - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
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
