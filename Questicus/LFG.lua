-- Find a group: lists you in the game's group finder for a dungeon, after asking your role (or using
-- the one you chose in the options). The playstyle is Relaxed unless you pick another in the options.
local Q = Questicus
local L = Q.L
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
      if not best or (best.heroic and not heroic) then best = { id = a.id, name = a.name, cat = a.cat, heroic = heroic } end
    end
  end
  if not best then
    -- a looser match: the group finder's name contains the dungeon's
    local w = norm(name)
    for _, a in ipairs(activities()) do
      if norm(a.name):find(w, 1, true) and not norm(a.name):find("heroic") then best = { id = a.id, name = a.name, cat = a.cat }; break end
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
local ROLEKEY = { tank = "Tank", healer = "Healer", dps = "DPS" }

-- ------------------------------------------------------------------ listing, through the game's own buttons
-- The game only creates a listing from its own code: C_LFGList.CreateListing called by an addon does
-- nothing (tried 2026-11-24), and if addon code opens the group finder or touches its form, the
-- game's own buttons stop working there too (ForeverDungeonJournal found searches hang until /reload).
-- So Questicus never calls into the window. The role buttons are secure buttons that run a macro of
-- /clicks; each /click hits a small hidden secure button of ours that, just before it fires, is pointed
-- at the game's button for the next step (eye button, Listing tab, the category, the dungeon's tick
-- box, your role's tick box, List). The game's code does all the work, as if you'd clicked each one.
LF.diag = {}
local want = {}
local function LFm() return LFGListingFrame end
local function microBtn() return _G.LFGMicroButton or _G.LFDMicroButton end
local function finderShown() return LFGParentFrame and LFGParentFrame:IsShown() end
local function listed() return C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() end
-- the dungeon's row (or its group's row) in the listing's scroll list, if it's on screen
local function rowFor(pred)
  local L = LFm()
  local sb = L and L.ActivityView and L.ActivityView.ScrollBox
  if not (sb and sb.EnumerateFrames and L.ActivityView:IsShown()) then return end
  for _, f in sb:EnumerateFrames() do
    local node = f.GetElementData and f:GetElementData()
    local d = node and node.GetData and node:GetData()
    if d and pred(d, node) then return f, node end
  end
