-- Secrets: WoW Forever's hidden quest chains, easter eggs and hidden collectibles. They're only routed
-- on a Completionist route (the setup survey / Options > Questing "Completionist"); every other route
-- leaves them out. What ForeverDB is missing for them (where the NPCs are, who gives what) is filled in
-- here from the players' guides, without overwriting anything the database already has.
--
-- Each chain: its quests (they get the level they're worth doing at, no category / repeatable filter),
-- what it needs first (Gate), tips shown with its NPCs and objects (DB.note, translated like any text),
-- and route tasks for the parts that aren't quests (an item to loot, an emote to use).
local Q = Questicus
local L = Q.L
local S = {}
Q.Secrets = S

S.CHAINS = {
  -- Alcaz Prison (Dustwallow Marsh) -> Moonbrook -> State Secrets: the Alcaz Operative Insignia toy
  alcaz = { name = "Alcaz Operative Insignia", quests = { 96335, 96337, 96376, 96377, 96379 } },
  -- Westfall / The Barrens -> Stonetalon -> Loch Modan -> Thoradin's Wall: the Cozy Sleeping Bag (12 slots)
  sleepingbag = { name = "Cozy Sleeping Bag", quests = { 79007, 79008, 79192, 79980, 79974, 79975, 79976 } },
  -- the dead Night Watch Guard in Duskwood: the Night Watchman's Torch toy (it's a "level 60" quest)
  torch = { name = "Night Watchman's Torch", quests = { 98372, 99267 }, level = 20 },
  -- Dawn Waker: the torch reveals the Ancient Hilt on Zephras Isle -> the sword Eluvi'ana
  dawnwaker = { name = "Dawn Waker", quests = { 93161, 97029 }, level = 20, needs = "torch" },
  -- /dance with an Excitable Slime in the Undercity canals: the slime companion (Horde)
  slime = { name = "Excitable Slime", quests = { 97583 }, level = 1 },
  -- /chicken at a chicken in Westfall: the Prairie Chicken companion (Alliance)
  chicken = { name = "Prairie Chicken", quests = { 3861 }, level = 1 },
}
-- quest id -> the secret it belongs to; quest id -> the level it's routed at
S.QUESTS, S.LEVEL = {}, {}
for key, ch in pairs(S.CHAINS) do
  for _, q in ipairs(ch.quests) do
    S.QUESTS[q] = key
    if ch.level then S.LEVEL[q] = ch.level end
  end
end
-- versions of one quest: doing one does the others
S.SAME = { { 96376, 96377, 96379 }, { 98372, 99267 } }
S.NAMES = {}
for key, ch in pairs(S.CHAINS) do S.NAMES[key] = ch.name end

function S.Is(id) return S.QUESTS[id] end
-- secrets go on the route only on a Completionist route
function S.Wanted() return Q.prefs and Q.prefs.style == "complete" end

-- ------------------------------------------------------------------ what you own
local TORCH, HEIRLOOM, GUSTJUMPER = 280612, 264908, 268109
local function itemCount(it)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(it, true)) or (GetItemCount and GetItemCount(it, true)) or 0
  return n or 0
end
-- in the bags or the bank, worn, a toy you learned or a companion you have
function S.Owned(it)
  if itemCount(it) > 0 then return true end
  if IsEquippedItem and IsEquippedItem(it) then return true end
  if PlayerHasToy then
    local ok, has = pcall(PlayerHasToy, it)
    if ok and has then return true end
  end
  local PJ = C_PetJournal
  if PJ and PJ.GetPetInfoByItemID and PJ.GetNumCollectedInfo then
    local ok, _, _, _, _, _, _, _, _, _, _, _, species = pcall(PJ.GetPetInfoByItemID, it)
    if ok and species then
      local ok2, n = pcall(PJ.GetNumCollectedInfo, species)
      if ok2 and n and n > 0 then return true end
    end
  end
  return Q.char and Q.char.secretGot and Q.char.secretGot[it] == true or false
