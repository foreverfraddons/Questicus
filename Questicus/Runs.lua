-- Questicus dungeon runs: every run of a dungeon is recorded - how long it took (to the last boss), the
-- gold and XP you made inside, every boss kill with its time, and the loot that dropped (and who got
-- it). The boss tracker shows the run as it goes; History shows past runs and the averages per dungeon
-- (which the dungeons panel uses for clear times and gold per run).
--
-- No combat log (WoW Forever closes it to addons). Kills come from the boss events (ENCOUNTER_END /
-- BOSS_KILL, the encounter IDs learned per boss), party kills and unit deaths (GUIDs, when not secret),
-- the "<mob> dies." line, dead bosses on nameplates, targeted or looted, and from right-clicking a boss.
-- A run is one copy of a dungeon: going out (a corpse run, a vendor trip) and back in carries on the
-- same run; a reset dungeon, another copy or a long time away starts a new one. Values the game hands
-- over as secret are skipped.
local Q = Questicus
local T, D, QS = Q.T, Q.Data, Q.Quests
local R = {}
Q.Runs = R

local MAX_RUNS = 100
local RESUME = 90 * 60                -- back inside within this: the same run
local function now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end
local function plain(v) if Q.Secret(v) then return nil end return v end

-- ------------------------------------------------------------------ storage (per character)
local function store()
  Q.char.runs = Q.char.runs or {}
  return Q.char.runs
end
R.store = store
function R:Current() return Q.char and Q.char.runCur end
local function changed() Q:Send("QC_RUN_CHANGED") end

-- the copy of the dungeon (instance ID) from a creature's GUID: Creature-0-server-map-copy-npc-spawn
function R.CopyOf(guid)
  if type(guid) ~= "string" or Q.Secret(guid) then return end
  local ok, kind, _, _, map, copy = pcall(strsplit, "-", guid)
  if ok and (kind == "Creature" or kind == "Vehicle") then return tonumber(map), tonumber(copy) end
end

local function readXP()
  if not (UnitXP and UnitXPMax) then return end
  local ok1, xp = pcall(UnitXP, "player")
  local ok2, mx = pcall(UnitXPMax, "player")
  if not (ok1 and ok2) or Q.Secret(xp) or Q.Secret(mx) then return end
  return tonumber(xp), tonumber(mx), Q.player.level
end
local function readMoney()
  if not GetMoney then return end
  local ok, m = pcall(GetMoney)
  if ok and not Q.Secret(m) then return tonumber(m) end
end

local lastXP, lastMax, lastLevel, lastMoney
local inside                                      -- the dungeon entry you're in (Dungeons list entry), or nil

-- start / resume the run for dungeon e
function R:Begin(e)
  local cur = R:Current()
  local t = now()
  if cur and cur.area == e.area and not cur.ended and (t - (cur.seen or cur.start)) < RESUME then
    cur.seen = t
    return cur
  end
  if cur and not cur.ended then R:Finish(cur) end
  cur = { area = e.area, name = e.name, start = t, seen = t, xp = 0, money = 0, kills = {}, loot = {},
    level = Q.player.level, bosses = 0 }
  local list = Q.Bosses and Q.Bosses:List(e)
  cur.bosses = list and #list or 0
  Q.char.runCur = cur
  changed()
  return cur
end
-- a run that's over goes into the history (only runs with something in them)
function R:Finish(run)
  run = run or R:Current()
  if not run or run.ended then return end
  run.ended = run.seen or now()
  local any = (run.xp or 0) > 0 or (run.money or 0) > 0 or next(run.kills) ~= nil or #run.loot > 0
  if any then
    local h = store()
    table.insert(h, 1, run)
    while #h > MAX_RUNS do table.remove(h) end
  end
  if Q.char.runCur == run then Q.char.runCur = nil end
  changed()
end
function R:NewRun()
  local cur = R:Current()
  if cur then R:Finish(cur) end
  if inside then R:Begin(inside) end
end

