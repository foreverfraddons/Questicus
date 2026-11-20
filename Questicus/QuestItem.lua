-- Questicus quest item button: a click-to-use button for the item a quest wants you to use (the
-- Swineherd's Staff on the boars, a torch on the tents, ...). It shows up only when you target the
-- npc / object the item is used on, or stand at the spot where it's used (for places and objects,
-- not mobs: those need targeting). Click it (or press its key: Esc > Options > Key Bindings > Questicus)
-- to use the item. Shift-drag moves it.
-- It's a secure action button: WoW doesn't let addons show, hide or change it in combat, so it is
-- set up before the fight and stays as it was until the fight ends.
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local QI = {}
Q.QuestItem = QI

-- key binding names (Bindings.xml)
BINDING_HEADER_QUESTICUS = "Questicus"
_G["BINDING_NAME_CLICK QuesticusQuestItem:LeftButton"] = "Use quest item"

local btn
local AREA = 40             -- yards: "at the spot where the item is used"

-- ------------------------------------------------------------------ which item
local function itemSpell(item)
  local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  if not f then return true end            -- can't tell: assume usable
  local ok, name = pcall(f, item)
  return ok and name ~= nil
end
local function count(item)
  return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item)) or (GetItemCount and GetItemCount(item)) or 0
end

-- usable items per quest in your log: the game's own "special item", else the item the quest gave
-- you (qx 18) or needs you to carry (qx 21), if it's in your bags and has a use
function QI:Items()
  local out = {}
  for id, e in pairs(QS.log) do
    if not e.complete then
      local item
      if GetQuestLogSpecialItemInfo then
        local idx = e.index
        if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then idx = C_QuestLog.GetLogIndexForQuestID(id) or idx end
        if idx then
          local ok, link = pcall(GetQuestLogSpecialItemInfo, idx)
          item = ok and link and tonumber(tostring(link):match("item:(%d+)")) or nil
        end
      end
      if not item then
        local info = QS:Info(id)
        local x = (info and info.x) or D:QuestExtra(id) or {}
        local cands = {}
        if x[18] then cands[#cands + 1] = x[18] end
        for _, it in ipairs(x[21] or {}) do cands[#cands + 1] = it end
        for _, it in ipairs(cands) do
          if count(it) > 0 and itemSpell(it) then item = it; break end
        end
      end
      if item and count(item) > 0 then out[id] = item end
    end
  end
  return out
end

local function npcKeyOf(unit) return Q.UnitKey(unit) end

-- does this quest want that npc / object? (its objectives, extra targets, or recorded sources)
local function wants(id, key)
  if not key then return false end
  local m = P.Meta(id)
  -- only objectives still open: once that part is done the button stays away
  local open = m and P.OpenLines(id, m) or {}
  local anyLine = false
  for li, l in ipairs(m and m.lines or {}) do
    if l.key == key then anyLine = true; if open[li] then return true end end
    for _, k in ipairs(l.srcs or {}) do
      if k == key then anyLine = true; if open[li] then return true end end
    end
  end
  if anyLine then return false end
  local info = QS:Info(id)
  for _, ref in ipairs(info and info.x and info.x[23] or {}) do if ref == key then return true end end
  for _, k in ipairs(D:QuestSources(id)) do if k == key then return true end end
  return false
end

-- the item to offer now and why, or nil
function QI:Pick()
  local items = QI:Items()
  if not next(items) then return end
  if Q.OnTaxi() then return end
  -- 1. your target is the npc / object one of these quests uses its item on
  -- (target only: mouseover would hide the button while you move the mouse to it)
  local key = npcKeyOf("target")
  if key then
    for id, item in pairs(items) do
      if wants(id, key) then return item, id, "for " .. D:Name(key) end
    end
  end
  -- 2. you're standing at a spot where the item is used: objects, places and the game's quest
  -- marker - not mob spawns (for mobs you target them)
  local here = D:PlayerPos()
  if here then
    for id, item in pairs(items) do
      local m = P.Meta(id)
      for li in pairs(m and m.lp and P.OpenLines(id, m) or {}) do
        local line = m.lines and m.lines[li]
        local mob = line and type(line.key) == "string" and line.key:sub(1, 1) == "c"
        if not mob then
          for _, p in ipairs(m.lp[li] or {}) do
            local k = p.key
            local pmob = type(k) == "string" and k:sub(1, 1) == "c"
            if not pmob and p.i == here.i and D.Dist(here, p) <= AREA then return item, id, "you're at the spot" end
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ button
local function build()
  btn = CreateFrame("Button", "QuesticusQuestItem", UIParent, "SecureActionButtonTemplate")
  btn:SetSize(44, 44)
  btn:SetFrameStrata("MEDIUM")
  btn:SetClampedToScreen(true)
  btn:SetMovable(true)
  -- WoW uses action buttons on key/mouse DOWN by default (ActionButtonUseKeyDown): register both,
  -- or the click never reaches the item (0.5.4 bug)
  btn:RegisterForClicks("AnyUp", "AnyDown")
  btn:SetAttribute("type", "item")
  btn:SetAttribute("shift-type1", "macro")      -- Shift-drag moves it without using the item
  btn:SetAttribute("shift-macrotext1", "")
  local at = Q.db.questItem and Q.db.questItem.at
  if at then btn:SetPoint(at[1], UIParent, at[1], at[2], at[3]) else btn:SetPoint("CENTER", UIParent, "CENTER", 0, -170) end
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("TOPLEFT", 3, -3); btn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  if btn.icon.SetTexCoord then btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  T.Border(btn, T.c.gold, 6, 2)
  btn.glow = btn:CreateTexture(nil, "BACKGROUND")
  btn.glow:SetPoint("TOPLEFT", -14, 14); btn.glow:SetPoint("BOTTOMRIGHT", 14, -14)
  btn.glow:SetTexture(Q.MEDIA .. "glow")
  btn.glow:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 0.55)
  btn.count = T.Text(btn, 12, T.c.text, "OUTLINE")
  btn.count:SetPoint("BOTTOMRIGHT", -3, 3)
  btn.label = T.Text(btn, 11, T.c.gold, "OUTLINE")
  btn.label:SetPoint("TOP", btn, "BOTTOM", 0, -3)
  btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
  btn.cd:SetAllPoints(btn.icon)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self.item and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.item) end
    GameTooltip:AddLine("Questicus: click to use" .. (self.why and (" (" .. self.why .. ")") or ""), 0.9, 0.8, 0.5, true)
    GameTooltip:AddLine("Shift-drag to move", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnMouseDown", function(self)
    if IsShiftKeyDown and IsShiftKeyDown() and not (InCombatLockdown and InCombatLockdown()) then
      self:StartMoving()
      QI.moving = true
    end
  end)
  btn:SetScript("OnMouseUp", function(self)
    -- a secure button can't be moved / stopped in combat: only finish a move that started out of it
    if not QI.moving or (InCombatLockdown and InCombatLockdown()) then return end
    QI.moving = nil
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    Q.db.questItem = Q.db.questItem or {}
    Q.db.questItem.at = { p, x, y }
  end)
  btn:Hide()
