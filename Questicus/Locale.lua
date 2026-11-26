-- Questicus: languages.
-- Questicus is written in English. Every other language the game comes in is a separate language pack
-- (an addon of its own: Questicus_deDE, Questicus_frFR, ...), downloaded from the Questicus files page
-- on CurseForge. A pack loads before Questicus (OptionalDeps in Questicus.toc) and puts its phrases in
-- QuesticusLocales[code] = { ["English phrase"] = "translation", ... }.
--
-- In the code: local L = Q.L, then L["Skip"] for a phrase, L("%d quests done", n) for one with values
-- (format placeholders; a translation may reorder them with %1$s / %2$s). A phrase a pack doesn't have
-- stays English.
--
-- Which language: Options > Language (QuesticusDB.lang): "auto" = the game's language when its pack
-- is installed, else English. Changing it takes a /reload.
local Q = Questicus

-- every language the game comes in, in the order the list shows them
Q.LANGS = {
  { code = "enUS", name = "English" },
  { code = "deDE", name = "Deutsch" },
  { code = "frFR", name = "Français" },
  { code = "esES", name = "Español (España)" },
  { code = "esMX", name = "Español (Latinoamérica)" },
  { code = "itIT", name = "Italiano" },
  { code = "ptBR", name = "Português (Brasil)" },
  { code = "ruRU", name = "Русский" },
  { code = "koKR", name = "한국어" },
  { code = "zhCN", name = "简体中文" },
  { code = "zhTW", name = "繁體中文" },
}
-- where the language packs are (the Questicus files page: each release carries them as extra files)
Q.LANG_URL = "https://www.curseforge.com/wow/addons/questicus/files"
-- languages whose letters need the game's own font for that language (only there on a client in it)
local CJK = { koKR = true, zhCN = true, zhTW = true }

QuesticusLocales = QuesticusLocales or {}

local function gameLang()
  local g = GetLocale and GetLocale() or "enUS"
  if g == "enGB" then g = "enUS" end
  return g
end
Q.GameLang = gameLang

-- the language pack for code: "loaded", "off" (installed but turned off in the AddOns list), "missing"
function Q.LangPack(code)
  if code == "enUS" then return "loaded" end
  if QuesticusLocales[code] then return "loaded" end
  local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
  if info then
    local ok, name, _, _, loadable, reason = pcall(info, "Questicus_" .. code)
    if ok and name and reason ~= "MISSING" then return "off" end
  end
  return "missing"
end

-- can this client show the language's letters?
function Q.LangFontOK(code)
  if not CJK[code] then return true end
  return CJK[gameLang()] == true
end

-- the language in use
local current, phrases = "enUS", nil
local function pick(choice)
  local want = (choice == nil or choice == "auto") and gameLang() or choice
  if want ~= "enUS" and QuesticusLocales[want] and Q.LangFontOK(want) then return want end
  return "enUS"
end
function Q.SetLanguage(choice)
  current = pick(choice)
  phrases = current ~= "enUS" and QuesticusLocales[current] or nil
end
function Q.Lang() return current end
-- (before the saved choice is known: the game's language)
Q.SetLanguage("auto")

-- L["phrase"] / L("format %s", ...)
local L = setmetatable({}, {
  __index = function(_, s)
    if type(s) ~= "string" then return s end
    local t = phrases and phrases[s]
    return (type(t) == "string" and t ~= "") and t or s
  end,
  __call = function(self, s, ...)
    local t = self[s]
    if select("#", ...) == 0 then return t end
    local ok, out = pcall(string.format, t, ...)
    if ok then return out end
    local ok2, en = pcall(string.format, s, ...)   -- a broken translation: the English one
    return ok2 and en or s
  end,
})
Q.L = L

Q:On("ADDON_LOADED", function(name)
  if name ~= Q.name then return end
  QuesticusDB = QuesticusDB or {}
  QuesticusDB.lang = QuesticusDB.lang or "auto"
  Q.SetLanguage(QuesticusDB.lang)
  if Q.T then Q.T.FONT = Q.LangFont(Q.T.FONT) end
end)

-- the font for the language in use: the game's own font covers the game's language; Russian on a
-- client in another language needs the Cyrillic font
function Q.LangFont(default)
  if current == "ruRU" and gameLang() ~= "ruRU" then return "Fonts\\FRIZQT___CYR.TTF" end
  return default
end

-- ------------------------------------------------------------------ a link to copy
-- The game can't open web pages: a small box with the address selected, Ctrl-C to copy.
local box
function Q.CopyBox(title, url)
  local T = Q.T
  if not box then
    box = T.Window("QuesticusCopyBox", 420, 96, "", nil)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box.what = T.Text(box, 11, T.c.dim)
    box.what:SetPoint("TOPLEFT", 14, -32)
    box.what:SetPoint("RIGHT", -14, 0)
    box.what:SetWordWrap(false)
    local f = CreateFrame("Frame", nil, box)
    f:SetPoint("TOPLEFT", 12, -50)
    f:SetPoint("RIGHT", -12, 0)
    f:SetHeight(24)
    T.RFill(f, { T.c.bg[1] * 0.6, T.c.bg[2] * 0.6, T.c.bg[3] * 0.6, 1 }, 4)
    T.Border(f, T.c.line, 4)
    box.input = CreateFrame("EditBox", nil, f)
    box.input:SetAutoFocus(true)
    box.input:SetFontObject(ChatFontNormal)
    box.input:SetPoint("TOPLEFT", 6, -4)
    box.input:SetPoint("BOTTOMRIGHT", -6, 4)
    box.input:SetScript("OnEscapePressed", function() box:Hide() end)
    box.input:SetScript("OnEnterPressed", function() box:Hide() end)
    box.input:SetScript("OnTextChanged", function(self, user)
      if user and box.url then self:SetText(box.url); self:HighlightText() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuesticusCopyBox") end
  end
  box.url = url
  box.title:SetText(title or "")
  box.what:SetText(Q.L["Ctrl-C to copy, then paste it in your browser"])
  box:Show()
  box.input:SetText(url)
  box.input:SetFocus()
  box.input:HighlightText()
end
