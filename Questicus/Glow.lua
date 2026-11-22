-- Questicus: Highlights - ore, herbs, quest objects, chests and your fishing bobber light up as you
-- come up to them.
-- How: the game's soft targeting always picks ONE thing you could interact with (the "softinteract"
-- unit) and can give it a nameplate. Questicus puts a light on that nameplate, coloured by what the
-- object is (read from the cursor the game would show on it, its tooltip and your quest log), and
-- animated by its state: out of reach, within reach, or unusable for now. Questicus' own code and
-- art (Media\qg_*.tga); settings in QuesticusDB.glow (account) and the character's categories.
local Q = Questicus
local T = Q.T
local G = {}
Q.Glow = G

local UNIT = "softinteract"
local M = Q.MEDIA
local S = Q.Secret

G.CATS = { "ore", "herb", "quest", "chest", "bobber", "other" }
G.CAT_NAMES = { ore = "Ore", herb = "Herbs", quest = "Quest objects", chest = "Chests", bobber = "Fishing bobber", other = "Other objects" }
G.CAT_TIPS = {
  ore = "Mineral veins and deposits.",
  herb = "Plants you can gather.",
  quest = "Objects one of your quests needs.",
  chest = "Chests, crates and other things you can loot.",
  bobber = "The bobber of your fishing line.",
  other = "Everyday objects: doors, mailboxes, levers...",
}
G.SAMPLES = { ore = "Copper Vein", herb = "Peacebloom", quest = "Supply Crate", chest = "Battered Chest", bobber = "Fishing Bobber", other = "Mailbox" }
local SAMPLE_CURSOR = { ore = "Mine", herb = "GatherHerbs", quest = "Quest", chest = "Pickup", bobber = "Fishing", other = "Interact" }

local DEFAULTS = {
  on = true,
  range = 15,            -- how far the game may pick an object (yards; the client stops near 15)
  arc = 2,               -- 0 straight ahead, 1 in front, 2 all around
  effect = "aura",
  size = 110,
  intensity = 100,
  offsetY = -40,         -- the light, up / down from the object's nameplate
  follow = false,        -- fades with the nameplate (object behind scenery ...)
  name = true,           -- the object's name over it, written by Questicus instead of the game
  icon = true,           -- and its interaction icon
  textSize = 100,
  exclusive = true,      -- the game only points out what gets a light (no icons on every NPC)
  glowOnly = false,      -- the light only: name and icon left to the game
  hideCombat = false, hideInstance = false, hideLocked = false, hideUntrained = true,
  colors = {
    ore = { 1, 0.6, 0.18 }, herb = { 0.4, 1, 0.42 }, quest = { 1, 0.84, 0.15 },
    chest = { 0.45, 0.78, 1 }, bobber = { 1, 0.45, 0.4 }, other = { 0.9, 0.9, 0.94 },
  },
  own = {},              -- category -> its own look { effect, size, intensity, offsetY, ... }
  ignored = {},          -- lower-case name -> name: never lit
  silhouette = false,    -- the light is cut out around your character
  cut = { scale = 100, shift = 0 },
  switch = false,        -- two gathering professions: alternate Find Herbs / Find Minerals
  switchYards = 15,
  debug = false,
}
local CHAR_DEFAULTS = { ore = true, herb = true, quest = true, chest = true, bobber = true, other = false }
-- the settings a category can have its own value for (colour is always per category)
G.LOOK = { "effect", "size", "intensity", "offsetY", "follow", "name", "icon", "textSize" }
G.LIMITS = { range = { 5, 15 }, size = { 40, 300 }, intensity = { 30, 150 }, offsetY = { -200, 200 },
  textSize = { 60, 200 }, cutScale = { 40, 300 }, cutShift = { -100, 100 }, switchYards = { 10, 50 } }

