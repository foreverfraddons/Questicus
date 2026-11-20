-- Questicus options window (/qc options) and a button in the game's AddOns settings.
local Q = Questicus
local T = Q.T
local frame

local function scaleRow(parent, text, get, set, y)
  local l = T.Text(parent, 12)
  l:SetPoint("TOPLEFT", 16, y)
  l:SetText(text)
  local seg = T.Segments(parent, { { 0.8, "Small" }, { 1, "Normal" }, { 1.25, "Large" } }, get, set, 72)
  seg:SetPoint("TOPLEFT", 200, y + 4)
  return seg
end

local function build()
  frame = T.Window("QuesticusOptions", 440, 944, "Questicus options", nil)
  frame:SetFrameStrata("DIALOG")
  local db, pr = Q.db, function() return Q.prefs end
  local w = {}
  local y = -38
  local function check(text, get, set, tip)
    local b = T.Check(frame, text, get, function(v) set(v); Q:Send("QC_OPTION") end, tip)
    b:SetPoint("TOPLEFT", 16, y)
    b:SetWidth(400)
    w[#w + 1] = b
    y = y - 24
  end
  check("Show the guide window", function() return db.guide.shown end, function(v)
    db.guide.shown = v
    if v then Q:ShowGuide() elseif Q.Guide.Frame() then Q.Guide.Frame():Hide() end
  end)
  check("Show the arrow", function() return db.arrow.shown end, function(v) db.arrow.shown = v; Q.Arrow:Refresh() end)
  check("Lock the arrow", function() return db.arrow.locked end, function(v) db.arrow.locked = v end)
  check("Show the minimap button", function() return not db.minimap.hide end,
    function(v) db.minimap.hide = not v; if Q.Minimap then Q.Minimap:Refresh() end end)
  check("Lock the guide window", function() return db.guide.locked end, function(v) db.guide.locked = v end)
  check("World map pins", function() return db.pins.world end, function(v) db.pins.world = v; Q.Pins:RefreshWorld() end)
  check("Minimap pins", function() return db.pins.minimap end, function(v) db.pins.minimap = v end)
  check("Boss tracker in dungeons", function() return db.bossTracker ~= false end,
    function(v) db.bossTracker = v end, "Pops up inside a dungeon (and when the route's dungeon step comes up): boss portraits, fights, loot, ticked off as you kill them.")
  check("Boss tracker: low profile (just the names)", function() return db.bossLow == true end,
    function(v) db.bossLow = v; if Q.Bosses then Q.Bosses:Refresh() end end, "A plain list of the bosses, ticked off as you kill them. Click a name for its loot.")
  check("Route lines on the minimap", function() return db.pins.mmRoute ~= false end,
    function(v) db.pins.mmRoute = v end, "Draws your next steps as lines on the minimap, and the patrol paths of the mobs you're after.")
  check("Quest objectives on the map (like Questie)", function() return db.pins.objectives ~= false end,
    function(v) db.pins.objectives = v; Q.Pins:RefreshWorld() end,
    "Every open objective of the quests in your log on the world map, with an icon for what to do there (kill, loot, use), and a ? where finished quests are handed in.")
  check("Quest tracker on the right", function() return Q.Tracker.cfg().on end,
    function(v) Q.Tracker.cfg().on = v; Q.Tracker:ApplyBlizzard(); Q.Tracker:Refresh() end,
    "Your quest log with progress bars, in Questicus' look. Right-click a quest to focus it or add it to your route. More settings: the cog in its title.")
  check("Collection mode (record only, no guiding)", function() return Q.CollectOnly() end,
    function(v) Q.CollectMode:Set(v) end,
    "Questicus stops guiding and only records: routes you take, quests, XP and rewards, objective spots. For this character.")
  check("Every quest you can pick up on the map", function() return db.pins.others end,
    function(v) db.pins.others = v; Q.Pins:RefreshWorld() end)
  check("PvP and battleground quests in routes", function() return Q.prefs.pvp == true end,
    function(v) Q.prefs.pvp = v; Q:Send("QC_PREFS_CHANGED") end, "Off: Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands and other PvP quests are left out.")
  check("Use flight paths in routes", function() return Q.prefs.flights ~= false end,
    function(v) Q.prefs.flights = v; Q.Planner:Build() end, "Flies when it beats running, with the flight masters you know. Unknown ones nearby become a step.")
  check("Take the flight automatically", function() return Q.prefs.autoFly ~= false end,
    function(v) Q.prefs.autoFly = v end, "Talking to the flight master of a fly step takes the flight. Hold Shift to choose yourself.")
  check("Shade the area where objectives can be", function() return db.pins.areas ~= false end,
    function(v) db.pins.areas = v; Q.Pins:RefreshWorld() end)
  check("Rares and notable drops on the map", function() return pr().collectibles end,
    function(v) pr().collectibles = v; Q.Pins:RefreshWorld() end)
  check("Auto accept route quests", function() return pr().autoAccept end, function(v) pr().autoAccept = v end)
  check("Auto turn in", function() return pr().autoTurnIn end, function(v) pr().autoTurnIn = v end)
  check("Auto pick the best reward", function() return pr().autoReward end, function(v) pr().autoReward = v end)
  check("Pin the current objective on the map automatically", function() return db.pins.autoPin ~= false end,
    function(v) db.pins.autoPin = v; if v then Q.Waypoint:Follow() else Q.Waypoint:Clear() end end)
  check("Skull / X / star over mobs and quest NPCs (nameplates)", function() return db.marks.plates end,
    function(v) db.marks.plates = v; Q.Marks:RefreshPlates() end)
  check("Pop-ups when you loot a quest item or an objective moves", function() return db.popups.on end,
    function(v) db.popups.on = v end, "Shift-drag a pop-up to move them. Right-click one to close it. /qc popuptest shows one.")
  check("Pop-up sound", function() return db.popups.sound end, function(v) db.popups.sound = v end)
  check("Help fill the database (record quest spots and item sources)", function() return db.collect ~= false end,
    function(v) db.collect = v end,
    "Saves where quest objectives count up and what you looted for them. Fills map spots ForeverDB is missing, for you right away and for everyone once your recordings are synced.")
  y = y - 6
  w[#w + 1] = scaleRow(frame, "Guide size", function() return db.guide.scale end, function(v)
    db.guide.scale = v
    local f = Q.Guide.Frame()
    if f then f:SetScale(v) end
  end, y)
  y = y - 30
  w[#w + 1] = scaleRow(frame, "Arrow size", function() return db.arrow.scale end, function(v)
    db.arrow.scale = v; Q.Arrow:Refresh()
  end, y)
  y = y - 30
  w[#w + 1] = scaleRow(frame, "Map pin size", function() return db.pins.size end, function(v)
    db.pins.size = v; Q.Pins:RefreshWorld()
  end, y)
  local survey = T.Button(frame, "Questions again", 130, 24)
  survey:SetPoint("BOTTOMLEFT", 16, 14)
  survey.tip = "Answer the setup questions again (style, completionist, gear, helpers)"
  survey:SetScript("OnClick", function() frame:Hide(); Q.Survey:Show() end)
  local plan = T.Button(frame, "Rebuild route", 120, 24)
  plan:SetPoint("LEFT", survey, "RIGHT", 8, 0)
  plan:SetScript("OnClick", function() Q.Planner:Build() end)
  local unskip = T.Button(frame, "Unskip all", 100, 24)
  unskip:SetPoint("LEFT", plan, "RIGHT", 8, 0)
  unskip:SetScript("OnClick", function() SlashCmdList.QUESTICUS("unskip") end)
  local trk = T.Button(frame, "Tracker settings", 120, 24)
  trk:SetPoint("BOTTOMLEFT", 134, 44)
  trk:SetScript("OnClick", function() Q.Tracker:Settings() end)
  local mapb = T.Button(frame, "Map settings", 110, 24)
  mapb:SetPoint("BOTTOMLEFT", 262, 44)
  mapb.tip = "Questicus Maps: the stitched world map's own settings (also /qc map)"
  mapb:SetScript("OnClick", function() frame:Hide(); Q.MapSettings() end)
  local patrol = T.Button(frame, "Record patrol", 110, 24)
  patrol:SetPoint("BOTTOMLEFT", 16, 44)
  patrol.tip = "Record the path of a mob that walks around (target it, then follow it). Shown as a line on the map."
  patrol:SetScript("OnClick", function() Q.Patrol:Show() end)
  frame:SetScript("OnShow", function() for _, x in ipairs(w) do x:Refresh() end end)
  local meta = T.Text(frame, 10, T.c.dim)
  meta:SetPoint("BOTTOMLEFT", 16, 76)
  meta:SetWidth(400)
  function frame:UpdateMeta()
    local m = Q.Data:Meta()
    local pool = Q.Quests.pool and #Q.Quests.pool or 0
    meta:SetText(("Questicus %s - ForeverDB %s (%s) - %d quests possible for this character")
      :format(Q.version, m and m.build or "missing", m and m.hash or "-", pool))
  end
end

-- Questicus Maps' settings (the map's menu, or its options window when the map is off)
function Q.MapSettings()
  local M = _G.QuesticusMap
  if M and M.OpenOptions then M.OpenOptions(); return end
  if SlashCmdList and SlashCmdList.OPENMAP then SlashCmdList.OPENMAP(""); return end   -- (the standalone OpenMap addon)
  Q:Print("Questicus Maps isn't running")
end

function Q:ShowOptions()
  if not frame then build() end
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
  local b = T.Button(panel, "Open Questicus options", 180, 24)
  b:SetPoint("TOPLEFT", 16, -48)
  b:SetScript("OnClick", function() Q:ShowOptions() end)
  local mb = T.Button(panel, "Questicus Maps settings", 180, 24)
  mb:SetPoint("TOPLEFT", 16, -80)
  mb:SetScript("OnClick", function() if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end; Q.MapSettings() end)
  local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Questicus")
  if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end)
