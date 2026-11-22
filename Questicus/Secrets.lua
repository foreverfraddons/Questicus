-- Secrets: WoW Forever's hidden quest chains (easter eggs). They're only routed on a Completionist
-- route (the setup survey / Options > Questing "Completionist"); every other route leaves them out.
-- What ForeverDB is missing for them (where the NPCs are, who gives what) is filled in here from the
-- players' guides, without overwriting anything the database already has.
local Q = Questicus
local S = {}
Q.Secrets = S

-- quest id -> the secret it belongs to
S.QUESTS = {
  -- Alcaz Operative Insignia (Alcaz Prison, Dustwallow Marsh -> Moonbrook -> State Secrets)
  [96335] = "alcaz",   -- The Man in the Iron Chains (Mason Connery, inside Alcaz Prison)
  [96337] = "alcaz",   -- More Valuable Than Gold (Connery's Trunk, Moonbrook inn upstairs)
  [96376] = "alcaz",   -- State Secrets (Nazgrel, Grommash Hold, Orgrimmar - Horde)
  [96377] = "alcaz",   -- State Secrets (Renzik "The Shiv", SI:7, Stormwind - Alliance)
  [96379] = "alcaz",   -- State Secrets (Rix Xizzix, Booty Bay - both)
}
-- versions of one quest: doing one does the others (only one State Secrets per character)
S.SAME = { { 96376, 96377, 96379 } }

S.NAMES = { alcaz = "Alcaz Operative Insignia" }

function S.Is(id) return S.QUESTS[id] ~= nil end
-- secrets go on the route only on a Completionist route
function S.Wanted() return Q.prefs and Q.prefs.style == "complete" end

local ALCAZ = 16620           -- Alcaz Prison (area id)
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
  -- Alcaz Prison's entrance (the portal in the tower's basement, Dustwallow Marsh 75.3, 14.1)
  if not (DB.dng and DB.dng[ALCAZ]) and Q.Data and Q.Data.EXTRA_DNG and not Q.Data.EXTRA_DNG[ALCAZ] then
    Q.Data.EXTRA_DNG[ALCAZ] = { "Alcaz Prison", 15, { 1445, 753, 141 } }
  end
  -- the people inside Alcaz Prison: the route takes you to its entrance
  for _, k in ipairs({ "c264770", "c264845", "c256236" }) do setIfMissing("ind", k, { ALCAZ }) end
  -- Connery's Trunk: Moonbrook inn, second floor (Westfall 43.4, 67.8)
  setIfMissing("spm", "o611086", { [1436] = { 434, 678 } })
  -- tips shown with those NPCs / objects
  DB.note = DB.note or {}
  local notes = {
    c264770 = "Mason Connery is chained up near the end of Alcaz Prison. Leave The Questioner (at the entrance) alive until you have his quest.",
    c256236 = "The Questioner: kill him only after taking Mason Connery's quest - he drops the Ornate Shackle Key.",
    o611086 = "Connery's Trunk: Moonbrook inn, upstairs (Westfall 43.4, 67.8) - click the loose floorboards by the chest.",
  }
  for k, v in pairs(notes) do if DB.note[k] == nil then DB.note[k] = v end end
end

-- one State Secrets done (any version): the others are done too
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
