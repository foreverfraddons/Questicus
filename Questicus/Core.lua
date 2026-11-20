-- Questicus: core namespace, saved variables, events, player info, helpers.
local ADDON = ...
local Q = {}
_G.Questicus = Q
Q.name = ADDON or "Questicus"
Q.version = "0.9.3"
-- on a flight path: heavy work (replans, map redraws) waits for the landing
-- WoW 12 "secret" values (GUIDs / names / health in some situations): never touch them as strings
function Q.Secret(v) return v ~= nil and issecretvalue ~= nil and issecretvalue(v) or false end
-- kind, id from a GUID; nil for a secret or odd one
function Q.ParseGUID(guid)
  if type(guid) ~= "string" or Q.Secret(guid) then return end
  local ok, kind, _, _, _, _, id = pcall(strsplit, "-", guid)
  if not ok or Q.Secret(kind) then return end
  return kind, tonumber(id)
end
function Q.UnitGUID(unit)
  if not UnitGUID then return end
  local ok, g = pcall(UnitGUID, unit)
  if ok and not Q.Secret(g) then return g end
end
function Q.UnitName(unit)
  if not UnitName then return end
  local ok, n = pcall(UnitName, unit)
  if ok and type(n) == "string" and not Q.Secret(n) then return n end
end
-- "c123" / "o123" for the npc / object a unit is, or nil
function Q.UnitKey(unit)
  local kind, id = Q.ParseGUID(Q.UnitGUID(unit))
  if not id then return end
  if kind == "Creature" or kind == "Vehicle" then return "c" .. id end
  if kind == "GameObject" then return "o" .. id end
end
function Q.OnTaxi() return UnitOnTaxi and UnitOnTaxi("player") and true or false end
Q.MEDIA = "Interface\\AddOns\\Questicus\\Media\\"