local function fill(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      if type(v) == "table" then t[k] = fill({}, v) else t[k] = v end
    elseif type(v) == "table" and type(t[k]) == "table" and k ~= "own" and k ~= "ignored" then
      fill(t[k], v)
    end
  end
  return t
end
function G.cfg()
  Q.db.glow = fill(type(Q.db.glow) == "table" and Q.db.glow or {}, DEFAULTS)
  return Q.db.glow
end
function G.cats()
  Q.char.glowCats = fill(type(Q.char.glowCats) == "table" and Q.char.glowCats or {}, CHAR_DEFAULTS)
  return Q.char.glowCats
end
-- one look setting for a category: its own value, else everyone's
function G.Look(cat, key)
  local c = G.cfg()
  local own = cat and c.own[cat]
  if own and own[key] ~= nil then return own[key] end
  return c[key]
end
function G.Defaults() return DEFAULTS end

local function dprint(...)
  if G.cfg().debug then Q:Print("|cff888888highlight:|r " .. table.concat({ ... }, " ")) end
end

-- ------------------------------------------------------------------ game settings (soft targeting)
local CV = {
  "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetInteractArc", "SoftTargetNameplateInteract",
  "SoftTargetIconInteract", "SoftTargetIconGameObject",
}
local function getc(n)
  local f = (C_CVar and C_CVar.GetCVar) or GetCVar
  local ok, v = pcall(f, n)
  if ok and v ~= nil then return v end
end
local pendingCV = {}
local function setc(n, v)
  if getc(n) == nil then return end
  v = tostring(v)
  if getc(n) == v then return end
  if InCombatLockdown and InCombatLockdown() then pendingCV[n] = v return end
  local f = (C_CVar and C_CVar.SetCVar) or SetCVar
  pcall(f, n, v)
end
local fishing = false
function G.ApplyCVars()
  local c = G.cfg()
  if not c.on then
    -- off: the game gets back exactly what it had
    if c.orig then
      for n, v in pairs(c.orig) do setc(n, v) end
      c.orig = nil
    end
    return
  end
  if not c.orig then
    c.orig = {}
    for _, n in ipairs(CV) do c.orig[n] = getc(n) end
  end
  setc("SoftTargetInteract", 3)                                  -- always, mouse and keyboard too
  setc("SoftTargetInteractRange", fishing and 60 or c.range)     -- (a bobber often lands further out)
  setc("SoftTargetInteractArc", c.arc)
  setc("SoftTargetNameplateInteract", 1)                         -- the object gets a nameplate: the light's anchor
  if c.glowOnly then
    if c.orig.SoftTargetIconInteract then setc("SoftTargetIconInteract", c.orig.SoftTargetIconInteract) end
    if c.orig.SoftTargetIconGameObject then setc("SoftTargetIconGameObject", c.orig.SoftTargetIconGameObject) end
  else
    -- Questicus draws the icon itself on lit objects; exclusive: none on NPCs either
    setc("SoftTargetIconGameObject", 0)
    setc("SoftTargetIconInteract", c.exclusive and 0 or 1)
  end
end
Q:On("PLAYER_REGEN_ENABLED", function()
  for n, v in pairs(pendingCV) do pendingCV[n] = nil; setc(n, v) end
end)

-- ------------------------------------------------------------------ what is it?
local CURSOR_CAT = {
  mine = "ore", gatherherbs = "herb", picklock = "chest", lootall = "chest", pickup = "chest",
  fishing = "bobber", fishingcursor = "bobber", interact = "other", gamepadinteract = "other", inspect = "other",
}
local SERVICE = { mail = true, speak = true, buy = true, trainer = true, taxi = true, innkeeper = true,
  repair = true, repairnpc = true, stablemaster = true }
local BOBBER = { [35591] = true }
local CHEST_WORDS = { "chest", "crate", "strongbox", "coffer", "footlocker", "barrel", "cache", "stash", "lockbox", "box", "trunk", "sack" }

-- the cursor the game would show on it: "Mine", "UnableGatherHerbs", "QuestTurnIn" ...
local function cursorFile()
  if not UnitCursorTexture then return end
  local ok, t = pcall(UnitCursorTexture, UNIT)
  if not ok or t == nil or S(t) or type(t) ~= "string" then return end
  return (t:match("([^\\/]+)$") or t):gsub("%.%w+$", "")
end
G.cursorFile = cursorFile

-- quest objectives in the log, by the text of what they ask for (an object's name is found in it)
local objectiveText
local function objectives()
  if objectiveText then return objectiveText end
  objectiveText = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return objectiveText end
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local id = C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(i)
    if id and id > 0 then
      for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
        if not o.finished and type(o.text) == "string" then objectiveText[#objectiveText + 1] = { o.text:lower(), id } end
      end
    end
  end
  return objectiveText
end
Q:On("QUEST_LOG_UPDATE", function() objectiveText = nil end)
local function questFor(name)
  if not name then return end
  local n = name:lower()
  for _, e in ipairs(objectives()) do
    if e[1]:find(n, 1, true) then return e[2] end
  end
end

-- your gathering professions (herbalism 182, mining 186)
local trained
local function professions()
  if trained then return trained end
  trained = {}
  if GetProfessions and GetProfessionInfo then
    for _, i in ipairs({ GetProfessions() }) do
      if i then
        local _, _, _, _, _, _, line = GetProfessionInfo(i)
        if line == 182 then trained.herb = true elseif line == 186 then trained.ore = true end
      end
    end
  end
  -- (older clients: the skill list)
  if not (trained.herb or trained.ore) and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local n = GetSkillLineInfo(i)
      if n == "Herbalism" then trained.herb = true elseif n == "Mining" then trained.ore = true end
    end
  end
  return trained
end
G.Professions = professions
for _, ev in ipairs({ "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
  Q:On(ev, function() trained = nil end)
end

local function tooltipLines()
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return {} end
  local ok, data = pcall(C_TooltipInfo.GetUnit, UNIT)
  local out = {}
  if ok and data and data.lines then
    for _, l in ipairs(data.lines) do
      local t = l.leftText
      if type(t) == "string" and not S(t) then out[#out + 1] = t end
    end
  end
  return out
end

-- -> category, state ("far" | "ready" | "locked"), name, cursor file, quest id
function G.Classify()
  if not (UnitExists and UnitExists(UNIT)) then return end
  local okN, name = pcall(UnitName, UNIT)
  if not okN or S(name) then name = nil end
  if UnitIsPlayer and UnitIsPlayer(UNIT) then return end
  local cur = cursorFile()
  local lc = cur and cur:lower() or ""
  local locked = lc:find("^unable") ~= nil
  local base = lc:gsub("^unable", "")
  local cat = CURSOR_CAT[base]
  if base:find("quest") or base:find("campaign") or base:find("legendary") or base:find("important")
    or base:find("recurring") or base:find("wrapper") then cat = "quest" end
  if SERVICE[base] then cat = "service" end
  local qid
  -- tied to a quest you have: the game says so, or an objective names it
  local okQ, rel = pcall(C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest or function() end, UNIT)
  if okQ and rel == true then cat = "quest" end
  if cat ~= "service" then
    qid = questFor(name)
    if qid then cat = "quest" end
  end
  local guid = UnitGUID and UnitGUID(UNIT)
  if type(guid) == "string" and not S(guid) then
    local kind, id = Q.ParseGUID(guid)
    if kind == "GameObject" and id and BOBBER[id] then cat = "bobber" end
    if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then
      if not cat or cat == "other" then cat = "service" end   -- people and animals: not ours to light
    end
  end
  if (not cat or cat == "other") and name then
    local ln = name:lower()
    if ln:find("bobber", 1, true) then cat = "bobber"
    elseif ln:find(" vein", 1, true) or ln:find(" deposit", 1, true) then cat = "ore"
    else
      for _, w in ipairs(CHEST_WORDS) do if ln:find(w, 1, true) then cat = "chest" break end end
    end
    if not cat or cat == "other" then
      for _, l in ipairs(tooltipLines()) do
        if l:find("Herbalism", 1, true) then cat = "herb" break end
        if l:find("Mining", 1, true) then cat = "ore" break end
        if l:find("Lockpicking", 1, true) or l:find("Locked", 1, true) then cat = "chest" break end
      end
    end
  end
  cat = cat or "other"
  local state = "far"
  local okR, inR = pcall(UnitIsInInteractRange or function() end, UNIT)
  if okR and inR == true then state = "ready" end
  if locked then state = "locked" end
  return cat, state, name, cur, qid
end

-- should it get a light at all? (nil, why) when not
function G.Wanted(cat, state, name)
  local c = G.cfg()
  if not c.on then return nil, "off" end
  if cat == "service" then return nil, "a character or a service" end
  if not G.cats()[cat] then return nil, "category off" end
  if name and c.ignored[name:lower()] then return nil, "ignored" end
  if c.hideCombat and UnitAffectingCombat and UnitAffectingCombat("player") then return nil, "in combat" end
  if c.hideInstance and IsInInstance and select(2, IsInInstance()) ~= "none" and select(2, IsInInstance()) ~= nil then return nil, "in an instance" end
  if c.hideLocked and state == "locked" then return nil, "unusable for now" end
  if c.hideUntrained and (cat == "herb" or cat == "ore") and not professions()[cat] then return nil, "profession not learned" end
  return true
end

-- ------------------------------------------------------------------ light effects
-- Each: build(f) makes its textures in frame f, run(f, t, size, r, g, b, a, st) draws one moment
-- (st: "far" | "ready" | "locked"; t: seconds since the light came on).
local E = {}
G.EFFECTS = E
G.EFFECT_ORDER = { "aura", "subtle", "sigil", "brackets", "vortex", "flame", "rift", "storm", "geyser",
  "spirit", "beam", "beacon", "orbit", "ripple", "sparkle" }
G.EFFECT_NAMES = {
  aura = "Aura", subtle = "Subtle", sigil = "Sigil", brackets = "Brackets", vortex = "Vortex", flame = "Flame",
  rift = "Rift", storm = "Storm", geyser = "Geyser", spirit = "Spirit", beam = "Beam", beacon = "Beacon",
  orbit = "Orbit", ripple = "Ripple", sparkle = "Sparkles",
}
G.EFFECT_TIPS = {
  aura = "A halo with a turning ring, two comets and drifting fireflies.",
  subtle = "Just a soft glow.",
  sigil = "A circle of runes turns around the object.",
  brackets = "Four corners close in and lock on once it's within reach.",
  vortex = "Arms of light coil around the object.",
  flame = "Tongues of fire in the object's colour.",
  rift = "A dark hole ringed with light pulls sparks in.",
  storm = "A cloud over the object, lightning falling from it.",
  geyser = "Sparks burst up from the object and fall back around it.",
  spirit = "Two wisps dance around it, each with a trail.",
  beam = "A column of light rises from the object.",
  beacon = "A crystal hovers over it on a thread of light.",
  orbit = "Three wisps circle it on their own orbits.",
  ripple = "Rings spread out on the ground around it.",
  sparkle = "Glints twinkle around it.",
}

local ALL = setmetatable({}, { __mode = "k" })   -- effect frame -> its textures
G.lockT = setmetatable({}, { __mode = "k" })   -- brackets: how locked on they are
G.ALL = ALL
local function tex(f, file, layer, sub, blend)
  local t = f:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(M .. file)
  t:SetBlendMode(blend or "ADD")
  ALL[f] = ALL[f] or {}
  table.insert(ALL[f], t)
  return t
end
local function at(t, f, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("CENTER", f, "CENTER", x or 0, y or 0)
  t:SetSize(math.max(1, w), math.max(1, h or w))
end
local function col(t, r, g, b, a) t:SetVertexColor(r, g, b, math.max(0, math.min(1, a))) end
local function spin(t, ang)
  if t.SetRotation then t:SetRotation(ang) end
end
local PI2 = math.pi * 2
local sin, cos = math.sin, math.cos
local function speed(st) return st == "ready" and 1.6 or st == "locked" and 0.4 or 1 end

E.aura = {
  build = function(f)
    f.halo = tex(f, "qg_glow", "ARTWORK", 0)
    f.ring = tex(f, "qg_ring", "ARTWORK", 1)
    f.com = { tex(f, "qg_spark", "ARTWORK", 2), tex(f, "qg_spark", "ARTWORK", 2) }
    f.fly = {}
    for i = 1, 6 do f.fly[i] = tex(f, "qg_glow", "ARTWORK", 3) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    local pulse = 0.85 + 0.15 * sin(t * 3 * k)
    at(f.halo, f, 0, 0, s * 1.1 * pulse); col(f.halo, r, g, b, a * 0.75)
    at(f.ring, f, 0, 0, s * (0.78 + 0.04 * sin(t * 2))); col(f.ring, r, g, b, a * 0.8); spin(f.ring, t * 0.6 * k)
    for i, c in ipairs(f.com) do
      local ang = t * 2.2 * k + i * math.pi
      at(c, f, cos(ang) * s * 0.37, sin(ang) * s * 0.37, s * 0.22); col(c, r, g, b, a)
    end
    for i, fl in ipairs(f.fly) do
      local ph = (t * 0.35 * k + i / #f.fly) % 1
      at(fl, f, sin(i * 2.4 + t) * s * 0.35, -s * 0.2 + ph * s * 0.7, s * 0.08)
      col(fl, r, g, b, a * sin(ph * math.pi))
    end
  end,
}
E.subtle = {
  build = function(f) f.halo = tex(f, "qg_glow") end,
  run = function(f, t, s, r, g, b, a, st)
    at(f.halo, f, 0, 0, s * (0.9 + 0.08 * sin(t * 2 * speed(st)))); col(f.halo, r, g, b, a * 0.7)
  end,
}
E.sigil = {
  build = function(f) f.halo = tex(f, "qg_glow", "ARTWORK", 0); f.runes = tex(f, "qg_runes", "ARTWORK", 1); f.inner = tex(f, "qg_runes", "ARTWORK", 1) end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, 0, s * 0.8); col(f.halo, r, g, b, a * 0.45)
    at(f.runes, f, 0, 0, s); col(f.runes, r, g, b, a * 0.95); spin(f.runes, t * 0.35 * k)
    at(f.inner, f, 0, 0, s * 0.62); col(f.inner, r, g, b, a * 0.55); spin(f.inner, -t * 0.5 * k)
  end,
}
E.brackets = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.c = {}
    for i = 1, 4 do f.c[i] = tex(f, "qg_bracket", "ARTWORK", 1) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local lock = st == "ready" and 1 or 0
    local lt = (G.lockT[f] or 0)
    lt = lt + (lock - lt) * 0.15
    G.lockT[f] = lt
    local d = s * (0.48 - 0.16 * lt) + (1 - lt) * s * 0.03 * sin(t * 4)
    local cs = s * 0.3
    local pos = { { -1, 1, 0 }, { 1, 1, -math.pi / 2 }, { 1, -1, math.pi }, { -1, -1, math.pi / 2 } }
    for i, c in ipairs(f.c) do
      at(c, f, pos[i][1] * d, pos[i][2] * d, cs); col(c, r, g, b, a); spin(c, pos[i][3])
    end
    at(f.halo, f, 0, 0, s * 0.7); col(f.halo, r, g, b, a * (0.25 + 0.35 * lt))
  end,
}
E.vortex = {
  build = function(f) f.halo = tex(f, "qg_glow"); f.sw = tex(f, "qg_swirl", "ARTWORK", 1); f.sw2 = tex(f, "qg_swirl", "ARTWORK", 1) end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, 0, s * 0.8); col(f.halo, r, g, b, a * 0.5)
    at(f.sw, f, 0, 0, s * 1.05); col(f.sw, r, g, b, a); spin(f.sw, -t * 1.4 * k)
    at(f.sw2, f, 0, 0, s * 0.7); col(f.sw2, r, g, b, a * 0.6); spin(f.sw2, -t * 2.1 * k + 1)
  end,
}
E.flame = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.fl = {}
    for i = 1, 5 do f.fl[i] = tex(f, "qg_flame", "ARTWORK", 1) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, -s * 0.1, s * 0.75); col(f.halo, r, g, b, a * 0.55)
    for i, fl in ipairs(f.fl) do
      local x = (i - 3) * s * 0.11
      local h = s * (0.55 + 0.2 * sin(t * 7 * k + i * 1.7) + 0.08 * sin(t * 13 * k + i))
      at(fl, f, x, -s * 0.25 + h / 2, s * 0.28, h)
      col(fl, r * 0.6 + 0.4, g * 0.75 + 0.1, b * 0.6, a * (i == 3 and 1 or 0.75))
    end
  end,
}
E.rift = {
  build = function(f)
    f.core = tex(f, "qg_glow", "ARTWORK", 0, "BLEND")
    f.edge = tex(f, "qg_ring_soft", "ARTWORK", 1)
    f.sp = {}
    for i = 1, 8 do f.sp[i] = tex(f, "qg_spark", "ARTWORK", 2) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.core, f, 0, 0, s * 0.62); col(f.core, 0, 0, 0, a * 0.85)
    at(f.edge, f, 0, 0, s * 0.72 * (1 + 0.04 * sin(t * 3))); col(f.edge, r, g, b, a); spin(f.edge, t * k)
    for i, p in ipairs(f.sp) do
      local ph = (t * 0.5 * k + i / #f.sp) % 1
      local rad = s * 0.6 * (1 - ph)
      local ang = i * 2.1 + ph * 5
      at(p, f, cos(ang) * rad, sin(ang) * rad, s * 0.12 * (1 - ph * 0.5)); col(p, r, g, b, a * sin(ph * math.pi))
    end
  end,
}
E.storm = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.cloud = tex(f, "qg_cloud", "ARTWORK", 1, "BLEND")
    f.bolt = tex(f, "qg_bolt", "ARTWORK", 2)
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.cloud, f, 0, s * 0.62, s * 1.0, s * 0.5); col(f.cloud, 0.35 + r * 0.25, 0.35 + g * 0.25, 0.4 + b * 0.25, a * 0.8)
    local cyc = (t * 0.9 * k) % 1.6
    local flash = cyc < 0.12 and 1 or (cyc > 0.2 and cyc < 0.27) and 0.7 or 0
    at(f.bolt, f, (math.floor(t * 0.9 * k / 1.6) % 3 - 1) * s * 0.12, s * 0.2, s * 0.25, s * 0.7)
    col(f.bolt, r * 0.5 + 0.5, g * 0.5 + 0.5, b * 0.5 + 0.5, a * flash)
    at(f.halo, f, 0, -s * 0.12, s * 0.7); col(f.halo, r, g, b, a * (0.35 + 0.4 * flash))
  end,
}
E.geyser = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.p = {}
    for i = 1, 10 do f.p[i] = tex(f, "qg_glow", "ARTWORK", 1) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, -s * 0.15, s * 0.7); col(f.halo, r, g, b, a * 0.55)
    for i, p in ipairs(f.p) do
      local ph = (t * 0.55 * k + i / #f.p) % 1
      local vx = ((i * 37) % 11 - 5) / 5
      local x = vx * s * 0.35 * ph
      local y = -s * 0.15 + s * 1.6 * ph - s * 1.7 * ph * ph
      at(p, f, x, y, s * 0.09); col(p, r, g, b, a * (1 - ph))
    end
  end,
}
E.spirit = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.w = {}
    for i = 1, 2 do
      f.w[i] = {}
      for j = 1, 6 do f.w[i][j] = tex(f, "qg_glow", "ARTWORK", 1) end
    end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, 0, s * 0.6); col(f.halo, r, g, b, a * 0.35)
    for i, trail in ipairs(f.w) do
      for j, p in ipairs(trail) do
        local tt = t * 1.8 * k - j * 0.09
        local ang = tt + i * math.pi
        local x = cos(ang) * s * 0.4
        local y = sin(ang * 2) * s * 0.14 + sin(tt * 0.7 + i) * s * 0.08
        at(p, f, x, y, s * (0.16 - j * 0.018)); col(p, r, g, b, a * (1 - j / 7))
      end
    end
  end,
}
E.beam = {
  build = function(f)
    f.halo = tex(f, "qg_glow"); f.col = tex(f, "qg_beam", "ARTWORK", 1)
    f.p = {}
    for i = 1, 6 do f.p[i] = tex(f, "qg_spark", "ARTWORK", 2) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, -s * 0.15, s * 0.7); col(f.halo, r, g, b, a * 0.55)
    at(f.col, f, 0, s * 0.45, s * 0.35, s * 1.3); col(f.col, r, g, b, a * (0.75 + 0.15 * sin(t * 3)))
    f.col:SetTexCoord(0, 1, 1, 0)
    for i, p in ipairs(f.p) do
      local ph = (t * 0.4 * k + i / #f.p) % 1
      at(p, f, sin(i * 1.9 + t) * s * 0.08, -s * 0.1 + ph * s * 1.1, s * 0.1); col(p, r, g, b, a * (1 - ph))
    end
  end,
}
E.beacon = {
  build = function(f)
    f.halo = tex(f, "qg_glow"); f.line = tex(f, "qg_beam", "ARTWORK", 1); f.gem = tex(f, "qg_gem", "ARTWORK", 2)
    f.gl = tex(f, "qg_glow", "ARTWORK", 1)
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    local bob = sin(t * 2 * k) * s * 0.05
    at(f.halo, f, 0, -s * 0.15, s * 0.55); col(f.halo, r, g, b, a * 0.5)
    at(f.line, f, 0, s * 0.25, s * 0.06, s * 0.75); col(f.line, r, g, b, a * 0.7); f.line:SetTexCoord(0, 1, 1, 0)
    at(f.gl, f, 0, s * 0.68 + bob, s * 0.5); col(f.gl, r, g, b, a * 0.6)
    at(f.gem, f, 0, s * 0.68 + bob, s * 0.26, s * 0.36); col(f.gem, r * 0.5 + 0.5, g * 0.5 + 0.5, b * 0.5 + 0.5, a)
  end,
}
E.orbit = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.w = {}
    for i = 1, 3 do f.w[i] = tex(f, "qg_glow", "ARTWORK", 1) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, 0, s * 0.55); col(f.halo, r, g, b, a * 0.45)
    for i, w in ipairs(f.w) do
      local ang = t * (1.2 + i * 0.35) * k + i * 2.1
      local tilt = i * 1.05
      local ox, oy = cos(ang) * s * 0.45, sin(ang) * s * 0.16
      local x, y = ox * cos(tilt) - oy * sin(tilt), ox * sin(tilt) + oy * cos(tilt)
      at(w, f, x, y, s * 0.2); col(w, r, g, b, a)
    end
  end,
}
E.ripple = {
  build = function(f)
    f.halo = tex(f, "qg_glow")
    f.rg = {}
    for i = 1, 3 do f.rg[i] = tex(f, "qg_ring", "ARTWORK", 1) end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    at(f.halo, f, 0, -s * 0.2, s * 0.5, s * 0.25); col(f.halo, r, g, b, a * 0.6)
    for i, rg in ipairs(f.rg) do
      local ph = (t * 0.45 * k + i / 3) % 1
      at(rg, f, 0, -s * 0.2, s * 1.2 * ph, s * 0.45 * ph); col(rg, r, g, b, a * (1 - ph))
    end
  end,
}
E.sparkle = {
  build = function(f)
    f.p = {}
    for i = 1, 9 do f.p[i] = tex(f, "qg_spark") end
  end,
  run = function(f, t, s, r, g, b, a, st)
    local k = speed(st)
    for i, p in ipairs(f.p) do
      local ph = (t * 0.6 * k + i * 0.37) % 1
      local seed = math.floor(t * 0.6 * k + i * 0.37)
      local x = (((seed * 7 + i * 13) % 17) / 17 - 0.5) * s * 0.9
      local y = (((seed * 11 + i * 5) % 19) / 19 - 0.5) * s * 0.9
      at(p, f, x, y, s * 0.2 * sin(ph * math.pi)); col(p, r, g, b, a * sin(ph * math.pi))
    end
  end,
}

