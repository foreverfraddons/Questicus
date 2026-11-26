-- Questicus: "What's new" (patch notes after an update) and the new-version notice.
-- Patch notes come from Changelog.lua. The first login after an update shows every version you
-- haven't seen yet. Addons can't reach the internet, so a new version is found the way DBM / BigWigs
-- do it: Questicus users in your guild and group tell each other which version they run.
local Q = Questicus
local L = Q.L
local T = Q.T
local N = {}
Q.News = N

local PREFIX = "Questicus"

-- "0.9.14" -> comparable numbers; "next" (an unreleased build) counts as this version
local function parts(v)
  if v == "next" then v = Q.version end
  local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
  if not a then return end
  return tonumber(a), tonumber(b), tonumber(c) or 0
end
function N.Newer(x, y)            -- is version x newer than y?
  local a1, b1, c1 = parts(x)
  local a2, b2, c2 = parts(y)
  if not a1 then return false end
  if not a2 then return true end
  if a1 ~= a2 then return a1 > a2 end
  if b1 ~= b2 then return b1 > b2 end
  return c1 > c2
end

-- ------------------------------------------------------------------ patch notes window
local SECTIONS = {
  { "added", "New", "7fdc5a" },
  { "changed", "Changed", "e0b04a" },
  { "fixed", "Fixed", "6fb7ff" },
}

