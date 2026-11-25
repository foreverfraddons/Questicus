-- Questicus guide window: the current step big and clear, the next few steps below, and the
-- quest objectives with live progress. The arrow and the map pins follow the current step.
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local GD = {}
Q.Guide = GD

local WIDTH = 330
local ICON = {
  accept = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  kill = "Interface\\Icons\\Ability_DualWield",
  loot = "Interface\\Icons\\INV_Misc_Bag_08",
  use = "Interface\\Icons\\INV_Misc_Gear_01",
  explore = "Interface\\Icons\\INV_Misc_Map_01",
  buy = "Interface\\Icons\\INV_Misc_Coin_02",
  fly = "Interface\\Icons\\Ability_Mount_Wyvern_01",
  hearth = "Interface\\Icons\\INV_Misc_Rune_01",
  fp = "Interface\\Icons\\INV_Misc_Map02",
  boat = "Interface\\Icons\\INV_Misc_Spyglass_03",
  zeppelin = "Interface\\Icons\\INV_Misc_Spyglass_03",
}
GD.ICON = ICON
local gold, white, dim, good, accent = T.HEX.gold, T.HEX.white, T.HEX.dim, T.HEX.good, T.HEX.accent
local function c(hex, s) return "|cff" .. hex .. s .. "|r" end

local frame, cur, rows = nil, nil, {}
GD.focus = 1

-- ------------------------------------------------------------------ text
local function itemText(id)
  local name, link = Q.GetItemInfo(id)
  if link then return link end
  return c(gold, "[" .. (name or D:Name("i" .. id)) .. "]")
end

-- the dungeon a step takes you into (a "Do ... in <dungeon>" step), or nil
-- the escort quest a step is about (accepting it, or doing it), or nil
function GD.EscortOf(s)
  if not s or (s.type ~= "accept" and s.type ~= "complete") then return nil end
  for _, id in ipairs(s.quests or {}) do
    if P.Kind and P.Kind(id) == "escort" then return id end
  end
end
function GD.DungeonOf(s)
  if not (s and s.type == "complete") then return end
  for _, id in ipairs(s.quests or {}) do
    local m = P.Meta(id)
    if m and m.dungeon then return m.dungeon, m.dungeonName end
  end
end
local function stepIcon(s)
  if GD.DungeonOf(s) then return Q.MEDIA .. "i_dungeon" end
  if s.type == "complete" then
    local m = P.Meta(s.quests[1])
    local first = m and m.lines and m.lines[1]
    return ICON[first and first.kind or "kill"] or ICON.kill
  end
  if s.type == "boat" then return ICON[s.kind or "boat"] or ICON.boat end
  if s.type == "prep" then return ICON.kill end
  return ICON[s.type] or ICON.accept
end

