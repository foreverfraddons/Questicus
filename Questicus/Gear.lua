-- Questicus gear advisor: scores items for the character's class and role, finds upgrades among
-- quest rewards and vendor items, and picks the best quest reward.
local Q = Questicus
local G = {}
Q.Gear = G
local D = Q.Data

-- ------------------------------------------------------------------ roles and weights
G.ROLES = {
  WARRIOR = { "melee", "tank" }, PALADIN = { "melee", "heal", "tank" }, HUNTER = { "ranged" },
  ROGUE = { "agile" }, PRIEST = { "caster", "heal" }, SHAMAN = { "melee", "caster", "heal" },
  MAGE = { "caster" }, WARLOCK = { "caster" }, DRUID = { "agile", "caster", "heal", "tank" },
}
G.ROLE_NAMES = { melee = "Melee (Strength)", agile = "Melee (Agility)", ranged = "Ranged", caster = "Caster",
  heal = "Healer", tank = "Tank" }

local S = {  -- stat keys from GetItemStats
  STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
  INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT", ARMOR = "RESISTANCE0_NAME",
  AP = "ITEM_MOD_ATTACK_POWER_SHORT", RAP = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", SP = "ITEM_MOD_SPELL_POWER_SHORT",
  HEAL = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", CRIT = "ITEM_MOD_CRIT_RATING_SHORT", HIT = "ITEM_MOD_HIT_RATING_SHORT",
  MP5 = "ITEM_MOD_MANA_REGENERATION_SHORT", DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
  DODGE = "ITEM_MOD_DODGE_RATING_SHORT", BLOCK = "ITEM_MOD_BLOCK_VALUE_SHORT", DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
}
G.STATKEYS = S

-- weights per point, tuned for levelling (weapon speed/DPS matters a lot early)
local W = {
  melee = { STR = 2.0, AGI = 1.0, STA = 0.7, INT = 0.25, AP = 0.9, CRIT = 16, HIT = 16, DPS = 9, ARMOR = 0.012 },
  agile = { AGI = 2.0, STR = 1.0, STA = 0.7, AP = 0.9, CRIT = 16, HIT = 16, DPS = 8, ARMOR = 0.012 },
  ranged = { AGI = 2.2, STA = 0.7, INT = 0.5, AP = 0.5, RAP = 0.9, CRIT = 16, HIT = 16, DPS = 1.5, RDPS = 9, ARMOR = 0.01 },
  caster = { INT = 1.0, SPI = 0.7, STA = 0.8, SP = 1.2, CRIT = 9, HIT = 9, MP5 = 1.5, WDPS = 4, ARMOR = 0.005 },
  heal = { INT = 1.0, SPI = 1.0, STA = 0.5, SP = 0.6, HEAL = 0.8, MP5 = 2.0, ARMOR = 0.005 },
  tank = { STA = 1.6, AGI = 1.0, STR = 1.0, ARMOR = 0.05, DEF = 2.0, DODGE = 14, BLOCK = 0.5, DPS = 4 },
}
G.WEIGHTS = W
G.STAT_NAMES = { STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit", ARMOR = "Armor",
  AP = "Attack power", RAP = "Ranged attack power", SP = "Spell power", HEAL = "Healing", CRIT = "Crit", HIT = "Hit",
  MP5 = "Mana per 5", DEF = "Defense", DODGE = "Dodge", BLOCK = "Block", DPS = "Weapon damage" }
