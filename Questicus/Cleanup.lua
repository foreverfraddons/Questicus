-- Questicus quest log clean-up: abandons quests that aren't in your route (and won't be), and
-- deletes leftover quest items no quest still needs. Always shows the list first: untick anything
-- you want to keep, then press Clean up. /qc cleanup, or the broom button on the guide.
local Q = Questicus
local L = Q.L
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local CL = {}
Q.Cleanup = CL

local frame

-- ------------------------------------------------------------------ what can go
-- quests in the planned route (any step)
local function routeQuests()
  local set = {}
  for _, s in ipairs(P.steps or {}) do
    for _, id in ipairs(s.quests or {}) do set[id] = true end
  end
  return set
end

-- why a quest in your log can go (nil = keep it)
function CL:QuestReason(id, inRoute)
  local e = QS.log[id]
  if not e then return end
  if inRoute[id] then return end
  local info = QS:Info(id)
  if Q.char.skipped[id] then return "you removed it from the route", true end
  local ex = P.Excluded and not e.complete and P.Excluded(id)
  if ex then return ex, true end
  if P.OptedOut and P.OptedOut(id) and P.Kind(id) then
    local k = P.Kind(id)
    return (k == "pvp" and "PvP quest" or k == "escort" and "escort quest" or "cooking / recipe quest") .. " - turned off in your settings", true
  end
  local lvl = (info and info.level) or e.level
  if lvl and lvl <= QS.GreyLevel(Q.player.level) then return "grey - gives almost no XP", true end
  if lvl and (Q.prefs.levelBelow or 0) > 0 and lvl < Q.player.level - Q.prefs.levelBelow and not e.complete then
    return ("more than %d levels below you"):format(Q.prefs.levelBelow), true
  end
  if e.complete then return end                                   -- finished: hand it in, don't throw it away
  local m = info and P.Meta(id)
  if m and m.dungeon then return "dungeon quest - not in the route (needs a group)", false end
  if info and info.level > Q.player.level + (Q.prefs.levelRange or 2) + 2 then return "too high for now", false end
  if not info then return "not in the database - Questicus can't route it", false end
  return "not in your route", true
end

