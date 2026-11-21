-- Questicus boss tracker: when you're in a dungeon (or the route's dungeon step is up), a bar of
-- boss portraits pops up. Click a boss for its stats, how the fight works and what it drops (with
-- drop chances); bosses get ticked off as you kill them. Right-click a portrait to tick / untick.
-- Sources: the game's Adventure Guide (bosses, portraits, abilities, loot), ForeverDB (levels, drop
-- chances, named elites) and bosses this account has fought (recorded, for WoW Forever's new
-- dungeons until the data has them). The author can add fight notes ("boss:<name>").
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local BT = {}
Q.Bosses = BT

local GOLD, DIM = T.HEX.gold, T.HEX.dim
local function c(hex, s) return Q.Color(hex, s) end
local QUALITY = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80" }

-- ------------------------------------------------------------------ Adventure Guide
local ej = {}
local function ejName(s) return (s or ""):lower():gsub("^the ", ""):gsub("[^%w]", "") end
local function ejInstance(dname)
  if not EJ_GetNumTiers then      -- the Adventure Guide loads on demand
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_EncounterJournal") end
  end
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return end
  local want = ejName(dname)
  local okT, nt = pcall(EJ_GetNumTiers)
  for tier = 1, (okT and nt or 0) do
    pcall(EJ_SelectTier, tier)
    for i = 1, 200 do
      local ok, id, name = pcall(EJ_GetInstanceByIndex, i, false)
      if not (ok and id) then break end
      local n = ejName(name)
      if n == want or n:find(want, 1, true) or want:find(n, 1, true) then return id end
    end
  end
end
local function strip(s)
  return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("%$%b{}", ""):gsub("%$%w+", "")
