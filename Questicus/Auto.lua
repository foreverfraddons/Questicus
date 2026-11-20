-- Questicus helpers at quest NPCs: turn in every finished quest, accept every quest that fits
-- your survey answers, take the best reward, and keep going until the NPC has nothing left.
-- Hold Shift while talking to an NPC to do it yourself.
local Q = Questicus
local QS, G = Q.Quests, Q.Gear

local function paused() return (IsShiftKeyDown and IsShiftKeyDown()) or (Q.CollectOnly and Q.CollectOnly()) end

-- any quest Questicus would route for this character (the survey decides), not only the next steps
local function wanted(id)
  if not id or id == 0 then return false end
  if Q.char.skipped[id] then return false end
  if QS:Info(id) == nil then return false end
  -- left out by your settings (dungeon quests off, elites with solo only, escort / PvP off ...)
  local P = Q.Planner
  if P and P.OptedOut and P.OptedOut(id) then return false end
  return true
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
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do offered[q.questID] = true end
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

Q:On("QUEST_COMPLETE", function()
  if paused() or not Q.prefs.autoTurnIn then return end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then return after(function() GetQuestReward(n) end) end
  if not Q.prefs.autoReward then return end
  local i, isUpgrade, pct = G:BestChoice()
  if not i then return end
  local link = GetQuestItemLink("choice", i)
  if isUpgrade then
    Q:Print(("took %s - an upgrade (+%d%%)"):format(link or "the reward", math.floor(pct)))
  else
    Q:Print(("took %s - no upgrade among the rewards, this one sells for the most"):format(link or "the reward"))
  end
  after(function() GetQuestReward(i) end)
end)

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
