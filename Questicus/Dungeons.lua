-- Questicus dungeons: every dungeon in the game with its levels, bosses, quests, XP and clear time,
-- and "Get all quests": dungeon mode routes you to every quest of that dungeon (with the chains
-- that unlock them), then into the dungeon. Clear times are learned from your own runs.
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local DG = {}
Q.Dungeons = DG

local list, detail
local GOLD, DIM = T.HEX.gold, T.HEX.dim
local function c(hex, s) return Q.Color(hex, s) end
local function mins(sec) sec = math.floor((sec or 0) / 60 + 0.5); return sec >= 60 and ("%dh %dm"):format(math.floor(sec / 60), sec % 60) or (sec .. " min") end

-- ------------------------------------------------------------------ data
-- mobs inside each dungeon: levels, spawn count, bosses (from the spawn data of its instance map)
local info
local function mobsOf()
  if info then return info end
  info = {}
  local DB = D.db
  local function add(area, key, count)
    local nid = tonumber(key:sub(2))
    local n = nid and D:NPC(nid)
    if not n then return end
    local e = info[area]
    if not e then e = { lo = 999, hi = 0, spawns = 0, elites = 0, bosses = {}, xpw = {} }; info[area] = e end
    local lo, hi, rank = n[3] or n[4] or 1, n[4] or n[3] or 1, n[5] or 0
    if D:Faction(nid) then return end                    -- friendly npcs inside (quest givers, prisoners)
    if hi <= 1 then return end                             -- critters, triggers
    e.spawns = e.spawns + count
    if rank == 1 or rank == 2 then e.elites = e.elites + count end
    -- bosses: boss rank, or a named elite with a single spawn
    if rank == 3 or ((rank == 1 or rank == 2) and count == 1) then e.bosses[#e.bosses + 1] = { n[1], hi, nid } end
    e.xpw[#e.xpw + 1] = { hi, count, rank, lo }
  end
  for key, groups in pairs(DB.spw or {}) do
    if key:sub(1, 1) == "c" then
      for _, g in ipairs(groups) do
        local area = D.INSTANCE_AREA[g[1]]
        if area then add(area, key, math.max(1, math.floor((#g - 1) / 2))) end
      end
    end
  end
  -- level range from the bulk of the mobs (a stray low-level add doesn't count)
  local function range(e)
    local top = 0
    for _, w in ipairs(e.xpw) do top = math.max(top, w[1]) end
    local lo, hi = 999, 0
    for _, w in ipairs(e.xpw) do
      if w[1] >= top - 15 then lo, hi = math.min(lo, w[4] or w[1]), math.max(hi, w[1]) end
    end
    e.lo, e.hi = lo, hi
    table.sort(e.bosses, function(a, b) return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    e.bossList = {}
    for i, b in ipairs(e.bosses) do e.bossList[i] = { name = b[1], lvl = b[2], nid = b[3] }; e.bosses[i] = b[1] end
  end
  for _, e in pairs(info) do e.fromSpawns = true; range(e) end
  -- dungeons without spawn data: the npcs known to be inside (levels and bosses, no counts)
  for key, areas in pairs(DB.ind or {}) do
    if key:sub(1, 1) == "c" then
      for _, area in ipairs(areas) do
        if not D.RAID_AREA[area] and not (info[area] and info[area].fromSpawns) then add(area, key, 1); info[area].ind = true end
      end
    end
  end
  for _, e in pairs(info) do if e.ind then range(e) end end
  return info
end

-- every dungeon worth listing: the classic ones and any with quests for you; no raids
local PVP = { [3277] = true, [3358] = true, [2597] = true, [16606] = true }
-- WoW Forever's own dungeons (Blizzard's list: levels and where they are); the later ones show up
-- as soon as ForeverDB has them
DG.FOREVER = {
  ["The Hall of Thanes"] = { 13, 18, "Beneath Ironforge, Dun Morogh" },
  ["Ruins of Lordaeron"] = { 15, 20, "Ruins above the Undercity, Tirisfal Glades" },
  ["Excavation Site: Wetlands"] = { 24, 29, "Above Whelgar's Excavation, Wetlands" },
  ["City of Dalaran"] = { 28, 33, "Alterac Mountains" },
  ["The Drowned City"] = { 35, 40 }, ["Krol'dok Stronghold"] = { 40, 45 }, ["Alcaz Prison"] = { 48, 53 },
  ["Blackmaw Hold"] = { 55, 60 }, ["Shaper's Terrace"] = { 58, 60 },
}
local isInstance = {}
for _, a in pairs(D.INSTANCE_AREA) do isInstance[a] = true end
local listCache, listKey
function DG:List()
  local idx = P.DungeonIndex()
  local key = tostring(QS.pool) .. ":" .. (QS.logCount or 0) .. ":" .. (Q.player.level or 0)
  if listCache and listKey == key then return listCache end
  local seen, out, byName, pendingQ = {}, {}, {}, {}
  local function add(area)
    if seen[area] or D.RAID_AREA[area] or PVP[area] then return end
    local d = D:Dungeon(area)
    if not d then return end
    seen[area] = true
    local m = mobsOf()[area]
    -- the same dungeon under two area ids (zone + instance): one line with both lists of quests
    local same = byName[d[1]]
    if same then
      for _, id in ipairs(idx[area] or {}) do same.quests[#same.quests + 1] = id end
      if not (same.mobs and same.mobs.fromSpawns) and m and m.fromSpawns then same.mobs, same.lo, same.hi = m, m.lo, m.hi end
      if isInstance[area] then same.area = area end
      return
    end
    -- a real dungeon: a classic instance, a WoW Forever dungeon, or one with elite mobs inside
    local fv = DG.FOREVER[d[1]]
    if not isInstance[area] and not fv and not (m and m.spawns > 0 and m.elites > 0) then
      pendingQ[d[1]] = pendingQ[d[1]] or {}
      for _, id in ipairs(idx[area] or {}) do table.insert(pendingQ[d[1]], id) end
      return
    end
    local qs = {}
    for _, id in ipairs(idx[area] or {}) do qs[#qs + 1] = id end
    for _, id in ipairs(pendingQ[d[1]] or {}) do qs[#qs + 1] = id end
    pendingQ[d[1]] = nil
    local qlo, qhi = 999, 0
    for _, id in ipairs(qs) do
      local i = QS:Info(id)
      if i then qlo, qhi = math.min(qlo, i.min or i.level), math.max(qhi, i.level) end
    end
    local lo = (fv and fv[1]) or ((m and m.lo < 999) and m.lo) or (qlo < 999 and qlo) or nil
    local hi = (fv and fv[2]) or ((m and m.hi > 0) and m.hi) or (qhi > 0 and qhi) or nil
    local e = { area = area, name = d[1], lo = lo, hi = hi, quests = qs, mobs = m, forever = fv ~= nil, where = fv and fv[3] }
    byName[d[1]] = e
    out[#out + 1] = e
  end
  for _, area in pairs(D.INSTANCE_AREA) do add(area) end
  for area in pairs(idx) do add(area) end
  for area, d in pairs(D.db.dng or {}) do if DG.FOREVER[d[1]] then add(area) end end
  table.sort(out, function(a, b) return (a.lo or 99) < (b.lo or 99) or ((a.lo or 99) == (b.lo or 99) and a.name < b.name) end)
  listCache, listKey = out, key
  return out
end

-- your own clear times (learned) or an estimate from the number of mobs and bosses
function DG:ClearTime(e)
  local runs = QuesticusCollect and QuesticusCollect.dclear and QuesticusCollect.dclear[e.area]
  if runs and #runs > 0 then
    local s = 0
    for _, r in ipairs(runs) do s = s + r end
    return s / #runs, #runs
  end
  local m = e.mobs
  if not m then return nil end
  return (m.spawns or 0) * 7 + #(m.bosses or {}) * 45 + 120, 0
end

-- XP for one run at your level: mob kills (elites give double, split in a group of 5)
function DG:MobXP(e, lv)
  local m = e.mobs
  if not (m and m.fromSpawns) then return nil end
  local xp = 0
  for _, w in ipairs(m.xpw) do
    local k = QS.KillXP(w[1], lv)
    if w[3] == 1 or w[3] == 2 or w[3] == 3 then k = k * 2 end
    xp = xp + k * w[2]
  end
  return xp / 5
end

function DG:QuestStatus(id, lv)
  if QS.done[id] then return "done", 0 end
  if QS.log[id] then return QS.log[id].complete and "ready to hand in" or "in your log", 1 end
  local i = QS:Info(id)
  if i and lv < (i.min or 1) then return ("needs level %d"):format(i.min), 3 end
  if QS:Available(id) then return "can get now", 2 end
  return "needs an earlier quest", 2
end

-- ------------------------------------------------------------------ pictures
-- the Dungeon Journal's button / background art when the client has it, else the dungeon finder's
-- icon, else a castle
DG.LFG = {
  ["Ragefire Chasm"] = "RagefireChasm", ["The Deadmines"] = "Deadmines", ["Deadmines"] = "Deadmines",
  ["Wailing Caverns"] = "WailingCaverns", ["Shadowfang Keep"] = "ShadowFang", ["Blackfathom Deeps"] = "BlackfathomDeeps",
  ["The Stockade"] = "Stockade", ["Stormwind Stockade"] = "Stockade", ["Gnomeregan"] = "Gnomeregan",
  ["Razorfen Kraul"] = "RazorfenKraul", ["Scarlet Monastery"] = "ScarletMonastery", ["Razorfen Downs"] = "RazorfenDowns",
  ["Uldaman"] = "Uldaman", ["Zul'Farrak"] = "ZulFarrak", ["Maraudon"] = "Maraudon", ["Sunken Temple"] = "SunkenTemple",
  ["The Temple of Atal'Hakkar"] = "SunkenTemple", ["Blackrock Depths"] = "BlackrockDepths",
  ["Blackrock Spire"] = "BlackrockSpire", ["Lower Blackrock Spire"] = "BlackrockSpire", ["Upper Blackrock Spire"] = "BlackrockSpire",
  ["Dire Maul"] = "DireMaul", ["Scholomance"] = "Scholomance", ["Stratholme"] = "Stratholme",
}
DG.CASTLE = "Interface\\Icons\\INV_Misc_Key_14"
local journal
local function journalArt()
  if journal then return journal end
  journal = {}
  if not (EJ_GetInstanceByIndex and EJ_GetNumTiers and EJ_SelectTier) then return journal end
  pcall(function()
    for tier = 1, EJ_GetNumTiers() do
      EJ_SelectTier(tier)
      for _, raid in ipairs({ false, true }) do
        local i = 1
        while true do
          local id, name, _, bg, button, _, _, _, _, _, small = EJ_GetInstanceByIndex(i, raid)
          if not id then break end
          if name and not journal[name] then journal[name] = { button = button, bg = bg, small = small } end
          i = i + 1
        end
      end
    end
  end)
  return journal
end
-- (icon, background) textures for a dungeon
function DG.Art(name)
  local j = journalArt()[name or ""]
  local lfg = DG.LFG[name or ""]
  local icon = (j and (j.small or j.button)) or (lfg and ("Interface\\LFGFrame\\LFGIcon-" .. lfg)) or DG.CASTLE
  local bg = (j and (j.button or j.bg)) or (lfg and ("Interface\\LFGFrame\\UI-LFG-BACKGROUND-" .. lfg)) or nil
  return icon, bg
end

-- ------------------------------------------------------------------ list window
local rows = {}
local function listRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, list.body)
  r:SetHeight(34)
  r.pic = r:CreateTexture(nil, "ARTWORK")
  r.pic:SetSize(30, 30)
  r.pic:SetPoint("LEFT", 4, 0)
  r.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.07) end
  r.name = T.Text(r, 12, T.c.text)
  r.name:SetPoint("LEFT", 42, 0)
  r.lv = T.Text(r, 11, T.c.dim)
  r.lv:SetPoint("LEFT", 250, 0)
  r.q = T.Text(r, 11, T.c.dim)
  r.q:SetPoint("RIGHT", -6, 0)
  r:SetScript("OnClick", function(self) if self.e then DG:ShowDungeon(self.e) end end)
  rows[i] = r
  return r
end
DG.rows = rows

function DG:Show()
  if not list then
    list = T.Window("QuesticusDungeons", 430, 200, "Dungeons", nil)
    list:SetFrameStrata("HIGH")
    list.note = T.Text(list, 11, T.c.dim)
    list.note:SetPoint("TOPLEFT", 14, -32)
    list.note:SetText("Click a dungeon for levels, quests, XP and clear time.")
    list.scroll = CreateFrame("ScrollFrame", nil, list)
    list.scroll:SetPoint("TOPLEFT", 8, -50)
    list.scroll:SetPoint("BOTTOMRIGHT", -8, 10)
    list.body = CreateFrame("Frame", nil, list.scroll)
    list.body:SetSize(414, 1)
    list.scroll:SetScrollChild(list.body)
    if list.scroll.EnableMouseWheel then list.scroll:EnableMouseWheel(true) end
    list.scroll:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, (list.body:GetHeight() or 0) - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
  end
  local lv = Q.player.level or 1
  local all = DG:List()
  local y = 0
  for i, e in ipairs(all) do
    local r = listRow(i)
    r.e = e
    local inRange = e.lo and lv >= e.lo - 2 and lv <= (e.hi or e.lo) + 2
    local active = Q.char.dmode == e.area
    r.pic:SetTexture((DG.Art(e.name)))
    r.pic:SetDesaturated(not inRange)
    r.name:SetText((active and c(GOLD, "> ") or "") .. (inRange and c(T.HEX.white, e.name) or c(DIM, e.name)) ..
      (e.forever and c(T.HEX.good, "  new") or ""))
    r.lv:SetText(e.lo and (e.lo == e.hi and tostring(e.lo) or (e.lo .. "-" .. (e.hi or e.lo))) or "?")
    local todo = 0
    for _, id in ipairs(e.quests) do if not QS.done[id] then todo = todo + 1 end end
    r.q:SetText(#e.quests > 0 and (todo .. " quest" .. (todo == 1 and "" or "s")) or "")
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", 0, 0); r:Show()
    y = y + 34
  end
  for i = #all + 1, #rows do rows[i]:Hide() end
  list.body:SetHeight(math.max(1, y))
  list:SetHeight(math.min(700, 60 + y + 12))
  if Q.Bosses then Q.Bosses.Front(list) else list:Show() end
  return all
end

-- ------------------------------------------------------------------ dungeon window
function DG:ShowDungeon(e)
  if not detail then
    detail = T.Window("QuesticusDungeon", 440, 300, "Dungeon", nil)
    detail:SetFrameStrata("HIGH")
    -- the dungeon's picture across the top
    detail.banner = detail:CreateTexture(nil, "ARTWORK")
    detail.banner:SetPoint("TOPLEFT", 10, -30)
    detail.banner:SetPoint("TOPRIGHT", -10, -30)
    detail.banner:SetHeight(90)
    detail.icon = detail:CreateTexture(nil, "OVERLAY")
    detail.icon:SetSize(48, 48)
    detail.icon:SetPoint("BOTTOMLEFT", detail.banner, "BOTTOMLEFT", 8, 8)
    detail.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detail.text = T.Text(detail, 12, T.c.text)
    detail.text:SetPoint("TOPLEFT", detail.banner, "BOTTOMLEFT", 4, -8)
    detail.text:SetPoint("RIGHT", -14, 0)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetSpacing(3)
    detail.go = T.Button(detail, "Get all quests", 140, 24)
    detail.go:SetPoint("BOTTOMRIGHT", -14, 12)
    detail.back = T.Button(detail, "All dungeons", 110, 24)
    detail.back:SetPoint("RIGHT", detail.go, "LEFT", -8, 0)
    detail.bosses = T.Button(detail, "Bosses", 80, 24)
    detail.bosses:SetPoint("RIGHT", detail.back, "LEFT", -8, 0)
    detail.bosses:SetScript("OnClick", function() if Q.Bosses and detail.e then Q.Bosses:Show(detail.e) end end)
    detail.back:SetScript("OnClick", function() detail:Hide(); DG:Show() end)
  end
  if list and list:IsShown() and detail.ClearAllPoints then
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
  end
  local lv = Q.player.level or 1
  detail.title:SetText(Q.Color(T.HEX.accent, e.name))
  local icon, bg = DG.Art(e.name)
  detail.icon:SetTexture(icon)
  if bg then
    detail.banner:SetTexture(bg)
    detail.banner:SetTexCoord(0, 1, 0.15, 0.85)
    detail.banner:SetVertexColor(1, 1, 1, 1)
  else
    detail.banner:SetTexture("Interface\\Buttons\\WHITE8x8")
    detail.banner:SetVertexColor(T.c.line[1], T.c.line[2], T.c.line[3], 0.35)
  end
  local L = {}
  local function add(s) L[#L + 1] = s end
  local ent = D:Entrance(e.area)[1]
  local mi = ent and ent.m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ent.m)
  if e.forever then add(c(T.HEX.good, "New in WoW Forever") .. (e.where and c(DIM, " - " .. e.where) or "")) end
  if mi then add(c(DIM, "Entrance: ") .. mi.name .. (ent.mx and ("  %.1f, %.1f"):format(ent.mx * 100, ent.my * 100) or "")) end
  if e.lo then add(c(DIM, e.forever and "Levels: " or "Mob levels: ") .. (e.lo == e.hi and e.lo or (e.lo .. "-" .. e.hi))) end
  local qlo, qhi = 999, 0
  for _, id in ipairs(e.quests) do local i = QS:Info(id); if i then qlo, qhi = math.min(qlo, i.min or 1), math.max(qhi, i.level) end end
  if qhi > 0 then add(c(DIM, "Quests from level: ") .. qlo .. c(DIM, "   quest levels up to ") .. qhi) end
  local m = e.mobs
  if m and m.fromSpawns and m.spawns > 0 then
    add(c(DIM, "Mobs: ") .. m.spawns .. c(DIM, " (") .. m.elites .. c(DIM, " elite)"))
  end
  if m and #m.bosses > 0 then
    local b = {}
    for i = 1, math.min(8, #m.bosses) do b[i] = m.bosses[i] end
    add(c(DIM, "Bosses and named elites: ") .. table.concat(b, ", ") .. (#m.bosses > 8 and " ..." or ""))
  end
  local ct, runs = DG:ClearTime(e)
  if ct then add(c(DIM, "Clear time: ") .. mins(ct) .. c(DIM, (runs and runs > 0) and ("  (your average of %d run%s)"):format(runs, runs == 1 and "" or "s") or "  (estimate)")) end
  local mx = DG:MobXP(e, lv)
  local qxp, todo, can = 0, 0, 0
  for _, id in ipairs(e.quests) do
    if not QS.done[id] then
      todo = todo + 1
      qxp = qxp + (QS.RewardXP(id, lv) or 0)
      if QS.log[id] or QS:Available(id) then can = can + 1 end
    end
  end
  if mx then add(c(DIM, "Mob XP per clear at your level: ") .. "~" .. math.floor(mx) .. c(DIM, " each (group of 5)")) end
  if qxp > 0 then add(c(DIM, "Quest XP left: ") .. math.floor(qxp) .. c(DIM, ("  (%d quest%s, %d you can get now)"):format(todo, todo == 1 and "" or "s", can))) end
  if ct and ct > 0 and ((mx or 0) + qxp) > 0 then
    add(c(DIM, "Average XP per hour (one run + quests): ") .. "~" .. math.floor(((mx or 0) + qxp) / ct * 3600))
  end
  if #e.quests > 0 then
    add(" ")
    add(c(GOLD, "Quests"))
    local sorted = {}
    for _, id in ipairs(e.quests) do sorted[#sorted + 1] = id end
    table.sort(sorted, function(a, b) return (QS:Info(a).level or 0) < (QS:Info(b).level or 0) end)
    for i, id in ipairs(sorted) do
      if i > 14 then add(c(DIM, ("  ... and %d more"):format(#sorted - 14))); break end
      local inf = QS:Info(id)
      local st = DG:QuestStatus(id, lv)
      add(("  [%d] %s  %s"):format(inf.level, inf.title, c(DIM, "- " .. st)))
    end
  else
    add(" ")
    add(c(DIM, "No quests for your character here."))
  end
  detail.text:SetText(table.concat(L, "\n"))
  local h = (detail.text.GetStringHeight and detail.text:GetStringHeight()) or (#L * 17)
  if type(h) ~= "number" or h < #L * 10 then h = #L * 17 end
  detail:SetHeight(math.min(860, 34 + 98 + h + 56))
  local active = Q.char.dmode == e.area
  detail.go:SetText(active and "Stop dungeon mode" or "Get all quests")
  detail.go:SetShown(active or todo > 0)
  detail.go.tip = active and "Back to your normal route" or
    "Dungeon mode: routes you to every quest of this dungeon (and the chains that unlock them), then into it"
  detail.go:SetScript("OnClick", function()
    if Q.char.dmode == e.area then
      P:DungeonMode(nil)
      Q:Print("dungeon mode off")
    else
      P:DungeonMode(e.area)
      Q:Print(("dungeon mode: getting every quest for %s"):format(e.name))
    end
    DG:ShowDungeon(e)
    if list and list:IsShown() then DG:Show() end
  end)
  detail.e = e
  if Q.Bosses then Q.Bosses.Front(detail) else detail:Show() end
  return L
end

-- ------------------------------------------------------------------ learn clear times
local run
local function where()
  if not GetInstanceInfo then return end
  local _, itype, _, _, _, _, _, mapID = GetInstanceInfo()
  if itype ~= "party" then return end
  if mapID and D.INSTANCE_AREA[mapID] then return D.INSTANCE_AREA[mapID] end
  local e = Q.Bosses and Q.Bosses:Current()           -- WoW Forever's dungeons: by name
  return e and e.area
end
local function check()
  local area = where()
  local now = GetTime and GetTime() or 0
  if area and not run then
    run = { area = area, start = now }
  elseif run and area ~= run.area then
    local dur = now - run.start
    if dur >= 300 and dur <= 4 * 3600 and QuesticusCollect and Q.db.collect ~= false then
      QuesticusCollect.dclear = QuesticusCollect.dclear or {}
      local t = QuesticusCollect.dclear[run.area] or {}
      t[#t + 1] = math.floor(dur)
      while #t > 10 do table.remove(t, 1) end
      QuesticusCollect.dclear[run.area] = t
    end
    run = area and { area = area, start = now } or nil
  end
end
Q:On("PLAYER_ENTERING_WORLD", check)
Q:On("ZONE_CHANGED_NEW_AREA", check)

Q:Command("dungeons", "every dungeon: levels, quests, XP, clear time - and dungeon mode (get all its quests)", function() DG:Show() end)
Q:Command("dungeonoff", "leave dungeon mode", function() if Q.char.dmode then P:DungeonMode(nil); Q:Print("dungeon mode off") end end)