-- ------------------------------------------------------------------ events
local ev = CreateFrame("Frame")
local handlers = {}
function Q:On(event, fn)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    pcall(ev.RegisterEvent, ev, event)
  end
  list[#list + 1] = fn
end
function Q:Fire(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then Q:Debug("error in " .. event .. ": " .. tostring(err)) end
  end
end
ev:SetScript("OnEvent", function(_, event, ...) Q:Fire(event, ...) end)

-- internal messages (not game events) use the same dispatcher
Q.Send = Q.Fire

-- ------------------------------------------------------------------ output
function Q:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff3fd0c9Questicus|r: " .. tostring(msg))
end
function Q:Debug(msg)
  if QuesticusDB and QuesticusDB.debug then Q:Print("|cff888888" .. tostring(msg) .. "|r") end
end

-- ------------------------------------------------------------------ saved variables
local DEFAULT_GLOBAL = {
  debug = false,
  collect = true,           -- record quest spots / sources for the database (QuesticusCollect)
  guide = { shown = true, locked = false, scale = 1, next = 3 },
  arrow = { shown = true, scale = 1, locked = false },
  minimap = { hide = false, angle = 200 },   -- minimap button (Minimap.lua)
  pins = { world = true, minimap = true, size = 1, others = true, autoPin = true },
  popups = { on = true, sound = true },  -- pop-up cards for quest items / objective progress (Popup.lua)
  marks = { plates = true },   -- X on mobs you need, star on quest givers (nameplates)
}
-- per character: the survey answers drive everything (see Survey.lua)
local DEFAULT_PREFS = {
  style = "balanced",       -- speed | balanced | complete | custom
  levelRange = 2,           -- quests up to this many levels above you
  gray = false,             -- do gray (trivial) quests
  breadcrumbs = "useful",   -- skip | useful | all
  allInZone = false,        -- every quest in a zone before leaving it
  repeatable = false,       -- repeatable / reputation turn-ins
  rep = false,              -- weight reputation rewards
  classQuests = true,
  profQuests = false,
  seasonal = false,
  elite = "solo",           -- solo | some | group
  dungeons = false,
  collectibles = false,     -- route through rare / unique quest items worth keeping
  forever = true,           -- WoW Forever's new zones (Zephras Isle, Riverglades, Hyjal...)
  legacy = true,            -- classic routes through old zones
  gear = "route",           -- route | onway | off
  gold = 2,                 -- 1 low ... 3 high: how much gold rewards count
  xp = 3,                   -- 1 low ... 3 high
  hearth = true,            -- use the hearthstone in routes
  autoAccept = true,
  autoTurnIn = true,
  autoReward = true,        -- pick the best reward for your spec
  role = nil,               -- tank | heal | melee | ranged | caster (from the survey)
  spec = nil,
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      fill(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end
Q.fill = fill

function Q:InitDB()
  QuesticusDB = fill(QuesticusDB or {}, DEFAULT_GLOBAL)
  QuesticusChar = QuesticusChar or {}
  local c = QuesticusChar
  c.prefs = fill(c.prefs or {}, DEFAULT_PREFS)
  c.skipped = c.skipped or {}     -- [questID] = true: never route this quest
  c.stepDone = c.stepDone or {}   -- [stepKey] = true: manual "done" for steps the game can't see
  c.surveyDone = c.surveyDone or false
  Q.db, Q.char, Q.prefs = QuesticusDB, c, c.prefs
end

-- ------------------------------------------------------------------ player
local RACE_ID = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5, Tauren = 6, Gnome = 7, Troll = 8,
  Goblin = 9, BloodElf = 10, Draenei = 11 }
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
  WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }

function Q:ReadPlayer()
  local p = Q.player or {}
  local _, raceFile, raceID = UnitRace("player")
  p.race = raceID or RACE_ID[raceFile or ""] or 0
  local _, classFile, classID = UnitClass("player")
  p.class = classFile
  p.classID = classID or CLASS_ID[classFile or ""] or 0
  local fac = UnitFactionGroup("player")
  p.faction = fac == "Alliance" and "A" or (fac == "Horde" and "H" or "?")
  p.level = UnitLevel("player") or 1
  p.name = UnitName("player")
  p.maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  Q.player = p
  return p
end

-- bit k of a quest mask (masks can be wider than 32 bits, so plain arithmetic)
function Q.HasBit(mask, k)
  if not mask or mask == 0 then return true end
  local b = 2 ^ (k - 1)
  return math.floor(mask / b) % 2 == 1
end

-- ------------------------------------------------------------------ helpers
function Q.After(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

local throttled = {}
-- run fn at most once per `sec`, coalescing calls (used for replanning)
function Q.Throttle(key, sec, fn)
  if throttled[key] then return end
  throttled[key] = true
  Q.After(sec, function() throttled[key] = nil; fn() end)
end

-- item info: WoW Forever's client only has C_Item.GetItemInfo (the old global is gone)
function Q.GetItemInfo(item)
  local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
  if not f or item == nil then return nil end
  return f(item)
end

function Q.Round(x) return math.floor(x + 0.5) end

function Q.Color(hex, text) return "|cff" .. hex .. tostring(text) .. "|r" end

-- ------------------------------------------------------------------ slash
SLASH_QUESTICUS1, SLASH_QUESTICUS2 = "/questicus", "/qc"
Q.commands = {}
function Q:Command(name, help, fn) Q.commands[name] = { help = help, fn = fn } end
SlashCmdList.QUESTICUS = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  local c = Q.commands[cmd]
  if c then return c.fn(rest) end
  if cmd == "" then
    if Q.ToggleGuide then Q:ToggleGuide() end
    return
  end
  Q:Print("commands:")
  local names = {}
  for k in pairs(Q.commands) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do Q:Print("  /qc " .. k .. " - " .. Q.commands[k].help) end
end
Q:Command("help", "this list", function() SlashCmdList.QUESTICUS("?") end)
Q:Command("debug", "toggle debug output", function()
  Q.db.debug = not Q.db.debug
  Q:Print("debug " .. (Q.db.debug and "on" or "off"))
end)

-- ------------------------------------------------------------------ startup
Q:On("ADDON_LOADED", function(name)
  if name ~= Q.name then return end
  Q:InitDB()
end)

Q:On("PLAYER_LOGIN", function()
  if not Q.db then Q:InitDB() end
  Q:ReadPlayer()
  local ok = Q.Data and Q.Data:Load()
  Q:Send("QC_READY", ok)
  Q.ready = true
end)

-- the game hides every frame while logging out / reloading: that is not the player closing them
Q:On("PLAYER_LOGOUT", function() Q.loggingOut = true end)

Q:On("PLAYER_LEVEL_UP", function(lv)
  if Q.player then Q.player.level = lv or UnitLevel("player") end
end)
