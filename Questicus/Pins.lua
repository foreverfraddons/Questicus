-- Questicus map pins: route steps, objective areas, every quest you can pick up, rares and
-- notable drops on the world map; the current target and nearby objectives on the minimap.
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local PN = {}
Q.Pins = PN

local vec = D.vec
local ICON = Q.Guide.ICON
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local DOT = Q.MEDIA .. "dot"
PN.STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
PN.CROSS = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"
PN.SKULL8 = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

-- ------------------------------------------------------------------ pools
local function pool(parent, size)
  local p = { used = 0, list = {}, parent = parent, size = size }
  function p:Get()
    self.used = self.used + 1
    local b = self.list[self.used]
    if not b then
      b = CreateFrame("Button", nil, self.parent)
      b:SetSize(self.size, self.size)
      b.tex = b:CreateTexture(nil, "ARTWORK")
      b.tex:SetAllPoints()
      b.num = T.Text(b, 9, T.c.text, "OUTLINE")
      b.num:SetPoint("BOTTOMRIGHT", 3, -2)
      b:SetScript("OnEnter", function(s)
        local tip = s.tip
        if not tip and s.tipFn then tip = s.tipFn(s) end        -- built only when you point at it
        if not tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        QS.tipItems = tip.items
        for i, l in ipairs(tip) do
          if i == 1 then GameTooltip:AddLine(l, 1, 0.82, 0.3, true) else GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
        end
        -- the quest's objective text and id (a step pin: each of its quests)
        local qs = (not tip.hasId) and (s.quests or (s.quest and { s.quest })) or {}
        for k, qid in ipairs(qs) do
          if k > 3 then break end
          if #qs > 1 then local i = QS:Info(qid); GameTooltip:AddLine(i and i.title or ("Quest " .. qid), 1, 0.82, 0.3, true) end
          for _, l in ipairs(QS:TipExtra(qid)) do GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
        end
        if s.spot or s.spotK then GameTooltip:AddLine("Ctrl-click: wrong spot? Remove it from the database", 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:SetScript("OnClick", function(s)
        -- Ctrl-click: nothing is there - remove the spot (for you now, for everyone via the recordings)
        local key, where = s.spotK, s.spotP
        if not key and s.spot then key, where = s.spot[1], s.spot[2] end
        if key and IsControlKeyDown and IsControlKeyDown() then
          GameTooltip:Hide()
          D:RemoveSpot(key, where)
          return
        end
        if s.step then Q.Guide.focus = s.step; Q.Guide:Refresh() end
      end)
      self.list[self.used] = b
    end
    b:SetFrameLevel((self.parent:GetFrameLevel() or 1) + 5)
    b.lvlOff = 5
    b:Show()
    return b
  end
  function p:Release()
    for i = 1, #self.list do
      local b = self.list[i]
      b:Hide(); b.tip = nil; b.step = nil; b.spot = nil; b.quest = nil; b.quests = nil
      b.tipFn, b.spotK, b.spotP, b.ta, b.tb, b.tc, b.td = nil, nil, nil, nil, nil, nil, nil
    end
    self.used = 0
  end
  return p
end

local function style(b, tex, size, r, g, bl, a, num)
  b.tex:SetTexture(tex)
  b.tex:SetVertexColor(r or 1, g or 1, bl or 1, a or 1)
  b:SetSize(size, size)
  b.num:SetText(num or "")
end

-- position of a point on map `mapID` (0-1), or nil
local function onMap(pt, mapID, loose)    -- loose: a little past the map's edge too (route corners)
  -- Questicus Maps' stitched world map: the canvas shows past its own map, place by world position
  local OM = PN.openMap and (_G.QuesticusMapAPI or _G.OpenMapAPI)
  if OM and pt.i and pt.x and OM.IsStitched() then
    local ok, x, y = pcall(OM.CanvasFromWorldPos, pt.i, pt.x, pt.y)
    if ok and x and x > -1.5 and x < 2.5 and y > -1.5 and y < 2.5 then return x, y end
    if ok then return end
  end
  local m, x, y = D:MapPos(pt)
  if m == mapID then return x, y end
  if not (C_Map and C_Map.GetMapPosFromWorldPos) then return end
  local ok, m2, pos = pcall(C_Map.GetMapPosFromWorldPos, pt.i, vec(pt.x, pt.y), mapID)
  if ok and m2 == mapID and pos then
    local px, py = pos.x, pos.y
    if pos.GetXY then px, py = pos:GetXY() end
    local lo, hi = loose and -0.6 or 0, loose and 1.6 or 1
    if px and px >= lo and px <= hi and py >= lo and py <= hi then return px, py end
  end
end

PN.OnMap = onMap

-- ------------------------------------------------------------------ rares (collectibles layer)
local rareDrops
local function rares()
  if rareDrops then return rareDrops end
  rareDrops = {}
  for npc, n in pairs(D.db.npc) do
    if n[5] == 2 or n[5] == 4 then rareDrops[npc] = {} end
  end
  for item, row in pairs(D.db.drop or {}) do
    local rec = D:Item(item)
    if rec and (rec[2] or 0) >= 2 then
      for i = 1, #row - 1, 2 do
        local t = rareDrops[row[i]]
        if t and #t < 6 then t[#t + 1] = { item = item, chance = (row[i + 1] or 0) / 100 } end
      end
    end
  end
  return rareDrops
end

-- ------------------------------------------------------------------ world map
local wpool, canvas, lastMap, lastScale, lastW, lastH
-- the canvas' real scale (the map's zoom): what the pins are drawn against
local function canvasScale(sc)
  local c = sc and sc.Child
  local k = c and c.GetScale and c:GetScale()
  if type(k) == "number" and k > 0 then return k end
  return sc and sc.GetCanvasScale and sc:GetCanvasScale() or 1
end
PN.CanvasScale = canvasScale
local available, availableFor = nil, nil

local function availableQuests()
  if available and availableFor == QS.logCount then return available end
  available = {}
  for _, id in ipairs(QS.pool or {}) do
    local info = QS:Info(id)
    if info and QS:Available(id) and info.level <= Q.player.level + 4 then available[#available + 1] = id end
  end
  availableFor = QS.logCount
  return available
end

-- What the drawing depends on. The same as last time: nothing is redrawn (the icons, quest areas
-- and lines stay as drawn). It changes with the map shown, the canvas size, your settings, the quest
-- log (accepting / handing in), and the route steps on the map (the step you're on and the next two,
-- with their open objectives). Moving only redraws the line from you (PN:DrawLeg).
local function signature(mapID, cw, ch)
  local pins = Q.db.pins
  local parts = { mapID or 0, math.floor((cw or 0) + 0.5), math.floor((ch or 0) + 0.5),
    pins.size or 1, tostring(pins.world), tostring(pins.objectives), tostring(pins.others),
    tostring(pins.areas), tostring(pins.areasNext), tostring(Q.prefs.collectibles),
    tostring(D:Ready()), tostring(Q.char.surveyDone), QS.logCount or 0, tostring(Q.CollectOnly and Q.CollectOnly() or false),
    Q.OnTaxi() and "t" or "g", Q.Guide.focus or 1 }
  if D:Ready() and Q.char.surveyDone then
    for k, e in ipairs(PN.RouteSteps()) do
      local st = e.step
      -- (the step you're on points at its nearest open spot, which changes as you walk: that only
      -- moves its icon and the line from you - PN:DrawLeg - so its fixed point counts here)
      local pt = (k == 1 and st.type == "complete") and st.point or e.point
      parts[#parts + 1] = ("%s:%s:%s:%s:%s"):format(e.index, st.type or "", table.concat(st.quests or {}, ","),
        pt and math.floor((pt.x or 0) + 0.5) or "-", pt and math.floor((pt.y or 0) + 0.5) or "-")
      if st.type == "complete" then parts[#parts + 1] = #P.StepPoints(st) end
    end
  end
  return table.concat(parts, "|")
end

-- Questicus' layer over the map's art; the game's waypoint / super-tracked pin (the yellow diamond
-- at the place Questicus pinned) goes under it, so the step icon and its number stay readable.
-- Checked again whenever the game moves or re-adds that pin (it lays its pins out by itself).
local WP_TEMPLATES = { "WaypointLocationPinTemplate", "SuperTrackedPinTemplate" }
local function eachWaypointPin(fn)
  if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
  for _, tmpl in ipairs(WP_TEMPLATES) do
    local ok, it = pcall(WorldMapFrame.EnumeratePinsByTemplate, WorldMapFrame, tmpl)
    if ok and it then for pin in it do fn(pin) end end
  end
end
local MAX_LEVEL = 9800
-- (no new functions per call: FixLevel runs every frame for 2 s after the map opens)
local fixLvl = 0
local function raiseOver(pin)
  local pl = pin.GetFrameLevel and pin:GetFrameLevel() or 0
  if pl >= fixLvl and pl + 10 <= MAX_LEVEL then fixLvl = pl + 10 end
end
local function pushUnder(pin)
  if pin.SetFrameLevel and (pin:GetFrameLevel() or 0) >= fixLvl then pcall(pin.SetFrameLevel, pin, fixLvl - 1) end
end
function PN:FixLevel()
  if not (PN.overlay and canvas) then return end
  local lvl = (canvas:GetFrameLevel() or 1) + 2500
  local OMA = PN.openMap and (_G.QuesticusMapAPI or _G.OpenMapAPI)
  if OMA then lvl = math.max(lvl, (tonumber(OMA.ArtTopLevel()) or 0) + 20) end
  -- Questicus Maps' own icons (its waypoint marker among them, up to 5 over its icon level) are on a
  -- layer of the map's view, not the canvas: over those too
  if OMA and WorldMapFrame.GetPinFrameLevelsManager then
    local okM, fl = pcall(WorldMapFrame.GetPinFrameLevelsManager, WorldMapFrame)
    if okM and fl and fl.GetValidFrameLevel then
      local okL, il = pcall(fl.GetValidFrameLevel, fl, "PIN_FRAME_LEVEL_QUESTICUSMAP_ICONS")
      if okL and tonumber(il) then lvl = math.max(lvl, il + 8) end
    end
  end
  fixLvl = lvl
  eachWaypointPin(raiseOver)
  lvl = math.min(MAX_LEVEL, fixLvl)
  local old = PN.overlay:GetFrameLevel() or lvl
  if old ~= lvl then
    if Q.Trace then Q.Trace(("Questicus layer %d -> %d"):format(old, lvl)) end
    PN.overlay:SetFrameLevel(lvl)
    -- (each icon keeps its own distance above the layer: step icon over its ring over the dots)
    if wpool then
      for i = 1, #wpool.list do local b = wpool.list[i]; b:SetFrameLevel(lvl + (b.lvlOff or 5)) end
    end
    if PN.areaLayer then PN.areaLayer:SetFrameLevel(math.max(1, lvl - 1)) end
  end
  -- a waypoint pin still at or above our layer (the game puts it high): down under it
  fixLvl = lvl
  eachWaypointPin(pushUnder)
end

-- the next draw happens whatever the signature says (a spot removed, a patrol recorded, a loading screen)
function PN:Invalidate() PN.sig = nil end

function PN:RefreshWorld(force)
  if force then PN.sig = nil end
  if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
  local sc = WorldMapFrame.ScrollContainer
  canvas = sc and sc.Child
  if not canvas then return end
  -- our own layer above the map's tiles and Blizzard's pins (pins parented straight to the canvas
  -- end up underneath the map textures and never show)
  if not PN.overlay then
    PN.overlay = CreateFrame("Frame", nil, canvas)
    PN.overlay:SetAllPoints(canvas)
  end
  PN.overlay:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "HIGH")
  PN:FixLevel()
  PN.overlay:Show()
  if not wpool then wpool = pool(PN.overlay, 18) end
  do
    local sig = signature(WorldMapFrame:GetMapID(), canvas:GetWidth(), canvas:GetHeight())
    if sig == PN.sig then
      -- (the size the same to the pixel that counts: remembered, so the next frame doesn't check again)
      lastW, lastH = canvas:GetWidth(), canvas:GetHeight()
      local cs = canvasScale(sc)
      if lastScale and math.abs(cs - lastScale) > lastScale * 1e-4 then PN:Rescale(cs) end
      PN:DrawLeg()
      return
    end
    -- (why, for the open-the-map trace: the first part of the signature that changed)
    if Q.Trace then
      local why = "first"
      if PN.sig then
        local a, b, i = {}, {}, 0
        for x in (PN.sig .. "|"):gmatch("([^|]*)|") do a[#a + 1] = x end
        for x in (sig .. "|"):gmatch("([^|]*)|") do b[#b + 1] = x end
        local NAMES = { "map", "width", "height", "size", "world", "objectives", "others", "areas", "areasNext",
          "collectibles", "db", "survey", "log", "collect", "taxi", "focus" }
        for j = 1, math.max(#a, #b) do if a[j] ~= b[j] then i = j break end end
        why = (NAMES[i] or ("step part " .. i)) .. " " .. tostring(a[i]) .. " -> " .. tostring(b[i])
      end
      Q.Trace("redraw: " .. why)
    end
    PN.sig = sig
    PN.draws = (PN.draws or 0) + 1
  end
  wpool:Release()
  PN:ReleasePatrolHits()
  PN:ReleaseAreas()
  for _, l in ipairs(PN.lines) do l.bg:Hide(); l.fg:Hide() end
  local mapID = WorldMapFrame:GetMapID()
  -- (collection mode: Questicus only records - nothing of its own on the map)
  if not (Q.db.pins.world and D:Ready() and Q.char.surveyDone) or (Q.CollectOnly and Q.CollectOnly()) then
    lastMap, lastScale, lastW, lastH = mapID, canvasScale(sc), canvas:GetWidth(), canvas:GetHeight()
    PN.leg = nil
    PN:DrawLeg()
    return
  end
  local cs = canvasScale(sc)
  local cw, ch = canvas:GetWidth(), canvas:GetHeight()
  local size = 18 * (Q.db.pins.size or 1)
  lastMap, lastScale, lastW, lastH = mapID, cs, cw, ch
  local function place(b, x, y)
    b.qx, b.qy = x, y
    b:SetScale(1 / cs)
    b:ClearAllPoints()
    b:SetPoint("CENTER", canvas, "TOPLEFT", x * cw * cs, -y * ch * cs)
  end
  -- every quest you can pick up (Questie-style)
  if Q.db.pins.others then
    for _, id in ipairs(availableQuests()) do
      local info = QS:Info(id)
      for _, k in ipairs(info and info.givers or {}) do
        for _, pt in ipairs(D:Points(k)) do
          local x, y = onMap(pt, mapID)
          if x then
            local b = wpool:Get()
            style(b, PN.STAR, size * 0.75, 1, 1, 1, 0.9)
            b.tip = QS:QuestTip(id, D:Name(k), "Quest you can pick up")
            b.spot = { k, pt }
            place(b, x, y)
            b.quest = id
            break
          end
        end
      end
    end
  end
  -- Questie-style: the open objectives of every quest in your log, and ? where finished ones go back
  if Q.db.pins.objectives ~= false then
    PN:Objectives(mapID, size, place)
  end
  -- rares and their notable drops
  if Q.prefs.collectibles then
    for npc, drops in pairs(rares()) do
      for _, pt in ipairs(D:Points("c" .. npc)) do
        local x, y = onMap(pt, mapID)
        if x then
          local n = D:NPC(npc)
          local b = wpool:Get()
          style(b, SKULL, size * 0.8, 1, 0.85, 0.4, 1)
          local tip = { n[1], ("Rare, level %s"):format(n[3] or "?") }
          for _, d in ipairs(drops) do
            tip[#tip + 1] = ("%s  %s"):format(D:Name("i" .. d.item), d.chance > 0 and (("%.1f%%"):format(d.chance)) or "")
          end
          b.tip = tip
          place(b, x, y)
          break
        end
      end
    end
  end
  -- the current step and the next two: colour coded icons, objective areas and the route line
  local shown = PN.RouteSteps()
  local prev = D:PlayerPos()
  local px, py, prevPt
  if prev then px, py = onMap(prev, mapID) end
  local li = 0
  for k, e in ipairs(shown) do
    local col, s, pt = PN.COLORS[k], e.step, e.point
    -- objective area (kill / collect spots) in the step's colour
    if s.type == "complete" then
      local all = {}
      local patrolled = {}
      for _, sp in ipairs(P.StepPoints(s)) do
        local op, id = sp.p, sp.id
        local path = D:Patrol(op.key)
        if path then
          -- a patrolling mob: draw its path once, with one icon where it's closest to you
          if not patrolled[op.key] then
            patrolled[op.key] = true
            local ax, ay
            local mp = {}
            for _, wp in ipairs(path) do
              local x, y = onMap(wp, mapID)
              if x and ax then
                li = li + 1
                PN:Line(li, ax, ay, x, y, col, k == 1 and 3 or 2, cw, ch, cs)
              end
              if x then mp[#mp + 1] = { x, y } end
              ax, ay = x, y
            end
            -- hovering the line says what patrols there and lifts the line above the icons
            PN:PatrolHits({ key = op.key, quest = id, label = PN.LABELS[k], col = col, pts = mp, step = e.index },
              cw, ch, cs, place)
            local nearest = D.Nearest(PN.lastHere or path[1], path) or path[1]
            local x, y = onMap(nearest, mapID)
            if x then
              local b = wpool:Get()
              style(b, k == 1 and PN.SKULL8 or DOT, size * (k == 1 and 0.7 or 0.5), k == 1 and 1 or col[1],
                k == 1 and 1 or col[2], k == 1 and 1 or col[3], 1)
              b.tip = { QS:Info(id).title, D:Name(op.key) .. " patrols along this line", PN.LABELS[k] }
              b.step = e.index
              b.quest = id
              place(b, x, y)
            end
          end
        else
          local x, y = onMap(op, mapID)
          if x then
            all[#all + 1] = { op, x, y, id, e.index, k }
            local b = wpool:Get()
            local mob = type(op.key) == "string" and op.key:sub(1, 1) == "c"
            if k == 1 and mob then
              style(b, PN.SKULL8, size * 0.62, 1, 1, 1, 1)    -- the step you're on: skull on its mobs
            else
              style(b, DOT, size * (k == 1 and 0.55 or 0.42), col[1], col[2], col[3], k == 1 and 0.95 or 0.7)
            end
            b.tip = { QS:Info(id).title, D:Name(op.key or ""), PN.LABELS[k] }
            b.step = e.index
            b.quest = id
            if op.key and op.key:sub(1, 1) ~= "t" then b.spot = { op.key, op } end
            place(b, x, y)
          end
        end
      end
      PN:Areas(all, col, k, cw, ch)
    end
    local x, y
    if pt then x, y = onMap(pt, mapID) end
    if k == 1 then PN.leg = x and { pt = pt, col = col, mapID = mapID, cw = cw, ch = ch, live = s.type == "complete" } or nil end
    if x then
      -- line from the step before (the line from you to the step you're on: PN:DrawLeg)
      if k > 1 and px and not (Q.OnTaxi() or (IsFlying and IsFlying())) then   -- no route lines while flying
        local legs = { { x, y } }
        -- (a leg into another zone goes through the crossings between zones, not over the zone line)
        local zp = prevPt and D.ZoneWalkPath and D.ZoneWalkPath(prevPt, pt)
        if zp then
          legs = {}
          for _, wpt in ipairs(zp) do
            local wx, wy = onMap(wpt, mapID, true)
            if wx then legs[#legs + 1] = { wx, wy } end
          end
          legs[#legs + 1] = { x, y }
        elseif k == 1 and prev and Q.Nav then
          -- the first leg follows the less obstructed path (Nav.lua)
          local path = Q.Nav:Route(prev, pt)
          if path and #path > 1 then
            legs = {}
            for _, wpt in ipairs(path) do
              local wx, wy = onMap(wpt, mapID, true)
              if wx then legs[#legs + 1] = { wx, wy } end
            end
          end
        end
        local ax, ay = px, py
        for _, leg in ipairs(legs) do
          li = li + 1
          PN:Line(li, ax, ay, leg[1], leg[2], col, k == 1 and 5 or 3.5, cw, ch, cs)
          ax, ay = leg[1], leg[2]
        end
      end
      -- coloured ring under the step icon
      local ring = wpool:Get()
      style(ring, DOT, size * (k == 1 and 1.9 or 1.5), col[1], col[2], col[3], 0.9)
      place(ring, x, y)
      ring:SetFrameLevel(ring:GetFrameLevel() + 1)
      ring.lvlOff = 6
      local b = wpool:Get()
      local icon = (s.type == "accept" and ICON.accept) or (s.type == "turnin" and ICON.turnin) or
        (s.type == "buy" and ICON.buy) or ICON[s.type] or ICON.kill
      style(b, icon, size * (k == 1 and 1.3 or 1.0), 1, 1, 1, 1, tostring(e.index))
      if k == 1 and PN.leg then PN.leg.ring, PN.leg.icon = ring, b end
      b:SetFrameLevel(ring:GetFrameLevel() + 2)
      b.lvlOff = 8
      b.tip = { Q.Guide.StepText(s), PN.LABELS[k] .. " - step " .. e.index .. " of your route",
        "Click to point the arrow here" }
      if pt.key and (pt.key:sub(1, 1) == "c" or pt.key:sub(1, 1) == "o") then b.spot = { pt.key, pt } end
      local note = D:Note(pt.key)
      if note then table.insert(b.tip, 2, note) end
      b.step = e.index
      b.quests = (s.type ~= "fly" and s.type ~= "boat") and s.quests or nil
      place(b, x, y)
      px, py, prevPt = x, y, pt
    else
      px, py, prevPt = nil, nil, nil            -- next leg starts on another map: no line across
    end
  end
  for i = li + 1, #PN.lines do PN.lines[i].bg:Hide(); PN.lines[i].fg:Hide() end
  PN:DrawLeg()
end

-- the line from you to the step you're on (along the less obstructed path, Nav.lua): the only part
-- of the map drawing that follows you as you move
PN.legLines = {}
-- the walking path as it's drawn: the grid's stair steps taken out (points that sit within a few yards
-- of a straight line between their neighbours go, unless that line would cross a wall) and the corners
-- rounded off - a smooth, solid line that still follows the lay of the land. Only for drawing: the
-- arrow keeps the exact path.
local SMOOTH_EPS = 15              -- yards
local function simplify(pts, a, b, out)
  local A, B = pts[a], pts[b]
  local best, bi = 0, nil
  local dx, dy = B.x - A.x, B.y - A.y
  local l2 = dx * dx + dy * dy
  for k = a + 1, b - 1 do
    local P = pts[k]
    local t = l2 > 0 and math.max(0, math.min(1, ((P.x - A.x) * dx + (P.y - A.y) * dy) / l2)) or 0
    local d = math.sqrt((P.x - A.x - dx * t) ^ 2 + (P.y - A.y - dy * t) ^ 2)
    if d > best then best, bi = d, k end
  end
  local walled = bi and Q.Nav and Q.Nav.HitsWall and Q.Nav.HitsWall(A.i or 0, A.x, A.y, B.x, B.y)
  if bi and (best > SMOOTH_EPS or walled) then
    simplify(pts, a, bi, out)
    simplify(pts, bi, b, out)
  else
    out[#out + 1] = B
  end
end
local smoothCache = {}
function PN.SmoothPath(start, path)
  if not (start and path and #path > 1) then return path end
  local c = smoothCache
  if c.path == path and c.n == #path and c.last == path[#path] and math.abs(c.x - start.x) < 2 and math.abs(c.y - start.y) < 2 then
    return c.out
  end
  local pts = { { i = start.i, x = start.x, y = start.y } }
  for _, q in ipairs(path) do pts[#pts + 1] = { i = q.i or start.i, x = q.x, y = q.y } end
  local simple = { pts[1] }
  if path.fine then
    for k = 2, #pts do simple[#simple + 1] = pts[k] end
  else
    simplify(pts, 1, #pts, simple)
  end
  -- rounded corners (Chaikin: each corner cut at a quarter of its two sides), twice
  local cur = simple
  for _ = 1, 2 do
    if #cur < 3 then break end
    local nxt = { cur[1] }
    for k = 1, #cur - 1 do
      local P, R = cur[k], cur[k + 1]
      local q = { i = P.i, x = P.x * 0.75 + R.x * 0.25, y = P.y * 0.75 + R.y * 0.25 }
      local rr = { i = P.i, x = P.x * 0.25 + R.x * 0.75, y = P.y * 0.25 + R.y * 0.75 }
      if k > 1 then nxt[#nxt + 1] = q end
      if k < #cur - 1 then nxt[#nxt + 1] = rr end
    end
    nxt[#nxt + 1] = cur[#cur]
    cur = nxt
  end
  -- the rounding must not cut over a wall (a narrow opening, a wall's end): then without it - and if even
  -- the straightened line would, the path as it was found
  local HW = Q.Nav and Q.Nav.HitsWall
  local function clear(list)
    if not HW then return true end
    for k = 1, #list - 1 do
      if HW(start.i or 0, list[k].x, list[k].y, list[k + 1].x, list[k + 1].y) then return false end
    end
    return true
  end
  if not clear(cur) then cur = clear(simple) and simple or pts end
  local out = {}
  for k = 2, #cur do out[#out + 1] = cur[k] end
  c.path, c.n, c.last, c.x, c.y, c.out = path, #path, path[#path], start.x, start.y, out
  return out
end
function PN:DrawLeg()
  local used = 0
  local L = PN.leg
  local here = D:PlayerPos()
  -- a ghost: the line leads to your corpse instead (back to the step once you're alive)
  local body = Q.Arrow and Q.Arrow.Corpse and Q.Arrow.Corpse()
  if body and canvas and lastMap then
    L = { pt = body, mapID = lastMap, cw = canvas:GetWidth(), ch = canvas:GetHeight(), col = PN.COLORS[1] }
  end
  -- the step you're on: its nearest open spot now (its icon moves there, nothing else is redrawn)
  if L and L.live and not body and canvas and L.mapID == lastMap then
    local now = Q.Guide:Target()
    if now and now ~= L.pt then
      local nx, ny = onMap(now, L.mapID)
      if nx then
        L.pt = now
        local cs = lastScale or 1
        for _, b in ipairs({ L.ring, L.icon }) do
          if b and b:IsShown() then
            b.qx, b.qy = nx, ny
            b:ClearAllPoints()
            b:SetPoint("CENTER", canvas, "TOPLEFT", nx * L.cw * cs, -ny * L.ch * cs)
          end
        end
      end
    end
  end
  if L and canvas and here and L.mapID == lastMap and Q.db.pins.world and not (Q.OnTaxi() or (IsFlying and IsFlying())) then
    local px, py = onMap(here, L.mapID)
    local x, y = onMap(L.pt, L.mapID)
    if px and x then
      local legs = { { x, y } }
      if Q.Nav then
        local path = Q.Nav:Route(here, L.pt)
        if path and #path > 1 then
          path = PN.SmoothPath(here, path)
          legs = {}
          for _, wpt in ipairs(path) do
            -- (a corner just past the map's edge - round a wall's far end - still drawn, or the line
            -- would skip it and cut straight over the walls)
            local wx, wy = onMap(wpt, L.mapID, true)
            if wx then legs[#legs + 1] = { wx, wy } end
          end
        end
      end
      local cs = lastScale or 1
      local ax, ay = px, py
      for _, leg in ipairs(legs) do
        used = used + 1
        local l = PN.legLines[used]
        if not l then
          l = { bg = PN.overlay:CreateLine(nil, "OVERLAY", nil, 6), fg = PN.overlay:CreateLine(nil, "OVERLAY", nil, 7) }
          l.bg:SetColorTexture(0, 0, 0, 0.75)
          PN.legLines[used] = l
        end
        local a1, b1, a2, b2 = ax * L.cw, -ay * L.ch, leg[1] * L.cw, -leg[2] * L.ch
        l.bg:SetStartPoint("TOPLEFT", canvas, a1, b1); l.bg:SetEndPoint("TOPLEFT", canvas, a2, b2); l.bg:Show()
        l.fg:SetStartPoint("TOPLEFT", canvas, a1, b1); l.fg:SetEndPoint("TOPLEFT", canvas, a2, b2); l.fg:Show()
        l.fg:SetColorTexture(L.col[1], L.col[2], L.col[3], 0.95)
        l.px = 5
        l.fg:SetThickness(5 / cs)
        l.bg:SetThickness(8 / cs)
        ax, ay = leg[1], leg[2]
      end
    end
  end
  for i = used + 1, #PN.legLines do PN.legLines[i].bg:Hide(); PN.legLines[i].fg:Hide() end
  -- (the icon may have moved: a waypoint marker over it is looked for again)
  local ic = PN.leg and PN.leg.icon
  local cx, cy
  if ic and ic:IsShown() then cx, cy = ic:GetCenter() end
  if cx and (cx ~= PN.coverX or cy ~= PN.coverY) then
    PN.coverX, PN.coverY = cx, cy
    Q.Throttle("wpcover", 0.2, function() PN:UncoverStep() end)
  end
end

-- A waypoint marker (the game's, or Questicus Maps' own on its stitched map) put exactly where
-- the step you're on is - Questicus pins the route's target - hides the step's icon and number.
-- The marker drawn over it is made see-through (and click-through) while it sits on the icon, and
-- comes back as soon as it doesn't. Found by place on screen: Questicus Maps' marker isn't reachable
-- any other way.
local covered = {}
local function hasWaypointArt(f)
  for _, r in ipairs({ f:GetRegions() }) do
    if r.GetAtlas then
      local a = r:GetAtlas()
      if type(a) == "string" and a:find("Waypoint", 1, true) then return true end
    end
    if r.GetTexture then
      local t = r:GetTexture()
      if type(t) == "string" and (t:find("Waypoint", 1, true) or t:find("ping5", 1, true)) then return true end
    end
  end
  for _, k in ipairs({ "Icon", "Texture" }) do
    local r = f[k]
    if type(r) == "table" and r.GetAtlas then
      local a = r:GetAtlas()
      if type(a) == "string" and a:find("Waypoint", 1, true) then return true end
    end
  end
end
local S = Q.Secret
local function screenCenter(f)
  local x, y = f:GetCenter()
  local k, w = f:GetEffectiveScale(), f:GetWidth()
  -- (another addon's protected frame in combat gives secret values: left alone)
  if not x or S(x) or S(y) or S(k) or S(w) then return end
  k = k or 1
  return x * k, y * k, (w or 0) * k
end
-- (reused between runs: walking the map's frames made a table per frame - megabytes on every open)
local uncoverList, uncoverKeep, uncoverN = {}, {}, 0
local kidBufs = {}
local function fillKids(t, ...)
  local n = select("#", ...)
  for i = 1, n do t[i] = (select(i, ...)) end
  for i = n + 1, #t do t[i] = nil end
  return n
end
local function uncoverWalk(p, depth)
  if depth > 7 or uncoverN > 6000 then return end
  local buf = kidBufs[depth] or {}
  kidBufs[depth] = buf
  local k = fillKids(buf, p:GetChildren())
  for i = 1, k do
    local c = buf[i]
    if c and not (c.IsForbidden and c:IsForbidden()) then
      uncoverN = uncoverN + 1
      uncoverList[uncoverN] = c
      if c ~= PN.overlay and (c.GetNumChildren and c:GetNumChildren() or 0) > 0 then uncoverWalk(c, depth + 1) end
    end
  end
end
local function hasUserWaypoint()
  if C_Map and C_Map.HasUserWaypoint then
    local ok, v = pcall(C_Map.HasUserWaypoint)
    if ok and v and not Q.Secret(v) then return true end
  end
  if C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything then
    local ok, v = pcall(C_SuperTrack.IsSuperTrackingAnything)
    if ok and v and not Q.Secret(v) then return true end
  end
  return false
end
function PN:UncoverStep()
  local ic = PN.leg and PN.leg.icon
  local keep = uncoverKeep
  wipe(keep)
  -- no waypoint / quest being followed: nothing of the game's to move out of the way
  if ic and ic:IsVisible() and WorldMapFrame and WorldMapFrame:IsShown() and hasUserWaypoint() then
    local ix, iy, iw = screenCenter(ic)
    if ix then
      local near = math.max(10, iw * 0.6)
      -- only the map's own frames (the markers are all on it), not every frame in the game
      uncoverN = 0
      uncoverWalk(WorldMapFrame, 0)
      for j = uncoverN + 1, #uncoverList do uncoverList[j] = nil end
      for j = 1, uncoverN do
        local f = uncoverList[j]
        if f ~= ic and f.IsVisible and f:IsVisible() then
          local x, y, w = screenCenter(f)
          if x and w < 80 and math.abs(x - ix) < near and math.abs(y - iy) < near and f:GetParent() ~= PN.overlay
            and f.GetRegions and hasWaypointArt(f) then
            keep[f] = true
            if not covered[f] then
              covered[f] = { a = f:GetAlpha(), m = f.IsMouseEnabled and f:IsMouseEnabled() }
              f:SetAlpha(0)
              if f.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then pcall(f.EnableMouse, f, false) end
            end
          end
        end
      end
    end
  end
  for f, was in pairs(covered) do
    if not keep[f] then
      f:SetAlpha(was.a or 1)
      if was.m and f.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then pcall(f.EnableMouse, f, true) end
      covered[f] = nil
    end
  end
end

-- ------------------------------------------------------------------ quest log objectives (Questie-style)
PN.OBJ_ICON = {
  kill = "Interface\\Icons\\Ability_DualWield",
  loot = "Interface\\Icons\\INV_Misc_Bag_08",
  buy = "Interface\\Icons\\INV_Misc_Coin_02",
  use = "Interface\\Icons\\INV_Misc_Gear_01",
  explore = "Interface\\Icons\\INV_Misc_Map_01",
}
local OBJ_MAX = 14            -- spots per objective (the rest are close to these)
function PN:Objectives(mapID, size, place)
  local n = 0
  for id, e in pairs(QS.log or {}) do
    local info = QS:Info(id)
    local title = (e.title or (info and info.title) or ("Quest " .. id))
    if e.complete then
      for _, k in ipairs((info and info.enders) or {}) do
        for _, pt in ipairs(D:Points(k)) do
          local x, y = onMap(pt, mapID)
          if x then
            local b = wpool:Get()
            style(b, ICON.turnin, size * 0.9, 1, 1, 1, 1)
            b.tip = { title, "Hand in to " .. D:Name(k), "Finished" }
            b.quest = id
            place(b, x, y)
            n = n + 1
            break
          end
        end
      end
    else
      local m = P.Meta(id)
      if m and m.lp then
        local open = P.OpenLines(id, m)
        for li in pairs(open) do
          local l = m.lines[li]
          local placed = {}
          local prog
          for _, o in ipairs(e.objectives or {}) do
            if l and l.name and (o.text or ""):lower():find(l.name:lower(), 1, true) then prog = o.text end
          end
          for _, pt in ipairs(m.lp[li] or {}) do
            if #placed >= OBJ_MAX then break end
            local x, y = onMap(pt, mapID)
            if x then
              local near
              for _, q in ipairs(placed) do
                if math.abs(q[1] - x) < 0.012 and math.abs(q[2] - y) < 0.012 then near = true; break end
              end
              if not near then
                placed[#placed + 1] = { x, y }
                local b = wpool:Get()
                local kind = (l and l.kind) or "explore"
                style(b, PN.OBJ_ICON[kind] or PN.OBJ_ICON.explore, size * 0.6, 1, 1, 1, 0.9)
                b.tip = { title, prog or (l and l.name) or "Objective", pt.key and D:Name(pt.key) or nil }
                if pt.key and pt.key:sub(1, 1) ~= "t" then b.spot = { pt.key, pt } end
                b.quest = id
                place(b, x, y)
                n = n + 1
              end
            end
          end
        end
      end
    end
  end
  return n
end

-- ------------------------------------------------------------------ patrol lines: hover
-- Lines can't take the mouse, so small invisible buttons sit along the path (under the other
-- icons, so those keep their own tooltips). Hovering one shows what patrols there and redraws the
-- whole path on a layer above every icon, thicker and brighter.
local hits, hitsUsed = {}, 0
function PN:ReleasePatrolHits()
  for i = 1, #hits do hits[i]:Hide() end
  hitsUsed = 0
  PN:HidePatrolTop()
end
local function hit()
  hitsUsed = hitsUsed + 1
  local b = hits[hitsUsed]
  if not b then
    b = CreateFrame("Button", nil, PN.overlay)
    b:SetSize(16, 16)
    b:SetScript("OnEnter", function(s)
      local e = s.patrol
      if not e then return end
      PN:ShowPatrolTop(e)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:AddLine(D:Name(e.key), 1, 0.82, 0.3)
      GameTooltip:AddLine("Patrols along this line - it walks the whole path, look along it", 0.9, 0.9, 0.9, true)
      local info = QS:Info(e.quest)
      if info then GameTooltip:AddLine("For: " .. info.title, 0.9, 0.9, 0.9, true) end
      if e.label then GameTooltip:AddLine(e.label, 0.6, 0.6, 0.6) end
      local own = QuesticusCollect and QuesticusCollect.patrol and QuesticusCollect.patrol["c:" .. e.key:sub(2)]
      GameTooltip:AddLine(own and "Path: your recording" or "Path: from the database (record a better one with /qc patrol)", 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide(); PN:HidePatrolTop() end)
    b:SetScript("OnClick", function(s) if s.patrol and s.patrol.step then Q.Guide.focus = s.patrol.step; Q.Guide:Refresh() end end)
    hits[hitsUsed] = b
  end
  b:SetFrameLevel((PN.overlay:GetFrameLevel() or 1) + 3)    -- under the step / mob icons (+5)
  b:Show()
  return b
end
function PN:PatrolHits(e, cw, ch, cs, place)
  e.cw, e.ch, e.cs = cw, ch, cs
  local pts = e.pts
  for j = 1, #pts do
    local b = hit()
    b.patrol = e
    place(b, pts[j][1], pts[j][2])
    if j < #pts then        -- and one between points, so the whole line reacts
      local m = hit()
      m.patrol = e
      place(m, (pts[j][1] + pts[j + 1][1]) / 2, (pts[j][2] + pts[j + 1][2]) / 2)
    end
  end
end

-- the highlighted path: its own frame above all of our icons
local top, topLines = nil, {}
function PN:ShowPatrolTop(e)
  if not canvas then return end
  if not top then
    top = CreateFrame("Frame", nil, PN.overlay)
    top:SetAllPoints(PN.overlay)
  end
  top:SetFrameLevel((PN.overlay:GetFrameLevel() or 1) + 40)
  top:Show()
  local col = e.col or { 1, 0.8, 0.3 }
  local n = 0
  for j = 1, #e.pts - 1 do
    n = n + 1
    local l = topLines[n]
    if not l then
      l = { bg = top:CreateLine(nil, "OVERLAY", nil, 6), fg = top:CreateLine(nil, "OVERLAY", nil, 7) }
      l.bg:SetColorTexture(0, 0, 0, 0.85)
      topLines[n] = l
    end
    local a, b = e.pts[j], e.pts[j + 1]
    l.bg:SetStartPoint("TOPLEFT", canvas, a[1] * e.cw, -a[2] * e.ch); l.bg:SetEndPoint("TOPLEFT", canvas, b[1] * e.cw, -b[2] * e.ch); l.bg:Show()
    l.fg:SetStartPoint("TOPLEFT", canvas, a[1] * e.cw, -a[2] * e.ch); l.fg:SetEndPoint("TOPLEFT", canvas, b[1] * e.cw, -b[2] * e.ch); l.fg:Show()
    l.fg:SetColorTexture(math.min(1, col[1] + 0.25), math.min(1, col[2] + 0.25), math.min(1, col[3] + 0.25), 1)
    l.fg:SetThickness(6 / (lastScale or e.cs))
    l.bg:SetThickness(10 / (lastScale or e.cs))
  end
  for j = n + 1, #topLines do topLines[j].bg:Hide(); topLines[j].fg:Hide() end
end
function PN:HidePatrolTop()
  if top then top:Hide() end
end

-- ------------------------------------------------------------------ objective areas
-- The places a step's objectives can be, grouped: spots within ~150 yd of each other form one area,
-- drawn as a see-through ellipse in the step's colour (strongest for the step you're on). A lone
-- spot gets no area, just its icon.
PN.areas = {}
local areaUsed = 0
local areaHits, hitUsed = {}, 0
PN.areaHits = areaHits
function PN:ReleaseAreas()
  for _, a in ipairs(PN.areas) do a.fill:Hide(); a.ring:Hide() end
  for _, h in ipairs(areaHits) do h:Hide() end
  areaUsed, hitUsed = 0, 0
end
-- hovering an area tells what it's for: the quest(s) and the objectives there
local function areaHit(cx, cy, r, g, label)
  hitUsed = hitUsed + 1
  local h = areaHits[hitUsed]
  if not h then
    h = CreateFrame("Button", nil, PN.areaLayer)
    h:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      for i, line in ipairs(PN.areaTip[self] or {}) do
        if i == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.85, 0.8, 0.7, true) end
      end
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    areaHits[hitUsed] = h
  end
  local quests, objs, seenQ, seenO = {}, {}, {}, {}
  for _, e in ipairs(g) do
    local id = e[4]
    if id and not seenQ[id] then seenQ[id] = true; local inf = QS:Info(id); quests[#quests + 1] = inf and inf.title or ("Quest " .. id) end
    local key = e[1] and e[1].key
    if key and not seenO[key] and key:sub(1, 1) ~= "t" then seenO[key] = true; objs[#objs + 1] = D:Name(key) end
  end
  local tip = { table.concat(quests, ", ") }
  if #objs > 0 then tip[#tip + 1] = table.concat(objs, ", ", 1, math.min(#objs, 6)) .. (#objs > 6 and " ..." or "") end
  tip[#tip + 1] = label
  PN.areaTip[h] = tip
  h:ClearAllPoints()
  h:SetSize(r * 2, r * 2)
  h:SetPoint("CENTER", PN.areaLayer, "TOPLEFT", cx, -cy)
  h:Show()
end
PN.areaTip = {}
local function areaTex()
  areaUsed = areaUsed + 1
  local a = PN.areas[areaUsed]
  if not a then
    if not PN.areaLayer then
      PN.areaLayer = CreateFrame("Frame", nil, PN.overlay)
      PN.areaLayer:SetAllPoints(PN.overlay)
    end
    PN.areaLayer:SetFrameLevel(math.max(1, (PN.overlay:GetFrameLevel() or 1) - 1))
    a = { fill = PN.areaLayer:CreateTexture(nil, "BACKGROUND"), ring = PN.areaLayer:CreateTexture(nil, "BORDER") }
    a.fill:SetTexture(Q.MEDIA .. "disc")
    a.ring:SetTexture(Q.MEDIA .. "ring_thin")          -- a fine line round the area
    PN.areas[areaUsed] = a
  end
  return a
end

-- groups of points (single link, same continent, within `gap` yards)
function PN.Group(list, gap)
  local groups, seen = {}, {}
  for i = 1, #list do
    if not seen[i] then
      seen[i] = true
      local g, q = { list[i] }, { i }
      while #q > 0 do
        local a = list[table.remove(q)]
        for j = 1, #list do
          if not seen[j] and list[j][1].i == a[1].i and D.Dist(list[j][1], a[1]) <= gap then
            seen[j] = true
            g[#g + 1] = list[j]; q[#q + 1] = j
          end
        end
      end
      groups[#groups + 1] = g
    end
  end
  return groups
end

-- ellipse around canvas points: centre, half axes (a >= b) and the angle of the long axis
function PN.Ellipse(pts, pad)
  local n, mx, my = #pts, 0, 0
  for _, p in ipairs(pts) do mx, my = mx + p[1], my + p[2] end
  mx, my = mx / n, my / n
  local sxx, syy, sxy = 0, 0, 0
  for _, p in ipairs(pts) do
    local dx, dy = p[1] - mx, p[2] - my
    sxx, syy, sxy = sxx + dx * dx, syy + dy * dy, sxy + dx * dy
  end
  local th = 0.5 * (math.atan2 or math.atan)(2 * sxy, sxx - syy)
  local ux, uy, vx, vy = math.cos(th), math.sin(th), -math.sin(th), math.cos(th)
  local u0, u1, v0, v1 = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(pts) do
    local dx, dy = p[1] - mx, p[2] - my
    local u, v = dx * ux + dy * uy, dx * vx + dy * vy
    u0, u1, v0, v1 = math.min(u0, u), math.max(u1, u), math.min(v0, v), math.max(v1, v)
  end
  local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
  local cx, cy = mx + ux * cu + vx * cv, my + uy * cu + vy * cv
  -- a little room around the outer spots (sqrt 2: the ellipse around a box reaches its corners)
  local a = (u1 - u0) / 2 * 1.25 + pad
  local b = (v1 - v0) / 2 * 1.25 + pad
  b = math.max(b, pad * 1.4, a * 0.25)
  if b > a then a, b, th = b, a, th + math.pi / 2 end
  return cx, cy, a, b, th
end

-- draw it: a square texture whose texture coordinates turn the round disc into the rotated ellipse
local function ellipseTex(t, cx, cy, a, b, th)
  local S = 2 * a
  local ux, uy, vx, vy = math.cos(th), math.sin(th), -math.sin(th), math.cos(th)
  local function tc(dx, dy)
    return 0.5 + 0.5 * (dx * ux + dy * uy) / a, 0.5 + 0.5 * (dx * vx + dy * vy) / b
  end
  local h = S / 2
  local ulx, uly = tc(-h, -h)
  local llx, lly = tc(-h, h)
  local urx, ury = tc(h, -h)
  local lrx, lry = tc(h, h)
  t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
  t:ClearAllPoints()
  t:SetPoint("CENTER", PN.areaLayer, "TOPLEFT", cx, -cy)
  t:SetSize(S, S)
  t:Show()
end

function PN:Areas(list, col, k, cw, ch)
  if Q.db.pins.areas == false or #list < 2 or not (cw and cw > 0) then return end
  if k > 1 and Q.db.pins.areasNext == false then return end
  local pad = math.max(10, cw * 0.012)
  local made = 0
  for _, g in ipairs(PN.Group(list, 150)) do
    if #g >= 2 and made < 12 then
      local pts = {}
      for _, e in ipairs(g) do pts[#pts + 1] = { e[2] * cw, e[3] * ch } end
      local cx, cy, a, b, th = PN.Ellipse(pts, pad)
      local t = areaTex()
      ellipseTex(t.fill, cx, cy, a, b, th)
      ellipseTex(t.ring, cx, cy, a, b, th)
      t.fill:SetVertexColor(col[1], col[2], col[3], k == 1 and 0.2 or 0.09)
      t.ring:SetVertexColor(col[1], col[2], col[3], k == 1 and 0.55 or 0.25)
      areaHit(cx, cy, math.max(8, b), g, PN.LABELS[k] .. (g[1][5] and (" - step " .. g[1][5]) or ""))
      made = made + 1
    end
  end
end

-- the three steps drawn on the maps: the one you're on (or picked) and the next two
PN.COLORS = { { 0.25, 0.9, 0.85 }, { 1, 0.78, 0.25 }, { 0.75, 0.5, 1 } }
PN.LABELS = { "Now", "Next", "After that" }
function PN.RouteSteps()
  local out = {}
  if Q.CollectOnly and Q.CollectOnly() then return out end    -- collection mode: no route
  local steps = P.steps or {}
  local f = Q.Guide.focus or 1
  for i = f, math.min(#steps, f + 2) do
    local s = steps[i]
    local pt
    if i == f then pt = (Q.Guide:Target(i))
    elseif s.type == "complete" then
      local m = P.Meta(s.quests[1])
      pt = s.point or (m and m.obj and m.obj.centre) or (s.unknown and D:QuestWaypoint(s.quests[1]))
    else
      pt = s.point
    end
    out[#out + 1] = { step = s, index = i, point = pt }
  end
  return out
end

-- route lines on the world map canvas (a dark outline under a coloured line)
PN.lines = {}
function PN:Line(i, x1, y1, x2, y2, col, px, cw, ch, cs)
  local l = PN.lines[i]
  if not l then
    l = {}
    l.bg = PN.overlay:CreateLine(nil, "OVERLAY", nil, 6)
    l.fg = PN.overlay:CreateLine(nil, "OVERLAY", nil, 7)
    l.bg:SetColorTexture(0, 0, 0, 0.75)
    PN.lines[i] = l
  end
  local a1, b1, a2, b2 = x1 * cw, -y1 * ch, x2 * cw, -y2 * ch
  l.bg:SetStartPoint("TOPLEFT", canvas, a1, b1); l.bg:SetEndPoint("TOPLEFT", canvas, a2, b2); l.bg:Show()
  l.fg:SetStartPoint("TOPLEFT", canvas, a1, b1); l.fg:SetEndPoint("TOPLEFT", canvas, a2, b2); l.fg:Show()
  l.fg:SetColorTexture(col[1], col[2], col[3], 0.95)
  l.fg:SetThickness(px / cs)
  l.bg:SetThickness((px + 3) / cs)
  l.px = px
end

-- the map zoomed (Blizzard's smooth zoom changes the scale every frame): the icons and line widths
-- follow at once, in the same frame, so nothing is drawn at the old size for a moment
function PN:Rescale(cs)
  if not canvas or not cs or cs <= 0 then return end
  lastScale = cs
  local cw, ch = lastW or canvas:GetWidth(), lastH or canvas:GetHeight()
  local function fix(b)
    if b:IsShown() and b.qx then
      b:SetScale(1 / cs)
      b:ClearAllPoints()
      b:SetPoint("CENTER", canvas, "TOPLEFT", b.qx * cw * cs, -b.qy * ch * cs)
    end
  end
  if wpool then for i = 1, wpool.used do fix(wpool.list[i]) end end
  for i = 1, hitsUsed do fix(hits[i]) end
  for _, l in ipairs(PN.legLines) do
    if l.px and l.fg:IsShown() then
      l.fg:SetThickness(l.px / cs)
      l.bg:SetThickness((l.px + 3) / cs)
    end
  end
  for _, l in ipairs(PN.lines) do
    if l.px and l.fg:IsShown() then
      l.fg:SetThickness(l.px / cs)
      l.bg:SetThickness((l.px + 3) / cs)
    end
  end
end

local function hookWorldMap()
  if not WorldMapFrame or PN.hooked then return end
  PN.hooked = true
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() PN:RefreshWorld() end) end
  -- (opening the map: checked once its own layout is done - read straight away the canvas could still
  -- have the size it had while shut, a redraw for nothing, then another)
  WorldMapFrame:HookScript("OnShow", function()
    PN.openedAt = GetTime and GetTime() or 0
    -- (Questicus Maps lays its art out again as the map opens, higher up: Questicus' layer is put back
    -- over it at once and on every frame while that settles - found under it for a moment, the
    -- quest areas and icons looked like they were drawn again)
    PN:FixLevel()
    Q.After(0.1, function() PN:RefreshWorld() end)
    Q.After(0.3, function() PN:UncoverStep() end)
  end)
  local watcher = CreateFrame("Frame", nil, WorldMapFrame)
  local acc = 0
  watcher:SetScript("OnUpdate", function(_, el)
    -- every frame (cheap): another map or canvas size (Questicus Maps changes zone as you drag it)
    -- redraws now; a zoom only resizes the icons. Waiting for the next check drew the icons at the
    -- old size for a moment - the "flashing big" icons.
    local sc = WorldMapFrame.ScrollContainer
    local c = sc and sc.Child
    local since = PN.openedAt and GetTime and (GetTime() - PN.openedAt) or 99
    local settling = since < 0.1
    if since < 2 then PN:FixLevel() end
    if c and lastMap and not settling then
      local w, h = c:GetWidth(), c:GetHeight()
      if WorldMapFrame:GetMapID() ~= lastMap or math.abs((w or 0) - (lastW or 0)) > 0.5
        or math.abs((h or 0) - (lastH or 0)) > 0.5 then
        PN:RefreshWorld()
      else
        local cs = canvasScale(sc)
        if lastScale and math.abs(cs - lastScale) > lastScale * 1e-4 then PN:Rescale(cs) end
      end
    end
    acc = acc + el
    if acc < (Q.OnTaxi() and 2 or 0.2) then return end
    acc = 0
    PN:FixLevel()
    -- (markers come and go - the map's own redraws reuse them: checked again now and then)
    PN.coverAcc = (PN.coverAcc or 0) + 1
    if PN.coverAcc >= 8 then PN.coverAcc = 0; PN:UncoverStep() end
    -- you moved: redraw (the route line starts at you)
    local here = D:PlayerPos()
    local moved = here and (not PN.lastHere or D.Dist(here, PN.lastHere) > 8)
    if moved then PN.lastHere = here end
    -- (only the line from you is redrawn, unless the route's steps on the map changed: signature())
    if moved or not lastMap then PN:RefreshWorld() end
  end)
end

-- ------------------------------------------------------------------ minimap
local MINIMAP_SIZE = {
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}
local mpool, mframe
local mlineFrame, mlines, mlineN = nil, {}, 0

-- minimap offset of a point in pixels from the centre, never clamped (lines get clipped instead)
local function minimapRaw(here, pt)
  local zoom = Minimap:GetZoom() or 0
  local diam = (IsIndoors and IsIndoors() and MINIMAP_SIZE.indoor or MINIMAP_SIZE.outdoor)[zoom] or 466
  local ex, ny = -(pt.y - here.y), pt.x - here.x
  if GetCVar and GetCVar("rotateMinimap") == "1" then
    local f = GetPlayerFacing and GetPlayerFacing() or 0
    local c, s = math.cos(f), math.sin(f)
    ex, ny = ex * c - ny * s, ex * s + ny * c
  end
  local scale = Minimap:GetWidth() / diam   -- pixels per yard
  return ex * scale, ny * scale
end

-- the part of a segment inside the minimap (round, or square with some minimap addons)
local function clipSegment(x1, y1, x2, y2, r)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1 = 0, 1
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    for _, e in ipairs({ { -dx, x1 + r }, { dx, r - x1 }, { -dy, y1 + r }, { dy, r - y1 } }) do
      local pp, qq = e[1], e[2]
      if pp == 0 then
        if qq < 0 then return end
      else
        local t = qq / pp
        if pp < 0 then if t > t1 then return elseif t > t0 then t0 = t end
        else if t < t0 then return elseif t < t1 then t1 = t end end
      end
    end
  else
    local a = dx * dx + dy * dy
    if a < 1e-6 then return end
    local b = 2 * (x1 * dx + y1 * dy)
    local c = x1 * x1 + y1 * y1 - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return end
    local sq = math.sqrt(disc)
    local ta, tb = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
    t0, t1 = math.max(0, ta), math.min(1, tb)
    if t0 >= t1 then return end
  end
  return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

local function mmLine(x1, y1, x2, y2, col, w, alpha)
  local half = (Minimap:GetWidth() or 140) / 2 - 2
  local a1, b1, a2, b2 = clipSegment(x1, y1, x2, y2, half)
  if not a1 then return end
  if not mlineFrame then
    mlineFrame = CreateFrame("Frame", nil, Minimap)
    mlineFrame:SetAllPoints(Minimap)
    mlineFrame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 4)
  end
  mlineN = mlineN + 1
  local l = mlines[mlineN]
  if not l then
    l = { bg = mlineFrame:CreateLine(nil, "OVERLAY", nil, 2), fg = mlineFrame:CreateLine(nil, "OVERLAY", nil, 3) }
    l.bg:SetColorTexture(0, 0, 0, 0.6)
    mlines[mlineN] = l
  end
  l.bg:SetStartPoint("CENTER", Minimap, a1, b1); l.bg:SetEndPoint("CENTER", Minimap, a2, b2); l.bg:Show()
  l.fg:SetStartPoint("CENTER", Minimap, a1, b1); l.fg:SetEndPoint("CENTER", Minimap, a2, b2); l.fg:Show()
  l.fg:SetColorTexture(col[1], col[2], col[3], alpha or 0.95)
  l.fg:SetThickness(w)
  l.bg:SetThickness(w + 2)
end
PN.ClipSegment = clipSegment

-- minimap offset of a point (pixels from the centre) or nil when outside and not clamped
local function minimapXY(here, pt, clamp)
  local zoom = Minimap:GetZoom() or 0
  local diam = (IsIndoors and IsIndoors() and MINIMAP_SIZE.indoor or MINIMAP_SIZE.outdoor)[zoom] or 466
  local radius = diam / 2
  local north, west = pt.x - here.x, pt.y - here.y
  local ex, ny = -west, north
  if GetCVar and GetCVar("rotateMinimap") == "1" then
    local f = GetPlayerFacing and GetPlayerFacing() or 0
    local c, s = math.cos(f), math.sin(f)
    ex, ny = ex * c - ny * s, ex * s + ny * c
  end
  -- square minimaps (Command Center's minimap look, other minimap addons) also show the corners
  local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
  local dist = square and math.max(math.abs(ex), math.abs(ny)) or math.sqrt(ex * ex + ny * ny)
  if dist > radius then
    if not clamp then return end
    ex, ny = ex / dist * radius * 0.95, ny / dist * radius * 0.95
  end
  local scale = (Minimap:GetWidth() / 2) / radius
  return ex * scale, ny * scale, dist <= radius
end

-- minimap pins' tooltips, built only when you point at one (no tables per refresh)
local MMTIP = {}
function MMTIP.giver(b) return QS:QuestTip(b.ta, D:Name(b.tb), "Quest you can pick up") end
function MMTIP.skull(b) return QS:TipExtra(QS:IdByTitle(b.tb), { D:Name("c" .. b.ta), "Kill for: " .. tostring(b.tb), "Current step" }) end
function MMTIP.mob(b) return QS:TipExtra(QS:IdByTitle(b.tb), { D:Name("c" .. b.ta), "For: " .. tostring(b.tb) }) end
function MMTIP.obj(b)
  local info = QS:Info(b.tb)
  return QS:TipExtra(b.tb, { D:Name(b.ta or ""), info and info.title or "", PN.LABELS[b.tc] })
end
function MMTIP.step(b)
  local t = { Q.Guide.StepText(b.ta), PN.LABELS[b.tb] .. " - step " .. b.tc .. " of your route" }
  local note = b.td and D:Note(b.td)
  if note then t[#t + 1] = note end
  local qs = b.ta and b.ta.type ~= "fly" and b.ta.type ~= "boat" and b.ta.quests or {}
  for k, qid in ipairs(qs) do
    if k > 3 then break end
    if #qs > 1 then local i = QS:Info(qid); t[#t + 1] = "|cffffd100" .. (i and i.title or ("Quest " .. qid)) .. "|r" end
    QS:TipExtra(qid, t)
  end
  return t
end

local function mmHideLines()
  PN.mmLines = mlineN
  for i = mlineN + 1, #mlines do mlines[i].bg:Hide(); mlines[i].fg:Hide() end
end
local function mmPut(b, x, y)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
local mmMobN = 0
local function mmMobs(here, list, skull)
  for npc, title in pairs(list) do
    if skull or not Q.Marks.main[npc] then
      for _, mp in ipairs(D:Points("c" .. npc)) do
        if mmMobN >= 50 then break end
        if mp.i == here.i and not mp.dungeon and D.Dist(here, mp) < 260 then
          local x, y = minimapXY(here, mp)
          if x then
            local b = mpool:Get()
            if skull then
              style(b, PN.SKULL8, 13, 1, 1, 1, 1)
              b:SetFrameLevel(b:GetFrameLevel() + 2)
              b.tipFn = MMTIP.skull
            else
              style(b, PN.CROSS, 11, 1, 1, 1, 0.9)
              b.tipFn = MMTIP.mob
            end
            b.ta, b.tb = npc, title
            b.spotK, b.spotP = "c" .. npc, mp
            mmPut(b, x, y)
            mmMobN = mmMobN + 1
          end
        end
      end
    end
  end
end

-- the first leg's path, worked out again only when you've moved a few yards or the step changed
local navCache = {}
local function navRoute(here, pt)
  local c = navCache
  if c.pt == pt and c.i == here.i and math.abs(c.x - here.x) < 4 and math.abs(c.y - here.y) < 4 then return c.path end
  c.pt, c.i, c.x, c.y = pt, here.i, here.x, here.y
  c.path = Q.Nav:Route(here, pt)
  return c.path
end

-- what the minimap pins depend on: nothing changed since the last draw = nothing to draw
local mmLast = {}
local function mmUnchanged(here, firstPt)
  local L = mmLast
  local rot = GetCVar and GetCVar("rotateMinimap") == "1"
  local facing = rot and GetPlayerFacing and GetPlayerFacing() or 0
  local zoom = Minimap:GetZoom() or 0
  local w = Minimap:GetWidth() or 0
  local mver = Q.Marks and Q.Marks.ver or 0
  local same = L.i == here.i and L.x and math.abs(L.x - here.x) < 1 and math.abs(L.y - here.y) < 1
    and math.abs((L.f or 0) - facing) < 0.03 and L.z == zoom and L.w == w and L.mv == mver
    and L.steps == P.steps and L.focus == (Q.Guide.focus or 1) and L.pt == firstPt
    and L.px == (firstPt and firstPt.x) and L.py == (firstPt and firstPt.y)
    and L.fly == (Q.OnTaxi() or (IsFlying and IsFlying()) or false) and L.ver == (PN.mmVer or 0)
    and L.indoor == (IsIndoors and IsIndoors() or false)
    and L.lines == (Q.db.pins.mmRoute ~= false) and L.others == (Q.db.pins.others and true or false)
  if same then return true end
  L.lines, L.others = Q.db.pins.mmRoute ~= false, Q.db.pins.others and true or false
  L.i, L.x, L.y, L.f, L.z, L.w, L.mv = here.i, here.x, here.y, facing, zoom, w, mver
  L.steps, L.focus, L.pt = P.steps, Q.Guide.focus or 1, firstPt
  L.px, L.py = firstPt and firstPt.x, firstPt and firstPt.y
  L.fly, L.ver, L.indoor = Q.OnTaxi() or (IsFlying and IsFlying()) or false, PN.mmVer or 0, IsIndoors and IsIndoors() or false
  return false
end
-- something the pins show changed (settings, quest log, a spot taken off): draw again
function PN.MinimapDirty() PN.mmVer = (PN.mmVer or 0) + 1 end
for _, ev in ipairs({ "QC_QUESTS_CHANGED", "QC_PLAN_UPDATED", "QC_TARGET_CHANGED", "MINIMAP_UPDATE_ZOOM", "QC_SETTINGS" }) do
  Q:On(ev, function() PN.MinimapDirty() end)
end

function PN:RefreshMinimap(force)
  if not Minimap then return end
  if not mpool then mpool = pool(Minimap, 14) end
  if not (Q.db.pins.minimap and Q.char.surveyDone and P.steps) or (Q.CollectOnly and Q.CollectOnly()) then
    if mpool.used > 0 or mlineN > 0 then mpool:Release(); mlineN = 0; mmHideLines() end
    mmLast.i = nil
    return
  end
  local here = D:PlayerPos()
  if not here then mpool:Release(); mlineN = 0; mmHideLines(); return end
  local route = PN.RouteSteps()
  local body = Q.Arrow and Q.Arrow.Corpse and Q.Arrow.Corpse()
  if not force and mmUnchanged(here, body or (route[1] and route[1].point)) then return end
  mpool:Release()
  mlineN = 0
  local lines = Q.db.pins.mmRoute ~= false
  -- flying (flight path or flying mount): no route lines or trails, just the icons
  local flying = Q.OnTaxi() or (IsFlying and IsFlying()) or false
  if flying then lines = false end
  -- quest givers you can pick up from, nearby: star
  if Q.db.pins.others then
    for _, id in ipairs(availableQuests()) do
      local info = QS:Info(id)
      for _, k in ipairs(info and info.givers or {}) do
        for _, gp in ipairs(D:Points(k)) do
          if gp.i == here.i and D.Dist(here, gp) < 300 then
            local x, y = minimapXY(here, gp)
            if x then
              local b = mpool:Get()
              style(b, PN.STAR, 12, 1, 1, 1, 0.95)
              b.tipFn, b.ta, b.tb = MMTIP.giver, id, k
              b.spotK, b.spotP = k, gp
              mmPut(b, x, y)
            end
          end
        end
      end
    end
  end
  -- mobs you still need for quests in your log (kills and every mob that drops a quest item): X
  -- the current step's mobs get a skull and are drawn first
  if Q.Marks and Q.Marks.need then
    mmMobN = 0
    mmMobs(here, Q.Marks.main, true)
    mmMobs(here, Q.Marks.need, false)
  end
  local prev, prevX, prevY = here, 0, 0
  local patrolled = PN.mmPatrolled or {}
  PN.mmPatrolled = patrolled
  for k, e in ipairs(route) do
    local col, s, pt = PN.COLORS[k], e.step, e.point
    if s.type == "complete" and k <= 2 then
      wipe(patrolled)
      for _, sp in ipairs(P.StepPoints(s)) do
        local op, id = sp.p, sp.id
        local path = D:Patrol(op.key)
        if path then
          if not patrolled[op.key] then
            patrolled[op.key] = true
            if lines then
              local ax, ay
              for _, wp in ipairs(path) do
                if wp.i == here.i then
                  local x, y = minimapRaw(here, wp)
                  if ax then mmLine(ax, ay, x, y, col, k == 1 and 2 or 1.5, 0.8) end
                  ax, ay = x, y
                else
                  ax = nil
                end
              end
            end
            op = D.Nearest(here, path) or op
          else
            op = nil
          end
        end
        if op then
          if op.i == here.i then
            local x, y = minimapXY(here, op)
            if x then
              local b = mpool:Get()
              style(b, DOT, k == 1 and 8 or 6, col[1], col[2], col[3], k == 1 and 0.9 or 0.6)
              b.tipFn, b.ta, b.tb, b.tc = MMTIP.obj, op.key, id, k
              if op.key and op.key:sub(1, 1) ~= "t" then b.spotK, b.spotP = op.key, op end
              mmPut(b, x, y)
            end
          end
        end
      end
    end
    if not pt or pt.i ~= here.i then break end
    if lines and body then
      -- (a ghost: the route's lines give way to the one to your corpse, below)
    elseif lines then
      -- route line from the previous point (you, then the step before); the first leg follows
      -- the less obstructed path. Lines are clipped at the minimap's edge, so they still show
      -- the way to steps that are further away.
      local ax, ay = minimapRaw(here, prev)
      local path = k == 1 and Q.Nav and not Q.OnTaxi() and navRoute(here, pt)
      if path and #path > 1 then path = PN.SmoothPath(here, path) end
      if path and #path > 1 then
        for _, wpt in ipairs(path) do
          local bx, by = minimapRaw(here, wpt)
          mmLine(ax, ay, bx, by, col, 3, 0.95)
          ax, ay = bx, by
        end
      else
        local bx, by = minimapRaw(here, pt)
        mmLine(ax, ay, bx, by, col, k == 1 and 3 or 2, k == 1 and 0.95 or 0.75)
      end
    elseif not flying then
      -- lines off: the old dotted trail to the first step
      local x0, y0 = minimapXY(here, pt, true)
      local dx, dy = x0 - prevX, y0 - prevY
      local n = math.floor(math.sqrt(dx * dx + dy * dy) / 9)
      for j = 1, n - 1 do
        local d = mpool:Get()
        style(d, DOT, k == 1 and 4 or 3, col[1], col[2], col[3], k == 1 and 0.95 or 0.75)
        mmPut(d, prevX + dx * j / n, prevY + dy * j / n)
      end
    end
    local x, y, inside = minimapXY(here, pt, k == 1)
    if x then
      local ring = mpool:Get()
      style(ring, DOT, k == 1 and 20 or 15, col[1], col[2], col[3], 0.9)
      mmPut(ring, x, y)
      local b = mpool:Get()
      style(b, s.type == "turnin" and ICON.turnin or (s.type == "accept" and ICON.accept) or
        (s.type == "buy" and ICON.buy or ICON[s.type] or ICON.kill), k == 1 and 14 or 11, 1, 1, 1, 1)
      b:SetFrameLevel(ring:GetFrameLevel() + 2)
      b.tipFn, b.ta, b.tb, b.tc, b.td = MMTIP.step, s, k, e.index, pt.key
      if pt.key and (pt.key:sub(1, 1) == "c" or pt.key:sub(1, 1) == "o") then b.spotK, b.spotP = pt.key, pt end
      mmPut(b, x, y)
    end
    if not lines and not inside then break end   -- dotted trail: nothing beyond the edge
    prev, prevX, prevY = pt, x or prevX, y or prevY
  end
  -- a ghost: the route line leads to your corpse (along the walkable path)
  if body and lines and body.i == here.i then
    local col = PN.COLORS[1]
    local ax, ay = minimapRaw(here, here)
    local path = Q.Nav and navRoute(here, body)
    if not (path and #path > 1) then path = { body } else path = PN.SmoothPath(here, path) end
    for _, wpt in ipairs(path) do
      local bx, by = minimapRaw(here, wpt)
      mmLine(ax, ay, bx, by, col, 3, 0.95)
      ax, ay = bx, by
    end
  end
  mmHideLines()
end

local function startMinimap()
  if mframe then return end
  mframe = CreateFrame("Frame")
  local acc = 0
  mframe:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    -- 4 times a second (once a second in flight); RefreshMinimap itself skips when nothing moved
    if acc < (Q.OnTaxi() and 1 or 0.25) then return end
    acc = 0
    PN:RefreshMinimap()
  end)
end

Q:On("QC_READY", function() hookWorldMap(); startMinimap() end)
-- taking off / landing: lines go away / come back right away
local function flightChanged() Q.After(0.3, function() PN:RefreshMinimap(); PN:RefreshWorld() end) end
-- after a loading screen: drawn again once
Q:On("PLAYER_ENTERING_WORLD", function() PN:Invalidate() end)
-- a new waypoint pin: under Questicus' icons right away
Q:On("USER_WAYPOINT_UPDATED", function() Q.After(0, function() PN:FixLevel() end); Q.After(0.3, function() PN:UncoverStep() end) end)
Q:On("SUPER_TRACKING_CHANGED", function() Q.After(0, function() PN:FixLevel() end) end)
Q:On("PLAYER_CONTROL_LOST", flightChanged)
Q:On("PLAYER_CONTROL_GAINED", flightChanged)
Q:On("QC_PLAN_UPDATED", function() available = nil; PN:RefreshWorld() end)
Q:On("QC_TARGET_CHANGED", function() PN:RefreshWorld() end)
-- dying / released / alive again: the route line switches between your corpse and the step
local function lifeChanged()
  Q.After(0.2, function() PN.MinimapDirty(); PN:RefreshMinimap(true); PN:RefreshWorld(true) end)
end
for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do Q:On(ev, lifeChanged) end

-- ------------------------------------------------------------------ your corpse (while a ghost)
-- a pin on the world map and the minimap where your body is (the arrow leads there too: Arrow.lua)
local CORPSE_TEX = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local corpseW, corpseM
local function corpsePin(parent, size)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(size, size)
  b.ring = b:CreateTexture(nil, "BACKGROUND")
  b.ring:SetTexture(Q.MEDIA .. "glow")
  b.ring:SetPoint("CENTER")
  b.ring:SetSize(size * 1.9, size * 1.9)
  b.ring:SetVertexColor(1, 0.25, 0.2, 0.7)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetTexture(CORPSE_TEX)
  b.tex:SetAllPoints()
  b:EnableMouse(true)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Your corpse", 1, 0.82, 0.3)
    GameTooltip:AddLine("Run back here to resurrect", 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end
function PN:RefreshCorpse()
  local body = Q.Arrow and Q.Arrow.Corpse and Q.Arrow.Corpse()
  -- world map
  if body and WorldMapFrame and WorldMapFrame:IsShown() and PN.overlay and canvas and Q.db.pins.world then
    if not corpseW then corpseW = corpsePin(PN.overlay, 24) end
    local x, y = onMap(body, WorldMapFrame:GetMapID())
    if x then
      local cs = canvasScale(WorldMapFrame.ScrollContainer)
      corpseW:SetFrameLevel(PN.overlay:GetFrameLevel() + 30)
      corpseW:SetScale(1 / cs)
      corpseW:ClearAllPoints()
      corpseW:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() * cs, -y * canvas:GetHeight() * cs)
      corpseW:Show()
    else corpseW:Hide() end
  elseif corpseW then corpseW:Hide() end
  -- minimap (at the edge when it's further than the minimap shows)
  local here = body and Minimap and D:PlayerPos()
  if here and here.i == body.i and Q.db.pins.minimap then
    if not corpseM then corpseM = corpsePin(Minimap, 16) end
    local x, y = minimapXY(here, body, true)
    if x then
      corpseM:SetFrameLevel(Minimap:GetFrameLevel() + 20)
      corpseM:ClearAllPoints()
      corpseM:SetPoint("CENTER", Minimap, "CENTER", x, y)
      corpseM:Show()
    else corpseM:Hide() end
  elseif corpseM then corpseM:Hide() end
end
do
  local acc = 0
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.1 then return end
    acc = 0
    if not (UnitIsGhost and UnitIsGhost("player")) then
      if corpseW and corpseW:IsShown() then corpseW:Hide() end
      if corpseM and corpseM:IsShown() then corpseM:Hide() end
      return
    end
    pcall(PN.RefreshCorpse, PN)
  end)
end
