-- Questicus: the Highlights settings window (/qc glow, Options > Highlights): a live preview,
-- the effect and its look (for every object or one category), categories and colours, when to hide
-- it, detection, the interact key, the cut-out around your character, and the tracking switch.
local Q = Questicus
local L = Q.L
local T = Q.T
local G = Q.Glow

local win
local scope = "all"            -- "all" or a category: what the look settings change
local refreshers = {}

local function setLook(key, v)
  local c = G.cfg()
  if scope == "all" then
    c[key] = v
    for _, own in pairs(c.own) do own[key] = nil end    -- (everyone: a category's own value goes)
  else
    c.own[scope] = c.own[scope] or {}
    c.own[scope][key] = v
  end
end
local function getLook(key)
  if scope == "all" then return G.cfg()[key] end
  return G.Look(scope, key)
end

-- a slider: label, value text, drag / wheel / click
local function slider(parent, label, lo, hi, step, get, set, fmt, tip)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(250, 34)
  f.label = T.Text(f, 11, T.c.dim)
  f.label:SetPoint("TOPLEFT")
  f.value = T.Text(f, 11, T.c.text)
  f.value:SetPoint("TOPRIGHT")
  -- a plain slider: thin groove, the filled part in the accent colour, and a knob you drag
  local track = CreateFrame("Button", nil, f)
  track:SetPoint("BOTTOMLEFT", 0, 0); track:SetPoint("BOTTOMRIGHT", 0, 0); track:SetHeight(16)
  local groove = track:CreateTexture(nil, "BACKGROUND")
  groove:SetColorTexture(T.c.bg2[1], T.c.bg2[2], T.c.bg2[3], 1)
  groove:SetPoint("LEFT", 0, 0); groove:SetPoint("RIGHT", 0, 0); groove:SetHeight(4)
  local edge = track:CreateTexture(nil, "BORDER")
  edge:SetColorTexture(0, 0, 0, 0.6)
  edge:SetPoint("TOPLEFT", groove, "TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", groove, "BOTTOMRIGHT", 1, -1)
  edge:SetDrawLayer("BACKGROUND", -1)
  local bar = track:CreateTexture(nil, "ARTWORK")
  bar:SetColorTexture(T.c.accent[1], T.c.accent[2], T.c.accent[3], 0.9)
  bar:SetPoint("LEFT", groove, "LEFT"); bar:SetHeight(4)
  local knob = CreateFrame("Frame", nil, track)
  knob:SetSize(10, 16)
  T.RFill(knob, T.c.accent, 3)
  T.Border(knob, { 0, 0, 0, 0.8 }, 3)
  knob:EnableMouse(false)
  f.tip = tip
  local function show()
    local v = get()
    f.label:SetText(label)
    f.value:SetText((fmt or "%d"):format(v))
    local w = track:GetWidth() or 250
    if not w or w <= 0 then w = 250 end
    local k = math.max(0, math.min(1, (v - lo) / (hi - lo)))
    bar:SetWidth(math.max(1, (w - 10) * k + 5))
    knob:ClearAllPoints()
    knob:SetPoint("CENTER", track, "LEFT", 5 + (w - 10) * k, 0)
  end
  local function fromX(x)
    local l, w = track:GetLeft(), track:GetWidth()
    if not (x and l and w and w > 10) then return end
    local k = math.max(0, math.min(1, (x - l - 5) / (w - 10)))
    local v = lo + k * (hi - lo)
    v = math.floor(v / step + 0.5) * step
    set(v); show()
  end
  local dragging = false
  local function atCursor(s)
    local x = GetCursorPosition and GetCursorPosition()
    if type(x) == "number" then fromX(x / s:GetEffectiveScale()) end
  end
  track:SetScript("OnMouseDown", function(s) dragging = true; atCursor(s) end)
  track:SetScript("OnMouseUp", function() dragging = false end)
  track:SetScript("OnUpdate", function(s) if dragging then atCursor(s) end end)
  track:EnableMouseWheel(true)
  track:SetScript("OnMouseWheel", function(_, d) set(math.max(lo, math.min(hi, get() + d * step))); show() end)
  track:SetScript("OnEnter", function(s)
    if f.tip then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetText(f.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
  end)
  track:SetScript("OnLeave", function() GameTooltip:Hide() end)
  track:SetScript("OnSizeChanged", function() show() end)
  f.Refresh = show
  refreshers[#refreshers + 1] = show
  show()
  return f
end

local function check(parent, text, get, set, tip)
  local b = T.Check(parent, text, get, set, tip)
  refreshers[#refreshers + 1] = function() b:Refresh() end
  return b
end

local function header(parent, text)
  local h = T.Text(parent, 12, T.c.gold)
  h:SetText(L[text])
  return h
end

-- the colour swatch of a category: left-click picks, right-click resets
local function swatch(parent, cat)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  local tx = b:CreateTexture(nil, "ARTWORK")
  tx:SetAllPoints(); tx:SetTexture(Q.MEDIA .. "disc")
  T.Border(b, T.c.line, 9)
  local function show() local c = G.cfg().colors[cat]; tx:SetVertexColor(c[1], c[2], c[3]) end
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, btn)
    local c = G.cfg()
    if btn == "RightButton" then
      local d = G.Defaults().colors[cat]
      c.colors[cat] = { d[1], d[2], d[3] }
      show()
      return
    end
    local cc = c.colors[cat]
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local old = { cc[1], cc[2], cc[3] }
      ColorPickerFrame:SetupColorPickerAndShow({
        r = cc[1], g = cc[2], b = cc[3], hasOpacity = false,
        swatchFunc = function() local r, g, bb = ColorPickerFrame:GetColorRGB(); c.colors[cat] = { r, g, bb }; show() end,
        cancelFunc = function() c.colors[cat] = old; show() end,
      })
    else
      Q:Print(L["this client has no colour picker."])
    end
  end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:SetText(G.CAT_NAMES[cat] .. " colour", 1, 1, 1)
    GameTooltip:AddLine(L["Left-click: choose a colour"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Right-click: back to the original"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  refreshers[#refreshers + 1] = show
  show()
  return b
end

local function refreshAll() for _, f in ipairs(refreshers) do f() end end

-- the preview: the chosen effect on a sample of the chosen category, cycling far -> within reach -> unusable
local function buildPreview(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(220, 220)
  T.RFill(p, { 0.03, 0.03, 0.05, 0.9 }, 8)
  T.Border(p, T.c.line, 8)
  if p.SetClipsChildren then p:SetClipsChildren(true) end
  local L = G.NewLight(p)
  L:SetPoint("CENTER", 0, -6)
  local name = T.Text(p, 12, T.c.text, "OUTLINE")
  name:SetPoint("BOTTOM", L, "TOP", 0, 6)
  local ic = p:CreateTexture(nil, "OVERLAY"); ic:SetSize(20, 20); ic:SetPoint("BOTTOM", name, "TOP", 0, 2)
  local stl = T.Text(p, 10, T.c.dim)
  stl:SetPoint("BOTTOM", 0, 6)
  local t0 = GetTime()
  p:SetScript("OnUpdate", function()
    local cat = scope == "all" and "ore" or scope
    local c = G.cfg()
    local t = GetTime() - t0
    local ph = t % 9
    local st = ph < 3 and "far" or ph < 7 and "ready" or "locked"
    local size = math.min(170, G.Look(cat, "size") or 110)
    L:Use(G.Look(cat, "effect"))
    L:SetSize(size, size)
    local a = ((G.Look(cat, "intensity") or 100) / 100) * (st == "far" and 0.6 or st == "locked" and 0.5 or 1)
    L:Draw(t, size, c.colors[cat] or c.colors.other, math.min(1, a), st)
    name:SetShown(G.Look(cat, "name") and not c.glowOnly)
    name:SetText(G.SAMPLES[cat])
    local rgb = c.colors[cat]
    name:SetTextColor(rgb[1] * 0.4 + 0.6, rgb[2] * 0.4 + 0.6, rgb[3] * 0.4 + 0.6)
    ic:SetShown(G.Look(cat, "icon") and not c.glowOnly)
    ic:SetTexture("Interface\\Cursor\\" .. ((st == "locked" and "Unable" or "") .. (({ ore = "Mine", herb = "GatherHerbs", quest = "Quest", chest = "Pickup", bobber = "Fishing", other = "Interact" })[cat])))
    stl:SetText(st == "far" and L["out of reach"] or st == "ready" and L["within reach"] or L["unusable for now"])
  end)
  return p
end

-- the cut-out outline on screen while the window is open
local outline
local function showOutline(on)
  if on and not outline then
    outline = UIParent:CreateTexture(nil, "OVERLAY")
    outline:SetTexture(Q.MEDIA .. "qg_ring")
    outline:SetVertexColor(1, 0.2, 0.2, 0.9)
  end
  if not outline then return end
  if on then
    local cx, cy, hw, hh = G.CutoutRect()
    outline:ClearAllPoints()
    outline:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    outline:SetSize(hw * 1.15, hh * 1.15)
    outline:Show()
  else
    outline:Hide()
  end
end

local function build()
  Q.db.glowWin = Q.db.glowWin or {}
  win = T.Window("QuesticusGlowSettings", 760, 600, "Questicus  -  Highlights", Q.db.glowWin)
  win:SetFrameStrata("DIALOG")
  local c = G.cfg()

  local prev = buildPreview(win)
  prev:SetPoint("TOPLEFT", 14, -34)

  -- column 2: the look
  local x2 = 250
  local scopeBar = T.Segments(win, { { "all", "All", "Changes apply to every category (and take away a category's own look)." },
    { "ore", "Ore" }, { "herb", "Herbs" }, { "quest", "Quests" }, { "chest", "Chests" }, { "bobber", "Bobber" }, { "other", "Other" } },
    function() return scope end, function(v) scope = v; refreshAll() end, 66)
  scopeBar:SetPoint("TOPLEFT", x2, -34)
  refreshers[#refreshers + 1] = function() scopeBar:Refresh() end

  local eh = header(win, L["Effect"])
  eh:SetPoint("TOPLEFT", x2, -66)
  local grid = {}
  for i, k in ipairs(G.EFFECT_ORDER) do
    local b = T.Button(win, G.EFFECT_NAMES[k], 94, 22)
    b:SetPoint("TOPLEFT", x2 + ((i - 1) % 5) * 98, -84 - math.floor((i - 1) / 5) * 26)
    b.tip = G.EFFECT_TIPS[k]
    b:SetScript("OnClick", function() setLook("effect", k); refreshAll() end)
    grid[k] = b
  end
  refreshers[#refreshers + 1] = function()
    local cur = getLook("effect")
    for k, b in pairs(grid) do
      if b.label then b.label:SetTextColor(k == cur and 1 or 0.75, k == cur and 0.85 or 0.75, k == cur and 0.3 or 0.75) end
    end
  end

  local sz = slider(win, "Size", 40, 300, 5, function() return getLook("size") end, function(v) setLook("size", v) end, "%d", "How big the light is.")
  sz:SetPoint("TOPLEFT", x2, -168)
  local it = slider(win, "Intensity", 30, 150, 5, function() return getLook("intensity") end, function(v) setLook("intensity", v) end, "%d%%", "How bright it is.")
  it:SetPoint("TOPLEFT", x2 + 260, -168)
  local of = slider(win, "Up / down", -200, 200, 5, function() return getLook("offsetY") end, function(v) setLook("offsetY", v) end, "%d", "Moves the light up or down from the object's nameplate.")
  of:SetPoint("TOPLEFT", x2, -206)
  local tsz = slider(win, "Text size", 60, 200, 5, function() return getLook("textSize") end, function(v) setLook("textSize", v) end, "%d%%", "Size of the name written over the object.")
  tsz:SetPoint("TOPLEFT", x2 + 260, -206)
  local n1 = check(win, "Show the name", function() return getLook("name") end, function(v) setLook("name", v) end, "Writes the object's name over the light as well (the game shows its own on the object's nameplate).")
  n1:SetPoint("TOPLEFT", x2, -246)
  local n2 = check(win, "Show the icon", function() return getLook("icon") end, function(v) setLook("icon", v) end, "Draws the interaction icon over the light as well (the game shows its own on the object's nameplate).")
  n2:SetPoint("TOPLEFT", x2 + 260, -246)
  local n3 = check(win, "Fade with the nameplate", function() return getLook("follow") end, function(v) setLook("follow", v) end, "The light fades with the object's nameplate (when the scenery hides it, say).")
  n3:SetPoint("TOPLEFT", x2, -268)
  local shared = T.Button(win, L["Same as all objects"], 140, 20)
  shared:SetPoint("TOPLEFT", x2 + 260, -268)
  shared.tip = L["Takes away this category's own look: it goes back to everyone's."]
  shared:SetScript("OnClick", function() if scope ~= "all" then G.cfg().own[scope] = nil; refreshAll() end end)
  refreshers[#refreshers + 1] = function() shared:SetShown(scope ~= "all") end

  -- left column under the preview: categories + colours
  local ch = header(win, L["Light up (this character)"])
  ch:SetPoint("TOPLEFT", 14, -266)
  for i, k in ipairs(G.CATS) do
    local sw = swatch(win, k)
    sw:SetPoint("TOPLEFT", 14, -286 - (i - 1) * 22)
    local cb = check(win, G.CAT_NAMES[k], function() return G.cats()[k] end, function(v) G.cats()[k] = v end, G.CAT_TIPS[k])
    cb:SetPoint("TOPLEFT", 38, -285 - (i - 1) * 22)
    cb:SetWidth(180)
  end
  local ign = T.Button(win, L["Ignore the object in front of me"], 210, 22)
  ign:SetPoint("TOPLEFT", 14, -424)
  ign.tip = L["Never lights it (or anything of the same name). On an ignored one: stops ignoring it. /qc glow ignore list names them."]
  ign:SetScript("OnClick", function() G.Ignore(); refreshAll() end)
  local ignN = T.Text(win, 10, T.c.dim)
  ignN:SetPoint("TOPLEFT", 14, -450)
  refreshers[#refreshers + 1] = function()
    local n = 0
    for _ in pairs(G.cfg().ignored) do n = n + 1 end
    ignN:SetText(L["Ignored objects: "] .. n .. L["   (/qc glow ignore clear forgets them)"])
  end

  -- column 2 lower: hide / detection
  local hh = header(win, L["Hide the light"])
  hh:SetPoint("TOPLEFT", x2, -300)
  check(win, "In combat", function() return G.cfg().hideCombat end, function(v) G.cfg().hideCombat = v end):SetPoint("TOPLEFT", x2, -318)
  check(win, "In dungeons, raids and battlegrounds", function() return G.cfg().hideInstance end, function(v) G.cfg().hideInstance = v end):SetPoint("TOPLEFT", x2, -340)
  check(win, "On things I can't use yet", function() return G.cfg().hideLocked end, function(v) G.cfg().hideLocked = v end,
    "Skill too low, locked... the game only says so once you're within reach."):SetPoint("TOPLEFT", x2, -362)
  check(win, "Herbs / ore without the profession", function() return G.cfg().hideUntrained end, function(v) G.cfg().hideUntrained = v end):SetPoint("TOPLEFT", x2, -384)

  local dh = header(win, L["Detection"])
  dh:SetPoint("TOPLEFT", x2 + 260, -300)
  local rg = slider(win, "Range", 5, 15, 1, function() return G.cfg().range end, function(v) G.cfg().range = v; G.ApplyCVars() end, "%d yd", "How far away the game may pick an object.")
  rg:SetPoint("TOPLEFT", x2 + 260, -318)
  local dir = T.Segments(win, { { 0, "Ahead" }, { 1, "In front" }, { 2, "All round" } }, function() return G.cfg().arc end,
    function(v) G.cfg().arc = v; G.ApplyCVars() end, 80)
  dir:SetPoint("TOPLEFT", x2 + 260, -358)
  refreshers[#refreshers + 1] = function() dir:Refresh() end
  check(win, "Only point out lit objects", function() return G.cfg().exclusive end, function(v) G.cfg().exclusive = v; G.ApplyCVars() end,
    "The game stops showing a name and icon on every NPC and object you could interact with."):SetPoint("TOPLEFT", x2 + 260, -388)
  check(win, "Light only (no name or icon)", function() return G.cfg().glowOnly end, function(v) G.cfg().glowOnly = v; G.ApplyCVars() end,
    "Questicus doesn't write the name and icon; the game (or another addon) keeps its own."):SetPoint("TOPLEFT", x2 + 260, -410)

  -- interact key
  local kb = T.Button(win, L["Interact key"], 200, 22)
  kb:SetPoint("TOPLEFT", x2 + 260, -436)
  kb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  kb.tip = L["The game's interact key: gathers, loots or uses the lit object once it's within reach (it works on NPCs too). Left-click: choose a key, right-click: remove it."]
  local function kbShow() kb.label:SetText(L["Interact key: "] .. (G.InteractKey() or L["not bound"])) end
  kb:SetScript("OnClick", function(s, btn)
    if btn == "RightButton" then G.SetInteractKey(nil); kbShow() return end
    s.label:SetText(L["Press a key (Escape: cancel)"])
    s:EnableKeyboard(true)
    s:SetScript("OnKeyDown", function(self, key)
      self:EnableKeyboard(false)
      self:SetScript("OnKeyDown", nil)
      if key ~= "ESCAPE" and not key:find("SHIFT") and not key:find("CTRL") and not key:find("ALT") then
        local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
        G.SetInteractKey(mods .. key)
      end
      kbShow()
    end)
  end)
  refreshers[#refreshers + 1] = kbShow

  -- bottom: cut-out, tracking, general
  local sh = header(win, L["Pass behind my character"])
  sh:SetPoint("TOPLEFT", 14, -476)
  check(win, "Cut the light out around my character", function() return G.cfg().silhouette end, function(v) G.cfg().silhouette = v end,
    "The light seems to pass behind you instead of covering you."):SetPoint("TOPLEFT", 14, -494)
  local cut = function(k) Q.char.glowCut = Q.char.glowCut or {}; return Q.char.glowCut end
  local cs = slider(win, "Cut-out size", 40, 300, 5, function() return cut().scale or 100 end, function(v) cut().scale = v; showOutline(win.outlineOn) end, "%d%%",
    "Raise it if the light bites into your character, lower it if it stays too far away. Each character keeps its own.")
  cs:SetPoint("TOPLEFT", 14, -518)
  local cy = slider(win, "Cut-out height", -100, 100, 5, function() return cut().shift or 0 end, function(v) cut().shift = v; showOutline(win.outlineOn) end, "%d%%")
  cy:SetPoint("TOPLEFT", 14, -556)
  local so = T.Button(win, L["Show the cut-out"], 120, 20)
  so:SetPoint("TOPLEFT", 270, -496)
  so.tip = L["Outlines the cut-out in red: it should hug your character. Goes away when this window closes."]
  so:SetScript("OnClick", function() win.outlineOn = not win.outlineOn; showOutline(win.outlineOn) end)

  local th = header(win, L["Two gathering professions"])
  th:SetPoint("TOPLEFT", x2 + 260, -476)
  check(win, "Alternate Find Herbs / Find Minerals", function() return G.cfg().switch end, function(v) G.cfg().switch = v end,
    "The game shows one tracking at a time; Questicus switches to the other each time you've moved far enough."):SetPoint("TOPLEFT", x2 + 260, -494)
  local sy = slider(win, "Distance between switches", 10, 50, 5, function() return G.cfg().switchYards end, function(v) G.cfg().switchYards = v end, "%d yd")
  sy:SetPoint("TOPLEFT", x2 + 260, -518)

  local en = check(win, "Highlights on", function() return G.cfg().on end, function(v) G.SetOn(v) end,
    "Off: Questicus gives the game back your own targeting settings.")
  en:SetPoint("BOTTOMLEFT", 14, 12)
  local df = T.Button(win, L["Defaults"], 90, 22)
  df:SetPoint("BOTTOMRIGHT", -14, 10)
  df.tip = L["Puts the effect, look and detection settings back (click twice)."]
  df:SetScript("OnClick", function(s)
    if not s.armed then s.armed = true; s.label:SetText(L["Sure?"]); Q.After(3, function() s.armed = false; s.label:SetText(L["Defaults"]) end) return end
    local cc = G.cfg()
    local d = G.Defaults()
    for _, k in ipairs({ "effect", "size", "intensity", "offsetY", "follow", "name", "icon", "textSize", "range", "arc", "exclusive", "glowOnly" }) do cc[k] = d[k] end
    cc.own = {}
    G.ApplyCVars()
    refreshAll()
  end)
  win:HookScript("OnHide", function()
    win.outlineOn = false; showOutline(false)
    -- opened from the options window: back to it, on the Highlights page
    if win.fromOptions then win.fromOptions = false; Q:ShowOptions("Highlights") end
  end)
end

function G.ShowSettings(fromOptions)
  if not win then build() end
  win.fromOptions = fromOptions and true or false
  refreshAll()
  win:Show()
end
