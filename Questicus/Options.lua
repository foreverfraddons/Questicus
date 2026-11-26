-- Questicus options window (/qc options) and a button in the game's AddOns settings.
local Q = Questicus
local T = Q.T
local L = Q.L
local frame

-- The window: a list of sections on the left, one short page on the right. Each page groups the
-- settings by what they're for, with a line saying what the page is about.
local W, H, SIDE = 640, 520, 150

local function sizeRow(parent, text, get, set)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(440, 26)
  local l = T.Text(f, 12)
  l:SetPoint("LEFT")
  l:SetText(L[text])
  local seg = T.Segments(f, { { 0.8, "Small" }, { 1, "Normal" }, { 1.25, "Large" } }, get, set, 72)
  seg:SetPoint("LEFT", 170, 0)
  f.Refresh = seg.Refresh
  return f
end

local function build()
  frame = T.Window("QuesticusOptions", W, H, "Questicus options", nil)
  frame:SetFrameStrata("DIALOG")
  local db, pr = Q.db, function() return Q.prefs end
  local refresh = {}
  local pages, tabs = {}, {}

  -- left: the sections
  local side = CreateFrame("Frame", nil, frame)
  side:SetPoint("TOPLEFT", 10, -34)
  side:SetPoint("BOTTOMLEFT", 10, 40)
  side:SetWidth(SIDE)
  T.RFill(side, T.c.bg2, 6)

  local function show(i)
    for k, pg in ipairs(pages) do pg:SetShown(k == i) end
    for k, t in ipairs(tabs) do
      local on = k == i
      t.sel:SetShown(on)
      t.label:SetTextColor(on and 1 or 0.8, on and 0.85 or 0.8, on and 0.35 or 0.82)
    end
    frame.page = i
  end

  -- one page: title, one line about it, then settings added top to bottom
  local function page(title, about)
    local i = #pages + 1
    local pg = CreateFrame("Frame", nil, frame)
    pg:SetPoint("TOPLEFT", side, "TOPRIGHT", 16, 0)
    pg:SetPoint("BOTTOMRIGHT", -16, 40)
    pg:Hide()
    local h = T.Text(pg, 15, T.c.gold)
    h:SetPoint("TOPLEFT", 0, -4)
    h:SetText(L[title])
    local a = T.Text(pg, 11, T.c.dim)
    a:SetPoint("TOPLEFT", 0, -26)
    a:SetPoint("RIGHT", 0, 0)
    a:SetJustifyH("LEFT")
    a:SetText(L[about])
    pg.y = -56
    pages[i] = pg
    local t = CreateFrame("Button", nil, side)
    t:SetSize(SIDE - 8, 26)
    t:SetPoint("TOPLEFT", 4, -6 - (i - 1) * 30)
    t.sel = T.RFill(t, { T.c.accent[1] * 0.35, T.c.accent[2] * 0.35, T.c.accent[3] * 0.35, 1 }, 5)
    t.label = T.Text(t, 12)
    t.label:SetPoint("LEFT", 10, 0)
    t.label:SetText(L[title])
    t.key = title
    t:SetScript("OnClick", function() show(i) end)
    tabs[i] = t
    return pg
  end
  local function group(pg, text)
    pg.y = pg.y - 6
    local g = T.Text(pg, 12, T.c.gold)
    g:SetPoint("TOPLEFT", 0, pg.y)
    g:SetText(L[text])
    pg.y = pg.y - 20
  end
  local function check(pg, text, get, set, tip)
    local b = T.Check(pg, text, get, function(v) set(v); Q:Send("QC_OPTION") end, tip)
    b:SetPoint("TOPLEFT", 8, pg.y)
    b:SetWidth(440)
    refresh[#refresh + 1] = function() b:Refresh() end
    pg.y = pg.y - 23
    return b
  end
  local function size(pg, text, get, set)
    local r = sizeRow(pg, text, get, set)
    r:SetPoint("TOPLEFT", 8, pg.y)
    refresh[#refresh + 1] = r.Refresh
    pg.y = pg.y - 30
  end
  local function buttons(pg, list)
    pg.y = pg.y - 6
    local x = 8
    for _, b in ipairs(list) do
      local btn = T.Button(pg, b[1], b[2], 24)
      btn:SetPoint("TOPLEFT", x, pg.y)
      btn.tip = b[4]
      btn:SetScript("OnClick", b[3])
      x = x + b[2] + 8
    end
    pg.y = pg.y - 32
  end

  -- 1. General
  local p = page("General", "The guide window, the arrow that points the way, and where to start over.")
  group(p, "Guide window")
  check(p, "Show the guide window", function() return db.guide.shown end, function(v)
    db.guide.shown = v
    if v then Q:ShowGuide() elseif Q.Guide.Frame() then Q.Guide.Frame():Hide() end
  end)
  check(p, "Lock it in place", function() return db.guide.locked end, function(v) db.guide.locked = v end)
  size(p, "Size", function() return db.guide.scale end, function(v)
    db.guide.scale = v
    local f = Q.Guide.Frame()
    if f then f:SetScale(v) end
  end)
  group(p, "Arrow")
  check(p, "Show the arrow", function() return db.arrow.shown end, function(v) db.arrow.shown = v; Q.Arrow:Refresh() end)
  check(p, "Lock it in place", function() return db.arrow.locked end, function(v) db.arrow.locked = v end)
  size(p, "Size", function() return db.arrow.scale end, function(v) db.arrow.scale = v; Q.Arrow:Refresh() end)
  check(p, "Show the minimap button", function() return not db.minimap.hide end,
    function(v) db.minimap.hide = not v; if Q.Minimap then Q.Minimap:Refresh() end end)
  buttons(p, {
    { "Setup questions again", 160, function() frame:Hide(); Q.Survey:Show() end, "Answer the setup questions again: play style, quests, gear, helpers." },
    { "Rebuild route", 110, function() Q.Planner:Build() end, "Works the route out again now." },
    { "Unskip all", 90, function() SlashCmdList.QUESTICUS("unskip") end, "Brings back every quest and step you skipped." },
  })

  -- 2. Automation: everything Questicus does on its own (all of it off until you turn it on)
  p = page("Automation", "What Questicus does for you on its own. Hold Shift while talking to someone to do it yourself once.")
  group(p, "Quest givers")
  check(p, "Accept route quests automatically", function() return pr().autoAccept end, function(v) pr().autoAccept = v end,
    "Quests on your route are accepted when you talk to the quest giver. Escort quests always ask first.")
  check(p, "Hand in quests automatically", function() return pr().autoTurnIn end, function(v) pr().autoTurnIn = v end,
    "Finished quests are handed in when you talk to the quest giver.")
  check(p, "Suggest the best reward", function() return pr().autoReward end, function(v) pr().autoReward = v end,
    "The reward that's the biggest upgrade for you (or sells for the most) - you confirm it before the quest is handed in.")
  group(p, "Travel")
  check(p, "Take the flight automatically", function() return Q.prefs.autoFly ~= false end,
    function(v) Q.prefs.autoFly = v end, "Talking to the flight master of a fly step takes the flight. Hold Shift to choose yourself.")
  group(p, "Map")
  check(p, "Pin the next objective on the map automatically", function() return db.pins.autoPin ~= false end,
    function(v) db.pins.autoPin = v; if v then Q.Waypoint:Follow() else Q.Waypoint:Clear() end end,
    "Puts the game's waypoint on the step you're on, so the game's own arrow and the minimap point there too.")

  -- 3. Questing
  p = page("Questing", "Which quests and travel the route uses.")
  group(p, "Travel")
  check(p, "Use flight paths in the route", function() return Q.prefs.flights ~= false end,
    function(v) Q.prefs.flights = v; Q.Planner:Build() end, "Flies when it beats running, with the flight masters you know. Unknown ones nearby become a step.")
  check(p, "Use my hearthstone in the route", function() return Q.prefs.hearth ~= false end,
    function(v) Q.prefs.hearth = v; Q.Planner:Build() end, "Hearths when it's ready and gets you to the next step faster (Hearthstone button on the step).")
  group(p, "Route")
  check(p, "Include escort quests", function() return Q.prefs.escort ~= false end,
    function(v) Q.prefs.escort = v; Q:Send("QC_PREFS_CHANGED") end, "Escort quests are marked green on the route and always ask before they start.")
  check(p, "Include PvP and battleground quests", function() return Q.prefs.pvp == true end,
    function(v) Q.prefs.pvp = v; Q:Send("QC_PREFS_CHANGED") end, "Off: Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands and other PvP quests are left out.")

  -- 4. Map
  p = page("Map & minimap", "What Questicus draws on the world map and the minimap.")
  group(p, "World map")
  check(p, "Show the route on the map", function() return db.pins.world end, function(v) db.pins.world = v; Q.Pins:RefreshWorld() end)
  check(p, "Quest objectives (like Questie)", function() return db.pins.objectives ~= false end,
    function(v) db.pins.objectives = v; Q.Pins:RefreshWorld() end,
    "Every open objective of the quests in your log, with an icon for what to do there, and a ? where finished quests are handed in.")
  check(p, "Every quest you can pick up", function() return db.pins.others end, function(v) db.pins.others = v; Q.Pins:RefreshWorld() end)
  check(p, "Shade the area objectives can be in", function() return db.pins.areas ~= false end,
    function(v) db.pins.areas = v; Q.Pins:RefreshWorld() end)
  check(p, "Rares and notable drops", function() return pr().collectibles end, function(v) pr().collectibles = v; Q.Pins:RefreshWorld() end)
  size(p, "Icon size", function() return db.pins.size end, function(v) db.pins.size = v; Q.Pins:RefreshWorld() end)
  group(p, "Minimap")
  check(p, "Show the route on the minimap", function() return db.pins.minimap end, function(v) db.pins.minimap = v end)
  check(p, "Route lines on the minimap", function() return db.pins.mmRoute ~= false end,
    function(v) db.pins.mmRoute = v end, "Your next steps as lines on the minimap, and the paths of mobs that walk around.")
  buttons(p, { { "Questicus Maps settings", 180, function() frame:Hide(); Q.MapSettings() end, "The stitched world map's own settings (also /qc map)." } })

  -- 4. Tracker & alerts
  p = page("Tracker & alerts", "Your quest list on the screen, pop-ups and the marks over mobs.")
  group(p, "Quest tracker")
  check(p, "Show the quest tracker", function() return Q.Tracker.cfg().on end,
    function(v) Q.Tracker.cfg().on = v; Q.Tracker:ApplyBlizzard(); Q.Tracker:Refresh() end,
    "Your quest log with progress bars, in Questicus' look. Right-click a quest to focus it or add it to your route.")
  buttons(p, { { "Tracker settings", 130, function() Q.Tracker:Settings() end, "Size, what it shows, folding (also the cog in its title)." } })
  group(p, "Pop-ups")
  check(p, "Pop-ups for quest items and objective progress", function() return db.popups.on end,
    function(v) db.popups.on = v end, "Shift-drag a pop-up to move them. Right-click one to close it. /qc popuptest shows one.")
  check(p, "Play a sound with them", function() return db.popups.sound end, function(v) db.popups.sound = v end)
  group(p, "Nameplates")
  check(p, "Marks over mobs you need and quest NPCs", function() return db.marks.plates end,
    function(v) db.marks.plates = v; Q.Marks:RefreshPlates() end, "An X over mobs your quests need, a star over quest givers.")

  -- 5. Dungeons
  p = page("Dungeons", "The boss tracker that opens inside a dungeon.")
  check(p, "Boss tracker in dungeons", function() return db.bossTracker ~= false end,
    function(v) db.bossTracker = v end, "Boss portraits, fights and loot, ticked off as you kill them. Also when the route's dungeon step comes up.")
  check(p, "Low profile (just the names)", function() return db.bossLow == true end,
    function(v) db.bossLow = v; if Q.Bosses then Q.Bosses:Refresh() end end, "A plain list of the bosses, ticked off as you kill them. Click a name for its loot.")
  buttons(p, { { "Run history", 110, function() SlashCmdList.QUESTICUS("runs") end, "Every dungeon run: time, gold, XP and loot (also /qc runs)." } })

  -- 6. Stat weights
  p = page("Stat weights", "How much each stat is worth to you. Questicus uses these to find gear upgrades and pick quest rewards.")
  local G = Q.Gear
  local roleNow = function() return G:Role() end
  local roles = {}
  for _, r in ipairs(G.ROLES[Q.player.class] or { "melee" }) do
    local nm = (G.ROLE_NAMES[r] or r):gsub(" %(.-%)", "")
    roles[#roles + 1] = { r, nm }
  end
  local wrows, wnote = {}, nil
  local function refreshWeights()
    local role = roleNow()
    local stats = G:RoleStats(role)
    local mine = G.CustomWeights(role)
    for i, r in ipairs(wrows) do
      local k = stats[i]
      r:SetShown(k ~= nil)
      if k then
        r.stat = k
        r.label:SetText(L[G.STAT_NAMES[k] or k])
        local v = (mine and mine[k]) or (not mine and G:Weights(role)[k]) or 0
        r.box:SetText(("%g"):format(math.floor(v * 1000 + 0.5) / 1000))
        local d = G.DefaultWeight(role, k)
        r.label:SetTextColor(math.abs(v - d) > 1e-6 and 1 or 0.9, math.abs(v - d) > 1e-6 and 0.82 or 0.9, math.abs(v - d) > 1e-6 and 0.3 or 0.9)
      end
    end
    if wnote then
      wnote:SetText(mine and L["Your own weights for this role (gold = changed from the default)."]
        or L["The defaults for this role, adjusted by your stat priority from the setup questions. Change any number to use your own."])
    end
  end
  if #roles > 1 then
    group(p, "Role")
    local seg = T.Segments(p, roles, roleNow, function(v) Q.prefs.role = v; G:Changed(); refreshWeights() end, 100)
    seg:SetPoint("TOPLEFT", 8, p.y)
    refresh[#refresh + 1] = seg.Refresh
    p.y = p.y - 32
  end
  group(p, "Worth per point")
  local top = p.y
  for i = 1, 18 do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(215, 22)
    r:SetPoint("TOPLEFT", 8 + col * 225, top - row * 25)
    r.label = T.Text(r, 11)
    r.label:SetPoint("LEFT")
    local box = CreateFrame("EditBox", nil, r)
    box:SetSize(64, 20)
    box:SetPoint("RIGHT")
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetJustifyH("CENTER")
    box:SetMaxLetters(7)
    T.RFill(box, T.c.bg2, 4)
    local function commit(self)
      local v = tonumber(self:GetText())
      if v and r.stat then G.SetWeight(roleNow(), r.stat, v) end
      self:ClearFocus()
      refreshWeights()
    end
    box:SetScript("OnEnterPressed", commit)
    box:SetScript("OnEditFocusLost", function(self) if self.dirty then self.dirty = false; commit(self) end end)
    box:SetScript("OnTextChanged", function(self, user) if user then self.dirty = true end end)
    box:SetScript("OnEscapePressed", function(self) self.dirty = false; self:ClearFocus(); refreshWeights() end)
    -- mouse wheel over the number: up / down by a step that fits its size
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(self, delta)
      if not r.stat then return end
      local v = tonumber(self:GetText()) or 0
      local step = v >= 5 and 1 or (v >= 0.5 and 0.1 or 0.01)
      G.SetWeight(roleNow(), r.stat, math.max(0, v + delta * step))
      refreshWeights()
    end)
    r.box = box
    wrows[i] = r
  end
  p.y = top - 9 * 25 - 4
  wnote = T.Text(p, 10, T.c.dim)
  wnote:SetPoint("TOPLEFT", 8, p.y)
  wnote:SetWidth(440)
  wnote:SetJustifyH("LEFT")
  p.y = p.y - 28
  buttons(p, { { "Back to defaults", 130, function() G.ResetWeights(roleNow()); refreshWeights() end,
    "Forget your own weights for this role and use the defaults again." } })
  refresh[#refresh + 1] = refreshWeights

  -- Waypoint (the marker in the world, your own pins) - Beacon.lua, Waypoint.lua, Way.lua
  local bc = function() return db.beacon end
  local function choice(pg, text, opts, get, set, w)
    local f = CreateFrame("Frame", nil, pg)
    f:SetSize(440, 26)
    f:SetPoint("TOPLEFT", 8, pg.y)
    local l = T.Text(f, 12)
    l:SetPoint("LEFT")
    l:SetText(L[text])
    local seg = T.Segments(f, opts, get, function(v) set(v); Q:Send("QC_OPTION") end, w or 64)
    seg:SetPoint("LEFT", 130, 0)
    refresh[#refresh + 1] = seg.Refresh
    pg.y = pg.y - 30
  end
  local function beaconRefresh() if Q.Beacon then Q.Beacon.Refresh() end end
  local function pickColor(key)
    local c = bc()[key] or Q.Beacon.COLORS.pin
    local function set(r, g, b) bc()[key] = { r, g, b }; beaconRefresh() end
    local CP = ColorPickerFrame
    if not CP then return end
    if CP.SetupColorPickerAndShow then
      CP:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], hasOpacity = false,
        swatchFunc = function() set(CP:GetColorRGB()) end,
        cancelFunc = function() set(c[1], c[2], c[3]) end })
    else
      CP.hasOpacity = false
      CP.previousValues = { r = c[1], g = c[2], b = c[3] }
      CP.func = function() set(CP:GetColorRGB()) end
      CP.cancelFunc = function() set(c[1], c[2], c[3]) end
      CP:SetColorRGB(c[1], c[2], c[3])
      CP:Hide(); CP:Show()
    end
  end
  p = page("Waypoint", "A marker in the world over where you're going, and waypoints of your own.")
  group(p, "In the world")
  check(p, "Show the waypoint in the world", function() return bc().on end, function(v) bc().on = v end,
    "A marker with a beam of light over the place, how far it is, when you'll be there and what it is.")
  check(p, "Pinpoint over the target when you're close", function() return bc().pinpoint ~= false end, function(v) bc().pinpoint = v end)
  choice(p, "Pinpoint from", { { 30, "30 yd" }, { 60, "60 yd" }, { 100, "100 yd" } },
    function() return bc().pinpointAt end, function(v) bc().pinpointAt = v end)
  check(p, "Pointer at the screen's edge when it's off screen", function() return bc().navigator ~= false end, function(v) bc().navigator = v end)
  check(p, "With an arrow", function() return bc().navArrow ~= false end, function(v) bc().navArrow = v end)
  check(p, "Right-click it to clear it", function() return bc().rightClear end, function(v) bc().rightClear = v end,
    "Questicus' own waypoint comes back when the route moves on to the next step.")
  check(p, "Fade it when the mouse is over it", function() return bc().fadeHover end, function(v) bc().fadeHover = v end)
  check(p, "Show it with the interface hidden (Alt-Z)", function() return bc().alwaysShow end,
    function(v) bc().alwaysShow = v; beaconRefresh() end)
  check(p, "Distances in meters", function() return bc().meters end, function(v) bc().meters = v end)
  group(p, "Your own waypoints")
  check(p, "Ctrl-click the minimap: a waypoint there", function() return bc().minimapPins ~= false end, function(v) bc().minimapPins = v end)
  check(p, "Follow a pin you put on the world map", function() return bc().trackPlaced ~= false end, function(v) bc().trackPlaced = v end,
    "Your pin is followed (arrow, marker in the world) until you get there, then the route again.")
  check(p, "Follow a map link you click in chat", function() return bc().trackLinks ~= false end, function(v) bc().trackLinks = v end)
  buttons(p, {
    { "Paste /way lines", 130, function() frame:Hide(); Q.Way.ShowPaste() end, "Put in a list of /way lines: followed one after the other." },
    { "Clear my waypoints", 140, function() Q.Way.Command("clear") end, "Back to the route." },
  })

  p = page("Waypoint look", "How the waypoint in the world looks and sounds.")
  group(p, "Waypoint")
  check(p, "Beam of light", function() return bc().beam ~= false end, function(v) bc().beam = v end)
  choice(p, "Info under it", { { "all", "All" }, { "distance", "Distance" }, { "eta", "Arrival" }, { "name", "Name" }, { "none", "None" } },
    function() return bc().info end, function(v) bc().info = v; bc().footer = v ~= "none" end, 58)
  choice(p, "Size", { { 0.8, "Small" }, { 1, "Normal" }, { 1.25, "Large" } }, function() return bc().scale end,
    function(v) bc().scale = v; bc().ppScale = v; bc().navScale = v end, 72)
  check(p, "Smaller when it's further away", function() return bc().worldScale ~= false end, function(v) bc().worldScale = v end)
  choice(p, "Opacity", { { 0.5, "50%" }, { 0.75, "75%" }, { 1, "100%" } }, function() return bc().alpha end, function(v) bc().alpha = v end, 72)
  group(p, "Pinpoint")
  check(p, "Say what it is (step, quest, NPC)", function() return bc().ppExtended ~= false end, function(v) bc().ppExtended = v; beaconRefresh() end)
  group(p, "Colour")
  check(p, "One colour of my own (else by what the step is)", function() return bc().customColor end,
    function(v) bc().customColor = v; beaconRefresh() end)
  buttons(p, {
    { "Pick colour", 110, function() pickColor("color") end, "The marker's colour" },
    { "Beam colour", 110, function() pickColor("beamColor") end, "The beam's colour" },
  })
  group(p, "Sound")
  check(p, "Sounds (a new waypoint)", function() return bc().sound end, function(v) bc().sound = v end)
  check(p, "When you get close and when you walk away", function() return bc().proximity ~= false end, function(v) bc().proximity = v end)

  -- 7. Highlights
  p = page("Highlights", "Ore, herbs, quest objects, chests and your fishing bobber light up as you come up to them.")
  check(p, "Highlights on", function() return Q.Glow.cfg().on end, function(v) Q.Glow.SetOn(v) end,
    "Off: Questicus gives the game back your own targeting settings.")
  buttons(p, { { "Highlight settings", 150, function() frame:Hide(); Q.Glow.ShowSettings(true) end, "Effects, colours, what lights up and when (also /qc glow)." } })

  -- Language: every language the game comes in; a language needs its pack (a separate download)
  p = page("Language", "The language Questicus uses. English is built in; every other language is a small language pack you download separately.")
  do
    local pick = T.Button(p, "", 230, 24)
    pick:SetPoint("TOPLEFT", 8, p.y)
    local lbl = T.Text(p, 12)
    lbl:SetPoint("LEFT", pick, "RIGHT", 10, 0)
    local function nameOf(code)
      if code == "auto" then
        local g = Q.GameLang()
        for _, l in ipairs(Q.LANGS) do if l.code == g then return L("Automatic (the game's language: %s)", l.name) end end
        return L["Automatic (the game's language)"]
      end
      for _, l in ipairs(Q.LANGS) do if l.code == code then return l.name end end
      return code
    end
    local menu
    local rows = {}
    local note = T.Text(p, 11, T.c.dim)
    local reload = T.Button(p, L["Reload now"], 110, 24)
    reload:SetScript("OnClick", function() if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end end)
    reload:Hide()
    local function usable(code)
      if code == "auto" then return true end
      return Q.LangPack(code) == "loaded" and Q.LangFontOK(code)
    end
    local function refreshLang()
      pick:SetText(nameOf(QuesticusDB.lang or "auto") .. "  v")
      local chosen = QuesticusDB.lang or "auto"
      local inUse = Q.Lang()
      local want = chosen == "auto" and Q.GameLang() or chosen
      reload:SetShown(want ~= inUse and usable(want))
      for _, r in ipairs(rows) do r.Refresh() end
    end
    pick:SetScript("OnClick", function(self)
      if menu and menu:IsShown() then menu:Hide(); return end
      if not menu then
        menu = CreateFrame("Frame", nil, self)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        T.RFill(menu, { T.c.bg[1], T.c.bg[2], T.c.bg[3], 0.98 }, 6)
        T.Border(menu, T.c.line, 6)
        local opts = { { code = "auto" } }
        for _, l in ipairs(Q.LANGS) do opts[#opts + 1] = l end
        menu:SetSize(260, 8 + #opts * 22)
        menu.items = {}
        for i, o in ipairs(opts) do
          local b = CreateFrame("Button", nil, menu)
          b:SetSize(248, 20)
          b:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 22)
          b.t = T.Text(b, 12)
          b.t:SetPoint("LEFT", 6, 0)
          b.code = o.code
          b:SetScript("OnClick", function(btn)
            if not usable(btn.code) then return end
            QuesticusDB.lang = btn.code
            menu:Hide()
            refreshLang()
          end)
          b:SetScript("OnEnter", function(btn)
            if usable(btn.code) then return end
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(Q.LangPack(btn.code) == "off" and L["Its language pack is installed but turned off in the AddOns list."]
              or (not Q.LangFontOK(btn.code) and L["Needs the game itself in this language (its letters come with the game's font)."])
              or L["Needs its language pack: download it from the Questicus files page."], 1, 1, 1, 1, true)
            GameTooltip:Show()
          end)
          b:SetScript("OnLeave", function() GameTooltip:Hide() end)
          menu.items[i] = b
        end
      end
      for _, b in ipairs(menu.items) do
        b.t:SetText(nameOf(b.code))
        local ok = usable(b.code)
        b.t:SetTextColor(ok and 0.95 or 0.45, ok and 0.9 or 0.45, ok and 0.85 or 0.45)
      end
      menu:ClearAllPoints()
      menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
      menu:Show()
    end)
    p.y = p.y - 34
    group(p, "Languages")
    for _, l in ipairs(Q.LANGS) do
      local r = CreateFrame("Frame", nil, p)
      r:SetSize(440, 18)
      r:SetPoint("TOPLEFT", 8, p.y)
      r.name = T.Text(r, 12)
      r.name:SetPoint("LEFT", 0, 0)
      r.state = T.Text(r, 11, T.c.dim)
      r.state:SetPoint("LEFT", 190, 0)
      function r.Refresh()
        local st = Q.LangPack(l.code)
        local ok = st == "loaded" and Q.LangFontOK(l.code)
        r.name:SetText(l.name .. (Q.Lang() == l.code and ("  " .. Q.Color("40ff40", L["(in use)"])) or ""))
        r.name:SetTextColor(ok and 0.95 or 0.45, ok and 0.9 or 0.45, ok and 0.85 or 0.45)
        r.state:SetText(l.code == "enUS" and L["Built in"]
          or (st == "loaded" and not Q.LangFontOK(l.code) and L["Installed - needs the game in this language"])
          or (st == "loaded" and L["Installed"]) or (st == "off" and L["Installed, turned off in the AddOns list"])
          or L["Language pack not installed"])
      end
      rows[#rows + 1] = r
      p.y = p.y - 19
    end
    p.y = p.y - 8
    note:SetPoint("TOPLEFT", 8, p.y)
    note:SetWidth(440)
    note:SetJustifyH("LEFT")
    note:SetText(L["A greyed-out language needs its language pack. Language packs are on the Questicus files page on CurseForge, next to each Questicus download: install the pack for your language, then pick it here. Spot a translation that needs correcting? Leave a comment on the Questicus page or contact me."])
    p.y = p.y - 64
    local link = T.Button(p, L["Questicus files page"], 170, 24)
    link:SetPoint("TOPLEFT", 8, p.y)
    link:SetScript("OnClick", function() Q.CopyBox(L["Questicus files page"], Q.LANG_URL) end)
    reload:SetPoint("LEFT", link, "RIGHT", 8, 0)
    reload.tip = L["A new language takes effect after a reload."]
    p.y = p.y - 32
    refresh[#refresh + 1] = refreshLang
  end

  -- 8. Advanced
  p = page("Advanced", "Recording and database helpers. You can leave these alone.")
  check(p, "Help fill the database", function() return db.collect ~= false end, function(v) db.collect = v end,
    "Saves where quest objectives count up and what you looted for them. Fills map spots ForeverDB is missing, for you right away and for everyone once your recordings are synced.")
  check(p, "Collection mode (record only, no guiding)", function() return Q.CollectOnly() end, function(v) Q.CollectMode:Set(v) end,
    "Questicus stops guiding and only records: routes you take, quests, XP and rewards, objective spots. For this character.")
  buttons(p, { { "Record a patrol", 130, function() Q.Patrol:Show() end, "Record the path of a mob that walks around (target it, then follow it). Shown as a line on the map." } })
  local meta = T.Text(p, 10, T.c.dim)
  meta:SetPoint("TOPLEFT", 8, p.y - 8)
  meta:SetWidth(440)
  meta:SetJustifyH("LEFT")
  function frame:UpdateMeta()
    local m = Q.Data:Meta()
    local pool = Q.Quests.pool and #Q.Quests.pool or 0
    meta:SetText(L("Questicus %s\nForeverDB %s (%s)\n%d quests possible for this character",
      Q.version, m and m.build or L["missing"], m and m.hash or "-", pool))
  end

  -- footer
  local ver = T.Text(frame, 10, T.c.dim)
  ver:SetPoint("BOTTOMLEFT", 16, 16)
  ver:SetText(L("Questicus %s  -  /qc help: all commands", Q.version))
  local news = T.Button(frame, L["What's new"], 100, 24)
  news:SetPoint("BOTTOMRIGHT", -14, 10)
  news.tip = L["The patch notes for this version (also /qc news)"]
  news:SetScript("OnClick", function() Q.News:Show(nil) end)

  frame:SetScript("OnShow", function() for _, f in ipairs(refresh) do f() end end)
  function frame.ShowPage(title)
    for i, t in ipairs(tabs) do if t.key == title or t.label:GetText() == title then show(i) return end end
  end
  show(1)
end

-- Questicus Maps' settings (the map's menu, or its options window when the map is off)
function Q.MapSettings()
  local M = _G.QuesticusMap
  if M and M.OpenOptions then M.OpenOptions(); return end
  if SlashCmdList and SlashCmdList.OPENMAP then SlashCmdList.OPENMAP(""); return end   -- (the standalone OpenMap addon)
  Q:Print(L["Questicus Maps isn't running"])
end

function Q:ShowOptions(pageTitle)
  if not frame then build() end
  if pageTitle and frame.ShowPage then frame.ShowPage(pageTitle) end
  frame:Show()
  frame:UpdateMeta()
end

Q:Command("options", "open the options", function() Q:ShowOptions() end)

-- entry in the game's settings (Esc > Options > AddOns)
Q:On("QC_READY", function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local panel = CreateFrame("Frame")
  local t = T.Text(panel, 16, T.c.gold)
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("Questicus")
  local b = T.Button(panel, L["Open Questicus options"], 180, 24)
  b:SetPoint("TOPLEFT", 16, -48)
  b:SetScript("OnClick", function() Q:ShowOptions() end)
  local mb = T.Button(panel, L["Questicus Maps settings"], 180, 24)
  mb:SetPoint("TOPLEFT", 16, -80)
  mb:SetScript("OnClick", function() if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end; Q.MapSettings() end)
  local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Questicus")
  if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end)
