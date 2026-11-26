-- Collectibles: companions (pets), mounts, toys, secrets and library books.
-- * On a Completionist route: companions sold by vendors you pass are bought on the way (the capital
--   pet vendors, Narkk's parrots in Booty Bay, Magus Tirth's Ancona Chicken, the wandering sellers).
--   Quest-given companions and toys come from their quests (Secrets.lua for the hidden ones).
-- * The collectibles tracker (optional - Options > Map & minimap, /qc collectibles): your progress per
--   kind, where each one comes from, and "Add to route" for any of them (on every route style): its
--   quest is added, or the route takes you to its vendor / the mob that drops it / the object it's in.
local Q = Questicus
local L = Q.L
local D, QS, T = Q.Data, Q.Quests, Q.T
local C = {}
Q.Collectibles = C

-- vendors whose companions are bought with gold (no event, currency or reputation)
C.VENDORS = { [6367] = true, [1263] = true, [8665] = true, [8404] = true, [8403] = true, [8401] = true,
  [2663] = true, [6548] = true, [8666] = true, [262471] = true, [268745] = true }
-- toys the database can't tell from other items (the game's toy box adds the rest)
C.TOYS = { 280612, 279471 }
local NEAR = 250              -- yards: only when the route passes by
local MONEY = 10000           -- keep at least 1 gold for the rest

local function owned(item)
  if Q.Secrets and Q.Secrets.Owned then return Q.Secrets.Owned(item) end
  return ((C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item, true)) or 0) > 0
end
C.Owned = owned

