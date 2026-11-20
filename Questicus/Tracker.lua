-- Questicus quest tracker: your quest log on the right, in Questicus' look, working with the route.
--  * each quest: level, title (difficulty colour), its objectives with progress bars (optional),
--    "ready to hand in" when done; the step of the route it's on
--  * left-click a quest: collapse / expand. Right-click: focus (the route goes there first),
--    add to / take off the route, show on the map, link in chat, abandon
--  * "+" in the title: add a quest you haven't got yet to the route (search by name)
--  * settings (cog): progress bars, levels, hide finished objectives, collapse finished quests,
--    only quests on the route, sort (route order / zone / level), width, font size, opacity, lock,
--    hide the game's own tracker
-- Kept in Q.db.tracker (look) and Q.char.focus / Q.char.forced / Q.char.trackCollapsed (per character).
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local TR = {}
Q.Tracker = TR

local DEFAULTS = { on = true, bars = true, levels = true, hideDone = false, collapseDone = false, onlyRoute = false,
  sort = "route", width = 260, font = 12, alpha = 0.85, locked = false, hideBlizzard = true, maxHeight = 520 }
local function cfg()
  Q.db.tracker = Q.db.tracker or {}
  local c = Q.db.tracker
  for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
  return c
end
TR.cfg = cfg

local frame, body
local rows = {}
TR.rows = rows

-- ------------------------------------------------------------------ helpers
local function diffColor(level)
  local lv = Q.player.level or 1
  local d = (level or lv) - lv
  if d >= 5 then return "ff4040" elseif d >= 3 then return "ff8040" elseif d >= -2 then return "ffff00"
  elseif level and level > QS.GreyLevel(lv) then return "40c040" end
  return "9d9d9d"
end
local function routeIndex()
  local idx = {}
  for i, s in ipairs(P.steps or {}) do
    for _, id in ipairs(s.quests or {}) do if not idx[id] then idx[id] = i end end
  end
  return idx
end
local function objectiveParts(o)
  local have, need = o.numFulfilled, o.numRequired
  local txt = o.text or ""
  if not need then
    local a, b = txt:match("(%d+)%s*/%s*(%d+)")
    have, need = tonumber(a), tonumber(b)
  end
  return txt, have, need
end
local function zoneOf(id)
  local z = P.QuestZone and P.QuestZone(id)
  local info = z and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(z)
  return (info and info.name) or "Other"
end

