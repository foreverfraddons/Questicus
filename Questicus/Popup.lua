-- Questicus pop-ups: a short animated card whenever a quest objective moves forward or you loot
-- an item a quest in your log needs ("Rot-Covered Harpoon 1/1"), and a bigger one when a quest is
-- complete. Up to four stack under each other; Shift-drag one to move them all.
local Q = Questicus
local T, D, QS = Q.T, Q.Data, Q.Quests
local PU = {}
Q.Popup = PU

local W, H, GAP, MAX = 300, 56, 6, 4
local HOLD, FADE_IN, FADE_OUT = 3.2, 0.18, 0.6
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local DONE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"

local anchor, cards = nil, {}
local snapshot, ready = {}, false
local recentItem = {}          -- [questID] = { icon, t } from the loot message just before progress

local function cfg() return Q.db.popups end

-- ------------------------------------------------------------------ frames
local function buildAnchor()
  anchor = CreateFrame("Frame", "QuesticusPopupAnchor", UIParent)
  anchor:SetSize(W, H)
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  local at = cfg().at
  if at then anchor:SetPoint(at[1], UIParent, at[1], at[2], at[3]) else anchor:SetPoint("TOP", 0, -190) end
end

local function newCard()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(W, H)
  f:SetFrameStrata("HIGH")
  f.bg = T.RFill(f, { T.c.bg[1], T.c.bg[2], T.c.bg[3], 0.94 }, 8)
  T.Border(f, T.c.line, 8)
  f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  f.glow:SetTexture(Q.MEDIA .. "glow")
  f.glow:SetPoint("CENTER", f, "LEFT", 28, 0)
  f.glow:SetSize(90, 90)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(36, 36)
  f.icon:SetPoint("LEFT", 10, 0)
  f.check = f:CreateTexture(nil, "OVERLAY")
  f.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  f.check:SetSize(20, 20)
  f.check:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 6, -6)
  f.title = T.Text(f, 12, T.c.gold)
  f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 1)
  f.title:SetPoint("RIGHT", -10, 0)
  f.title:SetWordWrap(false)
  f.text = T.Text(f, 12, T.c.text)
  f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.text:SetPoint("RIGHT", -44, 0)
  f.text:SetWordWrap(false)
  f.plus = T.Text(f, 14, T.c.good, "OUTLINE")
  f.plus:SetPoint("RIGHT", -10, -1)
  f.plus:SetJustifyH("RIGHT")
  f.bar = T.Bar(f, W - 66, 4)
  f.bar:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 10, 1)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() if IsShiftKeyDown and IsShiftKeyDown() then anchor:StartMoving() end end)
  f:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local p, _, _, x, y = anchor:GetPoint()
    cfg().at = { p, x, y }
    PU:Layout()
  end)
  f:SetScript("OnEnter", function(s) s.hover = true end)
  f:SetScript("OnLeave", function(s) s.hover = false end)
  f:SetScript("OnMouseUp", function(s, btn) if btn == "RightButton" then s.age = 99 end end)
  f:SetScript("OnUpdate", function(s, el)
    if not s.hover then s.age = s.age + el end
    local a
    if s.age < FADE_IN then a = s.age / FADE_IN
    elseif s.age < FADE_IN + s.hold then a = 1
    else a = 1 - (s.age - FADE_IN - s.hold) / FADE_OUT end
    if a <= 0 then s:Hide(); PU:Layout(); return end
    s:SetAlpha(a)
    -- slide in from above, bar fills to the new value
    local slide = math.max(0, 1 - s.age / FADE_IN) * 14
    s:SetPoint("TOP", anchor, "TOP", 0, -s.slot * (H + GAP) + slide)
    if s.barTo then
      s.barNow = s.barNow + (s.barTo - s.barNow) * math.min(1, el * 6)
      s.bar:SetValue(s.barNow)
    end
  end)
  f:Hide()
  return f
end

function PU:Layout()
  local slot = 0
  for _, c in ipairs(cards) do
    if c:IsShown() then
      c.slot = slot
      c:ClearAllPoints()
      c:SetPoint("TOP", anchor, "TOP", 0, -slot * (H + GAP))
      slot = slot + 1
    end
  end
end

