-- Questicus first-login survey: a few pages of questions that tailor the route to how this
-- character wants to quest. Runs once per character (redo any time with /qc survey).
local Q = Questicus
local T = Q.T
local SV = {}
Q.Survey = SV

local W, H = 660, 470
local PRESETS = {
  speed = { escort = false, cooking = false, levelRange = 3, gray = false, breadcrumbs = "useful", allInZone = false, repeatable = false, rep = false,
    elite = "some", dungeons = false, gear = "onway", xp = 3, gold = 1,
    collectibles = false },
  balanced = { levelRange = 2, gray = false, breadcrumbs = "useful", allInZone = false, repeatable = false, rep = false,
    elite = "solo", dungeons = false, gear = "route", xp = 3, gold = 2,
    collectibles = false },
  complete = { levelRange = 2, gray = true, breadcrumbs = "all", allInZone = true, repeatable = true, rep = true,
    elite = "some", dungeons = true, gear = "route", xp = 2, gold = 2,
    collectibles = true, profQuests = true, seasonal = true, pvp = true },
}
SV.PRESETS = PRESETS

local function pr() return Q.prefs end
local function getter(k) return function() return pr()[k] end end
local function setter(k) return function(v) pr()[k] = v end end

local frame, pages, page

local function header(p, title, sub)
  local t = T.Text(p, 20, T.c.gold)
  t:SetPoint("TOPLEFT", 24, -20)
  t:SetText(title)
  local s = T.Text(p, 12, T.c.dim)
  s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
  s:SetWidth(W - 48)
  s:SetText(sub or "")
  return t, s
end

local function label(p, text, x, y)
  local l = T.Text(p, 13, T.c.text)
  l:SetPoint("TOPLEFT", x, y)
  l:SetText(text)
  return l
end

-- ------------------------------------------------------------------ pages
local function pageStyle(p)
  header(p, "Welcome to Questicus", "A few quick questions so the route fits how you like to play. You can change any of this later.")
  local cards = {}
  local opts = {
    { "speed", "Interface\\Icons\\Ability_Rogue_Sprint", "Speedrun",
      "Fastest way to max level. Only the quests worth the walk." },
    { "balanced", "Interface\\Icons\\INV_Misc_Map_01", "Balanced",
      "Efficient levelling that keeps your gear and gold up as you go." },
    { "complete", "Interface\\Icons\\INV_Misc_Book_09", "Completionist",
      "Every quest you can do: breadcrumbs, chains, reputation, dungeons." },
    { "custom", "Interface\\Icons\\Trade_Engineering", "Custom",
      "Start from Balanced and set every option yourself on the next pages." },
  }
  local function refresh() for _, c in ipairs(cards) do c:SetSelected(pr().style == c.value) end end
  for i, o in ipairs(opts) do
    local c = T.Card(p, 296, 92, o[2], o[3], o[4])
    c:SetPoint("TOPLEFT", 24 + ((i - 1) % 2) * 316, -90 - math.floor((i - 1) / 2) * 104)
    c.value = o[1]
    c:SetScript("OnClick", function()
      pr().style = o[1]
      for k, v in pairs(PRESETS[o[1]] or PRESETS.balanced) do pr()[k] = v end
      refresh()
      for _, pg in ipairs(pages) do if pg.Refresh then pg:Refresh() end end
    end)
    cards[i] = c
  end
  refresh()
  local note = T.Text(p, 11, T.c.dim)
  note:SetPoint("BOTTOMLEFT", 24, 54)
  note:SetWidth(W - 48)
  note:SetText("Routes are worked out live from the WoW: Forever database (ForeverDB): your position, level and quest log decide every next step.")
end