-- ------------------------------------------------------------------ rows (a pool: headers, objective lines)
local function row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, body)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r.text = T.Text(r, 12, T.c.text)
  r.text:SetPoint("LEFT", 4, 0)
  r.text:SetPoint("RIGHT", -4, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.right = T.Text(r, 10, T.c.dim)
  r.right:SetPoint("RIGHT", -4, 0)
  r.bar = T.Bar(r, 100, 4)
  r.bar:SetPoint("BOTTOMLEFT", 16, 1)
  r.bar:SetPoint("BOTTOMRIGHT", -6, 1)
  r.bar:Hide()
  r:SetScript("OnClick", function(self, btn)
    local d = TR.rowData[self]
    if not (d and d.id) then return end
    if btn == "RightButton" then TR:Menu(d.id, self); return end
    if IsShiftKeyDown and IsShiftKeyDown() then TR:Link(d.id); return end
    if IsControlKeyDown and IsControlKeyDown() then TR:Focus(d.id); return end
    if IsAltKeyDown and IsAltKeyDown() then TR:Fold(d.id); return end
    TR:OpenLog(d.id)
  end)
  r:SetScript("OnEnter", function(self)
    local d = TR.rowData[self]
    if not (d and d.id) then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    for i, l in ipairs(QS:QuestTip(d.id, nil, nil)) do
      if i == 1 then GameTooltip:AddLine(l, 1, 0.82, 0.3) else GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
    end
    local ri = routeIndex()[d.id]
    GameTooltip:AddLine(ri and ("Route step " .. ri) or "Not on your route", 0.6, 0.8, 1)
    GameTooltip:AddLine("Click: open in the quest log - Ctrl-click: focus - Shift-click: link - Alt-click: fold - Right-click: more", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end
TR.rowData = {}

-- ------------------------------------------------------------------ the list
function TR:Refresh()
  local c = cfg()
  if not frame then return end
  if not c.on then frame:Hide(); return end
  frame:Show()
  if not TR.sizing then frame:SetWidth(c.width) end
  frame.bg:SetVertexColor(T.c.bg[1], T.c.bg[2], T.c.bg[3], c.alpha)
  local ri = routeIndex()
  local list = {}
  for id, e in pairs(QS.log or {}) do
    if not (c.onlyRoute and not ri[id]) then
      list[#list + 1] = { id = id, e = e, ri = ri[id] or 999, level = e.level or (QS:Info(id) or {}).level or 0 }
    end
  end
  if c.sort == "level" then
    table.sort(list, function(a, b) return a.level < b.level or (a.level == b.level and a.id < b.id) end)
  elseif c.sort == "zone" then
    for _, q in ipairs(list) do q.zone = zoneOf(q.id) end
    table.sort(list, function(a, b) return a.zone < b.zone or (a.zone == b.zone and a.ri < b.ri) end)
  else
    table.sort(list, function(a, b) return a.ri < b.ri or (a.ri == b.ri and a.id < b.id) end)
  end
  local n, y = 0, 0
  local fs = c.font
  local function put(text, right, h, data, bar)
    n = n + 1
    local r = row(n)
    TR.rowData[r] = data
    r:SetHeight(h)
    r.text:SetFont(T.FONT, data and data.header and fs or (fs - 1), "")
    r.text:SetText(text)
    r.right:SetText(right or "")
    if bar then
      r.bar:SetValue(bar)
      r.bar:Show()
    else
      r.bar:Hide()
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", 0, 0)
    r:Show()
    y = y + h
  end
  local lastZone
  local focus = Q.char.focus
  -- quests you added that you don't have yet
  local added = {}
  for id, root in pairs(Q.char.forced or {}) do
    if root == id and not QS.log[id] and not QS.done[id] then added[#added + 1] = id end
  end
  for _, q in ipairs(list) do
    local id, e = q.id, q.e
    if c.sort == "zone" and q.zone ~= lastZone then
      lastZone = q.zone
      put(Q.Color(T.HEX.dim, q.zone), nil, fs + 6, nil)
    end
    local col = diffColor(q.level)
    local title = (c.levels and ("[" .. q.level .. "] ") or "") .. (e.title or ("Quest " .. id))
    local mark = (focus == id) and Q.Color(T.HEX.gold, "> ") or ""
    local right = e.complete and Q.Color(T.HEX.good, "done") or (q.ri < 999 and ("#" .. q.ri) or "")
    put(mark .. Q.Color(col, title), right, fs + 6, { id = id, header = true })
    local folded = (Q.char.trackCollapsed and Q.char.trackCollapsed[id]) or (c.collapseDone and e.complete)
    if not folded then
      if e.complete then
        put("   " .. Q.Color(T.HEX.good, "Ready to hand in"), nil, fs + 3, { id = id })
      else
        for _, o in ipairs(e.objectives or {}) do
          if not (c.hideDone and o.finished) then
            local txt, have, need = objectiveParts(o)
            local colr = o.finished and T.HEX.good or T.HEX.white
            local p = (need and need > 0 and have) and (have / need) or (o.finished and 1 or nil)
            put("   " .. Q.Color(o.finished and T.HEX.dim or colr, txt), nil, fs + ((c.bars and p) and 8 or 3), { id = id },
              (c.bars and p) and p or nil)
          end
        end
      end
    end
    y = y + 3
  end
  if #added > 0 then
    put(Q.Color(T.HEX.dim, "Added to your route"), nil, fs + 6, nil)
    for _, id in ipairs(added) do
      local info = QS:Info(id)
      local q = D:Quest(id)
      put("  " .. Q.Color(T.HEX.gold, (info and info.title) or (q and q[1]) or ("Quest " .. id)), "#" .. (ri[id] or "?"), fs + 4, { id = id, header = true })
    end
  end
  if n == 0 then put(Q.Color(T.HEX.dim, "No quests in your log"), nil, fs + 6, nil) end
  for i = n + 1, #rows do rows[i]:Hide(); TR.rowData[rows[i]] = nil end
  body:SetHeight(math.max(1, y))
  -- folded: just the title bar. A size you dragged stays (the list scrolls); else it fits the list
  local h
  if c.collapsed then h = 28
  elseif c.height then h = c.height
  else h = math.min(c.maxHeight, 30 + y + 6) end
  frame.scroll:SetShown(not c.collapsed)
  frame.grip:SetShown(not c.collapsed and not c.locked)
  frame.collapse.t:SetTexture(c.collapsed and "Interface\\Buttons\\Arrow-Down-Up" or "Interface\\Buttons\\Arrow-Up-Up")
  if not TR.sizing then frame:SetHeight(h) end
  frame.title:SetText(Q.Color(T.HEX.accent, "Quests") .. Q.Color(T.HEX.dim, ("  %d/%d"):format(QS.logCount or 0, QS.MaxLog())) ..
    (focus and Q.Color(T.HEX.gold, "  focus") or ""))
  frame.scroll:SetVerticalScroll(math.min(frame.scroll:GetVerticalScroll() or 0, math.max(0, y - (h - 36))))
  TR:Thumb()
end

-- the scroll bar: a slim thumb on the right when the list is longer than the window
function TR:Thumb()
  if not frame then return end
  local sc = frame.scroll
  local view, total = sc:GetHeight() or 0, body:GetHeight() or 0
  if cfg().collapsed or total <= view + 2 or view <= 0 then frame.thumb:Hide(); return end
  local th = math.max(16, view * view / total)
  local pos = (sc:GetVerticalScroll() or 0) / math.max(1, total - view)
  frame.thumb:SetHeight(th)
  frame.thumb:ClearAllPoints()
  frame.thumb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 3, -pos * (view - th))
  frame.thumb:Show()
end

-- ------------------------------------------------------------------ actions
function TR:Fold(id)
  Q.char.trackCollapsed = Q.char.trackCollapsed or {}
  Q.char.trackCollapsed[id] = not Q.char.trackCollapsed[id] or nil
  TR:Refresh()
end
-- the quest in the game's quest log (the map's quest details on the modern UI, else the old log)
function TR:OpenLog(id)
  if not QS.log[id] then TR:ShowOnMap(id); return end
  if QuestMapFrame_OpenToQuestDetails then
    if pcall(QuestMapFrame_OpenToQuestDetails, id) then return end
  end
  local idx = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id))
    or (GetQuestLogIndexByID and GetQuestLogIndexByID(id))
  if idx and idx > 0 then
    if QuestLogFrame and ShowUIPanel and not QuestLogFrame:IsShown() then pcall(ShowUIPanel, QuestLogFrame) end
    if QuestLog_SetSelection then pcall(QuestLog_SetSelection, idx)
    elseif SelectQuestLogEntry then pcall(SelectQuestLogEntry, idx) end
    if QuestLog_Update then pcall(QuestLog_Update) end
    if QuestLogFrame then return end
  end
  if ToggleQuestLog then pcall(ToggleQuestLog) end
end
function TR:Focus(id)
  if Q.char.focus == id then Q.char.focus = nil; Q:Print("focus off - back to the normal route")
  else Q.char.focus = id; local i = QS:Info(id); Q:Print("focus: " .. ((i and i.title) or id) .. " - the route goes there first") end
  P:BuildAsync()
  TR:Refresh()
end
-- add / remove a quest; adding also adds the earlier chain quests it needs (Q.char.forced[q] = the quest
-- you picked, so taking it off takes its chain off too)
function TR:Force(id, on)
  Q.char.forced = Q.char.forced or {}
  if on then
    for q in pairs(P.NeedChain(id)) do
      if not Q.char.forced[q] then Q.char.forced[q] = id end
      Q.char.skipped[q] = nil
    end
    Q.char.forced[id] = id
  else
    local root = Q.char.forced[id] or id
    for q, r in pairs(Q.char.forced) do if q == id or r == root then Q.char.forced[q] = nil end end
  end
  P:BuildAsync()
  TR:Refresh()
end
function TR:Link(id)
  local e = QS.log[id]
  local link = GetQuestLink and GetQuestLink(id)
  if not link then link = ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, (e and e.level) or 0, (e and e.title) or ("Quest " .. id)) end
  if ChatEdit_InsertLink then ChatEdit_InsertLink(link) elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link) end
