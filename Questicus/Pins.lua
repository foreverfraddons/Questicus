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
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        for i, l in ipairs(s.tip) do
          if i == 1 then GameTooltip:AddLine(l, 1, 0.82, 0.3, true) else GameTooltip:AddLine(l, 0.9, 0.9, 0.9, true) end
        end
        if s.spot then GameTooltip:AddLine("Ctrl-click: wrong spot? Remove it from the database", 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:SetScript("OnClick", function(s)
        -- Ctrl-click: nothing is there - remove the spot (for you now, for everyone via the recordings)
        if s.spot and IsControlKeyDown and IsControlKeyDown() then
          GameTooltip:Hide()
          D:RemoveSpot(s.spot[1], s.spot[2])
          return
        end
        if s.step then Q.Guide.focus = s.step; Q.Guide:Refresh() end
      end)
      self.list[self.used] = b
    end
    b:SetFrameLevel((self.parent:GetFrameLevel() or 1) + 5)
    b:Show()
    return b
  end
  function p:Release()
    for i = 1, #self.list do self.list[i]:Hide(); self.list[i].tip = nil; self.list[i].step = nil; self.list[i].spot = nil end
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
local function onMap(pt, mapID)
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
    if px and px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
  end
end

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
local wpool, canvas, lastMap, lastScale
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

function PN:RefreshWorld()
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
  local lvl = (canvas:GetFrameLevel() or 1) + 2500
  local OMA = PN.openMap and (_G.QuesticusMapAPI or _G.OpenMapAPI)
  if OMA then lvl = math.max(lvl, (tonumber(OMA.ArtTopLevel()) or 0) + 20) end
  -- the game's waypoint (and super-tracked) pin goes under Questicus' overlay
  if WorldMapFrame.EnumeratePinsByTemplate then
    for _, tmpl in ipairs({ "WaypointLocationPinTemplate", "SuperTrackedPinTemplate" }) do
      local ok, it = pcall(WorldMapFrame.EnumeratePinsByTemplate, WorldMapFrame, tmpl)
      if ok and it then
        for pin in it do
          local pl = pin.GetFrameLevel and pin:GetFrameLevel() or 0
          if pl >= lvl then lvl = pl + 10 end
        end
      end
    end
  end
  PN.overlay:SetFrameLevel(math.min(9000, lvl))
  PN.overlay:Show()
  if not wpool then wpool = pool(PN.overlay, 18) end
  wpool:Release()
  PN:ReleasePatrolHits()
  PN:ReleaseAreas()
  for _, l in ipairs(PN.lines) do l.bg:Hide(); l.fg:Hide() end
  if not (Q.db.pins.world and D:Ready() and Q.char.surveyDone) then return end
  local mapID = WorldMapFrame:GetMapID()
  local cs = sc.GetCanvasScale and sc:GetCanvasScale() or 1
  local cw, ch = canvas:GetWidth(), canvas:GetHeight()
  local size = 18 * (Q.db.pins.size or 1)
  lastMap, lastScale = mapID, cs
  local function place(b, x, y)
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
  local px, py
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
            if op.key and op.key:sub(1, 1) ~= "t" then b.spot = { op.key, op } end
            place(b, x, y)
          end
        end
      end
      PN:Areas(all, col, k, cw, ch)
    end
    local x, y
    if pt then x, y = onMap(pt, mapID) end
    if x then
      -- line from the previous point (you, then the step before)
      if px and not (Q.OnTaxi() or (IsFlying and IsFlying())) then   -- no route lines while flying
        local legs = { { x, y } }
        if k == 1 and prev and Q.Nav then
          -- the first leg follows the less obstructed path (Nav.lua)
          local path = Q.Nav:Route(prev, pt)
          if path and #path > 1 then
            legs = {}
            for _, wpt in ipairs(path) do
              local wx, wy = onMap(wpt, mapID)
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
      local b = wpool:Get()
      local icon = (s.type == "accept" and ICON.accept) or (s.type == "turnin" and ICON.turnin) or
        (s.type == "buy" and ICON.buy) or ICON[s.type] or ICON.kill
      style(b, icon, size * (k == 1 and 1.3 or 1.0), 1, 1, 1, 1, tostring(e.index))
      b:SetFrameLevel(ring:GetFrameLevel() + 2)
      b.tip = { Q.Guide.StepText(s), PN.LABELS[k] .. " - step " .. e.index .. " of your route",
        "Click to point the arrow here" }
      if pt.key and (pt.key:sub(1, 1) == "c" or pt.key:sub(1, 1) == "o") then b.spot = { pt.key, pt } end
      local note = D:Note(pt.key)
      if note then table.insert(b.tip, 2, note) end
      b.step = e.index
      place(b, x, y)
      px, py = x, y
    else
      px, py = nil, nil            -- next leg starts on another map: no line across
    end
  end
  for i = li + 1, #PN.lines do PN.lines[i].bg:Hide(); PN.lines[i].fg:Hide() end
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
    for _, ln in ipairs({ l.bg, l.fg }) do
      ln:SetStartPoint("TOPLEFT", canvas, a[1] * e.cw, -a[2] * e.ch)
      ln:SetEndPoint("TOPLEFT", canvas, b[1] * e.cw, -b[2] * e.ch)
      ln:Show()
    end
    l.fg:SetColorTexture(math.min(1, col[1] + 0.25), math.min(1, col[2] + 0.25), math.min(1, col[3] + 0.25), 1)
    l.fg:SetThickness(6 / e.cs)
    l.bg:SetThickness(10 / e.cs)
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
  for _, ln in ipairs({ l.bg, l.fg }) do
    ln:SetStartPoint("TOPLEFT", canvas, a1, b1)
    ln:SetEndPoint("TOPLEFT", canvas, a2, b2)
    ln:Show()
  end
  l.fg:SetColorTexture(col[1], col[2], col[3], 0.95)
  l.fg:SetThickness(px / cs)
  l.bg:SetThickness((px + 3) / cs)
end

local function hookWorldMap()
  if not WorldMapFrame or PN.hooked then return end
  PN.hooked = true
  if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() PN:RefreshWorld() end) end
  WorldMapFrame:HookScript("OnShow", function() PN:RefreshWorld() end)
  local watcher = CreateFrame("Frame", nil, WorldMapFrame)
  local acc = 0
  watcher:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < (Q.OnTaxi() and 2 or 0.2) then return end
    acc = 0
    local sc = WorldMapFrame.ScrollContainer
    local cs = sc and sc.GetCanvasScale and sc:GetCanvasScale() or 1
    -- redraw when the map / zoom changes, or you moved (the route line starts at you)
    local here = D:PlayerPos()
    local moved = here and (not PN.lastHere or D.Dist(here, PN.lastHere) > 8)
    if moved then PN.lastHere = here end
    if WorldMapFrame:GetMapID() ~= lastMap or cs ~= lastScale or moved then PN:RefreshWorld() end
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
  for _, ln in ipairs({ l.bg, l.fg }) do
    ln:SetStartPoint("CENTER", Minimap, a1, b1)
    ln:SetEndPoint("CENTER", Minimap, a2, b2)
    ln:Show()
  end
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
  local dist = math.sqrt(ex * ex + ny * ny)
  if dist > radius then
    if not clamp then return end
    ex, ny = ex / dist * radius * 0.95, ny / dist * radius * 0.95
  end
  local scale = (Minimap:GetWidth() / 2) / radius
  return ex * scale, ny * scale, dist <= radius