-- a light: one frame per effect (made when first used), the active one shown
local function newLight(parent)
  local L = CreateFrame("Frame", nil, parent)
  L:SetSize(10, 10)
  L.fx = {}
  function L:Use(name)
    name = E[name] and name or "aura"
    if self.cur == name then return self.fx[name] end
    for _, fx in pairs(self.fx) do fx:Hide() end
    local fx = self.fx[name]
    if not fx then
      fx = CreateFrame("Frame", nil, self)
      fx:SetAllPoints(self)
      E[name].build(fx)
      self.fx[name] = fx
      if self.mask then for _, t in ipairs(ALL[fx] or {}) do if t.AddMaskTexture then pcall(t.AddMaskTexture, t, self.mask) end end end
    end
    fx:Show()
    self.cur = name
    return fx
  end
  function L:Draw(t, size, rgb, alpha, st)
    local fx = self.fx[self.cur]
    if not fx then return end
    local r, g, b = rgb[1], rgb[2], rgb[3]
    if st == "locked" then r, g, b = r * 0.35 + 0.3, g * 0.35 + 0.3, b * 0.35 + 0.3 end   -- greyed: not usable now
    E[self.cur].run(fx, t, size, r, g, b, alpha, st)
  end
  -- cut out around your character (a full-screen mask with a soft hole)
  function L:SetCutout(on)
    if on and not self.mask and self.CreateMaskTexture then
      local mk = self:CreateMaskTexture()
      mk:SetTexture(M .. "qg_hole", "CLAMP", "CLAMP")
      mk:SetAllPoints(UIParent)
      self.mask = mk
      for _, fx in pairs(self.fx) do
        for _, t in ipairs(ALL[fx] or {}) do if t.AddMaskTexture then pcall(t.AddMaskTexture, t, mk) end end
      end
    end
    if self.mask then
      if on then G.PlaceCutout(self.mask) else
        for _, fx in pairs(self.fx) do
          for _, t in ipairs(ALL[fx] or {}) do if t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, self.mask) end end
        end
        self.mask = nil
      end
    end
  end
  return L
