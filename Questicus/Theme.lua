-- Questicus UI kit: rounded dark panels with gold trim, drawn like Command Center.
local Q = Questicus
local T = {}
Q.T = T

local WHITE = "Interface\\Buttons\\WHITE8x8"
T.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- Colours follow Command Center's look (its "Horde war-camp" theme by default); with Command Center
-- installed, its current theme is used (T.ApplyCommandCenter, at login).
local function hexc(h, a)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a }
end
T.c = {
  bg = hexc("1b120d", 0.95),
  bg2 = hexc("271a12", 0.97),
  line = hexc("6b4a2e", 0.9),
  accent = hexc("e0b04a"),
  gold = hexc("e0b04a"),
  text = hexc("f3e3c3"),
  dim = hexc("b79f80"),
  good = hexc("7fdc5a"),
  bad = { 1, 0.38, 0.32 },
  head1 = hexc("3c1712"), head2 = hexc("1e0f0a"),
}
T.HEX = { accent = "e0b04a", gold = "e0b04a", dim = "b79f80", good = "7fdc5a", bad = "ff6152", white = "f3e3c3" }

local function tohex(c)
  local function b(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
  return ("%02x%02x%02x"):format(b(c[1]), b(c[2]), b(c[3]))
end
-- take Command Center's current theme colours (when it is installed)
function T.ApplyCommandCenter()
  local CC = _G.CommandCenter
  local ok, th = pcall(function() return CC and CC.UI and CC.UI.Theme and CC.UI:Theme() end)
  if not ok or type(th) ~= "table" or not th.bg then return false end
  local function set(k, v, a) if v then T.c[k] = { v[1], v[2], v[3], a } end end
  set("bg", th.bg, 0.95); set("bg2", th.panel, 0.97); set("line", th.edge, 0.9)
  set("accent", th.gold); set("gold", th.gold); set("text", th.text); set("dim", th.muted); set("good", th.live)
  set("head1", th.head1); set("head2", th.head2)
  T.HEX.accent, T.HEX.gold, T.HEX.dim = tohex(T.c.accent), tohex(T.c.gold), tohex(T.c.dim)
  T.HEX.good, T.HEX.white = tohex(T.c.good), tohex(T.c.text)
  T.fromCC = true
  return true
end

local function rgba(t) return t[1], t[2], t[3], t[4] or 1 end

function T.Fill(f, color, layer)
  local tex = f:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetTexture(WHITE)
  tex:SetVertexColor(rgba(color))
  tex:SetAllPoints()
  return tex
end

-- Rounded corners, the same way Command Center draws them: a 9-slice of Media\rfill (fill) and
-- Media\redge1 / redge2 (border), 64px textures with a 24px corner region.
local RC = 24 / 64
local SLICE = {
  TL = { 0, RC, 0, RC }, T = { RC, 1 - RC, 0, RC }, TR = { 1 - RC, 1, 0, RC },
  L = { 0, RC, RC, 1 - RC }, C = { RC, 1 - RC, RC, 1 - RC }, R = { 1 - RC, 1, RC, 1 - RC },
  BL = { 0, RC, 1 - RC, 1 }, B = { RC, 1 - RC, 1 - RC, 1 }, BR = { 1 - RC, 1, 1 - RC, 1 },
}
T.RADIUS = 6
-- a set of 9 textures that acts like one: :SetVertexColor, :Show, :Hide, :SetShown
local Set = {}
Set.__index = Set
function Set:SetVertexColor(r, g, b, a) for _, t in pairs(self.p) do t:SetVertexColor(r, g, b, a or 1) end end
function Set:SetShown(on) for _, t in pairs(self.p) do t:SetShown(on) end end
function Set:Show() self:SetShown(true) end
function Set:Hide() self:SetShown(false) end
function Set:Layout()
  local f, r, i, p = self.f, self.r, self.inset, self.p
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  if w > 0 and h > 0 then r = math.max(1, math.min(r, math.floor(math.min(w, h) / 2))) end
  local function P(t, ...) if t then t:ClearAllPoints(); t:SetPoint(...) end end
  P(p.TL, "TOPLEFT", f, "TOPLEFT", i, -i); p.TL:SetSize(r, r)
  P(p.TR, "TOPRIGHT", f, "TOPRIGHT", -i, -i); p.TR:SetSize(r, r)
  P(p.BL, "BOTTOMLEFT", f, "BOTTOMLEFT", i, i); p.BL:SetSize(r, r)
  P(p.BR, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -i, i); p.BR:SetSize(r, r)
  for _, k in ipairs({ "T", "B", "L", "R", "C" }) do if p[k] then p[k]:ClearAllPoints() end end
  p.T:SetPoint("TOPLEFT", p.TL, "TOPRIGHT"); p.T:SetPoint("BOTTOMRIGHT", p.TR, "BOTTOMLEFT")
  p.B:SetPoint("TOPLEFT", p.BL, "TOPRIGHT"); p.B:SetPoint("BOTTOMRIGHT", p.BR, "BOTTOMLEFT")
  p.L:SetPoint("TOPLEFT", p.TL, "BOTTOMLEFT"); p.L:SetPoint("BOTTOMRIGHT", p.BL, "TOPRIGHT")
  p.R:SetPoint("TOPLEFT", p.TR, "BOTTOMLEFT"); p.R:SetPoint("BOTTOMRIGHT", p.BR, "TOPRIGHT")
  if p.C then p.C:SetPoint("TOPLEFT", p.TL, "BOTTOMRIGHT"); p.C:SetPoint("BOTTOMRIGHT", p.BR, "TOPLEFT") end
end
local function slices(f, file, layer, sub, radius, inset, noCenter)
  local s = setmetatable({ f = f, r = radius or T.RADIUS, inset = inset or 0, p = {} }, Set)
  for k, tc in pairs(SLICE) do
    if not (noCenter and k == "C") then
      local t = f:CreateTexture(nil, layer, nil, sub)
      t:SetTexture(Q.MEDIA .. file)
      t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      s.p[k] = t
    end
  end
  s:Layout()
  if f.HookScript then f:HookScript("OnSizeChanged", function() s:Layout() end) end
  return s
end
T.Slices = slices

-- rounded fill (returns a set that takes SetVertexColor like a texture)
function T.RFill(f, color, radius, layer, sub, inset)
  local s = slices(f, "rfill", layer or "BACKGROUND", sub or -8, radius, inset)
  s:SetVertexColor(rgba(color))
  return s
end

-- rounded border (thick = 2 for windows, like Command Center)
function T.Border(f, color, radius, thick)
  local s = slices(f, (thick and thick >= 2) and "redge2" or "redge1", "BORDER", 7,
    radius or ((thick and thick >= 2) and 8 or T.RADIUS), 0, true)
  s:SetVertexColor(rgba(color or T.c.line))
  f.__border = { s }
  return s
end

function T.SetBorderColor(f, r, g, b, a)
  for _, l in ipairs(f.__border or {}) do l:SetVertexColor(r, g, b, a or 1) end
end

function T.Text(parent, size, color, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(T.FONT, size or 12, flags or "")
  fs:SetTextColor(rgba(color or T.c.text))
  fs:SetJustifyH("LEFT")
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  return fs
end

-- movable window with a title bar; saved position in `store` ({point, x, y})
function T.Window(name, w, h, title, store)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  -- soft drop shadow, rounded body, thick theme trim and a black hairline outside (Command Center look)
  local sh = CreateFrame("Frame", nil, f)
  sh:SetPoint("TOPLEFT", -18, 18); sh:SetPoint("BOTTOMRIGHT", 18, -20)
  sh:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
  local st = sh:CreateTexture(nil, "BACKGROUND")
  st:SetAllPoints(); st:SetTexture(Q.MEDIA .. "glow"); st:SetVertexColor(0, 0, 0, 0.7)
  f.shadow = sh
  f.bg = T.RFill(f, { T.c.bg[1], T.c.bg[2], T.c.bg[3], 0.97 }, 8)
  T.Border(f, T.c.line, 8, 2)
  local outer = CreateFrame("Frame", nil, f)
  outer:SetPoint("TOPLEFT", -1, 1); outer:SetPoint("BOTTOMRIGHT", 1, -1)
  slices(outer, "redge1", "BORDER", 6, 9, 0, true):SetVertexColor(0, 0, 0, 1)
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(24)
  -- header band: rounded top row + gradient body
  local h1, h2 = T.c.head1 or T.c.bg2, T.c.head2 or T.c.bg
  local cap = slices(bar, "rfill", "ARTWORK", 0, 6, 2)
  for _, k in ipairs({ "L", "C", "R", "BL", "B", "BR" }) do cap.p[k]:Hide() end
  for _, k in ipairs({ "TL", "T", "TR" }) do cap.p[k]:SetVertexColor(h1[1], h1[2], h1[3], 1) end
  cap.Layout = function() end   -- only the top row is used: keep it as built
  local bt = bar:CreateTexture(nil, "ARTWORK")
  bt:SetTexture(WHITE); bt:SetVertexColor(rgba(T.c.bg2))
  bt:SetPoint("TOPLEFT", 2, -8); bt:SetPoint("BOTTOMRIGHT", -2, 0)
  if CreateColor and bt.SetGradient then
    pcall(bt.SetGradient, bt, "VERTICAL", CreateColor(h2[1], h2[2], h2[3], 1), CreateColor(h1[1], h1[2], h1[3], 1))
  end
  local acc = bar:CreateTexture(nil, "OVERLAY")
  acc:SetTexture(WHITE); acc:SetVertexColor(T.c.line[1], T.c.line[2], T.c.line[3], 1); acc:SetHeight(1)
  acc:SetPoint("BOTTOMLEFT", 2, 0); acc:SetPoint("BOTTOMRIGHT", -2, 0)
  f.title = T.Text(bar, 13, T.c.gold)
  f.title:SetPoint("LEFT", 12, 0)
  f.title:SetText(Q.L[title or ""])
  f.bar = bar
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() if not (store and store.locked) then f:StartMoving() end end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    if store then
      local p, _, _, x, y = f:GetPoint()
      store.at = { p, x, y }
    end
  end)
  local close = CreateFrame("Button", nil, bar)
  close:SetSize(20, 20)
  close.icon = close:CreateTexture(nil, "ARTWORK")
  close.icon:SetSize(12, 12); close.icon:SetPoint("CENTER")
  close.icon:SetTexture(Q.MEDIA .. "i_close"); close.icon:SetVertexColor(rgba(T.c.dim))
  close:SetPoint("RIGHT", -5, 0)
  close:SetScript("OnEnter", function(s) s.icon:SetVertexColor(rgba(T.c.gold)) end)
  close:SetScript("OnLeave", function(s) s.icon:SetVertexColor(rgba(T.c.dim)) end)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
  if store and store.at then
    f:SetPoint(store.at[1], UIParent, store.at[1], store.at[2], store.at[3])
  else
    f:SetPoint("CENTER")
  end
  return f
end

function T.Button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 90, h or 22)
  b.bg = T.RFill(b, T.c.bg2)
  T.Border(b, T.c.line)
  b.label = T.Text(b, 12, T.c.gold)
  b.label:SetPoint("CENTER")
  b.label:SetJustifyH("CENTER")
  b.label:SetText(Q.L[text or ""])
  b:SetScript("OnEnter", function(s)
    T.SetBorderColor(s, rgba(T.c.accent))
    s.label:SetTextColor(rgba(T.c.text))
    if s.tip then
      GameTooltip:SetOwner(s, "ANCHOR_TOP")
      GameTooltip:SetText(Q.L[s.tip], 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(s)
    T.SetBorderColor(s, T.c.line[1], T.c.line[2], T.c.line[3], 1)
    s.label:SetTextColor(rgba(T.c.gold))
    GameTooltip:Hide()
  end)
  function b:SetText(t) self.label:SetText(Q.L[t]) end
  return b
end

-- icon-only button (texture path or file id)
function T.IconButton(parent, icon, size, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 18, size or 18)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(icon)
  b:SetHighlightTexture(WHITE)
  local hl = b:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.15) end
  b.tip = tip
  b:SetScript("OnEnter", function(s)
    if s.tip then
      GameTooltip:SetOwner(s, "ANCHOR_TOP")
      GameTooltip:SetText(Q.L[s.tip], 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function T.Check(parent, text, get, set, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(260, 20)
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
  T.RFill(box, { T.c.bg[1] * 0.6, T.c.bg[2] * 0.6, T.c.bg[3] * 0.6, 1 }, 4)
  T.Border(box, T.c.line, 4)
  local tick = T.RFill(box, T.c.accent, 3, "OVERLAY", 0, 3)
  b.label = T.Text(b, 12)
  b.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
  b.label:SetText(Q.L[text])
  b.tip = tip
  function b:Refresh() tick:SetShown(get() and true or false) end
  b:SetScript("OnClick", function(s) set(not get()); s:Refresh() end)
  b:SetScript("OnEnter", function(s)
    if s.tip then
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:SetText(Q.L[s.tip], 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Refresh()
  return b
end

-- a row of mutually exclusive options: opts = { {value, label, tip}, ... }
function T.Segments(parent, opts, get, set, w)
  local f = CreateFrame("Frame", nil, parent)
  local bw = w or 96
  f:SetSize(bw * #opts + 4 * (#opts - 1), 24)
  f.buttons = {}
  local function refresh()
    for _, b in ipairs(f.buttons) do
      local on = get() == b.value
      local a, p2 = T.c.accent, T.c.bg2
      if on then b.bg:SetVertexColor(a[1] * 0.45, a[2] * 0.45, a[3] * 0.45, 1) else b.bg:SetVertexColor(p2[1], p2[2], p2[3], 1) end
      b.label:SetTextColor(on and 1 or 0.8, on and 1 or 0.82, on and 1 or 0.86)
    end
  end
  for i, o in ipairs(opts) do
    local b = T.Button(f, o[2], bw, 24)
    b:SetPoint("LEFT", (i - 1) * (bw + 4), 0)
    b.value, b.tip = o[1], o[3]
    b:SetScript("OnClick", function() set(o[1]); refresh() end)
    f.buttons[i] = b
  end
  f.Refresh = refresh
  refresh()
  return f
end

-- big clickable card: icon, title, description; used by the survey
function T.Card(parent, w, h, icon, title, desc)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = T.RFill(b, T.c.bg2, 8)
  T.Border(b, T.c.line, 8)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(36, 36)
  b.icon:SetPoint("TOPLEFT", 10, -10)
  b.icon:SetTexture(icon)
  b.title = T.Text(b, 14, T.c.gold)
  b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -2)
  b.title:SetPoint("RIGHT", -8, 0)
  b.title:SetText(Q.L[title])
  b.desc = T.Text(b, 11, T.c.dim)
  b.desc:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
  b.desc:SetPoint("BOTTOMRIGHT", -8, 8)
  b.desc:SetJustifyV("TOP")
  b.desc:SetText(Q.L[desc])
  function b:SetSelected(on)
    self.selected = on
    if on then
      T.SetBorderColor(self, rgba(T.c.accent))
      local a = T.c.accent
      self.bg:SetVertexColor(a[1] * 0.3, a[2] * 0.3, a[3] * 0.3, 1)
    else
      T.SetBorderColor(self, T.c.line[1], T.c.line[2], T.c.line[3], 1)
      self.bg:SetVertexColor(rgba(T.c.bg2))
    end
  end
  b:SetScript("OnEnter", function(s) if not s.selected then T.SetBorderColor(s, T.c.text[1], T.c.text[2], T.c.text[3], 0.8) end end)
  b:SetScript("OnLeave", function(s) s:SetSelected(s.selected) end)
  return b
end

-- simple horizontal progress bar
function T.Bar(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  T.RFill(f, { T.c.bg[1] * 0.5, T.c.bg[2] * 0.5, T.c.bg[3] * 0.5, 1 }, math.max(1, math.floor(h / 2)))
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetTexture(WHITE)
  f.fill:SetVertexColor(rgba(T.c.accent))
  f.fill:SetPoint("TOPLEFT"); f.fill:SetPoint("BOTTOMLEFT")
  function f:SetValue(p)
    p = math.max(0, math.min(1, p or 0))
    self.fill:SetWidth(math.max(0.001, (self:GetWidth() or w) * p))
  end
  f:SetValue(0)
  return f
end

-- Command Center is loaded before Questicus (OptionalDeps): use its colours from the start
T.ApplyCommandCenter()
