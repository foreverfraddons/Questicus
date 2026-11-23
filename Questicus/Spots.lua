-- Objective spots: which kill / collect spot the arrow points at, and which ones to leave alone.
--  * The arrow goes to the closest open spot, leaning toward the next step of the route, so you work
--    your way through the area in that direction instead of zig-zagging.
--  * A spot where you just got progress (killed it / picked it up), or where you stood and there was
--    nothing to get, goes on cooldown: the arrow moves to another one until it should be back.
--  * The cooldown is the respawn time: what this account has measured, else what everyone measured
--    (ForeverDB's resp table), else 1 minute. Respawns are measured while you play (a spot you used,
--    seen with the mob / object back) and saved in QuesticusCollect.resp for the database, so the next
--    run - yours or anyone's after an update - uses the real timer.
local Q = Questicus
local D, P, QS = Q.Data, Q.Planner, Q.Quests
local S = Q.Secret
local SP = {}
Q.Spots = SP

local ARRIVE = 25          -- yards: close to a spot (a cooled one seen back, calibration)
local EXACT = 6            -- yards: standing on the map marker - look for what should be there
local STUCK = 14           -- yards: can't get closer (in a rock, up a slope) and standing still
local NEAR = 60            -- yards: progress here counts for the spot
local UNDER = 28           -- yards: a mob this close to the marker is "under" it (they wander a bit)
local SCAN_C = 2.5         -- seconds of looking for a creature at the marker before moving on
local SCAN_O = 4           -- seconds for an object (give it time to come into view)
local FALLBACK = 60        -- seconds: respawn time nobody has measured yet
local LEAN = 0.35          -- how much the next step pulls the choice (0 = just the closest)
local KEEP = 0.8           -- a new spot must be this much closer to take over (no flip-flopping)

local function now() return time() end
local lastResp = {}        -- [src] = the respawn time last used for its cooldowns
local function cds()
  if not Q.char then return {} end
  Q.char.spotcd = type(Q.char.spotcd) == "table" and Q.char.spotcd or {}
  return Q.char.spotcd
end
local function rec()
  if not (QuesticusCollect and Q.db and Q.db.collect ~= false) then return nil end
  QuesticusCollect.resp = type(QuesticusCollect.resp) == "table" and QuesticusCollect.resp or {}
  return QuesticusCollect.resp
end

function SP.Key(p)
  if not p then return end
  return ("%s:%d:%d:%d"):format(tostring(p.key or "?"), p.i or 0, math.floor((p.x or 0) / 5), math.floor((p.y or 0) / 5))
end

-- the creature / object a spot is for ("c123", "o456"), or nil when it isn't known
local function source(p)
  local k = p and p.key
  if type(k) == "string" and (k:sub(1, 1) == "c" or k:sub(1, 1) == "o") and tonumber(k:sub(2)) then return k end
end
SP.Source = source

