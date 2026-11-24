-- Questicus quest state: which quests this character can do, what is in the log, what is done,
-- and rough XP numbers for planning.
local Q = Questicus
local QS = {}
Q.Quests = QS
local D = Q.Data

QS.done = {}      -- [questID] = true (turned in)
QS.log = {}       -- [questID] = { title, level, complete, failed, objectives = {...} }
QS.logCount = 0
-- who can take a quest, where the data is wrong (until ForeverDB has the fix): 0 = everyone
QS.RACE_FIX = {
}

-- zoneOrSort values (QuestieDB) for quest categories
local CLASS_SORT = { [-61] = "WARLOCK", [-81] = "WARRIOR", [-82] = "SHAMAN", [-141] = "PALADIN", [-161] = "MAGE",
  [-162] = "ROGUE", [-261] = "HUNTER", [-262] = "PRIEST", [-263] = "DRUID" }
local PROF_SORT = { [-24] = 1, [-101] = 1, [-121] = 1, [-181] = 1, [-182] = 1, [-201] = 1, [-264] = 1, [-304] = 1,
  [-324] = 1, [-371] = 1, [-373] = 1 }
local SEASONAL_SORT = { [-22] = 1, [-284] = 1, [-364] = 1, [-366] = 1, [-367] = 1, [-368] = 1, [-369] = 1, [-370] = 1,
  [-374] = 1, [-375] = 1, [-376] = 1, [-1001] = 1, [-1002] = 1, [-1003] = 1, [-1005] = 1 }
local SKIP_SORT = { [-25] = 1, [-344] = 1, [-365] = 1, [-241] = 1 }   -- battlegrounds, legendary, AQ war, tournament
-- dungeon / raid areas
local DUNGEON = { [1581] = 1, [717] = 1, [718] = 1, [719] = 1, [721] = 1, [491] = 1, [722] = 1, [796] = 1, [1337] = 1,
  [2100] = 1, [1176] = 1, [1417] = 1, [1584] = 1, [1583] = 1, [2557] = 1, [2017] = 1, [2057] = 1, [209] = 1, [2437] = 1 }
local RAID = { [2717] = 1, [2677] = 1, [3428] = 1, [3429] = 1, [1977] = 1, [2159] = 1, [3456] = 1 }
QS.DUNGEON, QS.RAID = DUNGEON, RAID

-- classic XP needed for each level (1 -> 2 is [1])
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
  17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500,
  58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100,
  135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
function QS.XPToLevel(lv) return XP_TO_LEVEL[lv] or 220000 end

-- estimated quest XP (no XP data in the databases): classic curve with the gray-quest penalty
function QS.QuestXP(qlvl, plvl)
  qlvl = math.max(1, qlvl or plvl)
  local xp = 45 * qlvl + 1.2 * qlvl * qlvl
  local diff = plvl - qlvl
  if diff >= 10 then xp = xp * 0.1
  elseif diff > 5 then xp = xp * (1 - 0.2 * (diff - 5)) end
  return xp
end
-- real rewards from ForeverDB (table qrw: money, full XP, choice items, fixed items); XP gets the
-- same grey-quest penalty the game applies. Falls back to the estimate when the quest has no data.
local function penalty(qlvl, plvl)
  local diff = plvl - (qlvl or plvl)
  if diff >= 10 then return 0.1 elseif diff > 5 then return 1 - 0.2 * (diff - 5) end
  return 1
end
-- Rewards: what WoW Forever itself says always wins (Record.lua: the quest log right now, the quest
-- windows and turn-ins recorded on this account, everyone's recordings in ForeverDB's qinfo). ForeverDB's
-- base table (qrw, classic dumps) only fills what the game hasn't shown yet.
local rewCache, rewVer = {}, -1
function QS.Rewards(id)
  local R = Q.Record
  local base = D.db and D.db.qrw and D.db.qrw[id]
  if not R then return base end
  if rewVer ~= R.ver then wipe(rewCache); rewVer = R.ver end
  local hit = rewCache[id]
  if hit ~= nil then return hit or nil end
  local ch, rw = R.GameItems(id)
  local money = R.GameMoney(id)
  local full = R.GameXP(id, 0)              -- level 0: never live, the full value (no grey penalty)
  local r = base
  if ch or rw or money or full then
    r = { money or (base and base[1]) or 0, full or (base and base[2]) or 0, ch or (base and base[3]),
      rw or (base and base[4]) }
    if r[3] and #r[3] == 0 then r[3] = nil end
    if r[4] and #r[4] == 0 then r[4] = nil end
  end
  rewCache[id] = r or false
  return r