end

function PN:RefreshMinimap()
  if not Minimap then return end
  if not mpool then mpool = pool(Minimap, 14) end
  mpool:Release()
  mlineN = 0
  local function hideLines()
    PN.mmLines = mlineN
    for i = mlineN + 1, #mlines do mlines[i].bg:Hide(); mlines[i].fg:Hide() end
  end
  if not (Q.db.pins.minimap and Q.char.surveyDone and P.steps) then hideLines(); return end
  local here = D:PlayerPos()
  if not here then hideLines(); return end
  local lines = Q.db.pins.mmRoute ~= false
  -- flying (flight path or flying mount): no route lines or trails, just the icons
  local flying = Q.OnTaxi() or (IsFlying and IsFlying()) or false
  if flying then lines = false end
  local function put(b, x, y)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  local half = (Minimap:GetWidth() or 140) / 2
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
              b.tip = QS:QuestTip(id, D:Name(k), "Quest you can pick up")
              b.spot = { k, gp }
              put(b, x, y)
            end
          end
        end
      end
    end
  end
  -- mobs you still need for quests in your log (kills and every mob that drops a quest item): X
  -- the current step's mobs get a skull and are drawn first
  if Q.Marks and Q.Marks.need then
    local n = 0
    local function mobs(list, skull)
      for npc, title in pairs(list) do
        if skull or not Q.Marks.main[npc] then
          for _, mp in ipairs(D:Points("c" .. npc)) do
            if n >= 50 then break end
            if mp.i == here.i and not mp.dungeon and D.Dist(here, mp) < 260 then
              local x, y = minimapXY(here, mp)
              if x then
                local b = mpool:Get()
                if skull then
                  style(b, PN.SKULL8, 13, 1, 1, 1, 1)
                  b:SetFrameLevel(b:GetFrameLevel() + 2)
                  b.tip = { D:Name("c" .. npc), "Kill for: " .. title, "Current step" }
                else
                  style(b, PN.CROSS, 11, 1, 1, 1, 0.9)
                  b.tip = { D:Name("c" .. npc), "For: " .. title }
                end
                b.spot = { "c" .. npc, mp }
                put(b, x, y)
                n = n + 1
              end
            end
          end
        end
      end
    end
    mobs(Q.Marks.main, true)
    mobs(Q.Marks.need, false)
  end
  local prev, prevX, prevY = here, 0, 0
  for k, e in ipairs(PN.RouteSteps()) do
    local col, s, pt = PN.COLORS[k], e.step, e.point
    if s.type == "complete" and k <= 2 then
      local patrolled = {}
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
              b.tip = { D:Name(op.key or ""), (QS:Info(id) and QS:Info(id).title or ""), PN.LABELS[k] }
              if op.key and op.key:sub(1, 1) ~= "t" then b.spot = { op.key, op } end
              put(b, x, y)
            end
          end
        end
      end
    end
    if not pt or pt.i ~= here.i then break end
    if lines then
      -- route line from the previous point (you, then the step before); the first leg follows
      -- the less obstructed path. Lines are clipped at the minimap's edge, so they still show
      -- the way to steps that are further away.
      local legs = { pt }
      if k == 1 and Q.Nav and not Q.OnTaxi() then
        local path = Q.Nav:Route(here, pt)
        if path and #path > 1 then legs = path end
      end
      local ax, ay = minimapRaw(here, prev)
      for _, wpt in ipairs(legs) do
        local bx, by = minimapRaw(here, wpt)
        mmLine(ax, ay, bx, by, col, k == 1 and 3 or 2, k == 1 and 0.95 or 0.75)
        ax, ay = bx, by
      end
    elseif not flying then
      -- lines off: the old dotted trail to the first step
      local x0, y0 = minimapXY(here, pt, true)
      local dx, dy = x0 - prevX, y0 - prevY
      local n = math.floor(math.sqrt(dx * dx + dy * dy) / 9)
      for j = 1, n - 1 do
        local d = mpool:Get()
        style(d, DOT, k == 1 and 4 or 3, col[1], col[2], col[3], k == 1 and 0.95 or 0.75)
        put(d, prevX + dx * j / n, prevY + dy * j / n)
      end
    end
    local x, y, inside = minimapXY(here, pt, k == 1)
    if x then
      local ring = mpool:Get()
      style(ring, DOT, k == 1 and 20 or 15, col[1], col[2], col[3], 0.9)
      put(ring, x, y)
      local b = mpool:Get()
      style(b, s.type == "turnin" and ICON.turnin or (s.type == "accept" and ICON.accept) or
        (s.type == "buy" and ICON.buy or ICON[s.type] or ICON.kill), k == 1 and 14 or 11, 1, 1, 1, 1)
      b:SetFrameLevel(ring:GetFrameLevel() + 2)
      b.tip = { Q.Guide.StepText(s), PN.LABELS[k] .. " - step " .. e.index .. " of your route" }
      if pt.key and (pt.key:sub(1, 1) == "c" or pt.key:sub(1, 1) == "o") then b.spot = { pt.key, pt } end
      if pt.key and D:Note(pt.key) then table.insert(b.tip, D:Note(pt.key)) end
      put(b, x, y)
    end
    if not lines and not inside then break end   -- dotted trail: nothing beyond the edge
    prev, prevX, prevY = pt, x or prevX, y or prevY
  end
  hideLines()
end

local function startMinimap()
  if mframe then return end
  mframe = CreateFrame("Frame")
  local acc = 0
  mframe:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < (Q.OnTaxi() and 1 or 0.1) then return end
    acc = 0
    PN:RefreshMinimap()
  end)
end

Q:On("QC_READY", function() hookWorldMap(); startMinimap() end)
-- taking off / landing: lines go away / come back right away
local function flightChanged() Q.After(0.3, function() PN:RefreshMinimap(); PN:RefreshWorld() end) end
Q:On("PLAYER_CONTROL_LOST", flightChanged)
Q:On("PLAYER_CONTROL_GAINED", flightChanged)
Q:On("QC_PLAN_UPDATED", function() available = nil; PN:RefreshWorld() end)
Q:On("QC_TARGET_CHANGED", function() PN:RefreshWorld() end)