-- show a card: { title, text, icon, have, need, done, complete }
function PU:Show(o)
  if not (cfg().on and Q.char and Q.char.surveyDone ~= nil) or (Q.CollectOnly and Q.CollectOnly()) then return end
  if not anchor then buildAnchor() end
  -- the same quest + text again: update that card instead of stacking a new one
  local card
  for _, c in ipairs(cards) do
    if c:IsShown() and c.key == o.key then card = c end
  end
  if not card then
    for _, c in ipairs(cards) do if not c:IsShown() then card = c; break end end
    if not card then
      if #cards < MAX then card = newCard(); cards[#cards + 1] = card
      else
        card = cards[1]
        for _, c in ipairs(cards) do if c.age > card.age then card = c end end
      end
    end
    card.barNow = o.prev or 0
  end
  card.key = o.key
  card.age, card.hold = 0, o.complete and HOLD + 1.5 or HOLD
  card.icon:SetTexture(o.icon or QUEST_ICON)
  card.title:SetText(o.title or "")
  card.text:SetText(o.text or "")
  card.plus:SetText(o.plus or "")
  card.check:SetShown(o.done or o.complete or false)
  local col = o.complete and T.c.good or T.c.accent
  T.SetBorderColor(card, col[1], col[2], col[3], 0.9)
  card.glow:SetVertexColor(col[1], col[2], col[3], o.complete and 0.6 or 0.35)
  card.bar.fill:SetVertexColor(col[1], col[2], col[3], 1)
  if o.need and o.need > 0 then
    card.bar:Show()
    card.barTo = math.min(1, (o.have or 0) / o.need)
  elseif o.complete then
    card.bar:Show(); card.barTo = 1
  else
    card.bar:Hide(); card.barTo = nil
  end
  card:SetAlpha(0)
  card:Show()
  PU:Layout()
  if cfg().sound and PlaySound and SOUNDKIT then
    local kit = o.complete and (SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
      or (SOUNDKIT.IG_QUEST_LIST_SELECT or SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    if kit then pcall(PlaySound, kit) end
  end
end

-- ------------------------------------------------------------------ quest log changes
local function objKey(id, i) return id * 100 + i end

local function parseCount(text)
  local have, need = (text or ""):match("(%d+)%s*/%s*(%d+)")
  return tonumber(have), tonumber(need)
end

function PU:Check()
  local now = GetTime and GetTime() or 0
  for id, e in pairs(QS.log) do
    local s = snapshot[id]
    local title = e.title or (QS:Info(id) and QS:Info(id).title) or ("Quest " .. id)
    if s and ready then
      for i, o in ipairs(e.objectives or {}) do
        local before = s.obj[i]
        local have, need = o.numFulfilled, o.numRequired
        if not have then have, need = parseCount(o.text) end
        local bHave = before and before.have or 0
        local moved = (have and have > bHave) or (o.finished and not (before and before.finished))
        if moved then
          local item = recentItem[id]
          local icon = (item and now - item.t < 6) and item.icon or nil
          local label = (o.text or ""):gsub("^%s*%d+%s*/%s*%d+%s*", "")
          PU:Show({ key = objKey(id, i), title = title, icon = icon,
            text = (o.text and o.text ~= "" and o.text) or label,
            have = have, need = need, prev = need and need > 0 and bHave / need or 0,
            plus = have and bHave and have > bHave and ("+" .. (have - bHave)) or nil,
            done = o.finished })
        end
      end
      if e.complete and not s.complete then
        local info = QS:Info(id)
        local ender = info and info.enders and info.enders[1]
        PU:Show({ key = "done" .. id, title = title, icon = DONE_ICON, complete = true,
          text = "Quest complete" .. (ender and (" - turn in to " .. D:Name(ender)) or "") })
      end
    end
    local obj = {}
    for i, o in ipairs(e.objectives or {}) do
      local have = o.numFulfilled
      if not have then have = parseCount(o.text) end
      obj[i] = { have = have or 0, finished = o.finished }
    end
    snapshot[id] = { obj = obj, complete = e.complete }
  end
  for id in pairs(snapshot) do if not QS.log[id] then snapshot[id] = nil end end
  ready = true
end

-- ------------------------------------------------------------------ quest items you loot
-- quest items without an objective counter (things you need to make the objective, items that
-- start a quest) still get a card; counted ones get their icon on the progress card
local function questFor(itemID)
  for id in pairs(QS.log) do
    local x = (QS:Info(id) or {}).x or D:QuestExtra(id) or {}
    for _, it in ipairs(x[10] or {}) do if it == itemID then return id, true end end
    for _, it in ipairs(x[21] or {}) do if it == itemID then return id, false end end
  end
  if D.db and D.db.start and D.db.start[itemID] then return D.db.start[itemID], false, true end
end

Q:On("CHAT_MSG_LOOT", function(msg)
  if not (cfg().on and type(msg) == "string") or Q.Secret(msg) then return end
  -- only your own loot / items handed to you ("You receive loot: ...", "You receive item: ...")
  local mine = false
  for _, fmt in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE }) do
    if type(fmt) == "string" then
      local prefix = fmt:gsub("%%s.*", ""):gsub("%p", "%%%0")
      if prefix ~= "" and msg:find("^" .. prefix) then mine = true; break end
    end
  end
  if not mine and (LOOT_ITEM_SELF or LOOT_ITEM_PUSHED_SELF) then return end
  local itemID = tonumber(msg:match("|Hitem:(%d+)"))
  if not itemID then return end
  local qid, counted, starts = questFor(itemID)
  if not qid then return end
  local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or
    (GetItemIcon and GetItemIcon(itemID)) or nil
  recentItem[qid] = { icon = icon, t = GetTime and GetTime() or 0 }
  if counted then return end              -- the progress card follows with this icon
  local link = msg:match("(|c%x+|Hitem:.-|h.-|h|r)") or D:Name("i" .. itemID)
  local info = QS:Info(qid)
  PU:Show({ key = "item" .. itemID, icon = icon, title = info and info.title or ("Quest " .. qid),
    text = (starts and "Starts a quest: " or "Quest item: ") .. link })
end)

Q:On("QC_QUESTS_CHANGED", function() PU:Check() end)
Q:On("QC_READY", function()
  Q.db.popups = Q.fill(Q.db.popups or {}, { on = true, sound = true })
  PU:Check()
end)
Q:Command("popuptest", "show a sample quest pop-up", function()
  PU:Show({ key = "test", title = "WANTED: Old Rot-Chum", icon = 134400, text = "Rot-Covered Harpoon: 1/1",
    have = 1, need = 1, prev = 0, plus = "+1", done = true })
end)
