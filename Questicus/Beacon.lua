-- Questicus in-world waypoint: a marker standing over the destination in the world, with a beam of
-- light, the distance, when you'll get there and what it is. Close up it turns into a pinpoint over the
-- target that says what it is; off screen, a pointer at the edge shows which way to turn.
-- It rides on the game's own navigation frame (where the game draws its waypoint marker), so it works
-- for any waypoint that's tracked: Questicus' own, a pin you put on the map, /way, a map link.
local Q = Questicus
local T, D = Q.T, Q.Data
local B = {}
Q.Beacon = B

local MEDIA = Q.MEDIA
local frame
local cfg = function() return Q.db.beacon end

-- ------------------------------------------------------------------ what's tracked
local COLORS = {
  accept = { 1, 0.82, 0.1 },        -- a quest to pick up
  turnin = { 1, 0.62, 0.15 },       -- ready to hand in
  complete = { 0.25, 0.82, 0.79 },  -- objectives
  buy = { 0.6, 0.85, 0.35 },
  corpse = { 1, 0.3, 0.25 },
  pin = { 0.35, 0.7, 1 },           -- your own map pin / /way
  travel = { 0.55, 0.75, 1 },       -- flight master, boat, a place to go
}
B.COLORS = COLORS
local ICONS = {
  accept = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  complete = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
  buy = "Interface\\GossipFrame\\VendorGossipIcon",
  corpse = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  pin = "Interface\\Minimap\\Tracking\\None",
  travel = "Interface\\Minimap\\Tracking\\FlightMaster",
}

local function coordText(m, x, y)
  if not (m and x) then return nil end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return ("%s %.1f, %.1f"):format(info and info.name or "", x * 100, y * 100)
end

-- { kind, name, sub } for the waypoint being tracked
function B.Context()
  local W = Q.Waypoint
  if W and W.onCorpse then return { kind = "corpse", name = "Your corpse", sub = "Run back here to resurrect" } end
  local man = W and W.manual
  if man then
    return { kind = "pin", name = man.name or "Map pin", sub = coordText(man.m, man.x, man.y) }
  end
  if W and W.IsOurs and W:IsOurs() then
    local _, s = Q.Guide:Target()
    if s then
      local t = s.type
      local kind = (t == "accept" or t == "turnin" or t == "buy" or t == "complete") and t or "travel"
      local name = Q.Arrow and Q.Arrow.ShortText and Q.Arrow.ShortText(s) or ""
      if name == "" and Q.Guide.StepText then name = Q.Guide.StepText(s) or "" end
      local sub = (kind == "accept" and "Pick up") or (kind == "turnin" and "Ready to hand in")
        or (kind == "buy" and "Buy") or (kind == "complete" and "Objectives")
        or ((t == "fp" or t == "fly") and "Flight master") or ((t == "boat") and "Boat / zeppelin")
        or (t == "explore" and "Explore") or "Next step"
      return { kind = kind, name = name, sub = sub }
    end
  end
  local wp = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
  if wp then
    local x, y = wp.position.x, wp.position.y
    if wp.position.GetXY then x, y = wp.position:GetXY() end
    return { kind = "pin", name = "Map pin", sub = coordText(wp.uiMapID, x, y) }
  end
  return { kind = "pin", name = "Waypoint" }
end

local function colorOf(kind)
  local c = cfg()
  if c.customColor and c.color then return c.color end
  return COLORS[kind] or COLORS.pin
end

-- ------------------------------------------------------------------ text
local function distText(d)
  if cfg().meters then
    d = d * 0.9144
    if d >= 1000 then return ("%.1f km"):format(d / 1000) end
    return ("%d m"):format(math.floor(d + 0.5))
  end
  return ("%d yd"):format(math.floor(d + 0.5))
end
B.DistText = distText
local function etaText(s)
  if not s or s ~= s or s > 5940 then return nil end
  s = math.floor(s + 0.5)
  if s >= 60 then return ("%dm %02ds"):format(math.floor(s / 60), s % 60) end
  return ("%ds"):format(s)
end
B.EtaText = etaText