end
G.NewLight = newLight

-- where your character is on screen (the middle, a little low; size / height to taste per character)
function G.CutoutRect()
  local c = G.cfg()
  local cs = Q.char.glowCut or {}
  local sc = (cs.scale or c.cut.scale or 100) / 100
  local sh = (cs.shift or c.cut.shift or 0) / 100
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local hw, hh = 170 * sc, 300 * sc
  local cx, cy = W / 2, H / 2 - 30 + sh * hh
  return cx, cy, hw, hh, W, H
end
function G.PlaceCutout(mk)
  local cx, cy, hw, hh, W, H = G.CutoutRect()
  -- the mask covers the screen; its texture coordinates put the soft hole over the character
  local u0, u1 = 0.5 - cx / hw * 0.5, 0.5 + (W - cx) / hw * 0.5
  local v0, v1 = 0.5 - (H - cy) / hh * 0.5, 0.5 + cy / hh * 0.5
  mk:SetTexCoord(u0, u1, v0, v1)
end

-- ------------------------------------------------------------------ the light in the world
local host = CreateFrame("Frame", "QuesticusGlow", UIParent)
host:SetFrameStrata("BACKGROUND")
host:SetAllPoints(UIParent)
local light = newLight(host)
light:Hide()
local label = host:CreateFontString(nil, "OVERLAY")
label:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
local icon = host:CreateTexture(nil, "OVERLAY")
icon:SetSize(22, 22)
G.light, G.label, G.icon = light, label, icon

