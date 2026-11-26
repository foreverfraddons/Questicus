-- Questicus author tools: notes on route steps and saved route rules ("do this right after that").
-- Only the addon's author can write them (checked by character and realm); they are saved in the
-- author's QuesticusAuthor saved variables and copied into AuthorNotes.lua, which ships with the
-- addon. Everyone else only reads the shipped ones - their own QuesticusAuthor is never read.
local Q = Questicus
local T, D, QS, P = Q.T, Q.Data, Q.Quests, Q.Planner
local A = {}
Q.Author = A

local AUTHOR_REALM = "CAMWOWUS2Realm10RPPvP"
local AUTHOR_NAMES = {
  ["Baelgor"] = true, ["Baelgor Spiritbane"] = true,
  ["Aldric"] = true, ["Aldric Hollowvow"] = true,
  ["Get"] = true, ["Get Mailed"] = true,
}

local function who()
  local name = (UnitName and UnitName("player")) or ""
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ((GetRealmName and GetRealmName()) or ""):gsub("%s", "")
  return name, realm or ""
end
function A:IsAuthor()
  if A.author ~= nil then return A.author end
  local name, realm = who()
  if name == "" or realm == "" then return false end       -- not known yet: ask again later
  A.author = (AUTHOR_NAMES[name] or AUTHOR_NAMES[name:match("^(%S+)") or ""]) and realm == AUTHOR_REALM or false
  return A.author
end

local function shipped() return Q.AuthorData or { notes = {}, hints = {} } end
local function mine()
  if not A:IsAuthor() then return nil end
  QuesticusAuthor = QuesticusAuthor or {}
  QuesticusAuthor.notes = QuesticusAuthor.notes or {}
  QuesticusAuthor.hints = QuesticusAuthor.hints or {}
  return QuesticusAuthor
end
-- the author's own edits win over the shipped copy ("" / false = deleted)
local function get(kind, key)
  local m = mine()
  if m and m[kind][key] ~= nil then
    local v = m[kind][key]
    if v == false or v == "" then return nil end
    return v
  end
  return shipped()[kind][key]
end

-- ------------------------------------------------------------------ keys
function A.StepKey(s)
  if not s then return end
  if s.type == "fp" and s.node then return "fp:" .. s.node.id end
  if s.type == "fly" and s.to then return "fly:" .. s.to.id end
  if s.type == "buy" then return "buy:" .. (s.item or 0) end
  if s.type == "task" and s.key then return s.key end
  return s.type .. ":" .. ((s.quests and s.quests[1]) or s.item or 0)