local function pageRoute(p)
  header(p, "Your route", "How far ahead to push, what kind of content, and what matters most.")
  local w = {}
  label(p, "Quests up to this many levels above you", 24, -84)
  w[1] = T.Segments(p, { { 1, "+1" }, { 2, "+2" }, { 3, "+3" }, { 4, "+4" } }, getter("levelRange"), setter("levelRange"), 60)
  w[1]:SetPoint("TOPLEFT", 24, -104)
  label(p, "And this many levels below you", 330, -84)
  w[7] = T.Segments(p, { { 0, "Any XP", "Everything that still gives experience." }, { 2, "-2" }, { 3, "-3" },
    { 5, "-5" }, { 8, "-8" } }, function() return pr().levelBelow or 0 end, setter("levelBelow"), 56)
  w[7]:SetPoint("TOPLEFT", 330, -104)
  label(p, "Group content", 24, -144)
  w[2] = T.Segments(p, { { "solo", "Solo only", "Skip quests with elite targets or elites around the objectives." },
    { "some", "Easy elites", "Elite quests you can solo or duo near your level." },
    { "group", "Group quests", "Include elite group quests." } }, getter("elite"), setter("elite"), 120)
  w[2]:SetPoint("TOPLEFT", 24, -164)
  label(p, "Experience", 24, -204)
  w[3] = T.Segments(p, { { 1, "Low" }, { 2, "Normal" }, { 3, "Top priority" } }, getter("xp"), setter("xp"), 110)
  w[3]:SetPoint("TOPLEFT", 24, -224)
  label(p, "Gold", 24, -264)
  w[4] = T.Segments(p, { { 1, "Low" }, { 2, "Normal" }, { 3, "High" } }, getter("gold"), setter("gold"), 110)
  w[4]:SetPoint("TOPLEFT", 24, -284)
  w[5] = T.Check(p, "Dungeon quests (pick them up on the way, do them with a group)", getter("dungeons"), setter("dungeons"))
  w[5]:SetPoint("TOPLEFT", 24, -326); w[5]:SetWidth(560)
  w[6] = T.Check(p, "Use my hearthstone in routes", getter("hearth"), setter("hearth"))
  w[6]:SetPoint("TOPLEFT", 24, -350)
  function p:Refresh() for _, x in ipairs(w) do x:Refresh() end end
end