-- bag items: { bag, slot, item, count }
local function bagItems()
  local out = {}
  local C = C_Container
  local numSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  if not numSlots then return out end
  for bag = 0, 4 do
    for slot = 1, (numSlots(bag) or 0) do
      local item, count
      if C and C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if info then item, count = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        item, count = link and tonumber(link:match("item:(%d+)")), c
      end
      if item then out[#out + 1] = { bag = bag, slot = slot, item = item, count = count or 1 } end
    end
  end
  return out
end
CL.BagItems = bagItems

-- items a quest you keep (or the route) still needs
local function neededItems(keepQuests)
  local need = {}
  local function quest(id)
    local info = QS:Info(id)
    local x = (info and info.x) or D:QuestExtra(id) or {}
    for _, it in ipairs(x[10] or {}) do need[it] = id end
    for _, it in ipairs(x[21] or {}) do need[it] = id end
    if x[18] then need[x[18]] = id end
    if D.startItem and D.startItem[id] then need[D.startItem[id]] = id end
  end
  for id in pairs(keepQuests) do quest(id) end
  for _, s in ipairs(P.steps or {}) do
    if s.startItem then need[s.startItem] = s.quests and s.quests[1] or true end
  end
  return need
end

-- quest that this item starts (if any)
local startsQuest
local function starts(item)
  if not startsQuest then
    startsQuest = {}
    for q, it in pairs(D.startItem or {}) do startsQuest[it] = q end
  end
  return startsQuest[item]
end

-- why a bag item can go (nil = keep)
function CL:ItemReason(item, need)
  if need[item] then return end
  local rec = D:Item(item)
  local q = starts(item)
  if q then
    if QS.done[q] then return "starts a quest you already did" end
    if Q.char.skipped[q] then return "starts a quest you removed from the route" end
    return                                                       -- starts a quest you may still want
  end
  if rec and rec[5] == 12 then return "quest item no quest in your log needs" end
end

function CL:Scan()
  local inRoute = routeQuests()
  local quests, keep = {}, {}
  for id, e in pairs(QS.log) do
    local why, default = CL:QuestReason(id, inRoute)
    if why then
      quests[#quests + 1] = { id = id, title = e.title or ((QS:Info(id) or {}).title) or ("Quest " .. id), why = why, on = default }
    else
      keep[id] = true
    end
  end
  table.sort(quests, function(a, b) return a.title < b.title end)
  -- items: needed by quests you keep (unticked quests count as kept when the list is applied)
  local items = {}
  local need = neededItems(keep)
  local seen = {}
  for _, b in ipairs(bagItems()) do
    local why = CL:ItemReason(b.item, need)
    if why then
      -- also keep items the quests you might keep need (re-checked on Clean up)
      local q
      for _, x in ipairs(quests) do
        local info = QS:Info(x.id)
        local xx = (info and info.x) or {}
        for _, it in ipairs(xx[10] or {}) do if it == b.item then q = x end end
        for _, it in ipairs(xx[21] or {}) do if it == b.item then q = x end end
        if xx[18] == b.item then q = x end
      end
      if q then why = "for " .. q.title .. " (goes if that quest goes)" end
      local name = Q.GetItemInfo(b.item) or D:Name("i" .. b.item)
      items[#items + 1] = { bag = b.bag, slot = b.slot, item = b.item, count = b.count, name = name, why = why, on = true, quest = q }
      seen[b.item] = true
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return quests, items
end

-- ------------------------------------------------------------------ doing it
local function abandon(id)
  if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
    C_QuestLog.SetSelectedQuest(id)
    C_QuestLog.SetAbandonQuest()
    C_QuestLog.AbandonQuest()
    return true
  elseif SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
    local e = QS.log[id]
    if not (e and e.index) then return false end
    SelectQuestLogEntry(e.index)
    SetAbandonQuest()
    AbandonQuest()
    return true
  end
  return false
end

-- WoW Forever doesn't let addons delete items (DeleteCursorItem is protected). Questicus puts the
-- item on your cursor; dropping it on the game world opens the game's own "Destroy item?" box.
local function findItem(item)
  for _, b in ipairs(bagItems()) do if b.item == item then return b.bag, b.slot end end
end
function CL:PickUp(item)
  local bag, slot = findItem(item)
  if not bag then return false end
  local pick = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  if not pick then return false end
  if ClearCursor then ClearCursor() end
  pick(bag, slot)
  return true
end

-- abandons the ticked quests; returns the ticked items to delete by hand
function CL:Apply(quests, items)
  local gone = 0
  local dropped = {}
  for _, q in ipairs(quests) do
    if q.on and abandon(q.id) then gone = gone + 1; dropped[q.id] = true end
  end
  local left = {}
  for _, it in ipairs(items) do
    -- an item for a quest you kept stays
    if it.on and (not it.quest or dropped[it.quest.id]) then left[#left + 1] = it end
  end
  Q:Print(("clean-up: abandoned %d quest(s)%s"):format(gone,
    #left > 0 and (", " .. #left .. " item(s) to delete - click each one's button") or ""))
  P:Replan(0.5)
  return gone, left
end

-- ------------------------------------------------------------------ window
local rows, rowData, rowHead = {}, {}, {}
CL.rows = rows
local function row(i)
  local r = rows[i]
  if not r then
    r = CreateFrame("Frame", nil, frame.list)
    r:SetHeight(20)
    r.check = T.Check(r, "", function() local d = rowData[r] return d and d.on end, function(v) local d = rowData[r] if d then d.on = v end end)
    r.check:SetPoint("LEFT", 0, 0)
    r.check:SetWidth(380)
    r.pick = T.Button(r, "Pick up", 76, 18)
    r.pick:SetPoint("RIGHT", -2, 0)
    r.pick:Hide()
    r.pick:SetScript("OnClick", function()
      local d = rowData[r]
      if d and not CL:PickUp(d.item) then Q:Print(L["that item isn't in your bags any more"]) end
    end)
    r.why = T.Text(r, 10, T.c.dim)
    r.why:SetPoint("RIGHT", -4, 0)
    r.why:SetJustifyH("RIGHT")
    rows[i] = r
  end
  return r
end

function CL:Show()
  if not frame then
    frame = T.Window("QuesticusCleanup", 560, 200, "Clean up quest log", nil)
    frame:SetFrameStrata("DIALOG")
    frame.note = T.Text(frame, 11, T.c.dim)
    frame.note:SetPoint("TOPLEFT", 14, -32)
    frame.note:SetPoint("RIGHT", -14, 0)
    frame.note:SetText(L["Ticked lines go. Untick anything you want to keep."])
    frame.list = CreateFrame("Frame", nil, frame)
    frame.list:SetPoint("TOPLEFT", 14, -52)
    frame.list:SetPoint("RIGHT", -14, 0)
    frame.list:SetHeight(1)
    frame.go = T.Button(frame, "Clean up", 110, 24)
    frame.go:SetPoint("BOTTOMRIGHT", -14, 12)
    frame.go:SetScript("OnClick", function()
      local _, left = CL:Apply(frame.quests or {}, frame.items or {})
      if #left > 0 then CL:ShowItems(left) else frame:Hide() end
    end)
    frame.cancel = T.Button(frame, "Cancel", 90, 24)
    frame.cancel:SetPoint("RIGHT", frame.go, "LEFT", -8, 0)
    frame.cancel:SetScript("OnClick", function() frame:Hide() end)
  end
  local quests, items = CL:Scan()
  frame.quests, frame.items = quests, items
  local n, y = 0, 0
  local function header(text)
    n = n + 1
    local r = row(n)
    rowData[r] = nil
    r.check:Hide()
    r.pick:Hide()
    r.why:SetText("")
    local h = rowHead[r] or T.Text(r, 12, T.c.gold)
    rowHead[r] = h
    h:SetPoint("LEFT", 0, 0)
    h:SetText(text)
    h:Show()
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
    y = y + 22
  end
  local function line(data, text)
    n = n + 1
    local r = row(n)
    rowData[r] = data
    if rowHead[r] then rowHead[r]:Hide() end
    r.pick:Hide()
    r.why:ClearAllPoints(); r.why:SetPoint("RIGHT", -4, 0)
    r.check:Show()
    r.check.label:SetText(text)
    r.check:Refresh()
    r.why:SetText(data.why)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
    y = y + 21
  end
  header(#quests > 0 and L("Quests (%d)", #quests) or L["Quests: nothing to remove - everything in your log is in the route"])
  for _, q in ipairs(quests) do line(q, q.title) end
  y = y + 6
  header(#items > 0 and L("Quest items (%d)", #items) or L["Quest items: nothing left over"])
  for _, it in ipairs(items) do line(it, it.name .. (it.count > 1 and (" x" .. it.count) or "")) end
  for i = n + 1, #rows do rows[i]:Hide() end
  frame.list:SetHeight(math.max(1, y))
  frame:SetHeight(math.min(700, 52 + y + 50))
  frame.go:SetShown(#quests + #items > 0)
  frame.go:SetText(L["Clean up"])
  frame.note:SetText(L["Ticked lines go. Untick anything you want to keep."])
  frame.itemMode = nil
  frame:Show()
  return quests, items
end

-- step 2: items to delete by hand (the game only lets you destroy items yourself)
function CL:ShowItems(list)
  frame.itemMode = list
  frame.note:SetText(L["Click Pick up, then click anywhere on the game world (outside your bags) and confirm the game's \"Destroy\" box."])
  local n, y = 0, 0
  local have = {}
  for _, b in ipairs(bagItems()) do have[b.item] = true end
  for _, it in ipairs(list) do
    if have[it.item] then
      n = n + 1
      local r = row(n)
      rowData[r] = it
      if rowHead[r] then rowHead[r]:Hide() end
      r.check:Hide()
      local h = rowHead[r] or T.Text(r, 12, T.c.text)
      rowHead[r] = h
      h:SetPoint("LEFT", 0, 0)
      h:SetText(it.name .. (it.count > 1 and (" x" .. it.count) or ""))
      h:Show()
      r.pick:Show()
      r.why:SetText("")
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
      y = y + 22
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  if n == 0 then
    frame.itemMode = nil
    frame:Hide()
    Q:Print(L["clean-up done"])
    return
  end
  frame.list:SetHeight(math.max(1, y))
  frame:SetHeight(math.min(700, 52 + y + 50))
  frame.go:SetShown(false)
  frame:Show()
end
-- an item destroyed: take it off the list
Q:On("BAG_UPDATE_DELAYED", function()
  if frame and frame.itemMode and frame:IsShown() then CL:ShowItems(frame.itemMode) end
end)

Q:Command("cleanup", "abandon quests that aren't in your route and delete leftover quest items (shows the list first)", function() CL:Show() end)