end

local function done(st, q)
  local QS = Q.Quests
  return (st and st.done and st.done[q]) or (QS and QS.done and QS.done[q]) or false
end
-- the torch: owned, or its quest done (also in the planned route)
function S.HasTorch(st)
  if done(st, 98372) or done(st, 99267) then return true end
  return S.Owned(TORCH)
end

-- what a secret's quest needs before it can be routed
function S.Gate(id, st)
  local ch = S.CHAINS[S.QUESTS[id] or ""]
  if not ch then return true end
  -- one version per character: not when another one is taken or done
  for _, group in ipairs(S.SAME) do
    for _, q in ipairs(group) do
      if q == id then
        for _, other in ipairs(group) do
          if other ~= id and (done(st, other) or (st and st.log and st.log[other]) or (Q.Quests.log and Q.Quests.log[other])) then return false end
        end
      end
    end
  end
  if ch.needs == "torch" and not S.HasTorch(st) then return false end
  return true
end

-- ------------------------------------------------------------------ fill in the database
local ALCAZ = 16620           -- Alcaz Prison (area id)
-- tips shown with these NPCs / objects (English; the language packs translate them)
S.NOTES = {
  -- Alcaz
  c264770 = "Mason Connery is chained up near the end of Alcaz Prison. Leave The Questioner (at the entrance) alive until you have his quest.",
  c256236 = "The Questioner: kill him only after taking Mason Connery's quest - he drops the Ornate Shackle Key.",
  o611086 = "Connery's Trunk: Moonbrook inn, upstairs (Westfall 43.4, 67.8) - click the loose floorboards by the chest.",
  -- Cozy Sleeping Bag
  o415107 = "Secret (Cozy Sleeping Bag): the burned-out remains by the debris pile at Alexston's Farmstead.",
  o424010 = "Secret (Cozy Sleeping Bag): the burned-out remains by the debris pile at Alexston's Farmstead.",
  o415106 = "Secret (Cozy Sleeping Bag): the rubble of the destroyed tower south of Camp Taurajo.",
  o417072 = "Secret (Cozy Sleeping Bag): the rubble of the destroyed tower south of Camp Taurajo.",
  o424005 = "Secret (Cozy Sleeping Bag): an abandoned camp up the mountain path northeast of Sun Rock Retreat. Stepping Stones' reward lights its campfire.",
  o424012 = "Secret (Cozy Sleeping Bag): the dirt mound at the top of the path north of the camp. Take the jumps slowly - a fall means climbing again.",
  o424007 = "Secret (Cozy Sleeping Bag): at Stonewrought Dam, jump down from the easternmost dwarf head. Miss it and you land in the Wetlands.",
  o406918 = "Secret (Cozy Sleeping Bag): the bag hanging on the wall inside Thoradin's Wall. From the Hillsbrad side, climb the debris of the broken cart into the wall.",
  o424006 = "Secret (Cozy Sleeping Bag): the scroll just below the bag - it hands you the Cozy Sleeping Bag.",
  -- Night Watchman's Torch / Dawn Waker
  c271866 = "Secret (Night Watchman's Torch): the dead Night Watch Guard lies at one of several spots in Duskwood and moves around - look after dark on the game clock. Accept An Unfortunate End on the body and hand it in right there.",
  o676059 = "Secret (Dawn Waker): use the Night Watchman's Torch here to reveal the Ancient Hilt. Altairus guards it: pull him away, run until he gives up, then come back - no need to kill him.",
  c259012 = "Secret (Dawn Waker): Ealaane wants the Ancient Skyborne Blade, small and glowing blue, at one of 48.9 72.7 / 50.4 44.3 / 66.3 43.2 / 59.9 82.2 on Zephras Isle.",
  o676051 = "Secret (Dawn Waker): the Ancient Heirloom ring - wear it (not just carry it) for the rest of the Dawn Waker secret.",
  c3616 = "Secret (Dawn Waker): after handing in the Clouded Water Globe, talk to Onu again and pick the extra dialog option for the Befouled Water Globe.",
  c12736 = "Secret (Dawn Waker): after handing in Baron Aquanis' globe, talk to Je'neu again and pick the extra dialog option for the Befouled Water Globe.",
  -- companions
  c269452 = "Secret (Excitable Slime): the slimes swim in the Undercity canals. Stand somewhere dry next to one, target it and /dance until it wriggles in place facing you - then it offers WRIGGLE. Buy Nutritious Slime Sludge from Boyle (by the Apothecarium) first.",
  c4612 = "Boyle sells the Nutritious Slime Sludge for WRIGGLE. (the Excitable Slime companion).",
  c620 = "Secret (Prairie Chicken): target a chicken and /chicken at it until it offers CLUCK! - bring Special Chicken Feed from Farmer Saldean.",
  c233 = "Farmer Saldean sells the Special Chicken Feed for CLUCK! (the Prairie Chicken companion).",
  c6548 = "Magus Tirth: /chicken at him to turn him back into a human, then /beckon - only then does he sell the Ancona Chicken.",
}

