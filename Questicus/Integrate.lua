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

-- The quest log's search box on the world map: with Questicus Maps' resizable map window the game
-- could make it much wider than the quest log, so it ran off across the screen and pushed the buttons
-- that sit to its right (anchored to its right edge) out of sight. Its width is set so the box and
-- those buttons end at the quest list's right edge. Corrected inside the game's own SetWidth / SetPoint
-- calls (same frame: no flashing), out of combat only (it is Blizzard's frame).
local function searchBox()
  local qm = _G.QuestMapFrame
  local scroll = _G.QuestScrollFrame
  local box = (scroll and scroll.SearchBox) or (qm and qm.QuestsFrame and qm.QuestsFrame.SearchBox) or (qm and qm.SearchBox)
  return box, scroll
end
-- how far the frames chained to the box's right edge (buttons) reach past it; and where the first
-- other button on its row starts (the box must stop before it, not run under it)
local function rightExtent(box)
  local parent = box:GetParent()
  if not (parent and parent.GetChildren) then return 0 end
  local kids = { parent:GetChildren() }
  local chained, more = { [box] = true }, true
  local br = box:GetRight() or 0
  local reach = 0
  while more do
    more = false
    for _, c in ipairs(kids) do
      if not chained[c] and c.GetNumPoints then
        for i = 1, c:GetNumPoints() do
          local _, rel = c:GetPoint(i)
          if rel and chained[rel] then
            chained[c] = true; more = true
            if c:IsShown() and c:GetRight() then reach = math.max(reach, c:GetRight() - br) end
            break
          end
        end
      end
    end
  end
  local bl, bt, bb = box:GetLeft() or 0, box:GetTop() or 0, box:GetBottom() or 0
  local stop
  for _, c in ipairs(kids) do
    if not chained[c] and c.IsShown and c:IsShown() and c.GetLeft then
      local cl, ct, cb = c:GetLeft(), c:GetTop(), c:GetBottom()
      if cl and ct and cb and cl > bl + 40 and ct > bb and cb < bt and (c:GetWidth() or 0) < 80 then
        stop = math.min(stop or cl, cl)
      end
    end
  end
  return math.max(0, reach), stop
end
local fixing = false
function Q.FitQuestSearch()
  if fixing or (InCombatLockdown and InCombatLockdown()) then return end
  local box, scroll = searchBox()
  if not (box and scroll and box.GetRight and box:IsVisible()) then return end
  local l, r = box:GetLeft(), box:GetRight()
  local edge = (scroll.ScrollBar and scroll.ScrollBar:IsShown() and scroll.ScrollBar:GetRight()) or scroll:GetRight()
  if not (l and r and edge) then return end
  local reach, stop = rightExtent(box)
  local limit = math.min(edge, stop and (stop - 3) or edge)
  -- the game gives it its right width while there's text in it (seen in game): kept, and used when empty
  local typed = box.GetText and box:GetText() or ""
  if typed ~= "" then
    local w = box:GetWidth()
    if w and w >= 80 and r <= limit + 2 then Q.db.questSearchW = math.floor(w + 0.5) end
    return
  end
  local good = Q.db.questSearchW
  if good and good >= 80 and l + good + reach <= limit + 2 then limit = l + good + reach + 2 end
  local want = math.floor(limit - l - reach - 2)
  if want < 80 then return end
  -- only when it runs past the quest list or under a button (the game's own width otherwise stands)
  if r + reach <= limit + 2 then return end
  fixing = true
  if box:GetNumPoints() > 1 then
    local p, rel, rp, x, y = box:GetPoint(1)
    box:ClearAllPoints()
    box:SetPoint(p or "TOPLEFT", rel or scroll, rp or p or "TOPLEFT", x or 0, y or 0)
  end
  box:SetWidth(want)
  fixing = false
end
local function hookSearch()
  local box = searchBox()
  local qm = _G.QuestMapFrame
  if not box or Q.searchHooked then return end
  Q.searchHooked = true
  -- right after the game sizes or anchors it (same frame), and once laid out
  hooksecurefunc(box, "SetWidth", Q.FitQuestSearch)
  hooksecurefunc(box, "SetSize", Q.FitQuestSearch)
  hooksecurefunc(box, "SetPoint", Q.FitQuestSearch)
  box:HookScript("OnShow", Q.FitQuestSearch)
  box:HookScript("OnTextChanged", function() Q.After(0, Q.FitQuestSearch) end)
  box:HookScript("OnEditFocusLost", function() Q.After(0, Q.FitQuestSearch) end)
  box:HookScript("OnSizeChanged", Q.FitQuestSearch)
  if qm then qm:HookScript("OnShow", Q.FitQuestSearch); qm:HookScript("OnSizeChanged", Q.FitQuestSearch) end
  if WorldMapFrame then WorldMapFrame:HookScript("OnSizeChanged", Q.FitQuestSearch) end
  Q.FitQuestSearch()
end
Q:On("PLAYER_LOGIN", function() Q.After(2, hookSearch) end)
Q:On("PLAYER_REGEN_ENABLED", function() Q.After(0.2, Q.FitQuestSearch) end)
local captured = {}
local function capture(tag)
  if captured[tag] or not Q.db then return end
  captured[tag] = true
  local ok = pcall(function() SlashCmdList.QUESTICUS("questlogdebug quiet " .. tag) end)
end
Q:On("PLAYER_LOGIN", function()
  Q.After(3, function()
    local box = searchBox()
    if not box then return end
    box:HookScript("OnShow", function() Q.After(1, function() capture("open") end) end)
    box:HookScript("OnTextChanged", function(b) if b:GetText() ~= "" then Q.After(0.5, function() capture("typed") end) end end)
  end)
end)

-- /qc questlogdebug: the search box's row (its anchors, its neighbours' places) saved for a bug report
Q:Command("questlogdebug", "save the world map quest log's search bar layout (for a bug report)", function(arg)
  local quiet, tag = tostring(arg or ""):match("^(quiet)%s*(%S*)")
  local box = searchBox()
  if not box then Q:Print("no quest log search box found"); return end
  local function name(f) return f and (f.GetDebugName and f:GetDebugName() or f.GetName and f:GetName()) or tostring(f) end
  local function desc(f)
    local pts = {}
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do
      local p, rel, rp, x, y = f:GetPoint(i)
      pts[#pts + 1] = ("%s>%s:%s(%.0f,%.0f)"):format(tostring(p), name(rel), tostring(rp), x or 0, y or 0)
    end
    return ("%s shown=%s L=%.0f R=%.0f T=%.0f B=%.0f W=%.0f lvl=%s pts=%s"):format(name(f), tostring(f:IsShown()),
      f:GetLeft() or -1, f:GetRight() or -1, f:GetTop() or -1, f:GetBottom() or -1, f:GetWidth() or -1,
      tostring(f:GetFrameLevel()), table.concat(pts, " "))
  end
  local out = { "box: " .. desc(box), "parent: " .. desc(box:GetParent()) }
  local sc = _G.QuestScrollFrame
  if sc then out[#out + 1] = "scroll: " .. desc(sc) end
  if _G.QuestMapFrame then out[#out + 1] = "questmap: " .. desc(_G.QuestMapFrame) end
  for _, c in ipairs({ box:GetParent():GetChildren() }) do if c ~= box then out[#out + 1] = "kid: " .. desc(c) end end
  local qm = _G.QuestMapFrame
  if qm then for _, c in ipairs({ qm:GetChildren() }) do out[#out + 1] = "qmkid: " .. desc(c) end end
  local qf = qm and qm.QuestsFrame
  if qf and qf ~= box:GetParent() then for _, c in ipairs({ qf:GetChildren() }) do out[#out + 1] = "qfkid: " .. desc(c) end end
  Q.db.uiDebug = Q.db.uiDebug or {}
  Q.db.uiDebug[(tag and tag ~= "") and tag or "manual"] = out
  if not quiet then Q:Print("saved - /reload (or log out) so it's written to disk") end
end)