local cur = {}            -- what's lit: { key, cat, state, name, cursor, since, shown }
local fade = 0            -- 0..1 how much of the light is on
local stateSince, shownState, flashT = 0, "far", -9
local hiddenPlate

local function plateOf()
  local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(UNIT)
  return np
end

-- the game's own name on the object's nameplate: Questicus writes its own instead
local function gameName(plate, show)
  local uf = plate and (plate.UnitFrame or plate.unitFrame)
  local nm = uf and (uf.name or uf.Name)
  if nm and nm.SetAlpha then pcall(nm.SetAlpha, nm, show and 1 or 0) end
end

local function key()
  local g = UnitGUID and UnitGUID(UNIT)
  if type(g) == "string" and not S(g) then return g end
  local ok, n = pcall(UnitName, UNIT)
  return ok and not S(n) and n or "?"
end

local POLL = 0.12
local pollAcc = 0
local function poll()
  local cat, st, name, cursor, qid = G.Classify()
  local want = cat and G.Wanted(cat, st, name)
  local plate = cat and plateOf()
  if hiddenPlate and hiddenPlate ~= plate then gameName(hiddenPlate, true); hiddenPlate = nil end
  if not (want and plate) then
    if cat and plate and G.cfg().exclusive and not G.cfg().glowOnly then gameName(plate, false); hiddenPlate = plate end
    cur.on = false
    return
  end
  local k = key()
  if cur.key ~= k then
    cur.key, cur.since = k, GetTime()
    shownState, stateSince = st, GetTime()
    if G.cfg().debug then dprint(tostring(name), "->", cat, st, "(cursor " .. tostring(cursor) .. (qid and (", quest " .. qid) or "") .. ")") end
  end
  -- a state has to hold a moment before it shows (no flicker); unusable more carefully still
  if st ~= cur.state then cur.state, cur.stateAt = st, GetTime() end
  local hold = st == "locked" and 0.6 or 0.15
  if st ~= shownState and GetTime() - (cur.stateAt or 0) >= hold then
    if st == "ready" then flashT = GetTime() end
    shownState = st
  end
  cur.on, cur.cat, cur.name, cur.cursor, cur.plate = true, cat, name, cursor, plate
  local c = G.cfg()
  local showName, showIcon = G.Look(cat, "name") and not c.glowOnly, G.Look(cat, "icon") and not c.glowOnly
  if showName then gameName(plate, false); hiddenPlate = plate end
  cur.showName, cur.showIcon = showName, showIcon