-- the notes for versions newer than `since` (all of them up to this version), newest first
function N.Entries(since)
  local out = {}
  for _, e in ipairs(Q.Changelog or {}) do
    local v = e.v == "next" and Q.version or e.v
    if not N.Newer(v, Q.version) and (not since or N.Newer(v, since)) then
      local any = false
      for _, s in ipairs(SECTIONS) do if e[s[1]] and #e[s[1]] > 0 then any = true end end
      if any then out[#out + 1] = { v = v, e = e } end
    end
  end
  return out
end

function N.Text(entries)
  local lines = {}
  for i, it in ipairs(entries) do
    if i > 1 then lines[#lines + 1] = " " end
    lines[#lines + 1] = Q.Color(T.HEX.accent, L["Version "] .. it.v)
    for _, s in ipairs(SECTIONS) do
      local list = it.e[s[1]]
      if list and #list > 0 then
        lines[#lines + 1] = Q.Color(s[3], s[2])
        for _, l in ipairs(list) do lines[#lines + 1] = Q.Color(T.HEX.dim, "  - ") .. Q.Color(T.HEX.white, l) end
      end
    end
  end
  return table.concat(lines, "\n")
end

local win
local function build()
  win = T.Window("QuesticusNews", 460, 400, "What's new in Questicus", Q.db.news or {})
  win:SetFrameStrata("DIALOG")
  win.head = T.Text(win, 11, T.c.dim)
  win.head:SetPoint("TOPLEFT", 14, -32)
  win.head:SetPoint("RIGHT", -14, 0)
  win.head:SetJustifyH("LEFT")
  win.scroll = CreateFrame("ScrollFrame", nil, win)
  win.scroll:SetPoint("TOPLEFT", 14, -54)
  win.scroll:SetPoint("BOTTOMRIGHT", -14, 46)
  -- (long notes scroll inside the window instead of running out over whatever is under it)
  if win.scroll.SetClipsChildren then win.scroll:SetClipsChildren(true) end
  win.body = CreateFrame("Frame", nil, win.scroll)
  win.body:SetSize(432, 1)
  win.scroll:SetScrollChild(win.body)
  win.text = T.Text(win.body, 12, T.c.text)
  win.text:SetPoint("TOPLEFT")
  win.text:SetWidth(426)
  win.text:SetJustifyH("LEFT")
  win.text:SetSpacing(3)
  if win.scroll.EnableMouseWheel then win.scroll:EnableMouseWheel(true) end
  win.scroll:SetScript("OnMouseWheel", function(self, d)
    local max = math.max(0, (win.body:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
  end)
  local ok = T.Button(win, "Got it", 90, 24)
  ok:SetPoint("BOTTOMRIGHT", -14, 12)
  ok:SetScript("OnClick", function() win:Hide() end)
  win.update = T.Text(win, 11, T.c.gold)
  win.update:SetPoint("BOTTOMLEFT", 14, 18)
  win.update:SetPoint("RIGHT", ok, "LEFT", -10, 0)
  win.update:SetJustifyH("LEFT")
end

-- since: show the versions after this one (nil = every version; "only" = just this version's)
function N:Show(since, title)
  if not win then build() end
  local entries
  if since == "only" then
    entries = {}
    for _, it in ipairs(N.Entries(nil)) do if it.v == Q.version then entries[#entries + 1] = it end end
  else
    entries = N.Entries(since)
  end
  if #entries == 0 then entries = N.Entries(nil) end
  win.head:SetText(title or ("You're on version " .. Q.version .. "."))
  win.text:SetText(N.Text(entries))
  win.body:SetHeight(math.max(1, (win.text:GetStringHeight() or 0) + 8))
  win.scroll:SetVerticalScroll(0)
  local newest = Q.db.newestSeen
  win.update:SetText(newest and N.Newer(newest, Q.version)
    and ("Version " .. newest .. " is out - update on CurseForge.") or "")
  win:Show()
end

-- first login after an update: the notes for every version you haven't seen
local function afterLogin()
  local seen = Q.db.newsSeen
  if seen == Q.version then return end
  -- not over the setup questions: once they're answered (checked again every few seconds)
  local sv = _G.QuesticusSurvey
  if not (Q.char and Q.char.surveyDone) or (sv and sv.IsShown and sv:IsShown()) then
    Q.After(3, afterLogin)
    return
  end
  Q.db.newsSeen = Q.version
  if Q.db.newsOff then return end
  if not seen then
    N:Show("only", "Thanks for using Questicus! Here's what's new in version " .. Q.version .. ".")
  elseif N.Newer(Q.version, seen) then
    N:Show(seen, "Questicus was updated to " .. Q.version .. ". Here's what changed since " .. seen .. ".")
  end
end

-- ------------------------------------------------------------------ new version notice
local told = false
local function tell(v)
  if told then return end
  told = true
  Q:Print(Q.Color(T.HEX.gold, L["A new version of Questicus is out: "] .. v .. " (you have " .. Q.version .. ").")
    .. " Update it on CurseForge.")
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, "Questicus " .. v .. " is available - update on CurseForge", 0.88, 0.69, 0.29)
  end
end

local function canSend()
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  local inInst, kind = IsInInstance and IsInInstance()
  if inInst and (kind == "raid" or kind == "party") and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return false end
  end
  return true
end

local lastSent = {}
local function send(channel, force)
  if not canSend() then return end
  local now = GetTime and GetTime() or 0
  if not force and lastSent[channel] and now - lastSent[channel] < 60 then return end
  lastSent[channel] = now
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. Q.version, channel)
end

local function groupChannel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

function N.Broadcast()
  if IsInGuild and IsInGuild() then send("GUILD") end
  local g = groupChannel()
  if g then send(g) end
end

function N.OnMessage(prefix, text, channel)
  if prefix ~= PREFIX or type(text) ~= "string" or Q.Secret(text) then return end
  local v = text:match("^V:(%d+%.%d+%.?%d*)$")
  if not v then return end
  if N.Newer(v, Q.version) then
    if not Q.db.newestSeen or N.Newer(v, Q.db.newestSeen) then Q.db.newestSeen = v end
    tell(v)
  elseif N.Newer(Q.version, v) and channel then
    send(channel)          -- they're behind: answer with ours so they hear about it
  end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
Q:On("CHAT_MSG_ADDON", function(prefix, text, channel) N.OnMessage(prefix, text, channel) end)

local groupWait = false
Q:On("GROUP_ROSTER_UPDATE", function()
  if groupWait then return end
  groupWait = true
  Q.After(5, function() groupWait = false; local g = groupChannel(); if g then send(g) end end)
end)

Q:On("PLAYER_LOGIN", function()
  Q.db.news = Q.db.news or {}
  -- seen a newer version last time and still not updated: remind once
  if Q.db.newestSeen and N.Newer(Q.db.newestSeen, Q.version) then
    Q.After(8, function() tell(Q.db.newestSeen) end)
  elseif Q.db.newestSeen then
    Q.db.newestSeen = nil
  end
  Q.After(6, afterLogin)
  Q.After(12, N.Broadcast)
end)

Q:Command("news", "what's new in this version (patch notes)", function() N:Show(nil) end)
Q:Command("newsoff", "don't open the patch notes by themselves after an update (toggle)", function()
  Q.db.newsOff = not Q.db.newsOff
  Q:Print(L["patch notes after an update: "] .. (Q.db.newsOff and "off (type /qc news to read them)" or "on"))
end)