end
-- XP for a player of level plvl. Returns xp, known (real data, not the estimate), fromGame
function QS.RewardXP(id, plvl)
  local R = Q.Record
  local g = R and R.GameXP(id, plvl)
  if g then return g, true, true end
  local q = D:Quest(id)
  local base = D.db and D.db.qrw and D.db.qrw[id]
  if base and base[2] and base[2] > 0 then return math.floor(base[2] * penalty(q and q[2], plvl)), true end
  -- what someone really got for it at another level (your own turn-ins, any character)
  local rec = Q.Learn and Q.Learn:RecordedXP(id, plvl)
  if rec then return rec, true, true end
  return math.floor(QS.QuestXP(q and q[2] or plvl, plvl)), false
end
function QS.RewardMoney(id)
  local R = Q.Record
  local g = R and R.GameMoney(id)
  if g then return g end
  local base = D.db and D.db.qrw and D.db.qrw[id]
  return base and base[1] or 0
end

-- highest level that is grey (no XP to speak of) for a player of level plvl
function QS.GreyLevel(plvl)
  if plvl <= 5 then return 0 end
  if plvl <= 39 then return plvl - 5 - math.floor(plvl / 10) end
  if plvl <= 59 then return plvl - 1 - math.floor(plvl / 5) end
  return plvl - 9
end

-- XP for one kill of a mob of level mlvl
function QS.KillXP(mlvl, plvl)
  local base = plvl * 5 + 45
  local d = (mlvl or plvl) - plvl
  if d >= 0 then return base * (1 + 0.05 * math.min(d, 4)) end
  local gray = plvl <= 5 and 0 or (plvl <= 39 and plvl - 5 - math.floor(plvl / 10) or plvl - 1 - math.floor(plvl / 5))
  if mlvl <= gray then return 0 end
  return base * (1 + d / 20)
end

-- ------------------------------------------------------------------ completed / log
local function isDoneAPI(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
  if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
end

function QS:ReadDone()
  local t = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do t[id] = true end
  elseif GetQuestsCompleted then
    GetQuestsCompleted(t)
  end
  QS.done = t
end

function QS:IsDone(id) return QS.done[id] or false end

function QS:ReadLog()
  local log, n = {}, 0
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID and info.questID > 0 then
        local id = info.questID
        local e = { title = info.title, level = info.level, index = i }
        e.complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
        e.failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) or false
        e.objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {}
        log[id] = e
        n = n + 1
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, (GetNumQuestLogEntries()) do
      local title, level, _, header, _, complete, _, id = GetQuestLogTitle(i)
      if not header and id then
        local e = { title = title, level = level, index = i, complete = complete == 1, failed = complete == -1, objectives = {} }
        for o = 1, (GetNumQuestLeaderBoards(i) or 0) do
          local text, typ, finished = GetQuestLogLeaderBoard(o, i)
          e.objectives[o] = { text = text, type = typ, finished = finished }
        end
        log[id] = e
        n = n + 1
      end
    end
  end
  QS.log, QS.logCount = log, n
end

function QS.MaxLog()
  if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then return C_QuestLog.GetMaxNumQuestsCanAccept() end
  return MAX_QUESTLOG_QUESTS or 20
end

-- ------------------------------------------------------------------ static filters
-- Quests this character could ever take with the chosen preferences: race, class, faction of the
-- quest giver, categories. Built once per login / survey change.
local function giverOK(key, fac)
  if key:sub(1, 1) ~= "c" then return true end
  local f = D:Faction(tonumber(key:sub(2)))
  return not f or f == "AH" or f == fac
