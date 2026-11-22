-- Questicus recorder: fills the gaps in the database while you quest.
--   qsp  - where you were when a quest objective counted up (objective areas)
--   qsrc - what you looted right before an objective counted up (the real source of a quest item)
--   qst / sp - who gives and takes quests, and where they stand
-- Saved in QuesticusCollect (account-wide) in the same layout as Command Center's recordings, so
-- the recordings sync can send it to ForeverDB, where it helps every player. Used right away too:
-- a quest with no map spot gets one as soon as anyone (you included) made progress on it.
local Q = Questicus
local D, QS = Q.Data, Q.Quests
local C = {}
Q.Collect = C

local SPOT_NEAR, SPOT_MAX = 15, 60
local LOOT_WINDOW = 8          -- seconds between looting and the objective counting up
local recent = {}              -- { key, t } of recent loot sources
local snapshot = {}            -- [quest] = progress number

local function db()
  QuesticusCollect = QuesticusCollect or {}
  local c = QuesticusCollect
  c.v = 1
  c.qsp, c.qsrc, c.qst, c.sp = c.qsp or {}, c.qsrc or {}, c.qst or {}, c.sp or {}
  return c
end

function C.On() return Q.db and Q.db.collect ~= false end

-- "Creature-0-1-0-47-1706-..." -> "c:1706", "GameObject-...-645516-..." -> "o:645516"
function C.KeyOfGUID(guid)
  local kind, id = Q.ParseGUID(guid)
  if not id then return end
  if kind == "Creature" or kind == "Vehicle" then return "c:" .. id end
  if kind == "GameObject" then return "o:" .. id end
end

local function here()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local map = C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x or x <= 0 or y <= 0 then return end
  return map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