end

local lastX, lastY
host:SetScript("OnUpdate", function(_, el)
  pollAcc = pollAcc + el
  if pollAcc >= POLL then pollAcc = 0; poll() end
  local target = cur.on and 1 or 0
  local step = el / (cur.on and 0.45 or 0.4)
  if fade < target then fade = math.min(target, fade + step) elseif fade > target then fade = math.max(target, fade - step) end
  if fade <= 0 then light:Hide(); label:Hide(); icon:Hide(); return end
  local c = G.cfg()
  local cat = cur.cat or "other"
  local plate = cur.plate
  if cur.on and plate and plate.IsShown and plate:IsShown() then
    local x, y = plate:GetCenter()
    if x and not S(x) then
      local ps, us = plate:GetEffectiveScale(), UIParent:GetEffectiveScale()
      lastX, lastY = x * ps / us, y * ps / us
    end
  end
  if not lastX then return end
  local size = G.Look(cat, "size") or 110
  local off = G.Look(cat, "offsetY") or -40
  light:ClearAllPoints()
  light:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lastX, lastY + off)
  light:SetSize(size, size)
  light:Use(G.Look(cat, "effect"))
  light:SetCutout(c.silhouette)
  light:Show()
  local t = GetTime() - (cur.since or GetTime())
  local inten = (G.Look(cat, "intensity") or 100) / 100
  local a = fade * inten * (shownState == "far" and 0.6 or shownState == "locked" and 0.5 or 1)
  if G.Look(cat, "follow") and plate and plate.GetAlpha then
    local pa = plate:GetAlpha()
    if pa and not S(pa) then a = a * pa end
  end
  -- the moment it comes within reach: a flash
  local fl = GetTime() - flashT
  local scale = 1
  if fl < 0.5 then scale = 1 + 0.25 * math.sin(fl / 0.5 * math.pi); a = math.min(1.5, a * (1 + 0.6 * (1 - fl / 0.5))) end
  light:Draw(t, size * scale, c.colors[cat] or c.colors.other, math.min(1, a), shownState)
  -- name and icon over it
  local ts = (G.Look(cat, "textSize") or 100) / 100
  if cur.showName and cur.name then
    label:SetFont(STANDARD_TEXT_FONT, 13 * ts, "OUTLINE")
    label:ClearAllPoints()
    label:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", lastX, lastY + 6)
    local rgb = c.colors[cat] or c.colors.other
    label:SetTextColor(rgb[1] * 0.4 + 0.6, rgb[2] * 0.4 + 0.6, rgb[3] * 0.4 + 0.6, fade)
    label:SetText(cur.name)
    label:Show()
  else
    label:Hide()
  end
  if cur.showIcon and cur.cursor then
    icon:SetTexture("Interface\\Cursor\\" .. cur.cursor)
    icon:SetSize(22 * ts, 22 * ts)
    icon:ClearAllPoints()
    if label:IsShown() then icon:SetPoint("BOTTOM", label, "TOP", 0, 2) else icon:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", lastX, lastY + 6) end
    icon:SetAlpha(fade)
    icon:Show()
  else
    icon:Hide()
  end