end

function QS:Info(id)
  local c = QS.cache[id]
  if c ~= nil then return c or nil end
  QS.cache[id] = false
  local q = D:Quest(id)
  if not q then return end
  local x = D:QuestExtra(id) or {}
  local p, pr = Q.player, Q.prefs
  local info = { id = id, title = q[1] or ("Quest " .. id), level = q[2] or q[3] or 1, min = q[3] or 1, x = x }
  -- race / class
  local races = QS.RACE_FIX[id]
  if races == nil then races = x[1] end
  if races ~= 0 and not Q.HasBit(races, p.race) then return end
  if not Q.HasBit(x[2], p.classID) then return end
  local sort = x[11]
  if sort and sort < 0 then
    if CLASS_SORT[sort] then
      if CLASS_SORT[sort] ~= p.class or not pr.classQuests then return end
      info.class = true
    elseif PROF_SORT[sort] then
      if not pr.profQuests then return end
      info.prof = true
    elseif SEASONAL_SORT[sort] then
      if not pr.seasonal then return end
      info.seasonal = true
    elseif SKIP_SORT[sort] then
      return
    end
  elseif sort and (RAID[sort] or D.RAID_AREA[sort]) then
    return
  elseif sort and (DUNGEON[sort] or D:Dungeon(sort)) then
    info.dungeon = sort                  -- quest of a dungeon (its area id); routing decides below
  end
  if x[14] and not pr.profQuests then return end                   -- needs a profession skill
  if x[13] and x[13] % 2 == 1 then                                   -- repeatable
    if not pr.repeatable then return end
    info.repeatable = true
  end
  if x[6] and pr.breadcrumbs == "skip" then return end
  -- givers the player can talk to
  local givers = {}
  for _, k in ipairs(D:Givers(id) or {}) do if giverOK(k, p.faction) then givers[#givers + 1] = k end end
  info.startItem = D.startItem[id]
  if #givers == 0 and not info.startItem then return end
  info.givers = givers
  local enders = {}
  for _, k in ipairs(D:Enders(id) or {}) do if giverOK(k, p.faction) then enders[#enders + 1] = k end end
  info.enders = enders
  if #enders == 0 then return end
  -- elite objectives = group quest
  for _, c in ipairs(x[8] or {}) do
    local n = D:NPC(c)
    if n and (n[5] or 0) >= 1 then info.elite = true end
  end
  -- elite quests stay in the pool: Planner.Excluded leaves them out for "solo only" (dungeon mode
  -- still needs them)
  info.breadcrumbFor = x[6]
  info.rep = x[15] ~= nil
  QS.cache[id] = info
  return info
end

-- the whole chain a quest is part of, in order (earlier ones via prerequisites, later via "next")
function QS:Chain(id)
  local back, seen = {}, { [id] = true }
  local cur = id
  for _ = 1, 25 do
    local x = D:QuestExtra(cur) or {}
    local pre = (x[3] and x[3][1]) or (x[4] and x[4][1]) or (QS.prevOf and QS.prevOf[cur] and QS.prevOf[cur][1])
    if not pre or seen[pre] or not QS:CanEverTake(pre) then break end   -- (the other faction's part isn't yours)
    seen[pre] = true
    table.insert(back, 1, pre)
    cur = pre
  end
  local out = back
  out[#out + 1] = id
  cur = id
  for _ = 1, 25 do
    local x = D:QuestExtra(cur) or {}
    local nx = x[7]
    if not nx or seen[nx] or not D:Quest(nx) or not QS:CanEverTake(nx) then break end
    seen[nx] = true
    out[#out + 1] = nx
    cur = nx
  end
  return out
end
local function money(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "g" end
  if s > 0 then t[#t + 1] = s .. "s" end
  if k > 0 or #t == 0 then t[#t + 1] = k .. "c" end
  return table.concat(t, " ")
end
QS.MoneyText = money
-- for any quest tooltip: what the quest says to do (the line under its title in the quest log)
-- and its quest id, added to the lines `t` (returns t)
function QS:TipExtra(id, t, noId, noHow)
  t = t or {}
  if not id then return t end
  local how = not noHow and Q.Guide and Q.Guide.HowText and Q.Guide.HowText(id)
  if how then t[#t + 1] = "|cffffd100Objective:|r " .. how end
  if not noId then t[#t + 1] = "|cff808080Quest ID: " .. id .. "|r" end
  return t
end
-- the quest in your log with this title (for tooltips that only know the name)
function QS:IdByTitle(title)
  for id, e in pairs(QS.log or {}) do if e.title == title then return id end end
end
-- tooltip lines for a quest you could pick up: level, XP, money, the chain it's in
function QS:QuestTip(id, giverName, footer)
  local info = QS:Info(id)
  local q = D:Quest(id)
  local title = (info and info.title) or (q and q[1]) or ("Quest " .. id)
  local lv = (info and info.level) or (q and q[2]) or 0
  local lines = { ("%s  [%d]"):format(title, lv) }
  local xp = QS.RewardXP(id, Q.player.level)
  local m = QS.RewardMoney(id)
  lines[#lines + 1] = ("%d XP%s"):format(xp or 0, (m and m > 0) and ("   " .. money(m)) or "")
  if giverName then lines[#lines + 1] = "From " .. giverName end
  QS:TipExtra(id, lines, true)             -- the objective, with the chain under it
  local chain = QS:Chain(id)
  if #chain > 1 then
    local parts = {}
    for i, cid in ipairs(chain) do
      local cq = D:Quest(cid)
      local t = cq and cq[1] or tostring(cid)
      if cid == id then t = "|cffffffff[" .. t .. "]|r"
      elseif QS.done[cid] then t = "|cff7fdc5a" .. t .. "|r"
      else t = "|cffb79f80" .. t .. "|r" end
      parts[i] = t
    end
    lines[#lines + 1] = ("Chain (%d of %d): "):format((function() for i, c in ipairs(chain) do if c == id then return i end end end)() or 1, #chain)
      .. table.concat(parts, " > ")
  end
  QS:TipExtra(id, lines, false, true)      -- the quest ID last
  if footer then lines[#lines + 1] = footer end
  return lines
end

local questNPCs     -- (Quests.lua, reputation: the NPCs of the quests you could do)
function QS:BuildPool()
  QS.cache = {}
  questNPCs = nil
  -- quests that name another as their next one: that next quest needs one of them first, even
  -- where the data has no prerequisite (The Goblin Trader -> Smuggler's Paradise)
  QS.prevOf = {}
  for id, x in pairs(D.db.qx or {}) do
    if x[7] then
      local t = QS.prevOf[x[7]]
      if not t then t = {}; QS.prevOf[x[7]] = t end
      t[#t + 1] = id
    end
  end
  Q.char.blocked = Q.char.blocked or {}
  local pool = {}
  for id in pairs(D.db.quest) do
    if not Q.char.skipped[id] and QS:Info(id) then pool[#pool + 1] = id end
  end
  table.sort(pool)
  QS.pool = pool
  Q:Debug(#pool .. " quests possible for this character")
  return pool
end

-- ------------------------------------------------------------------ dynamic availability
-- `st` is a planning state: { done = set, log = set, level = n }. Without it the live state is used.
-- could this character ever take that quest (race / class / a quest giver of your faction)? An
-- "one of these first" prerequisite made only of quests you can never take isn't yours to do
-- (The Brassbolts Brothers is an Alliance breadcrumb for Gahz'rilla; Horde just take Gahz'rilla).
local everCache = {}
function QS:CanEverTake(id)
  local c = everCache[id]
  if c ~= nil then return c end
  local q, x, p = D:Quest(id), D:QuestExtra(id) or {}, Q.player
  local ok = q ~= nil
  local races = QS.RACE_FIX[id]
  if races == nil then races = x[1] end
  if ok and races ~= 0 and not Q.HasBit(races, p.race) then ok = false end
  if ok and not Q.HasBit(x[2], p.classID) then ok = false end
  if ok and not D.startItem[id] then
    local any = false
    for _, k in ipairs(D:Givers(id) or {}) do if giverOK(k, p.faction) then any = true; break end end
    ok = any
  end
  everCache[id] = ok
  return ok
end
local function anyOf(list, done)
  local takeable = false
  for _, pre in ipairs(list) do
    if done[pre] then return true end
    if QS:CanEverTake(pre) then takeable = true end
  end
  return not takeable          -- none of them is for you: not your requirement
end

-- ------------------------------------------------------------------ reputation / hostile quest NPCs
-- your standing with a faction: 1 hated .. 4 neutral .. 8 exalted (and the raw value), nil = not known
local standCache = {}
Q:On("UPDATE_FACTION", function() wipe(standCache) end)
function QS.Standing(faction)
  if not faction then return end
  local c = standCache[faction]
  if c then return c[1], c[2] end
  local r, v = QS.StandingNow(faction)
  standCache[faction] = { r, v }
  return r, v
end
function QS.StandingNow(faction)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, faction)
    if ok and type(d) == "table" and d.reaction and not Q.Secret(d.reaction) then return d.reaction, d.currentStanding end
  end
  if GetFactionInfoByID then
    local ok, name, _, standing, _, _, value = pcall(GetFactionInfoByID, faction)
    if ok and name and standing and not Q.Secret(standing) then return standing, value end
  end
end
-- quest NPCs seen hostile / unfriendly to this character (UnitReaction <= 3): they won't talk to you,
-- and their camp attacks you. Cleared when seen friendly again (your reputation went up)
-- the NPCs that give or take quests you could do (only those are worth remembering; rebuilt with the pool)
local function isQuestNPC(npc)
  if not questNPCs then
    questNPCs = {}
    for _, id in ipairs(QS.pool or {}) do
      local info = QS:Info(id)
      for _, list in ipairs({ info and info.givers or {}, info and info.enders or {} }) do
        for _, k in ipairs(list) do
          local n = tonumber(tostring(k):match("^c:?(%d+)$"))
          if n then questNPCs[n] = true end
        end
      end
    end
    for id in pairs(QS.log or {}) do
      local info = QS:Info(id)
      for _, k in ipairs(info and info.enders or {}) do
        local n = tonumber(tostring(k):match("^c:?(%d+)$"))
        if n then questNPCs[n] = true end
      end
    end
  end
  return questNPCs[npc]
end
QS.IsQuestNPC = isQuestNPC
Q:On("QC_QUESTS_CHANGED", function() questNPCs = nil end)
-- (earlier versions remembered every hostile mob: keep only quest NPCs)
Q:On("QC_READY", function()
  Q.After(5, function()
    local h = Q.char and Q.char.hostile
    if type(h) ~= "table" then return end
    for npc in pairs(h) do if not isQuestNPC(npc) then h[npc] = nil end end
  end)
end)
function QS.NoteReaction(unit)
  if not (UnitExists and UnitExists(unit)) or (UnitIsPlayer and UnitIsPlayer(unit)) then return end
  local k = Q.UnitKey(unit)
  local npc = k and tonumber(k:match("^c(%d+)$"))
  if not npc or not UnitReaction or not isQuestNPC(npc) then return end
  local ok, r = pcall(UnitReaction, unit, "player")
  if not ok or not r or Q.Secret(r) then return end
  Q.char.hostile = type(Q.char.hostile) == "table" and Q.char.hostile or {}
  local was = Q.char.hostile[npc]
  if r <= 3 then Q.char.hostile[npc] = time() elseif was then Q.char.hostile[npc] = nil end
  if (r <= 3) ~= (was ~= nil) and Q.Planner then Q.Planner:Replan(2) end
end
for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
  Q:On(ev, function() pcall(QS.NoteReaction, ev == "PLAYER_TARGET_CHANGED" and "target" or "mouseover") end)
end
Q:On("NAME_PLATE_UNIT_ADDED", function(unit) if type(unit) == "string" and not Q.Secret(unit) then pcall(QS.NoteReaction, unit) end end)

-- why you can't deal with this quest's NPCs, or nil: keys = info.givers / info.enders
function QS.RepBlock(id, keys)
  local info = QS:Info(id)
  if not info then return end
  local x = info.x or {}
  -- the reputation the quest needs (ForeverDB x[19] = {faction, minimum value})
  local need = x[19]
  if type(need) == "table" and need[1] then
    local reaction, value = QS.Standing(need[1])
    if value and need[2] and value < need[2] then return "needs more reputation" end
    if not reaction and (need[2] or 0) > 0 then return "needs reputation you don't have yet" end
  end
  -- the faction the quest gives reputation with is the quest NPCs' own: hostile / unfriendly with it,
  -- they won't talk to you (Timbermaw, Bloodsail, Wildhammer ... before you've earned them)
  local rep = x[15]
  if type(rep) == "table" and rep[1] and (rep[2] or 0) > 0 then
    local reaction = QS.Standing(rep[1])
    if reaction and reaction <= 3 then return "hostile with its faction" end
  end
  -- its NPCs were seen hostile to you
  local h = Q.char and Q.char.hostile
  if h and keys and #keys > 0 then
    local all = true
    for _, k in ipairs(keys) do
      local npc = tonumber(tostring(k):match("^c:?(%d+)$"))
      if not (npc and h[npc]) then all = false break end
    end
    if all then return "its NPC is hostile to you" end
  end
end

function QS:Available(id, st)
  local info = QS:Info(id)
  if not info then return false end
  local done = st and st.done or QS.done
  local log = st and st.log or QS.log
  local level = st and st.level or Q.player.level
  if done[id] or log[id] then return false end
  if level < info.min then return false end
  if QS.RepBlock(id, info.givers) then return false end
  -- the quest giver didn't offer it when you stood there: not available yet (cleared on level up /
  -- turn-ins, which can unlock it). Only for the live state, not for planning ahead.
  if not st and Q.char.blocked and Q.char.blocked[id] then return false end
  if st and st.blocked and st.blocked[id] then return false end
  -- other players' recordings: every one of its givers didn't offer it at this level or higher
  -- (ForeverDB qmiss), so it needs something the database doesn't know yet
  local miss = D.db and D.db.qmiss and D.db.qmiss[id]
  if miss and info.givers and #info.givers > 0 then
    local all = true
    for _, k in ipairs(info.givers) do
      local npc = tonumber(tostring(k):match("^c:?(%d+)$"))
      if not (npc and miss[npc] and level <= miss[npc]) then all = false break end
    end
    if all then return false end
  end
  local x = info.x
  if not x[3] and not x[4] and QS.prevOf and QS.prevOf[id] then
    if not anyOf(QS.prevOf[id], done) then return false end
  end
  if x[3] then
    if not anyOf(x[3], done) then return false end
  end
  if x[4] then
    for _, pre in ipairs(x[4]) do if not done[pre] then return false end end
  end
  if x[5] then
    for _, ex in ipairs(x[5]) do if done[ex] or log[ex] then return false end end
  end
  if info.breadcrumbFor and (done[info.breadcrumbFor] or log[info.breadcrumbFor]) then return false end
  if x[19] then
    local value
    if C_Reputation and C_Reputation.GetFactionDataByID then
      local fd = C_Reputation.GetFactionDataByID(x[19][1])
      value = fd and fd.currentStanding
    elseif GetFactionInfoByID then
      value = select(6, GetFactionInfoByID(x[19][1]))
    end
    if value and value < x[19][2] then return false end
  end
  return true
end

-- ------------------------------------------------------------------ events
-- QUEST_LOG_UPDATE fires all the time (kills, loot, other players' quests nearby...). Only tell
-- the rest of Questicus when the log really changed - a quest added / removed / completed / failed
-- or an objective moved - otherwise the route was rebuilt every few seconds for nothing (lag).
local function sameObjectives(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if x.finished ~= y.finished or x.numFulfilled ~= y.numFulfilled or x.text ~= y.text then return false end
  end
  return true
end
local function sameLog(old, new)
  if not old then return false end
  for id, e in pairs(new) do
    local o = old[id]
    if not o or o.complete ~= e.complete or o.failed ~= e.failed or o.index ~= e.index
      or not sameObjectives(o.objectives or {}, e.objectives or {}) then return false end
  end
  for id in pairs(old) do if not new[id] then return false end end
  return true
end
local function changed()
  local old = QS.log
  QS:ReadLog()
  if sameLog(old, QS.log) then return end
  Q:Send("QC_QUESTS_CHANGED")
end
Q:On("QC_READY", function(ok)
  if not ok then return end
  QS:ReadDone()
  QS:ReadLog()
  QS:BuildPool()
end)
Q:On("QUEST_LOG_UPDATE", function() Q.Throttle("log", 0.3, changed) end)
-- a quest taken (again) or dropped: forget what was worked out about it while it was in the log in
-- another state (its spots, "the game's waypoint" for a finished one ...), so abandoning and taking it
-- again is planned from what the log says now
local function fresh(id)
  if type(id) ~= "number" or id < 1 then return end
  if Q.Planner and Q.Planner.ForgetMeta then Q.Planner.ForgetMeta(id) end
  if Q.char and Q.char.blocked then Q.char.blocked[id] = nil end
end
Q:On("QUEST_ACCEPTED", function(a, b)
  local id = b or a
  fresh(id)
  if type(id) == "number" then QS.done[id] = nil end     -- (in your log: not handed in)
  Q.Throttle("log", 0.1, changed)
  Q.After(1.5, function() Q.Throttle("log", 0.1, changed) end)
end)
Q:On("QUEST_REMOVED", function(id)
  fresh(id)
  Q.Throttle("log", 0.3, changed)
end)
-- a quest the NPC didn't offer stays off the route until something could have unlocked it: a level
-- up, or handing in a quest at that same NPC (the usual chain). Handing in anything anywhere used to
-- bring them all back (Remote Contact / Betrayed kept reappearing).
Q:On("QUEST_TURNED_IN", function(id)
  if id then QS.done[id] = true end
  local bl = Q.char and Q.char.blocked
  local done = id and QS:Info(id)
  if bl and next(bl) and done then
    local at = {}
    for _, k in ipairs(done.enders or {}) do at[k] = true end
    for _, k in ipairs(done.givers or {}) do at[k] = true end
    for bid in pairs(bl) do
      local bi = QS:Info(bid)
      for _, k in ipairs(bi and bi.givers or {}) do if at[k] then bl[bid] = nil; break end end
    end
  end
  Q.Throttle("log", 0.2, changed)
end)
Q:On("PLAYER_LEVEL_UP", function() if Q.char and Q.char.blocked then wipe(Q.char.blocked) end end)

-- the NPC in front of you doesn't offer a quest the route expected from it: remember that, replan,
-- and record it for the database (QuesticusCollect.qna)
function QS:NotOffered(npcKey, offered)
  if not npcKey then return end
  local P = Q.Planner
  local changed = false
  for _, s in ipairs(P.steps or {}) do
    local id = s.quests and s.quests[1]
    -- only quests that should be open right now (later steps may wait for quests you haven't done yet)
    if s.type == "accept" and id and s.point and s.point.key == npcKey and not offered[id] and not QS.log[id]
      and QS:Available(id) then
      Q.char.blocked[id] = Q.player.level
      changed = true
      if QuesticusCollect and Q.db.collect ~= false then
        QuesticusCollect.qna = QuesticusCollect.qna or {}
        QuesticusCollect.qna[id] = { npc = npcKey, lv = Q.player.level, n = ((QuesticusCollect.qna[id] or {}).n or 0) + 1 }
      end
      Q:Print(("%s isn't offered here yet - it probably needs an earlier quest first. Route updated.")
        :format(s.title or ("quest " .. id)))
    end
  end
  if changed then P:Replan(0.2) end
end

Q:On("UNIT_QUEST_LOG_CHANGED", function(unit) if unit == "player" then Q.Throttle("log", 0.3, changed) end end)