G.STAT_ORDER = { "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "HEAL", "CRIT", "HIT", "MP5", "ARMOR", "DEF", "DODGE", "BLOCK", "DPS" }
G.WEAPON_NAMES = { [0] = "One-hand axes", [1] = "Two-hand axes", [2] = "Bows", [3] = "Guns", [4] = "One-hand maces",
  [5] = "Two-hand maces", [6] = "Polearms", [7] = "One-hand swords", [8] = "Two-hand swords", [10] = "Staves",
  [13] = "Fist weapons", [15] = "Daggers", [16] = "Thrown", [18] = "Crossbows", [19] = "Wands" }
G.ARMOR_NAMES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shields" }

-- what you told Questicus about gear (survey: stat priority + weapon types; "not for me" answers)
local function learned()
  Q.char.gear = Q.char.gear or { deny = {}, armor = {}, weapon = {}, stat = {} }
  return Q.char.gear
end
G.Learned = learned

-- the weights actually used: role, then your stat priority (1st counts most), then what you said
-- about items you turned down ("bad stats for me" lowers those stats)
function G:Weights(role)
  local base = W[role] or W.melee
  local w = {}
  for k, v in pairs(base) do w[k] = v end
  local prio = Q.prefs.statPrio
  if type(prio) == "table" and #prio > 0 then
    local top = 0
    for _, v in pairs(base) do if v < 5 then top = math.max(top, v) end end
    local inPrio = {}
    for i, k in ipairs(prio) do
      inPrio[k] = true
      local mult = ({ 1.6, 1.35, 1.15, 1.05, 1.0 })[i] or 1
      local v = w[k] or (top > 0 and top * 0.6) or 1
      if k == "CRIT" or k == "HIT" or k == "DODGE" then v = w[k] or 12 end
      if k == "DPS" then v = w[k] or 6 end
      w[k] = v * mult
    end
    for k, v in pairs(w) do
      if not inPrio[k] and k ~= "DPS" and k ~= "RDPS" and k ~= "WDPS" and k ~= "ARMOR" then w[k] = v * 0.8 end
    end
  end
  for k, f in pairs(learned().stat or {}) do if w[k] then w[k] = w[k] * f end end
  return w
end

-- armor subclass the class can wear (1 cloth, 2 leather, 3 mail, 4 plate); mail/plate at 40
local ARMOR_MAX = { WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, ROGUE = { 2, 2 },
  DRUID = { 2, 2 }, PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 } }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local DUAL = { WARRIOR = true, ROGUE = true, HUNTER = true }
-- weapon subclasses: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm, 7 1H sword, 8 2H sword,
-- 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local WEAPONS = {
  WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
  PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 }, WARLOCK = { 7, 10, 15, 19 },
  DRUID = { 4, 5, 10, 13, 15 },
}

local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 },
}

function G:Role()
  local pr = Q.prefs
  local cls = Q.player.class
  if pr.role and W[pr.role] then return pr.role end
  return (G.ROLES[cls] or { "melee" })[1]
end

-- ------------------------------------------------------------------ item info
local function itemInfo(item)
  local name, link, quality, ilvl, reqLevel, _, _, _, equipLoc, _, sell, classID, subID = Q.GetItemInfo(item)
  if not name then
    if C_Item and C_Item.RequestLoadItemDataByID and type(item) == "number" then
      pcall(C_Item.RequestLoadItemDataByID, item)
    end
    return nil
  end
  local id = type(item) == "number" and item or tonumber(tostring(link or item):match("item:(%d+)"))
  return { id = id, name = name, link = link, quality = quality, ilvl = ilvl, req = reqLevel or 0, loc = equipLoc,
    sell = sell or 0, class = classID, sub = subID }
end
G.ItemInfo = itemInfo

local function stats(link)
  local f = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not f then return {} end
  local ok, t = pcall(f, link)
  return ok and t or {}
end

