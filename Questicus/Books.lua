-- Library books (WoW Forever): books lying around Azeroth that you pick up and donate to your faction's
-- librarian (Garion Wendell, Stormwind / Owen Thadd, Undercity) for gear at 10, 20, 25 and 35 books.
-- Completionist routes pick each book up when you're in its zone at the right level, put the books in
-- the bank when you pass one while the librarian is far away, take them out again in the librarian's
-- city, and hand them in when it's worth the trip: when a reward is due or you're there anyway.
-- The book quests themselves are left out of the normal accept / turn-in planning: the librarian only
-- offers a book's quest while the book is in your bags.
local Q = Questicus
local L = Q.L
local D, QS = Q.Data, Q.Quests
local B = {}
Q.Books = B

-- rewards: quest, books needed (the quest's level requirement is the game's, from ForeverDB)
B.MILESTONES = { { 78150, 10 }, { 79536, 20 }, { 82208, 25 }, { 84394, 35 } }
local LIBRARIAN = { c211033 = true, c211022 = true, c5497 = true, c7825 = true }
-- books in the other faction's capital or towns: only for that faction
local FACTION = {
  [79091] = "A",   -- Archmage Antonidas (Ironforge, Hall of Explorers)
  [79093] = "A",   -- Rumi of Gnomeregan (Sentinel Hill / Thelsamar inn)
  [79094] = "H",   -- The Lessons of Ta'zo (Orgrimmar, Valley of Spirits)
  [79095] = "H",   -- The Apothecary's Metaphysical Primer (Brill)
  [79096] = "H",   -- Ataeric: On Arcane Curiosities (The Sepulcher)
}

