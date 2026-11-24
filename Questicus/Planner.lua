-- Questicus route planner.
-- Simulates the next stretch of questing from the live state (position, level, quest log) and
-- picks, step by step, the action with the most value per second of travel + work:
--   accept a quest, do objectives (bundled with every other quest whose objectives are in the same
--   area), turn in, or buy a gear upgrade from a vendor on the way.
-- Value = estimated XP (+ kill XP) weighted by the survey answers, plus gear upgrades, reputation
-- and completionist bonuses. Because each step is re-planned from the real state, the route keeps
-- itself up to date: the moment you accept, finish or turn in something, the guide moves on.
local Q = Questicus
local P = {}
Q.Planner = P
local D, QS, G = Q.Data, Q.Quests, Q.Gear

P.MAX_STEPS = 60
local WALK, MOUNT = 7, 11.2          -- yards per second
local CROSS = 2400                    -- seconds for a boat / zeppelin trip to another continent (and back)
local BUNDLE = 220                    -- objective areas this close are done together
local NEAR = 30                       -- talking to someone this close counts as "here"
local DVALUE = 1000                  -- dungeon mode: every quest of the dungeon is worth the same

-- uiMaps of zones WoW Forever added (Mount Hyjal, Zephras Isle, Riverglades)
P.FOREVER_MAPS = { [2482] = true, [2521] = true, [2548] = true }

-- per-build memo: values that don't change while one route is being worked out (cleared at the
-- start of every Build; outside a build nothing is cached)
local B
-- route building can run in slices (a few ms per frame) so a replan never freezes the game
local SLICE = 6
local function now() return debugprofilestop and debugprofilestop() or 0 end
local function maybeYield()
  if P.co and coroutine.running() == P.co and now() - (P.sliceStart or 0) > SLICE then coroutine.yield() end
end
P.MaybeYield = maybeYield
local function memo(tbl, key, f, ...)
  if not B then return f(...) end
  local t = B[tbl]
  if not t then t = {}; B[tbl] = t end
  local v = t[key]
  if v == nil then v = f(...); t[key] = v == nil and false or v end
  if v == false then return nil end
  return v
end
P.memo = memo

-- yards per second: what you really move at once learned (moving time only, Learn.lua), else the
-- usual run / mount speed
local function rawSpeed(mounted)
  local L = Q.Learn
  return (L and L:Speed(mounted)) or (mounted and MOUNT or WALK)
end
local function speed(level)
  local mounted = (level or 1) >= 40
  return memo("speed", mounted, rawSpeed, mounted)
end
P.Speed = speed

local function travel(a, b, level)
  if not a or not b then return CROSS end
  local sp = speed(level)
  if a.i ~= b.i then
    -- another continent: the boat / zeppelin there (remembered per build: it's asked a lot)
    local row = B and B.cross and B.cross[a]
    local v = row and row[b]
    if v then return v end
    local x = Q.Flight and Q.Flight.Cross and Q.Flight:Cross(a, b, sp, P.dset ~= nil)
    v = x and x.t or CROSS
    if B then
      B.cross = B.cross or {}
      B.cross[a] = B.cross[a] or {}
      B.cross[a][b] = v
    end
    return v
  end
  -- real walks are longer than the straight line: learned per zone from your own walks (Paths.lua)
  local k = Q.Paths and Q.Paths.Factor(P.MapOf(a)) or 1
  -- zone borders (mountains, walls, sea) between the two: the way round them (ForeverDB zbord)
  local d = D.Dist(a, b)
  local walk = math.max(d * k, D.WalkDist(a, b), d + (D.BorderExtra and D.BorderExtra(a, b) or 0)) / sp
  -- a flight is faster for the long legs (Flight.lua: known flight masters only)
  if walk > 60 and Q.Flight then
    local leg = Q.Flight:Leg(a, b, sp, P.dset ~= nil)
    if leg then return leg.t end
  end
  return walk
end

-- ------------------------------------------------------------------ objective times
-- How many of a thing an objective needs: the live quest log, what was seen before (any character),
-- else a typical number.
local DEFAULT_N = { kill = 8, loot = 6, use = 3, buy = 1, explore = 1 }
function P.Count(id, name, kind)
  local e = QS.log[id]
  for _, o in ipairs(e and e.objectives or {}) do
    if o.text and name and o.numRequired and o.numRequired > 0 and o.text:lower():find(name:lower(), 1, true) then
      return o.numRequired
    end
  end
  local seen = QuesticusCollect and QuesticusCollect.qn and QuesticusCollect.qn[id]
  if seen and name and seen[name] then return seen[name] end
  return DEFAULT_N[kind] or 1
end

-- seconds for one objective line (frac = share still to do), at player level lv
function P.LineTime(m, l, lv, frac)
  frac = frac or 1
  local L = Q.Learn
  local n = (l.n or 1) * frac
  local t
  if l.kind == "kill" or (l.kind == "loot" and l.mob) then
    local ttk = L and L:TTK((l.mlvl or lv) - lv) or 12
    if m.elite then ttk = ttk * 3 end
    local gap = L and L:Gap() or 14
    local kills = l.kind == "kill" and n or (n / math.max(0.12, l.chance or 0.35))
    t = kills * (ttk + gap)
    -- more kills than there are spawns: waiting for respawns (the respawn time measured live, Spots.lua)
    local key = l.kind == "kill" and l.key or (l.srcs and l.srcs[1]) or l.from
    if key and Q.Spots and Q.Spots.Respawn then
      if l.spawnN == nil then
        local c = 0
        for _, k in ipairs(l.kind == "kill" and { l.key } or (l.srcs or { key })) do c = c + #(D:Points(k) or {}) end
        l.spawnN = c
      end
      local sn = l.spawnN
      if sn > 0 and kills > sn then
        local rounds = math.ceil(kills / sn) - 1
        local wait = Q.Spots.Respawn(key) - sn * (ttk + gap)
        if wait > 0 then t = t + rounds * wait end
      end
    end
    t = math.min(1200, t)
  elseif l.kind == "loot" then
    t = math.min(600, n * 20)              -- objects / containers
  elseif l.kind == "buy" then t = 15
  elseif l.kind == "use" then t = n * 20
  elseif l.kind == "explore" then t = 10
  else t = 30 end
  return t
end
function P.LineKills(l, lv, frac)
  local n = (l.n or 1) * (frac or 1)
  if l.kind == "kill" then return n * QS.KillXP(l.mlvl or lv, lv) end
  if l.kind == "loot" and l.mob then
    return math.min(n / math.max(0.12, l.chance or 0.35), 30) * QS.KillXP(l.mlvl or lv, lv)
  end
  return 0
end
-- the whole quest: learned (time really spent on it, Learn.lua) or estimated
local questTime
function P.QuestTime(id, m, lv)
  return memo("qtime", id * 100 + (lv or 0), questTime, id, m, lv)
end
function questTime(id, m, lv)
  local t = m.extraT or 0
  for _, l in ipairs(m.lines or {}) do t = t + P.LineTime(m, l, lv) end
  if m.dungeon then t = math.max(t, 1500) end
  return t
end
function P.QuestKills(m, lv)
  local k = 0
  for _, l in ipairs(m.lines or {}) do k = k + P.LineKills(l, lv) end
  if m.dungeon then k = k + 30 * QS.KillXP(m.info.level, lv) end
  return k
end
-- what's left of a quest in your log: [line] = share still to do (0 = the quest's general spots)
function P.OpenLines(id, m)
  local e = QS.log[id]
  local open = {}
  if e and e.complete then return open end
  local matched, remainOf = {}, {}
  if e and e.objectives and #e.objectives > 0 then
    for _, o in ipairs(e.objectives) do
      local txt = (o.text or ""):lower()
      for li, l in ipairs(m.lines) do
        if not matched[li] and l.name and txt:find(l.name:lower(), 1, true) then
          matched[li] = true
          if not o.finished then
            local have, need = o.numFulfilled, o.numRequired
            if not need then have, need = txt:match("(%d+)%s*/%s*(%d+)") ; have, need = tonumber(have), tonumber(need) end
            open[li] = (need and need > 0 and have) and math.max(0.1, (need - have) / need) or 1
            if need and have then remainOf[li] = need - have end
          end
          break
        end
      end
    end
  end
  for li, l in ipairs(m.lines) do
    if not matched[li] and not l.part then open[li] = 1 end   -- not in the log (yet) / can't tell: still to do
  end
  -- parts: still needed while the objective they make isn't done and you don't carry enough of them
  for li, l in ipairs(m.lines) do
    if l.part then
      local objLi
      for lj, lo in ipairs(m.lines) do if lo.key == "i" .. tostring(l.forItem) then objLi = lj end end
      local objOpen = (objLi == nil) or open[objLi]
      local carry = P.ItemCount(l.part)
      local need = objLi and remainOf[objLi] or 1
      if objOpen and carry < math.max(1, need) then open[li] = 1 end
    end
  end
  -- objectives made from parts wait until you have them
  for li, l in ipairs(m.lines) do
    if l.after and open[li] then
      for _, pl in ipairs(l.after) do if open[pl] then open[li] = nil; break end end
    end
  end
  if m.lp and m.lp[0] then open[0] = 1 end
  -- a dungeon quest is one run: everything still open is done inside, in one go
  if m.dungeon then return next(open) and { [0] = 1 } or {} end
  return open