end
-- bosses of a dungeon from the Adventure Guide: { name, encounter, icon, display, abilities = {...}, loot = {...} }
local function ejBosses(dname)
  if ej[dname] ~= nil then return ej[dname] or nil end
  ej[dname] = false
  local inst = ejInstance(dname)
  if not (inst and EJ_GetEncounterInfoByIndex) then return end
  pcall(EJ_SelectInstance, inst)
  local out = {}
  for j = 1, 30 do
    local ok, name, desc, enc, root = pcall(EJ_GetEncounterInfoByIndex, j, inst)
    if not (ok and name and enc) then break end
    local b = { name = name, desc = strip(desc), encounter = enc, abilities = {}, loot = {} }
    if EJ_GetCreatureInfo then
      local ok2, _, _, _, display, icon = pcall(EJ_GetCreatureInfo, 1, enc)
      if ok2 then b.display, b.icon = display, icon end
    end
    -- abilities: the section tree, first two levels
    local GS = C_EncounterJournal and C_EncounterJournal.GetSectionInfo
    if GS and root then
      local function walk(id, depth)
        local n = 0
        while id and n < 20 and #b.abilities < 14 do
          n = n + 1
          local ok3, sec = pcall(GS, id)
          if not (ok3 and sec) then break end
          if sec.title and not sec.filteredByDifficulty then
            b.abilities[#b.abilities + 1] = { title = strip(sec.title), text = strip(sec.description), depth = depth }
          end
          if depth < 2 and sec.firstChildSectionID then walk(sec.firstChildSectionID, depth + 1) end
          id = sec.siblingSectionID
        end
      end
      walk(root, 1)
    end
    -- loot
    if EJ_SelectEncounter and EJ_GetNumLoot and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
      pcall(EJ_SelectEncounter, enc)
      local okN, nl = pcall(EJ_GetNumLoot)
      for k = 1, math.min(okN and nl or 0, 30) do
        local ok4, li = pcall(C_EncounterJournal.GetLootInfoByIndex, k)
        if ok4 and li and li.itemID then b.loot[#b.loot + 1] = li.itemID end
      end
    end
    out[#out + 1] = b
  end
  if #out > 0 then ej[dname] = out; return out end
end

-- ------------------------------------------------------------------ drops (ForeverDB)
local dropsOf
local function npcDrops(nid)
  if not dropsOf then
    dropsOf = {}
    for item, t in pairs(D.db.drop or {}) do
      for i = 1, #t - 1, 2 do
        local n = t[i]
        local l = dropsOf[n]
        if not l then l = {}; dropsOf[n] = l end
        l[#l + 1] = { item, (t[i + 1] or 0) / 10000 }
      end
    end
  end
  return dropsOf[nid] or {}
end
BT.NpcDrops = npcDrops

-- quests that need an item: as an objective (qx 10), or as a part you put together (qx 21)
local questItems
local function questsFor(item)
  if not questItems then
    questItems = {}
    for qid, x in pairs(D.db.qx or {}) do
      for _, it in ipairs(x[10] or {}) do questItems[it] = questItems[it] or {}; table.insert(questItems[it], { qid, "obj" }) end
      for _, it in ipairs(x[21] or {}) do questItems[it] = questItems[it] or {}; table.insert(questItems[it], { qid, "part" }) end
    end
  end
  return questItems[item]
end
local function iname(id) return Q.GetItemInfo(id) or D:Name("i" .. id) end
-- "[A] + [B] -> [C]" for a quest whose objective item is made from parts (qx 21), or nil
function BT.CombineText(qid)
  local x = D:QuestExtra(qid)
  if not (x and x[21] and #x[21] > 0 and x[10] and #x[10] > 0) then return end
  local parts = {}
  for _, it in ipairs(x[21]) do parts[#parts + 1] = c(T.HEX.white, "[" .. iname(it) .. "]") end
  local made = {}
  for _, it in ipairs(x[10]) do made[#made + 1] = c(T.HEX.gold, "[" .. iname(it) .. "]") end
  return table.concat(parts, " + ") .. "  ->  " .. table.concat(made, ", ")
end
local function dropSources(item)
  local t = D.db.drop and D.db.drop[item]
  return t and math.floor(#t / 2) or 0
end

-- ------------------------------------------------------------------ the boss list
local function recorded(dname)
  local r = QuesticusCollect and QuesticusCollect.dboss and QuesticusCollect.dboss[dname]
  return r or {}
end
function BT:List(e)
  local out, byName = {}, {}
  local names = Q.Dungeons and Q.Dungeons.BossNames and Q.Dungeons.BossNames(e)
  local function add(b)
    local k = b.name:lower()
    local had = byName[k]
    if had then
      for key, v in pairs(b) do if had[key] == nil then had[key] = v end end
      return
    end
    byName[k] = b
    out[#out + 1] = b
  end
  -- the Adventure Guide can hold a dungeon's modern version (other bosses): use it only when its
  -- bosses are the ones ForeverDB knows in there, else just borrow its details for matching names
  local guide = ejBosses(e.name) or {}
  local dbList = e.mobs and e.mobs.bossList or {}
  local known = {}
  for _, b in ipairs(dbList) do known[b.name:lower()] = b end
  local overlap = 0
  for _, b in ipairs(guide) do if known[b.name:lower()] then overlap = overlap + 1 end end
  if #guide > 0 and (#dbList == 0 or overlap > 0) then
    for _, b in ipairs(guide) do
      local k = known[b.name:lower()]
      local ids = D:NPCByName(b.name)
      b.nid = (k and k.nid) or (ids and ids[1])
      b.lvl = k and k.lvl
      add(b)
    end
  end
  -- ForeverDB: boss-rank and named elites
  if #out == 0 or overlap > 0 then
    for _, b in ipairs(dbList) do
      if #out == 0 or not byName[b.name:lower()] then
        if overlap == 0 then add({ name = b.name, nid = b.nid, lvl = b.lvl }) end
      end
    end
  end
  -- bosses fought here before (recorded): WoW Forever's own dungeons
  local rec = recorded(e.name)
  local extra = {}
  for nid, r in pairs(rec) do extra[#extra + 1] = { name = r.name, nid = tonumber(nid), order = r.order or 99, hp = r.hp } end
  table.sort(extra, function(a, b) return a.order < b.order end)
  for _, b in ipairs(extra) do add(b) end
  -- the game's own boss list for this dungeon (Questicus Maps' data): only those, in its order - quest
  -- NPCs and named elites that aren't bosses stay out
  if names then
    local real = {}
    for _, n in ipairs(names) do
      local b = byName[n:lower()]
      if not b then
        local ids = D:NPCByName(n)
        b = { name = n, nid = ids and ids[1] }
        local np = b.nid and D:NPC(b.nid)
        b.lvl = np and (np[4] or np[3])
      end
      real[#real + 1] = b
    end
    return real
  end
  -- no list: leave out friendly NPCs (quest givers, prisoners)
  local kept = {}
  for _, b in ipairs(out) do if not (b.nid and D:Faction(b.nid)) then kept[#kept + 1] = b end end
  return kept
end

-- ------------------------------------------------------------------ kills this run
local function run(area)
  local r = Q.char.bossRun
  local now = time and time() or 0
  if not r or r.area ~= area or (now - (r.t or 0)) > 3 * 3600 then
    r = { area = area, killed = {}, t = now }
    Q.char.bossRun = r
  end
  return r
end
-- kills live in the current run (Runs.lua); a run is started for the dungeon when needed
local function runFor(area)
  local R = Q.Runs
  local cur = R and R:Current()
  if cur and cur.area == area and not cur.ended then return cur end
end
function BT:Killed(area, name)
  if Q.Runs then return runFor(area) ~= nil and Q.Runs:Killed(name) end
  return run(area).killed[name:lower()] == true
end
function BT:KillTime(area, name)
  local cur = runFor(area)
  local k = cur and cur.kills[name:lower()]
  return k and k.t
end
function BT:SetKilled(area, name, v)
  if Q.Runs then
    local shown = BT.shownE
    if not runFor(area) and shown and shown.area == area then Q.Runs:Begin(shown) end
    if v then Q.Runs:Kill(name, "hand") else Q.Runs:Unkill(name) end
  else
    local r = run(area)
    r.killed[name:lower()] = v or nil
    r.t = time and time() or 0
  end
  BT:Refresh()
end

-- ------------------------------------------------------------------ windows
local bar, card
local slots = {}
BT.slots = slots
-- a creature's face as a still picture: its model, zoomed on the face, frozen on the first frame of
-- standing (not moving about)
function BT.Still(m, nid)
  if not (m and nid and m.SetCreature) then return end
  pcall(m.SetCreature, m, nid)
  if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 1) end
  if m.SetAnimation then pcall(m.SetAnimation, m, 0) end
  if m.FreezeAnimation then pcall(m.FreezeAnimation, m, 0, 0, 0) end
  if m.SetPaused then pcall(m.SetPaused, m, true) end
end

local SLOT_W, SLOT_H, PIC = 64, 86, 50   -- a boss: its round picture, its name under it (two lines)
local function slot(i)
  local s = slots[i]
  if s then return s end
  s = CreateFrame("Button", nil, bar)
  s:SetSize(SLOT_W, SLOT_H)
  if s.RegisterForClicks then s:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  s.bg = T.RFill(s, { T.c.bg[1] * 0.6, T.c.bg[2] * 0.6, T.c.bg[3] * 0.6, 1 }, 6)
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetPoint("TOP", 0, -5)
  s.icon:SetSize(PIC, PIC)
  -- round portraits, all the same shape whatever they come from
  if s.CreateMaskTexture then
    local mk = s:CreateMaskTexture()
    mk:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mk:SetAllPoints(s.icon)
    if s.icon.AddMaskTexture then s.icon:AddMaskTexture(mk) end
  end
  s.ring = s:CreateTexture(nil, "OVERLAY")
  s.ring:SetTexture(Q.MEDIA .. "ring_thin")
  s.ring:SetPoint("CENTER", s.icon, "CENTER")
  s.ring:SetSize(PIC + 4, PIC + 4)
  s.ring:SetVertexColor(T.c.line[1], T.c.line[2], T.c.line[3], 0.9)
  s.model = CreateFrame("PlayerModel", nil, s)
  s.model:SetPoint("TOP", 0, -5)
  s.model:SetSize(PIC, PIC)
  -- a model set while it wasn't drawn yet stays empty: set it again when it shows
  s.model:SetScript("OnShow", function(m)
    local nid = BT.modelNid and BT.modelNid[m]
    if nid then BT.Still(m, nid) end
  end)
  -- (the model loads a moment later: frozen again once it's there)
  pcall(s.model.SetScript, s.model, "OnModelLoaded", function(m)
    if m.FreezeAnimation then pcall(m.FreezeAnimation, m, 0, 0, 0) end
    if m.SetPaused then pcall(m.SetPaused, m, true) end
  end)
  -- the tick sits on its own layer above the portrait (a 3D portrait would cover a plain texture)
  s.top = CreateFrame("Frame", nil, s)
  s.top:SetAllPoints(s)
  s.top:SetFrameLevel(s.model:GetFrameLevel() + 5)
  s.check = s.top:CreateTexture(nil, "OVERLAY")
  s.check:SetSize(30, 30)
  s.check:SetPoint("CENTER", s.icon, "CENTER", 0, 0)
  s.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  -- the name under the picture, never over it: up to two lines, shortened past that
  s.name = T.Text(s, 9, T.c.text)
  s.name:SetPoint("TOP", s.icon, "BOTTOM", 0, -4)
  s.name:SetWidth(SLOT_W - 4)
  s.name:SetHeight(24)
  s.name:SetJustifyH("CENTER")
  s.name:SetJustifyV("TOP")
  if s.name.SetWordWrap then s.name:SetWordWrap(true) end
  if s.name.SetMaxLines then s.name:SetMaxLines(2) end
  s:SetScript("OnClick", function(self, btn)
    if not self.b then return end
    if btn == "RightButton" then BT:SetKilled(bar.e.area, self.b.name, not BT:Killed(bar.e.area, self.b.name))
    else BT:ShowBoss(bar.e, self.b) end
  end)
  s:SetScript("OnEnter", function(self)
    if not self.b then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(self.b.name, 1, 1, 1)
    local area = bar and bar.e and bar.e.area
    if area and BT:Killed(area, self.b.name) then
      local kt = BT:KillTime(area, self.b.name)
      GameTooltip:AddLine("Killed" .. (kt and Q.Runs and (" at " .. Q.Runs.Clock(kt)) or ""), 0.5, 0.86, 0.35)
      local got = Q.Runs and Q.Runs.LootOf and Q.Runs:LootOf(self.b.name) or {}
      if #got == 0 then
        GameTooltip:AddLine("No loot recorded from it", 0.6, 0.6, 0.6)
      else
        for _, l in ipairs(got) do
          GameTooltip:AddDoubleLine((l.link or ("item " .. tostring(l.id))) .. ((l.n or 1) > 1 and (" x" .. l.n) or ""),
            tostring(l.who or "?"), 1, 1, 1, 0.8, 0.8, 0.8)
        end
      end
    end
    GameTooltip:AddLine("Click: stats, fight and loot - right-click: tick off / undo", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  s:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slots[i] = s
  return s
end

-- The picture: the creature's own portrait (from its look, like the target frame's), else the
-- Adventure Guide's picture - unless it's the guide's stand-in skull, which bosses without a picture
-- of their own all share - else its 3D model, else a skull.
local DEAD_SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local function portrait(s, b, shared, dead)
  s.model:Hide()
  s.icon:Show()
  s.icon:SetTexCoord(0, 1, 0, 1)
  if dead then                                  -- killed this run: a skull (the tick goes over it)
    s.icon:SetTexture(DEAD_SKULL)
    return
  end
  local ownIcon = b.icon and not (shared and shared[b.icon])
  if b.nid and s.model.SetCreature then
    s.icon:Hide()
    BT.modelNid = BT.modelNid or {}
    BT.modelNid[s.model] = b.nid
    s.model:Show()
    BT.Still(s.model, b.nid)
  elseif ownIcon then
    s.icon:SetTexture(b.icon)
    s.icon:SetTexCoord(0.2, 0.8, 0, 1)        -- Adventure Guide portraits are wide: the middle
  elseif b.display and b.display ~= 0 and SetPortraitTextureFromCreatureDisplayID then
    pcall(SetPortraitTextureFromCreatureDisplayID, s.icon, b.display)
  else
    s.icon:SetTexture(DEAD_SKULL)
  end
end

function BT:Show(e)
  if not e then return end
  if not bar then
    Q.db.bossWin = Q.db.bossWin or {}
    bar = T.Window("QuesticusBosses", 300, 120, "Bosses", Q.db.bossWin)
    bar:SetFrameStrata("MEDIUM")
    bar.count = T.Text(bar.bar, 11, T.c.dim)
    bar.count:SetPoint("RIGHT", bar.close, "LEFT", -6, 0)
    bar.reset = T.Button(bar, "New run", 70, 18)
    bar.reset:SetPoint("BOTTOMRIGHT", -8, 6)
    bar.reset.tip = "Start a new run (the current one goes into the history)"
    bar.reset:SetScript("OnClick", function()
      Q.char.bossRun = nil
      if Q.Runs then Q.Runs:NewRun() end
      BT:Refresh()
    end)
    -- history of runs (averages, loot, times)
    bar.hist = T.Button(bar, "History", 70, 18)
    bar.hist:SetPoint("RIGHT", bar.reset, "LEFT", -6, 0)
    bar.hist.tip = "Your runs: completion time, gold, XP, loot (and who got it) and the averages"
    bar.hist:SetScript("OnClick", function() if Q.Runs then Q.Runs:ShowHistory(bar.e and bar.e.area) end end)
    -- this run: time, gold and XP
    bar.stats = T.Text(bar, 11, T.c.text)
    bar.stats:SetPoint("BOTTOMLEFT", 10, 9)
    bar.stats:SetPoint("RIGHT", bar.hist, "LEFT", -6, 0)
    bar.stats:SetJustifyH("LEFT")
    bar.stats:SetWordWrap(false)
    local acc = 0
    bar:HookScript("OnUpdate", function(_, el)
      acc = acc + (el or 0)
      if acc < 1 then return end
      acc = 0
      BT:Stats()
    end)
    bar.none = T.Text(bar, 11, T.c.dim)
    bar.none:SetPoint("TOPLEFT", 12, -34)
    bar.none:SetPoint("RIGHT", -12, 0)
    -- low profile: a plain text list instead of portraits
    bar.mode = CreateFrame("Button", nil, bar.bar)
    bar.mode:SetSize(18, 18)
    bar.mode:SetPoint("RIGHT", bar.count, "LEFT", -6, 0)
    bar.mode.t = bar.mode:CreateTexture(nil, "OVERLAY")
    bar.mode.t:SetAllPoints()
    bar.mode.t:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    bar.mode:SetScript("OnClick", function() Q.db.bossLow = not Q.db.bossLow; BT:Refresh() end)
    bar.mode:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(Q.db.bossLow and "Show portraits" or "Low profile: just a list of names", 1, 1, 1)
      GameTooltip:Show()
    end)
    bar.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- the title stops before the count and the buttons (cut with ... when the window is narrow)
    bar.title:SetPoint("RIGHT", bar.mode, "LEFT", -6, 0)
    bar.title:SetJustifyH("LEFT")
    bar.title:SetWordWrap(false)
  end
  bar.e = e
  BT.shownE = e
  bar.list = BT:List(e)
  BT.Front(bar)
  BT:Refresh()
  -- portraits (3D models, the Adventure Guide's pictures) aren't ready on the frame they're first set:
  -- draw again once the window is on screen
  local function again() if bar.e == e and bar:IsShown() then bar.list = BT:List(e); BT:Refresh() end end
  Q.After(0.05, again)
  Q.After(0.6, again)
  return bar.list
end

-- low profile rows: the names, ticked off as you kill them; click one for its loot
local lrows = {}
BT.lrows = lrows
BT.lrowBoss = {}
local function lrow(i)
  local r = lrows[i]
  if r then return r end
  r = CreateFrame("Button", nil, bar)
  r:SetHeight(18)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r.box = r:CreateTexture(nil, "ARTWORK")
  r.box:SetSize(14, 14)
  r.box:SetPoint("LEFT", 2, 0)
  r.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
  r.tick = r:CreateTexture(nil, "OVERLAY")
  r.tick:SetSize(16, 16)
  r.tick:SetPoint("CENTER", r.box, "CENTER", 1, 0)
  r.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  r.time = T.Text(r, 10, T.c.dim)
  r.time:SetPoint("RIGHT", -2, 0)
  r.name = T.Text(r, 12, T.c.text)
  r.name:SetPoint("LEFT", r.box, "RIGHT", 6, 0)
  r.name:SetPoint("RIGHT", -40, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.06) end
  r:SetScript("OnClick", function(self, btn)
    local b = BT.lrowBoss[self]
    if not b then return end
    if btn == "RightButton" then BT:SetKilled(bar.e.area, b.name, not BT:Killed(bar.e.area, b.name))
    else BT:ShowBoss(bar.e, b) end
  end)
  r:SetScript("OnEnter", function(self)
    local b = BT.lrowBoss[self]
    if not b then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.name, 1, 1, 1)
    GameTooltip:AddLine("Click: loot, stats and fight - right-click: tick off / undo", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  lrows[i] = r
  return r
end

-- the run's line at the bottom: time (stops at the last boss), gold and XP made inside
function BT:Stats()
  if not (bar and bar.stats) then return end
  local cur = Q.Runs and Q.Runs:Current()
  if cur and bar.e and cur.area == bar.e.area and not cur.ended then
    bar.stats:SetText((cur.done and c(T.HEX.good, "Cleared ") or "") .. Q.Runs:Summary(cur))
  else
    local av = Q.Runs and bar.e and Q.Runs:Averages(bar.e.area)
    bar.stats:SetText(av and c(DIM, ("avg %s  %s  %d XP"):format(av.time and Q.Runs.Clock(av.time) or "-", Q.Runs.Money(av.gold), math.floor(av.xp))) or "")
  end
end
Q:On("QC_RUN_CHANGED", function() if bar and bar:IsShown() then BT:Refresh() end end)

function BT:Refresh()
  if not (bar and bar:IsShown() and bar.e) then return end
  BT:Stats()
  local e, list = bar.e, bar.list or {}
  bar.title:SetText(Q.Color(T.HEX.accent, "Bosses") .. Q.Color(DIM, " - " .. e.name))
  if Q.db.bossLow then
    for _, s in ipairs(slots) do s:Hide() end
    local done, nextShown = 0, false
    for i, b in ipairs(list) do
      local r = lrow(i)
      BT.lrowBoss[r] = b
      local dead = BT:Killed(e.area, b.name)
      if dead then done = done + 1 end
      r.tick:SetShown(dead)
      local kt = dead and BT:KillTime(e.area, b.name)
      r.time:SetText(kt and Q.Runs.Clock(kt) or "")
      if dead then r.name:SetText(c(DIM, b.name))
      elseif not nextShown then nextShown = true; r.name:SetText(c(GOLD, b.name))   -- the next one to kill
      else r.name:SetText(b.name) end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 19)
      r:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
      r:Show()
    end
    for i = #list + 1, #lrows do lrows[i]:Hide() end
    bar.count:SetText(#list > 0 and (done .. "/" .. #list) or "")
    bar.none:SetText(#list == 0 and "No boss data for this dungeon yet." or "")
    local w = 200
    for _, r in ipairs(lrows) do
      if r:IsShown() and r.name.GetStringWidth then w = math.max(w, (r.name:GetStringWidth() or 0) + 84) end
    end
    bar:SetWidth(math.min(360, math.max(290, w)))
    bar:SetHeight(30 + math.max(1, #list) * 19 + 34)
    return
  end
  for _, r in ipairs(lrows) do r:Hide() end
  local done, per = 0, 6
  -- an Adventure Guide picture two bosses share is its stand-in, not theirs
  local seen, shared = {}, {}
  for _, b in ipairs(list) do
    if b.icon then
      if seen[b.icon] then shared[b.icon] = true end
      seen[b.icon] = true
    end
  end
  for i, b in ipairs(list) do
    local s = slot(i)
    s.b = b
    local dead = BT:Killed(e.area, b.name)
    if dead then done = done + 1 end
    portrait(s, b, shared, dead)
    s.icon:SetDesaturated(false)
    s.model:SetAlpha(1)
    s.check:SetShown(dead)
    s.name:SetText(dead and c(DIM, b.name) or b.name)
    local col, row = (i - 1) % per, math.floor((i - 1) / per)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", 8 + col * (SLOT_W + 2), -30 - row * (SLOT_H + 2))
    s:Show()
  end
  for i = #list + 1, #slots do slots[i]:Hide() end
  bar.count:SetText(#list > 0 and (done .. "/" .. #list) or "")
  bar.none:SetText(#list == 0 and "No boss data for this dungeon yet - bosses you fight here are added as you meet them." or "")
  local rows = math.max(1, math.ceil(#list / per))
  bar:SetWidth(math.max(300, 16 + math.min(#list, per) * (SLOT_W + 2)))
  bar:SetHeight(30 + rows * (SLOT_H + 2) + 30)
end

-- one boss: header (portrait, name, level), stats and fight, then its loot as item rows
local function itemLink(id, q)
  local _, link = Q.GetItemInfo(id)
  if type(link) == "string" and link:find("|Hitem:") then return link end
  local name = Q.GetItemInfo(id) or D:Name("i" .. id)
  return ("|cff%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(QUALITY[q] or "ffffff", id, name)
end
local function itemSub(id)
  if not (C_Item and C_Item.GetItemInfoInstant) then return "" end
  local ok, _, itype, sub, loc = pcall(C_Item.GetItemInfoInstant, id)
  if not ok then return "" end
  local slot = loc and loc ~= "" and _G[loc] or nil
  if slot and sub and sub ~= "" and itype ~= sub and not (sub == "Miscellaneous" or sub == "Junk") then
    if slot == sub then return slot end
    return slot .. ", " .. sub
  end
  return slot or sub or itype or ""
end
local lootRows = {}
BT.tabs = {}
local LOOT_ROWS = 4
-- a window always comes up on top of everything else (other addons' windows included)
function BT.Front(f)
  if not f then return end
  f:SetFrameStrata("DIALOG")
  if f.SetToplevel then f:SetToplevel(true) end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:Show()
  if f.Raise then f:Raise() end
end
BT.lootRows = lootRows
local function lootRow(i)
  local r = lootRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, card)
  r:SetHeight(40)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r.bg = T.RFill(r, { T.c.bg[1] * 0.55, T.c.bg[2] * 0.55, T.c.bg[3] * 0.55, 1 }, 4)
  T.Border(r, T.c.line, 4)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(32, 32)
  r.icon:SetPoint("LEFT", 5, 0)
  r.name = T.Text(r, 12, T.c.text)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
  r.name:SetPoint("RIGHT", -52, 0)
  r.name:SetWordWrap(false)
  r.sub = T.Text(r, 10, T.c.dim)
  r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 2)
  r.pct = T.Text(r, 12, T.c.text)
  r.pct:SetPoint("RIGHT", -8, 0)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.05) end
  -- hovering: the game's full item tooltip, the same as clicking the item in game
  r:SetScript("OnEnter", function(self)
    if not self.id then return end
    BT.hoverRow = self
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
    if not ok then pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() BT.hoverRow = nil; GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if not self.link then return end
    -- the game's own handling: Shift = put the link in chat, Ctrl = dressing room
    if HandleModifiedItemClick and HandleModifiedItemClick(self.link) then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
      if ChatEdit_InsertLink then ChatEdit_InsertLink(self.link)
      elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(self.link) end
      return
    end
    -- plain click: the game's item window, like clicking a link in chat
    local href = self.link:match("|H(.-)|h")
    if SetItemRef and href then pcall(SetItemRef, href, self.link, "LeftButton") end
  end)
  lootRows[i] = r
  return r
end

function BT:ShowBoss(e, b)
  if not card then
    card = T.Window("QuesticusBoss", 400, 300, "", nil)
    card:SetFrameStrata("HIGH")
    -- header: round portrait with a level badge, the boss's name
    card.pic = CreateFrame("Frame", nil, card)
    card.pic:SetSize(64, 64)
    card.pic:SetPoint("TOPLEFT", 14, -30)
    card.ring = card.pic:CreateTexture(nil, "BACKGROUND")
    card.ring:SetPoint("TOPLEFT", -3, 3); card.ring:SetPoint("BOTTOMRIGHT", 3, -3)
    card.ring:SetTexture(Q.MEDIA .. "disc")
    card.ring:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 1)
    card.face = card.pic:CreateTexture(nil, "ARTWORK")
    card.face:SetAllPoints()
    if card.face.SetMask then pcall(card.face.SetMask, card.face, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    card.model = CreateFrame("PlayerModel", nil, card.pic)
    card.model:SetAllPoints()
    card.badge = CreateFrame("Frame", nil, card.pic)
    card.badge:SetSize(26, 26)
    card.badge:SetPoint("BOTTOMLEFT", -6, -6)
    card.badge:SetFrameLevel(card.pic:GetFrameLevel() + 5)
    local bdisc = card.badge:CreateTexture(nil, "ARTWORK")
    bdisc:SetAllPoints(); bdisc:SetTexture(Q.MEDIA .. "disc"); bdisc:SetVertexColor(0.08, 0.06, 0.04, 1)
    local bring = card.badge:CreateTexture(nil, "OVERLAY")
    bring:SetAllPoints(); bring:SetTexture(Q.MEDIA .. "ring"); bring:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 1)
    card.lvl = T.Text(card.badge, 11, T.c.text)
    card.lvl:SetPoint("CENTER", 0, 0)
    card.name = T.Text(card, 16, T.c.text)
    card.name:SetPoint("LEFT", card.pic, "RIGHT", 14, 6)
    card.name:SetPoint("RIGHT", -14, 0)
    card.rank = T.Text(card, 11, T.c.dim)
    card.rank:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.text = T.Text(card, 11, T.c.text)
    card.text:SetPoint("TOPLEFT", 14, -104)
    card.text:SetPoint("RIGHT", -14, 0)
    card.text:SetJustifyH("LEFT")
    card.text:SetSpacing(2)
    card.lootHead = T.Text(card, 12, T.c.gold)
    card.sb = CreateFrame("Frame", nil, card)
    card.sb:SetWidth(6)
    T.RFill(card.sb, { T.c.bg[1] * 0.5, T.c.bg[2] * 0.5, T.c.bg[3] * 0.5, 1 }, 3)
    card.thumb = card.sb:CreateTexture(nil, "OVERLAY")
    card.thumb:SetWidth(6)
    card.thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
    card.thumb:SetVertexColor(T.c.gold[1], T.c.gold[2], T.c.gold[3], 0.8)
    card.pos = T.Text(card, 10, T.c.dim)
    if card.EnableMouseWheel then card:EnableMouseWheel(true) end
    card:SetScript("OnMouseWheel", function(_, d) BT:ScrollLoot(d) end)
    card.edit = T.Button(card, "Edit fight notes", 120, 20)
    card.edit:SetPoint("BOTTOMRIGHT", -12, 10)
    card.kill = T.Button(card, "Killed", 80, 20)
    card.kill:SetPoint("RIGHT", card.edit, "LEFT", -8, 0)
  end
  if bar and bar:IsShown() and card.ClearAllPoints then
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  end
  card.title:SetText(Q.Color(DIM, e.name))
  -- header
  local n = b.nid and D:NPC(b.nid)
  local lo, hi = n and n[3], n and n[4]
  local rank = n and n[5]
  local ranks = { [1] = "Elite", [2] = "Rare elite", [3] = "Boss", [4] = "Rare" }
  local lvl = hi or lo or b.lvl
  card.name:SetText(b.name)
  card.rank:SetText((rank and ranks[rank] or "") .. ((n and n[2]) and ("  <" .. n[2] .. ">") or ""))
  card.lvl:SetText(lvl and tostring(lvl) or "?")
  card.model:Hide(); card.face:Show()

  -- (the same still picture as in the tracker: its model first)
  if b.nid and card.model.SetCreature then
    card.face:Hide(); card.model:Show()
    BT.Still(card.model, b.nid)
  elseif b.display and SetPortraitTextureFromCreatureDisplayID then
    pcall(SetPortraitTextureFromCreatureDisplayID, card.face, b.display)
  elseif b.icon then
    card.face:SetTexture(b.icon)          -- (masked round: no tex coords allowed)
  else
    card.face:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
  end
  -- stats and the fight
  local L = {}
  local function add(s) L[#L + 1] = s end
  if lo and hi and lo ~= hi then add(c(DIM, "Level ") .. lo .. "-" .. hi) end
  local hp = b.hp or (QuesticusCollect and QuesticusCollect.bhp and b.nid and QuesticusCollect.bhp[b.nid])
  if hp then add(c(DIM, "Health: ") .. hp) end
  if b.desc and b.desc ~= "" then add(c(DIM, b.desc:sub(1, 240))) end
  if #L > 0 then add(" ") end
  add(c(GOLD, "The fight"))
  local note = Q.Author and Q.Author.BossNote and Q.Author:BossNote(b.name)
  if note then add(c(T.HEX.white, note)) end
  for i, a in ipairs(b.abilities or {}) do
    if i > 10 then break end
    local pad = a.depth and a.depth > 1 and "    - " or "- "
    add(pad .. c(T.HEX.white, a.title) .. ((a.text and a.text ~= "") and c(DIM, ": " .. a.text:sub(1, 160)) or ""))
  end
  if not note and #(b.abilities or {}) == 0 then add(c(DIM, "No fight notes yet.")) end
  card.text:SetText(table.concat(L, "\n"))
  local h = (card.text.GetStringHeight and card.text:GetStringHeight()) or 0
  if type(h) ~= "number" or h < #L * 9 then h = #L * 15 end
  -- loot: blue (rare) and better only, as item rows
  local items, seen = {}, {}
  local function quality(id)
    local rec = D:Item(id)
    local q = rec and rec[2]
    if not q and C_Item and C_Item.GetItemQualityByID then q = C_Item.GetItemQualityByID(id) end
    return q
  end
  -- sorted into: the boss's own loot (blue+), quest items, recipes, world drops (blue+ that drop anywhere)
  local function sort(id, chance)
    if seen[id] then return end
    local rec = D:Item(id)
    local q, class = quality(id), rec and rec[5]
    local qs = questsFor(id)
    local cat
    if class == 9 then cat = "recipe"
    elseif qs or class == 12 then cat = "quest"
    elseif q and q >= 3 then
      cat = (chance == nil or dropSources(id) <= 4 or chance >= 0.03) and "boss" or "world"
    end
    if cat then
      seen[id] = true
      local sub
      if cat == "quest" and qs then
        local qi = QS:Info(qs[1][1])
        local title = (qi and qi.title) or (D:Quest(qs[1][1]) or {})[1] or "a quest"
        if qs[1][2] == "part" then
          local x = D:QuestExtra(qs[1][1]) or {}
          local other = {}
          for _, it in ipairs(x[21] or {}) do if it ~= id then other[#other + 1] = "[" .. iname(it) .. "]" end end
          sub = "Put together" .. (#other > 0 and (" with " .. table.concat(other, " + ")) or "") .. " for " .. title
        else
          sub = "For " .. title
        end
      end
      items[#items + 1] = { id = id, chance = chance, q = q or (cat == "boss" and 3 or 1), cat = cat, sub = sub }
    end
  end
  for _, d in ipairs(b.nid and npcDrops(b.nid) or {}) do sort(d[1], d[2]) end
  for _, id in ipairs(b.loot or {}) do sort(id, nil) end
  table.sort(items, function(x, y)
    if (x.q or 0) ~= (y.q or 0) then return (x.q or 0) > (y.q or 0) end
    return (x.chance or -1) > (y.chance or -1)
  end)
  local y = 104 + h + 10
  card.lootHead:ClearAllPoints()
  card.lootHead:SetPoint("TOPLEFT", 14, -y)
  card.lootHead:SetText(#items > 0 and "Loot" or "Loot: nothing blue or better known yet")
  y = y + 20
  if card.b ~= b then card.lootOff = 0; BT.lootCat = nil end
  -- category tabs
  local cats = { { "boss", "Boss loot" }, { "quest", "Quest items" }, { "recipe", "Recipes" }, { "world", "World drops" } }
  local count = {}
  for _, it in ipairs(items) do count[it.cat] = (count[it.cat] or 0) + 1 end
  if not BT.lootCat or not count[BT.lootCat] then
    BT.lootCat = nil
    for _, ct in ipairs(cats) do if count[ct[1]] and not BT.lootCat then BT.lootCat = ct[1] end end
  end
  local tabs = BT.tabs
  local x = 54
  for k, ct in ipairs(cats) do
    local tb = tabs[k]
    if not tb then
      tb = T.Button(card, "", 84, 18)
      tabs[k] = tb
    end
    local n = count[ct[1]] or 0
    tb:SetText((BT.lootCat == ct[1] and "|cffffffff" or "") .. ct[2] .. " " .. n .. (BT.lootCat == ct[1] and "|r" or ""))
    tb:SetWidth(ct[2]:len() * 6 + 26)
    tb:ClearAllPoints()
    tb:SetPoint("TOPLEFT", x, -(y - 20))
    x = x + ct[2]:len() * 6 + 30
    tb:SetShown(n > 0)
    if n == 0 then x = x - (ct[2]:len() * 6 + 30) end
    tb:SetScript("OnClick", function() BT.lootCat = ct[1]; card.lootOff = 0; BT:ShowBoss(card.e, card.b) end)
  end
  local shownItems = {}
  for _, it in ipairs(items) do if it.cat == BT.lootCat then shownItems[#shownItems + 1] = it end end
  y = y + 4
  card.lootHead:SetText(#items > 0 and "Loot" or "Loot: nothing known yet")
  items = shownItems
  card.items, card.lootY = items, y
  BT:DrawLoot()
  y = y + math.min(#items, LOOT_ROWS) * 44 + (#items > LOOT_ROWS and 16 or 0)
  card:SetHeight(math.min(820, y + 40))
  local author = Q.Author and Q.Author:IsAuthor()
  card.edit:SetShown(author == true)
  card.edit:SetScript("OnClick", function() Q.Author:Edit("boss:" .. b.name:lower(), b.name .. " - fight notes") end)
  local dead = BT:Killed(e.area, b.name)
  card.kill:SetText(dead and "Not killed" or "Killed")
  card.kill:SetScript("OnClick", function() BT:SetKilled(e.area, b.name, not BT:Killed(e.area, b.name)); BT:ShowBoss(e, b) end)
  card.b, card.e = b, e
  BT.Front(card)
  return L, items
end

-- the loot list: 4 rows at a time, the mouse wheel scrolls
function BT:DrawLoot()
  local items, off, y = card.items or {}, card.lootOff or 0, card.lootY or 0
  for k = 1, LOOT_ROWS do
    local it = items[off + k]
    local r = lootRow(k)
    if not it then r:Hide() else
    r.link = itemLink(it.id, it.q)
    r.id = it.id
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or select(10, Q.GetItemInfo(it.id)) or 134400
    r.icon:SetTexture(icon)
    local name = Q.GetItemInfo(it.id) or D:Name("i" .. it.id)
    r.name:SetText(c(QUALITY[it.q] or "ffffff", name))
    r.sub:SetText(it.sub or itemSub(it.id))
    r.pct:SetText(it.chance and it.chance > 0 and (it.chance >= 0.1 and ("%d%%"):format(math.floor(it.chance * 100 + 0.5))
      or ("%.1f%%"):format(it.chance * 100)) or c(DIM, "?"))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 12, -(y + (k - 1) * 44))
    r:SetPoint("RIGHT", -24, 0)
    r:Show()
    end
  end
  for i = LOOT_ROWS + 1, #lootRows do lootRows[i]:Hide() end
  -- scroll bar on the right + "5-8 of 11"
  local more = #items > LOOT_ROWS
  card.sb:SetShown(more)
  card.pos:SetShown(more)
  if more then
    local h = LOOT_ROWS * 44 - 4
    card.sb:ClearAllPoints()
    card.sb:SetPoint("TOPRIGHT", -10, -y)
    card.sb:SetHeight(h)
    local frac, size = off / (#items - LOOT_ROWS), LOOT_ROWS / #items
    card.thumb:SetHeight(math.max(14, h * size))
    card.thumb:ClearAllPoints()
    card.thumb:SetPoint("TOP", card.sb, "TOP", 0, -(h - math.max(14, h * size)) * frac)
    card.pos:ClearAllPoints()
    card.pos:SetPoint("TOPRIGHT", -12, -(y + LOOT_ROWS * 44))
    card.pos:SetText(("%d-%d of %d - scroll for more"):format(off + 1, math.min(#items, off + LOOT_ROWS), #items))
  end
end
function BT:ScrollLoot(delta)
  if not (card and card.items) then return end
  local max = math.max(0, #card.items - LOOT_ROWS)
  card.lootOff = math.max(0, math.min(max, (card.lootOff or 0) - delta))
  BT:DrawLoot()
end

-- item details arrive from the server a moment later: refresh names / icons / an open tooltip
Q:On("GET_ITEM_INFO_RECEIVED", function(id)
  if not (card and card:IsShown() and card.items) then return end
  for _, it in ipairs(card.items) do
    if it.id == id then
      Q.Throttle("bosscard", 0.2, function()
        if card:IsShown() and card.b and card.e then BT:ShowBoss(card.e, card.b) end
        local r = BT.hoverRow
        if r and r:IsShown() and r:IsMouseOver() and r:GetScript("OnEnter") then r:GetScript("OnEnter")(r) end
      end)
      return
    end
  end
end)

-- ------------------------------------------------------------------ where am I
local function dungeonByName(name)
  if not (name and Q.Dungeons) then return end
  local want = ejName(name)
  for _, e in ipairs(Q.Dungeons:List()) do
    local n = ejName(e.name)
    if n == want or n:find(want, 1, true) or want:find(n, 1, true) then return e end
  end
end
BT.DungeonByName = dungeonByName
function BT:Current()
  if not GetInstanceInfo then return end
  local name, itype, _, _, _, _, _, mapID = GetInstanceInfo()
  if itype ~= "party" then return end
  local area = mapID and D.INSTANCE_AREA[mapID]
  if area and Q.Dungeons then
    for _, e in ipairs(Q.Dungeons:List()) do if e.area == area or e.name == (D:Dungeon(area) or {})[1] then return e end end
  end
  return dungeonByName(name)
end

-- record bosses you fight (new dungeons) and tick them off
local function record(e, nid, name)
  if not (e and name) or Q.db.collect == false or not QuesticusCollect then return end
  QuesticusCollect.dboss = QuesticusCollect.dboss or {}
  local t = QuesticusCollect.dboss[e.name] or {}
  QuesticusCollect.dboss[e.name] = t
  local key = tostring(nid or name)
  if not t[key] then
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    t[key] = { name = name, order = n + 1 }
  end
end
local function npcOf(guid)
  local kind, id = Q.ParseGUID(guid)
  if kind == "Creature" or kind == "Vehicle" then return id end
end
local function bossUnits()
  local e = BT:Current()
  if not e then return end
  for i = 1, 5 do
    local u = "boss" .. i
    if UnitExists and UnitExists(u) then
      local guid, name = Q.UnitGUID(u), Q.UnitName(u)
      if name then
        record(e, npcOf(guid), name)
        local okh, hp = pcall(UnitHealthMax, u)
        local secret = issecretvalue and okh and issecretvalue(hp)
        if okh and not secret and type(hp) == "number" and hp > 0 and QuesticusCollect then
          local nid = npcOf(guid)
          if nid then QuesticusCollect.bhp = QuesticusCollect.bhp or {}; QuesticusCollect.bhp[nid] = hp end
        end
      end
    end
  end
  if bar and bar:IsShown() and bar.e == e then bar.list = BT:List(e); BT:Refresh() end
end
Q:On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", bossUnits)
Q:On("ENCOUNTER_START", function(_, name)
  local e = BT:Current()
  if e and type(name) == "string" and not Q.Secret(name) then record(e, nil, name) end
  bossUnits()
end)
-- boss kills (boss events, deaths, corpses) are recorded by the run log (Runs.lua)
-- (no combat log: WoW Forever forbids addons from registering COMBAT_LOG_EVENT_UNFILTERED)

-- pop up inside a dungeon, and when the route's dungeon step comes up
local lastAuto
local function auto()
  if Q.db.bossTracker == false then return end
  local e = BT:Current()
  if not e then
    local s = P.steps and P.steps[1]
    local m = s and s.type == "complete" and s.quests and P.Meta(s.quests[1])
    if m and m.dungeon and Q.Dungeons then
      local d = D:Dungeon(m.dungeon)
      e = d and dungeonByName(d[1])
    end
  end
  if e and lastAuto ~= e.area then
    lastAuto = e.area
    BT:Show(e)
  elseif not e then
    lastAuto = nil
  end
end
Q:On("PLAYER_ENTERING_WORLD", function() Q.After(2, auto) end)
Q:On("ZONE_CHANGED_NEW_AREA", function() Q.After(1, auto) end)
Q:On("QC_PLAN_UPDATED", auto)

Q:Command("bosses", "the boss tracker for the dungeon you're in (or the route's dungeon)", function()
  local e = BT:Current()
  if not e and Q.char.dmode and Q.Dungeons then
    for _, x in ipairs(Q.Dungeons:List()) do if x.area == Q.char.dmode then e = x end end
  end
  if e then BT:Show(e) else Q:Print("not in a dungeon - open one from the dungeons panel") end
end)
