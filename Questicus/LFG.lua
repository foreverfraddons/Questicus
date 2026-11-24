-- Find a group: lists you in the game's group finder for a dungeon, after asking your role (or using
-- the one you chose in the options). The playstyle is Relaxed unless you pick another in the options.
local Q = Questicus
local T = Q.T
local LF = {}
Q.LFG = LF
local cfg = function()
  Q.db.lfg = type(Q.db.lfg) == "table" and Q.db.lfg or {}
  local c = Q.db.lfg
  if c.playstyle == nil then c.playstyle = "relaxed" end
  if c.role == nil then c.role = "ask" end
  return c
end
LF.cfg = cfg

-- ------------------------------------------------------------------ the group finder's activity
local function norm(n)
  n = (n or ""):lower():gsub("^the ", ""):gsub("[%p%s]", "")
  return n
end
-- other names a dungeon goes by in the group finder
local ALSO = {
  ["templeofatalhakkar"] = { "sunkentemple" }, ["sunkentemple"] = { "templeofatalhakkar" },
  ["deadmines"] = { "deadmines" }, ["stockade"] = { "stormwindstockade", "stockades" },
  ["blackrockspire"] = { "lowerblackrockspire", "upperblackrockspire" },
}
local function activities()
  local out = {}
  if not (C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities) then return out end
  local ok, cats = pcall(C_LFGList.GetAvailableCategories)
  for _, cat in ipairs(ok and cats or {}) do
    local ok2, acts = pcall(C_LFGList.GetAvailableActivities, cat)
    for _, id in ipairs(ok2 and acts or {}) do
      local info
      if C_LFGList.GetActivityInfoTable then
        local ok3, t = pcall(C_LFGList.GetActivityInfoTable, id)
        info = ok3 and t
      end
      local name = info and (info.fullName or info.shortName)
      if not name and C_LFGList.GetActivityFullName then
        local ok4, n = pcall(C_LFGList.GetActivityFullName, id)
        name = ok4 and n
      end
      if type(name) == "string" then out[#out + 1] = { id = id, name = name, cat = cat } end
    end
  end
  return out
end
-- the activity for this dungeon (the normal one, not heroic / a raid of the same name)
function LF.Activity(name)
  local want = { [norm(name)] = true }
  for _, a in ipairs(ALSO[norm(name)] or {}) do want[a] = true end
  local best
  for _, a in ipairs(activities()) do
    local n = norm(a.name)
    local base = n:gsub("heroic", ""):gsub("normal", ""):gsub("mythic", "")
    if want[n] or want[base] then
      local heroic = n:find("heroic") or n:find("mythic")
      if not best or (best.heroic and not heroic) then best = { id = a.id, name = a.name, heroic = heroic } end
    end
  end
  if not best then
    -- a looser match: the group finder's name contains the dungeon's
    local w = norm(name)
    for _, a in ipairs(activities()) do
      if norm(a.name):find(w, 1, true) and not norm(a.name):find("heroic") then best = { id = a.id, name = a.name }; break end
    end
  end
  return best
end

-- ------------------------------------------------------------------ playstyle
local STYLE_WORDS = {
  relaxed = { "relax", "casual" },
  standard = { "standard" },
  learning = { "learn" },
  serious = { "serious", "competitive", "hardcore", "expert" },
}
LF.STYLES = { { "relaxed", "Relaxed" }, { "standard", "Standard" }, { "learning", "Learning" }, { "serious", "Serious" } }
local function enumValue(enum, words)
  if type(enum) ~= "table" then return nil end
  -- (the first word wins: "relax" before "fun", so FunRelaxed and not FunSerious)
  for _, w in ipairs(words) do
    for k, v in pairs(enum) do
      if tostring(k):lower():find(w, 1, true) then return v end
    end
  end
end
local function styleValues()
  local words = STYLE_WORDS[cfg().playstyle] or STYLE_WORDS.relaxed
  return enumValue(Enum and Enum.LFGEntryPlaystyle, words), enumValue(Enum and Enum.LFGEntryGeneralPlaystyle, words)
end

-- ------------------------------------------------------------------ listing
local ROLES = { tank = "Tank", healer = "Healer", dps = "Damage" }
local function setRole(role)
  local t, h, d = role == "tank", role == "healer", role == "dps"
  if C_LFGList and C_LFGList.SetRoles then pcall(C_LFGList.SetRoles, { tank = t, healer = h, dps = d }) end
  if SetLFGRoles then pcall(SetLFGRoles, false, t, h, d) end
end
local function openFinder()
  if PVEFrame_ShowFrame then pcall(PVEFrame_ShowFrame, "GroupFinderFrame")
  elseif ToggleLFGParentFrame then pcall(ToggleLFGParentFrame)
  elseif LFGListingFrame and ShowUIPanel then pcall(ShowUIPanel, LFGListingFrame) end
end
LF.Open = openFinder
-- (called from a click: the game only lets a listing be made right after you click something)
function LF:List(act, role, dname)
  setRole(role)
  local ps, gps = styleValues()
  local ok, res = pcall(C_LFGList.CreateListing, {
    activityIDs = { act.id }, playstyle = ps, generalPlaystyle = gps,
    isAutoAccept = false, isPrivateGroup = false, newPlayerFriendly = false,
  })
  -- (older group finders take the activities as a plain list)
  if not ok or res == false then ok, res = pcall(C_LFGList.CreateListing, { act.id }) end
  if ok and res ~= false then
    Q:Print(("Listed for %s as %s%s. Players can now find you in the group finder."):format(act.name, ROLES[role] or role,
      (ps or gps) and (" - " .. cfg().playstyle) or ""))
  else
    Q:Print(("Couldn't list you for %s - the group finder is open, list from there."):format(dname or act.name))
    openFinder()
  end
end

-- the role prompt
local pick
local function rolePrompt(act, dname)
  if not pick then
    pick = T.Window("QuesticusLFGRole", 300, 120, "Find a group", nil)
    pick:SetFrameStrata("DIALOG")
    pick.text = T.Text(pick, 12, T.c.text)
    pick.text:SetPoint("TOPLEFT", 14, -34)
    pick.text:SetPoint("RIGHT", -14, 0)
    pick.text:SetJustifyH("LEFT")
    pick.btns = {}
    local x = 14
    for _, role in ipairs({ "tank", "healer", "dps" }) do
      local b = T.Button(pick, ROLES[role], 84, 24)
      b:SetPoint("BOTTOMLEFT", x, 14)
      x = x + 92
      b:SetScript("OnClick", function()
        pick:Hide()
        if pick.act then LF:List(pick.act, role, pick.dname) end
      end)
      pick.btns[role] = b
    end
  end
  pick.act, pick.dname = act, dname
  pick.text:SetText(("Your role for %s?"):format(Q.Color(T.HEX.gold, dname or act.name)))
  -- (roles your class can't fill are greyed)
  local can = { tank = true, healer = true, dps = true }
  if C_SpecializationInfo == nil and UnitClass then
    local _, cls = UnitClass("player")
    local TANK = { WARRIOR = 1, PALADIN = 1, DRUID = 1, DEATHKNIGHT = 1, MONK = 1, DEMONHUNTER = 1, SHAMAN = 1 }
    local HEAL = { PRIEST = 1, PALADIN = 1, DRUID = 1, SHAMAN = 1, MONK = 1, EVOKER = 1 }
    can.tank, can.healer = TANK[cls] ~= nil, HEAL[cls] ~= nil
  end
  for role, b in pairs(pick.btns) do if b.SetEnabled then b:SetEnabled(can[role]) end end
  pick:Show()
end

-- the button: find the dungeon in the group finder, then list (asking the role first)
function LF:Find(area, name)
  local dname = name
  if not dname and Q.Dungeons then
    for _, e in ipairs(Q.Dungeons:List()) do if e.area == area then dname = e.name end end
  end
  if not (C_LFGList and C_LFGList.CreateListing) then
    Q:Print("The group finder isn't available here.")
    return
  end
  if C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then
    Q:Print("You're already listed in the group finder.")
    openFinder()
    return
  end
  if IsInGroup and IsInGroup() and UnitIsGroupLeader and not UnitIsGroupLeader("player") then
    Q:Print("Only your group's leader can list the group.")
    return
  end
  local act = LF.Activity(dname or "")
  if not act then
    Q:Print(("%s isn't in the group finder's list - the group finder is open, search for it there."):format(dname or "This dungeon"))
    openFinder()
    return
  end
  local role = cfg().role
  if role == "tank" or role == "healer" or role == "dps" then
    LF:List(act, role, dname)
  else
    rolePrompt(act, dname)
  end
end

Q:Command("lfg", "list yourself in the group finder for the dungeon you're working on", function()
  local s = Q.Planner and Q.Planner.steps
  for _, st in ipairs(s or {}) do
    local area, name = Q.Guide.DungeonOf(st)
    if area then LF:Find(area, name); return end
  end
  if Q.char.dmode then LF:Find(Q.char.dmode) else Q:Print("No dungeon on your route.") end
end)