-- ------------------------------------------------------------------ the lists
local lists = {}
local function bad(name) return not name or name:find("%[") or name:find("^Test") or name:find("^zz") or name:find("Deprecated") end
function C.List(kind)
  if lists[kind] then return lists[kind] end
  local db = D.db or {}
  local out, seen = {}, {}
  local function add(id)
    if id and not seen[id] then
      local it = db.item and db.item[id]
      if it and not bad(it[1]) then seen[id] = true; out[#out + 1] = id end
    end
  end
  if kind == "pets" then
    for id, it in pairs(db.item or {}) do if it[5] == 15 and it[6] == 2 then add(id) end end
  elseif kind == "mounts" then
    for id, it in pairs(db.item or {}) do if it[5] == 15 and it[6] == 5 then add(id) end end
  elseif kind == "toys" then
    for _, id in ipairs(C.TOYS) do add(id) end
    -- every toy the game's toy box knows
    local TB = C_ToyBox
    if TB and TB.GetNumToys and TB.GetToyFromIndex then
      pcall(function()
        if TB.SetCollectedShown then TB.SetCollectedShown(true) end
        if TB.SetUncollectedShown then TB.SetUncollectedShown(true) end
        if TB.ForceToyRefilter then TB.ForceToyRefilter() end
        for i = 1, TB.GetNumToys() or 0 do
          local id = TB.GetToyFromIndex(i)
          if id and id > 0 then
            if db.item and db.item[id] then add(id) elseif not seen[id] then seen[id] = true; out[#out + 1] = id end
          end
        end
      end)
    end
  end
  table.sort(out, function(a, b) return (D:Name("i" .. a) or "") < (D:Name("i" .. b) or "") end)
  lists[kind] = out
  return out
end

-- item -> quests that give it
local rewIdx
local function rewardQuests(item)
  if not rewIdx then
    rewIdx = {}
    for q, r in pairs(D.db and D.db.rew or {}) do
      local function scan(v)
        if type(v) == "number" then rewIdx[v] = rewIdx[v] or {}; table.insert(rewIdx[v], q)
        elseif type(v) == "table" then for _, x in pairs(v) do scan(x) end end
      end
      scan(r)
    end
  end
  return rewIdx[item]
end

local function zoneOf(key)
  local p = D:Points(key)
  p = p and p[1]
  local map = p and D:MapPos(p)
  local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name, p
end

-- where an item comes from: list of { kind = quest / vendor / drop / object, key, quest, chance }
function C.Sources(item)
  local out = {}
  for _, q in ipairs(rewardQuests(item) or {}) do
    if QS:Info(q) then out[#out + 1] = { kind = "quest", quest = q } end
  end
  for _, s in ipairs(D:ItemSources(item, 6)) do
    local kind = s.vendor and "vendor" or (s.key:sub(1, 1) == "o" and "object" or "drop")
    if not s.vendor or D:Faction(tonumber(s.key:sub(2))) ~= (Q.player.faction == "A" and "H" or "A") then
      out[#out + 1] = { kind = kind, key = s.key, chance = s.chance }
    end
  end
  return out
end

function C.SourceText(item)
  local s = C.Sources(item)[1]
  if not s then return L["Where it comes from isn't known yet"] end
  if s.kind == "quest" then
    local info = QS:Info(s.quest)
    return L("Quest: %s", info and info.title or tostring(s.quest))
  end
  local who, zone = D:Name(s.key), zoneOf(s.key)
  local where = zone and (" - " .. zone) or ""
  if s.kind == "vendor" then return L("Sold by %s", who) .. where end
  if s.kind == "object" then return L("Found in %s", who) .. where end
  local pct = (s.chance or 0) > 0 and (" (" .. (s.chance >= 0.1 and ("%d%%"):format(math.floor(s.chance * 100 + 0.5)) or ("%.1f%%"):format(s.chance * 100)) .. ")") or ""
  return L("Drops from %s", who) .. pct .. where
end

-- ------------------------------------------------------------------ on the route
local function wanted() Q.char.collectWant = Q.char.collectWant or {} return Q.char.collectWant end
function C.Want(item, on)
  local w = wanted()
  if on then
    w[item] = true
    -- from a quest: that quest (and the chain before it) goes on the route
    local s = C.Sources(item)[1]
    if s and s.kind == "quest" and Q.Tracker and Q.Tracker.Force then Q.Tracker:Force(s.quest, true) end
  else
    w[item] = nil
    local s = C.Sources(item)[1]
    if s and s.kind == "quest" and Q.Tracker and Q.Tracker.Force and Q.char.forced and Q.char.forced[s.quest] then
      Q.Tracker:Force(s.quest, false)
    end
  end
  if Q.Planner then Q.Planner:BuildAsync() end
end
function C.Wanted(item) return wanted()[item] == true end

local pets
local function vendorPets()
  if pets then return pets end
  pets = {}
  local db = D.db
  if not (db and db.vend and db.item) then pets = nil; return {} end
  local fac = Q.player and Q.player.faction
  for item, npcs in pairs(db.vend) do
    local it = db.item[item]
    if it and it[5] == 15 and it[6] == 2 then
      for _, n in ipairs(npcs) do
        local f = D:Faction(n)
        if C.VENDORS[n] and (not f or f == "AH" or f == fac) then
          pets[#pets + 1] = { item = item, npc = n }
        end
      end
    end
  end
  table.sort(pets, function(a, b) return a.item < b.item end)
  return pets
end

local tasks, pts = {}, {}
local function nearestOf(st, key, maxd)
  local list = pts[key]
  if not list then list = D:Points(key) or {}; pts[key] = list end
  local best, bd
  for _, pt in ipairs(list) do
    local d = (st.pos and pt.i == st.pos.i) and D.Dist(st.pos, pt) or 1e6
    if not bd or d < bd then best, bd = pt, d end
  end
  if best and maxd and bd > maxd then return nil end
  return best, bd
end

local function provider(st, lv, add, travel)
  if not st.pos then return end
  local money = GetMoney and GetMoney() or 0
  -- Completionist: vendor companions on the way
  if Q.prefs and Q.prefs.style == "complete" and money >= MONEY then
    for _, p in ipairs(vendorPets()) do
      if not owned(p.item) and not C.Wanted(p.item) then
        local key = "c" .. p.npc
        local best = nearestOf(st, key, NEAR)
        if best then
          local k = "pet:" .. p.item
          local t = tasks[k]
          if not t then
            local name, who = D:Name("i" .. p.item) or "?", D:Name(key) or "?"
            t = { key = k, icon = "buy", quests = {}, pet = p.item,
              text = L("Buy %s from %s (a companion)", "|cffffd100" .. name .. "|r", "|cffffffff" .. who .. "|r"),
              short = L("Buy %s", name),
              why = { L["Completionist: a companion for your collection, sold right on your way"] } }
            tasks[k] = t
          end
          add(t, best, travel(st.pos, best, lv) + 12, QS.QuestXP(lv, lv) * 0.5)
        end
      end
    end
  end
  -- what you added from the collectibles tracker (every route style)
  for item in pairs(wanted()) do
    if owned(item) then
      wanted()[item] = nil
    else
      local name = D:Name("i" .. item) or "?"
      for _, s in ipairs(C.Sources(item)) do
        if s.kind ~= "quest" then
          local best = nearestOf(st, s.key)
          if best then
            local k = "want:" .. item
            local who = D:Name(s.key) or "?"
            local t = { key = k, icon = s.kind == "vendor" and "buy" or (s.kind == "drop" and "kill" or "loot"), quests = {}, pet = item,
              why = { L["You added it from the collectibles tracker"] } }
            if s.kind == "vendor" then
              t.text = L("Buy %s from %s", "|cffffd100" .. name .. "|r", "|cffffffff" .. who .. "|r")
            elseif s.kind == "object" then
              t.text = L("Get %s from %s", "|cffffd100" .. name .. "|r", "|cffffffff" .. who .. "|r")
            else
              t.text = L("Kill %s until %s drops", "|cffffffff" .. who .. "|r", "|cffffd100" .. name .. "|r")
            end
            t.short = name
            local work = s.kind == "drop" and math.min(600, 20 / math.max(0.02, s.chance or 0.05)) or 15
            add(t, best, travel(st.pos, best, lv) + work, QS.QuestXP(lv, lv) * 40)
            break
          end
        end
      end
    end
  end
end
if Q.Planner and Q.Planner.AddTasks then Q.Planner.AddTasks(provider) end

-- got it: the route moves on, and the tracker says so
local known = {}
local function check()
  local P = Q.Planner
  local s = P and P.steps and P.steps[1]
  if s and s.type == "task" and s.task and s.task.pet and owned(s.task.pet) then P:Replan(0.3) end
  if not (Q.prefs and Q.prefs.collectTracker) then return end
  for item in pairs(known) do
    if known[item] == false and owned(item) then
      known[item] = true
      local kind = C.KindOf(item)
      local list = kind and C.List(kind) or {}
      local have = 0
      for _, id in ipairs(list) do if owned(id) then have = have + 1 end end
      Q:Print(L("New in your collection: %s (%d / %d)", D:Name("i" .. item) or "?", have, #list))
    end
  end
  if C.win and C.win:IsShown() then C:Refresh() end
end
function C.KindOf(item)
  for _, k in ipairs({ "pets", "mounts", "toys" }) do
    for _, id in ipairs(C.List(k)) do if id == item then return k end end
  end
end
Q:On("BAG_UPDATE_DELAYED", function() Q.Throttle("collectCheck", 1, check) end)
Q:On("NEW_PET_ADDED", function() Q.Throttle("collectCheck", 1, check) end)
Q:On("NEW_TOY_ADDED", function() Q.Throttle("collectCheck", 1, check) end)
Q:On("NEW_MOUNT_ADDED", function() Q.Throttle("collectCheck", 1, check) end)
Q:On("COMPANION_LEARNED", function() Q.Throttle("collectCheck", 1, check) end)
Q:On("LEARNED_SPELL_IN_TAB", function() Q.Throttle("collectCheck", 1, check) end)
Q:On("QC_READY", function()
  if not (Q.prefs and Q.prefs.collectTracker) then return end
  Q.After(5, function()
    for _, k in ipairs({ "pets", "mounts", "toys" }) do
      for _, id in ipairs(C.List(k)) do known[id] = owned(id) end
    end
  end)
end)

-- ------------------------------------------------------------------ the tracker window
local KINDS = { { "pets", "Companions" }, { "mounts", "Mounts" }, { "toys", "Toys" }, { "secrets", "Secrets" }, { "books", "Library books" } }
C.kind = "pets"
local rows = {}

-- rows for the window: { icon, name, sub, done, item / chain / book }
local function entries(kind)
  local out = {}
  if kind == "secrets" then
    local S = Q.Secrets
    for key, ch in pairs(S and S.CHAINS or {}) do
      local n, all, any = 0, 0, false
      for _, q in ipairs(ch.quests) do
        local info = QS:Info(q)
        if info then
          all = all + 1
          any = true
          if QS.done[q] then n = n + 1 end
        end
      end
      if any then
        out[#out + 1] = { icon = 134939, name = L[ch.name], sub = L("%d of %d quests done", n, all), done = n >= all,
          chain = key }
      end
    end
    for _, t in ipairs(S and S.TASKS or {}) do
      out[#out + 1] = { item = t.item, name = D:Name("i" .. t.item) or "?", sub = L[t.text]:gsub("^[^:]*: ", ""), done = owned(t.item) }
    end
  elseif kind == "books" then
    local B = Q.Books
    for _, b in ipairs(B and B.List() or {}) do
      if QS:Info(b.quest) then
        local zone = zoneOf(b.obj)
        local state = B.Done(b) and L["handed in"] or (B.Carried(b) and L["in your bags"]) or (B.Banked(b) and L["in the bank"]) or nil
        out[#out + 1] = { item = b.item, name = D:Name("i" .. b.item) or (QS:Info(b.quest).title), sub = (zone or "") .. (state and ("  - " .. state) or ""),
          done = B.Done(b), book = b }
      end
    end
  else
    for _, id in ipairs(C.List(kind)) do
      out[#out + 1] = { item = id, name = D:Name("i" .. id) or ("item " .. id), done = owned(id) }
    end
  end
  table.sort(out, function(a, b)
    if a.done ~= b.done then return not a.done end
    return a.name < b.name
  end)
  return out
end

local function row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, C.win.body)
  r:SetHeight(34)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.06) end
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(26, 26)
  r.icon:SetPoint("LEFT", 6, 0)
  r.name = T.Text(r, 12, T.c.text)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
  r.name:SetPoint("RIGHT", -96, 0)
  r.sub = T.Text(r, 10, T.c.dim)
  r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
  r.sub:SetPoint("RIGHT", -96, 0)
  r.state = T.Text(r, 11, T.c.dim)
  r.state:SetPoint("RIGHT", -8, 0)
  r:RegisterForClicks("AnyUp")
  r:SetScript("OnClick", function(self)
    local e = self.e
    if not e or e.done then return end
    if e.chain then
      -- a secret: its first quest you can take goes on the route
      for _, q in ipairs(Q.Secrets.CHAINS[e.chain].quests) do
        if QS:Info(q) and not QS.done[q] and Q.Tracker and Q.Tracker.Force then Q.Tracker:Force(q, true); break end
      end
      if Q.Planner then Q.Planner:BuildAsync() end
    elseif e.item and not e.book then
      C.Want(e.item, not C.Wanted(e.item))
    end
    C:Refresh()
  end)
  r:SetScript("OnEnter", function(self)
    local e = self.e
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.item and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, e.item) else GameTooltip:AddLine(e.name) end
    if e.item and not e.book then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(C.SourceText(e.item), 0.85, 0.75, 0.6, true)
    end
    if not e.done and not e.book then
      GameTooltip:AddLine(L["Click: add to your route / take it off"], 0.5, 0.85, 0.4)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

function C:Refresh()
  local win = C.win
  if not (win and win:IsShown()) then return end
  local list = entries(C.kind)
  local have = 0
  for _, e in ipairs(list) do if e.done then have = have + 1 end end
  win.count:SetText(L("%d / %d collected", have, #list))
  win.bar:SetValue(#list > 0 and have / #list or 0)
  local y, n = 0, 0
  local hide = Q.char.collectHideDone
  for _, e in ipairs(list) do
    if not (hide and e.done) then
      n = n + 1
      local r = row(n)
      r.e = e
      local tex = e.icon or (e.item and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.item))
        or (D.db.item[e.item] and D.db.item[e.item][8]))) or 134400
      r.icon:SetTexture(tex)
      r.icon:SetDesaturated(not e.done)
      r.name:SetText(e.done and Q.Color(T.HEX.good, e.name) or e.name)
      r.sub:SetText(e.sub or (e.item and C.SourceText(e.item)) or "")
      if e.done then r.state:SetText(Q.Color(T.HEX.good, L["collected"]))
      elseif (e.item and C.Wanted(e.item)) or (e.chain and Q.char.forced and Q.char.forced[Q.Secrets.CHAINS[e.chain].quests[1]]) then
        r.state:SetText(Q.Color(T.HEX.gold, L["on your route"]))
      else r.state:SetText("") end
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
      y = y + 36
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  win.body:SetHeight(math.max(1, y))
end

function C:Show()
  if not C.win then
    local win = T.Window("QuesticusCollectibles", 480, 560, "Collectibles", "collectWin")
    C.win = win
    local opts = {}
    for _, k in ipairs(KINDS) do opts[#opts + 1] = { k[1], L[k[2]] } end
    win.kinds = T.Segments(win, opts, function() return C.kind end, function(v) C.kind = v; win.scroll:SetVerticalScroll(0); C:Refresh() end, 88)
    win.kinds:SetPoint("TOPLEFT", 12, -32)
    win.count = T.Text(win, 12, T.c.gold)
    win.count:SetPoint("TOPLEFT", 14, -64)
    win.bar = T.Bar(win, 300, 8)
    win.bar:SetPoint("LEFT", win.count, "RIGHT", 10, 0)
    win.bar:SetPoint("RIGHT", -14, 0)
    win.scroll = CreateFrame("ScrollFrame", nil, win)
    win.scroll:SetPoint("TOPLEFT", 8, -84)
    win.scroll:SetPoint("BOTTOMRIGHT", -8, 40)
    win.body = CreateFrame("Frame", nil, win.scroll)
    win.body:SetSize(464, 1)
    win.scroll:SetScrollChild(win.body)
    if win.scroll.EnableMouseWheel then win.scroll:EnableMouseWheel(true) end
    win.scroll:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, (win.body:GetHeight() or 0) - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 72)))
    end)
    win.hide = T.Check(win, "Hide what you have", function() return Q.char.collectHideDone end,
      function(v) Q.char.collectHideDone = v or nil; C:Refresh() end)
    win.hide:SetPoint("BOTTOMLEFT", 12, 10)
    win.note = T.Text(win, 10, T.c.dim)
    win.note:SetPoint("BOTTOMRIGHT", -14, 14)
    win.note:SetText(L["Click one to add it to your route"])
  end
  if Q.Bosses then Q.Bosses.Front(C.win) else C.win:Show() end
  C:Refresh()
end
function C:Toggle()
  if C.win and C.win:IsShown() then C.win:Hide() else C:Show() end
end
Q:Command("collectibles", "the collectibles tracker: companions, mounts, toys, secrets, library books", function() C:Toggle() end)