end
function TR:ShowOnMap(id)
  local z = P.QuestZone and P.QuestZone(id)
  if not (WorldMapFrame and z) then return end
  if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
  if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, z) end
end
function TR:Abandon(id)
  if Q.Cleanup and Q.Cleanup.AbandonOne then Q.Cleanup:AbandonOne(id); return end
  if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
    C_QuestLog.SetSelectedQuest(id); C_QuestLog.SetAbandonQuest(); C_QuestLog.AbandonQuest()
  end
end

-- right-click menu (Questicus' own, like the guide's)
local menu
local menuBtns = {}
function TR:Menu(id, anchor)
  if not menu then
    menu = CreateFrame("Frame", "QuesticusTrackerMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    T.RFill(menu, { T.c.bg[1], T.c.bg[2], T.c.bg[3], 0.98 }, 6)
    T.Border(menu, T.c.line, 6)
    menu.title = T.Text(menu, 11, T.c.gold)
    menu.title:SetPoint("TOPLEFT", 8, -7)
    menu.title:SetPoint("RIGHT", -8, 0)
    menu.title:SetWordWrap(false)
    local away = 0
    menu:SetScript("OnUpdate", function(self, el)
      if self:IsMouseOver() or (TR.menuAnchor and TR.menuAnchor:IsMouseOver()) then away = 0 return end
      away = away + el
      if away > 1.2 then self:Hide() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuesticusTrackerMenu") end
  end
  local inLog = QS.log[id] ~= nil
  local items = {}
  local function add(text, fn) items[#items + 1] = { text, fn } end
  add(Q.char.focus == id and "Stop focusing" or "Focus (go here first)", function() TR:Focus(id) end)
  local forced = Q.char.forced and Q.char.forced[id]
  if forced then add("Take off my route", function() TR:Force(id, false) end)
  else add("Add to my route", function() TR:Force(id, true) end) end
  if Q.char.skipped[id] then add("Back on the route", function() Q.char.skipped[id] = nil; QS:BuildPool(); P:BuildAsync() end)
  else add("Skip (leave off the route)", function() if P.SkipQuest then P:SkipQuest(id) end end) end
  if inLog then add("Open in the quest log", function() TR:OpenLog(id) end) end
  add("Fold / unfold", function() TR:Fold(id) end)
  add("Show on map", function() TR:ShowOnMap(id) end)
  add("Link in chat", function() TR:Link(id) end)
  if inLog then add("Abandon", function() TR:Abandon(id) end) end
  local i = QS:Info(id)
  menu.title:SetText((i and i.title) or (QS.log[id] and QS.log[id].title) or ("Quest " .. id))
  for k, it in ipairs(items) do
    local b = menuBtns[k]
    if not b then b = T.Button(menu, "", 176, 20); menuBtns[k] = b end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 6, -24 - (k - 1) * 22)
    b:SetText(it[1])
    b:SetScript("OnClick", function() menu:Hide(); it[2]() end)
    b:Show()
  end
  for k = #items + 1, #menuBtns do menuBtns[k]:Hide() end
  menu:SetSize(188, 30 + #items * 22)
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor or UIParent, "TOPLEFT", -4, 0)
  TR.menuAnchor = anchor
  menu:Show()
  return items
end

-- ------------------------------------------------------------------ add a quest (search)
local search
function TR:Search()
  if not search then
    search = T.Window("QuesticusTrackerAdd", 320, 300, "Add a quest to your route", nil)
    search.box = CreateFrame("EditBox", nil, search)
    search.box:SetSize(290, 22)
    search.box:SetPoint("TOPLEFT", 14, -34)
    search.box:SetAutoFocus(true)
    search.box:SetFontObject(ChatFontNormal)
    T.RFill(search.box, { T.c.bg[1] * 0.6, T.c.bg[2] * 0.6, T.c.bg[3] * 0.6, 1 }, 4)
    search.box:SetTextInsets(6, 6, 0, 0)
    search.box:SetScript("OnEscapePressed", function() search:Hide() end)
    search.box:SetScript("OnTextChanged", function() Q.Throttle("trsearch", 0.25, function() TR:SearchResults() end) end)
    search.results = {}
  end
  if Q.Bosses then Q.Bosses.Front(search) else search:Show() end
  search.box:SetText("")
  TR:SearchResults()
  return search
end
function TR:SearchResults(text)
  local q = (text or (search and search.box:GetText()) or ""):lower()
  local found = {}
  if #q >= 3 then
    for _, id in ipairs(QS.pool or {}) do
      local info = QS:Info(id)
      if info and not QS.done[id] and not QS.log[id] and info.title:lower():find(q, 1, true) then
        found[#found + 1] = info
        if #found >= 10 then break end
      end
    end
  end
  for i, info in ipairs(found) do
    local b = search and search.results[i]
    if search and not b then b = T.Button(search, "", 290, 20); search.results[i] = b end
    if b then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 14, -62 - (i - 1) * 22)
      b:SetText(("[%d] %s"):format(info.level, info.title))
      b:SetScript("OnClick", function() TR:Force(info.id, true); Q:Print("added to your route: " .. info.title); search:Hide() end)
      b:Show()
    end
  end
  if search then for i = #found + 1, #search.results do search.results[i]:Hide() end end
  return found
end

-- ------------------------------------------------------------------ settings
local opt
function TR:Settings()
  if not opt then
    opt = T.Window("QuesticusTrackerOptions", 300, 420, "Quest tracker", nil)
    local y = -34
    local function check(text, key, tip)
      local b = T.Check(opt, text, function() return cfg()[key] end, function(v) cfg()[key] = v; TR:ApplyBlizzard(); TR:Refresh() end, tip)
      b:SetPoint("TOPLEFT", 14, y)
      y = y - 24
      return b
    end
    check("Show the tracker", "on")
    check("Progress bars", "bars", "A bar under each objective with a count (8/10).")
    check("Quest levels", "levels")
    check("Hide finished objectives", "hideDone")
    check("Fold quests that are done", "collapseDone")
    check("Only quests on my route", "onlyRoute")
    check("Hide the game's own tracker", "hideBlizzard")
    check("Lock in place", "locked")
    local lbl = T.Text(opt, 11, T.c.dim); lbl:SetPoint("TOPLEFT", 14, y - 2); lbl:SetText("Order"); y = y - 18
    local seg = T.Segments(opt, { { "route", "Route" }, { "zone", "Zone" }, { "level", "Level" } },
      function() return cfg().sort end, function(v) cfg().sort = v; TR:Refresh() end, 80)
    seg:SetPoint("TOPLEFT", 14, y); y = y - 30
    local function stepper(text, key, step, lo, hi)
      local l = T.Text(opt, 11, T.c.dim); l:SetPoint("TOPLEFT", 14, y - 4)
      local function upd() l:SetText(("%s: %s"):format(text, tostring(cfg()[key]))) end
      upd()
      local minus = T.Button(opt, "-", 24, 18); minus:SetPoint("TOPLEFT", 180, y)
      local plus = T.Button(opt, "+", 24, 18); plus:SetPoint("LEFT", minus, "RIGHT", 6, 0)
      minus:SetScript("OnClick", function() cfg()[key] = math.max(lo, cfg()[key] - step); upd(); TR:Refresh() end)
      plus:SetScript("OnClick", function() cfg()[key] = math.min(hi, cfg()[key] + step); upd(); TR:Refresh() end)
      y = y - 24
    end
    stepper("Width", "width", 20, 180, 420)
    stepper("Font size", "font", 1, 9, 16)
    stepper("Background", "alpha", 0.1, 0.1, 1)
    stepper("Max height", "maxHeight", 40, 200, 900)
  end
  if Q.Bosses then Q.Bosses.Front(opt) else opt:Show() end
end

-- the game's own objective tracker (out of combat only: it's part of the protected UI layout)
function TR:ApplyBlizzard()
  local f = ObjectiveTrackerFrame or WatchFrame
  if not f or (InCombatLockdown and InCombatLockdown()) then return end
  local hide = cfg().on and cfg().hideBlizzard
  if hide then
    if not TR.hooked and f.HookScript then
      TR.hooked = true
      f:HookScript("OnShow", function(s)
        if cfg().on and cfg().hideBlizzard and not (InCombatLockdown and InCombatLockdown()) then s:Hide() end
      end)
    end
    f:Hide()
  elseif not f:IsShown() then
    f:Show()
  end
end

-- ------------------------------------------------------------------ build
function TR:Build()
  if frame then return end
  local c = cfg()
  frame = T.Window("QuesticusTracker", c.width, 200, "Quests", c)
  frame.close:Hide()
  if not c.at then frame:ClearAllPoints(); frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 60) end
  -- buttons in the title: add a quest, settings, fold all
  local function tbtn(icon, tip, fn, prev)
    local b = CreateFrame("Button", nil, frame.bar)
    b:SetSize(18, 18)
    b:SetPoint("RIGHT", prev or frame.bar, prev and "LEFT" or "RIGHT", prev and -2 or -6, 0)
    b.t = b:CreateTexture(nil, "OVERLAY"); b.t:SetSize(14, 14); b.t:SetPoint("CENTER"); b.t:SetTexture(icon)
    b.t:SetAlpha(0.75)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(s) s.t:SetAlpha(1); GameTooltip:SetOwner(s, "ANCHOR_BOTTOM"); GameTooltip:AddLine(tip, 1, 1, 1); GameTooltip:Show() end)
    b:SetScript("OnLeave", function(s) s.t:SetAlpha(0.75); GameTooltip:Hide() end)
    return b
  end
  frame.cog = tbtn("Interface\\Icons\\Trade_Engineering", "Tracker settings", function() TR:Settings() end)
  frame.add = tbtn("Interface\\PaperDollInfoFrame\\Character-Plus", "Add a quest to your route", function() TR:Search() end, frame.cog)
  -- fold the whole tracker to its title bar
  frame.collapse = tbtn("Interface\\Buttons\\Arrow-Up-Up", "Fold the tracker (just the title) / open it", function()
    c.collapsed = not c.collapsed or nil
    TR:Refresh()
  end, frame.add)
  frame.fold = tbtn("Interface\\Buttons\\UI-MinusButton-Up", "Fold / unfold all quests", function()
    Q.char.trackCollapsed = Q.char.trackCollapsed or {}
    local any = next(Q.char.trackCollapsed) ~= nil
    wipe(Q.char.trackCollapsed)
    if not any then for id in pairs(QS.log) do Q.char.trackCollapsed[id] = true end end
    TR:Refresh()
  end, frame.collapse)
  local sc = CreateFrame("ScrollFrame", nil, frame)
  sc:SetPoint("TOPLEFT", 6, -28)
  sc:SetPoint("BOTTOMRIGHT", -6, 6)
  body = CreateFrame("Frame", nil, sc)
  body:SetSize(c.width - 12, 1)
  sc:SetScrollChild(body)
  if sc.EnableMouseWheel then sc:EnableMouseWheel(true) end
  sc:SetScript("OnMouseWheel", function(self, d)
    local max = math.max(0, (body:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 30)))
    TR:Thumb()
  end)
  frame.scroll = sc
  frame.thumb = frame:CreateTexture(nil, "OVERLAY")
  frame.thumb:SetWidth(3)
  frame.thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
  frame.thumb:SetVertexColor(T.c.line[1], T.c.line[2], T.c.line[3], 0.9)
  frame.thumb:Hide()
  -- resize from the bottom-right corner (the list scrolls when it doesn't fit); right-click: fit the list
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(180, 80, 600, 1000)
  elseif frame.SetMinResize then frame:SetMinResize(180, 80); frame:SetMaxResize(600, 1000) end
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" and not c.locked and not (InCombatLockdown and InCombatLockdown()) then
      TR.sizing = true
      frame:StartSizing("BOTTOMRIGHT")
    end
  end)
  grip:SetScript("OnMouseUp", function(_, btn)
    if btn ~= "LeftButton" or TR.sizing ~= true then return end
    TR.sizing = nil
    frame:StopMovingOrSizing()
    c.width = math.floor((frame:GetWidth() or c.width) + 0.5)
    c.height = math.floor((frame:GetHeight() or 200) + 0.5)
    local pt, _, _, x, yy = frame:GetPoint()
    c.at = { pt, x, yy }
    TR:Refresh()
  end)
  grip:SetScript("OnClick", function() c.height = nil; TR:Refresh() end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize", 1, 1, 1)
    GameTooltip:AddLine("Right-click: fit the list again", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.grip = grip
  frame:HookScript("OnSizeChanged", function()
    body:SetWidth(math.max(50, (frame:GetWidth() or c.width) - 12))
    TR:Thumb()
  end)
end

local function refresh() Q.Throttle("tracker", 0.2, function() TR:Refresh() end) end
Q:On("QC_READY", function()
  TR:Build()
  TR:ApplyBlizzard()
  TR:Refresh()
end)
Q:On("QC_QUESTS_CHANGED", refresh)
Q:On("QC_PLAN_UPDATED", refresh)
Q:On("QUEST_LOG_UPDATE", refresh)
Q:On("PLAYER_REGEN_ENABLED", function() TR:ApplyBlizzard() end)
-- a focused / added quest you've handed in is done with
Q:On("QUEST_TURNED_IN", function(id)
  if id and Q.char.focus == id then Q.char.focus = nil end
  if id and Q.char.forced then Q.char.forced[id] = nil end
end)
Q:On("QUEST_REMOVED", function(id)
  if id and Q.char.focus == id and not QS.log[id] then Q.char.focus = nil end
end)

Q:Command("tracker", "the quest tracker: /qc tracker (show / hide), /qc tracker options", function(arg)
  if arg == "options" or arg == "settings" then TR:Settings(); return end
  cfg().on = not cfg().on
  TR:ApplyBlizzard()
  TR:Refresh()
end)