function GD.StepText(s, short)
  if s.type == "accept" and s.startItem then
    return "Use " .. itemText(s.startItem) .. " to start " .. c(gold, s.title)
  elseif s.type == "accept" then
    return "Accept " .. c(gold, s.title) .. (short and "" or (" from " .. c(white, s.npc)))
  elseif s.type == "turnin" then
    return "Turn in " .. c(gold, s.title) .. (short and "" or (" to " .. c(white, s.npc)))
  elseif s.type == "buy" then
    return "Buy " .. itemText(s.item) .. " from " .. c(white, s.npc) .. c(good, (" +%d%%"):format(math.floor(s.pct or 0)))
  elseif s.type == "fly" then
    return "Fly to " .. c(gold, s.to.name) .. (short and "" or (" from " .. c(white, s.from.name)))
  elseif s.type == "hearth" then
    return "Hearth to " .. c(gold, (s.to and s.to.name) or "your inn")
  elseif s.type == "fp" then
    return "Get the flight path at " .. c(gold, s.node.name)
  elseif s.type == "explore" then
    return "Explore " .. c(gold, s.area and s.area.name or "this area")
  elseif s.type == "prep" then
    return c(gold, "Before the dungeon: ") .. (s.prep and s.prep.text or "")
  elseif s.type == "boat" then
    return ("Take the %s to "):format(s.kind or "boat") .. c(gold, s.toName or "the other continent") ..
      (short and "" or (" - at " .. c(white, s.from and s.from.place or "the docks")))
  elseif s.type == "complete" then
    local t = {}
    for i, title in ipairs(s.titles or {}) do
      -- a quest done in parts: say which part this step is for
      local q = s.quests and s.quests[i]
      local part = s.partText and q and s.partText[q]
      local m = q and P.Meta(q)
      local whole = m and m.lines and part and #m.lines <= 1
      t[#t + 1] = c(gold, title) .. ((part and part ~= "" and not whole and (s.partial or #s.quests > 1)) and c(dim, " (" .. part .. ")") or "")
    end
    -- a dungeon run: the dungeon is the step (the quests are listed under it)
    if s.dungeon and not short then
      local done = 0
      for _, id in ipairs(s.quests) do
        local e = QS.log[id]
        if (e and e.complete) or (QS.IsDone and QS:IsDone(id)) then done = done + 1 end
      end
      return "Run " .. c("c08cff", s.dungeon) .. c(dim, ("   %d/%d quests done"):format(done, #s.quests))
    end
    return "Do " .. table.concat(t, ", ") .. (s.dungeon and c(T.HEX.bad, " in " .. s.dungeon) or "")
  end
  return s.type
end

-- what the quest itself says to do: the line under its title in the quest log ("Use the Holy Water
-- on the corrupted Moonwell"), from the game for quests in your log, else what was recorded when you
-- (or anyone, through ForeverDB) read it at the quest giver. Cached per quest.
local howCache = {}
Q:On("QUEST_ACCEPTED", function(a, b) local id = b or a; if id then howCache[id] = nil end end)
function GD.HowText(id)
  local h = howCache[id]
  if h ~= nil then return h or nil end
  local txt
  local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
  if idx and GetQuestLogQuestText then
    local ok, _, obj = pcall(GetQuestLogQuestText, idx)
    if ok and type(obj) == "string" and not Q.Secret(obj) and obj ~= "" then txt = obj end
  end
  if not txt then
    local rec = (QuesticusCollect and QuesticusCollect.qinfo and QuesticusCollect.qinfo[id]) or (D.db and D.db.qinfo and D.db.qinfo[id])
    if rec and type(rec.o) == "string" and rec.o ~= "" then txt = rec.o end
  end
  if txt then txt = txt:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") end
  -- not cached until the game has it (the log's text loads a moment after accepting)
  if txt or not idx then howCache[id] = txt or false end
  return txt
end

-- where an objective comes from, by its name in the quest's planning data: "(drops from Kobold
-- Vermin)", "(from Raw Windstone)", "(sold by ...)"
local function sourceHint(id, text)
  local m = P.Meta(id)
  if not (m and m.lines and type(text) == "string") then return "" end
  -- the line this objective is (by name, or by kind in another language)
  local e = QS.log[id]
  if e and e.objectives then
    local _, byObj = P.MatchObjectives(id, m, e)
    for oi, o in ipairs(e.objectives) do
      local l = o.text == text and byObj[oi] and m.lines[byObj[oi]]
      if l and l.from then
        local who = D:Name(l.from)
        if who and who ~= "" then
          if l.kind == "buy" then return c(dim, " (sold by " .. who .. ")") end
          return c(dim, (l.from:sub(1, 1) == "o" and " (from " or " (drops from ") .. who .. ")")
        end
      end
    end
  end
  local t = text:lower()
  for _, l in ipairs(m.lines) do
    if l.name and l.from and t:find(tostring(l.name):lower(), 1, true) then
      local kind = l.from:sub(1, 1)
      local who = D:Name(l.from)
      if who and who ~= "" then
        if l.kind == "buy" then return c(dim, " (sold by " .. who .. ")") end
        return c(dim, (kind == "o" and " (from " or " (drops from ") .. who .. ")")
      end
    end
  end
  return ""
end

-- objective lines with live progress (from the quest log when the quest is there), plus how to do
-- it: the quest's own line, the quest item to use and on what, where items come from
local function objectiveLines(s)
  local out = {}
  local items = Q.QuestItem and Q.QuestItem.Items and Q.QuestItem:Items() or {}
  for _, id in ipairs(s.quests) do
    local e = QS.log[id]
    local how = GD.HowText(id)
    if how and not (e and e.complete) then
      out[#out + 1] = c(T.HEX.gold, "  How: ") .. c(white, how)
    end
    -- the quest's item to use (the quest item button / its key binding)
    local item = items[id]
    if item and not (e and e.complete) then
      local key = GetBindingKey and GetBindingKey("CLICK QuesticusQuestItem:LeftButton")
      local target
      local m = P.Meta(id)
      local open = m and P.OpenLines(id, m) or {}
      for li, l in ipairs(m and m.lines or {}) do
        if open[li] and (l.kind == "kill" or l.kind == "use") and l.name then target = l.name break end
      end
      out[#out + 1] = c(T.HEX.gold, "  Use ") .. itemText(item) .. (target and (" on " .. c(white, target)) or "") ..
        c(dim, key and (" (quest item button or " .. key .. ")") or " (the quest item button)")
    end
    if e and e.objectives and #e.objectives > 0 then
      for _, o in ipairs(e.objectives) do
        local txt = o.text or ""
        out[#out + 1] = o.finished and c(dim, "  - " .. txt) or ("  - " .. txt .. sourceHint(id, txt))
      end
    else
      local m = P.Meta(id)
      for _, l in ipairs(m and m.lines or {}) do
        local verb = ({ kill = "Kill ", loot = "Get ", use = "Use ", explore = "", buy = "Buy " })[l.kind] or ""
        local from = l.from and (c(dim, " (" .. D:Name(l.from) .. ")")) or ""
        out[#out + 1] = "  - " .. verb .. c(white, l.name) .. from
      end
    end
  end
  return out
end

-- a dungeon run, tidy: each quest's name, then what's left of it on short lines (no quest text)
local function dungeonLines(s)
  local out = {}
  local items = Q.QuestItem and Q.QuestItem.Items and Q.QuestItem:Items() or {}
  for k, id in ipairs(s.quests) do
    local e = QS.log[id]
    local title = (s.titles and s.titles[k]) or (QS:Info(id) or {}).title or ("Quest " .. id)
    if k > 1 then out[#out + 1] = " " end
    out[#out + 1] = c("c08cff", "|TInterface\\GossipFrame\\ActiveQuestIcon:12|t ") .. c(gold, title)
    if e and e.complete then
      out[#out + 1] = "     " .. c(good, "done - hand it in")
    elseif e and e.objectives and #e.objectives > 0 then
      for _, o in ipairs(e.objectives) do
        local txt = o.text or ""
        out[#out + 1] = "     " .. (o.finished and c(dim, txt) or (c(white, txt) .. sourceHint(id, txt)))
      end
    else
      local m = P.Meta(id)
      for _, l in ipairs(m and m.lines or {}) do
        local verb = ({ kill = "Kill ", loot = "Get ", use = "Use ", explore = "", buy = "Buy " })[l.kind] or ""
        out[#out + 1] = "     " .. verb .. c(white, l.name) .. (l.from and c(dim, "  " .. D:Name(l.from)) or "")
      end
    end
    local item = items[id]
    if item and not (e and e.complete) then out[#out + 1] = "     " .. c(dim, "use ") .. itemText(item) end
  end
  return out
end
GD.DungeonLines = dungeonLines

-- ------------------------------------------------------------------ current target
-- The point the arrow should point at: for objective steps, the nearest spot of an objective
-- that is not finished yet.
-- (the arrow, map, minimap and waypoint all ask many times a second: the answer for a "complete"
-- step is worked out at most 4 times a second, or at once when the quest log / spots change)
local tcache = {}
GD.tver = 0
Q:On("QC_QUESTS_CHANGED", function() GD.tver = GD.tver + 1 end)
Q:On("QC_PLAN_UPDATED", function() GD.tver = GD.tver + 1 end)
function GD:Target(index)
  local idx = index or GD.focus
  if idx == GD.focus and Q.Nav and Q.Nav.StepKey then
    local st = P.steps and P.steps[idx]
    Q.Nav.focusKey = Q.Nav.StepKey(st)
    -- walking to a person, a flight master, a place or an object: exact; mobs: as before (they wander)
    Q.Nav.precise = st and st.type ~= "complete" or false
  end
  local s = P.steps and P.steps[idx]
  if not s then return end
  if s.type ~= "complete" then return s.point, s end
  if s.unknown then return D:QuestWaypoint(s.quests[1]) or s.point, s end
  local c = tcache[idx]
  local now = GetTime and GetTime() or 0
  if c and c.s == s and c.ver == GD.tver and now - c.t < 0.25 and not (Q.Spots and Q.Spots.dirty) then
    if idx == GD.focus then GD.targetOf = c.of end
    return c.p, s, c.of
  end
  local p1, _, of1 = GD:TargetNow(idx, s)
  c = c or {}
  tcache[idx] = c
  c.s, c.ver, c.t, c.p, c.of = s, GD.tver, now, p1, of1
  return p1, s, of1
end
function GD:TargetNow(index, s)
  local here = D:PlayerPos()
  -- only objectives that aren't finished: the arrow moves on to the next one by itself
  -- remember which quest / objective the chosen spot belongs to (the arrow names that one)
  local pts, of = {}, {}
  local entries = P.StepPoints(s)
  for _, e in ipairs(entries) do pts[#pts + 1] = e.p; of[e.p] = e end
  if #pts == 0 then return s.point, s end
  local best
  -- the arrow's step: closest open spot leaning toward the next step, spots just used / found empty
  -- left alone until they respawn (Spots.lua)
  if Q.Spots and (index == nil or index == GD.focus) then
    -- (the arrow asks every frame: choose at most 4 times a second, unless a spot changed)
    local now = GetTime()
    local c = GD.spotPick
    if c and c.s == s and now - c.t < 0.25 and not Q.Spots.dirty and of[c.p] then
      best = c.p
    else
      Q.Spots.entries = entries
      -- a mob for this step in view: don't point at a marker somewhere else - the spot of that mob
      -- nearest to you (the arrow says it's right there when it's close)
      local vis, close = Q.Spots.Visible and Q.Spots.Visible(entries)
      GD.inView = vis and { src = vis, close = close } or nil
      local pick
      if vis and here then
        local bd
        for _, e in ipairs(entries) do
          if Q.Spots.Source(e.p) == vis and e.p.i == here.i then
            local d = D.Dist(here, e.p)
            if not bd or d < bd then pick, bd = e, d end
          end
        end
        -- no known spawn of it anywhere near where you can see it (beyond nameplate range): the mob is
        -- standing somewhere the database doesn't know - pointing at a far marker would lead you away
        local range = Q.Spots.PlateRange and Q.Spots.PlateRange() or 40
        if not bd or bd > range + 10 then GD.inView.far = true end
      end
      pick = pick or Q.Spots.Choose(entries, here, index or GD.focus)
      best = pick and pick.p
      local src = best and Q.Spots.Source(best)
      if Q.Nav and (index or GD.focus) == GD.focus then Q.Nav.precise = src ~= nil and src:sub(1, 1) == "o" end
      c = GD.spotPick or {}
      GD.spotPick = c
      c.s, c.t, c.p = s, now, best
    end
  end
  best = best or D.Nearest(here or s.point, pts)
  local e = best and of[best]
  local tof = e and { id = e.id, li = e.li, key = best.key } or nil
  if (index or GD.focus) == GD.focus then GD.targetOf = tof end
  return best or s.point, s, tof
end

-- Mobs for other quests in your log that live along the way to this step: kill them as you pass.
-- Returns "Name (Quest)" strings; also fills GD.wayKeys (npc keys) for the nameplate marks.
function GD:OnTheWay(s)
  local out, keys, named = {}, {}, {}
  GD.wayKeys = keys
  local here = D:PlayerPos()
  local tgt = GD:Target()
  if not here or not tgt or here.i ~= tgt.i then return out end
  local path = (Q.Nav and Q.Nav:Route(here, tgt)) or { tgt }
  local legs, a = {}, here
  for _, p in ipairs(path) do legs[#legs + 1] = { a, p }; a = p end
  local function nearPath(p)
    if p.i ~= here.i then return false end
    for _, l in ipairs(legs) do
      local ax, ay, bx, by = l[1].x, l[1].y, l[2].x, l[2].y
      local dx, dy = bx - ax, by - ay
      local len2 = dx * dx + dy * dy
      local t = len2 > 0 and math.max(0, math.min(1, ((p.x - ax) * dx + (p.y - ay) * dy) / len2)) or 0
      local cx, cy = ax + dx * t, ay + dy * t
      if (p.x - cx) ^ 2 + (p.y - cy) ^ 2 < 120 * 120 then return true end
    end
    return false
  end
  local skip = {}
  for _, id in ipairs(s.quests or {}) do skip[id] = true end
  for id, e in pairs(QS.log) do
    if not e.complete and not skip[id] then
      local m = P.Meta(id)
      local open = m and m.lines and P.OpenLines(id, m) or {}
      for li, l in ipairs(m and m.lines or {}) do if open[li] then
        -- kill targets, and EVERY mob that can drop a quest item (not just the best one)
        local cands = {}
        if l.kind == "kill" then cands[1] = l.key
        elseif l.kind == "loot" then
          for _, src in ipairs(D:ItemSources(tonumber(l.key:sub(2)))) do
            if not src.vendor then cands[#cands + 1] = src.key end
          end
        end
        for _, srcKey in ipairs(cands) do
          if srcKey:sub(1, 1) == "c" and not keys[srcKey] then
            for _, p in ipairs(D:Points(srcKey)) do
              if not p.dungeon and nearPath(p) then
                keys[srcKey] = id
                if not named[id] then
                  named[id] = true
                  out[#out + 1] = c(white, (QS:Info(id) and QS:Info(id).title) or e.title or ("Quest " .. id))
                end
                break
              end
            end
          end
        end
      end end
    end
  end
  return out
end

-- ------------------------------------------------------------------ frame
-- ------------------------------------------------------------------ right-click menu
local menu, menuAnchor
local function menuItems(index)
  local s = (index == 0) and P.prevStep or (P.steps and P.steps[index])
  if not s then return {} end
  local items = {}
  local function add(text, tip, fn) items[#items + 1] = { text, tip, fn } end
  -- the step you just finished: notes only
  if index == 0 then
    if Q.Author then Q.Author:MenuItems(s, 0, add) end
    return items
  end
  local ids = s.quests or {}
  add("Details", "Everything about this step", function() if Q.Details then Q.Details:Show(index) end end)
  add("Point the arrow here", "Make this the step the arrow and map follow", function() GD.focus = index; GD:Refresh() end)
  if #ids > 0 then
    add("Do this next", "Put this quest first in the route", function()
      wipe(P.prefer); wipe(P.later)
      for _, id in ipairs(ids) do P.prefer[id] = true end
      GD.focus = 1; P:Build()
    end)
    add("Skip for now", "Move it to the back of the route for this session", function()
      for _, id in ipairs(ids) do P.later[id] = true; P.prefer[id] = nil end
      GD.focus = 1; P:Build()
    end)
    add("Remove from route", "Never route this quest again (/qc unskip brings it back)", function()
      for _, id in ipairs(ids) do Q.char.skipped[id] = true end
      GD.focus = 1; P:SkipQuest(ids[1])
      Q:Print("removed from the route: " .. (s.title or (s.titles and table.concat(s.titles, ", ")) or ""))
    end)
  elseif s.type == "hearth" then
    add("Don't hearth this time", "Leave the hearthstone out of the route for 30 minutes", function()
      Q.Flight.noHearthUntil = (GetTime and GetTime() or 0) + 1800
      GD.focus = 1; P:Build()
    end)
    add("Never hearth in routes", "Turn the hearthstone off in the route (Options to turn back on)", function()
      Q.prefs.hearth = false
      GD.focus = 1; P:Build()
    end)
  elseif s.type == "fly" then
    add("Don't fly this time", "Run instead for the next 10 minutes", function()
      Q.Flight.noFlyUntil = (GetTime and GetTime() or 0) + 600
      GD.focus = 1; P:Build()
    end)
    add("Never fly in routes", "Turn flight paths off in the route (Options to turn back on)", function()
      Q.prefs.flights = false
      GD.focus = 1; P:Build()
    end)
  elseif s.type == "explore" then
    add("Skip for now", "Leave this area for later", function()
      P.later["explore" .. s.area.key] = true; GD.focus = 1; P:Build()
    end)
    add("No exploring in routes", "Completionist without the map exploration (/qc explore to turn back on)", function()
      Q.char.noExplore = true; GD.focus = 1; P:Build()
    end)
  elseif s.type == "fp" then
    add("Skip for now", "Leave this flight path for later", function()
      P.later["fp" .. s.node.id] = true; GD.focus = 1; P:Build()
    end)
    add("Remove from route", "Never send me to this flight master", function()
      Q.char.noFP = Q.char.noFP or {}
      Q.char.noFP[s.node.id] = true
      GD.focus = 1; P:Build()
    end)
  elseif s.type == "buy" then
    add("Remove from route", "Not worth going for - don't suggest this item again", function()
      Q.Gear:Deny(s.item, "trip"); GD.focus = 1; P:Build()
    end)
  end
  if Q.Author then Q.Author:MenuItems(s, index, add) end
  if Q.char.dmode then
    add("Leave dungeon mode", "Back to your normal route", function() P:DungeonMode(nil); GD.focus = 1 end)
  end
  if next(P.prefer) or next(P.later) then
    add("Back to the normal order", "Forget \"do this next\" / \"skip for now\"", function()
      wipe(P.prefer); wipe(P.later); GD.focus = 1; P:Build()
    end)
  end
  return items
end

function GD:Menu(index, anchor)
  if not menu then
    menu = CreateFrame("Frame", "QuesticusStepMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    T.RFill(menu, { T.c.bg[1], T.c.bg[2], T.c.bg[3], 0.98 }, 6)
    T.Border(menu, T.c.line, 6)
    menu.title = T.Text(menu, 11, T.c.gold)
    menu.title:SetPoint("TOPLEFT", 8, -7)
    menu.title:SetPoint("RIGHT", -8, 0)
    menu.title:SetWordWrap(false)
    menu.buttons = {}
    -- close when the mouse has been away for a moment
    local away = 0
    menu:SetScript("OnUpdate", function(self, el)
      if self:IsMouseOver() or (menuAnchor and menuAnchor:IsMouseOver()) then away = 0 return end
      away = away + el
      if away > 1.2 then self:Hide() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuesticusStepMenu") end
  end
  local items = menuItems(index)
  local s = (index == 0) and P.prevStep or P.steps[index]
  if not s then return items end
  menu.title:SetText(index == 0 and ("Last step: " .. GD.StepText(s, true)) or ("Step %d: %s"):format(index, GD.StepText(s, true)))
  for i, it in ipairs(items) do
    local b = menu.buttons[i]
    if not b then
      b = T.Button(menu, "", 196, 20)
      menu.buttons[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 22)
    b:SetText(it[1])
    b.tip = it[2]
    b:SetScript("OnClick", function() menu:Hide(); it[3]() end)
    b:Show()
  end
  for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetSize(208, 30 + #items * 22)
  menu:ClearAllPoints()
  local x, y
  if GetCursorPosition then x, y = GetCursorPosition() end
  local sc = UIParent:GetEffectiveScale() or 1
  if x and y then menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc - 4, y / sc + 4)
  else menu:SetPoint("TOPLEFT", anchor or UIParent, "BOTTOMLEFT") end
  menuAnchor = anchor
  menu:Show()
  return items
end

local function newRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(20)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("LEFT", 6, 0)
  r.stripe = r:CreateTexture(nil, "ARTWORK")
  r.stripe:SetTexture("Interface\\Buttons\\WHITE8x8")
  r.stripe:SetPoint("TOPLEFT", 0, -2)
  r.stripe:SetPoint("BOTTOMLEFT", 0, 2)
  r.stripe:SetWidth(3)
  r.text = T.Text(r, 11, T.c.dim)
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.text:SetPoint("RIGHT", -6, 0)
  r.text:SetWordWrap(false)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.06) end
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r:SetScript("OnClick", function(self, btn)
    if btn == "RightButton" then GD:Menu(self.index, self); return end
    GD.focus = self.index
    GD:Refresh()
    if Q.Details then Q.Details:Show(self.index) end
  end)
  r:SetScript("OnEnter", function(self)
    local s = P.steps[self.index]
    if not s then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GD.StepText(s), 1, 1, 1, true)
    for _, l in ipairs(objectiveLines(s)) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8, true) end
    if Q.Details then Q.Details:TooltipLines(GameTooltip, s) end
    for _, n in ipairs(Q.Author and Q.Author:NotesFor(s) or {}) do GameTooltip:AddLine("Note: " .. n, 0.88, 0.69, 0.29, true) end
    GameTooltip:AddLine("Click: details, and point the arrow here - right-click: more (remove, do next ...)", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function build()
  local g = Q.db.guide
  frame = T.Window("QuesticusGuide", g.w or WIDTH, g.h or 200, "Questicus", g)
  -- a spot you've put it in stays: Command Center's dock opens it there instead of out of its icon
  -- (ccOwnSpot), and the minimap button / commands bring it back there
  if g.at then frame.ccOwnSpot = true end
  frame.bar:HookScript("OnDragStop", function()
    frame.ccOwnSpot = true
    frame.__fromDock = nil
  end)
  frame:SetScale(g.scale or 1)
  frame.title:SetText(Q.Color(T.HEX.accent, "Questicus"))
  -- broom: clean up the quest log (quests not in the route, leftover quest items)
  frame.clean = CreateFrame("Button", nil, frame.bar)
  frame.clean:SetSize(20, 20)
  frame.clean:SetPoint("RIGHT", frame.close, "LEFT", -1, 0)
  frame.clean:SetFrameLevel(frame.bar:GetFrameLevel() + 2)
  frame.clean.icon = frame.clean:CreateTexture(nil, "OVERLAY")
  frame.clean.icon:SetSize(15, 15)
  frame.clean.icon:SetPoint("CENTER")
  frame.clean.icon:SetTexture(Q.MEDIA .. "i_clean")          -- own broom icon (the game has no broom icon file)
  frame.clean.icon:SetVertexColor(T.c.dim[1], T.c.dim[2], T.c.dim[3], 1)
  frame.clean:SetScript("OnClick", function() if Q.Cleanup then Q.Cleanup:Show() end end)
  frame.clean:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Clean up quest log", 1, 1, 1)
    GameTooltip:AddLine("Abandon quests that aren't in your route and delete quest items nothing needs. Shows the list first.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  frame.clean:SetScript("OnLeave", function(self)
    self.icon:SetVertexColor(T.c.dim[1], T.c.dim[2], T.c.dim[3], 1)
    GameTooltip:Hide()
  end)
  -- dungeons: every dungeon's info and "get all quests" (dungeon mode)
  frame.dng = CreateFrame("Button", nil, frame.bar)
  frame.dng:SetSize(20, 20)
  frame.dng:SetPoint("RIGHT", frame.clean, "LEFT", -1, 0)
  frame.dng:SetFrameLevel(frame.bar:GetFrameLevel() + 2)
  frame.dng.icon = frame.dng:CreateTexture(nil, "OVERLAY")
  frame.dng.icon:SetSize(15, 15)
  frame.dng.icon:SetPoint("CENTER")
  frame.dng.icon:SetTexture(Q.MEDIA .. "i_dungeon")
  frame.dng.icon:SetVertexColor(T.c.dim[1], T.c.dim[2], T.c.dim[3], 1)
  frame.dng:SetScript("OnClick", function() if Q.Dungeons then Q.Dungeons:Show() end end)
  frame.dng:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Dungeons", 1, 1, 1)
    GameTooltip:AddLine("Levels, bosses, quests, XP and clear time of every dungeon - and \"Get all quests\" to route you through a dungeon's quests.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  frame.dng:SetScript("OnLeave", function(self)
    self.icon:SetVertexColor(T.c.dim[1], T.c.dim[2], T.c.dim[3], 1)
    GameTooltip:Hide()
  end)
  -- zones: which zones the route may use
  frame.zn = CreateFrame("Button", nil, frame.bar)
  frame.zn:SetSize(20, 20)
  frame.zn:SetPoint("RIGHT", frame.dng, "LEFT", -1, 0)
  frame.zn:SetFrameLevel(frame.bar:GetFrameLevel() + 2)
  frame.zn.icon = frame.zn:CreateTexture(nil, "OVERLAY")
  frame.zn.icon:SetSize(15, 15)
  frame.zn.icon:SetPoint("CENTER")
  frame.zn.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  frame.zn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.zn.icon:SetAlpha(0.75)
  frame.zn:SetScript("OnClick", function() if Q.Zones then Q.Zones:Show() end end)
  frame.zn:SetScript("OnEnter", function(self)
    self.icon:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Zones", 1, 1, 1)
    GameTooltip:AddLine("Pick which zones your route may use.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  frame.zn:SetScript("OnLeave", function(self) self.icon:SetAlpha(0.75); GameTooltip:Hide() end)
  frame.lvl = T.Text(frame.bar, 11, T.c.dim)
  frame.lvl:SetPoint("RIGHT", frame.zn, "LEFT", -6, 0)
  -- between the title and the buttons: when the window is narrow it shortens (never runs over the title)
  frame.lvl:SetPoint("LEFT", frame.title, "RIGHT", 8, 0)
  frame.lvl:SetJustifyH("RIGHT")
  frame.lvl:SetWordWrap(false)
  frame.xp = T.Bar(frame, (g.w or WIDTH) - 8, 3)
  frame.xp:SetPoint("TOPLEFT", 4, -26)
  frame.xp:SetPoint("TOPRIGHT", -4, -26)

  cur = CreateFrame("Frame", nil, frame)
  cur:SetPoint("TOPLEFT", 8, -34)
  cur:SetPoint("RIGHT", -8, 0)
  cur.bg = T.RFill(cur, { T.c.bg2[1], T.c.bg2[2], T.c.bg2[3], 0.95 }, 8)
  T.Border(cur, { T.c.accent[1], T.c.accent[2], T.c.accent[3], 0.45 }, 8)
  cur:EnableMouse(true)
  cur:SetScript("OnMouseUp", function(self, btn)
    if btn == "RightButton" then GD:Menu(GD.focus, self); return end
    if btn == "LeftButton" and Q.Details then Q.Details:Toggle(GD.focus) end
  end)
  cur:SetScript("OnEnter", function(self)
    local s = P.steps and P.steps[GD.focus]
    if not s or not Q.Details then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GD.StepText(s), 1, 1, 1, true)
    Q.Details:TooltipLines(GameTooltip, s)
    GameTooltip:AddLine("Click for all details", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  cur:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cur.icon = cur:CreateTexture(nil, "ARTWORK")
  cur.icon:SetSize(28, 28)
  cur.icon:SetPoint("TOPLEFT", 8, -8)
  -- dungeon run: a pulsing glow round the step and a banner, so it's obvious you're on it
  cur.glow = cur:CreateTexture(nil, "BACKGROUND")
  cur.glow:SetPoint("TOPLEFT", -14, 14); cur.glow:SetPoint("BOTTOMRIGHT", 14, -14)
  cur.glow:SetTexture(Q.MEDIA .. "glow")
  cur.glow:SetVertexColor(0.75, 0.45, 1, 0.8)
  cur.glow:Hide()
  cur.banner = CreateFrame("Frame", nil, cur)
  cur.banner:SetHeight(16)
  cur.banner:SetPoint("BOTTOM", cur, "TOP", 0, -8)      -- a tab sitting on the step's top edge, as wide as its text
  cur.banner:SetFrameLevel(cur:GetFrameLevel() + 6)
  T.RFill(cur.banner, { 0.42, 0.22, 0.62, 1 }, 5)
  cur.banner.text = T.Text(cur.banner, 10, { 1, 0.92, 0.7, 1 }, "OUTLINE")
  cur.banner.text:SetPoint("CENTER", 0, 0)
  cur.banner:Hide()
  -- an escort step: the same tab, green
  cur.ebanner = CreateFrame("Frame", nil, cur)
  cur.ebanner:SetHeight(16)
  cur.ebanner:SetPoint("BOTTOM", cur, "TOP", 0, -8)
  cur.ebanner:SetFrameLevel(cur:GetFrameLevel() + 6)
  T.RFill(cur.ebanner, { 0.16, 0.48, 0.22, 1 }, 5)
  cur.ebanner.text = T.Text(cur.ebanner, 10, { 0.9, 1, 0.85, 1 }, "OUTLINE")
  cur.ebanner.text:SetPoint("CENTER", 0, 0)
  cur.ebanner:Hide()
  local pulse = 0
  cur:HookScript("OnUpdate", function(_, el)
    if not cur.glow:IsShown() then return end
    pulse = pulse + el
    cur.glow:SetAlpha(0.45 + 0.35 * math.abs(math.sin(pulse * 2)))
  end)
  cur.num = T.Text(cur, 9, T.c.dim)
  cur.num:SetPoint("TOP", cur.icon, "BOTTOM", 0, -2)
  cur.text = T.Text(cur, 13, T.c.text)
  cur.text:SetPoint("TOPLEFT", cur.icon, "TOPRIGHT", 8, 0)
  cur.text:SetPoint("RIGHT", -8, 0)
  cur.obj = T.Text(cur, 11, T.c.text)
  cur.obj:SetPoint("TOPLEFT", cur.text, "BOTTOMLEFT", 0, -4)
  cur.obj:SetPoint("RIGHT", -8, 0)
  cur.obj:SetSpacing(2)
  cur.info = T.Text(cur, 11, T.c.accent)
  cur.info:SetPoint("TOPLEFT", cur.obj, "BOTTOMLEFT", 0, -4)
  cur.up = T.Text(cur, 11, T.c.good)
  cur.up:SetPoint("TOPLEFT", cur.info, "BOTTOMLEFT", 0, -3)
  cur.up:SetPoint("RIGHT", -8, 0)
  cur.skip = T.Button(cur, "Skip", 46, 18)
  cur.skip.tip = "Skip this quest - it won't be routed again (/qc unskip brings skipped quests back)."
  cur.skip:SetScript("OnClick", function()
    local s = P.steps[GD.focus]
    if s and s.quests and s.quests[1] then
      for _, id in ipairs(s.quests) do Q.char.skipped[id] = true end
      GD.focus = 1
      P:SkipQuest(s.quests[1])
    elseif s and s.item then
      P.vendorUps = nil
      P:Build()
    end
  end)
  cur.map = T.Button(cur, "Map", 46, 18)
  -- a dungeon run: the game's group finder (LFG.lua lays a secure button over this one)
  cur.lfg = T.Button(cur, "Group finder", 84, 18)
  cur.lfg.tip = "Open the game's group finder to look for or list a group for this dungeon"
  if Q.LFG and Q.LFG.Overlay then Q.LFG.Overlay(cur.lfg) end
  cur.lfg:Hide()
  -- a hearth step: use the hearthstone (a secure button: only a real click may use an item)
  cur.hs = T.Button(cur, "Hearthstone", 90, 18)
  cur.hs.tip = "Use your Hearthstone"
  if Q.SecureOverlay then
    Q.SecureOverlay(cur.hs, "QuesticusHearthButton", function() return "/use item:" .. (Q.Flight.HS_ITEM or 6948) end,
      "Can't use it from here in combat - use your Hearthstone from your bags.")
  end
  cur.hs:Hide()
  -- a dungeon run folds away to one line; this opens / closes the quest list under it
  cur.fold = T.Button(cur, "Expand", 64, 18)
  cur.fold.tip = "Show or hide the dungeon's quests and what's left of each"
  cur.fold:SetScript("OnClick", function()
    Q.db.guide.dunOpen = not Q.db.guide.dunOpen or nil
    GD:Refresh()
  end)
  cur.fold:Hide()
  cur.map.tip = "Pin this objective on the map and open the map there"
  cur.map:SetScript("OnClick", function()
    local p = GD:Target()
    if not p then return end
    local _, m = Q.Waypoint:Pin(p)
    m = m or D:MapPos(p)
    if m and WorldMapFrame then
      if not WorldMapFrame:IsShown() then ToggleWorldMap() end
      WorldMapFrame:SetMapID(m)
    end
  end)

  -- the route list scrolls (mouse wheel) inside whatever room the window has
  local sc = CreateFrame("ScrollFrame", nil, frame)
  -- the step you just finished (right-click: notes)
  frame.prev = CreateFrame("Button", nil, frame)
  frame.prev:SetHeight(14)
  frame.prev:SetPoint("TOPLEFT", cur, "BOTTOMLEFT", 6, -3)
  frame.prev:SetPoint("RIGHT", cur, "RIGHT", -6, 0)
  if frame.prev.RegisterForClicks then frame.prev:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  frame.prev.text = T.Text(frame.prev, 10, T.c.dim)
  frame.prev.text:SetPoint("LEFT", 0, 0)
  frame.prev.text:SetPoint("RIGHT", 0, 0)
  frame.prev.text:SetJustifyH("LEFT")
  frame.prev.text:SetWordWrap(false)
  frame.prev:SetScript("OnClick", function(self) if P.prevStep then GD:Menu(0, self) end end)
  frame.prev:SetScript("OnEnter", function(self)
    if not P.prevStep then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Last step: " .. GD.StepText(P.prevStep), 1, 1, 1, true)
    for _, n in ipairs(Q.Author and Q.Author:NotesFor(P.prevStep) or {}) do GameTooltip:AddLine("Note: " .. n, 0.88, 0.69, 0.29, true) end
    if Q.Author and Q.Author:IsAuthor() then GameTooltip:AddLine("Click: add a note to it", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  frame.prev:SetScript("OnLeave", function() GameTooltip:Hide() end)
  sc:SetPoint("TOPLEFT", cur, "BOTTOMLEFT", 0, -20)
  sc:SetPoint("RIGHT", -8, 0)
  sc:SetPoint("BOTTOM", frame, "BOTTOM", 0, 30)
  sc:EnableMouseWheel(true)
  frame.scroll = sc
  frame.next = CreateFrame("Frame", nil, sc)
  frame.next:SetSize((g.w or WIDTH) - 16, 1)
  sc:SetScrollChild(frame.next)
  sc.thumb = sc:CreateTexture(nil, "OVERLAY")
  sc.thumb:SetTexture(Q.MEDIA .. "rfill")
  sc.thumb:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 0.45)
  sc.thumb:SetWidth(3)
  sc.thumb:Hide()
  function sc:Room() return math.max(0, (frame.next:GetHeight() or 0) - (self:GetHeight() or 0)) end
  function sc:Thumb()
    local room, h = self:Room(), self:GetHeight() or 0
    if room <= 0 or h <= 0 then self.thumb:Hide(); return end
    local total = h + room
    local th = math.max(16, h * h / total)
    local y = (self:GetVerticalScroll() or 0) / room * (h - th)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
    self.thumb:SetHeight(th)
    self.thumb:Show()
  end
  function sc:ScrollTo(v)
    self:SetVerticalScroll(math.max(0, math.min(self:Room(), v)))
    self:Thumb()
  end
  sc:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo((self:GetVerticalScroll() or 0) - delta * 40) end)
  sc:HookScript("OnSizeChanged", function(self, w)
    if w and w > 0 then frame.next:SetWidth(w) end
    self:ScrollTo(self:GetVerticalScroll() or 0)
  end)

  -- resize from the bottom-right corner; right-click the grip to go back to the automatic size
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(260, 140, 800, 1000)
  elseif frame.SetMinResize then frame:SetMinResize(260, 140); frame:SetMaxResize(800, 1000) end
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" and not g.locked then frame.sizing = true; frame:StartSizing("BOTTOMRIGHT") end
  end)
  grip:SetScript("OnMouseUp", function(_, btn)
    if btn ~= "LeftButton" or frame.sizing ~= true then return end
    frame.sizing = nil
    frame:StopMovingOrSizing()
    g.w, g.h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
    local p, _, _, x, y = frame:GetPoint()
    g.at = { p, x, y }
    frame.ccOwnSpot = true
    GD:Refresh()
  end)
  grip:SetScript("OnClick", function() GD:ResetSize() end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize", 1, 1, 1)
    GameTooltip:AddLine("Right-click: back to the automatic size", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.grip = grip
  frame:HookScript("OnSizeChanged", function(self, w)
    if self.sizing == true then GD:Layout() end
    Q.Throttle("guideHeader", 0.1, function() GD:Refresh() end)
  end)

  frame.foot = T.Text(frame, 10, T.c.dim)
  frame.foot:SetPoint("BOTTOMLEFT", 10, 9)
  frame.foot:SetWordWrap(false)
  frame.opt = T.Button(frame, "Options", 64, 18)
  frame.opt:SetPoint("BOTTOMRIGHT", -20, 6)
  frame.opt:SetScript("OnClick", function() if Q.ShowOptions then Q:ShowOptions() end end)
  frame.list = T.Button(frame, "Hide list", 70, 18)
  frame.list:SetPoint("RIGHT", frame.opt, "LEFT", -4, 0)
  frame.list.tip = "Hide or show the route list below the current step"
  frame.list:SetScript("OnClick", function()
    g.hideList = not g.hideList
    GD:Refresh()
  end)
  frame.more = T.Button(frame, "More", 50, 18)
  frame.more:SetPoint("RIGHT", frame.list, "LEFT", -4, 0)
  frame.more.tip = "Show more of the route (or drag the corner to make the window bigger and scroll)"
  frame.more:SetScript("OnClick", function()
    g.next = (g.next or 3) >= 12 and 3 or 12
    GD:Refresh()
  end)
  frame.foot:SetPoint("RIGHT", frame.more, "LEFT", -6, 0)

  -- remember "closed" only when the player closed it: not while the whole UI is hidden
  -- (Alt+Z, cinematics, screenshots) and not while logging out or reloading
  frame:SetScript("OnHide", function()
    if Q.loggingOut or not UIParent:IsShown() then return end
    g.shown = false
  end)
  frame:SetScript("OnShow", function() g.shown = true end)
  local acc = 0
  frame:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.5 then return end
    acc = 0
    -- on a flight path the distance isn't measured: "in flight" once, measured again when you land
    if Q.OnTaxi() then
      if not frame.inFlight then frame.inFlight = true; if cur and cur.info then cur.info:SetText("in flight") end end
      return
    end
    frame.inFlight = nil
    GD:RefreshDistance()
  end)
end

local function zoneName(p)
  local m = p and D:MapPos(p)
  local info = m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return info and info.name
end

function GD:RefreshDistance()
  if Q.Waypoint then Q.Waypoint:Follow() end
  if not frame or not frame:IsShown() then return end
  local p = GD:Target()
  if not p then cur.info:SetText(""); return end
  local here = D:PlayerPos()
  local d = D.Dist(here, p)
  local z = zoneName(p)
  if d >= D.FAR then
    cur.info:SetText((z and (z .. " - ") or "") .. "another continent")
  else
    cur.info:SetText(("%d yd"):format(math.floor(d)) .. (z and ("  -  " .. z) or ""))
  end
end

function GD:Refresh()
  if not frame then
    -- the guide is closed, but the arrow and pins still follow the route
    Q:Send("QC_TARGET_CHANGED")
    return
  end
  if frame.prev then
    local ps = P.prevStep
    frame.prev.text:SetText(ps and (Q.Color(T.HEX.good, "Last step: ") .. GD.StepText(ps, true)) or "")
  end
  local dm = Q.char.dmode and D:Dungeon(Q.char.dmode)
  frame.title:SetText(Q.Color(T.HEX.accent, "Questicus") .. (dm and Q.Color(T.HEX.dim, " - " .. dm[1]) or ""))
  local steps = P.steps or {}
  local lv = Q.player.level
  local xp, max = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
  local ttl = Q.Details and Q.Details:TimeToLevel()
  local w = frame:GetWidth() or WIDTH
  local full = ("Level %d  %d%%"):format(lv, math.floor(xp / math.max(1, max) * 100)) ..
    (ttl and ("  -  " .. ttl .. " to " .. (lv + 1)) or "")
  -- narrow window: just the level and %, then only the %
  frame.lvl:SetText(w >= 330 and full or (w >= 280 and ("Lv %d  %d%%"):format(lv, math.floor(xp / math.max(1, max) * 100))
    or ("%d%%"):format(math.floor(xp / math.max(1, max) * 100))))
  frame.xp:SetValue(xp / math.max(1, max))
  if GD.focus > #steps then GD.focus = 1 end
  local s = steps[GD.focus]
  if not s then
    cur.icon:SetTexture(ICON.explore)
    cur.num:SetText("")
    if D.old then
      cur.text:SetText("ForeverDB needs an update.")
      cur.obj:SetText("This ForeverDB has no quest details yet. Update it on CurseForge.")
    elseif not D:Ready() then
      cur.text:SetText("ForeverDB is not installed.")
      cur.obj:SetText("Questicus needs the ForeverDB addon for its quest data.")
    elseif not Q.char.surveyDone then
      cur.text:SetText("Answer a few questions to start.")
      cur.obj:SetText("/qc survey")
    else
      cur.text:SetText("No quests to route right now.")
      cur.obj:SetText("Try a wider level range in /qc options, or /qc unskip.")
    end
    cur.up:SetText("")
    cur.skip:Hide(); cur.map:Hide()
  else
    cur.icon:SetTexture(stepIcon(s))
    cur.num:SetText(GD.focus == 1 and "NOW" or ("#" .. GD.focus))
    cur.text:SetText(GD.StepText(s))
    local dArea, dName = GD.DungeonOf(s)
    local esc = not dArea and GD.EscortOf(s)
    local open = Q.db.guide.dunOpen
    local lines = s.type == "complete" and (dArea and (open and dungeonLines(s) or {}) or objectiveLines(s)) or {}
    -- (the DUNGEON label under the icon is wider than it: move the step text clear of it)
    -- (the icon moves in so the label stays inside the box; the text stays where it was)
    cur.icon:SetPoint("TOPLEFT", dArea and 18 or 8, -8)
    cur.text:SetPoint("TOPLEFT", cur.icon, "TOPRIGHT", dArea and 12 or 8, 0)
    cur.glow:SetShown(dArea ~= nil or esc ~= nil)
    cur.banner:SetShown(dArea ~= nil)
    cur.ebanner:SetShown(esc ~= nil)
    if esc then
      -- an escort: green, and it asks before it starts (Auto.lua)
      cur.glow:SetVertexColor(0.35, 0.95, 0.45, 0.8)
      cur.icon:SetVertexColor(0.7, 1, 0.7, 1)
      cur.num:SetText(c("5cff6a", "ESCORT"))
      T.SetBorderColor(cur, 0.35, 0.9, 0.45, 1)
      local info = QS:Info(esc)
      cur.ebanner.text:SetText("ESCORT QUEST - " .. ((info and info.title) or "escort"):upper())
      cur.ebanner:SetWidth(math.min((cur.ebanner.text:GetStringWidth() or 200) + 24, math.max(120, (cur:GetWidth() or 300) - 12)))
      lines[#lines + 1] = c("5cff6a", "  Escort: ") .. c(dim, s.type == "accept"
        and "it starts when you accept it - be ready to follow and keep them alive. Questicus asks first."
        or "stay close and keep them alive until they're safe.")
    elseif dArea then
      cur.glow:SetVertexColor(0.75, 0.45, 1, 0.8)
      cur.icon:SetVertexColor(0.85, 0.65, 1, 1)
      cur.num:SetText(c("c08cff", "DUNGEON"))
      T.SetBorderColor(cur, 0.75, 0.45, 1, 1)
      local bt, done, total = Q.Bosses, 0, 0
      if bt and Q.Dungeons then
        for _, e in ipairs(Q.Dungeons:List()) do
          if e.area == dArea or e.name == dName then
            for _, b in ipairs(bt:List(e)) do total = total + 1; if bt:Killed(e.area, b.name) then done = done + 1 end end
          end
        end
      end
      cur.banner.text:SetText("DUNGEON RUN - " .. (dName or "dungeon"):upper() .. (total > 0 and ("   bosses %d/%d"):format(done, total) or ""))
      cur.banner:SetWidth(math.min((cur.banner.text:GetStringWidth() or 200) + 24, math.max(120, (cur:GetWidth() or 300) - 12)))

    else
      cur.icon:SetVertexColor(1, 1, 1, 1)
      T.SetBorderColor(cur, T.c.accent[1], T.c.accent[2], T.c.accent[3], 0.45)
    end
    if s.type == "boat" then
      lines[#lines + 1] = c(dim, "  Board at ") .. c(white, (s.from and s.from.place) or "the docks") ..
        c(dim, (" - the %s lands at "):format(s.kind or "boat")) .. c(white, (s.to and s.to.place) or s.toName or "")
      lines[#lines + 1] = c(dim, "  Wait on the platform / dock until it arrives, then get on; the route carries on where it lands.")
    end
    -- items you put together for a quest (qx 21): "Combine A + B -> C"
    for _, id in ipairs((s.type == "complete" and (open or not dArea)) and s.quests or {}) do
      local combine = Q.Bosses and Q.Bosses.CombineText and Q.Bosses.CombineText(id)
      if combine then lines[#lines + 1] = (dArea and "     " .. c(dim, "combine ") or c(T.HEX.gold, "  Combine: ")) .. combine end
    end
    -- hand-checked tip for where you are going (ForeverDB fixes.json), e.g. "stands in the murloc hut"
    local tp = GD:Target()
    local note = tp and D:Note(tp.key)
    if not note and s.type == "complete" then
      for _, id in ipairs(s.quests) do
        local m = P.Meta(id)
        for _, l in ipairs(m and m.lines or {}) do note = note or D:Note(l.from or l.key) end
      end
    end
    if dArea and not open then note = nil end
    if note then lines[#lines + 1] = c(T.HEX.accent, "  Tip: ") .. c(dim, note) end
    -- the author's notes for this step (AuthorNotes.lua)
    for _, n in ipairs(Q.Author and Q.Author:NotesFor(s) or {}) do
      lines[#lines + 1] = c(T.HEX.gold, "  Note: ") .. c(T.HEX.white, n)
    end
    local way = GD:OnTheWay(s)
    if #way > 0 then
      lines[#lines + 1] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:12|t " ..
        c(T.HEX.gold, "On the way: ") .. table.concat(way, ", ") .. c(dim, " (marked X)")
    end
    if s.unknown and not GD:Target() then
      lines[#lines + 1] = c(dim, "  (no map spot for this one yet - check the quest text)")
    end
    if s.type == "turnin" and s.quests[1] and not QS.log[s.quests[1]] then
      lines = { c(dim, "  (not in your quest log)") }
    end
    cur.obj:SetText(table.concat(lines, "\n"))
    local up = s.upgrade
    cur.up:SetText(up and ("Upgrade: " .. itemText(up.item) .. (" +%d%%"):format(math.floor(up.pct))) or "")
    cur.skip:Show(); cur.map:Show()
  end
  -- layout of the current box
  local h = 14 + math.max(28, (cur.text:GetStringHeight() or 14) + (cur.obj:GetStringHeight() or 0) + 22 +
    ((cur.up:GetText() or "") ~= "" and 16 or 0))
  cur:SetHeight(h + 18)
  cur.map:SetPoint("BOTTOMRIGHT", -6, 5)
  cur.skip:SetPoint("RIGHT", cur.map, "LEFT", -4, 0)
  local fs = steps[GD.focus]
  cur.hs:SetShown(fs ~= nil and fs.type == "hearth")
  cur.hs:ClearAllPoints()
  cur.hs:SetPoint("RIGHT", cur.skip, "LEFT", -4, 0)
  local runStep = steps[GD.focus] and GD.DungeonOf(steps[GD.focus])
  cur.lfg:SetShown(runStep ~= nil and Q.LFG ~= nil)
  cur.lfg:ClearAllPoints()
  cur.lfg:SetPoint("RIGHT", cur.skip, "LEFT", -4, 0)
  cur.fold:SetShown(runStep ~= nil)
  cur.fold:SetText(Q.db.guide.dunOpen and "Collapse" or "Expand")
  cur.fold:ClearAllPoints()
  cur.fold:SetPoint("RIGHT", cur.lfg:IsShown() and cur.lfg or cur.skip, "LEFT", -4, 0)
  -- the route list: every step after the current one when the window was sized by hand (it
  -- scrolls), otherwise the next few (More) and the window grows to fit
  local g = Q.db.guide
  local hide = g.hideList
  local n = hide and 0 or (g.h and #steps or (g.next or 3))
  local shown = 0
  for i = 1, n do
    local idx = i + (GD.focus == 1 and 1 or 0)
    if GD.focus ~= 1 and i == 1 then idx = 1 end
    if GD.focus ~= 1 and idx >= GD.focus and i > 1 then idx = i + 1 end
    local st = steps[idx]
    local r = rows[i]
    if st then
      if not r then r = newRow(frame.next); rows[i] = r end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", frame.next, "TOPLEFT", 0, -(i - 1) * 20)
      r:SetPoint("RIGHT", frame.next, "RIGHT", -6, 0)
      r.index = idx
      r.icon:SetTexture(stepIcon(st))
      local dRow = GD.DungeonOf(st)
      r.icon:SetVertexColor(dRow and 0.85 or 1, dRow and 0.65 or 1, 1, 1)
      r.text:SetText(c(dim, idx .. ". ") .. GD.StepText(st, true))
      -- same colours as the map: next = gold, after that = violet
      local k = idx - GD.focus + 1
      local col = Q.Pins and Q.Pins.COLORS and Q.Pins.COLORS[k]
      if col and k > 1 then r.stripe:SetVertexColor(col[1], col[2], col[3], 1); r.stripe:Show() else r.stripe:Hide() end
      r:Show()
      shown = i
    elseif r then
      r:Hide()
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  GD.shownRows = shown
  local foot = ""
  if #steps > 0 then
    foot = ("%d steps - about level %d by the end"):format(#steps, P.endLevel or lv)
  end
  frame.foot:SetText(foot)
  frame.list:SetText(hide and "Show list" or "Hide list")
  frame.more:SetShown(not hide and not g.h)
  GD:Layout()
  GD:RefreshDistance()
  Q:Send("QC_TARGET_CHANGED")
end

-- window size: automatic (fits the current step + the next few) unless resized by hand
function GD:Layout()
  if not frame then return end
  local g = Q.db.guide
  local shown = GD.shownRows or 0
  local fixed = 34 + (cur:GetHeight() or 60) + 8 + 30
  frame.next:SetHeight(math.max(1, shown * 20))
  if frame.sizing ~= true then
    frame:SetWidth(g.w or WIDTH)
    if g.hideList then
      frame:SetHeight(fixed)
    elseif g.h then
      frame:SetHeight(math.max(g.h, fixed + 20))
    else
      frame:SetHeight(fixed + shown * 20)
    end
  end
  frame.scroll:SetShown(not g.hideList)
  local w = frame.scroll:GetWidth()
  if w and w > 0 then frame.next:SetWidth(w) end
  frame.scroll:ScrollTo(frame.scroll:GetVerticalScroll() or 0)
end

function GD:ResetSize()
  local g = Q.db.guide
  g.w, g.h = nil, nil
  if frame then frame.scroll:ScrollTo(0) end
  GD:Refresh()
end

function Q:ShowGuide()
  if Q.CollectOnly and Q.CollectOnly() then
    Q:Print("collection mode is on - Questicus only records (/qc collectonly to guide again)")
    return
  end
  if not frame then build() end
  local g = Q.db.guide
  if g.at and not frame:IsShown() then
    frame:ClearAllPoints()
    frame:SetPoint(g.at[1], UIParent, g.at[1], g.at[2], g.at[3])
    frame.ccOwnSpot = true
    frame.__fromDock = nil
  end
  frame:Show()
  GD:Refresh()
end
function Q:ToggleGuide()
  if frame and frame:IsShown() then
    frame:Hide()
    Q.db.guide.shown = false
  else
    Q.db.guide.shown = true
    Q:ShowGuide()
  end
end
GD.Frame = function() return frame end

Q:On("QC_PLAN_UPDATED", function()
  GD.focus = 1
  if Q.db.guide.shown and Q.char.surveyDone then
    if not frame then build() end
    frame:Show()
  end
  GD:Refresh()
end)
Q:On("QC_QUESTS_CHANGED", function() GD:Refresh() end)
Q:On("PLAYER_XP_UPDATE", function() GD:Refresh() end)
Q:On("QC_READY", function()
  if Q.db.guide.shown and Q.char.surveyDone then Q:ShowGuide() end
end)
Q:Command("guide", "show / hide the guide", function() Q:ToggleGuide() end)
Q:Command("guidesize", "put the guide window back to its automatic size", function() GD:ResetSize() end)