local function addSpot(tbl, key, map, x, y)
  local maps = tbl[key]
  if not maps then maps = {}; tbl[key] = maps end
  local pts = maps[map]
  if not pts then pts = {}; maps[map] = pts end
  if #pts >= SPOT_MAX * 2 then return false end
  for j = 1, #pts - 1, 2 do
    if math.abs(pts[j] - x) <= SPOT_NEAR and math.abs(pts[j + 1] - y) <= SPOT_NEAR then return false end
  end
  pts[#pts + 1], pts[#pts + 2] = x, y
  return true
end

local function progressOf(e)
  local n = 0
  for _, o in ipairs(e.objectives or {}) do
    n = n + (o.numFulfilled or 0) + (o.finished and 1000 or 0)
  end
  return n
end

-- ------------------------------------------------------------------ objective progress
function C:CheckProgress()
  if not C.On() then return end
  local now = GetTime and GetTime() or 0
  local c = db()
  for id, e in pairs(QS.log) do
    local p = progressOf(e)
    local before = snapshot[id]
    if before and p > before then
      Q:Send("QC_PROGRESS", id)
      local map, x, y = here()
      if map and addSpot(c.qsp, id, map, x, y) then C.recorded = (C.recorded or 0) + 1 end
      -- a kill credit: the mob you just killed (your target) is where this objective lives - unless
      -- an object was just picked up (then the dead mob you still have targeted had nothing to do with
      -- it: Harvesting Windstones got a bear as its "source")
      local fromObject = false
      for _, r in ipairs(recent) do
        if now - r.t <= LOOT_WINDOW and r.key:sub(1, 1) == "o" then fromObject = true end
      end
      -- (objects picked up without a loot window: the one in front of you right now)
      if not fromObject and Q.Glow and Q.Glow.Find and Q.Glow.Unit then
        local ok = pcall(Q.Glow.Find)
        local u = ok and Q.Glow.Unit()
        local ok7 = u and C.KeyOfGUID(Q.UnitGUID(u))
        if ok7 and ok7:sub(1, 1) == "o" then
          fromObject = true
          recent[#recent + 1] = { key = ok7, t = now }
        end
      end
      if not fromObject and UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then
        local tk = C.KeyOfGUID(Q.UnitGUID("target"))
        if tk then
          recent[#recent + 1] = { key = tk, t = now }
          if map then addSpot(c.sp, tk, map, x, y) end
        end
      end
      -- whatever was looted just before counts as a source of this quest
      for _, r in ipairs(recent) do
        if now - r.t <= LOOT_WINDOW then
          local s = c.qsrc[id]
          if not s then s = {}; c.qsrc[id] = s end
          s[r.key] = (s[r.key] or 0) + 1
        end
      end
      D:Forget(id)
      if Q.Planner.ForgetMeta then Q.Planner.ForgetMeta(id) end
    end
    snapshot[id] = p
  end
  for id in pairs(snapshot) do if not QS.log[id] then snapshot[id] = nil end end
end

-- ------------------------------------------------------------------ loot sources
Q:On("LOOT_OPENED", function()
  if not C.On() or not GetNumLootItems then return end
  local now = GetTime and GetTime() or 0
  for i = #recent, 1, -1 do if now - recent[i].t > LOOT_WINDOW then table.remove(recent, i) end end
  local seen = {}
  local function add(key)
    if key and not seen[key] then seen[key] = true; recent[#recent + 1] = { key = key, t = now } end
  end
  for slot = 1, GetNumLootItems() do
    if GetLootSourceInfo then
      local info = { pcall(GetLootSourceInfo, slot) }
      for j = 2, #info, 2 do add(C.KeyOfGUID(info[j])) end
    end
  end
  -- WoW Forever often gives no loot source: the dead mob you target / point at is the corpse
  if not next(seen) then
    for _, u in ipairs({ "target", "mouseover" }) do
      if UnitExists and UnitExists(u) and UnitIsDead and UnitIsDead(u) then add(C.KeyOfGUID(Q.UnitGUID(u))) end
    end
  end
end)

-- ------------------------------------------------------------------ quest givers / enders
local function npcKey()
  return C.KeyOfGUID(Q.UnitGUID("npc"))
end
local function noteNPC(field)
  if not C.On() then return end
  local id = GetQuestID and GetQuestID()
  local key = npcKey()
  if not id or id == 0 or not key then return end
  local c = db()
  local q = c.qst[id]
  if not q then q = {}; c.qst[id] = q end
  q.n = q.n or (GetTitleText and GetTitleText()) or nil
  q[field] = q[field] or {}
  local have = false
  for _, k in ipairs(q[field]) do if k == key then have = true end end
  if not have then table.insert(q[field], key) end
  local map, x, y = here()
  if map then addSpot(c.sp, key, map, x, y) end
end
Q:On("QUEST_DETAIL", function() noteNPC("g") end)
Q:On("QUEST_PROGRESS", function() noteNPC("e") end)
Q:On("QUEST_COMPLETE", function() noteNPC("e") end)

Q:On("QC_QUESTS_CHANGED", function() C:CheckProgress() end)

-- where you walk becomes known ground for the pathing (Nav.lua); kept per continent, capped
local TRAIL_MAX = 30000
local trailN = 0
local walker = CreateFrame("Frame")
local acc = 0
walker:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 2 then return end
  acc = 0
  if not C.On() or not Q.Nav or (IsFlying and IsFlying()) or (UnitOnTaxi and UnitOnTaxi("player")) then return end
  local pos = D:PlayerPos()
  if not pos or not pos.i then return end
  local k = Q.Nav:Walked(pos)
  if not k then return end
  local c = db()
  c.trail = c.trail or {}
  local t = c.trail[pos.i]
  if not t then t = {}; c.trail[pos.i] = t end
  if not t[k] and trailN < TRAIL_MAX then t[k] = 1; trailN = trailN + 1 end
end)
Q:On("QC_READY", function()
  db()
  for id, e in pairs(QS.log) do snapshot[id] = progressOf(e) end
end)

Q:Command("recorded", "what Questicus has recorded for the database", function()
  local c = db()
  local nq, ns, ng = 0, 0, 0
  for _ in pairs(c.qsp) do nq = nq + 1 end
  for _ in pairs(c.qsrc) do ns = ns + 1 end
  for _ in pairs(c.qst) do ng = ng + 1 end
  Q:Print(("recorded objective areas for %d quests, item sources for %d, givers/enders for %d. Recording is %s.")
    :format(nq, ns, ng, C.On() and "on" or "off"))
end)
