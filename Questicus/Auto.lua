-- Questicus helpers at quest NPCs: turn in every finished quest, accept the quests on your route, take the best reward, and keep going until the NPC has nothing left.
-- Hold Shift while talking to an NPC to do it yourself.
local Q = Questicus
local QS, G = Q.Quests, Q.Gear

local function paused() return (IsShiftKeyDown and IsShiftKeyDown()) or (Q.CollectOnly and Q.CollectOnly()) end

-- only quests the route has you pick up: an "accept" step for it anywhere in the planned route (60 steps),
-- or one you added yourself. (It used to take any quest the survey allows, so NPCs handed you quests
-- the route had left out - too far, too slow, grey, another zone - and they sat in your log.)
local function onRoute(id)
  local P = Q.Planner
  local steps = P and P.steps
  if not steps then return nil end                     -- no route worked out yet
  for _, s in ipairs(steps) do
    if s.type == "accept" then
      for _, q in ipairs(s.quests or {}) do if q == id then return true end end
    end
  end
  return false
end
Q.AutoOnRoute = onRoute

local function wanted(id)
  if not id or id == 0 then return false end
  if Q.char.skipped[id] then return false end
  if QS:Info(id) == nil then return false end
  if Q.char.forced and Q.char.forced[id] then return true end   -- you added it yourself
  -- left out by your settings (dungeon quests off, elites with solo only, escort / PvP off ...)
  local P = Q.Planner
  if P and P.OptedOut and P.OptedOut(id) then return false end
  if P and P.Excluded and P.Excluded(id) then return false end
  local r = onRoute(id)
  if r == nil then return true end                      -- (before the first route: the survey decides)
  return r
end

local function after(fn) Q.After(0.05, function() if not paused() then fn() end end) end

-- ------------------------------------------------------------------ gossip (modern NPC dialog)
local function npcKey()
  return Q.UnitKey("npc")
end

local function gossip()
  if not C_GossipInfo then return end
  local pr = Q.prefs
  -- learn which route quests this NPC does NOT offer (missing prerequisites in the data)
  if C_GossipInfo.GetAvailableQuests then
    local offered = {}
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      offered[q.questID] = true
      if not Q.ENGLISH then Q.Data.LearnName("q", q.questID, q.title) end
    end
    QS:NotOffered(npcKey(), offered)
  end
  if pr.autoTurnIn and C_GossipInfo.GetActiveQuests then
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
      if q.isComplete then return C_GossipInfo.SelectActiveQuest(q.questID) end
    end
  end
  if pr.autoAccept and C_GossipInfo.GetAvailableQuests then
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      if wanted(q.questID) then return C_GossipInfo.SelectAvailableQuest(q.questID) end
    end
  end
end

-- ------------------------------------------------------------------ greeting (old quest-list dialog)
local function greeting()
  local pr = Q.prefs
  if GetAvailableQuestInfo then
    local offered = {}
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      local id = select(5, GetAvailableQuestInfo(i))
      if id then offered[id] = true end
    end
    QS:NotOffered(npcKey(), offered)
  end
  if pr.autoTurnIn then
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
      local _, complete = GetActiveTitle(i)
      if complete then return SelectActiveQuest(i) end
    end
  end
  if pr.autoAccept then
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
      if wanted(id) then return SelectAvailableQuest(i) end
    end
  end
end

Q:On("GOSSIP_SHOW", function() if not paused() then after(gossip) end end)
Q:On("QUEST_GREETING", function() if not paused() then after(greeting) end end)

Q:On("QUEST_DETAIL", function()
  if paused() or not Q.prefs.autoAccept then return end
  local id = GetQuestID and GetQuestID()
  if wanted(id) then after(function() AcceptQuest() end) end
end)

-- escort / shared quests ask to confirm
Q:On("QUEST_ACCEPT_CONFIRM", function()
  if paused() or not Q.prefs.autoAccept then return end
  if ConfirmAcceptQuest then ConfirmAcceptQuest() end
end)

Q:On("QUEST_PROGRESS", function()
  if paused() or not Q.prefs.autoTurnIn then return end
  if IsQuestCompletable and IsQuestCompletable() then after(function() CompleteQuest() end) end
end)

-- does the reward choice teach a profession? Forever's starting quests offer "Mining for Dummies",
-- "Wild Harvest", "Pelt Collecting for Beginners" ...: the book's name, its tooltip ("Use: Teaches you
-- Mining") or its kind (recipe / profession item) gives it away
local PROFS = { "mining", "herbalism", "skinning", "alchemy", "blacksmithing", "enchanting", "engineering",
  "leatherworking", "tailoring", "jewelcrafting", "inscription", "cooking", "fishing", "first aid", "archaeology" }
local function teaches(text)
  if type(text) ~= "string" or Q.Secret(text) then return false end
  local t = text:lower()
  if t:find("for dummies", 1, true) or t:find("for beginners", 1, true) then return true end
  if t:find("teaches you", 1, true) or t:find("learn ", 1, true) then
    for _, p in ipairs(PROFS) do if t:find(p, 1, true) then return true end end
  end
  return false
