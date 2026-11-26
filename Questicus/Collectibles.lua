-- Collectibles on the way (Completionist): companions sold by vendors you pass - the capital pet
-- vendors, Narkk's parrots in Booty Bay, Magus Tirth's Ancona Chicken, the wandering kitten and wolf pup
-- sellers. Quest-given companions and toys (CLUCK!, WRIGGLE., the torch ...) are in Secrets.lua; the
-- rest come from their normal quests, which a Completionist route already does.
local Q = Questicus
local L = Q.L
local D, QS = Q.Data, Q.Quests
local C = {}
Q.Collectibles = C

-- vendors whose companions are bought with gold (no event, currency or reputation)
C.VENDORS = { [6367] = true, [1263] = true, [8665] = true, [8404] = true, [8403] = true, [8401] = true,
  [2663] = true, [6548] = true, [8666] = true, [262471] = true, [268745] = true }
local NEAR = 250              -- yards: only when the route passes by
local MONEY = 10000           -- keep at least 1 gold for the rest

local pets
local function build()
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

local function owned(item)
  if Q.Secrets and Q.Secrets.Owned then return Q.Secrets.Owned(item) end
  return ((C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item, true)) or 0) > 0
end

local tasks, pts = {}, {}
local function provider(st, lv, add, travel)
  if not (Q.prefs and Q.prefs.style == "complete") then return end
  local money = GetMoney and GetMoney() or 0
  if money < MONEY then return end
  for _, p in ipairs(build()) do
    if not owned(p.item) then
      local key = "c" .. p.npc
      local list = pts[key]
      if not list then list = D:Points(key) or {}; pts[key] = list end
      local best, bd
      for _, pt in ipairs(list) do
        if st.pos and pt.i == st.pos.i then
          local d = D.Dist(st.pos, pt)
          if not bd or d < bd then best, bd = pt, d end
        end
      end
      if best and bd <= NEAR then
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
if Q.Planner and Q.Planner.AddTasks then Q.Planner.AddTasks(provider) end

-- bought it: the route moves on
Q:On("BAG_UPDATE_DELAYED", function()
  local P = Q.Planner
  local s = P and P.steps and P.steps[1]
  if s and s.type == "task" and s.task and s.task.pet and owned(s.task.pet) then P:Replan(0.3) end
end)