end
-- the spots still to visit for a quest in the log (finished objectives left out)
function P.OpenPoints(id)
  local m = P.Meta(id)
  if not (m and m.lp) then return {} end
  local out = {}
  for li in pairs(P.OpenLines(id, m)) do
    for _, p in ipairs(m.lp[li] or {}) do out[#out + 1] = p end
  end
  return out
end
-- the spots of a planned step: only the objectives that step is for
function P.StepPoints(s)
  local out = {}
  if not s or s.type ~= "complete" then return out end
  for _, part in ipairs(s.parts or {}) do
    local m = P.Meta(part.id)
    local e = QS.log[part.id]
    if m and m.lp and not (e and e.complete) then
      local live = e and P.OpenLines(part.id, m)
      for _, li in ipairs(part.lines) do
        if not live or live[li] then
          for _, p in ipairs(m.lp[li] or {}) do out[#out + 1] = { p = p, id = part.id, li = li } end
        end
      end
    end
  end
  return out
end

-- ------------------------------------------------------------------ per-quest planning data
local meta = {}   -- [questID] = { givers, enders, obj = {centre, radius, pts}, time, kills, text }
function P:Reset() wipe(meta) end
-- how long objectives really take you (learned while you play, Learn.lua): 1 = as estimated
local K = 1
function P.TimeK() return K end
local function effort(m)
  local work = P.WorkTime and m.id and P.WorkTime(m.id, m) or (m.time or 0) * K
  return m.effort - (m.time or 0) + work
end
function P.Effort(m)
  if not (m and m.effort) then return nil end
  return memo("effort", m.id or m, effort, m)
end
function P.ForgetMeta(id) meta[id] = nil end

local function points(keys)
  local out = {}
  for _, k in ipairs(keys or {}) do
    for _, p in ipairs(D:Points(k)) do
      p.key = p.key or k
      out[#out + 1] = p
    end
  end
  return out
end

local function questMeta(id)
  local m = meta[id]
  if m ~= nil then return m or nil end
  meta[id] = false
  local info = QS:Info(id)
  if not info then return end
  m = { info = info, id = id }
  m.givers = points(info.givers)
  m.enders = points(info.enders)
  if #m.givers == 0 and not info.startItem then return end
  if #m.enders == 0 then return end
  -- WoW Forever's new zones vs the classic (legacy) zones, as chosen in the survey
  local pr = Q.prefs
  if not (pr.forever and pr.legacy) and m.givers[1] then
    local map = D:MapPos(m.givers[1])
    local isNew = map and P.FOREVER_MAPS[map]
    if (isNew and not pr.forever) or (not isNew and map and not pr.legacy) then return end
  end
  local x = info.x
  -- every objective is a "line" with its own spots, so a finished objective drops out of the route
  -- and the parts of a quest that are far apart can be done at different times
  local objPts, lines, extraT = {}, {}, 0
  local cur = 0                          -- the line the spots being added belong to (0 = the quest)
  local function addPts(list, key)
    for _, p in ipairs(list) do
      objPts[#objPts + 1] = { i = p.i, x = p.x, y = p.y, m = p.m, mx = p.mx, my = p.my, dungeon = p.dungeon,
        key = p.key or key, li = cur }
    end
  end
  local function newLine(l)
    lines[#lines + 1] = l
    cur = #lines
    l.n = P.Count(id, l.name, l.kind)
    return l
  end
  for _, c in ipairs(x[8] or {}) do
    local key = "c" .. c
    local n = D:NPC(c)
    newLine({ kind = "kill", key = key, name = n and n[1] or key, mlvl = n and n[4] or info.level })
    addPts(D:Points(key), key)
  end
  for _, o in ipairs(x[9] or {}) do
    local key = "o" .. o
    newLine({ kind = "use", key = key, name = D:Name(key) })
    addPts(D:Points(key), key)
  end
  -- items: drops, objects, vendors, containers; plus the items you need to make them (qx 21)
  local function itemObjective(it, need)
    local srcs = D:ItemSources(it)          -- every mob / object / vendor that has it
    local best = srcs[1]
    local l
    if not need then
      l = newLine({ kind = (best and best.vendor) and "buy" or "loot", key = "i" .. it, name = D:Name("i" .. it),
        from = best and best.key, srcs = {} })
    else
      cur = 0
    end
    if best then
      for _, s in ipairs(srcs) do
        if s.chance >= (best.chance * 0.5) or s.vendor then
          addPts(D:Points(s.key), s.key)
          if l and s.key:sub(1, 1) == "c" and not s.vendor then l.srcs[#l.srcs + 1] = s.key end
        end
      end
      if l then
        local mob = best.key:sub(1, 1) == "c" and not best.vendor
        local n = mob and D:NPC(tonumber(best.key:sub(2)))
        l.mlvl = n and n[4] or info.level
        l.mob = mob
        l.chance = best.vendor and 1 or (best.chance > 0 and best.chance or 0.35)
        l.vendor = best.vendor
      elseif need then
        extraT = extraT + 30
      end
    end
    -- no known source: an item named after its owner ("Old Rot-Chum's Head") comes from that npc
    if not best then
      local owner = D:Name("i" .. it):match("^(.-)'s ")
      local ids = owner and D:NPCByName(owner)
      if ids then
        best = { key = "c" .. ids[1], chance = 1 }
        if l then l.from, l.mob, l.chance, l.srcs = best.key, true, 1, { best.key } end
        for _, nid in ipairs(ids) do addPts(D:Points("c" .. nid), "c" .. nid) end
        if l then local n = D:NPC(ids[1]); l.mlvl = n and n[4] or info.level end
      end
    end
    return best ~= nil
  end
  for _, it in ipairs(x[10] or {}) do itemObjective(it) end
  -- the parts you put together (qx 21) are a step of their own: get them first, then the objective
  -- (A Sample of Slime: Felwood Slime Sample from the oozes, before the Corrupted Felwood Sample)
  local partLines = {}
  for k, it in ipairs(x[21] or {}) do
    local before = #lines
    itemObjective(it)
    if #lines > before then
      local l = lines[#lines]
      l.part = it
      l.forItem = (x[10] and (#x[10] == #x[21] and x[10][k] or x[10][1])) or nil
      partLines[#partLines + 1] = #lines
    end
  end
  if #partLines > 0 then
    for li, l in ipairs(lines) do
      if not l.part and l.key and l.key:sub(1, 1) == "i" then
        local it = tonumber(l.key:sub(2))
        l.after = {}
        for _, pl in ipairs(partLines) do
          if not lines[pl].forItem or lines[pl].forItem == it then l.after[#l.after + 1] = pl end
        end
        if #l.after == 0 then l.after = nil end
      end
    end
  end
  -- what players really looted for this quest (recordings): with a single item objective, those
  -- mobs are its sources (Paletusk Harvesting: Young Paletusk, not the classic Duskwood boars)
  local rec = D:QuestSources(id)
  local lootLines = {}
  for li, l in ipairs(lines) do if l.kind == "loot" then lootLines[#lootLines + 1] = li end end
  if #rec > 0 and #lootLines == 1 then
    cur = lootLines[1]
    local l = lines[cur]
    for _, k in ipairs(rec) do
      addPts(D:Points(k), k)
      if k:sub(1, 1) == "c" then
        l.srcs = l.srcs or {}
        l.srcs[#l.srcs + 1] = k
        if not l.mob then l.mob, l.chance = true, 0.5 end
      end
    end
  end
  -- an objective with sources in several zones: the ones on the quest giver's map win (WoW Forever
  -- reuses classic items; their classic drops are elsewhere)
  local gmap = m.givers[1] and D:MapPos(m.givers[1]) or (m.enders[1] and D:MapPos(m.enders[1]))
  -- only lines whose spots are spread far apart can be in several zones: skip the map lookups otherwise
  local spread = {}
  for _, p in ipairs(objPts) do
    local li = p.li
    if li and li > 0 then
      local b = spread[li]
      if not b then b = { p.i, p.x, p.x, p.y, p.y, false }; spread[li] = b end
      if p.i ~= b[1] then b[6] = true end
      if p.x < b[2] then b[2] = p.x elseif p.x > b[3] then b[3] = p.x end
      if p.y < b[4] then b[4] = p.y elseif p.y > b[5] then b[5] = p.y end
    end
  end
  local wide = false
  for _, b in pairs(spread) do
    if b[6] or (b[3] - b[2]) > 2000 or (b[5] - b[4]) > 2000 then wide = true; break end
  end
  if gmap and wide then
    local onMap, any = {}, {}
    for _, p in ipairs(objPts) do
      if p.li and p.li > 0 then
        any[p.li] = true
        if D:MapPos(p) == gmap then onMap[p.li] = true end
      end
    end
    local keep = {}
    for _, p in ipairs(objPts) do
      if not (p.li and p.li > 0 and onMap[p.li]) or D:MapPos(p) == gmap then keep[#keep + 1] = p end
    end
    objPts = keep
  end
  cur = 0
  local trig = D:TriggerPoints(id)
  if #trig > 0 then
    newLine({ kind = "explore", key = "t" .. id, name = "Explore the area" })
    for _, p in ipairs(trig) do p.key = "t" .. id end
    addPts(trig, "t" .. id)
    cur = 0
  end
  -- hidden objectives (use the cannon ...): their spots and targets (qx 22 / 23)
  for map, pts in pairs(x[22] or {}) do
    for j = 1, #pts - 1, 2 do
      local inst, wx, wy = D:WorldPos(tonumber(map) or map, pts[j] / 1000, pts[j + 1] / 1000)
      if inst then objPts[#objPts + 1] = { i = inst, x = wx, y = wy, key = "t" .. id, li = 0 } end
    end
    extraT = math.max(extraT, 40)
  end
  for _, ref in ipairs(x[23] or {}) do
    if ref:sub(1, 1) ~= "i" then addPts(D:Points(ref), ref) end
  end
  -- objectives with no spots at all: where you (or other players) made progress on this quest, and
  -- for a quest in your log the game's own quest marker
  local missing = #lines == 0
  for li in ipairs(lines) do
    local has = false
    for _, p in ipairs(objPts) do if p.li == li then has = true; break end end
    if not has then missing = true end
  end
  if missing and #objPts > 0 then
    cur = 0
    addPts(D:QuestSpots(id))
  end
  if missing and QS.log[id] then
    local wp = D:QuestWaypoint(id)
    if wp then cur = 0; addPts({ wp }, "q" .. id); m.fromGame = true end
  end
  -- where players actually made progress / what they looted for it (recordings)
  if #objPts == 0 then
    addPts(D:QuestSpots(id))
    for _, k in ipairs(D:QuestSources(id)) do addPts(D:Points(k), k) end
    if #objPts > 0 then m.recorded = true; extraT = math.max(extraT, 120) end
  end
  -- "WANTED: Name" quests: the wanted npc
  if #objPts == 0 then
    local wanted = info.title:match("^[Ww][Aa][Nn][Tt][Ee][Dd]:%s*(.+)$")
    for _, nid in ipairs(wanted and D:NPCByName(wanted) or {}) do addPts(D:Points("c" .. nid), "c" .. nid) end
    if #objPts > 0 then extraT = math.max(extraT, 90) end
  end
  -- quests of a dungeon with no spots outside: the dungeon's entrance
  if #objPts == 0 and type(info.dungeon) == "number" and #lines > 0 then
    addPts(D:Entrance(info.dungeon))
  end
  -- any objective inside a dungeon makes it a dungeon quest (group run)
  for _, p in ipairs(objPts) do
    if p.dungeon then m.dungeon = p.dungeon; break end
  end
  if m.dungeon then
    if not (Q.prefs.dungeons or QS.log[id] or (P.dset and P.dset[id])) then return end
    local d = D:Dungeon(m.dungeon)
    m.dungeonName = d and d[1] or "a dungeon"
    local only = {}
    for _, p in ipairs(objPts) do if p.dungeon == m.dungeon then p.li = 0; only[#only + 1] = p end end
    objPts = only
  end
  m.lines, m.extraT, m.elite = lines, extraT, info.elite
  m.dungeonQuest = info.dungeon ~= nil or m.dungeon ~= nil
  -- the spots of each line, kept near that line's main area; the line's centre
  m.lp, m.lc = {}, {}
  if #objPts > 0 then
    local by = {}
    for _, p in ipairs(objPts) do
      local li = p.li or 0
      if li > 0 and not lines[li] then li = 0 end
      by[li] = by[li] or {}
      table.insert(by[li], p)
    end
    local all = {}
    for li, pts in pairs(by) do
      local c = D.Cluster(pts, 200, m.givers[1] or m.enders[1])
      local near = {}
      for _, p in ipairs(pts) do if D.Dist(p, c) <= 1200 then near[#near + 1] = p end end
      -- hundreds of spawn spots (It Takes Guts: 862) say no more than ~60 spread over the area
      if #near > 60 then
        local thin, step = {}, #near / 60
        for j = 1, 60 do thin[j] = near[math.floor((j - 1) * step) + 1] end
        near = thin
      end
      for _, p in ipairs(near) do all[#all + 1] = p end
      m.lp[li], m.lc[li] = near, c
    end
    local c, r, mem = D.Cluster(all, 200, m.givers[1] or m.enders[1])
    m.obj = { centre = c, radius = r, pts = all, members = mem }
  elseif #lines > 0 then
    m.objUnknown = true           -- objectives without known places: shown, but not routed
  end
  m.time, m.kills = P.QuestTime(id, m, info.level), P.QuestKills(m, info.level)
  -- rough effort from the giver: walk to the objectives, do them, walk to the ender
  local g = m.givers[1] or m.enders[1]
  local mid = m.obj and m.obj.centre or g
  local e = D.Nearest(mid, m.enders)
  m.effort = travel(g, mid, info.level) + m.time + travel(mid, e, info.level)
  -- dungeon quests are picked up on the way; the run itself is planned when you have them
  if m.dungeon then m.effort = m.effort - m.time + 300 end
  -- hostile elites where the objectives are (for "solo only" / "easy elites")
  if m.obj and Q.prefs.elite ~= "group" then
    local lv = Q.player.level or 1
    local minLv = (Q.prefs.elite == "some") and (lv + 2) or (lv - 4)
    -- an elite camp, not one named elite at the edge: a good share of the objective spots have
    -- elites right next to them
    local pts, hits, first = m.obj.pts, 0, nil
    for _, p in ipairs(pts) do
      local nid, elv = D:EliteNear(p, 40, minLv)
      if nid then hits = hits + 1; first = first or { nid = nid, lvl = elv } end
    end
    if first and (hits >= math.max(2, #pts * 0.35) or (#pts < 4 and hits >= 1)) then
      first.share = hits / #pts
      m.eliteNear = first
    end
  end
  meta[id] = m
  return m
end
P.Meta = questMeta

-- quests your settings leave out completely, even when they're in your log (picked up by hand or
-- by auto accept): dungeon quests with dungeons off, elite quests with "solo only". Reason or nil.
function P.Excluded(id)
  if P.dset and P.dset[id] then return end          -- dungeon mode: its quests and their chains
  if Q.char.forced and Q.char.forced[id] then return end   -- you added it yourself
  local pr = Q.prefs
  local info = QS:Info(id)
  local x = (info and info.x) or D:QuestExtra(id) or {}
  local m = info and questMeta(id)
  if not pr.dungeons then
    local sort = x[11]
    if (info and info.dungeon) or (m and m.dungeon) or (sort and sort > 0 and D:Dungeon(sort)) then
      return "dungeon quest - dungeon quests are off in your settings"
    end
  end
  if pr.elite ~= "group" then
    if pr.elite == "solo" then
      for _, c in ipairs(x[8] or {}) do
        local n = D:NPC(c)
        if n and (n[5] or 0) >= 1 and (n[5] or 0) ~= 4 then
          return ("elite target (%s) - you picked solo only"):format(n[1] or "elite")
        end
      end
    end
    if m and m.eliteNear then
      local n = D:NPC(m.eliteNear.nid)
      return ("elites where the objectives are (%s, level %d) - you picked %s"):format(n and n[1] or "elite",
        m.eliteNear.lvl or 0, pr.elite == "solo" and "solo only" or "easy elites")
    end
  end
end

-- ------------------------------------------------------------------ value
local rawValue
local function questValue(id, level)
  return memo("value", id * 100 + (level or 0), rawValue, id, level) or 0
end
function rawValue(id, level)
  local m = questMeta(id)
  if not m then return 0 end
  local pr, info = Q.prefs, m.info
  local xp = QS.RewardXP(id, level)
  local v = xp * (0.5 + 0.25 * (pr.xp or 3)) + m.kills * 0.6
  local money = QS.RewardMoney(id)
  if money > 0 then
    v = v + money / 10 * 0.25 * (pr.gold or 2)          -- real quest money (ForeverDB qrw)
  else
    v = v + xp * 0.15 * ((pr.gold or 2) - 1)           -- no money data: gold follows quest level
  end
  if pr.gear ~= "off" then
    local ok, up = pcall(G.QuestUpgrade, G, id)   -- gear advice must never stop the route
    if ok and up then v = v + math.min(1, up.pct / 25) * QS.QuestXP(level, level) * (pr.gear == "route" and 1.5 or 0.6) end
  end
  if pr.rep and info.rep then v = v + xp * 0.5 end
  -- completionist: every quest is worth doing, whatever it gives (the walk decides the order)
  if pr.style == "complete" then v = math.max(v, QS.QuestXP(level, level) * 1.2) + QS.QuestXP(level, level) * 0.6 end
  if info.class then v = v + xp * 1.5 end            -- class quests unlock spells / gear
  return v
end
P.Value = questValue

-- ------------------------------------------------------------------ simulation
-- where the route starts: where you are - or, while dead / a ghost, where you died (running back
-- from the graveyard doesn't change the plan)
function P.Here()
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and P.deathPos then return P.deathPos end
  -- on a flight: plan from where it lands
  local to = Q.Flight and Q.Flight:FlyingTo()
  if to and UnitOnTaxi and UnitOnTaxi("player") then return to end
  return D:PlayerPos()
end
Q:On("PLAYER_DEAD", function() P.deathPos = D:PlayerPos() end)
local function alive()
  if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
    if P.deathPos then P.deathPos = nil; P:Replan(1) end
  end
end
Q:On("PLAYER_ALIVE", alive)
Q:On("PLAYER_UNGHOST", alive)
local function newState()
  local st = {
    done = setmetatable({}, { __index = QS.done }),
    log = {},               -- [questID] = "obj" | "ready"
    level = Q.player.level,
    xp = UnitXP and UnitXP("player") or 0,
    pos = P.Here(),
    time = 0,
    count = 0,
    bought = {},
    fp = {},
    explored = {},
    blocked = Q.char.blocked or {},
    lastKey = Q.char.lastDone,          -- the last thing you really did (for the author's route rules)
  }
  st.open = {}
  for id, e in pairs(QS.log) do
    st.log[id] = e.complete and "ready" or "obj"
    local m = not e.complete and questMeta(id)
    if m then
      st.open[id] = P.OpenLines(id, m)
      -- every objective done (the log just hasn't flagged it yet)
      if not next(st.open[id]) and #m.lines > 0 then st.log[id] = "ready" end
    end
    st.count = st.count + 1
  end
  return st
end

local function gainXP(st, xp)
  st.xp = st.xp + xp
  while st.level < (Q.player.maxLevel or 60) and st.xp >= QS.XPToLevel(st.level) do
    st.xp = st.xp - QS.XPToLevel(st.level)
    st.level = st.level + 1
  end
end

-- ------------------------------------------------------------------ escort / cooking opt-out
local function hasBit(v, b) return v and (math.floor(v / b) % 2 == 1) end
local kindCache = {}
function P.Kind(id)
  local k = kindCache[id]
  if k == nil then k = P.StaticKind(id) or false; kindCache[id] = k end
  if k then return k end
  local e = QS.log[id]
  for _, o in ipairs(e and e.objectives or {}) do
    if o.text and o.text:lower():find("escort", 1, true) then return "escort" end
  end
end
function P.StaticKind(id)
  if Q.Secrets and Q.Secrets.Is(id) then return "secret" end
  local info = QS:Info(id)
  local x = (info and info.x) or D:QuestExtra(id) or {}
  if not info then local q = D:Quest(id); info = q and { title = q[1] } end
  -- battleground quests (Warsong Gulch, Arathi Basin, Alterac Valley, WoW Forever's Darkspear Islands)
  -- and other PvP quests
  local zone = x[11]
  if zone == 3277 or zone == 3358 or zone == 2597 or zone == 16606 then return "pvp" end
  local tl = (info and info.title or ""):lower()
  if tl:find("warsong", 1, true) or tl:find("arathi basin", 1, true) or tl:find("alterac valley", 1, true)
    or tl:find("darkspear islands", 1, true)
    or tl:find("battleground", 1, true) or tl:find("pvp", 1, true) then return "pvp" end
  if hasBit(x[12], 2) and hasBit(x[13], 2) then return "escort" end
  -- WoW Forever's own quests have no flags: go by the usual escort titles
  local t = (info and info.title or ""):lower()
  if t:find("escort", 1, true) or t:find("'s escape$") or t == "the escape" then return "escort" end
  local skill = x[14]
  if (type(skill) == "table" and skill[1] == 185) or skill == 185 or x[11] == -304 then return "cooking" end
  local r = QS.Rewards(id)
  for _, list in ipairs({ r and r[3] or {}, r and r[4] or {} }) do
    for _, it in ipairs(list) do
      local rec = D:Item(it)
      if rec and rec[5] == 9 then return "recipe" end
    end
  end
end
-- an opted-out quest is still worth it when its chain leads to gear for you or a dungeon
local KIND_NAMES = { escort = "Escort quest", cooking = "Cooking quest", recipe = "Recipe quest", pvp = "PvP quest" }
local neededFor
function P.NeededFor(id) return memo("needed", id, neededFor, id) end
function neededFor(id)
  local seen, q, n = {}, id, 0
  while q and not seen[q] and n < 10 do
    seen[q] = true
    n = n + 1
    local info = QS:Info(q)
    if not info then break end
    if q ~= id then
      if info.dungeon and Q.prefs.dungeons then return ("leads to %s (dungeon)"):format(info.title) end
      if Q.prefs.gear ~= "off" then
        local ok, up = pcall(G.QuestUpgrade, G, q)
        if ok and up then return ("leads to %s (a gear upgrade for you)"):format(info.title) end
      end
    else
      local ok, up = pcall(G.QuestUpgrade, G, q)
      if ok and up and Q.prefs.gear ~= "off" then return "its reward is a gear upgrade for you" end
    end
    q = info.x and info.x[7]
  end
end
P.keepWhy = {}
local optedOut
function P.OptedOut(id) return optedOut(id) end
function optedOut(id)
  if P.dset and P.dset[id] then return false end
  if Q.char.forced and Q.char.forced[id] then return false end
  if P.ZoneOff(id) then return true end
  if P.Excluded(id) then return true end
  local kind = P.Kind(id)
  if not kind then return false end
  local pr = Q.prefs
  local want = (kind == "escort" and pr.escort ~= false) or ((kind == "cooking" or kind == "recipe") and pr.cooking ~= false)
    or (kind == "pvp" and pr.pvp == true)
  if want then return false end
  -- secret quest chains (easter eggs): only on a Completionist route
  if kind == "secret" then return not (Q.Secrets and Q.Secrets.Wanted()) end
  if kind == "pvp" or kind == "escort" then return true end   -- PvP / escort quests off: no exceptions
  -- (an escort you add yourself - tracker "+", a dungeon's "Get all quests" - still goes on the route)
  local need = P.NeededFor(id)
  if need then
    P.keepWhy[id] = KIND_NAMES[kind] .. " - kept because the chain needs it: " .. need
    return false
  end
  return true
end

-- an escort in your log with escorts turned off: no objective work (abandon it, or add it in the
-- tracker to do it anyway)
function P.EscortOff(id)
  if Q.prefs.escort ~= false or (Q.char.forced and Q.char.forced[id]) or (P.dset and P.dset[id]) then return false end
  return P.Kind(id) == "escort"
end

-- quests in the level window that are worth routing at all
local function candidates(st)
  local pr = Q.prefs
  local list = {}
  -- dungeon mode: only that dungeon's quests and the chains leading to them, any level you can take
  if P.dset then
    for id in pairs(P.dset) do
      if not st.log[id] and QS:Available(id, st) then
        local m = questMeta(id)
        if m and (#m.givers > 0 or P.HasStartItem(m.info)) then list[#list + 1] = id end
      end
    end
    table.sort(list)
    return list
  end
  -- every quest that still gives real XP (not just the last 6 levels: a level 38 quest is still
  -- worth it at 46 when it's right where you're questing anyway)
  local lo = (pr.gray or pr.style == "complete") and 1 or (QS.GreyLevel(st.level) + 1)
  -- "no more than N levels below you" (survey); 0 / nil = anything that still gives XP
  -- the level window is your real level's (not the level the route expects you at later): the route
  -- is re-planned as you level, so a +2 setting never shows a quest more than 2 levels above you now
  local cur = Q.player.level or st.level
  if (pr.levelBelow or 0) > 0 then lo = math.max(lo, cur - pr.levelBelow) end
  local hi = cur + (pr.levelRange or 2)
  -- the part that doesn't depend on the simulated state: once per level window per build
  local static = memo("cands", lo * 1000 + hi, function()
    local out = {}
    for n, id in ipairs(QS.pool) do
      if n % 100 == 0 then maybeYield() end
      local info = QS:Info(id)
      if info and info.level >= lo and info.level <= hi and not optedOut(id) then
        local m = questMeta(id)
        if m and (#m.givers > 0 or P.HasStartItem(m.info)) then out[#out + 1] = id end
      end
    end
    return out
  end)
  local seen = {}
  for _, id in ipairs(static or {}) do
    if not st.log[id] and QS:Available(id, st) then list[#list + 1] = id; seen[id] = true end
  end
  -- quests you added to the route yourself (tracker), whatever their level / zone / settings
  for id in pairs(Q.char.forced or {}) do
    if not seen[id] and not st.log[id] and QS:Available(id, st) and questMeta(id) then list[#list + 1] = id end
  end
  return list
end

-- efficiency cut: in speed mode only the better half of quests is worth a detour
local function effCut(list, st)
  if P.dset then return list end
  local style = Q.prefs.style
  if style == "complete" or #list < 6 then return list end
  local effs = {}
  for _, id in ipairs(list) do
    local m = questMeta(id)
    effs[#effs + 1] = questValue(id, st.level) / (P.Effort(m) + 30)
  end
  local sorted = {}
  for i, e in ipairs(effs) do sorted[i] = e end
  table.sort(sorted)
  local cut = sorted[math.floor(#sorted * (style == "speed" and 0.45 or 0.15)) + 1] or 0
  local out, dropped = {}, {}
  for i, id in ipairs(list) do
    -- anything picked up right around you is always worth it (same hub, a few seconds)
    local near = st.pos and D.Dist(st.pos, D.Nearest(st.pos, questMeta(id).givers)) <= 350
    if near or effs[i] >= cut or (Q.char.forced and Q.char.forced[id]) then out[#out + 1] = id else dropped[#dropped + 1] = id end
  end
  -- quests done together are nearly free: keep any whose objectives are where a kept quest (or one
  -- in your log) already takes you, and whose giver is on the way there
  local areas = {}
  local function addAreas(m) for _, c in pairs(m and m.lc or {}) do areas[#areas + 1] = c end end
  for id in pairs(st.log) do addAreas(questMeta(id)) end
  for _, id in ipairs(out) do addAreas(questMeta(id)) end
  for _, id in ipairs(dropped) do
    local m = questMeta(id)
    local keep
    for _, c in pairs(m.lc or {}) do
      for _, a in ipairs(areas) do
        if a.i == c.i and D.Dist(a, c) <= BUNDLE * 1.5 then keep = a; break end
      end
      if keep then break end
    end
    local g = keep and D.Nearest(keep, m.givers)
    if keep and (P.HasStartItem(m.info) or (g and g.i == keep.i and D.Dist(g, keep) <= 900)) then
      out[#out + 1] = id
      P.keptTogether = P.keptTogether or {}
      P.keptTogether[id] = true
    end
  end
  return out
end

-- time still needed for some lines of a quest: learned work time when there is one (split by the
-- lines' share of the estimate), else the estimate x your pace (K)
local function linesTime(id, m, lines, open, lv)
  local est, total = 0, 0
  for _, li in ipairs(lines) do
    local l = m.lines[li]
    est = est + (l and P.LineTime(m, l, lv, open[li]) or (m.extraT or 30) * (open[li] or 1))
  end
  local learned = Q.Learn and Q.Learn:WorkTime(id)
  if learned then
    total = P.QuestTime(id, m, lv)
    return learned * est / math.max(1, total), true
  end
  return est * K, false
end
P.LinesTime = linesTime
function P.WorkTime(id, m, lv)
  local learned = Q.Learn and Q.Learn:WorkTime(id)
  if learned then return learned, true end
  return P.QuestTime(id, m, lv or m.info.level) * K, false
end

-- the open lines of a quest grouped by place: lines whose areas are close are done in one go
local GROUP = 2 * BUNDLE
local function groupsOf(id, m, open)
  local out = {}
  for li in pairs(open) do
    -- an objective made from parts waits while its parts are still open
    local l = m.lines[li]
    local wait = false
    if l and l.after then for _, pl in ipairs(l.after) do if open[pl] then wait = true end end end
    local c = (not wait) and m.lc[li] or nil
    if c then
      local g
      for _, gg in ipairs(out) do
        if gg.centre.i == c.i and D.Dist(gg.centre, c) <= GROUP then g = gg; break end
      end
      if g then g.lines[#g.lines + 1] = li
      else out[#out + 1] = { id = id, lines = { li }, centre = c } end
    end
  end
  for _, g in ipairs(out) do table.sort(g.lines) end
  return out
end
-- both points in the same zone (ForeverDB's zone borders): dungeon mode finishes the chain quest of the
-- zone you're in before it sends you off
local function sameZone(a, b)
  if not (a and b) or a.i ~= b.i or not D.ZoneAt then return false end
  local za = D:ZoneAt(a.i, a.x, a.y)
  return za and za ~= 0 and za == D:ZoneAt(b.i, b.x, b.y) or false
end
local function nearestIn(pos, m, lines)
  local best, bd
  for _, li in ipairs(lines) do
    for _, p in ipairs(m.lp[li] or {}) do
      if pos and p.i == pos.i then
        local d = D.Dist(pos, p)
        if not bd or d < bd then best, bd = p, d end
      elseif not best then best = p end
    end
  end
  return best
end

-- going to `to` from `from`, how much further you'd be from objectives still waiting nearby (you'd
-- have to come back for them). `skip[g]` = groups the action itself does.
local PENDING = 700
local function detour(pending, from, to, lv, skip)
  if not (from and to) then return 0 end
  local best, bd
  for _, g in ipairs(pending) do
    if not (skip and skip[g]) and g.centre.i == from.i then
      local d = D.Dist(from, g.centre)
      if d <= PENDING and (not bd or d < bd) then best, bd = g, d end
    end
  end
  if not best then return 0 end
  -- the walk back counts in full: you'll have to come here again for them
  local extra = travel(to, best.centre, lv) - travel(from, best.centre, lv)
  return extra > 0 and extra or 0
end

-- ------------------------------------------------------------------ exploration (completionist)
-- the areas of a zone you haven't uncovered on the map yet: legacy.zones[map] (Explorer achievement
-- criteria with a map spot), checked against the map's explored textures and the criteria themselves
local exploreCache = {}
P.exploreCache = exploreCache
local function exploredKeys(map)
  local got = {}
  local E = C_MapExplorationInfo
  local ok, list = pcall(function() return E and E.GetExploredMapTextures and E.GetExploredMapTextures(map) end)
  for _, t in ipairs(ok and list or {}) do
    got[("%d:%d:%d:%d"):format(t.offsetX or 0, t.offsetY or 0, t.textureWidth or 0, t.textureHeight or 0)] = true
  end
  return got
end
function P.ExploreTargets(map)
  if exploreCache[map] then return exploreCache[map] end
  local out = {}
  local L = D.db and D.db.legacy
  local zone = L and L.zones and L.zones[map]
  if zone then
    local names = {}
    for _, a in ipairs((L.completion and L.completion[map] and L.completion[map].areas) or {}) do if a.key then names[a.key] = a.name end end
    local got = exploredKeys(map)
    for _, e in ipairs(zone) do
      if e.kind == "explore" and e.key and e.x and not got[e.key] and not (Q.char.explored and Q.char.explored[map .. ":" .. e.key]) then
        local done
        if e.achievement and e.criteria and GetAchievementCriteriaInfoByID then
          local ok, _, _, c = pcall(GetAchievementCriteriaInfoByID, e.achievement, e.criteria)
          done = ok and c == true
        end
        if not done then
          local i, x, y = D:WorldPos(map, e.x, e.y)
          if i then
            out[#out + 1] = { key = map .. ":" .. e.key, name = names[e.key] or "an unexplored area", map = map,
              point = { i = i, x = x, y = y, m = map, mx = e.x, my = e.y } }
          end
        end
      end
    end
  end
  exploreCache[map] = out
  return out
end
Q:Command("explore", "completionist: map exploration in the route on / off", function()
  Q.char.noExplore = not Q.char.noExplore or nil
  Q:Print("map exploration in completionist routes: " .. (Q.char.noExplore and "off" or "on"))
  wipe(exploreCache); P:Build()
end)
Q:On("MAP_EXPLORATION_UPDATED", function() wipe(exploreCache); P:Replan(1) end)
Q:On("ZONE_CHANGED", function() wipe(exploreCache) end)
-- reaching an explore step's spot counts as explored, even if the game's event doesn't come
-- (the spot is the middle of the area, so you've been inside it)
function P.CheckExplore(here)
  local s = P.steps and P.steps[1]
  if not (s and s.type == "explore" and s.area and here) then return end
  if D.Dist(here, s.area.point) < 20 then
    Q.char.explored = Q.char.explored or {}
    Q.char.explored[s.area.key] = true
    wipe(exploreCache)
    P:Replan(0.5)
    return true
  end
end
do
  local acc = 0
  local tick = CreateFrame("Frame")
  tick:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < 1.5 then return end
    acc = 0
    if P.steps and P.steps[1] and P.steps[1].type == "explore" then P.CheckExplore(D:PlayerPos()) end
  end)
end
-- areas worth a detour from here (the zone you're in and the zones the route is in)
local function exploreNear(st)
  local map = P.MapOf(st.pos)
  local out = {}
  if not map then return out end
  for _, a in ipairs(P.ExploreTargets(map)) do
    if not st.explored[a.key] and D.Dist(st.pos, a.point) < 600 then out[#out + 1] = a end
  end
  return out
end

P.prefer, P.later = {}, {}
function P.ActionKey(a)
  if a.type == "explore" then return "explore:" .. a.area.key end
  if a.type == "fp" then return "fp:" .. a.node.id end
  if a.type == "prep" then return "prep:" .. a.prep.key end
  return a.type .. ":" .. (a.id or a.item or 0)
end

local function bestAction(st, cands)
  local best, bestScore, second, secondScore
  local trace = P.trace
  local function offer(a, score)
    -- the quest you focused in the tracker comes first; quests you added yourself weigh more
    local fq = Q.char.focus
    if fq then
      local hit = a.id == fq
      for _, b in ipairs(a.bundle or {}) do if b == fq then hit = true end end
      if hit then score = score * 40 end
    end
    if a.id and Q.char.forced and Q.char.forced[a.id] then score = score * 6 end
    -- finish the zone you're in first (survey "Finish a zone's quests before moving on" / completionist)
    if P.zoneFocus and a.point and a.type ~= "fp" and a.type ~= "fly" then
      local zm = P.MapOf(a.point)
      if zm and zm ~= P.zoneFocus then score = score * 0.12 end
    end
    -- the author's saved route: "this right after that"
    if st.lastKey and P.Hint and P.Hint(st.lastKey) == P.ActionKey(a) then score = score * 6 end
    -- right-click menu on a step: "do this next" / "skip for now"
    local key = a.node and ("fp" .. a.node.id) or nil
    for _, id in ipairs(a.bundle or { a.id or key }) do
      if P.prefer[id] then score = score * 8 end
      if P.later[id] then score = score * 0.03 end
    end
    if key and P.later[key] then score = score * 0.03 end
    -- stick to the step you're already on unless something is clearly better: re-planning as you
    -- walk must not flip you between two targets that are about as good
    if P.stick and P.stickKey and P.ActionKey(a) == P.stickKey then score = score * 1.6 end
    a.score = score
    if trace then trace[#trace + 1] = { a = a, score = score } end
    if not bestScore or score > bestScore then
      second, secondScore = best, bestScore
      best, bestScore = a, score
    elseif not secondScore or score > secondScore then
      second, secondScore = a, score
    end
  end
  local lv = st.level
  -- dungeon mode: quests of the dungeon (or their chains) still to pick up - the run waits for them
  local dPending = #P.PrepStages(st)
  for id in pairs(P.dset or {}) do
    local inf = QS:Info(id)
    if not st.done[id] and not st.log[id] and inf and (inf.min or 1) <= lv then dPending = dPending + 1 end
  end
  -- every group of objectives still waiting, for the "don't walk away from them" check
  local pending, groups = {}, {}
  local yi = 0
  for id, stage in pairs(st.log) do
    yi = yi + 1
    if yi % 8 == 0 then maybeYield() end
    local m = stage == "obj" and not Q.char.skipped[id] and not P.Excluded(id)
      and not (P.dset and not P.dset[id]) and not P.ZoneOff(id) and not P.EscortOff(id) and questMeta(id)
    if m and m.lc and st.open[id] then
      groups[id] = groupsOf(id, m, st.open[id])
      for _, g in ipairs(groups[id]) do pending[#pending + 1] = g end
    end
  end
  -- turn-ins and objectives for quests in the (simulated) log
  for id, stage in pairs(st.log) do
    -- left out by your settings: no objectives (a finished one can still be handed in)
    local m = not Q.char.skipped[id] and not (stage ~= "ready" and P.Excluded(id))
      and not (P.dset and not P.dset[id] and stage ~= "ready")   -- dungeon mode: other quests only get handed in
      and not (stage ~= "ready" and P.ZoneOff(id))                 -- zones you turned off: hand-ins only
      and not (stage ~= "ready" and P.EscortOff(id))               -- escorts turned off: hand-ins only
      and not (stage == "ready" and QS.RepBlock(id, (QS:Info(id) or {}).enders))  -- hand-in NPC hostile to you
      and questMeta(id)
    if m then
      -- dungeon mode: every quest of the dungeon is wanted, so only the walking decides the order
      local v = (P.dset and P.dset[id]) and DVALUE or questValue(id, lv)
      -- dungeon mode: other quests are only handed in when the hand-in is right on the way
      local offTrack = false
      if stage == "ready" and P.dset and not P.dset[id] then
        local pe = D.Nearest(st.pos, m.enders)
        offTrack = not (pe and st.pos and pe.i == st.pos.i and D.Dist(st.pos, pe) <= 250)
      end
      if stage == "ready" and offTrack then
        -- (finished, its hand-in off the dungeon's way: nothing to do for it now. It used to fall through
        -- to "objectives with no known place" and fill the route with "Do <quest>" steps that never ended)
      elseif stage == "ready" then
        local p = D.Nearest(st.pos, m.enders)
        local t = travel(st.pos, p, lv) + 6
        local back = detour(pending, st.pos, p, lv)
        -- someone else's quest ends at the same NPC and its objectives are close: finish it first,
        -- then hand both in on one trip
        local same
        for _, g in ipairs(pending) do
          local m2 = questMeta(g.id)
          local e2 = m2 and D.Nearest(p, m2.enders)
          if e2 and p and e2.i == p.i and D.Dist(e2, p) <= 40 and st.pos and D.Dist(st.pos, g.centre) <= 700 then
            same = g; break
          end
        end
        if same then back = math.max(back, travel(p, same.centre, lv) * 0.9) end
        offer({ type = "turnin", id = id, point = p, t = t, back = back, sameEnder = same and same.id },
          v * 1.15 / (t + back))
      elseif st.udone and st.udone[id] then
        -- (already planned once below: one "Do" step for it is enough)
      elseif not m.obj or not st.open[id] or not next(groups[id] or {}) then
        -- objectives the databases have no place for: never "turn in" before they are done.
        -- Point at the game's own quest waypoint when it has one, else stay put.
        local wp = (QS.log[id] and D:QuestWaypoint(id)) or nil
        local work = P.WorkTime(id, m, lv)
        local t = (wp and travel(st.pos, wp, lv) or 0) + (work > 0 and work or 120)
        -- last in line: everything with a known place comes first
        offer({ type = "complete", id = id, point = wp, bundle = { id }, parts = { { id = id, lines = {} } }, t = t,
          unknown = true }, v * 0.05 / (t + 300))
      elseif (m.info.level <= (Q.player.level or lv) + (Q.prefs.levelRange or 2) or (P.dset and P.dset[id]) or (Q.char.forced and Q.char.forced[id]))
        and not (P.dset and not P.dset[id]) then               -- dungeon mode: only its quests
        local open = st.open[id]
        local totalT = linesTime(id, m, (function() local l = {} for li in pairs(open) do l[#l + 1] = li end return l end)(), open, lv)
        for _, g in ipairs(groups[id]) do
          local target = nearestIn(st.pos, m, g.lines)
          local work = linesTime(id, m, g.lines, open, lv)
          local share = math.max(0.15, work / math.max(1, totalT))
          local t = travel(st.pos, target, lv) + work
          local value = v * share
          local parts, bundle, skip = { g }, { id }, { [g] = true }
          local together = {}
          -- every other quest with objectives in the same place (or that you did together before)
          for _, g2 in ipairs(pending) do
            if g2.id ~= id and not skip[g2] then
              local close = g2.centre.i == g.centre.i and D.Dist(g2.centre, g.centre) <= BUNDLE
              local learned = not close and g2.centre.i == g.centre.i and D.Dist(g2.centre, g.centre) <= 650
                and Q.Learn and Q.Learn:Together(id, g2.id) >= 2
              local m2x = (close or learned) and questMeta(g2.id)
              -- dungeon mode: the dungeon's run waits until everything is picked up
              if m2x and P.dset and dPending > 0 and m2x.dungeon and not m.dungeon then close, learned = false, false end
              if close or learned then
                local m2 = questMeta(g2.id)
                local o2 = st.open[g2.id]
                local w2, all2 = linesTime(g2.id, m2, g2.lines, o2, lv), P.WorkTime(g2.id, m2, lv)
                value = value + questValue(g2.id, lv) * math.max(0.15, w2 / math.max(1, all2))
                -- quests of the same dungeon share one run; overlapping areas share the walking
                t = t + ((m.dungeon and m2.dungeon == m.dungeon) and 120 or w2 * 0.6)
                parts[#parts + 1] = g2
                skip[g2] = true
                if not together[g2.id] then together[g2.id] = learned and "learned" or "near"; bundle[#bundle + 1] = g2.id end
              end
            end
          end
          local back = detour(pending, st.pos, g.centre, lv, skip)
          local after = D.Nearest(g.centre, m.enders)
          local tail = travel(g.centre, after, lv) * 0.3
          -- you're standing in this area already: finish it now (walking off and coming back is
          -- exactly the back-and-forth to avoid)
          local here = st.pos and target and target.i == st.pos.i and
            (D.Dist(st.pos, target) <= 150 or D.Dist(st.pos, g.centre) <= 300)
          offer({ type = "complete", id = id, point = target, bundle = bundle, parts = parts, t = t, back = back,
            together = together, inArea = here,
            partial = #g.lines < (function() local n = 0 for _ in pairs(open) do n = n + 1 end return n end)() },
            value / (t + back + tail) * (here and 3 or 1) * ((P.dset and m.dungeon and dPending > 0) and 0.01 or 1)
              * ((P.dset and P.dset[id] and not m.dungeon and sameZone(st.pos, target)) and 1.6 or 1))
        end
      end
    end
  end
  -- accepting new quests
  if st.count < QS.MaxLog() then
    for ci, id in ipairs(cands) do
      if ci % 16 == 0 then maybeYield() end
      local m = questMeta(id)
      local p, t, fromItem
      if P.HasStartItem(m.info) then
        p, t, fromItem = st.pos, 0, m.info.startItem   -- use the item right where you are
      else
        p = D.Nearest(st.pos, m.givers)
        t = travel(st.pos, p, lv)
      end
      local here = t * speed(lv) <= NEAR
      local ew = (Q.prefs.style == "speed" and 1.0) or (Q.prefs.style == "complete" and 0.15) or 0.5
      local score = P.dset and (DVALUE / (t + 5)) or (questValue(id, lv) / (t + ew * P.Effort(m) + 5))
      -- its objectives are where you're going anyway: do them together
      local overlap
      for _, c in pairs(m.lc or {}) do
        for _, g in ipairs(pending) do
          if g.centre.i == c.i and D.Dist(g.centre, c) <= BUNDLE then overlap = g.id; break end
        end
        if overlap then break end
      end
      if overlap then score = score * 1.4 end
      -- walking away from objectives that are waiting right here means coming back for them
      -- (counted even when its objectives overlap others waiting somewhere: an overlap far away - the
      -- dungeon's quests at the Sunken Temple - made a quest across the sea look "on the way" and the
      -- route left the chain quest you were standing next to)
      local back = (not here) and detour(pending, st.pos, p, lv) or 0
      if back > 0 then score = score * t / (t + back) end
      if here then score = score * 4 end       -- same NPC / hub: take it now
      if t * speed(lv) < 200 then score = score * 1.6 end   -- right on the way: pick it up
      if Q.prefs.allInZone and t < 120 then score = score * 1.5 end
      offer({ type = "accept", id = id, point = p, t = t + 5, item = fromItem, here = here, overlap = overlap, back = back }, score)
    end
  end
  -- flight paths of your faction you don't have yet, close by: worth the few seconds
  if Q.Flight and Q.prefs.flights ~= false then
    -- dungeon mode: things to fetch before the run (the mallet for Gahz'rilla ...)
    for _, stage in ipairs(P.PrepStages(st)) do
      local pts = stage.points()
      local best, bt
      for _, pt in ipairs(pts) do
        local t = travel(st.pos, pt, lv)
        if not bt or t < bt then best, bt = pt, t end
      end
      if best then
        local t = bt + (stage.work or 30)
        offer({ type = "prep", prep = stage, point = best, t = t }, DVALUE / (t + 5))
      end
      break                                   -- one stage at a time, in order
    end
    -- dungeon mode: picking up flight paths on the way pays off for the next legs
    -- completionist: uncover the map (exploration XP, the zone's Explorer achievement)
    if Q.prefs.style == "complete" and not P.dset and not Q.char.noExplore then
      for _, ar in ipairs(exploreNear(st)) do
        local key = "explore" .. ar.key
        if not P.later[key] then
          local t = travel(st.pos, ar.point, lv) + 3
          offer({ type = "explore", area = ar, point = ar.point, t = t }, QS.QuestXP(lv, lv) * 0.8 / (t + 10))
        end
      end
    end
    for _, n in ipairs(Q.Flight:Unknown(st.pos, P.dset and 600 or 350)) do
      if not st.fp[n.id] then
        local t = travel(st.pos, n, lv) + 8
        offer({ type = "fp", node = n, point = Q.Flight.MasterPoint and Q.Flight.MasterPoint(n) or n, t = t }, (P.dset and DVALUE * 0.5 or QS.QuestXP(lv, lv) * 0.4) / t)
      end
    end
  end
  -- gear from vendors on the way
  if P.vendorUps and Q.prefs.gear == "route" then
    for _, u in ipairs(P.vendorUps) do
      if not st.bought[u.item] and D.Dist(st.pos, u.point) <= 260 then
        local t = travel(st.pos, u.point, lv) + 10
        offer({ type = "buy", item = u.item, npc = u.npc, point = u.point, pct = u.pct, t = t },
          u.pct / 25 * QS.QuestXP(lv, lv) / t)
      end
    end
  end
  return best, second
end

local function apply(st, a)
  st.lastKey = P.ActionKey(a)
  st.pos = a.point or st.pos
  st.time = st.time + (a.t or 0)
  if a.type == "accept" then
    local m = questMeta(a.id)
    st.log[a.id] = (m.obj or m.objUnknown) and "obj" or "ready"
    st.open[a.id] = {}
    for li in ipairs(m.lines) do st.open[a.id][li] = 1 end
    if m.lp and m.lp[0] then st.open[a.id][0] = 1 end
    if m.dungeon then st.open[a.id] = { [0] = 1 } end      -- one run inside
    st.count = st.count + 1
  elseif a.type == "complete" then
    for _, part in ipairs(a.parts or {}) do
      local id, m = part.id, questMeta(part.id)
      local open = st.open[id]
      local k = 0
      if a.unknown then st.udone = st.udone or {}; st.udone[id] = true end
      if a.unknown or not open then
        k = m.kills
        st.open[id] = {}
      else
        for _, li in ipairs(part.lines) do
          if m.lines[li] then k = k + P.LineKills(m.lines[li], st.level, open[li]) end
          open[li] = nil
        end
      end
      if not next(st.open[id] or {}) then st.log[id] = "ready" end
      st.gained = (st.gained or 0) + k
      gainXP(st, k)
    end
  elseif a.type == "turnin" then
    st.log[a.id] = nil
    st.done[a.id] = true
    st.count = st.count - 1
    local gx = QS.RewardXP(a.id, st.level)
    st.gained = (st.gained or 0) + gx
    gainXP(st, gx)
  elseif a.type == "buy" then
    st.bought[a.item] = true
  elseif a.type == "fp" then
    st.fp[a.node.id] = true
  elseif a.type == "explore" then
    st.explored[a.area.key] = true
  elseif a.type == "prep" then
    st.prep = st.prep or {}
    st.prep[a.prep.key] = true
  end
end

-- ------------------------------------------------------------------ steps
-- quests that start from an item: only when it is in your bags
-- what's in your bags (item id -> true), refreshed when the bags change: a table lookup instead of
-- hundreds of GetItemCount calls
local function scanBags()
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemID) then return nil end
  local set = {}
  for bag = 0, 4 do
    for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
      local id = C.GetContainerItemID(bag, slot)
      if id then set[id] = true end
    end
  end
  return set
end
function P.ItemCount(it)
  if not it then return 0 end
  return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or (GetItemCount and GetItemCount(it)) or 0
end
function P.HasStartItem(info)
  local it = info and info.startItem
  if not it then return false end
  if P.bagSet then return P.bagSet[it] == true end
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or (GetItemCount and GetItemCount(it)) or 0
  return n > 0
end

local function npcName(point)
  return point and point.key and D:Name(point.key) or "?"
end

-- quests started by an item that drops from these mobs (so the guide can say "loot it")
local startIdx
local function startsFrom(key)
  if not startIdx then
    startIdx = {}
    for q, item in pairs(D.startItem or {}) do
      for _, src in ipairs(D:ItemSources(item)) do
        if src.key:sub(1, 1) == "c" and not src.vendor then
          startIdx[src.key] = startIdx[src.key] or {}
          table.insert(startIdx[src.key], q)
        end
      end
    end
  end
  return startIdx[key]
end

local function lineNames(m, lines)
  local t = {}
  for _, li in ipairs(lines) do
    local l = m.lines[li]
    if l then t[#t + 1] = l.name end
    if li == 0 and not m.dungeon then t[#t + 1] = m.fromGame and "the game's quest marker" or "where progress was recorded" end
  end
  return table.concat(t, ", ")
end
local function short(a)
  if not a then return nil end
  local title = a.id and QS:Info(a.id) and QS:Info(a.id).title or ""
  if a.type == "accept" then return "accept " .. title end
  if a.type == "turnin" then return "turn in " .. title end
  if a.type == "complete" then return "do " .. title end
  if a.type == "buy" then return "buy " .. D:Name("i" .. (a.item or 0)) end
  if a.type == "fp" then return "get the flight path at " .. a.node.name end
  if a.type == "explore" then return "explore " .. a.area.name end
  if a.type == "prep" then return a.prep.text end
  return a.type
end
local function mins(sec) return sec < 90 and (math.floor(sec + 0.5) .. " s") or (math.floor(sec / 60 + 0.5) .. " min") end

-- why this step, and why it beats the next best thing
local function reasons(a, alt, st)
  local why = {}
  local lv = st.level
  if a.type == "complete" then
    local m = questMeta(a.id)
    if a.unknown then
      why[#why + 1] = "No map spots for these objectives yet - left for last (the game's quest marker is used)"
    else
      local n = #(a.bundle or {})
      if n > 1 then
        local learned
        for _, how in pairs(a.together or {}) do if how == "learned" then learned = true end end
        why[#why + 1] = ("%d quests have objectives here - done in one go"):format(n) ..
          (learned and " (you did some of them together before)" or "")
      end
      if a.partial then
        local g = a.parts[1]
        local rest = {}
        for li in pairs(st.open[a.id] or {}) do
          local found
          for _, x in ipairs(g.lines) do if x == li then found = true end end
          if not found and m.lines[li] then rest[#rest + 1] = m.lines[li].name end
        end
        why[#why + 1] = "Only " .. lineNames(m, g.lines) .. " here now" ..
          (#rest > 0 and (" - " .. table.concat(rest, ", ") .. " is elsewhere and comes later in the route") or "")
      end
      if a.inArea then why[#why + 1] = "You're right where these objectives are - finish them before leaving" end
      if (a.back or 0) > 20 then why[#why + 1] = "Avoids walking away from objectives that are still waiting nearby" end
    end
  elseif a.type == "turnin" then
    why[#why + 1] = "Finished - hand it in while you're close"
    if (a.back or 0) > 20 then why[#why + 1] = "Still worth it although objectives are waiting nearby" end
  elseif a.type == "accept" then
    if a.item then why[#why + 1] = "You have the item that starts it"
    elseif a.here then why[#why + 1] = "Right here - take it before leaving"
    elseif a.overlap then
      why[#why + 1] = "Its objectives are where " .. ((QS:Info(a.overlap) or {}).title or "another quest") .. " takes you anyway"
    end
    if P.keptTogether and P.keptTogether[a.id] then why[#why + 1] = "Low value alone, but done together with quests in the same area" end
    if P.keepWhy[a.id] then why[#why + 1] = P.keepWhy[a.id] end
  elseif a.type == "buy" then
    why[#why + 1] = ("%d%% better than what you wear, on the way"):format(math.floor(a.pct or 0))
  elseif a.type == "explore" then
    why[#why + 1] = "Completionist: an area of the map you haven't explored yet - exploration XP and the zone's Explorer achievement"
  elseif a.type == "fp" then
    why[#why + 1] = "A flight path you don't have yet, a few seconds away - later routes can fly from here"
  end
  if a.t and a.t > 0 then why[#why + 1] = "About " .. mins(a.t + (a.back or 0)) end
  if alt and alt.score and a.score and a.score > 0 then
    local x = a.score / math.max(1e-6, alt.score)
    why[#why + 1] = ("Next best was to %s: %s"):format(short(alt) or "?",
      x >= 1.05 and ("this is %.1fx more XP per minute"):format(x) or "about as good, this one is closer")
  end
  return why
end

local function makeStep(a, st, alt)
  local s = { type = a.type, point = a.point, level = st.level, quests = a.bundle or { a.id }, t = a.t or 0 }
  s.why = reasons(a, alt, st)
  s.rate = a.score and a.t and a.t > 0 and a.score or nil
  if a.id and (a.type == "turnin" or a.type == "accept" or a.type == "complete") then
    s.xp, s.realXP = QS.RewardXP(a.id, st.level)
    s.money = QS.RewardMoney(a.id)
  end
  s.key = a.type .. ":" .. (a.id or a.item or 0)
  if a.type == "prep" then
    s.key, s.prep, s.quests = "prep:" .. a.prep.key, a.prep, { a.prep.quest }
    s.why = { a.prep.why }
  end
  if a.type == "accept" and a.item then s.point = nil end
  if a.type == "accept" or a.type == "turnin" then
    local info = QS:Info(a.id)
    s.title, s.qlevel = info.title, info.level
    s.npc = npcName(a.point)
    if a.type == "accept" and a.item then s.startItem, s.npc = a.item, nil end
    if a.type == "turnin" and Q.prefs.gear ~= "off" then
      local ok, up = pcall(G.QuestUpgrade, G, a.id)
      s.upgrade = ok and up or nil
    end
  elseif a.type == "complete" then
    s.unknown = a.unknown
    local m = questMeta(a.id)
    s.dungeon = m and m.dungeonName
    s.titles = {}
    for _, id in ipairs(s.quests) do s.titles[#s.titles + 1] = QS:Info(id).title end
    -- which objectives of which quest this step is for
    s.parts, s.partial = {}, a.partial
    local mobs = {}
    for _, g in ipairs(a.parts or {}) do
      s.parts[#s.parts + 1] = { id = g.id, lines = g.lines }
      local mg = questMeta(g.id)
      for _, li in ipairs(g.lines) do
        local l = mg and mg.lines[li]
        if l then
          if l.kind == "kill" then mobs[l.key] = true end
          for _, k in ipairs(l.srcs or {}) do mobs[k] = true end
        end
      end
      if mg then s.partText = s.partText or {}; s.partText[g.id] = lineNames(mg, g.lines) end
    end
    -- quests that start from an item those mobs drop: "loot X - it starts Y"
    for key in pairs(mobs) do
      for _, q in ipairs(startsFrom(key) or {}) do
        if not QS.done[q] and not QS.log[q] and QS:Info(q) then
          s.drops = s.drops or {}
          s.drops[#s.drops + 1] = { item = D.startItem[q], quest = q }
        end
      end
    end
  elseif a.type == "buy" then
    s.item, s.npc, s.pct = a.item, D:Name("c" .. a.npc), a.pct
  elseif a.type == "fp" then
    s.node, s.npc = a.node, a.node.name
    s.key = "fp:" .. a.node.id
  elseif a.type == "explore" then
    s.area = a.area
    s.key = "explore:" .. a.area.key
  end
  return s
end

-- ------------------------------------------------------------------ zones
-- the zone map a point is in (cached on the point)
function P.MapOf(p)
  if not p then return end
  local m = D:MapPos(p)
  return m
end
-- the zone a quest is picked up in (its first giver), else where its objectives are
function P.QuestZone(id)
  local m = questMeta(id)
  if not m then return end
  local g = m.givers and m.givers[1]
  if g then return P.MapOf(g) end
  for li, c in pairs(m.lc or {}) do return P.MapOf(c) end
end
function P.ZoneOff(id)
  local off = Q.char.zoneOff
  if not (off and next(off)) or (P.dset and P.dset[id]) then return false end
  local z = P.QuestZone(id)
  return z and off[z] or false
end

-- ------------------------------------------------------------------ dungeons
-- which dungeon a quest is for: its quest sort, or objectives that only exist inside one
local dqCache = {}
local function keyDungeon(key)
  local pts = D:Points(key)
  return pts[1] and pts[1].dungeon or nil
end
function P.QuestDungeon(id)
  local c = dqCache[id]
  if c ~= nil then return c or nil end
  if Q.Dungeons and Q.Dungeons.Extras then Q.Dungeons.Extras() end
  local info = QS:Info(id)
  local x = (info and info.x) or D:QuestExtra(id) or {}
  local a = info and info.dungeon
  if a and (D.RAID_AREA[a] or not D:Dungeon(a)) then a = nil end
  if not a then
    for _, cId in ipairs(x[8] or {}) do a = a or keyDungeon("c" .. cId) end
    for _, o in ipairs(x[9] or {}) do a = a or keyDungeon("o" .. o) end
    for _, it in ipairs(x[10] or {}) do
      if a then break end
      local srcs = D:ItemSources(it)
      if srcs[1] and not srcs[1].vendor then a = keyDungeon(srcs[1].key) end
    end
    -- WoW Forever's newest dungeons (Questicus Maps' boss lists): a quest to kill one of their bosses
    if not a and Q.Dungeons and Q.Dungeons.bossArea then
      for _, cId in ipairs(x[8] or {}) do a = a or Q.Dungeons.bossArea[cId] end
    end
    if a and D.RAID_AREA[a] then a = nil end
  end
  dqCache[id] = a or false
  return a
end
-- dungeon area -> quests of it this character can do (built once per quest pool)
function P.DungeonIndex()
  if P.dIdx and P.dIdxPool == QS.pool then return P.dIdx end
  if Q.Dungeons and Q.Dungeons.Extras then Q.Dungeons.Extras() end
  local idx = {}
  for _, id in ipairs(QS.pool or {}) do
    local a = P.QuestDungeon(id)
    if a then idx[a] = idx[a] or {}; table.insert(idx[a], id) end
  end
  P.dIdx, P.dIdxPool = idx, QS.pool
  return idx
end
-- things to fetch before a dungeon run, for one of its quests. Each stage is done when you carry
-- its item (or a later stage's). points() = where to go.
local function hasItem(it)
  if P.bagSet then return P.bagSet[it] == true end
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it)) or (GetItemCount and GetItemCount(it)) or 0
  return n > 0
end
P.DUNGEON_PREP = {
  -- Gahz'rilla (2770): the Mallet of Zul'Farrak rings the gong that summons him
  { quest = 2770, stages = {
    { key = "zf-mallet-1", has = { 9241, 9240 }, work = 60,
      text = "Kill Qiaga the Keeper (Jintha'Alor, The Hinterlands) for the Sacred Mallet",
      why = "Gahz'rilla only comes when you ring the gong in Zul'Farrak with the Mallet of Zul'Farrak: it starts as the Sacred Mallet Qiaga the Keeper drops",
      points = function() return D:Points("c7996") end },
    { key = "zf-mallet-2", has = { 9240 }, work = 15,
      text = "Use the Sacred Mallet at the altar of Jintha'Alor (59, 77) - it becomes the Mallet of Zul'Farrak",
      why = "The Mallet of Zul'Farrak rings the gong that summons Gahz'rilla",
      points = function()
        local i, x, y = D:WorldPos(1425, 0.59, 0.77)
        if i then return { { i = i, x = x, y = y, key = "altar" } } end
        local q = D:Points("c7996")[1]          -- the altar is at the top of Jintha'Alor, by Qiaga
        return q and { q } or {}
      end },
  } },
}
-- the stages still to do in dungeon mode (in order), for quests of the dungeon you haven't done
function P.PrepStages(st)
  local out = {}
  if not P.dset then return out end
  for _, pr in ipairs(P.DUNGEON_PREP) do
    if P.dset[pr.quest] and not (st and st.done and st.done[pr.quest]) and not QS.done[pr.quest] then
      local laterHave = false
      for k = #pr.stages, 1, -1 do
        local stg = pr.stages[k]
        local have = laterHave
        for _, it in ipairs(stg.has) do if hasItem(it) then have = true end end
        if st and st.prep and st.prep[stg.key] then have = true end
        if have then laterHave = true end
        stg.quest = pr.quest
        if not have then table.insert(out, 1, stg) end
      end
    end
  end
  return out
end

-- a quest plus the earlier chain quests it needs (not done yet), into `set`
function P.NeedChain(id, set, depth)
  set = set or {}
  depth = depth or 0
  if depth > 12 or set[id] or QS.done[id] then return set end
  local info = QS:Info(id)
  if not info then return set end
  set[id] = true
  local x = info.x
  for _, pre in ipairs(x[4] or {}) do P.NeedChain(pre, set, depth + 1) end
  local any = x[3] or ((not x[3] and not x[4]) and QS.prevOf and QS.prevOf[id]) or nil
  if any then
    -- one of them done: nothing earlier to do. One in your log: it's part of the chain still to finish
    -- (it used to count as done here, so dungeon mode dropped the quest you were on - Larion and Muigin
    -- for the Sunken Temple - and sent you elsewhere). Else the first one the data knows.
    local done, inLog
    for _, pre in ipairs(any) do
      if QS.done[pre] then done = true; break end
      if QS.log[pre] then inLog = inLog or pre end
    end
    if not done then
      if inLog then P.NeedChain(inLog, set, depth + 1)
      else
        for _, pre in ipairs(any) do if QS:Info(pre) then P.NeedChain(pre, set, depth + 1); break end end
      end
    end
  end
  return set
end

-- every quest still to do for a dungeon, plus the chain quests that unlock them
function P.DungeonTargets(area)
  local set = {}
  local function need(id, depth)
    if depth > 12 or set[id] or QS.done[id] then return end
    local info = QS:Info(id)
    if not info then return end
    set[id] = true
    local x = info.x
    for _, pre in ipairs(x[4] or {}) do need(pre, depth + 1) end
    local any = x[3] or ((not x[3] and not x[4]) and QS.prevOf and QS.prevOf[id]) or nil
    if any then
      -- one of them done: nothing earlier to do. One in your log: it's part of the chain still to finish
      -- (it used to count as done here, so dungeon mode dropped the quest you were on - Larion and Muigin
      -- for the Sunken Temple - and sent you elsewhere). Else the first one the data knows.
      local done, inLog
      for _, pre in ipairs(any) do
        if QS.done[pre] then done = true; break end
        if QS.log[pre] then inLog = inLog or pre end
      end
      if not done then
        if inLog then need(inLog, depth + 1)
        else
          for _, pre in ipairs(any) do if QS:Info(pre) then need(pre, depth + 1); break end end
        end
      end
    end
  end
  -- the same dungeon can have two area ids (its zone and its instance): both lists
  local d = D:Dungeon(area)
  for a, ids in pairs(P.DungeonIndex()) do
    local da = D:Dungeon(a)
    if a == area or (d and da and da[1] == d[1]) then
      for _, id in ipairs(ids) do need(id, 0) end
    end
  end
  return set
end
function P:DungeonMode(area)
  Q.char.dmode = area
  wipe(meta)
  P:Reset()
  if QS.pool then QS:BuildPool() end
  P:BuildAsync()
  Q:Send("QC_DMODE_CHANGED", area)
end

function P:Build()
  if not (D:Ready() and QS.pool) then return end
  if P.co and coroutine.running() ~= P.co then P.co = nil end   -- a direct build replaces a sliced one
  local t0 = debugprofilestop and debugprofilestop() or 0
  K = Q.Learn and Q.Learn:TimeScale() or 1
  B = {}
  -- the zone to finish first
  P.zoneFocus = nil
  if (Q.prefs.allInZone or Q.prefs.style == "complete") and not Q.char.dmode then
    local here = P.Here and P.Here()
    -- same lookup as the route's points, so they compare (the game's own map can be a sub-zone)
    P.zoneFocus = (here and P.MapOf(here)) or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
  end
  P.dset = nil
  if Q.char.dmode then
    P.dset = P.DungeonTargets(Q.char.dmode)
    if not next(P.dset) then
      local d = D:Dungeon(Q.char.dmode)
      Q:Print(("dungeon mode: every quest for %s is done - back to the normal route"):format(d and d[1] or "the dungeon"))
      Q.char.dmode = nil
      P.dset = nil
      wipe(meta)
    end
  end
  local st = newState()
  if not st.pos then P.steps = {}; return end
  P.vendorUps = nil
  if Q.prefs.gear == "route" then
    local ok, ups = pcall(G.VendorUpgrades, G, st.level, st.pos, 2500)
    P.vendorUps = ok and ups or nil
  end
  local steps = {}
  local cands = effCut(candidates(st), st)
  local lastLevel = st.level
  for n = 1, P.MAX_STEPS do
    maybeYield()
    P.stick = (n == 1)
    local a, alt = bestAction(st, cands)
    P.stick = false
    if not a then break end
    -- another continent: get to the dock (flying if faster), take the boat / zeppelin
    local sp = speed(st.level)
    local cross = Q.Flight and a.point and st.pos and a.point.i ~= st.pos.i and Q.Flight:Cross(st.pos, a.point, sp, P.dset ~= nil)
    if cross and #steps < P.MAX_STEPS - 2 then
      local toDock = Q.Flight:Leg(st.pos, cross.from, sp, P.dset ~= nil)
      if toDock then
        steps[#steps + 1] = { type = "fly", point = toDock.from, from = toDock.from, to = toDock.to, level = st.level, quests = {},
          t = toDock.t, key = "fly:" .. toDock.to.id, npc = toDock.from.name,
          why = { "On the way to the " .. cross.route.kind .. ": flying is faster" } }
      end
      steps[#steps + 1] = { type = "boat", point = cross.from, from = cross.from, to = cross.to, route = cross.route,
        toName = cross.toName, kind = cross.route.kind, level = st.level, quests = {}, t = cross.ride,
        key = "boat:" .. cross.route.id .. ":" .. cross.to.i,
        why = { ("The next step is on another continent: take the %s to %s"):format(cross.route.kind, cross.toName) } }
      st.pos = cross.to
    end
    -- the way there is a flight: a step for it first
    local leg = Q.Flight and a.point and Q.Flight:Leg(st.pos, a.point, speed(st.level), P.dset ~= nil)
    if leg and #steps < P.MAX_STEPS - 1 then
      steps[#steps + 1] = { type = "fly", point = leg.from, from = leg.from, to = leg.to, level = st.level, quests = {},
        t = leg.t, key = "fly:" .. leg.to.id, npc = leg.from.name,
        why = { ("Flying saves about %s over running (%s instead of %s)"):format(mins(leg.walk - leg.t), mins(leg.t), mins(leg.walk)) } }
    end
    steps[#steps + 1] = makeStep(a, st, alt)
    apply(st, a)
    if a.type == "turnin" or st.level ~= lastLevel then
      cands = effCut(candidates(st), st)       -- new quests unlocked / new level window
      lastLevel = st.level
    else
      for i = #cands, 1, -1 do if st.log[cands[i]] then table.remove(cands, i) end end
    end
  end
  -- the step that just dropped off the top was done: keep it (the guide shows it, for notes)
  local old = P.steps and P.steps[1]
  if old and old.key and old.type ~= "fly" then
    local still = false
    for _, ns in ipairs(steps) do if ns.key == old.key then still = true; break end end
    if not still then P.prevStep = old end
  end
  P.steps = steps
  P:LogFirst(steps)
  P.endLevel, P.endXP, P.simTime = st.level, st.xp, st.time
  -- XP per second along the planned route (for "time to level")
  P.xpPerSec = (st.time > 60 and (st.gained or 0) > 0) and (st.gained / st.time) or nil
  P.buildMs = (debugprofilestop and debugprofilestop() or 0) - t0
  B = nil
  Q:Send("QC_PLAN_UPDATED", steps)
  return steps
end

-- what the first step is, and when / why it changed (for "it sent me back and forth" reports):
-- Q.char.routeLog keeps the last 40 changes; /qc routelog shows them
function P:LogFirst(steps)
  local s = steps[1]
  local real = s
  if s and s.type == "fly" then real = steps[2] or s end
  local key = s and (s.type == "fly" and ("fly:" .. s.to.id) or s.key) or nil
  P.stickKey = real and ((real.type == "fp" or real.type == "explore") and real.key or (real.type .. ":" .. ((real.quests and real.quests[1]) or real.item or 0))) or nil
  if key == P.lastFirst then return end
  P.lastFirst = key
  if not (s and Q.char) then return end
  Q.char.routeLog = Q.char.routeLog or {}
  local log = Q.char.routeLog
  local here = P.Here()
  local txt = Q.Guide and Q.Guide.StepText and Q.Guide.StepText(s, true) or s.type
  txt = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  log[#log + 1] = { t = time and time() or 0, step = txt, why = s.why and s.why[1], why2 = s.why and s.why[#s.why],
    i = here and here.i, x = here and math.floor(here.x), y = here and math.floor(here.y),
    log = (function() local n = 0 for _ in pairs(QS.log) do n = n + 1 end return n end)() }
  while #log > 40 do table.remove(log, 1) end
end
Q:Command("routelog", "the last changes of your first route step and why (helps when it sends you back and forth)", function()
  local log = Q.char.routeLog or {}
  if #log == 0 then Q:Print("nothing logged yet") return end
  for i = math.max(1, #log - 9), #log do
    local e = log[i]
    Q:Print(("%s  %s  - %s"):format(date and date("%H:%M:%S", e.t) or e.t, e.step, e.why2 or e.why or ""))
  end
end)

-- replans while you play are built in slices; P:Build() itself stays immediate
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
  if not P.co then self:Hide(); return end
  P.sliceStart = now()
  local ok, err = coroutine.resume(P.co)
  if coroutine.status(P.co) == "dead" then
    P.co = nil
    self:Hide()
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end)
function P:BuildAsync()
  -- collection mode doesn't guide: no route to work out (leaving it builds one right away)
  if Q.CollectOnly and Q.CollectOnly() then return end
  P.lastAsyncAt = now()
  if _G.QUESTICUS_SYNC or not coroutine then return P:Build() end
  P.co = coroutine.create(function() P:Build() end)
  P.sliceStart = now()
  local ok, err = coroutine.resume(P.co)          -- first slice right away
  if coroutine.status(P.co) == "dead" then
    P.co = nil
    if not ok and geterrorhandler then geterrorhandler()(err) end
    return
  end
  driver:Show()
end
-- a whole replan makes megabytes of garbage, so automatic ones are at least 5 s apart (changes
-- in between are gathered into one)
local REPLAN_GAP = 5
function P:Replan(delay)
  if Q.CollectOnly and Q.CollectOnly() then return end
  delay = delay or 0.4
  local since = P.lastAsyncAt and ((now() - P.lastAsyncAt) / 1000) or 999   -- (now() is in ms)
  if since + delay < REPLAN_GAP then delay = REPLAN_GAP - since end
  Q.Throttle("replan", delay, function()
    -- on a flight: plan once (from where it lands), then wait for the landing
    if Q.OnTaxi() then
      if P.taxiPlanned then P.afterTaxi = true; return end
      P.taxiPlanned = true
    end
    P:BuildAsync()
  end)
end
-- taking off: remember it (the landing always replans, so the "fly" step goes away)
Q:On("PLAYER_CONTROL_LOST", function()
  Q.After(1, function() if Q.OnTaxi() then P.wasTaxi = true end end)
end)
Q:On("PLAYER_CONTROL_GAINED", function()
  if Q.OnTaxi() then return end
  P.taxiPlanned = nil
  if P.afterTaxi or P.wasTaxi then P.afterTaxi, P.wasTaxi = nil, nil; P:Replan(0.3) end
end)
-- a flight step whose flight you're already on is done: replan from where it lands
Q:On("TAXIMAP_CLOSED", function() Q.After(1.5, function() if Q.OnTaxi() then P.wasTaxi = true; P:Replan(0.1) end end) end)

-- skip a quest for good (from the guide)
function P:SkipQuest(id)
  Q.char.skipped[id] = true
  QS:BuildPool()
  P:BuildAsync()
end

-- a kill or a loot that only moves an objective's count (3/8 -> 4/8) doesn't change the route: replan
-- when a quest comes, goes, is done or failed, or an objective finishes (a replan is megabytes of work)
local lastLogSig
local function logSig()
  local parts = {}
  for id, e in pairs(QS.log or {}) do
    parts[#parts + 1] = id .. (e.complete and "c" or "") .. (e.failed and "f" or "")
    for i, o in ipairs(e.objectives or {}) do if o.finished then parts[#parts + 1] = id .. "o" .. i end end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end
Q:On("QC_QUESTS_CHANGED", function()
  local sig = logSig()
  if sig == lastLogSig then return end
  lastLogSig = sig
  P:Replan(0.2)
end)
Q:On("QC_REPLAN", function() P:Replan(0.5) end)
Q:On("PLAYER_LEVEL_UP", function() P:Replan(1) end)
Q:On("ZONE_CHANGED_NEW_AREA", function() P:Replan(1) end)
-- a looted item can start a quest: compare the quest-starting items in the bags before / after
local startOf
Q:On("BAG_UPDATE_DELAYED", function()
  if not (Q.Data:Ready() and Q.Data.startItem) then return end
  if not startOf then
    startOf = {}
    for q, item in pairs(Q.Data.startItem) do startOf[item] = startOf[item] or q end
  end
  local prepBefore = P.dset and #P.PrepStages() or 0
  local old, new = P.bagSet or {}, scanBags()
  P.bagSet = new
  if not new then return end
  if P.dset and #P.PrepStages() ~= prepBefore then P:Replan(0.5); return end
  -- a quest that puts parts together: getting / using them changes where to go next
  for id in pairs(QS.log) do
    local m = meta[id]
    if m and m.lines then
      for _, l in ipairs(m.lines) do
        if l.part then
          P.partCounts = P.partCounts or {}
          local n = P.ItemCount(l.part)
          if P.partCounts[l.part] ~= n then P.partCounts[l.part] = n; P:Replan(0.5); return end
        end
      end
    end
  end
  local changed = false
  for item in pairs(new) do if startOf[item] and not old[item] and QS:Info(startOf[item]) then changed = true break end end
  if not changed then
    for item in pairs(old) do if startOf[item] and not new[item] and QS:Info(startOf[item]) then changed = true break end end
  end
  if changed then P:Replan(0.5) end
end)
Q:On("QC_READY", function() P.bagSet = scanBags() end)
Q:On("QC_PREFS_CHANGED", function()
  P:Reset()
  if QS.pool then QS:BuildPool() end
  P:BuildAsync()
end)
Q:On("QC_READY", function(ok)
  if ok and Q.char.surveyDone then Q.After(2, function() P:BuildAsync() end) end
end)
Q:Command("plan", "rebuild the route now", function() P:Build(); Q:Print(#(P.steps or {}) .. " steps planned") end)
Q:Command("unskip", "bring back every quest you skipped", function()
  wipe(Q.char.skipped)
  QS:BuildPool()
  P:Build()
  Q:Print("skipped quests are back in the route")
end)
