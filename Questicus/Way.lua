-- Your own waypoints: /way, a list of /way lines pasted in one go, and Ctrl-click on the minimap.
-- Each one is followed (in the world, on the map) until you get there; then the next one, then the
-- route again (Waypoint.lua).
local Q = Questicus
local L = Q.L
local T, D = Q.T, Q.Data
local WY = {}
Q.Way = WY
local cfg = function() return Q.db.beacon end

-- ------------------------------------------------------------------ zone names
local names
local function norm(s) return (s or ""):lower():gsub("[%s%p]", "") end
local function addMap(id)
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
  if info and info.name and info.name ~= "" then
    local k = norm(info.name)
    -- (the zone wins over a dungeon map or floor of the same name)
    if not names[k] or (info.mapType == 3 and names[k].t ~= 3) then names[k] = { id = id, t = info.mapType } end
  end
end
local function buildNames()
  names = {}
  if not (C_Map and C_Map.GetMapChildrenInfo) then return end
  for _, root in ipairs({ 946, 947, 1414, 1415, 1945 }) do
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
    if ok and kids then for _, k in ipairs(kids) do addMap(k.mapID) end end
    addMap(root)
  end
end
function WY.MapByName(s)
  if not names then buildNames() end
  local k = norm(s)
  if k == "" then return end
  if names[k] then return names[k].id end
  -- the start of a name ("stv" won't do, "stranglethorn" will)
  local best
  for n, e in pairs(names) do
    if n:sub(1, #k) == k and (not best or #n < #best[1]) then best = { n, e.id } end
  end
  return best and best[2]
end

-- ------------------------------------------------------------------ /way
-- /way [zone | #mapID] x y [name]   (x y as 45.2 61.3 or 45.2, 61.3)
function WY.Parse(msg)
  msg = (msg or ""):gsub("^%s*/way%s*", ""):gsub(",", " ")
  local words = {}
  for w in msg:gmatch("%S+") do words[#words + 1] = w end
  -- the first two numbers next to each other are the coordinates
  local xi
  for i = 1, #words - 1 do
    if tonumber(words[i]) and tonumber(words[i + 1]) then xi = i; break end
  end
  if not xi then return end
  local x, y = tonumber(words[xi]), tonumber(words[xi + 1])
  if x > 1 or y > 1 then x, y = x / 100, y / 100 end
  if x < 0 or x > 1 or y < 0 or y > 1 then return end
  local zone = table.concat(words, " ", 1, xi - 1)
  local name = table.concat(words, " ", xi + 2)
  local m
  if zone:match("^#%d+$") then m = tonumber(zone:sub(2))
  elseif zone ~= "" then m = WY.MapByName(zone) end
  if zone ~= "" and not m then return nil, ("No zone called \"%s\""):format(zone) end
  if not m then
    -- the map you have open, else where you are
    m = (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID())
      or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
  end
  if not m then return end
  return { m = m, x = x, y = y, name = name ~= "" and name or nil }
end

local function wayTo(w, quiet)
  local W = Q.Waypoint
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(w.m)
  local label = w.name or ("%s %.1f, %.1f"):format(info and info.name or "", w.x * 100, w.y * 100)
  if W:PinUser(w.m, w.x, w.y, label, quiet) and not quiet then
    Q:Print(("Waypoint: %s"):format(label))
  end
end

function WY.Command(msg)
  local m = (msg or ""):lower():match("^%s*(%S*)")
  local W = Q.Waypoint
  if m == "clear" or m == "reset" then
    W.queue = {}
    if W.manual then W:NextUser() end
    Q:Print(L["Your waypoints cleared - back to the route."])
    return
  end
  if m == "paste" then WY.ShowPaste(); return end
  if m == "" or m == "help" then
    Q:Print(L["/way [zone] x y [name] - a waypoint (zone: the open map or where you are when left out)"])
    Q:Print(L["/way paste - put in a list of /way lines, followed one after the other"])
    Q:Print(L["/way clear - drop your waypoints, back to the route"])
    Q:Print(L["Ctrl-click the minimap: a waypoint where you clicked"])
    return
  end
  local w, err = WY.Parse(msg)
  if not w then Q:Print(err or "Use: /way [zone] x y [name]"); return end
  W.queue = {}
  wayTo(w)
end

-- several lines: the first now, the rest one after the other
function WY.Many(text)
  local list = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local w = WY.Parse(line)
    if w then list[#list + 1] = w end
  end
  if #list == 0 then Q:Print(L["No /way lines in that."]); return 0 end
  local W = Q.Waypoint
  W.queue = {}
  for k = 2, #list do
    local w = list[k]
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(w.m)
    W.queue[#W.queue + 1] = { m = w.m, x = w.x, y = w.y,
      name = w.name or ("%s %.1f, %.1f"):format(info and info.name or "", w.x * 100, w.y * 100) }
  end
  wayTo(list[1], true)
  Q:Print(("%d waypoint%s - followed one after the other."):format(#list, #list == 1 and "" or "s"))
  return #list
end

-- the paste window
local paste
function WY.ShowPaste()
  if not paste then
    paste = T.Window("QuesticusWayPaste", 420, 300, "Paste /way lines", nil)
    paste:SetFrameStrata("DIALOG")
    local sf = CreateFrame("ScrollFrame", nil, paste, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -40)
    sf:SetPoint("BOTTOMRIGHT", -34, 48)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFont(T.FONT, 12, "")
    eb:SetWidth(360)
    eb:SetScript("OnEscapePressed", function() paste:Hide() end)
    sf:SetScrollChild(eb)
    paste.eb = eb
    local go = T.Button(paste, "Follow these", 120, 24)
    go:SetPoint("BOTTOMRIGHT", -14, 12)
    go:SetScript("OnClick", function() if WY.Many(eb:GetText()) > 0 then paste:Hide() end end)
    local cancel = T.Button(paste, "Cancel", 90, 24)
    cancel:SetPoint("RIGHT", go, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() paste:Hide() end)
  end
  paste.eb:SetText("")
  paste:Show()
  paste.eb:SetFocus()
end

SLASH_QUESTICUSWAY1 = "/qway"
-- (/way too, unless another addon - TomTom - has it)
if not (SlashCmdList.TOMTOM_WAY or (_G.TomTom)) then SLASH_QUESTICUSWAY2 = "/way" end
SlashCmdList.QUESTICUSWAY = WY.Command
Q:Command("way", "a waypoint: /qc way [zone] x y [name], /qc way paste, /qc way clear", function(rest) WY.Command(rest) end)

-- ------------------------------------------------------------------ Ctrl-click the minimap
-- the spot under the cursor on the minimap, in world yards
function WY.MinimapCursorPos()
  local here = D:PlayerPos()
  if not (here and Minimap) then return end
  local cx, cy = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  local mx, my = Minimap:GetCenter()
  local ex, ny = cx / s - mx, cy / s - my
  local zoom = Minimap:GetZoom() or 0
  local sizes = (IsIndoors and IsIndoors() and MINIMAP_SIZE and MINIMAP_SIZE.indoor) or (MINIMAP_SIZE and MINIMAP_SIZE.outdoor) or {}
  local radius = (sizes[zoom] or 466) / 2
  local scale = (Minimap:GetWidth() / 2) / radius
  ex, ny = ex / scale, ny / scale
  if GetCVar and GetCVar("rotateMinimap") == "1" then
    local f = -(GetPlayerFacing and GetPlayerFacing() or 0)
    local c, sn = math.cos(f), math.sin(f)
    ex, ny = ex * c - ny * sn, ex * sn + ny * c
  end
  -- (east on screen is minus "y" - world y grows to the west)
  return { i = here.i, x = here.x + ny, y = here.y - ex }
end
local function onMinimapClick(_, button)
  if button ~= "LeftButton" or not (IsControlKeyDown and IsControlKeyDown()) then return end
  if cfg().minimapPins == false then return end
  local pt = WY.MinimapCursorPos()
  if not pt then return end
  local m, x, y = D:MapPos(pt)
  if not m then Q:Print(L["Can't put a waypoint there."]); return end
  Q.Waypoint.queue = {}
  wayTo({ m = m, x = x, y = y })
end
Q:On("QC_READY", function()
  if Minimap and Minimap.HookScript then Minimap:HookScript("OnMouseUp", onMinimapClick) end
end)

-- your own sounds: /qc waysound show|near|leave <sound file ID>  (0 = silent, nothing = the default)
Q:Command("waysound", "the waypoint's sounds: /qc waysound show|near|leave <file ID | 0 for none | blank for default>", function(rest)
  local which, id = (rest or ""):lower():match("^(%a+)%s*(%d*)")
  if not (which == "show" or which == "near" or which == "leave") then
    Q:Print(L["/qc waysound show|near|leave <file ID>  - 0 mutes it, nothing puts the default back"])
    return
  end
  cfg().sounds = cfg().sounds or {}
  cfg().sounds[which] = (id ~= "" and tonumber(id)) or nil
  Q:Print(("Waypoint sound \"%s\": %s"):format(which, id == "" and "default" or (id == "0" and "none" or id)))
  if Q.Beacon then Q.Beacon.Play(which) end
end)