-- arrival time: how fast the distance is going down (smoothed)
local speed, lastD, lastT = 0, nil, nil
local function sample(d)
  local now = GetTime()
  if lastD and now - lastT >= 0.5 then
    local v = (lastD - d) / (now - lastT)
    if math.abs(lastD - d) > 200 then v = 0 end          -- (a new destination: start over)
    speed = speed * 0.7 + v * 0.3
    lastD, lastT = d, now
  elseif not lastD then
    lastD, lastT = d, now
  end
  if speed > 0.8 then return d / speed end
end

-- ------------------------------------------------------------------ sounds
local SOUNDS = {
  show = function() return SOUNDKIT and SOUNDKIT.MAP_PING or 3175 end,
  near = function() return SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 619 end,
  leave = function() return SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_CLOSE or 876 end,
}
local function play(which)
  local c = cfg()
  if not c.sound then return end
  local custom = c.sounds and tonumber(c.sounds[which])
  if custom and custom > 0 then
    if PlaySoundFile then pcall(PlaySoundFile, custom, "Master") end
    return
  end
  if c.sounds and c.sounds[which] == 0 then return end   -- muted
  if PlaySound then pcall(PlaySound, SOUNDS[which](), "Master") end
end
B.Play = play

-- ------------------------------------------------------------------ frames
local function build()
  local parent = cfg().alwaysShow and WorldFrame or UIParent
  frame = CreateFrame("Frame", "QuesticusBeacon", parent)
  frame:SetSize(40, 40)
  frame:SetFrameStrata("BACKGROUND")
  frame:SetFrameLevel(2)
  frame:Hide()

  -- the waypoint: diamond, beam, info under it
  local wpf = CreateFrame("Button", nil, frame)
  wpf:SetSize(30, 30)
  wpf:SetPoint("CENTER")
  wpf:RegisterForClicks("RightButtonUp")
  frame.wp = wpf
  wpf.beam = wpf:CreateTexture(nil, "BACKGROUND")
  wpf.beam:SetTexture(MEDIA .. "wp_beam")
  wpf.beam:SetBlendMode("ADD")
  wpf.beam:SetSize(26, 360)
  wpf.beam:SetPoint("BOTTOM", wpf, "CENTER", 0, 6)
  wpf.glow = wpf:CreateTexture(nil, "BORDER")
  wpf.glow:SetTexture(MEDIA .. "glow")
  wpf.glow:SetBlendMode("ADD")
  wpf.glow:SetSize(64, 64)
  wpf.glow:SetPoint("CENTER")
  wpf.back = wpf:CreateTexture(nil, "ARTWORK")
  wpf.back:SetTexture(MEDIA .. "wp_diamond")
  wpf.back:SetAllPoints()
  wpf.edge = wpf:CreateTexture(nil, "ARTWORK", nil, 1)
  wpf.edge:SetTexture(MEDIA .. "wp_diamond_edge")
  wpf.edge:SetPoint("CENTER")
  wpf.edge:SetSize(36, 36)
  wpf.icon = wpf:CreateTexture(nil, "OVERLAY")
  wpf.icon:SetSize(16, 16)
  wpf.icon:SetPoint("CENTER")
  wpf.line1 = T.Text(wpf, 13, T.c.text, "OUTLINE")
  wpf.line1:SetPoint("TOP", wpf, "BOTTOM", 0, -4)
  wpf.line2 = T.Text(wpf, 11, T.c.dim, "OUTLINE")
  wpf.line2:SetPoint("TOP", wpf.line1, "BOTTOM", 0, -2)

  -- the pinpoint: a card over the target with what it is
  local pp = CreateFrame("Button", nil, frame)
  pp:SetSize(220, 44)
  pp:SetPoint("BOTTOM", frame, "CENTER", 0, 40)
  pp:RegisterForClicks("RightButtonUp")
  frame.pp = pp
  pp.bg = T.RFill(pp, { 0.05, 0.06, 0.08, 0.82 }, 8)
  pp.bar = pp:CreateTexture(nil, "ARTWORK")
  pp.bar:SetColorTexture(1, 1, 1, 1)
  pp.bar:SetPoint("TOPLEFT", 6, -6)
  pp.bar:SetPoint("BOTTOMLEFT", 6, 6)
  pp.bar:SetWidth(3)
  pp.icon = pp:CreateTexture(nil, "ARTWORK")
  pp.icon:SetSize(22, 22)
  pp.icon:SetPoint("LEFT", 16, 0)
  pp.name = T.Text(pp, 13, T.c.text, "OUTLINE")
  pp.name:SetPoint("TOPLEFT", pp.icon, "TOPRIGHT", 8, 2)
  pp.name:SetPoint("RIGHT", -8, 0)
  pp.name:SetJustifyH("LEFT")
  pp.name:SetWordWrap(false)
  pp.sub = T.Text(pp, 11, T.c.dim, "OUTLINE")
  pp.sub:SetPoint("TOPLEFT", pp.name, "BOTTOMLEFT", 0, -2)
  pp.sub:SetPoint("RIGHT", -8, 0)
  pp.sub:SetJustifyH("LEFT")
  pp.sub:SetWordWrap(false)
  pp.tail = pp:CreateTexture(nil, "ARTWORK")
  pp.tail:SetTexture(MEDIA .. "wp_diamond")
  pp.tail:SetSize(12, 12)
  pp.tail:SetPoint("TOP", pp, "BOTTOM", 0, -26)

  -- the navigator: at the screen's edge, pointing to it
  local nv = CreateFrame("Button", nil, frame)
  nv:SetSize(34, 34)
  nv:SetPoint("CENTER")
  nv:RegisterForClicks("RightButtonUp")
  frame.nv = nv
  nv.back = nv:CreateTexture(nil, "ARTWORK")
  nv.back:SetTexture(MEDIA .. "wp_diamond")
  nv.back:SetAllPoints()
  nv.icon = nv:CreateTexture(nil, "OVERLAY")
  nv.icon:SetSize(16, 16)
  nv.icon:SetPoint("CENTER")
  nv.arrow = nv:CreateTexture(nil, "OVERLAY", nil, 1)
  nv.arrow:SetTexture(MEDIA .. "arrow")
  nv.arrow:SetSize(26, 26)
  nv.dist = T.Text(nv, 11, T.c.text, "OUTLINE")
  nv.dist:SetPoint("TOP", nv, "BOTTOM", 0, -3)

  for _, b in ipairs({ wpf, pp, nv }) do
    b:SetScript("OnClick", function() if cfg().rightClear then B.Clear() end end)
    b:SetScript("OnEnter", function(s)
      if not cfg().rightClear then return end
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      local c = B.Context()
      GameTooltip:AddLine(c.name or "Waypoint", 1, 0.82, 0.3)
      if c.sub then GameTooltip:AddLine(c.sub, 0.9, 0.9, 0.9) end
      GameTooltip:AddLine("Right-click: clear", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
end

-- right-click: clear the waypoint (Questicus' own: hidden until the route moves on to another step)
function B.Clear()
  local W = Q.Waypoint
  if W and W.Dismiss then W:Dismiss() end
end

local function tint(c, kind)
  local col = colorOf(kind)
  local conf = cfg()
  local ic = ICONS[kind] or ICONS.pin
  for _, t in ipairs({ frame.wp.back, frame.nv.back, frame.pp.tail }) do t:SetVertexColor(col[1], col[2], col[3], 1) end
  frame.wp.edge:SetVertexColor(1, 1, 1, 0.9)
  frame.wp.glow:SetVertexColor(col[1], col[2], col[3], 0.55)
  local bc = (conf.customColor and conf.beamColor) or col
  frame.wp.beam:SetVertexColor(bc[1], bc[2], bc[3], 1)
  frame.pp.bar:SetVertexColor(col[1], col[2], col[3], 1)
  frame.nv.arrow:SetVertexColor(col[1], col[2], col[3], 1)
  for _, t in ipairs({ frame.wp.icon, frame.nv.icon, frame.pp.icon }) do
    t:SetTexture(ic)
    if conf.customColor and conf.tintIcon then t:SetVertexColor(col[1], col[2], col[3], 1) else t:SetVertexColor(1, 1, 1, 1) end
  end
  frame.pp.name:SetText(c.name or "")
  frame.pp.sub:SetText(c.sub or "")
  frame.pp.sub:SetShown(conf.ppInfo ~= false and conf.ppExtended ~= false and c.sub ~= nil)
  frame.pp.name:SetShown(conf.ppInfo ~= false)
  local w = math.max(frame.pp.name:GetStringWidth() or 0, frame.pp.sub:IsShown() and frame.pp.sub:GetStringWidth() or 0)
  frame.pp:SetWidth(math.min(320, math.max(120, w + 58)))
  frame.pp:SetHeight(frame.pp.sub:IsShown() and 44 or 32)
end

-- ------------------------------------------------------------------ hiding the game's own marker
local function hideBlizzard()
  local f = _G.SuperTrackedFrame
  if f and B.active and f:IsShown() then f:Hide() end
end
local hooked
local function hookBlizzard()
  if hooked or not _G.SuperTrackedFrame then return end
  hooked = true
  hooksecurefunc(SuperTrackedFrame, "Show", hideBlizzard)
  hooksecurefunc(SuperTrackedFrame, "SetShown", hideBlizzard)
end
local function restoreBlizzard()
  local f = _G.SuperTrackedFrame
  if f and f.CheckInitializeNavigationFrame then
    pcall(f.CheckInitializeNavigationFrame, f)
    f:SetShown(f.navFrame ~= nil)
  end
end

-- ------------------------------------------------------------------ every frame
local lastKey, wasNear, shownAt = nil, nil, 0
local function navFrame()
  if not (C_Navigation and C_Navigation.GetFrame) then return end
  local ok, f = pcall(C_Navigation.GetFrame)
  return ok and f or nil
end
local function distance()
  if C_Navigation and C_Navigation.GetDistance then
    local ok, d = pcall(C_Navigation.GetDistance)
    if ok and d and d > 0 then return d end
  end
end

-- the size: larger close up, smaller far away (or a fixed size)
local function scaleFor(d)
  local c = cfg()
  local s = c.scale or 1
  if c.worldScale ~= false then
    local lo, hi = c.minScale or 0.6, c.maxScale or 1.2
    local f = 1 - math.min(1, math.max(0, (d - 30) / 500))
    s = s * (lo + (hi - lo) * f)
  end
  return s
end

function B:Update()
  local c = cfg()
  local f = c.on and not B.standDown and navFrame()
  local d = f and distance()
  if not f or not d or (Q.CollectOnly and Q.CollectOnly()) then
    if frame and frame:IsShown() then frame:Hide() end
    if B.active then B.active = false; restoreBlizzard() end
    lastD, speed, lastKey, wasNear, B.lastDest = nil, 0, nil, nil, nil
    return
  end
  if not frame then build() end
  B.active = true
  hookBlizzard()
  hideBlizzard()
  -- arrived: nothing to show (Questicus' route moves on by itself)
  local hideAt = c.hideAt or 4
  if d <= hideAt then frame:Hide(); return end

  local ctx = B.Context()
  local key = ctx.kind .. "|" .. (ctx.name or "") .. "|" .. (ctx.sub or "")
  if key ~= lastKey then
    tint(ctx, ctx.kind)
    lastKey = key
    -- a new destination (not just its text changing): a sound, and "near" starts over
    local dest = ctx.kind .. "|" .. (ctx.name or "")
    if dest ~= B.lastDest then
      B.lastDest = dest
      if GetTime() - shownAt > 1 then play("show") end
      shownAt = GetTime()
      wasNear = nil
    end
  end
  -- sounds: getting there / walking away
  local prox = c.proxDist or 20
  if c.proximity ~= false then
    if d <= prox and wasNear == false then play("near") end
    if d > prox + 10 and wasNear == true then play("leave") end
  end
  if d <= prox then wasNear = true elseif d > prox + 10 then wasNear = false end

  -- where on screen (the game's frame is clamped to the edge when the place is off screen)
  local cx, cy = f:GetCenter()
  if not cx then frame:Hide(); return end
  local es = f:GetEffectiveScale()
  local parent = frame:GetParent()
  local ps = parent:GetEffectiveScale()
  local x, y = cx * es / ps, cy * es / ps
  local clamped = C_Navigation.WasClampedToScreen and C_Navigation.WasClampedToScreen()
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
  frame:Show()

  local alpha = c.alpha or 1
  local mode
  if clamped then mode = c.navigator ~= false and "nav" or nil
  elseif d <= (c.pinpointAt or 60) then mode = c.pinpoint ~= false and "pp" or "wp"
  else mode = c.waypoint ~= false and "wp" or nil end
  frame.wp:SetShown(mode == "wp")
  frame.pp:SetShown(mode == "pp")
  frame.nv:SetShown(mode == "nav")
  if not mode then return end
  local hover = c.fadeHover ~= false and ((mode == "wp" and frame.wp:IsMouseOver()) or (mode == "pp" and frame.pp:IsMouseOver()))
  if hover then alpha = alpha * 0.3 end
  frame:SetAlpha(alpha)
  local eta = sample(d)

  if mode == "wp" then
    local s = scaleFor(d)
    frame.wp:SetScale(s)
    frame.wp.beam:SetShown(c.beam ~= false)
    frame.wp.beam:SetAlpha(c.beamAlpha or 0.7)
    local info = c.info or "all"
    local l1, l2
    if info == "all" then
      l1 = distText(d) .. ((etaText(eta) and ("  ·  " .. etaText(eta))) or "")
      l2 = ctx.name
    elseif info == "distance" then l1 = distText(d)
    elseif info == "eta" then l1 = etaText(eta) or distText(d)
    elseif info == "name" then l1 = ctx.name end
    frame.wp.line1:SetText(l1 or "")
    frame.wp.line2:SetText(l2 or "")
    frame.wp.line1:SetShown(c.footer ~= false and l1 ~= nil)
    frame.wp.line2:SetShown(c.footer ~= false and l2 ~= nil)
    frame.wp.line1:SetAlpha(c.footerAlpha or 1)
    frame.wp.line2:SetAlpha((c.footerAlpha or 1) * (c.subAlpha or 0.8))
  elseif mode == "pp" then
    frame.pp:SetScale(c.ppScale or 1)
    -- a slow bob, so it reads as a marker over the target
    local bob = math.sin(GetTime() * 2.2) * 3
    frame.pp:ClearAllPoints()
    frame.pp:SetPoint("BOTTOM", frame, "CENTER", 0, 40 + bob)
    frame.pp.icon:SetShown(c.ppIcon ~= false)
  else
    -- pointer: on the edge, turned away from the middle of the screen
    frame.nv:SetScale(c.navScale or 1)
    local w, h = parent:GetWidth(), parent:GetHeight()
    local ang = math.atan2 and math.atan2(y - h / 2, x - w / 2) or math.atan(y - h / 2, x - w / 2)
    local inset = c.navInset or 60
    local px = math.max(inset, math.min(w - inset, x))
    local py = math.max(inset, math.min(h - inset, y))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parent, "BOTTOMLEFT", px, py)
    frame.nv.arrow:SetShown(c.navArrow ~= false)
    frame.nv.arrow:SetSize(26 * (c.navArrowScale or 1), 26 * (c.navArrowScale or 1))
    frame.nv.arrow:ClearAllPoints()
    frame.nv.arrow:SetPoint("CENTER", frame.nv, "CENTER", math.cos(ang) * 30, math.sin(ang) * 30)
    -- (the arrow art points up: turn it to the angle)
    frame.nv.arrow:SetRotation(ang - math.pi / 2)
    frame.nv.icon:SetShown(c.navIcon ~= false)
    frame.nv.dist:SetText(distText(d))
  end
end

-- ------------------------------------------------------------------ start
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.016 then return end
  acc = 0
  local ok, err = pcall(B.Update, B)
  if not ok and not B.err then B.err = true; Q:Debug("beacon: " .. tostring(err)) end
end)

-- moving between "show when the interface is hidden" (on the world) and normal
function B.Reparent()
  if not frame then return end
  frame:SetParent(cfg().alwaysShow and WorldFrame or UIParent)
  frame:SetFrameStrata("BACKGROUND")
end
function B.Refresh()
  lastKey = nil
  if frame then B.Reparent() end
end

Q:On("QC_READY", function()
  -- WaypointUI does the same: stand down while it's running, so you don't get two markers
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if loaded and loaded("WaypointUI") then
    B.standDown = true
    Q:Print("WaypointUI is running, so Questicus' in-world waypoint is off. Questicus now has everything it did - disable WaypointUI and /reload to use Questicus' own.")
  end
end)
