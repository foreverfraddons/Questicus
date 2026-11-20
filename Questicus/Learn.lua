-- Questicus learning: the route adapts to how you actually play. Everything here is measured while
-- you quest and fed straight back into the planner (the next replan uses it).
--   Work time  - every active second is split between the quests that made progress in the last
--                2 minutes; at turn-in that is the time the quest really took (QuesticusCollect.qwork,
--                account-wide). Quests whose work overlapped are "done together" (qtog): the planner
--                bundles them next time even when their areas are a bit apart, and the step details
--                show the time for the whole group.
--   Travel     - yards per second, mounted and on foot, counted only while you actually move: standing
--                still for more than a second stops the clock until you move again.
--   Kills      - time to kill (combat time / kills, per level difference) and the gap between pulls.
--   Pace       - how the real work time compares with the estimate, for quests with no record yet.
--   Counts     - how many of a thing an objective needs (seen in the quest log, for planning ahead).
-- /qc learn shows it, /qc learn reset starts over.
local Q = Questicus
local D, QS, P = Q.Data, Q.Quests, Q.Planner
local L = {}
Q.Learn = L

local VERSION = 2
local WORKING = 120          -- a quest counts as "being worked on" this long after it progressed
local STILL = 1              -- seconds of standing still before travel time stops counting

local function st()
  local s = Q.char and Q.char.learn
  if not s or s.v ~= VERSION then
    s = { v = VERSION, k = 1, kn = 0,
      walk = { d = 0, t = 0 }, mount = { d = 0, t = 0 },
      ttk = {}, ttkAll = { t = 0, n = 0 }, gap = { t = 0, n = 0 }, total = 0 }
    if Q.char then Q.char.learn = s end
  end
  return s
end
local function acct()
  QuesticusCollect = QuesticusCollect or {}
  local c = QuesticusCollect
  c.qwork, c.qtog, c.qn = c.qwork or {}, c.qtog or {}, c.qn or {}
  return c
end
local function on() return Q.db and Q.db.collect ~= false end

-- ------------------------------------------------------------------ what the planner asks
function L:TimeScale()
  if not Q.char then return 1 end
  local s = st()
  if (s.kn or 0) < 2 then return 1 end
  return math.max(0.5, math.min(2.5, s.k or 1))
end

function L:Speed(mounted)
  if not Q.char then return nil end
  local r = st()[mounted and "mount" or "walk"]
  if r.t < 60 then return nil end                -- a minute of moving before trusting it
  local v = r.d / r.t
  if v < 3 or v > 40 then return nil end
  return v
end

local function ttkFormula(diff) return math.max(4, math.min(30, 11 + 1.3 * diff)) end
function L:TTK(diff)
  diff = math.max(-10, math.min(5, math.floor((diff or 0) + 0.5)))
  local s = Q.char and st()
  if not s then return ttkFormula(diff) end
  local b = s.ttk[diff]
  if b and b.n >= 3 then return b.t / b.n end
  if s.ttkAll.n >= 5 then
    -- learned overall, shaped by the level difference
    local avgDiff = (s.ttkAll.d or 0) / s.ttkAll.n
    return (s.ttkAll.t / s.ttkAll.n) * ttkFormula(diff) / ttkFormula(avgDiff)
  end
  return ttkFormula(diff)
end

function L:Gap()
  local s = Q.char and st()
  if s and s.gap.n >= 5 then return math.max(4, math.min(60, s.gap.t / s.gap.n)) end
  return 14
end

-- seconds a quest really takes (average over every time it was done, any character)
function L:WorkTime(id)
  local w = QuesticusCollect and QuesticusCollect.qwork and QuesticusCollect.qwork[id]
  if w and w.n and w.n > 0 and w.s and w.s > 5 then return w.s end
end

-- how often two quests were worked on at the same time (30 s units)
function L:Together(a, b)
  local t = QuesticusCollect and QuesticusCollect.qtog
  if not t then return 0 end
  local x = t[a] and t[a][b] or 0
  local y = t[b] and t[b][a] or 0
  return math.max(x, y)