local list, byQuest, isMilestone
local function build()
  if list then return list end
  list, byQuest, isMilestone = {}, {}, {}
  local db = D.db
  if not (db and db.qe and db.qg and db.qx) then list = nil; return {} end
  for _, m in ipairs(B.MILESTONES) do isMilestone[m[1]] = m[2] end
  for id, enders in pairs(db.qe) do
    local lib = false
    for _, k in ipairs(enders) do if LIBRARIAN[k] then lib = true end end
    local x = db.qx[id]
    if lib and x and x[10] and #x[10] == 1 and not isMilestone[id] then
      local obj
      for _, k in ipairs(db.qg[id] or {}) do if k:sub(1, 1) == "o" then obj = k end end
      if obj then
        local b = { quest = id, item = x[10][1], obj = obj }
        list[#list + 1] = b
        byQuest[id] = b
      end
    end
  end
  table.sort(list, function(a, b) return a.quest < b.quest end)
  return list
end
B.List = function() return build() end

-- the book quests and rewards are this module's, not the normal planning's
function B.Handles(id)
  build()
  return (byQuest and byQuest[id] ~= nil) or (isMilestone and isMilestone[id] ~= nil) or false
end
-- what Auto may accept at the librarian: a book you carry, a reward you've earned
function B.AutoWanted(id)
  build()
  if byQuest and byQuest[id] then return B.Carried(byQuest[id]) end
  if isMilestone and isMilestone[id] then return B.Count() >= isMilestone[id] end
  return false
end

function B.Wanted() return Q.prefs and Q.prefs.style == "complete" end

-- ------------------------------------------------------------------ live state
local function count(it)
  return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or (GetItemCount and GetItemCount(it)) or 0
end
function B.Carried(b)
  local P = Q.Planner
  if P and P.bagSet then return P.bagSet[b.item] == true end
  return count(b.item) > 0
end
function B.Banked(b) return Q.char and Q.char.bank and Q.char.bank[b.item] == true or false end
function B.Done(b, st) return (st and st.done and st.done[b.quest]) or QS.done[b.quest] or false end
-- books handed in so far
function B.Count(st)
  local n = 0
  for _, b in ipairs(build()) do if B.Done(b, st) then n = n + 1 end end
  return n
end

-- the bank: what's in it, read when you open it (the game only tells while it's open)
local function scanBank()
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return end
  local set = {}
  local bags = { -1 }
  for b = 5, 11 do bags[#bags + 1] = b end
  for _, bag in ipairs(bags) do
    local ok, n = pcall(C.GetContainerNumSlots, bag)
    for slot = 1, (ok and n or 0) do
      local id = C.GetContainerItemID(bag, slot)
      if id then set[id] = true end
    end
  end
  Q.char.bank = set
end
local bankOpen = false
local function bankChanged()
  if not bankOpen then return end
  local before = {}
  for _, b in ipairs(build()) do before[b.quest] = B.Banked(b) end
  scanBank()
  for _, b in ipairs(build()) do
    if before[b.quest] ~= B.Banked(b) then
      if Q.Planner then Q.Planner:Replan(0.5) end
      return
    end
  end
end
Q:On("BANKFRAME_OPENED", function() bankOpen = true; Q.After(0.3, bankChanged); Q.After(0.31, function() if Q.Planner then Q.Planner:Replan(0.5) end end) end)
Q:On("BANKFRAME_CLOSED", function() bankChanged(); bankOpen = false end)
Q:On("PLAYERBANKSLOTS_CHANGED", function() Q.After(0.2, bankChanged) end)
Q:On("BAG_UPDATE_DELAYED", function()
  if bankOpen then Q.After(0.2, bankChanged) end
  -- picked up a book: the route moves on
  local P = Q.Planner
  local s = P and P.steps and P.steps[1]
  if s and s.type == "task" and s.task and s.task.book then Q.After(0.3, function() P:Replan(0.3) end) end
end)
Q:On("QUEST_TURNED_IN", function(id)
  if B.Handles(id) and Q.Planner then Q.Planner:Replan(1) end
end)

-- ------------------------------------------------------------------ where
local pointCache = {}
local function points(key)
  local p = pointCache[key]
  if not p then p = D:Points(key) or {}; pointCache[key] = p end
  return p
end
local function nearest(from, pts)
  local best, bd
  for _, p in ipairs(pts) do
    local d = (from and p.i == from.i) and D.Dist(from, p) or (1e6 + (p.x or 0) * 0)
    if not bd or d < bd then best, bd = p, d end
  end
  return best, bd
end
-- the lowest level of the zone a spot is in (Zones.lua), nil for cities
local function zoneLow(p)
  local map = D:MapPos(p)
  local r = map and Q.Zones and Q.Zones.Ranges and Q.Zones.Ranges()[map]
  return r and r[1] or nil, map
end
local bankers
local function bankerPoints()
  if bankers then return bankers end
  bankers = {}
  local fac = Q.player and Q.player.faction
  for id, n in pairs(D.db and D.db.npc or {}) do
    if n[2] == "Banker" then
      local f = D:Faction(id)
      if not f or f == "AH" or f == fac then
        for _, p in ipairs(points("c" .. id)) do bankers[#bankers + 1] = p end
      end
    end
  end
  return bankers
end
-- the librarian of your faction (the enders of a book quest you can do)
local function librarian(st, b)
  local info = QS:Info(b.quest)
  local best, bd, bk
  for _, k in ipairs(info and info.enders or {}) do
    local p, d = nearest(st.pos, points(k))
    if p and (not bd or d < bd) then best, bd, bk = p, d, k end
  end
  return best, bk
end

-- ------------------------------------------------------------------ the route
local function state(st)
  if st.books then return st.books end
  local s = { carry = {}, bank = {}, n = 0 }
  for _, b in ipairs(build()) do
    if B.Done(b, st) then s.n = s.n + 1
    elseif B.Carried(b) then s.carry[b.quest] = b
    elseif B.Banked(b) then s.bank[b.quest] = b end
  end
  st.books = s
  return s
end
local function copy(s)
  local c = { carry = {}, bank = {}, n = s.n }
  for k, v in pairs(s.carry) do c.carry[k] = v end
  for k, v in pairs(s.bank) do c.bank[k] = v end
  return c
end
local function size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- rewards the books you'd hand in earn (quest ids), and what they're worth
local function rewards(st, s, extra, lv)
  local out, v = {}, 0
  for _, m in ipairs(B.MILESTONES) do
    local q, need = m[1], m[2]
    local info = QS:Info(q)
    if info and not st.done[q] and not QS.done[q] and s.n + extra >= need and lv >= (info.min or 1) then
      out[#out + 1] = q
      v = v + QS.QuestXP(lv, lv) * 4 + QS.RewardXP(q, lv)
    end
  end
  return out, v
end
local function booksXP(t, lv)
  local v = 0
  for q in pairs(t) do v = v + (QS.RewardXP(q, lv) or 0) end
  return v
end

local tasks = {}
local function task(key, make)
  local t = tasks[key]
  if not t then t = make(); t.key = key; tasks[key] = t end
  return t
end

local NEAR = 900                     -- yards: books farther away wait until the route gets close
local function provider(st, lv, add, travel)
  if not B.Wanted() or #build() == 0 then return end
  local s = state(st)
  local fac = Q.player and Q.player.faction
  local first = build()[1]
  -- pick books up
  for _, b in ipairs(list) do
    if not B.Done(b, st) and not s.carry[b.quest] and not s.bank[b.quest] and (not FACTION[b.quest] or FACTION[b.quest] == fac)
      and QS:Info(b.quest) then
      local p, d = nearest(st.pos, points(b.obj))
      local low, map = p and zoneLow(p)
      local here = map and Q.Planner.zoneFocus == map
      if p and d < (here and 1e5 or NEAR) and lv >= (low or 1) then
        local name = D:Name("i" .. b.item) or (QS:Info(b.quest) or {}).title or L["a library book"]
        local t = task("book:" .. b.quest, function()
          return { book = true, icon = "loot", quests = {},
            text = L("Pick up the library book %s", "|cffffd100" .. name .. "|r"), short = L("Pick up %s", name),
            why = { L["Completionist: a library book - donate it to your faction's librarian; 10, 20, 25 and 35 books earn rewards"] } }
        end)
        t.apply = function(sim) local c = copy(state(sim)); c.carry[b.quest] = b; sim.books = c end
        add(t, p, travel(st.pos, p, lv) + 15, (QS.RewardXP(b.quest, lv) or 0) + QS.QuestXP(lv, lv) * 0.6)
      end
    end
  end
  local nc, nb = size(s.carry), size(s.bank)
  if nc + nb == 0 or not first then return end
  local lib, libKey = librarian(st, first)
  if not lib then return end
  local libName = D:Name(libKey) or L["the librarian"]
  -- banked books and a bank in the librarian's city: take them out first, then hand in everything
  local libBank = nb > 0 and nearest(lib, bankerPoints())
  if libBank and not (libBank.i == lib.i and D.Dist(libBank, lib) < 700) then libBank = nil end
  -- hand them in (what you carry)
  if nc > 0 and not libBank then
    local rq, rv = rewards(st, s, nc, lv)
    local quests = {}
    for q in pairs(s.carry) do quests[#quests + 1] = q end
    table.sort(quests)
    for _, q in ipairs(rq) do quests[#quests + 1] = q end
    local t = { key = "books:handin:" .. s.n .. ":" .. nc, book = true, icon = "turnin" }
    t.quests = quests
    t.text = L("Hand your library books to %s (%d)", "|cffffffff" .. libName .. "|r", nc)
      .. (#rq > 0 and ("|cff40ff40 " .. L["+ reward"] .. "|r") or "")
    t.short = L("Hand in %d books", nc)
    t.why = { #rq > 0 and L("%d books handed in earns the next library reward - worth the trip now", s.n + nc)
      or L["The librarian is on your way - the books count toward the rewards"] }
    t.apply = function(sim)
      local c = copy(state(sim))
      for q in pairs(c.carry) do sim.done[q] = true; c.n = c.n + 1 end
      c.carry = {}
      for _, q in ipairs(rq) do sim.done[q] = true end
      sim.books = c
    end
    add(t, lib, travel(st.pos, lib, lv) + 10 + 3 * nc, booksXP(s.carry, lv) + rv)
  end
  -- banked books: take them out in the librarian's city first
  if libBank then
    local bk = libBank
    do
      local all = copy(s)
      for q, b in pairs(all.bank) do all.carry[q] = b end
      local rq, rv = rewards(st, s, nc + nb, lv)
      local t = { key = "books:withdraw:" .. s.n .. ":" .. nb, book = true, icon = "loot", quests = {} }
      t.text = L("Take your %d library books out of the bank (for %s)", nb, "|cffffffff" .. libName .. "|r")
      t.short = L("Take %d books out of the bank", nb)
      t.why = { L["The librarian is close: the books you left in the bank go with you"] }
      t.apply = function(sim)
        local c = copy(state(sim))
        for q, b in pairs(c.bank) do c.carry[q] = b end
        c.bank = {}
        sim.books = c
      end
      -- (worth as much as the hand-in it leads to)
      add(t, bk, travel(st.pos, bk, lv) + travel(bk, lib, lv) + 25, (booksXP(all.carry, lv) + rv) * 0.95)
    end
  end
  -- carrying several and passing a bank while the librarian is far: leave them there (bag space)
  if nc >= 3 then
    local bk, d = nearest(st.pos, bankerPoints())
    local far = (lib.i ~= st.pos.i) or D.Dist(st.pos, lib) > 1500
    if bk and d < 150 and far then
      local t = { key = "books:deposit:" .. s.n .. ":" .. nc, book = true, icon = "loot", quests = {} }
      t.text = L("Put your %d library books in the bank - you'll take them out again near %s", nc, "|cffffffff" .. libName .. "|r")
      t.short = L("Bank %d books", nc)
      t.why = { L["You're at a bank and the librarian is far away: the books stop taking bag space until then"] }
      t.apply = function(sim)
        local c = copy(state(sim))
        for q, b in pairs(c.carry) do c.bank[q] = b end
        c.carry = {}
        sim.books = c
      end
      add(t, bk, travel(st.pos, bk, lv) + 20, QS.QuestXP(lv, lv) * 1.0)
    end
  end
end

if Q.Planner and Q.Planner.AddTasks then Q.Planner.AddTasks(provider) end
B.provider = provider
