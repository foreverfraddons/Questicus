if Questicus and Questicus.mapStandalone then return end   -- (the standalone OpenMap addon is on: it runs the map)
--------------------------------------------------------------------------------
-- Init: loaded last. Settings at ADDON_LOADED; the map, options and slash
-- commands at PLAYER_LOGIN.
--
--   /qc map (/qc map)        options
--   /qc map status         what the map is doing
--   /qc map notes          map notes (paint areas, say what's there, export them)
--   /qc map debug          the debug overlay (frame rate, frame times, what Questicus Maps costs)
--   /qc map bench [zoom]   times the map at several zooms, each part off in turn (Bench.lua)
--   /qc map pins           the map pins (Pins.lua)
--   /qc map news           what's new in this version (News.lua)
--   /qc map draw           the quill: draw on the map (Sketch.lua)
--   /qc map dungeons       which map each dungeon entrance opens (Dungeons.lua)
--   /qc map entrance <name>  where you stand, as a dungeon entrance for tools/map-data (Dungeons.lua)
--   /qc map highlights     where the game draws each zone's highlight, for tools/map-preview (Debug.lua)
--------------------------------------------------------------------------------

local ADDON, ns = ...
if ns.loadMs.start then ns.loadMs.files = debugprofilestop() - ns.loadMs.start end

local function Options()
	local mod = ns:GetModule("worldmap")
	local args = mod.Options and mod:Options() or {}
	args.enabled = { type = "toggle", name = ns.L["Enable Questicus Maps"], order = 0, width = "full",
		desc = ns.L["Turning Questicus Maps off takes a reload."],
		get = function() return mod.db.enabled end,
		set = function(_, v) mod.db.enabled = v; ns:Print(ns.L["Takes effect after a /reload."]) end }
	args.padWaits = { type = "description", order = 0.5, fontSize = "medium",
		name = function() return "|cffff8040" .. mod.PadOffText() .. "|r" end,
		hidden = function() return not mod.padWaits or (mod.PadViewOn and mod.PadViewOn()) or false end }
	return { type = "group", name = "|cff" .. ns.ACCENT .. "Questicus Maps|r " .. ns.version, args = args }
end

-- Questicus Maps' settings are the map's own menu (Panel.lua); with the map off (no menu), the options window,
-- which can turn it back on
local function OpenOptions()
	local mod = ns:GetModule("worldmap")
	if mod.enabled and mod.OpenMenu and mod:OpenMenu() then return end
	local ACD = LibStub("AceConfigDialog-3.0", true)
	if ACD then ACD:Open("Questicus Maps") end
end
ns.OpenOptions = OpenOptions

local function Slash(msg)
	local raw = (msg or ""):match("^%s*(.-)%s*$")
	msg = raw:lower()
	local mod = ns:GetModule("worldmap")
	local word, rest = msg:match("^(%S+)%s+(.+)$")
	local takes = { bench = true, entrance = true }  -- (/qc map bench 16: at that zoom; /qc map entrance Dire Maul - East)
	if takes[word] then msg, rest = word, raw:match("^%S+%s+(.+)$") end
	local run = {
		status = "Diag", paint = "TogglePaint", notes = "TogglePaint", debug = "ToggleDebugOverlay",
		bench = "Bench", pins = "TogglePins", news = "ToggleNews", entrance = "Entrance", draw = "ToggleSketch", dungeons = "DungeonDiag", bosses = "ToggleBossPlacer", forgetflights = "ForgetFlights",
		welcome = "ShowWelcome", highlights = "Highlights", warm = "ToggleWarm",
		reset = "ResetWindow",   -- (reset: the windowed map's size and place, for one off the screen)
	}
	-- (the controller view's diagnostics: it runs while Questicus Maps' usual map is off, PadView.lua)
	if msg == "padview" and mod.PadViewDiag then return mod.PadViewDiag() end
	-- the controller view's map (PadView.lua): what works on it, its status its own
	if run[msg] and mod.padWaits and mod.PadViewOn and mod.PadViewOn() then
		local onView = { pins = true, draw = true, news = true }
		if msg == "status" and mod.PadViewDiag then mod.PadViewDiag()
		elseif onView[msg] and mod[run[msg]] then mod[run[msg]](mod)
		else ns:Print(ns.L["That isn't available with the Gamepad UI yet."]) end
		return
	end
	if run[msg] then
		if mod.enabled and mod[run[msg]] then mod[run[msg]](mod, takes[msg] and rest or nil)
		elseif mod.padWaits then ns:Print(mod.PadOffText())
		else ns:Print(ns.L["The map is off."]) end
	else
		OpenOptions()
	end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		ns:InitDB()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		local t0 = debugprofilestop and debugprofilestop()
		ns:EnableModules()
		if t0 then ns.loadMs.login = debugprofilestop() - t0 end
		local AC = LibStub("AceConfig-3.0", true)
		if AC then AC:RegisterOptionsTable("Questicus Maps", Options) end
		-- the map's settings live in Questicus: Questicus' options window and settings page have the
		-- "Map settings" button, and the commands are /qc map ... (and /qmap)
		SLASH_QUESTICUSMAP1 = "/qmap"
		SlashCmdList.QUESTICUSMAP = Slash
		ns.Slash = Slash
		local Q = _G.Questicus
		if Q and Q.Command then
			Q:Command("map", "Questicus Maps: /qc map (settings), status, notes, pins, draw, news, dungeons, bench, reset", function(rest) Slash(rest) end)
		end
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)

function ns.NotifyOptions()
	local ACR = LibStub("AceConfigRegistry-3.0", true)
	if ACR then ACR:NotifyChange("Questicus Maps") end
end