end
function L:Partners(id)
  local out = {}
  for other, n in pairs(QuesticusCollect and QuesticusCollect.qtog and QuesticusCollect.qtog[id] or {}) do
    if n >= 2 then out[#out + 1] = other end
  end
  return out
end

-- ------------------------------------------------------------------ work time per quest
local lastProgress = {}       -- [quest] = GetTime() of its last objective progress
local work = {}               -- [quest] = active seconds so far (this session; also in Q.char.work)
local togAcc = {}             -- [a..":"..b] = seconds together, converted to 30 s units
local function now() return GetTime and GetTime() or 0 end

function L:Progress(id) lastProgress[id] = now() end
Q:On("QC_PROGRESS", function(id) L:Progress(id) end)
Q:On("QUEST_ACCEPTED", function(a, b)
  local id = b or a
  if type(id) == "number" then lastProgress[id] = now() end   -- just taken: you're about to work on it
end)

local function workingSet()
  local set, t = {}, now()
  for id, at in pairs(lastProgress) do
    local e = QS.log[id]
    if e and not e.complete and t - at <= WORKING then set[#set + 1] = id
    elseif not e then lastProgress[id] = nil end
  end
  return set
end

function L:Work(dt)
  local set = workingSet()
  if #set == 0 then return end
  Q.char.work = Q.char.work or {}
  local share = dt / #set
  for _, id in ipairs(set) do Q.char.work[id] = (Q.char.work[id] or 0) + share end
  if #set > 1 and on() then
    local c = acct()
    for i = 1, #set do
      for j = i + 1, #set do
        local a, b = math.min(set[i], set[j]), math.max(set[i], set[j])
        local k = a .. ":" .. b
        togAcc[k] = (togAcc[k] or 0) + dt
        if togAcc[k] >= 30 then
          togAcc[k] = togAcc[k] - 30
          c.qtog[a] = c.qtog[a] or {}
          c.qtog[a][b] = (c.qtog[a][b] or 0) + 1
        end
      end
    end
  end
end

-- at turn-in: the real work time, the pace vs the estimate, and who it was done with
Q:On("QUEST_TURNED_IN", function(id)
  if type(id) ~= "number" or not Q.char then return end
  local w = Q.char.work and Q.char.work[id]
  if Q.char.work then Q.char.work[id] = nil end
  lastProgress[id] = nil
  if not w or w < 5 then return end
  local s = st()
  -- pace: real / estimated (estimate without pace), averaged
  local m = P.Meta(id)
  if m and m.time and m.time > 20 then
    local ratio = math.max(0.3, math.min(4, w / m.time))
    s.kn = (s.kn or 0) + 1
    local a = math.max(0.1, 1 / math.min(s.kn, 12))
    s.k = (s.k or 1) * (1 - a) + ratio * a
  end
  if on() then
    local c = acct()
    local r = c.qwork[id] or { s = 0, n = 0 }
    r.s = (r.s * r.n + w) / (r.n + 1)
    r.n = r.n + 1
    r.lv = Q.player.level
    c.qwork[id] = r
  end
  Q:Debug(("work time %s: %s"):format(id, math.floor(w)))
end)

-- objective counts seen in the log (for planning quests you haven't taken yet)
Q:On("QC_QUESTS_CHANGED", function()
  if not on() then return end
  local c = acct()
  for id, e in pairs(QS.log) do
    local m = P.Meta(id)
    for _, o in ipairs(e.objectives or {}) do
      if o.numRequired and o.numRequired > 0 and o.text and m then
        local txt = o.text:lower()
        for _, l in ipairs(m.lines or {}) do
          if l.name and txt:find(l.name:lower(), 1, true) then
            c.qn[id] = c.qn[id] or {}
            c.qn[id][l.name] = o.numRequired
          end
        end
      end
    end
  end
end)

-- ------------------------------------------------------------------ travel speed (moving only)
local lastPos, still = nil, 0
local function counting()
  if not (Q.char and Q.char.surveyDone) then return false end
  if UnitOnTaxi and UnitOnTaxi("player") then return false end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
  return true
end

function L:Move(dt)
  local here = D:PlayerPos()
  local moved = false
  if here and lastPos and here.i == lastPos.i then
    local d = D.Dist(here, lastPos)
    if d > 0.25 and d < 60 * dt + 5 then      -- a real step (not a teleport / loading screen)
      moved = true
      still = 0
      if counting() and not (IsFlying and IsFlying()) and not (IsSwimming and IsSwimming()) then
        local r = st()[(IsMounted and IsMounted()) and "mount" or "walk"]
        r.d, r.t = r.d + d, r.t + dt
        if r.t > 1800 then r.d, r.t = r.d * 0.5, r.t * 0.5 end   -- recent moving counts most
      end
    else
      still = still + dt
    end
  else
    still = still + dt
  end
  lastPos = here
  return moved or still <= STILL
end

-- ------------------------------------------------------------------ time to kill + gap
local fight, kills, lastFightEnd, fightDiff = nil, 0, nil, 0
Q:On("PLAYER_REGEN_DISABLED", function()
  fight, kills = now(), 0
  local lv = UnitLevel and UnitLevel("target")
  if Q.Secret(lv) then lv = nil end
  fightDiff = (lv and lv > 0) and math.max(-10, math.min(5, lv - Q.player.level)) or 0
  if lastFightEnd and counting() then
    local gap = fight - lastFightEnd
    if gap > 1 and gap < 60 then
      local g = st().gap
      g.t, g.n = g.t + gap, g.n + 1
      if g.n > 60 then g.t, g.n = g.t * 0.5, g.n * 0.5 end
    end
  end
end)
-- "X dies, you gain N experience" = one kill
Q:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
  if fight and type(msg) == "string" and not Q.Secret(msg) and msg:find("dies") then kills = kills + 1 end
end)
Q:On("PLAYER_REGEN_ENABLED", function()
  if not fight then return end
  local t = now() - fight
  lastFightEnd = now()
  if kills > 0 and t > 1 and t < 600 and counting() then
    local s = st()
    local per = t / kills
    local b = s.ttk[fightDiff] or { t = 0, n = 0 }
    b.t, b.n = b.t + per, b.n + 1
    if b.n > 40 then b.t, b.n = b.t * 0.5, b.n * 0.5 end
    s.ttk[fightDiff] = b
    local a = s.ttkAll
    a.t, a.n, a.d = a.t + per, a.n + 1, (a.d or 0) + fightDiff
    if a.n > 80 then a.t, a.n, a.d = a.t * 0.5, a.n * 0.5, a.d * 0.5 end
  end
  fight = nil
end)

-- ------------------------------------------------------------------ ticking
local f = CreateFrame("Frame")
local acc, slow = 0, 0
f:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.2 then return end
  local dt = math.min(acc, 2)
  acc = 0
  if not Q.char then return end
  local active = L:Move(dt)
  if (UnitAffectingCombat and UnitAffectingCombat("player")) then active = true end
  if active and counting() and not (IsInInstance and IsInInstance()) then
    L:Work(dt)
    st().total = (st().total or 0) + dt
  end
end)

-- ------------------------------------------------------------------ quest XP from recordings
-- the full XP of a quest, worked back from what someone really got at their level
local function penalty(qlvl, plvl)
  local diff = plvl - (qlvl or plvl)
  if diff >= 10 then return 0.1 elseif diff > 5 then return 1 - 0.2 * (diff - 5) end
  return 1
end
function L:RecordedXP(id, plvl)
  local a = QuesticusCollect and QuesticusCollect.qact and QuesticusCollect.qact[id]
  if not (a and a.xp and a.xp > 0 and a.lv) then return end
  local q = D:Quest(id)
  local ql = q and q[2]
  local p = penalty(ql, a.lv)
  if p <= 0.1 then return end            -- grey when recorded: too little to work back from
  return math.floor(a.xp / p * penalty(ql, plvl))
end

Q:Command("learn", "what Questicus has learned about your play (/qc learn reset to start over)", function(arg)
  local s = st()
  if arg == "reset" then
    Q.char.learn, Q.char.work = nil, nil
    Q:Print("learning reset for this character (quest times other characters recorded stay)")
    if P.Replan then P:Replan(1) end
    return
  end
  local function sp(r) return r.t >= 60 and ("%.1f yd/s (%d min moving)"):format(r.d / r.t, math.floor(r.t / 60)) or "not enough yet" end
  local nq = 0
  for _ in pairs(QuesticusCollect and QuesticusCollect.qwork or {}) do nq = nq + 1 end
  Q:Print(("on foot %s, mounted %s"):format(sp(s.walk), sp(s.mount)))
  Q:Print(("time to kill %.0f s (even level), %d fights; %.0f s between pulls"):format(L:TTK(0), math.floor(s.ttkAll.n), L:Gap()))
  Q:Print(("estimates x%.2f from %d quests; real times known for %d quests (all characters)"):format(L:TimeScale(), s.kn or 0, nq))
end)
