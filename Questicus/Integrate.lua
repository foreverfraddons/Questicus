-- Questicus + Command Center: when Command Center is installed, Questicus uses its theme colours
-- and shows up as one of its tools (home tile, Tools window, dock, Button Box). Without Command
-- Center, Questicus runs on its own (its own minimap button, the same look).
local Q = Questicus
local T = Q.T

local registered = false
local function register()
  local CC = _G.CommandCenter
  if registered or not (CC and CC.RegisterTool) then return end
  registered = CC:RegisterTool({
    label = "Questicus",
    desc = "Step-by-step questing: route, arrow, map pins and gear upgrades",
    icon = Q.MEDIA .. "icon",
    tint = false,
    window = "QuesticusGuide",
    available = function() return true end,
    isOn = function() local f = Q.Guide.Frame(); return f and f:IsShown() or false end,
    set = function(on)
      if on then Q:ShowGuide() else local f = Q.Guide.Frame(); if f then f:Hide() end end
    end,
  }) and true or false
end

T.ApplyCommandCenter()        -- colours before any Questicus window is built
register()
Q:On("PLAYER_LOGIN", function() T.ApplyCommandCenter(); register() end)
Q.WithCommandCenter = function() return registered end

-- ------------------------------------------------------------------ Questicus Maps
-- Questicus Maps (the built-in world map, from OpenMap - WorldMap\): Questicus draws on its stitched
-- world map (route, steps, objectives, quest
-- givers placed by world position, so they show across the whole stitched view and above its art),
-- adds its switches to the map's menu and its quests to its dungeon cards. (With the standalone
-- OpenMap addon still on, the same is done through its OpenMapAPI.)
local omHooked = false
local function openMap()
  local OM = _G.QuesticusMapAPI or _G.OpenMapAPI
  local ev = (OM == _G.QuesticusMapAPI) and "QuesticusMap_" or "OpenMap_"
  if omHooked or type(OM) ~= "table" or not OM.CanvasFromWorldPos then return end
  omHooked = true
  local PN, P, QS, D = Q.Pins, Q.Planner, Q.Quests, Q.Data
  PN.openMap = true
  local owner = "Questicus"
  local function redraw() Q.Throttle("openmap", 0.15, function() PN:RefreshWorld() end) end
  if OM.RegisterCallback then
    pcall(OM.RegisterCallback, owner, ev .. "ViewChanged", redraw)
    pcall(OM.RegisterCallback, owner, ev .. "StitchedChanged", redraw)
  end
  if OM.RegisterMenuToggle then
    local icon = Q.MEDIA .. "icon"
    local function toggle(id, label, get, set)
      pcall(OM.RegisterMenuToggle, owner, { id = id, label = label, icon = icon, section = "Questicus", get = get, set = function(v) set(v); PN:RefreshWorld() end })
    end
    toggle("route", "Route and steps", function() return Q.db.pins.world ~= false end, function(v) Q.db.pins.world = v end)
    toggle("objectives", "Quest objectives", function() return Q.db.pins.objectives ~= false end, function(v) Q.db.pins.objectives = v end)
    toggle("givers", "Quests you can pick up", function() return Q.db.pins.others == true end, function(v) Q.db.pins.others = v end)
    toggle("areas", "Objective areas", function() return Q.db.pins.areas ~= false end, function(v) Q.db.pins.areas = v end)
    toggle("rares", "Rares and notable drops", function() return Q.prefs.collectibles == true end, function(v) Q.prefs.collectibles = v end)
  end
  if OM.RegisterDungeonSection and Q.Dungeons then
    pcall(OM.RegisterDungeonSection, owner, function(info)
      local lines = {}
      local lv = Q.player.level or 1
      for _, inst in ipairs((info and info.instances) or {}) do
        for _, e in ipairs(Q.Dungeons:List()) do
          if e.name == inst.name then
            for _, id in ipairs(e.quests) do
              local qi = QS:Info(id)
              if qi and #lines < 38 then
                local st = Q.Dungeons:QuestStatus(id, lv)
                lines[#lines + 1] = ("[%d] %s  |cff9d9d9d%s|r"):format(qi.level, qi.title, st)
              end
            end
          end
        end
      end
      if #lines == 0 then return nil end
      lines[#lines + 1] = "|cff9d9d9d/qc dungeons - Get all quests routes you to them|r"
      return "Questicus quests", lines
    end)
  end
  PN:RefreshWorld()
end
Q.OpenMapHook = openMap
Q.MapHook = openMap
Q:On("QC_READY", openMap)
Q:On("ADDON_LOADED", function(name) if name == "OpenMap" then Q.After(0.5, openMap) end end)
