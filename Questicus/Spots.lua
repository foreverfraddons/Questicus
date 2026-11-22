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

local ARRIVE = 25          -- yards: standing at the spot
local NEAR = 60            -- yards: progress here counts for the spot
local EMPTY_WAIT = 5       -- seconds at a spot with nothing there before it's called empty
local FALLBACK = 60        -- seconds: respawn time nobody has measured yet
local LEAN = 0.35          -- how much the next step pulls the choice (0 = just the closest)
local KEEP = 0.8           -- a new spot must be this much closer to take over (no flip-flopping)

local function now() return time() end
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
function SP.Respawn(src)
  local own = src and QuesticusCollect and QuesticusCollect.resp and QuesticusCollect.resp[src]
  local shared = src and D.db and D.db.resp and D.db.resp[src]
  local t
  if own and (own.n or 0) > 0 then
    t = own.s / own.n
    if shared and (own.n or 0) < 3 then t = (t * own.n + shared * 3) / (own.n + 3) end
  elseif shared then
    t = shared
  end
  -- "it wasn't back yet after this long": never wait less than that again
  local lo = own and own.lo
  if not t then t = lo and math.max(FALLBACK, lo * 1.25) or FALLBACK end
  if lo and t < lo then t = lo * 1.1 end
  return math.max(10, math.min(t, 3600))
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
local function present(src)
  if not src then return nil end
  local kind, id = src:sub(1, 1), tonumber(src:sub(2))
  -- enemy nameplates off: mobs can't be seen this way, so nothing is concluded
  if kind == "c" and GetCVarBool and not GetCVarBool("nameplateShowEnemies") then return nil end
  if kind == "c" and C_NamePlate and C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local tok = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      if tok and not S(tok) then
        local k = Q.UnitKey(tok)
        local dead = UnitIsDead and UnitIsDead(tok)
        if k == src and not (dead and not S(dead)) then return true end
      end
    end
    return false
  end
  if kind == "o" and Q.Glow and Q.Glow.Find then
    local ok = pcall(Q.Glow.Find)
    local unit = ok and Q.Glow.Unit and Q.Glow.Unit()
    if unit and Q.UnitKey(unit) == src then return true end
    return nil          -- objects only show when in front of you: not seeing it proves nothing
  end
end
SP.Present = present

-- a respawn measured: the spot was used at t0 and its mob / object is back
local function measured(src, secs)
  local r = rec()
  if not (r and src) or secs < 5 or secs > 3600 then return end
  local e = r[src] or { n = 0, s = 0 }
  -- (seen back after this long: it can't be more than this; keep the shortest few)
  e.n, e.s = e.n + 1, e.s + secs
  e.min = e.min and math.min(e.min, secs) or secs
  r[src] = e
  Q:Debug(("respawn measured for %s: %ds (avg %ds over %d)"):format(src, secs, math.floor(e.s / e.n), e.n))
end
-- not back yet this long after it was used: the respawn is longer than that
local function notYet(src, secs)
  local r = rec()
  if not (r and src) or secs < 5 then return end
  local e = r[src] or { n = 0, s = 0 }
  if not e.lo or secs > e.lo then e.lo = secs end
  r[src] = e
end

local atSince, atKey
local function tick()
  if not (Q.char and Q.char.surveyDone) or (Q.CollectOnly and Q.CollectOnly()) then return end
  local here = D:PlayerPos()
  if not here then return end
  -- spots on cooldown near you: back early (respawned) or still gone after their cooldown
  for k, c in pairs(cds()) do
    if c.i == here.i and c.x and D.Dist(here, c) <= ARRIVE and c.src then
      local seen = present(c.src)
      if seen == true then
        if c.used then measured(c.src, now() - c.used) end
        cds()[k] = nil
        SP.dirty = true
      end
    elseif now() >= c.untl then
      cds()[k] = nil
    end
  end
  -- the spot the arrow is on
  local e = current
  if not (e and e.p) or D.Dist(here, e.p) > ARRIVE then atSince, atKey = nil, nil return end
  local k = SP.Key(e.p)
  if atKey ~= k then atSince, atKey = GetTime(), k end
  local src = source(e.p)
  local seen = present(src)
  -- a spot used before, come back to after its cooldown, still empty: the respawn is longer
  local last = SP.lastUsed and SP.lastUsed[k]
  if seen == false and last then notYet(src, now() - last) end
  if seen == true then atSince = GetTime() return end    -- it's there: go get it
  if GetTime() - atSince >= EMPTY_WAIT then
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
    SP.Cool(best.p, "used")
    SP.lastUsed = SP.lastUsed or {}
    SP.lastUsed[SP.Key(best.p)] = now()
    SP.Kick()
  end
end
Q:On("QC_QUESTS_CHANGED", function() pcall(onProgress) end)
Q:On("QUEST_ACCEPTED", function(a, b)
  local id = b or a
  if type(id) == "number" then counts[id] = snapshot(id) end
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