-- reputation an item needs (ForeverDB item fields 13 / 14: faction, standing 0 Hated ... 7 Exalted)
G.STANDING = { [0] = "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
function G:RepNeed(id)
  local rec = id and D:Item(id)
  if rec and rec[13] and rec[13] > 0 then return rec[13], rec[14] or 0 end
end
function G:RepOK(id)
  local f, need = G:RepNeed(id)
  if not f then return true end
  local reaction
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, fd = pcall(C_Reputation.GetFactionDataByID, f)
    reaction = ok and fd and fd.reaction or nil
  elseif GetFactionInfoByID then
    local ok, _, _, standing = pcall(GetFactionInfoByID, f)
    reaction = ok and standing or nil
  end
  if not reaction then return false end            -- you haven't met them yet
  return reaction - 1 >= need
end

-- can this character use the item (at `level`)?
function G:CanUse(it, level)
  local cls = Q.player.class
  level = level or Q.player.level
  if not it.loc or it.loc == "" or it.loc == "INVTYPE_BODY" or it.loc == "INVTYPE_TABARD" or it.loc == "INVTYPE_BAG" then
    return false
  end
  if (it.req or 0) > level then return false end
  if not G:RepOK(it.id) then return false end
  local lg = learned()
  if it.class == 4 and it.sub and lg.armor[it.sub] then return false end      -- "wrong armor type for me"
  if it.class == 2 and it.sub then
    if lg.weapon[it.sub] then return false end                                 -- "wrong weapon type for me"
    local allowed = Q.prefs.weapons                                            -- survey: weapon types you use
    if type(allowed) == "table" and next(allowed) and not allowed[it.sub] then return false end
  end
  if it.class == 4 then -- armor
    if it.sub == 6 then return SHIELD[cls] or false end
    if it.sub and it.sub >= 1 and it.sub <= 4 then
      local m = ARMOR_MAX[cls] or { 1, 1 }
      return it.sub <= (level >= 40 and m[2] or m[1])
    end
    return true
  elseif it.class == 2 then
    for _, s in ipairs(WEAPONS[cls] or {}) do if s == it.sub then return true end end
    return false
  end
  return SLOTS[it.loc] ~= nil
end

function G:Score(link, role)
  local it = itemInfo(link)
  if not it then return nil end
  role = role or G:Role()
  local w = G:Weights(role)
  local st = stats(it.link)
  local score = 0
  for k, key in pairs(S) do
    local v = st[key]
    if v and v ~= 0 then
      if k == "DPS" then
        local ranged = it.loc == "INVTYPE_RANGED" or it.loc == "INVTYPE_RANGEDRIGHT" or it.loc == "INVTYPE_THROWN"
        local wand = it.class == 2 and it.sub == 19
        score = score + v * ((wand and w.WDPS) or (ranged and w.RDPS) or w.DPS or 0)
      else
        score = score + v * (w[k] or 0)
      end
    end
  end
  -- wearing a lighter armor type than you could: small penalty (you will outgrow it)
  if it.class == 4 and it.sub and it.sub >= 1 and it.sub <= 4 then
    local m = ARMOR_MAX[Q.player.class] or { 1, 1 }
    local best = Q.player.level >= 40 and m[2] or m[1]
    if it.sub < best then score = score * 0.9 end
  end
  return score, it
end

local function equippedScore(slot, role)
  local link = GetInventoryItemLink("player", slot)
  if not link then return 0, nil end
  return G:Score(link, role) or 0, link
end

-- Upgrade check: returns gain (score points), percent, slot, the item it replaces
function G:Upgrade(item, level)
  local score, it = G:Score(item)
  if not score then return nil end            -- not cached yet
  local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  if id and learned().deny[id] then return 0 end   -- you said it's not for you
  if not G:CanUse(it, level) then return 0 end
  local slots = SLOTS[it.loc]
  if not slots then return 0 end
  local cls = Q.player.class
  if it.loc == "INVTYPE_WEAPON" and not DUAL[cls] then slots = { 16 } end
  if it.loc == "INVTYPE_WEAPONOFFHAND" and not DUAL[cls] then return 0 end
  local base, replaced, bestSlot
  if it.loc == "INVTYPE_2HWEAPON" then
    local mh = equippedScore(16)
    local oh = equippedScore(17)
    base, bestSlot = mh + oh, 16
    replaced = GetInventoryItemLink("player", 16)
  else
    for _, s in ipairs(slots) do
      local sc, l = equippedScore(s)
      -- a two-hander in the main hand counts against a one-hander
      if not base or sc < base then base, replaced, bestSlot = sc, l, s end
    end
  end
  base = base or 0
  local gain = score - base
  if gain <= 0 then return 0 end
  local pct = base > 0 and gain / base * 100 or 100
  return gain, pct, bestSlot, replaced, it
end

-- ------------------------------------------------------------------ quest rewards
local qcache = {}
function G:Reset() wipe(qcache) end

-- best upgrade among a quest's rewards: { item, pct } or false; nil while item data loads
function G:QuestUpgrade(qid)
  local c = qcache[qid]
  if c ~= nil then return c end
  local items = D.rewards and D.rewards[qid]
  if not items then qcache[qid] = false; return false end
  local best, pending = false, false
  local lv = math.max(Q.player.level, (D:Quest(qid) or {})[3] or 1)
  for _, item in ipairs(items) do
    local gain, pct = G:Upgrade(item, lv)
    if gain == nil then pending = true
    elseif gain > 0 and (not best or pct > best.pct) then best = { item = item, pct = pct, gain = gain } end
  end
  if pending and not best then return nil end
  qcache[qid] = best
  return best
end

-- index of the reward to take in the quest frame (GetQuestReward)
function G:BestChoice()
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then return n == 1 and 1 or nil end
  local bestI, bestPct, sellI, sellV = nil, 0, 1, -1
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    if link then
      local gain, pct = G:Upgrade(link)
      if gain and gain > 0 and pct > bestPct then bestI, bestPct = i, pct end
      local it = itemInfo(link)
      if it and it.sell > sellV then sellI, sellV = i, it.sell end
    end
  end
  return bestI or sellI, bestI ~= nil, bestPct
end

-- what class training at a level costs (copper): what your class trainer listed last time, else
-- the usual classic amount (about 3 spells of 6 x level^2 copper each)
function G.TrainingCost(level)
  local t = Q.char and Q.char.trainCost
  if t and t[level] ~= nil then return t[level] end
  if t and Q.char.trainCostAt and level <= (Q.char.trainCostAt or 0) then return 0 end
  -- the trainer listed this level and showed nothing for it: nothing to learn then
  if t and next(t) then
    local top = 0
    for l in pairs(t) do if l > top then top = l end end
    if level < top then return 0 end
  end
  -- every class's training costs, recorded by players at their trainers (ForeverDB train)
  local all = D.db and D.db.train and D.db.train[Q.player.class]
  if all and next(all) then
    G.trainByLevel = G.trainByLevel or {}
    local by = G.trainByLevel[Q.player.class]
    if not by then
      by = {}
      for _, e in pairs(all) do
        local cost, lv = tonumber(e[1]), tonumber(e[2])
        if cost and lv then by[lv] = (by[lv] or 0) + cost end
      end
      G.trainByLevel[Q.player.class] = by
    end
    return by[level] or 0
  end
  return 18 * level * level
end
-- what an item costs at a vendor: recorded prices (Questicus, Command Center), else 4 x its sell price
function G.BuyPrice(item, npc, it)
  for _, src in ipairs({ QuesticusCollect, CommandCenterCollect }) do
    local v = type(src) == "table" and src.vend and src.vend[npc]
    local e = v and v[item]
    if type(e) == "table" and tonumber(e[1]) then return tonumber(e[1]) end
  end
  return (it and it.sell or 0) * 4
end

-- vendor upgrades near a point: list of { item, npc, pct, point }
--  * white (and grey) items only when they're weapons
--  * only when you can buy it and still pay for your next level's class training
function G:VendorUpgrades(level, near, radius)
  local out = {}
  if not D.db.vend then return out end
  radius = radius or 400
  local money = GetMoney and GetMoney() or 0
  local keep = G.TrainingCost(level + 1)
  for item, npcs in pairs(D.db.vend) do
    local rec = D:Item(item)
    local req = rec and rec[3] or 0
    if req <= level and req >= level - 6 and (rec and (rec[2] or 1) >= 1) then
      for _, npc in ipairs(npcs) do
        local pts = D:Points("c" .. npc)
        local p, d = D.Nearest(near, pts)
        if p and d <= radius then
          local gain, pct, _, _, it = G:Upgrade(item, level)
          local plain = it and (it.quality or (rec and rec[2]) or 1) <= 1 and it.class ~= 2
          if gain and gain > 0 and pct >= 5 and it and not plain
            and money - G.BuyPrice(item, npc, it) >= keep then
            out[#out + 1] = { item = item, npc = npc, pct = pct, point = p }
          end
          break
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.pct > b.pct end)
  return out
end

Q:On("PLAYER_EQUIPMENT_CHANGED", function() G:Reset(); Q.Throttle("replan", 1, function() Q:Send("QC_REPLAN") end) end)
Q:On("GET_ITEM_INFO_RECEIVED", function()
  Q.Throttle("iteminfo", 1.5, function() G:Reset(); Q:Send("QC_REPLAN") end)
end)
Q:On("PLAYER_LEVEL_UP", function() G:Reset() end)

-- ------------------------------------------------------------------ why this item / not for me
-- lines explaining an upgrade: how much better, which stats make it, how it fits your priority
function G:Explain(item)
  local out = {}
  local gain, pct, slot, replaced, it = G:Upgrade(item)
  if not gain then return out end
  if gain == 0 then
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
    if id and learned().deny[id] then out[#out + 1] = "You turned it down: " .. learned().deny[id] end
    return out
  end
  local rname = replaced and (Q.GetItemInfo(replaced)) or "nothing"
  out[#out + 1] = ("%+d%% over %s"):format(math.floor(pct + 0.5), rname)
  local role = G:Role()
  local w = G:Weights(role)
  local st = stats(it.link)
  local parts = {}
  for k, key in pairs(S) do
    local v = st[key]
    if v and v ~= 0 and (w[k] or 0) > 0 then parts[#parts + 1] = { k = k, v = v, s = v * w[k] } end
  end
  table.sort(parts, function(a, b) return a.s > b.s end)
  local t = {}
  for i = 1, math.min(3, #parts) do
    local p = parts[i]
    t[#t + 1] = ("%s %s"):format(p.k == "DPS" and ("%.1f"):format(p.v) or ("+" .. p.v), G.STAT_NAMES[p.k] or p.k)
  end
  if #t > 0 then out[#out + 1] = "Mostly from " .. table.concat(t, ", ") .. " (" .. (G.ROLE_NAMES[role] or role) .. ")" end
  local prio = Q.prefs.statPrio
  if type(prio) == "table" and parts[1] then
    for i, k in ipairs(prio) do
      if k == parts[1].k then out[#out + 1] = ("Matches your stat priority: %s is your #%d"):format(G.STAT_NAMES[k] or k, i) end
    end
  end
  return out
end

G.DENY_REASONS = {
  { "type", "Wrong armor / weapon type for me" },
  { "stats", "Wrong stats for me" },
  { "keep", "I'm keeping what I have" },
  { "trip", "Not worth going for" },
}
-- turn an item down; Questicus learns from why
function G:Deny(item, reason)
  local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  if not id then return end
  local lg = learned()
  local label
  for _, r in ipairs(G.DENY_REASONS) do if r[1] == reason then label = r[2] end end
  lg.deny[id] = label or reason
  local it = itemInfo(id)
  if it and reason == "type" then
    if it.class == 4 and it.sub then lg.armor[it.sub] = true end
    if it.class == 2 and it.sub then lg.weapon[it.sub] = true end
  elseif it and reason == "stats" then
    -- the two stats that made it look good count less from now on
    local w = G:Weights(G:Role())
    local st = stats(it.link)
    local parts = {}
    for k, key in pairs(S) do
      if st[key] and (w[k] or 0) > 0 and k ~= "DPS" and k ~= "ARMOR" then parts[#parts + 1] = { k = k, s = st[key] * w[k] } end
    end
    table.sort(parts, function(a, b) return a.s > b.s end)
    for i = 1, math.min(2, #parts) do
      local k = parts[i].k
      lg.stat[k] = math.max(0.3, (lg.stat[k] or 1) * 0.7)
    end
  end
  G:Reset()
  Q:Send("QC_REPLAN")
  return lg.deny[id]
end
function G:Undeny(id)
  learned().deny[id] = nil
  G:Reset()
  Q:Send("QC_REPLAN")
end
Q:Command("gear", "gear you turned down (/qc gear reset forgets them)", function(arg)
  local lg = learned()
  if arg == "reset" then
    Q.char.gear = nil
    G:Reset(); Q:Send("QC_REPLAN")
    Q:Print("gear answers forgotten")
    return
  end
  local n = 0
  for id, why in pairs(lg.deny) do n = n + 1; Q:Print((Q.GetItemInfo(id) or ("item " .. id)) .. ": " .. why) end
  for sub in pairs(lg.armor) do Q:Print("never: " .. (G.ARMOR_NAMES[sub] or sub)) end
  for sub in pairs(lg.weapon) do Q:Print("never: " .. (G.WEAPON_NAMES[sub] or sub)) end
  for k, f in pairs(lg.stat) do Q:Print(("%s counts x%.2f"):format(G.STAT_NAMES[k] or k, f)) end
  if n == 0 and not next(lg.armor) and not next(lg.weapon) then Q:Print("nothing turned down yet") end
end)
function G.ClassWeapons() return WEAPONS[Q.player.class] or {} end