-- ------------------------------------------------------------------ kills
local function norm(s) return (s or ""):lower():gsub("[^%w]", "") end
-- the boss a name / npc id / encounter is (the tracker's list), or nil
function R:BossFor(e, name, nid, encounter)
  if not (e and Q.Bosses) then return end
  local list = Q.Bosses:List(e)
  local enc = QuesticusCollect and QuesticusCollect.benc
  if encounter and enc and enc[encounter] then name = enc[encounter] end
  local n = name and norm(name)
  for _, b in ipairs(list) do
    if (nid and b.nid == nid) or (n and norm(b.name) == n) then return b end
  end
  -- an encounter named for a group (or a boss whose name the encounter shortens)
  if n and #n >= 4 then
    for _, b in ipairs(list) do
      local bn = norm(b.name)
      if bn:find(n, 1, true) or n:find(bn, 1, true) then return b end
    end
  end
end
-- a boss died: tick it off with its time
function R:Kill(name, how)
  local cur = R:Current()
  if not (cur and name) then return end
  local k = name:lower()
  if not cur.kills[k] then
    cur.kills[k] = { t = now() - cur.start, how = how }
    cur.seen = now()
    cur.lastBoss = { k = k, t = now() }
    local done = 0
    for _ in pairs(cur.kills) do done = done + 1 end
    if cur.bosses > 0 and done >= cur.bosses and not cur.done then cur.done = now() - cur.start end
    changed()
  end
end
function R:Unkill(name)
  local cur = R:Current()
  if cur and name then cur.kills[name:lower()] = nil; cur.done = nil; changed() end
end
function R:Killed(name)
  local cur = R:Current()
  return cur and name and cur.kills[name:lower()] ~= nil or false
end
local where
local function onDeath(name, nid, how, encounter)
  if not inside then
    local e = where and where()                   -- (an event came before the zone change was seen)
    if not e then return end
    inside = e
    R:Begin(e)
  end
  local b = R:BossFor(inside, name, nid, encounter)
  if not b then return end
  if encounter and type(name) == "string" and QuesticusCollect and Q.db.collect ~= false then
    QuesticusCollect.benc = QuesticusCollect.benc or {}
    QuesticusCollect.benc[encounter] = b.name                -- this encounter is that boss, from now on
  end
  R:Kill(b.name, how)
end

-- ------------------------------------------------------------------ loot (the loot chat lines)
-- "You receive loot: [x]x2." / "Name receives loot: [x]." - patterns from the game's own strings
local lootPats
local function pattern(fmt)
  if not fmt then return end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end
local function patterns()
  if lootPats then return lootPats end
  lootPats = {}
  local function add(g, self) local p = pattern(_G[g]); if p then lootPats[#lootPats + 1] = { p, self } end end
  add("LOOT_ITEM_SELF_MULTIPLE", true); add("LOOT_ITEM_SELF", true)
  add("LOOT_ITEM_PUSHED_SELF_MULTIPLE", true); add("LOOT_ITEM_PUSHED_SELF", true)
  add("LOOT_ITEM_MULTIPLE", false); add("LOOT_ITEM", false)
  if #lootPats == 0 then
    lootPats = { { "^You receive loot: (.+)x(%d+)%.$", true }, { "^You receive loot: (.+)%.$", true },
      { "^(.+) receives loot: (.+)x(%d+)%.$", false }, { "^(.+) receives loot: (.+)%.$", false } }
  end
  return lootPats
end
function R.ParseLoot(text)
  if type(text) ~= "string" then return end
  for _, p in ipairs(patterns()) do
    local a, b, c = text:match(p[1])
    if a then
      if p[2] then return Q.UnitName and Q.UnitName("player") or "you", a, tonumber(b) or 1 end
      return a, b, tonumber(c) or 1
    end
  end
end
local function onLoot(text)
  local cur = R:Current()
  if not (cur and inside) then return end
  local who, link, n = R.ParseLoot(plain(text))
  if not link then return end
  local id = tonumber(link:match("item:(%d+)"))
  if not id then return end
  local q = select(3, Q.GetItemInfo(id))
  if q and q < 2 then return end                                    -- greys and whites: not worth a line
  -- which boss it came from: the corpse being looted, else the boss killed in the last few minutes
  local boss = R.lootFrom
  if not boss and cur.lastBoss and now() - (cur.lastBoss.t or 0) < 180 then boss = cur.lastBoss.k end
  cur.loot[#cur.loot + 1] = { id = id, link = link, who = who, n = n, t = now() - cur.start, boss = boss }
  cur.seen = now()
  changed()
end

-- ------------------------------------------------------------------ XP and gold
local function onXP()
  local xp, mx, lv = readXP()
  if not xp then return end
  local cur = R:Current()
  if cur and inside and lastXP then
    local gain
    if lv == lastLevel then gain = xp - lastXP
    elseif lv and lastLevel and lv > lastLevel then gain = (lastMax - lastXP) + xp end
    if gain and gain > 0 then cur.xp = cur.xp + gain; cur.seen = now(); changed() end
  end
  lastXP, lastMax, lastLevel = xp, mx, lv
end
local function onMoney()
  local m = readMoney()
  if not m then return end
  local cur = R:Current()
  if cur and inside and lastMoney and m > lastMoney then
    cur.money = cur.money + (m - lastMoney)
    cur.seen = now()
    changed()
  end
  lastMoney = m
end

-- ------------------------------------------------------------------ where you are
function where()
  if not GetInstanceInfo then return end
  local _, itype = GetInstanceInfo()
  if itype ~= "party" then return end
  return Q.Bosses and Q.Bosses:Current()
end
local function refresh()
  local e = where()
  if e then
    inside = e
    R:Begin(e)
  else
    inside = nil
    local cur = R:Current()
    if cur and not cur.ended and (now() - (cur.seen or cur.start)) >= RESUME then R:Finish(cur) end
  end
  changed()
end
R.Refresh = refresh

-- a new copy of the dungeon (someone reset it): a new run
local function onCopy(guid)
  local cur = R:Current()
  if not (cur and inside) then return end
  local _, copy = R.CopyOf(guid)
  if not copy then return end
  if cur.copy and cur.copy ~= copy then
    R:Finish(cur)
    R:Begin(inside).copy = copy
  else
    cur.copy = copy
  end
end

Q:On("PLAYER_ENTERING_WORLD", function()
  lastXP, lastMax, lastLevel = readXP()
  lastMoney = readMoney()
  Q.After(2, refresh)
end)
Q:On("ZONE_CHANGED_NEW_AREA", function() Q.After(1, refresh) end)
Q:On("PLAYER_XP_UPDATE", onXP)
Q:On("PLAYER_LEVEL_UP", function() Q.After(0.5, onXP) end)
Q:On("PLAYER_MONEY", onMoney)
Q:On("CHAT_MSG_LOOT", onLoot)
Q:On("ENCOUNTER_END", function(id, name, _, _, success)
  if success == 1 or success == true then onDeath(plain(name), nil, "boss", tonumber(plain(id))) end
end)
Q:On("BOSS_KILL", function(id, name) onDeath(plain(name), nil, "boss", tonumber(plain(id))) end)
Q:On("UNIT_DIED", function(guid)
  local kind, nid = Q.ParseGUID(guid)
  if nid and (kind == "Creature" or kind == "Vehicle") then onDeath(nil, nid, "died") end
end)
Q:On("PARTY_KILL", function(_, target)
  local kind, nid = Q.ParseGUID(target)
  if nid then onCopy(target); onDeath(nil, nid, "party") end
end)
Q:On("CHAT_MSG_COMBAT_HOSTILE_DEATH", function(text)
  text = plain(text)
  if type(text) ~= "string" then return end
  local name = text:match("^(.+) dies%.$") or text:match("^You have slain (.+)!$")
  if name then onDeath(name, nil, "death") end
end)
-- a dead boss on a nameplate, targeted or looted
local function deadUnit(unit)
  if not inside or not (UnitExists and UnitExists(unit)) then return end
  local ok, dead = pcall(UnitIsDead, unit)
  if not ok or Q.Secret(dead) or not dead then return end
  local guid = Q.UnitGUID(unit)
  local _, nid = Q.ParseGUID(guid)
  if guid then onCopy(guid) end
  onDeath(Q.UnitName(unit), nid, "corpse")
end
Q:On("NAME_PLATE_UNIT_ADDED", deadUnit)
Q:On("PLAYER_TARGET_CHANGED", function() deadUnit("target") end)
Q:On("LOOT_OPENED", function()
  deadUnit("target")
  -- looting a boss you killed: what you take is its loot
  R.lootFrom = nil
  local cur = R:Current()
  if cur and GetLootSourceInfo then
    local ok, guid = pcall(GetLootSourceInfo, 1)
    local _, id = Q.ParseGUID(ok and guid or nil)
    local nm = id and Q.Data and Q.Data.NPC and Q.Data:NPC(id)
    nm = nm and nm[1]
    if type(nm) == "string" and cur.kills[nm:lower()] then R.lootFrom = nm:lower() end
  end
end)
Q:On("LOOT_CLOSED", function() Q.After(2, function() R.lootFrom = nil end) end)

-- what dropped from a boss in this run (or `run`), and who got it
function R:LootOf(name, run)
  run = run or R:Current()
  local out = {}
  if not (run and name) then return out end
  local k = name:lower()
  for _, l in ipairs(run.loot or {}) do if l.boss == k then out[#out + 1] = l end end
  return out
end
-- "X has been reset." for your dungeon
Q:On("CHAT_MSG_SYSTEM", function(text)
  text = plain(text)
  local cur = R:Current()
  local resetPat = type(INSTANCE_RESET_SUCCESS) == "string" and INSTANCE_RESET_SUCCESS:gsub("%.", "%%."):gsub("%%s", "(.+)")
  local isReset = type(text) == "string" and ((text:find("reset") or text:find("Reset")) or (resetPat and text:match(resetPat)))
  if type(text) == "string" and cur and text:find(cur.name, 1, true) and isReset then
    R:Finish(cur)
  end
end)
Q:On("PLAYER_LOGOUT", function()
  local cur = R:Current()
  if cur then cur.seen = cur.seen or now() end
end)

-- ------------------------------------------------------------------ averages
-- per dungeon over the recorded runs: { runs, time (completed runs), gold, xp }
function R:Averages(area)
  local n, tn, tsum, gsum, xsum = 0, 0, 0, 0, 0
  for _, r in ipairs(store()) do
    if r.area == area then
      n = n + 1
      gsum, xsum = gsum + (r.money or 0), xsum + (r.xp or 0)
      if r.done then tn, tsum = tn + 1, tsum + r.done end
    end
  end
  if n == 0 then return end
  return { runs = n, time = tn > 0 and tsum / tn or nil, timed = tn, gold = gsum / n, xp = xsum / n }
end

function R.Money(cp)
  cp = math.floor(cp or 0)
  local g, s, c = math.floor(cp / 10000), math.floor(cp / 100) % 100, cp % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return ("%ds %dc"):format(s, c) end
  return c .. "c"
end
function R.Clock(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
end
-- one line for the tracker: time, gold, XP
function R:Summary(run)
  run = run or R:Current()
  if not run then return "" end
  local t = run.done or ((run.ended or now()) - run.start)
  return ("%s   %s   %s XP"):format(R.Clock(t), R.Money(run.money), (BreakUpLargeNumbers and BreakUpLargeNumbers(run.xp or 0)) or tostring(run.xp or 0))
end

-- ------------------------------------------------------------------ history window
local win, detail
local hrows = {}
R.hrows = hrows
R.rowRun = {}
local function hrow(i)
  local r = hrows[i]
  if r then return r end
  r = CreateFrame("Button", nil, win.body)
  r:SetHeight(32)
  r:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  local hl = r:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 1, 1, 0.06) end
  r.top = T.Text(r, 12, T.c.text)
  r.top:SetPoint("TOPLEFT", 6, -2)
  r.top:SetPoint("RIGHT", -6, 0)
  r.top:SetJustifyH("LEFT")
  r.sub = T.Text(r, 10, T.c.dim)
  r.sub:SetPoint("TOPLEFT", 6, -17)
  r.sub:SetPoint("RIGHT", -6, 0)
  r.sub:SetJustifyH("LEFT")
  r:SetScript("OnClick", function(self) local run = R.rowRun[self]; if run then R:ShowRun(run) end end)
  hrows[i] = r
  return r
end

function R:ShowHistory(area)
  if not win then
    win = T.Window("QuesticusRuns", 460, 420, "Dungeon runs", nil)
    win.avg = T.Text(win, 11, T.c.text)
    win.avg:SetPoint("TOPLEFT", 14, -32)
    win.avg:SetPoint("RIGHT", -14, 0)
    win.avg:SetJustifyH("LEFT")
    win.avg:SetSpacing(2)
    win.scroll = CreateFrame("ScrollFrame", nil, win)
    win.scroll:SetPoint("TOPLEFT", 8, -110)
    win.scroll:SetPoint("BOTTOMRIGHT", -8, 10)
    win.body = CreateFrame("Frame", nil, win.scroll)
    win.body:SetSize(440, 1)
    win.scroll:SetScrollChild(win.body)
    if win.scroll.EnableMouseWheel then win.scroll:EnableMouseWheel(true) end
    win.scroll:SetScript("OnMouseWheel", function(self, d)
      local max = math.max(0, (win.body:GetHeight() or 0) - (self:GetHeight() or 0))
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
  end
  R.histArea = area
  local runs = {}
  for _, r in ipairs(store()) do if not area or r.area == area then runs[#runs + 1] = r end end
  -- averages: this dungeon, or every dungeon you've run
  local lines = {}
  local seen, order = {}, {}
  for _, r in ipairs(runs) do if not seen[r.area] then seen[r.area] = r.name; order[#order + 1] = r.area end end
  for k, a in ipairs(order) do
    if k > 4 then lines[#lines + 1] = Q.Color(T.HEX.dim, ("... and %d more dungeons"):format(#order - 4)); break end
    local av = R:Averages(a)
    lines[#lines + 1] = Q.Color(T.HEX.gold, seen[a]) .. Q.Color(T.HEX.dim, ("  %d run%s - average "):format(av.runs, av.runs == 1 and "" or "s"))
      .. (av.time and (R.Clock(av.time) .. Q.Color(T.HEX.dim, " to clear, ")) or "")
      .. R.Money(av.gold) .. Q.Color(T.HEX.dim, ", ") .. math.floor(av.xp) .. Q.Color(T.HEX.dim, " XP")
  end
  if #lines == 0 then lines[1] = Q.Color(T.HEX.dim, "No runs recorded yet - they're saved as you play dungeons.") end
  win.avg:SetText(table.concat(lines, "\n"))
  win.title:SetText(Q.Color(T.HEX.accent, "Dungeon runs") .. (area and Q.Color(T.HEX.dim, " - " .. (seen[area] or "")) or ""))
  local y = 0
  for i, r in ipairs(runs) do
    local row = hrow(i)
    R.rowRun[row] = r
    local kills = 0
    for _ in pairs(r.kills or {}) do kills = kills + 1 end
    local when = date and date("%b %d %H:%M", r.start) or tostring(r.start)
    row.top:SetText(("%s  %s"):format(Q.Color(T.HEX.gold, r.name), Q.Color(T.HEX.dim, when)))
    row.sub:SetText(("%s%s   %s   %s XP   %d/%d bosses   %d item%s"):format(
      r.done and "" or Q.Color(T.HEX.dim, "unfinished "), R.Clock(r.done or ((r.ended or now()) - r.start)), R.Money(r.money), r.xp or 0,
      kills, r.bosses or 0, #(r.loot or {}), #(r.loot or {}) == 1 and "" or "s"))
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("RIGHT", 0, 0); row:Show()
    y = y + 34
  end
  for i = #runs + 1, #hrows do hrows[i]:Hide(); R.rowRun[hrows[i]] = nil end
  win.body:SetHeight(math.max(1, y))
  if Q.Bosses then Q.Bosses.Front(win) else win:Show() end
  return runs
end

-- one run: its bosses with kill times, and the loot with who got it
local lrows = {}
R.lootRows = lrows
R.lootData = {}
function R:ShowRun(run)
  if not detail then
    detail = T.Window("QuesticusRun", 400, 300, "Run", nil)
    detail.text = T.Text(detail, 12, T.c.text)
    detail.text:SetPoint("TOPLEFT", 14, -32)
    detail.text:SetPoint("RIGHT", -14, 0)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetSpacing(3)
  end
  if win and win:IsShown() then detail:ClearAllPoints(); detail:SetPoint("TOPLEFT", win, "TOPRIGHT", 8, 0) end
  detail.title:SetText(Q.Color(T.HEX.accent, run.name) .. Q.Color(T.HEX.dim, date and ("  " .. date("%b %d %H:%M", run.start)) or ""))
  local L = {}
  L[#L + 1] = Q.Color(T.HEX.dim, "Time: ") .. R.Clock(run.done or ((run.ended or now()) - run.start)) .. (run.done and "" or Q.Color(T.HEX.dim, "  (not every boss was killed)"))
  L[#L + 1] = Q.Color(T.HEX.dim, "Gold: ") .. R.Money(run.money) .. Q.Color(T.HEX.dim, "    XP: ") .. (run.xp or 0)
    .. Q.Color(T.HEX.dim, ("    level %d"):format(run.level or 0))
  L[#L + 1] = " "
  L[#L + 1] = Q.Color(T.HEX.gold, "Bosses")
  local ks = {}
  for name, k in pairs(run.kills or {}) do ks[#ks + 1] = { name, k.t } end
  table.sort(ks, function(a, b) return a[2] < b[2] end)
  for _, k in ipairs(ks) do L[#L + 1] = ("  %s  %s"):format(Q.Color(T.HEX.dim, R.Clock(k[2])), k[1]:gsub("^%l", string.upper)) end
  if #ks == 0 then L[#L + 1] = Q.Color(T.HEX.dim, "  none recorded") end
  L[#L + 1] = " "
  L[#L + 1] = Q.Color(T.HEX.gold, "Loot") .. Q.Color(T.HEX.dim, "  (uncommon and better)")
  detail.text:SetText(table.concat(L, "\n"))
  local h = (detail.text.GetStringHeight and detail.text:GetStringHeight()) or #L * 17
  if type(h) ~= "number" or h < #L * 10 then h = #L * 17 end
  local y = h + 8
  for i, it in ipairs(run.loot or {}) do
    local r = lrows[i]
    if not r then
      r = CreateFrame("Button", nil, detail)
      r:SetHeight(20)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 2, 0)
      r.text = T.Text(r, 12, T.c.text); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.text:SetPoint("RIGHT", -2, 0)
      r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
      r:SetScript("OnEnter", function(self)
        local d = R.lootData[self]; if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, d.id)) then pcall(GameTooltip.SetHyperlink, GameTooltip, d.link) end
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r:SetScript("OnClick", function(self)
        local d = R.lootData[self]
        if d and HandleModifiedItemClick then HandleModifiedItemClick(d.link) end
      end)
      lrows[i] = r
    end
    R.lootData[r] = it
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)
    r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.text:SetText(it.link .. ((it.n or 1) > 1 and (" x" .. it.n) or "") .. Q.Color(T.HEX.dim, "  - " .. tostring(it.who or "?")))
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", detail.text, "TOPLEFT", 0, -y); r:SetPoint("RIGHT", detail, "RIGHT", -14, 0); r:Show()
    y = y + 21
  end
  for i = #(run.loot or {}) + 1, #lrows do lrows[i]:Hide(); R.lootData[lrows[i]] = nil end
  if #(run.loot or {}) == 0 then y = y + 18 end
  detail:SetHeight(math.min(760, 32 + y + 16))
  if Q.Bosses then Q.Bosses.Front(detail) else detail:Show() end
  return L
end

Q:Command("runs", "your dungeon runs: times, gold, XP, loot and averages", function() R:ShowHistory() end)