end

local function fight() return InCombatLockdown and InCombatLockdown() end

function QI:Refresh()
  if Q.db.questItem and Q.db.questItem.off then if btn and not fight() then btn:Hide() end return end
  if not (D:Ready() and Q.char and Q.char.surveyDone) then return end
  if fight() then QI.pending = true; return end      -- protected: wait for the fight to end
  if not btn then build() end
  local item, qid, why = QI:Pick()
  if not item then btn:Hide(); btn.item = nil; return end
  if btn.item ~= item then
    btn:SetAttribute("item", "item:" .. item)
    btn.item = item
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)) or select(10, Q.GetItemInfo(item)) or 134400
    btn.icon:SetTexture(icon)
  end
  btn.why, btn.quest = why, qid
  local n = count(item)
  btn.count:SetText(n > 1 and n or "")
  local qi = QS:Info(qid)
  btn.label:SetText(qi and qi.title or "")
  btn:Show()
  QI:Cooldown()
end

function QI:Cooldown()
  if not (btn and btn.item and btn:IsShown()) then return end
  local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if not f then return end
  local ok, start, dur = pcall(f, btn.item)
  if ok and start and dur and dur > 1.5 then btn.cd:SetCooldown(start, dur) end
end

local function soon() Q.Throttle("questitem", 0.25, function() QI:Refresh() end) end
Q:On("PLAYER_TARGET_CHANGED", soon)
Q:On("BAG_UPDATE_DELAYED", soon)
Q:On("QC_QUESTS_CHANGED", soon)
Q:On("QC_PLAN_UPDATED", soon)
Q:On("QC_TARGET_CHANGED", soon)
Q:On("BAG_UPDATE_COOLDOWN", function() QI:Cooldown() end)
Q:On("PLAYER_REGEN_ENABLED", function() if QI.pending then QI.pending = nil; QI:Refresh() end end)
-- walking into / out of an objective area
local tick = CreateFrame("Frame")
local acc = 0
tick:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 1.5 then return end
  acc = 0
  QI:Refresh()
end)

Q:Command("questitem", "the quest item button: /qc questitem off | on", function(arg)
  Q.db.questItem = Q.db.questItem or {}
  Q.db.questItem.off = (arg == "off")
  QI:Refresh()
  Q:Print("quest item button " .. (Q.db.questItem.off and "off" or "on"))
end)