-- respawn seconds for a creature / object: measured here > measured by everyone (ForeverDB) > 1 minute
-- the respawn from real timings only (yours, everyone's), nil when there are none
local function timed(src)
  local own = src and QuesticusCollect and QuesticusCollect.resp and QuesticusCollect.resp[src]
  local shared = src and D.db and D.db.resp and D.db.resp[src]
  local t
  if own and (own.n or 0) > 0 then
    t = own.s / own.n
    if shared and (own.n or 0) < 3 then t = (t * own.n + shared * 3) / (own.n + 3) end
  elseif shared then
    t = shared
  end
  return t, own
end
local LO_TRUST = 2.5      -- "not back after X" far beyond the timed respawn: it came back elsewhere (mobs
                          -- share spawn points), not later - don't let that stretch the cooldowns
local LO_MAX = 900        -- seconds: "not back yet" with nothing timed stops counting past this
function SP.Respawn(src)
  local t, own = timed(src)
  -- "it wasn't back yet after this long": wait at least that; "it was back by then": at most that
  local lo, hi = own and own.lo, own and own.hi
  if t and lo and lo > t * LO_TRUST then lo = nil end
  if not t and lo and hi and hi > lo then t = (lo + hi) / 2 end
  if not t and hi then t = math.min(FALLBACK, hi) end
  if not t then t = lo and math.max(FALLBACK, lo * 1.25) or FALLBACK end
  if lo and t < lo then t = lo * 1.05 end
  return math.max(10, math.min(t, 3600))
end
-- how long "not back yet" may keep counting for this mob before it means "came back somewhere else"
local function loLimit(src)
  local t = timed(src)
  return t and t * LO_TRUST or LO_MAX
end

function SP.OnCooldown(p)
  local k = SP.Key(p)
  local c = k and cds()[k]
  if not c then return false end
  if now() >= c.untl then cds()[k] = nil return false end
  return true, c.untl - now()
end
function SP.Cool(p, why, secs)
  local k = SP.Key(p)
  if not k then return end
  local src = source(p)
  secs = secs or SP.Respawn(src)
  if src and lastResp[src] == nil then lastResp[src] = SP.Respawn(src) end
  cds()[k] = { untl = now() + secs, t = now(), why = why, src = src, i = p.i, x = p.x, y = p.y }
  if why == "used" then cds()[k].used = now() end
  SP.dirty = true
  Q:Debug(("spot on cooldown (%s) for %ds: %s"):format(why, secs, k))
end

-- ------------------------------------------------------------------ choosing the spot
local current            -- the spot the arrow is on, kept until a clearly better one comes up
local function nextPoint(index)
  local nxt = P.steps and P.steps[(index or 1) + 1]
  return nxt and nxt.point
end
-- pts: { {p, id, li}, ... }; returns the entry to point at
function SP.Choose(entries, here, index)
  if #entries == 0 then return end
  here = here or entries[1].p
  local toward = nextPoint(index)
  local open, soonest, soonestLeft = {}, nil, nil
  for _, e in ipairs(entries) do
    local cool, left = SP.OnCooldown(e.p)
    if cool then
      if not soonestLeft or left < soonestLeft then soonest, soonestLeft = e, left end
    else
      open[#open + 1] = e
    end
  end
  -- calibrating a respawn: stay on that spot
  if SP.calib then
    for _, e in ipairs(entries) do
      if SP.Key(e.p) == SP.calib.key then
        if not current or current.p ~= e.p then SP.changed = true end
        current = e
        return e
      end
    end
  end
  -- every spot is on cooldown: the one that's back first
  if #open == 0 then return soonest end
  local function score(e)
    local d = D.Dist(here, e.p)
    if toward and toward.i == e.p.i then d = d + LEAN * D.Dist(e.p, toward) end
    return d
  end
  local best, bs
  for _, e in ipairs(open) do
    local sc = score(e)
    if not bs or sc < bs then best, bs = e, sc end
  end
  -- keep the spot you're heading to unless the new one is clearly better
  if current and current.p ~= best.p then
    for _, e in ipairs(open) do
      if e.p == current.p then
        if bs > score(e) * KEEP - 10 then best = e end
        break
      end
    end
  end
  if not current or current.p ~= best.p then SP.changed = true end
  current = best
  return best
end
function SP.Current() return current end

-- ------------------------------------------------------------------ watching what happens at the spot
local counts = {}        -- [questID][line] = numFulfilled last seen
local function snapshot(id)
  local e = QS.log and QS.log[id]
  local out = {}
  for li, o in ipairs(e and e.objectives or {}) do out[li] = tonumber(o.numFulfilled) or (o.finished and 1 or 0) end
  return out
end

-- the mob / object of the spot is there (a nameplate of that npc; the object in front of you)
-- how close a unit is: true / false within about yd yards, nil when the game won't say
local function within(tok, yd)
  if not CheckInteractDistance then return nil end
  local ok, r = pcall(CheckInteractDistance, tok, yd <= 11 and 2 or 4)
  if not ok or r == nil or S(r) then return nil end
  return r and true or false
end
-- every unit Questicus can look at: nameplates (mobs, and objects with one), soft targets, target, mouse
local function units()
  local out = { "softenemy", "softinteract", "softfriend", "target", "mouseover" }
  if C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local tok = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      if type(tok) == "string" and not S(tok) then out[#out + 1] = tok end
    end
  end
  return out
end
-- is the spot's mob / object there? true = seen (alive, within `near` yards when the game says how
-- far), false = looked and it isn't, nil = can't tell (no source known)
local function present(src, near)
  if not src then return nil end
  local kind = src:sub(1, 1)
  near = near or UNDER
  if kind == "o" and Q.Glow and Q.Glow.Find then pcall(Q.Glow.Find) end
  for _, tok in ipairs(units()) do
    local okE, ex = pcall(UnitExists, tok)
    if okE and ex and not S(ex) and Q.UnitKey(tok) == src then
      local dead = UnitIsDead and UnitIsDead(tok)
      if not (dead and not S(dead)) then
        if kind == "o" then return true end               -- objects show only up close / in front
        local w = within(tok, near)
        if w ~= false then return true end
      end
    end
  end
  if kind == "o" and Q.Glow and Q.Glow.Unit then
    local u = Q.Glow.Unit()
    if u and Q.UnitKey(u) == src then return true end
  end
  return false
end
SP.Present = present

-- ------------------------------------------------------------------ seeing spawns from a distance
-- With enemy nameplates on, every mob within nameplate range has one. A spot that close whose mob has
-- no live nameplate anywhere around you is empty: no need to walk onto every marker to find out.
-- (Nameplates show through walls and hills too.) Not for objects - they only show up close.
local function plateRange()
  local d = GetCVar and tonumber(GetCVar("nameplateMaxDistance") or "")
  d = d or 41
  return math.max(15, math.min(d, 60) - 5)
end
local function platesOn()
  if not GetCVarBool then return false end
  local ok, on = pcall(GetCVarBool, "nameplateShowEnemies")
  return ok and on and not S(on) and true or false
end
SP.PlatesOn, SP.PlateRange = platesOn, plateRange
-- live mobs in view, by source ("c123" = n); mobs someone else tagged don't count
local seenNow = {}
local function inView()
  wipe(seenNow)
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return seenNow end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local tok = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if type(tok) == "string" and not S(tok) then
      local k = Q.UnitKey(tok)
      if k then
        local dead = UnitIsDead and UnitIsDead(tok)
        local taken = UnitIsTapDenied and UnitIsTapDenied(tok)
        if not (dead and not S(dead)) and not (taken and not S(taken)) then seenNow[k] = (seenNow[k] or 0) + 1 end
      end
    end
  end
  return seenNow
end
SP.InView = inView
-- a mob for one of these spots that you can see right now (nameplate, target, soft target, mouseover):
-- returns its source and whether it's close (within ~28 yd when the game says), else nil
function SP.Visible(entries)
  local want
  for _, e in ipairs(entries or {}) do
    local src = source(e.p)
    if src and src:sub(1, 1) == "c" then want = want or {}; want[src] = true end
  end
  if not want then return nil end
  local best, bestClose
  for _, tok in ipairs(units()) do
    local okE, ex = pcall(UnitExists, tok)
    if okE and ex and not S(ex) then
      local k = Q.UnitKey(tok)
      if k and want[k] then
        local dead = UnitIsDead and UnitIsDead(tok)
        local taken = UnitIsTapDenied and UnitIsTapDenied(tok)
        if not (dead and not S(dead)) and not (taken and not S(taken)) then
          local close = within(tok, 28) == true
          if close and not bestClose then best, bestClose = k, true
          elseif not best then best = k end
        end
      end
    end
  end
  return best, bestClose
end
local unseen = {}        -- [spot key] = GetTime() since its mob hasn't been in view while you were close
local GONE_AFTER = 1.5   -- seconds in range with no live nameplate of its mob
local tipShown
local function farScan(here)
  local entries = SP.entries
  if not entries or #entries == 0 then return end
  if not platesOn() then
    if not tipShown and current and source(current.p) and source(current.p):sub(1, 1) == "c" then
      tipShown = true
      Q:Print("tip: turn on enemy nameplates (default key V) - Questicus then sees from a distance which spawns are up and skips the empty ones.")
    end
    return
  end
  local r = plateRange()
  local view = inView()
  local t = GetTime()
  for _, e in ipairs(entries) do
    local src = source(e.p)
    if src and src:sub(1, 1) == "c" and e.p.i == here.i then
      local k = SP.Key(e.p)
      local d = D.Dist(here, e.p)
      if d <= r and not (view[src]) then
        if not SP.OnCooldown(e.p) then
          unseen[k] = unseen[k] or t
          if t - unseen[k] >= GONE_AFTER and not (SP.calib and SP.calib.key == k) then
            SP.Cool(e.p, "gone")
            unseen[k] = nil
            SP.changed = true
          end
        end
      else
        unseen[k] = nil
        -- its mob is in view again: spots near you skipped from a distance are worth a look (not ones you
        -- stood on and found empty - that would send you round in circles)
        if d <= r and view[src] then
          local c = cds()[k]
          if c and c.why == "gone" then cds()[k] = nil; SP.changed = true end
        end
      end
    end
  end
end
SP.FarScan = farScan

-- ------------------------------------------------------------------ new spawn points
-- A mob of a quest in your log standing next to you (about 10 yd, out of combat - not chasing you):
-- where you stand is its spawn. More than 30 yd from every known spawn -> a new one (Data.lua D:AddSpawn).
local questMobs, questMobsVer
local function mobsOfLog()
  if questMobs and questMobsVer == (Q.Guide and Q.Guide.tver) then return questMobs end
  questMobs, questMobsVer = {}, Q.Guide and Q.Guide.tver
  for id in pairs(QS.log or {}) do
    local m = P.Meta and P.Meta(id)
    for _, l in ipairs(m and m.lines or {}) do
      if l.kind == "kill" and l.key then questMobs[l.key] = true end
      for _, k in ipairs(l.srcs or {}) do questMobs[k] = true end
      if l.mob and l.from then questMobs[l.from] = true end
    end
  end
  return questMobs
end
local spawnTried = {}
local function spawnScan(here)
  local mobs = mobsOfLog()
  if not next(mobs) then return end
  local t = GetTime()
  for _, tok in ipairs(units()) do
    local okE, ex = pcall(UnitExists, tok)
    if okE and ex and not S(ex) then
      local k = Q.UnitKey(tok)
      if k and mobs[k] and t - (spawnTried[k] or 0) >= 5 then
        local dead = UnitIsDead and UnitIsDead(tok)
        local fighting = UnitAffectingCombat and UnitAffectingCombat(tok)
        if not (dead and not S(dead)) and not (fighting and not S(fighting)) and within(tok, 10) == true then
          spawnTried[k] = t
          D:AddSpawn(k, here)
        end
      end
    end
  end
end
SP.SpawnScan = spawnScan

-- a respawn measured: the spot was used at t0 and its mob / object is back
-- ------------------------------------------------------------------ objects that don't respawn on a timer
-- Some quest objects only appear when you do something (use an item on a mob and kill it: Broodling
-- Essence): no respawn time to measure, no calibrating. They're told apart by:
--  * no fixed spawn in the database (spw: the world's placed objects), or
--  * picked up right after a kill (your target lies dead) or after using an item / the quest item.
-- Remembered per object (Q.db.osummon) and recorded (QuesticusCollect.osummon) for the database.
local lastItemUse = 0
if UseContainerItem then hooksecurefunc("UseContainerItem", function() lastItemUse = GetTime() end) end
if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", function() lastItemUse = GetTime() end) end
if UseItemByName then hooksecurefunc("UseItemByName", function() lastItemUse = GetTime() end) end
Q:On("QC_READY", function()
  local b = _G.QuesticusQuestItem
  if b and b.HookScript then b:HookScript("PostClick", function() lastItemUse = GetTime() end) end
end)
function SP.IsSummoned(src)
  if not (src and src:sub(1, 1) == "o") then return false end
  Q.db.osummon = type(Q.db.osummon) == "table" and Q.db.osummon or {}
  if Q.db.osummon[src] then return true end
  local shared = D.db and D.db.osummon and D.db.osummon[src]
  if shared then return true end
  return not (D.db and D.db.spw and D.db.spw[src])          -- not a placed object
end
-- at a pickup: did it just appear because of what you did?
local function noteSummoned(src)
  if not (src and src:sub(1, 1) == "o") then return false end
  local dead = UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target")
  if (dead and not Q.Secret(dead)) or GetTime() - lastItemUse < 60 then
    Q.db.osummon = type(Q.db.osummon) == "table" and Q.db.osummon or {}
    Q.db.osummon[src] = true
    if QuesticusCollect and Q.db.collect ~= false then
      QuesticusCollect.osummon = type(QuesticusCollect.osummon) == "table" and QuesticusCollect.osummon or {}
      QuesticusCollect.osummon[src] = (QuesticusCollect.osummon[src] or 0) + 1
    end
    return true
  end
  return SP.IsSummoned(src)
end
SP.NoteSummoned = noteSummoned

-- the respawn time changed: every cooldown of that mob / object is re-timed at once, so the arrow (and
-- which spots it skips) follows what was just learned
local function retime(src)
  if not src then return end
  local secs = SP.Respawn(src)
  -- a big change (a quarter or more): the route's time for quests with that mob is worked out again
  local was = lastResp[src]
  lastResp[src] = secs
  if was and math.abs(secs - was) >= was * 0.25 and P and P.Replan then
    Q.Throttle("respreplan", 20, function() P:Replan(5) end)
  end
  for _, c in pairs(cds()) do
    if c.src == src then
      local untl = (c.used or c.t or now()) + secs
      if untl ~= c.untl then c.untl = untl; SP.changed = true end
    end
  end
end
SP.Retime = retime
local MIN_RESP = 20       -- seconds: "back" sooner than this is another one of them wandering past
local function measured(src, secs)
  local r = rec()
  if not (r and src) or secs < MIN_RESP or secs > 3600 then return end
  if SP.IsSummoned(src) then return end
  local e = r[src] or { n = 0, s = 0 }
  -- (seen back after this long: it can't be more than this; keep the shortest few)
  e.n, e.s = e.n + 1, e.s + secs
  e.min = e.min and math.min(e.min, secs) or secs
  r[src] = e
  Q:Debug(("respawn measured for %s: %ds (avg %ds over %d)"):format(src, secs, math.floor(e.s / e.n), e.n))
  retime(src)
end
-- not back yet this long after it was used: the respawn is longer than that
local function notYet(src, secs)
  local r = rec()
  if not (r and src) or secs < 5 or secs > loLimit(src) then return end
  if SP.IsSummoned(src) then return end
  local e = r[src] or { n = 0, s = 0 }
  if not e.lo or secs > e.lo + 2 then
    e.lo = secs
    r[src] = e
    retime(src)
  end
end
-- found back this long after it was used (you weren't watching before): the respawn is at most that
local function backBy(src, secs)
  local r = rec()
  if not (r and src) or secs < MIN_RESP or secs > 3600 then return end
  if SP.IsSummoned(src) then return end
  local e = r[src] or { n = 0, s = 0 }
  if not e.hi or secs < e.hi then
    e.hi = secs
    r[src] = e
    retime(src)
  end
end
SP.Measured, SP.NotYet, SP.BackBy = measured, notYet, backBy

local atSince, atKey
local lastPos, lastPosAt, stillFor = nil, nil, 0
local function tick()
  if not (Q.char and Q.char.surveyDone) or (Q.CollectOnly and Q.CollectOnly()) then return end
  local here = D:PlayerPos()
  if not here then return end
  if SP.calib and SP.CalibTick then SP.CalibTick(here) end
  -- spots on cooldown near you: back early (respawned) or still gone after their cooldown
  -- (with enemy nameplates on, a mob's spot within nameplate range shows whether it's back from afar:
  -- no live nameplate of it = not back yet, the respawn is longer than the time since you killed it)
  local plates = platesOn()
  local view = plates and inView() or nil
  local range = plateRange()
  local t = now()
  for k, c in pairs(cds()) do
    local d = c.i == here.i and c.x and D.Dist(here, c)
    if d and d <= ARRIVE and c.src then
      local seen = present(c.src, UNDER)
      if seen == true then
        if c.used then measured(c.src, t - c.used) end
        cds()[k] = nil
        SP.dirty = true
      elseif c.used and seen == false and t - (c.ny or 0) >= 5 then
        c.ny = t
        notYet(c.src, t - c.used)
      end
    elseif d and c.used and c.src and view and d <= range and c.src:sub(1, 1) == "c"
        and not view[c.src] and t - (c.ny or 0) >= 5 then
      c.ny = t
      notYet(c.src, t - c.used)
    end
    if cds()[k] and t >= c.untl then cds()[k] = nil end
  end
  pcall(farScan, here)
  pcall(spawnScan, here)
  -- standing still? (a marker you can't quite reach still counts once you stop next to it)
  if lastPos and D.Dist(here, lastPos) < 1.5 then stillFor = stillFor + (GetTime() - (lastPosAt or GetTime()))
  else stillFor = 0 end
  lastPos, lastPosAt = here, GetTime()
  -- the spot the arrow is on: only once you're on its marker, look for what should be there
  local e = current
  local d = e and e.p and D.Dist(here, e.p)
  local onIt = d and (d <= EXACT or (d <= STUCK and stillFor >= 2))
  if not onIt then atSince, atKey = nil, nil return end
  local k = SP.Key(e.p)
  if atKey ~= k then atSince, atKey = GetTime(), k end
  local src = source(e.p)
  local seen = present(src, UNDER)
  -- a spot used before, come back to after its cooldown, still empty: the respawn is longer
  local last = SP.lastUsed and SP.lastUsed[k]
  if seen == false and last then notYet(src, now() - last) end
  if seen == true then
    if last then backBy(src, now() - last); SP.lastUsed[k] = nil end
    atSince = GetTime() return                           -- it's there: go get it
  end
  if SP.calib and SP.calib.key == k then return end      -- waiting for it on purpose
  local wait = (src and src:sub(1, 1) == "o") and SCAN_O or SCAN_C
  if GetTime() - atSince >= wait then
    SP.Cool(e.p, "empty")
    atSince, atKey = nil, nil
    SP.Kick()
  end
end

SP.Tick = tick

-- progress on the quest the arrow's spot is for, near that spot: that one is used
local function onProgress()
  local e = current
  if not e then return end
  local before = counts[e.id] or {}
  local after = snapshot(e.id)
  counts[e.id] = after
  local gained = (after[e.li] or 0) > (before[e.li] or 0)
  if not gained then
    -- (a line without its own number: any line of the quest)
    for li, v in pairs(after) do if v > (before[li] or 0) then gained = true break end end
  end
  if not gained then return end
  local here = D:PlayerPos()
  -- the nearest spot of the same objective to where you are gets the cooldown
  local best, bd
  for _, ent in ipairs(SP.entries or {}) do
    if ent.id == e.id then
      local d = D.Dist(here, ent.p)
      if not bd or d < bd then best, bd = ent, d end
    end
  end
  if best and bd <= NEAR then
    if SP.calib and SP.calib.key == SP.Key(best.p) then
      SP.Calibrated("collected")
      return
    end
    SP.Cool(best.p, "used")
    SP.lastUsed = SP.lastUsed or {}
    SP.lastUsed[SP.Key(best.p)] = now()
    if not noteSummoned(source(best.p)) then SP.MaybeCalibrate(best.p) end
    SP.Kick()
  end
end
Q:On("QC_QUESTS_CHANGED", function() pcall(onProgress) end)
Q:On("QUEST_ACCEPTED", function(a, b)
  local id = b or a
  if type(id) == "number" then counts[id] = snapshot(id) end
end)

-- ------------------------------------------------------------------ calibrating a quest object's respawn
-- A quest object nobody has a respawn time for yet: once (ever, per object), ask to wait at it. The
-- wait ends when it's back (seen in front of you) or collected again at that spot; that time is the
-- respawn, saved for the database so nobody has to do it again.
local function known(src)
  local own = QuesticusCollect and QuesticusCollect.resp and QuesticusCollect.resp[src]
  return (own and (own.n or 0) > 0) or (D.db and D.db.resp and D.db.resp[src]) and true or false
end
SP.Known = known
local function asked()
  Q.db.calibAsked = type(Q.db.calibAsked) == "table" and Q.db.calibAsked or {}
  return Q.db.calibAsked
end

local pop
local function fmt(secs)
  secs = math.max(0, math.floor(secs))
  return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end
local function buildPop()
  local T = Q.T
  pop = T.Window("QuesticusCalibrate", 360, 178, "Help calibrate Questicus")
  pop:SetFrameStrata("HIGH")
  pop:ClearAllPoints(); pop:SetPoint("TOP", 0, -160)
  pop.text = T.Text(pop, 12, T.c.text)
  pop.text:SetPoint("TOPLEFT", 16, -36); pop.text:SetPoint("TOPRIGHT", -16, -36)
  pop.text:SetJustifyH("LEFT")
  pop.text:SetSpacing(2)
  pop.timer = T.Text(pop, 13, T.c.gold)
  pop.timer:SetPoint("BOTTOMLEFT", 16, 46)
  pop.yes = T.Button(pop, "I'll wait here", 130, 24)
  pop.yes:SetPoint("BOTTOMLEFT", 16, 14)
  pop.no = T.Button(pop, "Not now", 100, 24)
  pop.no:SetPoint("BOTTOMRIGHT", -16, 14)
  pop.yes:SetScript("OnClick", function()
    if SP.calib then
      SP.calib.waiting = true
      pop.yes:Hide()
      pop.no.label:SetText("Stop")
    end
  end)
  pop.no:SetScript("OnClick", function() SP.StopCalibrate(true) end)
  pop.close:SetScript("OnClick", function() SP.StopCalibrate(true) end)
  pop:SetScript("OnUpdate", function()
    local c = SP.calib
    if not c then pop:Hide() return end
    pop.timer:SetText(c.waiting and ("Waiting: " .. fmt(now() - c.t0)) or "")
  end)
end

function SP.MaybeCalibrate(p)
  local src = source(p)
  if not src or src:sub(1, 1) ~= "o" or SP.calib then return end          -- quest objects only
  if not rec() or known(src) or asked()[src] then return end              -- once ever, per object
  if SP.IsSummoned(src) then return end                                   -- appears when you do something
  if Q.CollectOnly and Q.CollectOnly() then return end
  asked()[src] = time()
  SP.calib = { p = p, key = SP.Key(p), src = src, t0 = now() }
  if not pop then buildPop() end
  local name = (D.Name and D:Name(src)) or "This object"
  pop.text:SetText(("|cffe0b04a%s|r's respawn timer isn't in the database yet.\n\nPlease stand here and wait for it to respawn to calibrate Questicus to this quest. Keep facing the spot - Questicus sees it come back and saves the time.\n\nThis only happens once, ever, and you're helping everyone else never have to do it."):format(name))
  pop:SetHeight(math.max(178, (pop.text:GetStringHeight() or 100) + 110))
  pop.yes:Show(); pop.no.label:SetText("Not now")
  pop:Show()
  SP.changed = true
end

function SP.StopCalibrate(byPlayer)
  if not SP.calib then return end
  SP.calib = nil
  if pop then pop:Hide() end
  if byPlayer then Q:Print("calibration stopped - the respawn time is still measured whenever it's seen back") end
  SP.changed = true
end

function SP.Calibrated(how)
  local c = SP.calib
  if not c then return end
  local secs = now() - c.t0
  measured(c.src, secs)
  SP.calib = nil
  if pop then pop:Hide() end
  local name = (D.Name and D:Name(c.src)) or "it"
  Q:Print(("%s respawns in %s - saved for everyone. Thank you!"):format(name, fmt(secs)))
  -- (the spot was just collected again: it's on cooldown for the time measured)
  if how == "collected" then SP.Cool(c.p, "used", secs) end
  SP.changed = true
end

-- watching the calibrated spot: back in front of you, picked up again, or you left
local function calibTick(here)
  local c = SP.calib
  if not c then return end
  local d = D.Dist(here, c.p)
  if d > 150 then
    SP.calib = nil
    if pop then pop:Hide() end
    Q:Print("calibration stopped - you left the spot")
    SP.changed = true
    return
  end
  if d <= ARRIVE + 10 and now() - c.t0 >= 5 and present(c.src) == true then SP.Calibrated("seen") end
end
SP.CalibTick = calibTick
-- picked up again (the quest may be finished by now, so no quest progress): the loot window's object
Q:On("LOOT_OPENED", function()
  local c = SP.calib
  if not c or not GetNumLootItems then return end
  for slot = 1, GetNumLootItems() or 0 do
    local ok, guid = pcall(GetLootSourceInfo, slot)
    if ok and type(guid) == "string" and not S(guid) then
      local kind, id = Q.ParseGUID(guid)
      if kind == "GameObject" and "o" .. tostring(id) == c.src then
        local here = D:PlayerPos()
        if here and D.Dist(here, c.p) <= NEAR then SP.Calibrated("collected") end
        return
      end
    end
  end
end)

-- the arrow / map / waypoint pick a new spot
function SP.Kick()
  if SP.dirty or SP.changed then
    SP.dirty = false
    Q.Throttle("spotkick", 0.3, function() Q:Send("QC_TARGET_CHANGED") end)
  end
end

local acc = 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.5 then return end
  acc = 0
  pcall(tick)
  if SP.changed then SP.changed = false; SP.Kick() end
end)

-- recordings from before these checks: timings shorter than MIN_RESP (another mob wandering past) and
-- "not back yet" stretched far past the timed respawn are dropped once
Q:On("QC_READY", function()
  local r = QuesticusCollect and QuesticusCollect.resp
  if type(r) ~= "table" then return end
  for src, e in pairs(r) do
    if type(e) == "table" then
      if (e.n or 0) > 0 and (e.s or 0) / e.n < MIN_RESP then e.n, e.s, e.min = 0, 0, nil end
      if e.hi and e.hi < MIN_RESP then e.hi = nil end
      local t = timed(src)
      if e.lo and ((t and e.lo > t * LO_TRUST) or (not t and e.lo > LO_MAX)) then e.lo = nil end
    end
  end
  for _, c in pairs(cds()) do if c.src then c.untl = math.min(c.untl, (c.used or c.t or now()) + SP.Respawn(c.src)) end end
end)

Q:Command("respawn", "objective spots on cooldown and respawn times (/qc respawn reset)", function(arg)
  if arg == "reset" then wipe(cds()); SP.Kick(); Q:Print("objective spot cooldowns cleared") return end
  local n = 0
  for k, c in pairs(cds()) do
    n = n + 1
    if n <= 10 then Q:Print(("%s: %s, back in %ds"):format(k, c.why or "?", math.max(0, c.untl - now()))) end
  end
  local src = current and source(current.p)
  Q:Print(("%d spots on cooldown%s"):format(n, src and (" - this spot respawns in about %ds"):format(math.floor(SP.Respawn(src))) or ""))
end)
