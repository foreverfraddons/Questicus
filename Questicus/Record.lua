-- Questicus recorder, part 2: everything else the game shows while you play that ForeverDB (and so
-- Questicus' routes) can use. Saved in QuesticusCollect (account-wide) next to Collect.lua's tables,
-- sent with your recordings (the sync), merged by forever-db's tools/build.py.
--   gold    [npc]  = { n = corpses looted, c = copper total, lo, hi }      money per kill
--   skinl   [npc]  = { n = skinned, i = { [item] = count } }              skinning loot (not kill loot)
--   fishl   [uiMap]= { n = catches, i = { [item] = count } }               fishing loot per zone
--   gathl   ["o:id"] = { n, i }                                            herb / ore / chest loot (when Command Center isn't recording loot)
--   taxi    [npc]  = { t, at = node name, nodes = { [name] = { cost, x, y } } }   flight masters, their routes and prices
--   trn     [npc]  = { t, s = { [name] = { cost, level, skill, skillRank, sub } } } what trainers teach
--   qinfo   [quest]= { o = objectives text, xp, m = money, grp, minlv, item = started by item }  quest details
--   qoff    [npc]  = { [quest] = lowest level it was offered at }          quests an NPC really offers
--   qmiss   [quest]= { [npc] = level }                                     quests the database says the NPC gives, but it didn't
--   qrep    [quest]= { [faction] = gain }                                  reputation for handing a quest in
--   area    [uiMap]= { [subzone] = { x, y, ... } }                         subzone names over the map
--   enc     [encounterID] = { name, instance, map }                        dungeon / raid encounters
--   rare    [npc]  = { { t, map, x, y }, ... }                             rares seen and when (respawn timers)
--   oskill  [object]= { profession, level }                                skill an herb / vein / chest needs
--   itemx   [item] = { name, quality, ilvl, reqLevel, class, subclass, equipLoc, sell, stack }  items ForeverDB doesn't have
--   ctype   [npc]  = { creature type, family }
-- Also, when Command Center isn't there to do it: loot, vendors, npc names / levels, object names,
-- item names, spots (its CommandCenterCollect layout, so the build merges both the same way).
-- Never: anything about other players, chat, or your settings. Off with Options > Advanced >
-- "Help fill the database" (the same switch as Collect.lua).
local Q = Questicus
local D, QS = Q.Data, Q.Quests
local S = Q.Secret
local R = {}
Q.Record = R

local SPOT_NEAR, SPOT_MAX = 15, 40
local KEYS = { "gold", "skinl", "fishl", "gathl", "taxi", "trn", "qinfo", "qoff", "qmiss", "qrep", "area", "enc", "rare",
  "oskill", "itemx", "ctype", "loot", "vend", "npc", "obj", "sp", "item", "recentR" }

local function on() return Q.db and Q.db.collect ~= false end
local function db()
  QuesticusCollect = type(QuesticusCollect) == "table" and QuesticusCollect or {}
  local c = QuesticusCollect
  for _, k in ipairs(KEYS) do if type(c[k]) ~= "table" then c[k] = {} end end
  return c
end
R.db = db
local function clean(v) if v == nil or S(v) then return nil end return v end

-- Command Center's Collector records loot / vendors / npcs itself: counts aren't doubled
local function ccRecords()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("CommandCenter")
  if loaded == nil and IsAddOnLoaded then loaded = IsAddOnLoaded("CommandCenter") end
  return loaded and type(CommandCenterCollect) == "table"
end
R.ccRecords = ccRecords

local function here()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  m = ok and clean(m)
  if not m then return end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or not pos then return m end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x or S(x) or x <= 0 or y <= 0 then return m end
  return m, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end
R.here = here

local function addSpot(list, x, y, max)
  if #list >= (max or SPOT_MAX) * 2 then return false end
  for j = 1, #list - 1, 2 do
    if math.abs(list[j] - x) <= SPOT_NEAR and math.abs(list[j + 1] - y) <= SPOT_NEAR then return false end
  end
  list[#list + 1], list[#list + 2] = x, y
  return true
end
local function noteSpot(key)
  local m, x, y = here()
  if not (m and x) then return end
  local sp = db().sp
  sp[key] = sp[key] or {}
  sp[key][m] = sp[key][m] or {}
  addSpot(sp[key][m], x, y)
end

local function kindId(guid)
  guid = clean(guid)
  local kind, id = Q.ParseGUID(guid)
  if not id then return end
  if kind == "Creature" or kind == "Vehicle" then return "c", id end
  if kind == "GameObject" then return "o", id end
  if kind == "Item" then return "i", nil end
end

-- ------------------------------------------------------------------ items
local pendingItems = {}
local function itemDetails(id)
  if not id or (D:Item(id) and db().itemx[id] == nil and D:Item(id)[1]) then return end   -- ForeverDB has it
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return end
  local ok, name, _, q, ilvl, req, _, _, stack, loc, _, sell, cls, sub = pcall(getInfo, id)
  if not ok or not name or S(name) then pendingItems[id] = true return end
  db().itemx[id] = { name, clean(q), clean(ilvl), clean(req), clean(cls), clean(sub), clean(loc), clean(sell), clean(stack) }
end
Q:On("GET_ITEM_INFO_RECEIVED", function(id)
  if id and pendingItems[id] and on() then pendingItems[id] = nil; pcall(itemDetails, id) end
end)
local function noteItem(link)
  link = clean(link)
  if type(link) ~= "string" then return end
  local id = tonumber(link:match("item:(%d+)"))
  if not id then return end
  if not ccRecords() then
    local name = link:match("%[(.-)%]")
    if name and name ~= "" then
      local e = db().item[id]
      if not e or e[1] ~= name then db().item[id] = { name, e and e[2] } end
    end
  end
  pcall(itemDetails, id)
  return id
end
R.noteItem = noteItem

-- ------------------------------------------------------------------ creatures
local CLS = { worldboss = 3, rareelite = 2, elite = 1, rare = 4, normal = 0, trivial = 0, minus = 0 }
local function noteUnit(unit)
  if not (UnitExists and UnitExists(unit)) or (UnitIsPlayer and UnitIsPlayer(unit)) then return end
  local kind, id = kindId(UnitGUID(unit))
  if kind ~= "c" then return end
  local c = db()
  local okT, ct = pcall(UnitCreatureType, unit)
  local okF, fam = pcall(UnitCreatureFamily or function() end, unit)
  ct, fam = okT and clean(ct) or nil, okF and clean(fam) or nil
  if ct then c.ctype[id] = { ct, fam } end
  local cls = clean(UnitClassification and UnitClassification(unit))
  -- rares: when and where seen (one sighting per 10 minutes)
  if cls == "rare" or cls == "rareelite" then
    local m, x, y = here()
    if m and x then
      local l = c.rare[id] or {}
      local last = l[#l]
      if not last or time() - (last[1] or 0) > 600 then
        l[#l + 1] = { time(), m, x, y }
        while #l > 50 do table.remove(l, 1) end
        c.rare[id] = l
      end
    end
  end
  if ccRecords() then return id end
  local name, lvl = clean(UnitName(unit)), clean(UnitLevel(unit))
  if not name or name == "" or name == UNKNOWNOBJECT then return id end
  local e = c.npc[id] or {}
  e[1] = name
  if lvl and lvl > 0 then
    e[2] = (e[2] and math.min(e[2], lvl)) or lvl
    e[3] = (e[3] and math.max(e[3], lvl)) or lvl
  end
  if cls and CLS[cls] then e[4] = CLS[cls] end
  local r = clean(UnitReaction and UnitReaction(unit, "player")); if r then e[5] = r end
  c.npc[id] = e
  return id
end
R.noteUnit = noteUnit

-- ------------------------------------------------------------------ loot: money, skinning, fishing, gathering
local lastSpell, lastSpellAt = nil, 0
local SKIN = { Skinning = "skin", ["Herb Gathering"] = "herb", Mining = "mine", Disenchant = "dis", Fishing = "fish" }
Q:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not spellID or S(spellID) then return end
  local nm = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
  if nm and SKIN[nm] then lastSpell, lastSpellAt = SKIN[nm], GetTime() end
end)
local lastUsedItem, lastUsedAt
if C_Container and C_Container.UseContainerItem then
  hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    local ok, i = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(i) == "table" and clean(i.itemID) then lastUsedItem, lastUsedAt = i.itemID, GetTime() end
  end)
end

local function seen(guid)
  local c = db()
  local now = time()
  if c.recentR[guid] and now - c.recentR[guid] < 900 then return true end
  c.recentR[guid] = now
  return false
end
local function prune()
  local c = db()
  local now = time()
  for g, t in pairs(c.recentR) do if now - t >= 900 then c.recentR[g] = nil end end
end

local function moneyOf(slot)
  -- the copper in a money slot, from its text ("1 Silver 23 Copper")
  local ok, _, txt = pcall(GetLootSlotInfo, slot)
  txt = ok and clean(txt) or nil
  if type(txt) ~= "string" then return end
  local function n(word) return tonumber(txt:match("(%d+)%s*" .. word)) or 0 end
  local g = n("Gold") * 10000 + n("Silver") * 100 + n("Copper")
  return g > 0 and g or nil
end

local function onLoot()
  if not on() or not GetNumLootItems then return end
  local n = GetNumLootItems() or 0
  if n == 0 then return end
  local c = db()
  local fishing = IsFishingLoot and IsFishingLoot()
  local spell = (GetTime() - lastSpellAt < 4) and lastSpell or nil
  local m = here()
  local corpses, copper, items = {}, {}, {}   -- per source guid
  for slot = 1, n do
    local link = GetLootSlotLink and clean(GetLootSlotLink(slot))
    local id = noteItem(link)
    local typ = GetLootSlotType and GetLootSlotType(slot)
    local okS, a1, a2, a3, a4, a5, a6 = pcall(GetLootSourceInfo, slot)
    local src = okS and { a1, a2, a3, a4, a5, a6 } or {}
    if fishing then
      if id and m then
        local f = c.fishl[m] or { n = 0, i = {} }
        local okQ, _, _, qty = pcall(GetLootSlotInfo, slot)
        f.i[id] = (f.i[id] or 0) + (okQ and clean(qty) or 1)
        c.fishl[m] = f
      end
    else
      for k = 1, #src, 2 do
        local guid, qty = clean(src[k]), clean(src[k + 1])
        if guid then
          corpses[guid] = true
          if typ == 2 or (LOOT_SLOT_MONEY and typ == LOOT_SLOT_MONEY) then
            copper[guid] = (copper[guid] or 0) + (tonumber(qty) or moneyOf(slot) or 0)
          elseif id then
            items[guid] = items[guid] or {}
            items[guid][id] = (items[guid][id] or 0) + (tonumber(qty) or 1)
          end
        end
      end
    end
  end
  if fishing then
    if m then c.fishl[m] = c.fishl[m] or { n = 0, i = {} }; c.fishl[m].n = c.fishl[m].n + 1 end
    return
  end
  for guid in pairs(corpses) do
    local kind, sid = kindId(guid)
    if kind and sid and not seen(guid .. (spell or "")) then
      if kind == "c" and spell == "skin" then
        local e = c.skinl[sid] or { n = 0, i = {} }
        e.n = e.n + 1
        for it, q in pairs(items[guid] or {}) do e.i[it] = (e.i[it] or 0) + q end
        c.skinl[sid] = e
      elseif kind == "c" then
        local g = c.gold[sid] or { n = 0, c = 0 }
        g.n = g.n + 1
        local cp = copper[guid]
        if cp and cp > 0 then
          g.c = g.c + cp
          g.lo = g.lo and math.min(g.lo, cp) or cp
          g.hi = g.hi and math.max(g.hi, cp) or cp
        end
        c.gold[sid] = g
        if not ccRecords() then
          local e = c.loot["c:" .. sid] or { n = 0, i = {} }
          e.n = e.n + 1
          for it, q in pairs(items[guid] or {}) do e.i[it] = (e.i[it] or 0) + q end
          c.loot["c:" .. sid] = e
        end
        noteSpot("c:" .. sid)
      elseif kind == "o" then
        if not ccRecords() then
          local key = "o:" .. sid
          local e = c.loot[key] or { n = 0, i = {} }
          e.n = e.n + 1
          for it, q in pairs(items[guid] or {}) do e.i[it] = (e.i[it] or 0) + q end
          c.loot[key] = e
          local nm = GameTooltipTextLeft1 and GameTooltip:IsShown() and clean(GameTooltipTextLeft1:GetText())
          if nm and nm ~= "" then c.obj[sid] = { nm } end
        end
        noteSpot("o:" .. sid)
      end
    end
  end
end
R.onLoot = onLoot
local lootDone = false   -- one read per loot window (LOOT_OPENED can come twice)
Q:On("LOOT_OPENED", function() if lootDone then return end lootDone = true; pcall(onLoot) end)
Q:On("LOOT_CLOSED", function() lootDone = false end)
Q:On("PLAYER_ENTERING_WORLD", function() lootDone = false end)

-- ------------------------------------------------------------------ flight masters
local function npcId(unit)
  local kind, id = kindId(UnitGUID and UnitGUID(unit or "npc"))
  if kind == "c" then return id end
end
Q:On("TAXIMAP_OPENED", function()
  if not on() or not NumTaxiNodes then return end
  pcall(function()
    local id = npcId("npc")
    if not id then return end
    noteUnit("npc"); noteSpot("c:" .. id)
    local e = { t = time(), nodes = {} }
    for i = 1, NumTaxiNodes() do
      local name = clean(TaxiNodeName(i))
      local typ = TaxiNodeGetType and clean(TaxiNodeGetType(i))
      if name then
        if typ == "CURRENT" then e.at = name end
        local x, y = TaxiNodePosition(i)
        e.nodes[name] = { clean(TaxiNodeCost and TaxiNodeCost(i)) or 0, x and math.floor(x * 1000 + 0.5), y and math.floor(y * 1000 + 0.5), typ }
      end
    end
    db().taxi[id] = e
  end)
end)

-- ------------------------------------------------------------------ trainers
Q:On("TRAINER_SHOW", function()
  if not on() or not GetNumTrainerServices then return end
  Q.After(0.3, function()
    pcall(function()
      local id = npcId("npc")
      if not id then return end
      noteUnit("npc"); noteSpot("c:" .. id)
      local list = {}
      for i = 1, GetNumTrainerServices() do
        local name, sub = GetTrainerServiceInfo(i)
        name = clean(name)
        if name then
          local okC, cost = pcall(GetTrainerServiceCost, i)
          local okL, lvl = pcall(GetTrainerServiceLevelReq or function() end, i)
          local okK, skill, rank = pcall(GetTrainerServiceSkillReq or function() end, i)
          list[name .. (sub and sub ~= "" and (" (" .. sub .. ")") or "")] = { okC and clean(cost) or nil, okL and clean(lvl) or nil,
            okK and clean(skill) or nil, okK and clean(rank) or nil }
        end
      end
      if next(list) then db().trn[id] = { t = time(), s = list } end
    end)
  end)
end)

-- ------------------------------------------------------------------ quests: details, offers, missing ones, item starts, reputation
local function lvl() return UnitLevel and clean(UnitLevel("player")) or 0 end
Q:On("QUEST_DETAIL", function()
  if not on() then return end
  pcall(function()
    local qid = clean(GetQuestID and GetQuestID())
    if not qid or qid == 0 then return end
    local e = db().qinfo[qid] or {}
    local o = clean(GetObjectiveText and GetObjectiveText())
    if o and o ~= "" then e.o = o end
    local xp = clean(GetRewardXP and GetRewardXP()); if xp and xp > 0 then e.xp = xp end
    local mo = clean(GetRewardMoney and GetRewardMoney()); if mo and mo > 0 then e.m = mo end
    local g = clean(GetSuggestedGroupNum and GetSuggestedGroupNum()); if g and g > 0 then e.grp = g end
    local l = lvl()
    if l > 0 then e.minlv = e.minlv and math.min(e.minlv, l) or l end
    -- no one to talk to, and an item just used: the item starts it
    if not (UnitExists and (UnitExists("questnpc") or UnitExists("npc"))) and lastUsedItem and GetTime() - (lastUsedAt or 0) < 5 then
      e.item = lastUsedItem
    end
    db().qinfo[qid] = e
  end)
end)

local function offered(npc, list)
  local c = db()
  local l = lvl()
  c.qoff[npc] = c.qoff[npc] or {}
  local set = {}
  for _, q in ipairs(list) do
    local id = clean(q.questID)
    if id then
      set[id] = true
      local cur = c.qoff[npc][id]
      c.qoff[npc][id] = (cur and l > 0) and math.min(cur, l) or (l > 0 and l or cur or 0)
    end
  end
  -- the database's quests for this NPC that it didn't offer, though it says you could take them
  -- now (every one, not just the route's: Quests.lua's qna has those)
  if QS and QS.pool and QS.Available then
    local key = Q.UnitKey and Q.UnitKey("npc")
    for _, qid in ipairs(QS.pool) do
      if not set[qid] and QS:Available(qid) then
        local info = QS:Info(qid)
        for _, k in ipairs(info and info.givers or {}) do
          if k == key then
            c.qmiss[qid] = c.qmiss[qid] or {}
            c.qmiss[qid][npc] = l
            break
          end
        end
      end
    end
  end
end
Q:On("GOSSIP_SHOW", function()
  if not on() then return end
  pcall(function()
    local id = npcId("npc")
    if not id then return end
    noteUnit("npc"); noteSpot("c:" .. id)
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
      offered(id, C_GossipInfo.GetAvailableQuests() or {})
    end
  end)
end)

-- reputation for a quest: the faction lines right after handing it in
local lastTurnIn, lastTurnInAt
Q:On("QUEST_TURNED_IN", function(qid) lastTurnIn, lastTurnInAt = qid, GetTime() end)
local REP = FACTION_STANDING_INCREASED and FACTION_STANDING_INCREASED:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
Q:On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
  if not (on() and REP and lastTurnIn and GetTime() - (lastTurnInAt or 0) < 3) or S(msg) then return end
  local fac, amt = msg:match(REP)
  if fac and tonumber(amt) then
    local c = db()
    c.qrep[lastTurnIn] = c.qrep[lastTurnIn] or {}
    c.qrep[lastTurnIn][fac] = tonumber(amt)
  end
end)

-- ------------------------------------------------------------------ places: subzone names, encounters
local lastArea, lastAreaAt = nil, 0
local function noteArea()
  if not on() then return end
  local sub = clean(GetSubZoneText and GetSubZoneText())
  if not sub or sub == "" then return end
  local m, x, y = here()
  if not (m and x) then return end
  local c = db()
  c.area[m] = c.area[m] or {}
  c.area[m][sub] = c.area[m][sub] or {}
  addSpot(c.area[m][sub], x, y, 60)
end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
  Q:On(ev, function() pcall(noteArea) end)
end
Q:On("ENCOUNTER_START", function(eid, name)
  if not on() or S(eid) or not eid then return end
  local _, _, _, _, _, _, _, inst = GetInstanceInfo()
  db().enc[eid] = { clean(name), clean(inst), (here()) }
end)

-- ------------------------------------------------------------------ creatures you meet, objects in front of you
Q:On("PLAYER_TARGET_CHANGED", function() if on() then pcall(noteUnit, "target") end end)
local lastMo = 0
Q:On("UPDATE_MOUSEOVER_UNIT", function()
  if not on() or GetTime() - lastMo < 0.25 then return end
  lastMo = GetTime()
  pcall(noteUnit, "mouseover")
end)
Q:On("NAME_PLATE_UNIT_ADDED", function(unit)
  if not on() or type(unit) ~= "string" or S(unit) then return end
  -- (rares and creature types only: a nameplate is too far away for a spot)
  pcall(function()
    local cls = clean(UnitClassification and UnitClassification(unit))
    if cls == "rare" or cls == "rareelite" then noteUnit(unit) end
  end)
end)

-- the soft-targeted object (Highlights finds it): its spot, name and the skill it needs
local objAcc = 0
local objFrame = CreateFrame("Frame")
objFrame:SetScript("OnUpdate", function(_, el)
  objAcc = objAcc + el
  if objAcc < 1 then return end
  objAcc = 0
  if not on() or not (Q.Glow and Q.Glow.Find) then return end
  pcall(function()
    if not Q.Glow.Find() then return end
    local unit = Q.Glow.Unit and Q.Glow.Unit() or "softinteract"
    local kind, oid = kindId(UnitGUID and UnitGUID(unit))
    if kind ~= "o" then return end
    local inR = UnitIsInInteractRange and clean(UnitIsInInteractRange(unit))
    if inR then noteSpot("o:" .. oid) end              -- within reach: close enough for a spot
    local c = db()
    local name = clean(UnitName(unit))
    if name and name ~= "" and not ccRecords() then c.obj[oid] = { name } end
    if not c.oskill[oid] and C_TooltipInfo and C_TooltipInfo.GetUnit then
      local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
      for _, l in ipairs(ok and data and data.lines or {}) do
        local t = clean(l.leftText)
        local prof, need = type(t) == "string" and t:match("^Requires ([%a ]+) %((%d+)%)")
        if prof then c.oskill[oid] = { prof, tonumber(need) } break end
      end
    end
  end)
end)

-- ------------------------------------------------------------------ vendors (when Command Center isn't recording them)
local function onMerchant()
  if not on() or ccRecords() then return end
  local id = npcId("npc")
  if not id then return end
  noteUnit("npc"); noteSpot("c:" .. id)
  local list = {}
  for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
    local item = noteItem(GetMerchantItemLink and GetMerchantItemLink(i))
    if item then
      local price, stack, avail
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, t = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(t) == "table" then price, stack, avail = t.price, t.stackCount, t.numAvailable end
      elseif GetMerchantItemInfo then
        local _, _, p, s, a = GetMerchantItemInfo(i)
        price, stack, avail = p, s, a
      end
      list[item] = { clean(price) or 0, clean(stack) or 1, (clean(avail) or -1) > 0 and avail or nil }
    end
  end
  if next(list) then list.t = time(); db().vend[id] = list end
end
Q:On("MERCHANT_SHOW", function() Q.After(0.3, function() pcall(onMerchant) end) end)

Q:On("PLAYER_LOGIN", function()
  local c = db()
  local v, b = GetBuildInfo and GetBuildInfo()
  c.build = tostring(v or "") .. "-" .. tostring(b or "")
  prune()
end)

-- how much there is
function R.Counts()
  local c = db()
  local out = {}
  for _, k in ipairs(KEYS) do
    if k ~= "recentR" then
      local n = 0
      for _ in pairs(c[k]) do n = n + 1 end
      out[k] = n
    end
  end
  return out
end
Q:Command("recorded", "what Questicus has recorded for the database", function()
  local n = R.Counts()
  local parts = {}
  for _, k in ipairs(KEYS) do if n[k] and n[k] > 0 then parts[#parts + 1] = k .. " " .. n[k] end end
  Q:Print("recorded: " .. (#parts > 0 and table.concat(parts, ", ") or "nothing yet") ..
    (ccRecords() and " (loot, vendors and npcs: Command Center records those)" or ""))
end)
