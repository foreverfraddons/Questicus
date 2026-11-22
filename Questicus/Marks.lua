-- Questicus marks: a skull over the mobs of the step you're on, an X over other mobs you still need for a quest in your log (kills and the mobs that
-- drop your quest items), a star over NPCs with a quest for you. Drawn on nameplates (the game's
-- real raid markers can't be set by addons in WoW Forever).
local Q = Questicus
local D, QS, P = Q.Data, Q.Quests, Q.Planner
local M = {}
Q.Marks = M

local CROSS, STAR, SKULL = 7, 1, 8
local ICON = { [CROSS] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
  [STAR] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
  [SKULL] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" }
M.ICON, M.SKULL = ICON, SKULL
local need, givers, main = {}, {}, {}   -- npc id -> quest title
M.need, M.givers, M.main = need, givers, main
local overlays = {}               -- nameplate -> texture frame

local function npcID(unit)
  local guid = Q.UnitGUID(unit)
  local kind, id = Q.ParseGUID(guid)
  if kind == "Creature" or kind == "Vehicle" then return id, guid end
end

-- what to mark, rebuilt when the quest log or the route changes
M.ver = 0
function M:Rebuild()
  M.ver = M.ver + 1
  wipe(need); wipe(givers)
  if not (D:Ready() and QS.pool) then return end
  for id, e in pairs(QS.log) do
    if not e.complete then
      local info = QS:Info(id)
      local title = (info and info.title) or e.title or ""
      local x = info and info.x or (D:QuestExtra(id) or {})
      local m = P.Meta(id)
      if m and m.lines then
        -- only objectives that aren't finished yet: done with the entrails = no more X on those mobs
        local open = P.OpenLines(id, m)
        for li, l in ipairs(m.lines) do
          if open[li] then
            if l.kind == "kill" then need[tonumber(l.key:sub(2))] = title end
            if l.kind == "loot" then
              for _, s in ipairs(D:ItemSources(tonumber(l.key:sub(2)))) do    -- every mob that can drop it
                if s.key:sub(1, 1) == "c" and not s.vendor then need[tonumber(s.key:sub(2))] = title end
              end
            end
          end
        end
        if open[0] or #m.lines == 0 then
          for _, k in ipairs(D:QuestSources(id)) do
            if k:sub(1, 1) == "c" then need[tonumber(k:sub(2))] = title end
          end
        end
      else
        for _, c in ipairs(x[8] or {}) do need[c] = title end
        for _, it in ipairs(x[10] or {}) do
          for _, s in ipairs(D:ItemSources(it)) do
            if s.key:sub(1, 1) == "c" and not s.vendor then need[tonumber(s.key:sub(2))] = title end
          end
        end
      end
    else
      for _, k in ipairs((QS:Info(id) or {}).enders or {}) do
        if k:sub(1, 1) == "c" then givers[tonumber(k:sub(2))] = "Turn in: " .. (e.title or "") end
      end
    end
  end
  for _, s in ipairs(P.steps or {}) do
    if s.type == "accept" and s.point and s.point.key and s.point.key:sub(1, 1) == "c" then
      givers[tonumber(s.point.key:sub(2))] = givers[tonumber(s.point.key:sub(2))] or ("Quest: " .. (s.title or ""))
    end
  end
  M:RebuildMain(true)
  M:RefreshPlates()
end

-- the mobs of the step you're on (the guide's current step): skull instead of X
local mainSig
function M:RebuildMain(force)
  local s = P.steps and P.steps[(Q.Guide and Q.Guide.focus) or 1]
  local sig = s and (s.type .. ":" .. table.concat(s.quests or {}, ",")) or ""
  if sig == mainSig and not force then return end
  mainSig = sig
  M.ver = (M.ver or 0) + 1
  wipe(main)
  if s and s.type == "complete" then
    for _, e in ipairs(P.StepPoints(s)) do
      local k = e.p.key
      if type(k) == "string" and k:sub(1, 1) == "c" then main[tonumber(k:sub(2))] = (QS:Info(e.id) or {}).title or "" end
    end
  end
  if not force then M:RefreshPlates() end
end

function M:Kind(unit)
  local id = npcID(unit)
  if not id then return end
  -- attackable or not: some objectives are friendly NPCs (heal the Injured Deathguard)
  local dead = UnitIsDead and UnitIsDead(unit)
  if main[id] and not dead then return SKULL, main[id] .. " (current step)" end
  if need[id] and not dead then return CROSS, need[id] end
  if givers[id] and not (UnitCanAttack and UnitCanAttack("player", unit)) then return STAR, givers[id] end
end

-- ------------------------------------------------------------------ nameplates
local function overlay(plate)
  local o = overlays[plate]
  if not o then
    o = CreateFrame("Frame", nil, plate)
    o:SetSize(22, 22)
    o:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    o.tex = o:CreateTexture(nil, "OVERLAY")
    o.tex:SetAllPoints()
    overlays[plate] = o
  end
  return o
end

function M:Plate(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
  local kind = Q.db.marks.plates and not (Q.CollectOnly and Q.CollectOnly()) and M:Kind(unit)
  local o = overlays[plate]
  if not kind then if o then o:Hide() end return end
  o = overlay(plate)
  o.tex:SetTexture(ICON[kind])
  o:Show()
end

function M:RefreshPlates()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then M:Plate(unit) elseif overlays[plate] then overlays[plate]:Hide() end
  end
end

-- Real raid markers are NOT possible: SetRaidTarget is protected in WoW Forever (ADDON_ACTION_FORBIDDEN
-- when an addon calls it), so Questicus only draws its own X / star icons.
function M:Raid() end

Q:On("NAME_PLATE_UNIT_ADDED", function(unit) M:Plate(unit) end)
Q:On("NAME_PLATE_UNIT_REMOVED", function(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  if plate and overlays[plate] then overlays[plate]:Hide() end
end)
Q:On("QC_QUESTS_CHANGED", function() Q.Throttle("marks", 0.5, function() M:Rebuild() end) end)
Q:On("QC_PLAN_UPDATED", function() Q.Throttle("marks", 0.5, function() M:Rebuild() end) end)
Q:On("QC_TARGET_CHANGED", function() Q.Throttle("marksmain", 0.3, function() M:RebuildMain() end) end)

-- ------------------------------------------------------------------ mob info (ForeverDB, from Drop Tables)
-- gold = {[npc] = {average copper per kill, smallest, largest, kills}}; skin = {[item] = {npc, chance, ...}}
local skinBy                      -- [npc] = { {item, chance}, ... } built once
local function skinsOf(npc)
  local db = Q.Data and Q.Data.db
  if not (db and db.skin) then return nil end
  if not skinBy then
    skinBy = {}
    for item, t in pairs(db.skin) do
      for k = 1, #t - 1, 2 do
        local l = skinBy[t[k]] or {}
        l[#l + 1] = { item, t[k + 1] }
        skinBy[t[k]] = l
      end
    end
    for _, l in pairs(skinBy) do table.sort(l, function(x, y) return x[2] > y[2] end) end
  end
  return skinBy[npc]
end
local SKINNING_LINE = 393
local function canSkin()
  if GetProfessions and GetProfessionInfo then
    local ok, a, b = pcall(GetProfessions)
    for _, i in ipairs(ok and { a, b } or {}) do
      local ok2, _, _, _, _, _, _, line = pcall(GetProfessionInfo, i)
      if ok2 and line == SKINNING_LINE then return true end
    end
  end
  if IsSpellKnown then
    for _, s in ipairs({ 8613, 8617, 8618, 10768 }) do if IsSpellKnown(s) then return true end end
  end
  return false
end
local function npcOf(unit)
  local g = UnitGUID and UnitGUID(unit)
  local kind, id = g and g:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if kind == "Creature" then return tonumber(id) end
end
local function money(c)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  return c .. "c"
end
-- money per kill (and what skinning gives, if you can skin) on mobs you can fight
local function mobInfo(tt, unit)
  if Q.db.marks.mobInfo == false then return end
  if not (UnitCanAttack and UnitCanAttack("player", unit)) or UnitIsPlayer(unit) then return end
  local npc = npcOf(unit)
  local db = npc and Q.Data and Q.Data.db
  if not db then return end
  local g = db.gold and db.gold[npc]
  if g and g[1] and g[1] > 0 then
    tt:AddLine("Questicus: about " .. money(g[1]) .. " per kill", 0.25, 0.82, 0.79)
  end
  local sk = canSkin() and skinsOf(npc)
  if sk and #sk > 0 then
    local parts = {}
    for k = 1, math.min(3, #sk) do
      local id, ch = sk[k][1], sk[k][2]
      local name = Q.GetItemInfo(id) or (Q.Data.Name and Q.Data:Name("i" .. id)) or ("item " .. id)
      parts[#parts + 1] = name .. " " .. math.floor(ch / 100 + 0.5) .. "%"
    end
    tt:AddLine("Skinning: " .. table.concat(parts, ", "), 0.85, 0.7, 0.45)
  end
end

-- tooltip line on units we mark (modern tooltip API; never in combat, never on forbidden tooltips)
local function tipLine(tt)
  if (Q.CollectOnly and Q.CollectOnly()) then return end        -- collection mode: Questicus adds nothing
  if not tt or (tt.IsForbidden and tt:IsForbidden()) or (InCombatLockdown and InCombatLockdown()) then return end
  local ok, _, unit = pcall(tt.GetUnit, tt)
  if not ok or type(unit) ~= "string" then return end
  local ok2, kind, why = pcall(M.Kind, M, unit)
  if ok2 and kind then tt:AddLine("|T" .. ICON[kind] .. ":12|t Questicus: " .. why, 0.25, 0.82, 0.79) end
  pcall(mobInfo, tt, unit)
end
Q:Command("mobinfo", "money per kill and skinning on mob tooltips on / off", function()
  Q.db.marks.mobInfo = Q.db.marks.mobInfo == false
  Q:Print("mob tooltips: " .. (Q.db.marks.mobInfo and "on" or "off"))
end)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, tipLine)
elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
  GameTooltip:HookScript("OnTooltipSetUnit", tipLine)
end