-- fill in what ForeverDB doesn't have (called by Data.lua right after loading it)
function Q.SecretsPatch(DB)
  local function setIfMissing(tbl, key, val)
    if not DB[tbl] then DB[tbl] = {} end
    if DB[tbl][key] == nil then DB[tbl][key] = val end
  end
  -- The Man in the Iron Chains: Mason Connery, a prisoner near the end of Alcaz Prison, gives it and
  -- takes it back; the Ornate Shackle Key drops from The Questioner (the boss at the entrance)
  setIfMissing("qg", 96335, { "c264770" })
  setIfMissing("qe", 96335, { "c264770" })
  setIfMissing("drop", 274029, { 256236, 10000 })
  -- More Valuable Than Gold: freed Mason gives it; Connery's Trunk in the Moonbrook inn takes it
  setIfMissing("qg", 96337, { "c264845" })
  setIfMissing("qe", 96337, { "o611086" })
  -- State Secrets needs the Document Box from More Valuable Than Gold, and only one version is done
  local same = { 96376, 96377, 96379 }
  for _, q in ipairs(same) do
    local x = DB.qx and DB.qx[q]
    if x then
      if x[3] == nil then x[3] = { 96337 } end
      if x[5] == nil then
        local others = {}
        for _, o in ipairs(same) do if o ~= q then others[#others + 1] = o end end
        x[5] = others
      end
    end
  end
  -- the torch: one version per character
  for _, pair in ipairs({ { 98372, 99267 }, { 99267, 98372 } }) do
    local x = DB.qx and DB.qx[pair[1]]
    if x and x[5] == nil then x[5] = { pair[2] } end
  end
  -- Alcaz Prison's entrance (the portal in the tower's basement, Dustwallow Marsh 75.3, 14.1)
  if not (DB.dng and DB.dng[ALCAZ]) and Q.Data and Q.Data.EXTRA_DNG and not Q.Data.EXTRA_DNG[ALCAZ] then
    Q.Data.EXTRA_DNG[ALCAZ] = { "Alcaz Prison", 15, { 1445, 753, 141 } }
  end
  -- the people inside Alcaz Prison: the route takes you to its entrance
  for _, k in ipairs({ "c264770", "c264845", "c256236" }) do setIfMissing("ind", k, { ALCAZ }) end
  -- Connery's Trunk: Moonbrook inn, second floor (Westfall 43.4, 67.8)
  setIfMissing("spm", "o611086", { [1436] = { 434, 678 } })
  -- the Ancient Heirloom (replacement / for everyone who isn't Skyborne): top floor of the tower
  setIfMissing("spm", "o676051", { [2521] = { 417, 234 } })
  DB.note = DB.note or {}
  for k, v in pairs(S.NOTES) do if DB.note[k] == nil then DB.note[k] = v end end
end

-- one version done: the others are done too
Q:On("QUEST_TURNED_IN", function(id)
  for _, group in ipairs(S.SAME) do
    for _, q in ipairs(group) do
      if q == id and Q.Quests then
        for _, other in ipairs(group) do Q.Quests.done[other] = true end
      end
    end
  end
end)
Q:On("QC_READY", function()
  local QS = Q.Quests
  if not (QS and QS.done) then return end
  for _, group in ipairs(S.SAME) do
    local any = false
    for _, q in ipairs(group) do if QS.done[q] then any = true end end
    if any then for _, q in ipairs(group) do QS.done[q] = true end end
  end
end)

-- ------------------------------------------------------------------ route tasks (not quests)
-- { key, chain, item = what you get, map, x, y (0-1), work (seconds there), text, why, gate(st) }
S.TASKS = {
  { key = "heirloom", chain = "dawnwaker", item = HEIRLOOM, map = 2521, x = 0.417, y = 0.234, work = 25, icon = "loot",
    text = "Secret: pick up the Ancient Heirloom (Zephras Isle, top floor of the tower) and wear it",
    why = "Dawn Waker secret: the ring has to be worn for the Highborne spirit, the switches and the vault to show up later",
    gate = function(st) return S.HasTorch(st) and not done(st, 92460) end },
  { key = "gustjumper", chain = "frog", item = GUSTJUMPER, map = 2521, x = 0.51, y = 0.72, work = 40, icon = "use",
    text = "Secret: /sing by the frogs (Zephras Isle) - a Musical Gustjumper joins you",
    why = "Hidden companion: use /sing next to the group of frogs; another frog appears and becomes your pet" },
}

local points = {}
local function taskPoint(t)
  local p = points[t.key]
  if p == nil then
    local D = Q.Data
    local i, x, y = D and D:WorldPos(t.map, t.x, t.y)
    p = i and { i = i, x = x, y = y, m = t.map, mx = t.x, my = t.y } or false
    points[t.key] = p
  end
  return p or nil
end

-- learned a companion / toy while at a task's spot: that task is done (when the game can't say)
local function markNear()
  local P = Q.Planner
  local s = P and P.steps and P.steps[1]
  if not (s and s.type == "task" and s.task and s.task.secret) then return end
  local here = Q.Data and Q.Data:PlayerPos()
  if here and s.point and Q.Data.Dist(here, s.point) < 60 then
    Q.char.secretGot = Q.char.secretGot or {}
    Q.char.secretGot[s.task.item] = true
    P:Replan(0.5)
  end
end
Q:On("COMPANION_LEARNED", markNear)
Q:On("NEW_PET_ADDED", markNear)
Q:On("NEW_TOY_ADDED", function() if Q.Planner then Q.Planner:Replan(1) end end)

local tasks = {}
Q:On("QC_READY", function()
  local P = Q.Planner
  if S.registered or not (P and P.AddTasks) then return end
  S.registered = true
  P.AddTasks(function(st, lv, add, travel)
    if not S.Wanted() then return end
    local QS = Q.Quests
    for _, t in ipairs(S.TASKS) do
      if not S.Owned(t.item) and (not t.gate or t.gate(st)) and lv >= (t.level or 1) then
        local pt = taskPoint(t)
        if pt and st.pos then
          local task = tasks[t.key]
          if not task then
            task = { key = "secret:" .. t.key, secret = true, item = t.item, icon = t.icon,
              text = "|cffffd100" .. L[t.text] .. "|r", short = L[t.text], why = { L[t.why] } }
            tasks[t.key] = task
          end
          local tt = travel(st.pos, pt, lv) + (t.work or 20)
          add(task, pt, tt, QS.QuestXP(lv, lv) * 1.2)
        end
      end
    end
  end)
end)