end
local STEPS = {
  { "Open", function()          -- the group finder (the game's own eye / micro button)
      if finderShown() then return nil, "already open" end
      return microBtn(), "eye button"
    end },
  { "Tab", function()           -- its listing tab
      local L = LFm()
      if L and L:IsShown() then return nil, "on the listing tab" end
      return _G.LFGParentFrameTab1, "listing tab"
    end },
  { "Cat", function()           -- the dungeons category
      local L = LFm()
      if not (L and L.CategoryView) then return nil, "no listing window" end
      if L.GetCategorySelection and L:GetCategorySelection() == want.cat and L.ActivityView:IsShown() then return nil, "category picked" end
      for _, b in ipairs(L.CategoryView.CategoryButtons or {}) do
        if b.categoryID == want.cat then return b, "category " .. tostring(want.cat) end
      end
      return nil, "category " .. tostring(want.cat) .. L[" not found"]
    end },
  { "Exp", function()           -- the dungeon's group, if folded
      local gid = want.group
      if not gid or gid == 0 then return nil, "no group" end
      local f, node = rowFor(function(d) return d.activityGroupID == gid and d.activityID == nil end)
      if f and node.IsCollapsed and node:IsCollapsed() then return f.ExpandOrCollapseButton, "unfold group" end
      return nil, f and L["group open"] or L["group row not shown"]
    end },
  { "Act", function()           -- tick the dungeon
      local f = rowFor(function(d) return d.activityID == want.id end)
      if not f then return nil, "dungeon row not on screen" end
      if f.CheckButton:GetChecked() then return nil, "dungeon ticked" end
      return f.CheckButton, "tick dungeon"
    end },
}
for _, r in ipairs({ "tank", "healer", "dps" }) do
  STEPS[#STEPS + 1] = { "R" .. r, function()   -- your role ticked, the others not
    local L = LFm()
    local rb = L and L.SoloRoleButtons and L.SoloRoleButtons:IsShown() and L.SoloRoleButtons[ROLEKEY[r]]
    if not rb then return nil, "no role boxes (in a group?)" end
    local cb = rb.CheckButton
    local on = want.role == r
    if not cb:IsEnabled() then return nil, r .. L[" not allowed"] end
    if (cb:GetChecked() and true or false) ~= on then return cb, (on and "tick " or "untick ") .. r end
    return nil, r .. " ok"
  end }
end
STEPS[#STEPS + 1] = { "Post", function()      -- List
  local L = LFm()
  local pb = L and L.PostButton
  if not pb then return nil, "no List button" end
  if not pb:IsEnabled() then return nil, "List button disabled" end
  return pb, "List"
end }

local macro = {}
for _, st in ipairs(STEPS) do
  local name = "QuesticusLFGStep" .. st[1]
  local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
  b:SetAttribute("type", "qcnone")
  b:SetScript("PreClick", function(self)
    if InCombatLockdown and InCombatLockdown() then return end
    local ok, target, why = pcall(st[2])
    if not ok then target, why = nil, "error: " .. tostring(target) end
    LF.diag.steps = LF.diag.steps or {}
    LF.diag.steps[#LF.diag.steps + 1] = st[1] .. ": " .. tostring(why)
    if target then
      self:SetAttribute("type", "click")
      self:SetAttribute("clickbutton", target)
    else
      self:SetAttribute("type", "qcnone")
      self:SetAttribute("clickbutton", nil)
    end
  end)
  macro[#macro + 1] = "/click " .. name
end
LF.MACRO = table.concat(macro, "\n")

local function report(dname)
  C_Timer.After(1.5, function()
    LF.diag.listed = listed() and true or false
    Q.db.lfgDiag = LF.diag
    if LF.diag.listed then
      Q:Print(L("Listed for %s as %s. Players can now find you in the group finder.", dname, ROLES[want.role] or want.role))
    else
      Q:Print(L("Not listed yet for %s - press your role again (the first press opens the group finder). /qc lfg why shows each step.", dname))
    end
  end)
end

-- the role prompt: its three buttons are the secure ones (a real click is what lets the game list you)
local pick
local function roleButton(parent, role)
  local b = CreateFrame("Button", "QuesticusLFGRole" .. role, parent, "SecureActionButtonTemplate")
  b:SetSize(84, 24)
  b.bg = T.RFill(b, T.c.bg2)
  T.Border(b, T.c.line)
  b.label = T.Text(b, 12, T.c.gold)
  b.label:SetPoint("CENTER")
  b.label:SetText(ROLES[role])
  b:RegisterForClicks("AnyUp")
  b:SetAttribute("type", "macro")
  b:SetAttribute("macrotext", LF.MACRO)
  b:SetScript("PreClick", function()
    want.role = role
    LF.cfg().lastRole = role
    LF.diag = { name = want.name, act = want.id, cat = want.cat, role = role, t = time and time(), steps = {} }
  end)
  b:SetScript("PostClick", function() report(want.name or "the dungeon") end)
  b:SetScript("OnEnter", function(s) T.SetBorderColor(s, T.c.accent[1], T.c.accent[2], T.c.accent[3], 1) end)
  b:SetScript("OnLeave", function(s) local on = LF.cfg().role == role; T.SetBorderColor(s, on and 0.75 or T.c.line[1], on and 0.45 or T.c.line[2], on and 1 or T.c.line[3], 1) end)
  return b
end
local function rolePrompt(act, dname)
  if InCombatLockdown and InCombatLockdown() then Q:Print(L["Can't list you in combat - try again after the fight."]); return end
  if not pick then
    pick = T.Window("QuesticusLFGRole", 300, 128, "Find a group", nil)
    pick:SetFrameStrata("DIALOG")
    pick.text = T.Text(pick, 12, T.c.text)
    pick.text:SetPoint("TOPLEFT", 14, -32)
    pick.text:SetPoint("RIGHT", -14, 0)
    pick.text:SetJustifyH("LEFT")
    pick.btns = {}
    local x = 14
    for _, role in ipairs({ "tank", "healer", "dps" }) do
      local b = roleButton(pick, role)
      b:SetPoint("BOTTOMLEFT", x, 14)
      x = x + 92
      pick.btns[role] = b
    end
    -- (secure buttons can't be hidden in combat: close the prompt as a fight starts)
    pick:RegisterEvent("PLAYER_REGEN_DISABLED")
    pick:SetScript("OnEvent", function(self) self:Hide() end)
  end
  local ai = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(act.id)
  want.id, want.cat, want.name = act.id, act.cat or (ai and ai.categoryID), dname or act.name
  want.group = ai and (ai.groupFinderActivityGroupID or ai.activityGroupID)
  pick.text:SetText(L("List yourself for %s as:", Q.Color(T.HEX.gold, act.name)) ..
    "\n" .. Q.Color(T.HEX.dim, L["The group finder opens; press again if it isn't listed yet."]))
  local pre = LF.cfg().role
  for role, b in pairs(pick.btns) do
    local on = pre == role
    T.SetBorderColor(b, on and 0.75 or T.c.line[1], on and 0.45 or T.c.line[2], on and 1 or T.c.line[3], 1)
  end
  pick:Show()
end
LF.Prompt = rolePrompt

-- the button: find the dungeon in the group finder, then ask the role (the click on it lists you)
function LF:Find(area, name)
  local dname = name
  if not dname and Q.Dungeons then
    for _, e in ipairs(Q.Dungeons:List()) do if e.area == area then dname = e.name end end
  end
  if not (C_LFGList and C_LFGList.GetAvailableCategories) then
    Q:Print(L["The group finder isn't available here."])
    return
  end
  if IsInGroup and IsInGroup() and UnitIsGroupLeader and not UnitIsGroupLeader("player") then
    Q:Print(L["Only your group's leader can list the group."])
    return
  end
  local act = LF.Activity(dname or "")
  if not act then
    Q:Print(L("%s isn't in the group finder's list.", dname or L["This dungeon"]))
    return
  end
  rolePrompt(act, dname)
end

-- ------------------------------------------------------------------ the Group finder button
-- Opens the game's group finder. Addon code can't open it itself without breaking it (its searches
-- then hang until /reload), so an invisible secure button lies over ours and presses the game's own
-- group finder (eye) button. It sits on UIParent and is moved / hidden only out of combat.
function LF.Overlay(btn)
  if btn.qcOverlay then return end
  local o = CreateFrame("Button", "QuesticusGroupFinderButton", UIParent, "SecureActionButtonTemplate")
  btn.qcOverlay = o
  -- (secure buttons act on the press or the release depending on the ActionButtonUseKeyDown setting:
  -- registered for both, the game uses the one that setting says)
  o:RegisterForClicks("AnyUp", "AnyDown")
  o:SetAttribute("type", "macro")
  o:Hide()
  o:SetScript("PreClick", function(self, _, down)
    if InCombatLockdown and InCombatLockdown() then return end
    local m = microBtn()
    -- (only one of press / release may run it, or the window opens and shuts again)
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    local mine = (down and true or false) == (keyDown and true or false)
    self:SetAttribute("macrotext", (mine and m and m:GetName()) and ("/click " .. m:GetName()) or "")
  end)
  o:SetScript("PostClick", function(_, _, down)
    if not microBtn() then Q:Print(L["Couldn't find the game's group finder button - open it from the micro menu."]) end
    if down then return end
    C_Timer.After(0.4, function()
      if not finderShown() then
        local m = microBtn()
        Q:Print(L("The group finder didn't open (button %s, key-down %s).", tostring(m and m:GetName()),
          tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown"))))
      end
    end)
  end)
  o:SetScript("OnEnter", function() local f = btn:GetScript("OnEnter"); if f then f(btn) end end)
  o:SetScript("OnLeave", function() local f = btn:GetScript("OnLeave"); if f then f(btn) end end)
  local function place()
    if InCombatLockdown and InCombatLockdown() then return end
    if not btn:IsVisible() then if o:IsShown() then o:Hide() end; return end
    local l, b, w, h = btn:GetLeft(), btn:GetBottom(), btn:GetWidth(), btn:GetHeight()
    if not l then return end
    local s = btn:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    o:SetSize(w * s, h * s)
    -- (just above the button, whatever window it's in)
    if o:GetFrameStrata() ~= btn:GetFrameStrata() then o:SetFrameStrata(btn:GetFrameStrata()) end
    if o:GetFrameLevel() <= btn:GetFrameLevel() then o:SetFrameLevel(btn:GetFrameLevel() + 5) end
    if not o:IsShown() then o:Show() end
  end
  btn:HookScript("OnUpdate", place)
  btn:HookScript("OnHide", function() if not (InCombatLockdown and InCombatLockdown()) then o:Hide() end end)
  -- (in combat the overlay is hidden; a click then lands on the button itself)
  btn:SetScript("OnClick", function() Q:Print(L["The group finder can't be opened by Questicus in combat - try after the fight."]) end)
end

-- ------------------------------------------------------------------ any secure button over one of ours
-- Q.SecureOverlay(btn, name, macroFn, combatMsg): an invisible secure button lies over btn and runs the
-- macro text macroFn() returns (e.g. "/use item:6948") - things only a real click may do. Placed
-- and hidden only out of combat; in combat a click lands on btn itself and prints combatMsg.
function Q.SecureOverlay(btn, name, macroFn, combatMsg)
  if btn.qcOverlay then return btn.qcOverlay end
  local o = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
  btn.qcOverlay = o
  o:RegisterForClicks("AnyUp", "AnyDown")
  o:SetAttribute("type", "macro")
  o:Hide()
  o:SetScript("PreClick", function(self, _, down)
    if InCombatLockdown and InCombatLockdown() then return end
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    local mine = (down and true or false) == (keyDown and true or false)
    self:SetAttribute("macrotext", mine and (macroFn() or "") or "")
  end)
  o:SetScript("OnEnter", function() local f = btn:GetScript("OnEnter"); if f then f(btn) end end)
  o:SetScript("OnLeave", function() local f = btn:GetScript("OnLeave"); if f then f(btn) end end)
  local function place()
    if InCombatLockdown and InCombatLockdown() then return end
    if not btn:IsVisible() then if o:IsShown() then o:Hide() end; return end
    local l, b, w, h = btn:GetLeft(), btn:GetBottom(), btn:GetWidth(), btn:GetHeight()
    if not l then return end
    local s = btn:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    o:SetSize(w * s, h * s)
    if o:GetFrameStrata() ~= btn:GetFrameStrata() then o:SetFrameStrata(btn:GetFrameStrata()) end
    if o:GetFrameLevel() <= btn:GetFrameLevel() then o:SetFrameLevel(btn:GetFrameLevel() + 5) end
    if not o:IsShown() then o:Show() end
  end
  btn:HookScript("OnUpdate", place)
  btn:HookScript("OnHide", function() if not (InCombatLockdown and InCombatLockdown()) then o:Hide() end end)
  btn:SetScript("OnClick", function() Q:Print(combatMsg or "Not in combat - try after the fight.") end)
  return o
end