end)

-- ------------------------------------------------------------------ fishing: further out while the line is in
local FISHING_ICON = 136245
local function channelCheck()
  local ok, name, _, tx = pcall(UnitChannelInfo, "player")
  local now = ok and tx == FISHING_ICON or false
  if now ~= fishing then
    fishing = now
    G.ApplyCVars()
  end
end
Q:On("UNIT_SPELLCAST_CHANNEL_START", function(u) if u == "player" then channelCheck() end end)
Q:On("UNIT_SPELLCAST_CHANNEL_STOP", function(u) if u == "player" then Q.After(1.5, channelCheck) end end)

-- ------------------------------------------------------------------ two gathering professions: alternate the trackings
local FIND = { herb = 2383, ore = 2580 }      -- Find Herbs, Find Minerals
local lastSwitchAt
local function trackingIndex(spellName)
  if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
  for i = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(i)
    local nm = type(info) == "table" and info.name or info
    if nm == spellName then return i, type(info) == "table" and info.active end
  end
end
local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end
function G.SwitchTracking()
  local c = G.cfg()
  if not (c.switch and c.on) or (InCombatLockdown and InCombatLockdown()) then return end
  local p = professions()
  if not (p.herb and p.ore) then return end
  local hi, hon = trackingIndex(spellName(FIND.herb))
  local oi, oon = trackingIndex(spellName(FIND.ore))
  if not (hi and oi and C_Minimap.SetTracking) then return end
  if hon then pcall(C_Minimap.SetTracking, oi, true) else pcall(C_Minimap.SetTracking, hi, true) end
