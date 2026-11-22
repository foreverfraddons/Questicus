-- Questicus collection mode: Questicus stops guiding (no guide window, arrow, route lines, map
-- waypoint or auto accept / hand in) and only records, for the database and for later routes:
--   * everything the recorder always keeps (objective spots, loot sources, quest givers / takers)
--   * the paths you walk (Paths.lua) and how long objectives take you (Learn.lua)
--   * every quest's reward as you hand it in: XP, money, your level (QuesticusCollect.qrw)
--   * the order you did things in, with where and when (QuesticusCollect.route[character])
-- Recording also runs outside collection mode; this mode is for playing your own way (or with
-- another guide) while Questicus watches. Per character: /qc collectonly or the Options window.
local Q = Questicus
local D, QS = Q.Data, Q.Quests
local CM = {}
Q.CollectMode = CM

local ROUTE_MAX = 4000

function Q.CollectOnly() return Q.char ~= nil and Q.char.collectOnly == true end

local function db()
  QuesticusCollect = QuesticusCollect or {}
  local c = QuesticusCollect
  c.qrw = c.qrw or {}
  c.route = c.route or {}
  return c
end
CM.db = db

local function charKey()
  local n = Q.UnitName and Q.UnitName("player") or (UnitName and UnitName("player")) or "?"
  local realm = GetRealmName and GetRealmName() or ""
  return tostring(n) .. "-" .. tostring(realm)
end

local function where()
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return map end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x then return map end
  return map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

-- one entry of the route log: { what, quest, map, x, y, time (seconds played this session), level }
function CM:Log(what, id)
  if not (Q.db and Q.db.collect ~= false) then return end
  local r = db().route
  local k = charKey()
  local list = r[k]
  if not list then list = {}; r[k] = list end
  local map, x, y = where()
  list[#list + 1] = { what, id or 0, map or 0, x or 0, y or 0, math.floor(GetTime and GetTime() or 0), Q.player and Q.player.level or 0 }
  if #list > ROUTE_MAX then table.remove(list, 1) end
  return list[#list]
end

-- what a quest really gave (the game passes XP and money with QUEST_TURNED_IN)
function CM:Reward(id, xp, money)
  if not (id and Q.db and Q.db.collect ~= false) then return end
  local lv = Q.player and Q.player.level or 0
  local t = db().qrw
  local e = t[id]
  if not e then e = {}; t[id] = e end
  e[lv] = { tonumber(xp) or 0, tonumber(money) or 0 }
  return e[lv]
end

local function safe(v) if Q.Secret and Q.Secret(v) then return nil end return v end
Q:On("QUEST_ACCEPTED", function(a, b)
  local id = safe(b) or safe(a)     -- (index, questID) on old clients, (questID) on new ones
  if type(id) == "number" then CM:Log("a", id) end
end)
Q:On("QUEST_TURNED_IN", function(id, xp, money)
  id, xp, money = safe(id), safe(xp), safe(money)
  if type(id) ~= "number" then return end
  CM:Log("t", id)
  CM:Reward(id, xp, money)
end)
Q:On("TAXIMAP_CLOSED", function() if UnitOnTaxi and UnitOnTaxi("player") then CM:Log("f", 0) end end)
Q:On("PLAYER_LEVEL_UP", function(lv) CM:Log("l", tonumber(safe(lv)) or 0) end)

local function hideGuiding()
  local g = Q.Guide and Q.Guide.Frame and Q.Guide.Frame()
  if g then g:Hide() end
  if Q.Arrow and Q.Arrow.Update then pcall(Q.Arrow.Update, Q.Arrow) end
  if Q.Waypoint then Q.Waypoint:Clear() end
  if Q.Pins then
    if Q.Pins.RefreshWorld then Q.Pins:RefreshWorld(true) end
    if Q.Pins.RefreshMinimap then Q.Pins:RefreshMinimap() end
  end
end

function CM:Set(on)
  Q.char.collectOnly = on and true or nil
  if on then
    hideGuiding()
    Q:Print("collection mode on: Questicus records routes, quests, XP and rewards and doesn't guide")
  else
    Q:Print("collection mode off: guiding again")
    if Q.Planner then Q.Planner:BuildAsync() end
    Q:ShowGuide()
  end
  -- the map and minimap: emptied of Questicus' icons in collection mode, back when it's off
  if Q.Pins then
    if Q.Pins.RefreshWorld then Q.Pins:RefreshWorld(true) end
    if Q.Pins.RefreshMinimap then Q.Pins:RefreshMinimap() end
  end
end

-- how much has been collected
function CM:Counts()
  local c = db()
  local n = { rewards = 0, route = 0, spots = 0, sources = 0, npcs = 0 }
  for _ in pairs(c.qrw) do n.rewards = n.rewards + 1 end
  for _, l in pairs(c.route) do n.route = n.route + #l end
  for _ in pairs(c.qsp or {}) do n.spots = n.spots + 1 end
  for _ in pairs(c.qsrc or {}) do n.sources = n.sources + 1 end
  for _ in pairs(c.sp or {}) do n.npcs = n.npcs + 1 end
  return n
end

Q:On("QC_READY", function() if Q.CollectOnly() then hideGuiding() end end)

Q:Command("collectonly", "collection mode: only record (routes, quests, XP, rewards), no guiding - on / off", function()
  CM:Set(not Q.CollectOnly())
  local n = CM:Counts()
  Q:Print(("collected so far: %d quest rewards, %d route entries, %d quests with objective spots, %d loot sources, %d NPC spots")
    :format(n.rewards, n.route, n.spots, n.sources, n.npcs))
end)
