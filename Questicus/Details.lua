-- Questicus step details + quest history.
-- Click a step (or the current step) for everything about it: where, objectives, XP, gold, item
-- rewards (with upgrade check), reputation, estimated time, the chain it belongs to, and what it
-- really gave and how long it took when you did it. Every quest you turn in is recorded (time from
-- accept to turn-in, XP, money, items) and compared with the database; the comparison is saved in
-- QuesticusCollect.qact so ForeverDB can be corrected.
local Q = Questicus
local L = Q.L
local T, D, QS, P, G = Q.T, Q.Data, Q.Quests, Q.Planner, Q.Gear
local DT = {}
Q.Details = DT

local frame, shownIndex
local function c(hex, s) return "|cff" .. hex .. s .. "|r" end

-- ------------------------------------------------------------------ formatting
function DT.Time(sec)
  if not sec or sec <= 0 then return "-" end
  sec = math.floor(sec + 0.5)
  if sec < 60 then return sec .. " s" end
  if sec < 3600 then return ("%d min %02d s"):format(math.floor(sec / 60), sec % 60) end
  return ("%d h %02d min"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end
local function short(sec)
  if not sec then return nil end
  if sec < 3600 then return ("%d min"):format(math.max(1, math.floor(sec / 60 + 0.5))) end
  return ("%d h %d min"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end
function DT.Money(copper)
  copper = math.floor(copper or 0)
  if copper <= 0 then return "-" end
  local g, s, cp = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "|cffffd100g|r" end
  if s > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
  if cp > 0 and g == 0 then out[#out + 1] = cp .. "|cffeda55fc|r" end
  return table.concat(out, " ")
end
local function itemLine(id)
  local name, link, _, _, _, _, _, _, _, icon = Q.GetItemInfo(id)
  local rec = D:Item(id)
  icon = icon or (rec and rec[8]) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
  local txt = link or c(T.HEX.gold, "[" .. (name or D:Name("i" .. id)) .. "]")
  local gain, pct = nil, nil
  if G then
    local ok, g1, p1 = pcall(G.Upgrade, G, id)
    if ok then gain, pct = g1, p1 end
  end
  local tag = (gain and gain > 0 and pct) and c(T.HEX.good, (" upgrade +%d%%"):format(math.floor(pct))) or ""
  return "|T" .. icon .. ":14|t " .. txt .. tag
end
local function factionName(id)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, fd = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and fd and fd.name then return fd.name end
  end
  if GetFactionInfoByID then
    local ok, name = pcall(GetFactionInfoByID, id)
    if ok and name then return name end
  end
  return "Faction " .. id
end

-- ------------------------------------------------------------------ history
local function hist() Q.char.hist = Q.char.hist or {}; return Q.char.hist end
local pendingItems -- { id, t } while the reward items of a turn-in arrive

Q:On("QUEST_ACCEPTED", function(a, b)
  local id = b or a                          -- (index, questID) on older clients, (questID) on newer
  if type(id) ~= "number" or id < 1 then return end
  local h = hist()[id] or {}
  h.acc = time()
  h.lv = Q.player.level
  -- what the plan expected, to compare at turn-in
  h.estXP = QS.RewardXP(id, Q.player.level)
  h.estMoney = QS.RewardMoney(id)
  local m = P.Meta(id)
  h.estSecs = P.Effort(m)
  h.title = (QS:Info(id) and QS:Info(id).title) or h.title
  hist()[id] = h
end)

Q:On("QUEST_TURNED_IN", function(id, xp, money)
  if type(id) ~= "number" then return end
  local h = hist()[id] or {}
  h.done = time()
  if h.acc then h.secs = h.done - h.acc end
  h.xp, h.money = xp or 0, money or 0
  h.items = {}
  h.title = h.title or (QS:Info(id) and QS:Info(id).title)
  hist()[id] = h
  pendingItems = { id = id, t = GetTime and GetTime() or 0 }
  -- the database check: real reward vs ForeverDB, for the recordings sync
  if QuesticusCollect and Q.db.collect ~= false then
    QuesticusCollect.qact = QuesticusCollect.qact or {}
    local r = QS.Rewards(id)
    QuesticusCollect.qact[id] = { xp = h.xp, money = h.money, lv = Q.player.level, secs = h.secs,
      dbxp = r and r[2] or nil, dbmoney = r and r[1] or nil }
  end
  local okXP = h.estXP and h.xp and math.abs(h.estXP - h.xp) <= math.max(5, h.xp * 0.05)
  Q:Debug(("turned in %s: %d XP (planned %d)%s, %s, took %s"):format(h.title or id, h.xp or 0, h.estXP or 0,
    okXP and "" or " - DIFFERENT", DT.Money(h.money), DT.Time(h.secs)))
  if frame and frame:IsShown() then DT:Refresh() end
end)

-- reward items arrive as "You receive item: ..." right after the turn-in
Q:On("CHAT_MSG_LOOT", function(msg)
  if not pendingItems or type(msg) ~= "string" or Q.Secret(msg) then return end
  if (GetTime and GetTime() or 0) - pendingItems.t > 3 then pendingItems = nil; return end
  local item = tonumber(msg:match("|Hitem:(%d+)"))
  local h = hist()[pendingItems.id]
  if item and h then h.items = h.items or {}; table.insert(h.items, item) end
end)

-- ------------------------------------------------------------------ time to level
local session = { start = nil, xp = 0 }
Q:On("PLAYER_XP_UPDATE", function()
  local now = UnitXP("player")
  if session.last and now > session.last then session.xp = session.xp + (now - session.last) end
  session.last = now
  session.start = session.start or time()
end)
Q:On("PLAYER_LEVEL_UP", function() session.last = 0 end)

-- "25 min": from your pace this session (after 10 minutes of play), else from the planned route
function DT:TimeToLevel()
  local need = (UnitXPMax and UnitXPMax("player") or 0) - (UnitXP and UnitXP("player") or 0)
  if need <= 0 then return nil end
  local rate
  if session.start and time() - session.start > 600 and session.xp > 0 then
    rate = session.xp / (time() - session.start)
  else
    rate = P.xpPerSec
  end
  if not rate or rate <= 0 then return nil end
  return "~" .. short(need / rate)
end

-- ------------------------------------------------------------------ tooltip lines for a step
function DT:TooltipLines(tt, s)
  if s.t and s.t > 0 then tt:AddLine(L["Estimated time: "] .. DT.Time(s.t), 0.9, 0.85, 0.7) end
  if s.why and s.why[1] then tt:AddLine(L["Why: "] .. s.why[1], 0.75, 0.7, 0.6, true) end
  if s.xp then
    tt:AddLine(("Reward: %s XP%s%s"):format(s.xp, s.realXP and "" or " (estimate)",
      (s.money and s.money > 0) and ("  -  " .. DT.Money(s.money)) or ""), 0.9, 0.85, 0.7)
  end
end

-- ------------------------------------------------------------------ panel
local function build()
  local g = Q.db.guide
  frame = T.Window("QuesticusDetails", 320, 420, "Step details", nil)
  frame:SetFrameStrata("MEDIUM")
  frame.text = T.Text(frame, 12)
  frame.text:SetPoint("TOPLEFT", 12, -34)
  frame.text:SetPoint("RIGHT", -12, 0)
  frame.text:SetJustifyV("TOP")
  frame.text:SetSpacing(3)
  frame:SetScript("OnHide", function() shownIndex = nil; if frame.menu then frame.menu:Hide() end end)
  -- "not for me": turn the gear down with a reason, Questicus learns from it
  frame.deny = T.Button(frame, "Not for me...", 110, 20)
  frame.deny:SetPoint("BOTTOMLEFT", 10, 8)
  frame.deny.tip = "Turn this item down and tell Questicus why"
  frame.deny:Hide()
  local menu = CreateFrame("Frame", nil, frame)
  menu:SetSize(250, 4 + #G.DENY_REASONS * 24)
  menu:SetPoint("TOPLEFT", frame.deny, "BOTTOMLEFT", 0, -2)
  menu:SetFrameStrata("DIALOG")
  T.RFill(menu, T.c.bg, 6)
  T.Border(menu, T.c.line, 6)
  for i, r in ipairs(G.DENY_REASONS) do
    local b = T.Button(menu, r[2], 242, 22)
    b:SetPoint("TOPLEFT", 4, -2 - (i - 1) * 24)
    b:SetScript("OnClick", function()
      if DT.gearItem then
        G:Deny(DT.gearItem, r[1])
        Q:Print(("%s turned down: %s"):format(Q.GetItemInfo(DT.gearItem) or ("item " .. DT.gearItem), r[2]))
      end
      menu:Hide()
      DT:Refresh()
    end)
  end
  menu:Hide()
  frame.menu = menu
  frame.deny:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
end

local function place()
  local gf = Q.Guide.Frame()
  frame:ClearAllPoints()
  if gf and gf:IsShown() then
    local right = (gf:GetRight() or 0) + 330 < (UIParent:GetWidth() or 1920)
    if right then frame:SetPoint("TOPLEFT", gf, "TOPRIGHT", 6, 0)
    else frame:SetPoint("TOPRIGHT", gf, "TOPLEFT", -6, 0) end
  else
    frame:SetPoint("CENTER")
  end
end

local function lines(s)
  local out = {}
  local function add(t) out[#out + 1] = t or "" end
  local gold, dim, good, bad = T.HEX.gold, T.HEX.dim, T.HEX.good, T.HEX.bad
  add(c(gold, Q.Guide.StepText(s)))
  local id = s.quests and s.quests[1]
  local info = id and QS:Info(id)
  if info then
    add(c(dim, ("Quest level %d  -  needs level %d%s%s"):format(info.level, info.min,
      info.elite and "  -  elite" or "", info.dungeon and "  -  dungeon" or "")))
  end
  -- why this step (and why it beats the next best one)
  if s.why and #s.why > 0 then
    add(" ")
    add(c(gold, L["Why this step"]))
    for _, w in ipairs(s.why) do add("  - " .. w) end
  end
  if s.drops then
    for _, d in ipairs(s.drops) do
      local qi = QS:Info(d.quest)
      add(c(good, L["  Loot "] .. D:Name("i" .. (d.item or 0)) .. " here - it starts " .. (qi and qi.title or d.quest)))
    end
  end
  -- where
  local tgt = Q.Guide:Target(shownIndex)
  if tgt then
    local here = D:PlayerPos()
    local m = D:MapPos(tgt)
    local zone = m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    local dist = here and D.Dist(here, tgt)
    add(("Where: %s%s%s"):format(tgt.key and D:Name(tgt.key) or "here",
      zone and ("  -  " .. zone.name) or "",
      (dist and dist < D.FAR) and ("  -  %d yd"):format(math.floor(dist)) or ""))
    local note = D:Note(tgt.key)
    if note then add(c(dim, L["Tip: "] .. note)) end
  end
  -- objectives
  if id then
    local m = P.Meta(id)
    if m and m.lines and #m.lines > 0 then
      add(" ")
      add(c(gold, L["Objectives"]))
      local e = QS.log[id]
      if e and e.objectives and #e.objectives > 0 then
        for _, o in ipairs(e.objectives) do add((o.finished and c(dim, "  - " .. o.text) or ("  - " .. (o.text or "")))) end
      else
        for _, l in ipairs(m.lines) do
          local verb = ({ kill = "Kill ", loot = "Get ", use = "Use ", explore = "", buy = "Buy " })[l.kind] or ""
          local n = 0
          if l.kind == "loot" then for _ in ipairs(D:ItemSources(tonumber(l.key:sub(2)))) do n = n + 1 end end
          add("  - " .. verb .. l.name .. (n > 1 and c(dim, (" (%d mobs drop it)"):format(n)) or ""))
        end
      end
    end
  end
  -- rewards
  if id then
    add(" ")
    add(c(gold, L["Rewards"]))
    local xp, real, rec = QS.RewardXP(id, Q.player.level)
    add(("  XP: %s%s"):format(xp, rec and c(dim, L[" (what the game says)"]) or (real and "" or c(dim, L[" (estimate - no data)"]))))
    add("  Gold: " .. DT.Money(QS.RewardMoney(id)))
    local r = QS.Rewards(id)
    if r and r[3] then
      add("  Choose one:")
      for _, it in ipairs(r[3]) do add("    " .. itemLine(it)) end
    end
    if r and r[4] then
      add("  You also get:")
      for _, it in ipairs(r[4]) do add("    " .. itemLine(it)) end
    end
    if not (r and (r[3] or r[4])) and D.rewards and D.rewards[id] then
      for _, it in ipairs(D.rewards[id]) do add("    " .. itemLine(it)) end
    end
    local rep = info and info.x and info.x[15]
    if rep then
      for i = 1, #rep - 1, 2 do add(("  Reputation: %s %+d"):format(factionName(rep[i]), rep[i + 1])) end
    end
  end
  -- the gear Questicus wants you to get here, and why
  local gearItem = (s.type == "buy" and s.item) or (s.upgrade and s.upgrade.item)
  if not gearItem and id and G then
    local ok, up = pcall(G.QuestUpgrade, G, id)
    gearItem = ok and up and up.item or nil
  end
  DT.gearItem = gearItem
  if gearItem and G then
    add(" ")
    add(c(gold, L["Why this gear"]))
    add("  " .. itemLine(gearItem))
    for _, l in ipairs(G:Explain(gearItem)) do add("  - " .. l) end
    add(c(dim, L["  Not for you? Use the button below - Questicus learns from your answer."]))
  end
  -- quests you did together before (learned), and the time for the whole group
  if id and Q.Learn then
    local partners = Q.Learn:Partners(id)
    if #partners > 0 then
      local total = Q.Learn:WorkTime(id) or 0
      local names = {}
      for _, q in ipairs(partners) do
        local qi = QS:Info(q)
        names[#names + 1] = qi and qi.title or tostring(q)
        total = total + (Q.Learn:WorkTime(q) or 0)
      end
      add(" ")
      add(c(gold, L["Done together"]))
      add("  With " .. table.concat(names, ", "))
      if total > 0 then add(("  The whole group took about %s"):format(DT.Time(total))) end
    end
  end
  -- time
  add(" ")
  add(c(gold, L["Time"]))
  if s.t and s.t > 0 then add("  This step: about " .. DT.Time(s.t)) end
  local m = id and P.Meta(id)
  if m and m.effort then
    local work, learned = P.WorkTime(id, m, Q.player.level)
    add("  Whole quest: about " .. DT.Time(P.Effort(m)) .. c(dim, learned and " (work time learned from real runs)" or ""))
    if not learned and Q.Learn then
      add(c(dim, ("  Kills: ~%d s each + %d s between pulls (%s)"):format(math.floor(Q.Learn:TTK(0) + 0.5),
        math.floor(Q.Learn:Gap() + 0.5), (Q.char.learn and Q.char.learn.ttkAll and Q.char.learn.ttkAll.n or 0) >= 5 and "learned" or "estimate")))
    end
  end
  local worked = id and Q.char.work and Q.char.work[id]
  if worked and worked > 5 then add(c(dim, L["  Worked on it so far: "] .. DT.Time(worked))) end
  -- chain
  if info and info.x then
    local x = info.x
    local prev = {}
    for _, q in ipairs(x[3] or {}) do prev[#prev + 1] = q end
    for _, q in ipairs(x[4] or {}) do prev[#prev + 1] = q end
    if #prev == 0 and QS.prevOf and QS.prevOf[id] then prev = QS.prevOf[id] end
    if #prev > 0 or x[7] then
      add(" ")
      add(c(gold, L["Chain"]))
      for _, q in ipairs(prev) do
        local t = D:Quest(q)
        add("  After: " .. (t and t[1] or q) .. (QS.done[q] and c(good, L["  done"]) or c(bad, L["  not done"])))
      end
      if x[7] then local t = D:Quest(x[7]); add("  Leads to: " .. (t and t[1] or x[7])) end
    end
  end
  -- history (this character)
  local h = id and Q.char.hist and Q.char.hist[id]
  if h and h.done then
    add(" ")
    add(c(gold, L["When you did it"]))
    local okXP = h.estXP and h.xp and math.abs(h.estXP - h.xp) <= math.max(5, h.xp * 0.05)
    add(("  Took %s%s"):format(DT.Time(h.secs), h.estSecs and c(dim, L[" (planned "] .. DT.Time(h.estSecs) .. ")") or ""))
    add(("  Got %d XP %s"):format(h.xp or 0, h.estXP and (okXP and c(good, L["as planned"]) or
      c(bad, ("(planned %d)"):format(h.estXP))) or ""))
    add(("  Got %s %s"):format(DT.Money(h.money), (h.estMoney and h.estMoney > 0) and
      ((math.abs((h.money or 0) - h.estMoney) <= 1) and c(good, L["as planned"]) or c(bad, L["(planned "] .. DT.Money(h.estMoney) .. ")")) or ""))
    for _, it in ipairs(h.items or {}) do add("    " .. itemLine(it)) end
  elseif h and h.acc then
    add(" ")
    add(c(dim, L["Accepted "] .. DT.Time(time() - h.acc) .. " ago"))
  end
  return out
end

function DT:Refresh()
  if not frame or not frame:IsShown() then return end
  local s = P.steps and P.steps[shownIndex or 1]
  if not s then frame:Hide(); return end
  frame.title:SetText(("Step %d of your route"):format(shownIndex or 1))
  frame.text:SetText(table.concat(lines(s), "\n"))
  frame.deny:SetShown(DT.gearItem ~= nil)
  frame:SetHeight(math.max(160, (frame.text:GetStringHeight() or 300) + 50 + (DT.gearItem and 26 or 0)))
end

function DT:Show(index)
  if not frame then build() end
  shownIndex = index or 1
  place()
  frame:Show()
  DT:Refresh()
end
function DT:Toggle(index)
  if frame and frame:IsShown() and shownIndex == index then frame:Hide() else DT:Show(index) end
end

Q:On("QC_PLAN_UPDATED", function() if frame and frame:IsShown() then DT:Refresh() end end)
Q:On("QC_QUESTS_CHANGED", function() if frame and frame:IsShown() then DT:Refresh() end end)
Q:Command("history", "quests you turned in on this character: time, XP and gold vs planned", function()
  local n = 0
  for id, h in pairs(hist()) do
    if h.done then
      n = n + 1
      Q:Print(("%s: %s, %d XP (planned %s), %s"):format(h.title or id, DT.Time(h.secs), h.xp or 0,
        tostring(h.estXP or "?"), DT.Money(h.money)))
    end
  end
  if n == 0 then Q:Print(L["no quests recorded yet - they are recorded from now on"]) end
end)