end
local moveAcc = 0
local moveFrame = CreateFrame("Frame")
moveFrame:SetScript("OnUpdate", function(_, el)
  moveAcc = moveAcc + el
  if moveAcc < 1 then return end
  moveAcc = 0
  local c = Q.db and Q.db.glow
  if not (c and c.switch and c.on) then return end
  local here = Q.Data and Q.Data:PlayerPos()
  if not here then return end
  if not lastSwitchAt or lastSwitchAt.i ~= here.i then lastSwitchAt = here return end
  if Q.Data.Dist(here, lastSwitchAt) >= (c.switchYards or 15) then
    lastSwitchAt = here
    G.SwitchTracking()
  end
end)

-- ------------------------------------------------------------------ the interact key (the game's own)
function G.InteractKey() return GetBindingKey and GetBindingKey("INTERACTTARGET") end
function G.SetInteractKey(k)
  if InCombatLockdown and InCombatLockdown() then Q:Print("key bindings can't change in combat.") return end
  local old = G.InteractKey()
  if old then pcall(SetBinding, old) end
  if k then
    local taken = GetBindingAction and GetBindingAction(k)
    if taken and taken ~= "" and taken ~= "INTERACTTARGET" then Q:Print(k .. " no longer does \"" .. (_G["BINDING_NAME_" .. taken] or taken) .. "\".") end
    if not SetBinding(k, "INTERACTTARGET") then Q:Print("the game refused the key " .. k .. ".") end
  end
  if SaveBindings and GetCurrentBindingSet then pcall(SaveBindings, GetCurrentBindingSet()) end
end

-- ------------------------------------------------------------------ ignoring objects
function G.Ignore(name)
  if not name then
    local ok, n = pcall(UnitName, UNIT)
    name = ok and not S(n) and n or nil
  end
  if not name then Q:Print("no object in front of you to ignore.") return end
  local c = G.cfg()
  local k = name:lower()
  if c.ignored[k] then
    c.ignored[k] = nil
    Q:Print(name .. " is no longer ignored.")
  else
    c.ignored[k] = name
    Q:Print(name .. " won't light up any more (/qc glow ignore again on it to undo).")
  end
end

-- ------------------------------------------------------------------ start / commands
function G.SetOn(on)
  local c = G.cfg()
  c.on = on and true or false
  G.ApplyCVars()
  if not c.on then cur.on = false; if hiddenPlate then gameName(hiddenPlate, true); hiddenPlate = nil end end
  Q:Print("highlights " .. (c.on and "on." or "off - your own targeting settings are back."))
end

Q:On("PLAYER_LOGIN", function()
  G.cfg(); G.cats()
  Q.After(1, G.ApplyCVars)
end)
Q:On("PLAYER_ENTERING_WORLD", function() Q.After(2, G.ApplyCVars) end)

local function status()
  local c = G.cfg()
  local p = professions()
  Q:Print(("highlights %s, effect %s, range %d, direction %d, exclusive %s, glow only %s"):format(c.on and "on" or "off",
    c.effect, c.range, c.arc, tostring(c.exclusive), tostring(c.glowOnly)))
  local on = {}
  for _, k in ipairs(G.CATS) do if G.cats()[k] then on[#on + 1] = G.CAT_NAMES[k] end end
  Q:Print("lit on this character: " .. table.concat(on, ", ") .. " | herbalism " .. tostring(p.herb and true or false) .. ", mining " .. tostring(p.ore and true or false))
  for _, n in ipairs(CV) do Q:Print("  " .. n .. " = " .. tostring(getc(n))) end
  local cat, st, name, cursor = G.Classify()
  if cat then Q:Print(("in front of you: %s -> %s, %s (cursor %s)"):format(tostring(name), cat, st, tostring(cursor))) end
end

Q:Command("glow", "highlights: /qc glow [on | off | effect <name> | ignore | ignore list | ignore clear | status | debug]", function(arg)
  local a = tostring(arg or ""):lower()
  local c = G.cfg()
  if a == "" then if G.ShowSettings then G.ShowSettings() else status() end
  elseif a == "on" then G.SetOn(true)
  elseif a == "off" then G.SetOn(false)
  elseif a == "status" then status()
  elseif a == "debug" then c.debug = not c.debug; Q:Print("highlight diagnostics " .. (c.debug and "on" or "off"))
  elseif a == "ignore" then G.Ignore()
  elseif a == "ignore list" then
    local l = {}
    for _, n in pairs(c.ignored) do l[#l + 1] = n end
    table.sort(l)
    Q:Print(#l == 0 and "no object is ignored." or ("ignored: " .. table.concat(l, ", ")))
  elseif a == "ignore clear" then c.ignored = {}; Q:Print("no object is ignored any more.")
  elseif a:match("^effect") then
    local e = a:match("^effect%s+(%S+)")
    if e and E[e] then c.effect = e; Q:Print("effect: " .. G.EFFECT_NAMES[e])
    else Q:Print("effects: " .. table.concat(G.EFFECT_ORDER, ", ") .. " (now " .. c.effect .. ")") end
  else
    Q:Print("/qc glow [on | off | effect <name> | ignore | ignore list | ignore clear | status | debug]")
  end
end)