end
local function choiceTeaches(i)
  local name = GetQuestItemInfo and GetQuestItemInfo("choice", i)
  if teaches(name) then return true end
  local link = GetQuestItemLink and GetQuestItemLink("choice", i)
  local id = type(link) == "string" and not Q.Secret(link) and tonumber(link:match("item:(%d+)"))
  if not id then return false end
  if teaches(Q.GetItemInfo and Q.GetItemInfo(id)) then return true end
  local cls = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(id))
  if cls == 9 then return true end                       -- recipes / profession books
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    for _, l in ipairs(ok and data and data.lines or {}) do
      if teaches(l.leftText) then return true end
    end
  end
  return false
end
function Q.ProfessionChoice(n)
  for i = 1, n or 0 do
    if choiceTeaches(i) then return true end
  end
  return false
end

Q:On("QUEST_COMPLETE", function()
  if paused() or not Q.prefs.autoTurnIn then return end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then return after(function() GetQuestReward(n) end) end
  if not Q.prefs.autoReward then return end
  -- a choice of professions (Forever's starting quests: "Mining for Dummies", "Herbalism for
  -- Dummies" ...): yours to pick, never picked for you
  if Q.ProfessionChoice and Q.ProfessionChoice(n) then
    Q:Print("pick the profession you want from the rewards - Questicus leaves that choice to you")
    return
  end
  local i, isUpgrade, pct = G:BestChoice()
  if not i then return end
  -- never handed in on its own: you confirm the pick (or choose another in the quest window)
  Q.ConfirmReward(i, isUpgrade, pct)
end)

-- ------------------------------------------------------------------ confirm the reward
-- A small card beside the quest window: the reward Questicus would pick, why, and two buttons.
-- "Take it" hands the quest in with it; "I'll choose" leaves the quest window to you.
local confirm
function Q.ConfirmReward(i, isUpgrade, pct)
  local T = Q.T
  if not confirm then
    confirm = T.Window("QuesticusRewardConfirm", 300, 118, "Quest reward", nil)
    confirm:SetFrameStrata("DIALOG")
    confirm.item = CreateFrame("Button", nil, confirm)
    confirm.item:SetSize(34, 34)
    confirm.item:SetPoint("TOPLEFT", 14, -34)
    confirm.item.tex = confirm.item:CreateTexture(nil, "ARTWORK")
    confirm.item.tex:SetAllPoints()
    confirm.item:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetQuestItem then GameTooltip:SetQuestItem("choice", confirm.index) end
      GameTooltip:Show()
    end)
    confirm.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    confirm.text = T.Text(confirm, 12, T.c.text)
    confirm.text:SetPoint("TOPLEFT", confirm.item, "TOPRIGHT", 8, 0)
    confirm.text:SetPoint("RIGHT", -14, 0)
    confirm.text:SetJustifyH("LEFT")
    confirm.take = T.Button(confirm, "Take it", 96, 22)
    confirm.take:SetPoint("BOTTOMLEFT", 14, 12)
    confirm.take:SetScript("OnClick", function()
      local idx = confirm.index
      confirm:Hide()
      if idx and QuestFrame and QuestFrame:IsShown() then GetQuestReward(idx) end
    end)
    confirm.mine = T.Button(confirm, "I'll choose", 96, 22)
    confirm.mine:SetPoint("LEFT", confirm.take, "RIGHT", 8, 0)
    confirm.mine:SetScript("OnClick", function() confirm:Hide() end)
    -- (gone with the quest window)
    confirm:RegisterEvent("QUEST_FINISHED")
    confirm:SetScript("OnEvent", function(self) self:Hide() end)
  end
  confirm.index = i
  local name, tex = GetQuestItemInfo("choice", i)
  local link = GetQuestItemLink("choice", i)
  confirm.item.tex:SetTexture(tex or 134400)
  confirm.text:SetText((link or name or "This reward") .. "\n" ..
    (isUpgrade and Q.Color("40ff40", ("An upgrade (+%d%%)"):format(math.floor(pct or 0)))
      or Q.Color("c0c0c0", "No upgrade among the rewards - this one sells for the most")))
  confirm:ClearAllPoints()
  if QuestFrame and QuestFrame:IsShown() then
    confirm:SetPoint("TOPLEFT", QuestFrame, "TOPRIGHT", 8, -40)
  else
    confirm:SetPoint("CENTER", 0, 120)
  end
  confirm:Show()
end

-- after a quest is accepted or handed in the NPC often still has more: carry on with the list
Q:On("QUEST_FINISHED", function()
  Q.After(0.25, function()
    if paused() then return end
    if GossipFrame and GossipFrame:IsShown() then gossip()
    elseif QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then greeting() end
  end)
end)

-- two quest-automation addons fight over the same NPC window (one accepts, the other closes it)
Q:On("QC_READY", function()
  local others = { "SmartQuestAutomation", "AutoTurnIn", "QuickQuest" }
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  for _, name in ipairs(others) do
    if isLoaded and isLoaded(name) and (Q.prefs.autoAccept or Q.prefs.autoTurnIn) then
      Q:Print(("|cffff6152%s is also automating quests.|r Two of them at once fight over the NPC window, so " ..
        "quests get picked up or handed in only sometimes. Turn one off: disable %s, or Questicus' auto accept / " ..
        "turn-in in /qc options."):format(name, name))
    end
  end
end)