end
-- every note key a step can carry (a bundle of quests: one per quest)
local function noteKeys(s)
  local out = {}
  if s.type == "accept" or s.type == "turnin" or s.type == "complete" then
    for _, id in ipairs(s.quests or {}) do out[#out + 1] = { s.type .. ":" .. id, id } end
  else
    local k = A.StepKey(s)
    if k then out[1] = { k } end
  end
  return out
end
function A:NotesFor(s)
  local out = {}
  if not s then return out end
  local keys = noteKeys(s)
  for _, k in ipairs(keys) do
    local n = get("notes", k[1])
    if n then
      local info = k[2] and #keys > 1 and QS:Info(k[2])
      out[#out + 1] = (info and (info.title .. ": ") or "") .. n
    end
  end
  return out
end
-- the author's fight notes for a boss (boss tracker)
function A:BossNote(name) return name and get("notes", "boss:" .. name:lower()) or nil end
-- the author's route rule: what comes right after `key`
function P.Hint(key) return key and get("hints", key) or nil end

-- the step before (flights aren't steps of their own in the plan)
local function prevKey(index)
  for i = index - 1, 1, -1 do
    local s = P.steps[i]
    if s and s.type ~= "fly" then return A.StepKey(s) end
  end
  return Q.char.lastDone
end

-- ------------------------------------------------------------------ what you really did last
Q:On("QUEST_ACCEPTED", function(a, b)
  local id = b or a
  if type(id) == "number" and id > 100 then Q.char.lastDone = "accept:" .. id end
end)
Q:On("QUEST_TURNED_IN", function(id)
  if type(id) == "number" then Q.char.lastDone = "turnin:" .. id end
end)

-- ------------------------------------------------------------------ note editor
local ed
local function editor()
  if ed then return ed end
  ed = T.Window("QuesticusNoteEditor", 420, 190, "Author note", nil)
  ed:SetFrameStrata("DIALOG")
  ed.what = T.Text(ed, 11, T.c.dim)
  ed.what:SetPoint("TOPLEFT", 14, -32)
  ed.what:SetPoint("RIGHT", -14, 0)
  ed.what:SetWordWrap(false)
  local box = CreateFrame("Frame", nil, ed)
  box:SetPoint("TOPLEFT", 12, -50)
  box:SetPoint("BOTTOMRIGHT", -12, 44)
  T.RFill(box, { T.c.bg[1] * 0.6, T.c.bg[2] * 0.6, T.c.bg[3] * 0.6, 1 }, 4)
  T.Border(box, T.c.line, 4)
  ed.input = CreateFrame("EditBox", nil, box)
  ed.input:SetMultiLine(true)
  ed.input:SetAutoFocus(true)
  ed.input:SetFontObject(ChatFontNormal)
  ed.input:SetPoint("TOPLEFT", 6, -6)
  ed.input:SetPoint("BOTTOMRIGHT", -6, 6)
  ed.input:SetMaxLetters(400)
  ed.input:SetScript("OnEscapePressed", function() ed:Hide() end)
  ed.save = T.Button(ed, "Save", 90, 22)
  ed.save:SetPoint("BOTTOMRIGHT", -12, 12)
  ed.save:SetScript("OnClick", function()
    local txt = (ed.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    A:SetNote(ed.key, txt)
    ed:Hide()
  end)
  ed.del = T.Button(ed, "Delete", 80, 22)
  ed.del:SetPoint("RIGHT", ed.save, "LEFT", -8, 0)
  ed.del:SetScript("OnClick", function() A:SetNote(ed.key, ""); ed:Hide() end)
  return ed
end
function A:Edit(key, label)
  if not A:IsAuthor() then return end
  local e = editor()
  e.key = key
  e.what:SetText(label or key)
  e.input:SetText(get("notes", key) or "")
  e:Show()
  if e.input.SetFocus then e.input:SetFocus() end
end
function A:SetNote(key, txt)
  local m = mine()
  if not (m and key) then return end
  m.notes[key] = (txt ~= "") and txt or false
  Q:Print((txt ~= "") and ("note saved for " .. key) or ("note removed from " .. key))
  if Q.Guide then Q.Guide:Refresh() end
end
function A:SetHint(after, key)
  local m = mine()
  if not (m and after) then return end
  m.hints[after] = key or false
  if Q.Planner then Q.Planner:Build() end
end

-- ------------------------------------------------------------------ step menu (author only)
function A:MenuItems(s, index, add)
  if not A:IsAuthor() then return end
  local keys = noteKeys(s)
  for _, k in ipairs(keys) do
    local info = k[2] and QS:Info(k[2])
    local label = (#keys > 1 and info) and (" - " .. info.title) or ""
    local has = get("notes", k[1])
    add((has and "Edit note" or "Add note") .. label, "Author: a note on this step, saved into the addon for everyone",
      function() A:Edit(k[1], (Q.Guide and Q.Guide.StepText(s, true) or k[1]) .. label) end)
  end
  local key, before = A.StepKey(s), prevKey(index)
  if key and before and before ~= key then
    if get("hints", before) == key then
      add("Remove route rule", "Author: stop forcing this right after " .. before, function() A:SetHint(before, nil) end)
    else
      add("Route: always right after the step before", "Author: saved into the addon - routes do this right after " .. before,
        function() A:SetHint(before, key); Q:Print(("route rule saved: %s right after %s"):format(key, before)) end)
    end
  end
end

Q:Command("author", "author notes and route rules: who's allowed, how many are saved", function()
  local name, realm = who()
  A.author = nil
  if not A:IsAuthor() then
    Q:Print(("author tools are off for %s-%s (only the addon's author can add notes and route rules)"):format(name, realm))
    return
  end
  local m = mine()
  local n, h = 0, 0
  for _, v in pairs(m.notes) do if v then n = n + 1 end end
  for _, v in pairs(m.hints) do if v then h = h + 1 end end
  Q:Print(("author tools on for %s-%s: %d note(s), %d route rule(s) saved this session and before (shipped: AuthorNotes.lua)"):format(name, realm, n, h))
end)