local function pageComplete(p)
  header(p, "Completionist", "What to include beyond the main levelling route.")
  label(p, "Breadcrumb quests (the ones that send you to a new place)", 24, -84)
  local w = {}
  w[1] = T.Segments(p, { { "skip", "Skip" }, { "useful", "When useful", "Take them when the route goes there anyway." },
    { "all", "All of them" } }, getter("breadcrumbs"), setter("breadcrumbs"), 120)
  w[1]:SetPoint("TOPLEFT", 24, -104)
  local checks = {
    { "gray", "Gray (low level) quests too" },
    { "allInZone", "Finish a zone's quests before moving on" },
    { "repeatable", "Repeatable quests and reputation turn-ins" },
    { "rep", "Prefer quests with reputation rewards" },
    { "classQuests", "Class quests (spells, class items)" },
    { "profQuests", "Profession quests" },
    { "escort", "Escort quests", "Off: never on your route (unless you add one yourself, or it's a dungeon quest in dungeon mode)." },
    { "cooking", "Cooking and recipe quests", "Off: skipped unless a chain needs them for gear or a dungeon (the step says why)." },
    { "pvp", "PvP and battleground quests", "Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands and other PvP quests. Off by default." },
    { "seasonal", "Holiday / seasonal quests" },
    { "forever", "WoW Forever's new zones and quests" },
    { "legacy", "Classic (legacy) zones and routes" },
    { "collectibles", "Show rares and notable drops on the map" },
  }
  for i, c in ipairs(checks) do
    -- escort / cooking are in unless you turn them off; everything else is off unless turned on
    local get = (c[1] == "escort" or c[1] == "cooking") and function() return pr()[c[1]] ~= false end or getter(c[1])
    local b = T.Check(p, c[2], get, setter(c[1]), c[3])
    b:SetPoint("TOPLEFT", 24 + ((i - 1) % 2) * 310, -146 - math.floor((i - 1) / 2) * 28)
    b:SetWidth(300)
    w[#w + 1] = b
  end
  function p:Refresh() for _, x in ipairs(w) do x:Refresh() end end
end

local function pageGear(p)
  header(p, "Gear", "Questicus compares every reward and vendor item with what you wear and routes you to the upgrades.")
  label(p, "Your role", 24, -84)
  local roles = Q.Gear.ROLES[Q.player.class] or { "melee" }
  local opts = {}
  for _, r in ipairs(roles) do opts[#opts + 1] = { r, Q.Gear.ROLE_NAMES[r] } end
  if not pr().role then pr().role = roles[1] end
  local w = {}
  w[1] = T.Segments(p, opts, getter("role"), setter("role"), 136)
  w[1]:SetPoint("TOPLEFT", 24, -104)
  label(p, "Upgrades", 24, -146)
  w[2] = T.Segments(p, { { "route", "Route me to them", "Quests and vendors with upgrades get a higher priority." },
    { "onway", "Only on the way", "Show upgrades, but never detour for them." },
    { "off", "Don't bother" } }, getter("gear"), setter("gear"), 140)
  w[2]:SetPoint("TOPLEFT", 24, -166)
  w[3] = T.Check(p, "Suggest the best quest reward (I confirm it)", getter("autoReward"), setter("autoReward"),
    "Takes the biggest upgrade, or the reward that sells for the most if none is an upgrade. Hold Shift to choose yourself.")
  w[3]:SetPoint("TOPLEFT", 24, -212); w[3]:SetWidth(500)
  local sp = T.Text(p, 11, T.c.dim)
  sp:SetPoint("TOPLEFT", 24, -246)
  sp:SetWidth(W - 48)
  sp:SetText("Stat weights are tuned for levelling (weapon damage counts a lot early on). Armor you will outgrow at 40 counts a little less.")
  function p:Refresh() for _, x in ipairs(w) do x:Refresh() end end
end

local function pageStats(p)
  header(p, "Stats and weapons", "Which stats matter most to you, and the weapon types you actually use. Upgrades and quest rewards follow this.")
  local G = Q.Gear
  label(p, "Stat priority (click to pick, right-click to clear)", 24, -84)
  local opts = G.STAT_ORDER
  local rows = {}
  local function prio()
    if type(pr().statPrio) ~= "table" then pr().statPrio = {} end
    return pr().statPrio
  end
  local function refresh()
    local pl = prio()
    for i, b in ipairs(rows) do
      local k = pl[i]
      b:SetText(("%d.  %s  v"):format(i, k and (G.STAT_NAMES[k] or k) or "-"))
    end
  end
  -- the drop-down: every stat not already higher up the list, plus "(none)"
  local menu
  local menuBtns = {}
  local function openMenu(i, anchor)
    if not menu then
      menu = CreateFrame("Frame", "QuesticusStatMenu", p)
      menu:SetFrameStrata("FULLSCREEN_DIALOG")
      menu:SetClampedToScreen(true)
      menu:EnableMouse(true)
      T.RFill(menu, { T.c.bg[1], T.c.bg[2], T.c.bg[3], 0.98 }, 6)
      T.Border(menu, T.c.line, 6)
      local away = 0
      menu:SetScript("OnUpdate", function(self, el)
        if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) then away = 0 return end
        away = away + el
        if away > 1.5 then self:Hide() end
      end)
      if UISpecialFrames then table.insert(UISpecialFrames, "QuesticusStatMenu") end
    end
    local pl = prio()
    if i > #pl + 1 then i = #pl + 1 end
    local items = { { nil, "(none)" } }
    for _, k in ipairs(opts) do
      local used = false
      for j = 1, #pl do if j ~= i and pl[j] == k then used = true end end
      if not used then items[#items + 1] = { k, G.STAT_NAMES[k] or k } end
    end
    local cols = #items > 12 and 2 or 1
    local per = math.ceil(#items / cols)
    for n, it in ipairs(items) do
      local b = menuBtns[n]
      if not b then b = T.Button(menu, "", 150, 20); menuBtns[n] = b end
      local col, row = math.floor((n - 1) / per), (n - 1) % per
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 6 + col * 154, -6 - row * 22)
      b:SetText((pl[i] == it[1] and "> " or "") .. it[2])
      b:SetScript("OnClick", function()
        if it[1] then pl[i] = it[1] else table.remove(pl, i) end
        menu:Hide()
        refresh()
      end)
      b:Show()
    end
    for n = #items + 1, #menuBtns do menuBtns[n]:Hide() end
    menu:SetSize(12 + cols * 154 - 4, 12 + per * 22 - 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu.anchor = anchor
    menu:Show()
    if menu.Raise then menu:Raise() end
    return items
  end
  p.OpenStatMenu = openMenu
  for i = 1, 5 do
    local b = T.Button(p, "", 200, 24)
    b:SetPoint("TOPLEFT", 24, -104 - (i - 1) * 28)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(self, btn)
      if btn == "RightButton" then
        table.remove(prio(), i)
        if menu then menu:Hide() end
        refresh()
      elseif menu and menu:IsShown() and menu.anchor == self then
        menu:Hide()
      else
        openMenu(i, self)
      end
    end)
    rows[i] = b
  end
  local hint = T.Text(p, 11, T.c.dim)
  hint:SetPoint("TOPLEFT", 240, -108)
  hint:SetWidth(W - 270)
  hint:SetText("Empty = Questicus uses the usual weights for your role. Your 1st stat counts most; stats you leave out count a bit less.")
  label(p, "Weapon types I use (untick the ones you never want)", 24, -256)
  local checks = {}
  for i, sub in ipairs(G.ClassWeapons()) do
    local c = T.Check(p, G.WEAPON_NAMES[sub] or ("Type " .. sub), function()
      local w = pr().weapons
      return type(w) ~= "table" or not next(w) or w[sub] == true
    end, function(v)
      local w = pr().weapons
      if type(w) ~= "table" or not next(w) then
        w = {}
        for _, x in ipairs(G.ClassWeapons()) do w[x] = true end
        pr().weapons = w
      end
      w[sub] = v or nil
      if not next(w) then pr().weapons = nil end
    end)
    c:SetPoint("TOPLEFT", 24 + ((i - 1) % 3) * 205, -276 - math.floor((i - 1) / 3) * 26)
    c:SetWidth(200)
    checks[#checks + 1] = c
  end
  function p:Refresh()
    refresh()
    for _, c in ipairs(checks) do c:Refresh() end
  end
end

local function pageHelpers(p)
  header(p, "Helpers", "Things Questicus can do for you while you play.")
  local w = {}
  local list = {
    { pr, "autoAccept", "Accept route quests automatically", "Hold Shift when talking to skip it once. Escort quests always ask first." },
    { pr, "autoTurnIn", "Turn in finished quests automatically" },
    { function() return Q.db.guide end, "shown", "Step-by-step guide window" },
    { function() return Q.db.arrow end, "shown", "Waypoint arrow" },
    { function() return Q.db.pins end, "world", "Pins on the world map" },
    { function() return Q.db.pins end, "minimap", "Pins on the minimap" },
    { function() return Q.db.pins end, "others", "Every quest you can pick up on the map (not just the route)" },
  }
  for i, c in ipairs(list) do
    local tbl, k = c[1], c[2]
    local b = T.Check(p, c[3], function() return tbl()[k] end, function(v) tbl()[k] = v end, c[4])
    b:SetPoint("TOPLEFT", 24, -84 - (i - 1) * 30)
    b:SetWidth(560)
    w[#w + 1] = b
  end
  function p:Refresh() for _, x in ipairs(w) do x:Refresh() end end
end

local function pageDone(p)
  header(p, "All set", "")
  local txt = T.Text(p, 13, T.c.text)
  txt:SetPoint("TOPLEFT", 24, -84)
  txt:SetWidth(W - 48)
  txt:SetSpacing(4)
  function p:Refresh()
    local o = pr()
    local styles = { speed = "Speedrun", balanced = "Balanced", complete = "Completionist", custom = "Custom" }
    local lines = {
      "Style: " .. Q.Color(T.HEX.gold, styles[o.style] or o.style),
      "Quests up to +" .. o.levelRange .. " levels" .. ((o.levelBelow or 0) > 0 and (", down to -" .. o.levelBelow) or "") .. ", " .. ({ solo = "solo only", some = "easy elites", group = "group quests" })[o.elite],
      "Breadcrumbs: " .. o.breadcrumbs .. (o.gray and ", gray quests too" or "") .. (o.allInZone and ", finish zones" or ""),
      "Gear: " .. ({ route = "route to upgrades", onway = "upgrades on the way", off = "off" })[o.gear] ..
        " (" .. (Q.Gear.ROLE_NAMES[o.role or ""] or "auto") .. ")",
      "Auto accept " .. (o.autoAccept and "on" or "off") .. ", auto turn-in " .. (o.autoTurnIn and "on" or "off"),
      "",
      "The guide shows the next steps. Follow the arrow, and the route moves on by itself when you accept, finish or turn in quests.",
      "Commands: /qc (guide), /qc survey, /qc options, /qc plan.",
    }
    txt:SetText(table.concat(lines, "\n"))
  end
end

local BUILDERS = { pageStyle, pageRoute, pageComplete, pageGear, pageStats, pageHelpers, pageDone }

local function show(i)
  page = math.max(1, math.min(#pages, i))
  for k, pg in ipairs(pages) do pg:SetShown(k == page) end
  if pages[page].Refresh then pages[page]:Refresh() end
  frame.back:SetShown(page > 1)
  frame.next:SetText(page == #pages and "Start questing" or "Next")
  frame.dots:SetText(("%d / %d"):format(page, #pages))
end

local function build()
  frame = T.Window("QuesticusSurvey", W, H, "Questicus  -  set up your questing", nil)
  frame:SetFrameStrata("DIALOG")
  pages = {}
  SV.pages = pages
  for i, b in ipairs(BUILDERS) do
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 0, -24)
    p:SetPoint("BOTTOMRIGHT", 0, 44)
    b(p)
    p:Hide()
    pages[i] = p
  end
  frame.back = T.Button(frame, "Back", 90, 26)
  frame.back:SetPoint("BOTTOMLEFT", 16, 12)
  frame.back:SetScript("OnClick", function() show(page - 1) end)
  frame.next = T.Button(frame, "Next", 140, 26)
  frame.next:SetPoint("BOTTOMRIGHT", -16, 12)
  frame.next:SetScript("OnClick", function()
    if page < #pages then show(page + 1) else SV:Finish() end
  end)
  frame.dots = T.Text(frame, 11, T.c.dim)
  frame.dots:SetPoint("BOTTOM", 0, 18)
end

function SV:Show()
  if not frame then build() end
  frame:Show()
  show(1)
end

function SV:Finish()
  Q.char.surveyDone = true
  frame:Hide()
  Q:Send("QC_PREFS_CHANGED")
  if Q.ShowGuide then Q:ShowGuide() end
  Q:Print("route ready. Follow the guide and the arrow - have fun!")
end

Q:On("QC_READY", function(ok)
  if ok and not Q.char.surveyDone then Q.After(3, function() SV:Show() end) end
end)
Q:Command("survey", "answer the setup questions again", function() SV:Show() end)
