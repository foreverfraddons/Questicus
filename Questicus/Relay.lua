-- Questicus relay: players' recordings reach ForeverDB through the game itself.
-- An addon can't send anything out of the game, so recordings only left the PCs that run the sync task.
-- Now every Questicus sends what it learned - respawn times, new spawn points, zone border crossings,
-- objects that only appear on a kill - in addon messages (nothing shows in chat) to a collector: a
-- Questicus with the author's local dev tools loaded (QuesticusDev). The collector answers "got it" and
-- keeps them by sender (QuesticusCollect.relay[hash of the sender]); its PC's sync sends them on to
-- ForeverDB, where each sender counts as a recording of its own.
--  * Senders only talk when a collector said "I'm here" (guild, group) in the last 15 minutes, and then by
--    whisper to it: no guild-wide spam. An item is sent until the collector confirms it, and again only if
--    it changed (a respawn time measured more often).
--  * Small: at most one message every 0.4 s, 60 a session, nothing in combat or instance chat lockdown.
--  * Options > Advanced "Help fill the database" (Q.db.collect) off: nothing is sent.
local Q = Questicus
local D = Q.Data
local R = {}
Q.Relay = R

local PREFIX = "QuesticusR"
local HELLO_EVERY = 600            -- seconds between a collector's "I'm here"
local COLLECTOR_FRESH = 900        -- a collector heard within this long counts as online
local GAP = 0.4                    -- seconds between two messages
local PER_SESSION = 60
local MAX_SENDERS = 400            -- (collector) senders kept

local function now() return time and time() or 0 end
local function on() return Q.db and Q.db.collect ~= false and QuesticusCollect ~= nil end
local function isCollector() return Q.Dev ~= nil end            -- the local-only dev addon
R.IsCollector = isCollector

-- short, stable id of a string (an item's key, a sender's name)
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  local out, chars = "", "0123456789abcdefghijklmnopqrstuvwxyz"
  for _ = 1, 6 do local k = h % 36; out = out .. chars:sub(k + 1, k + 1); h = math.floor(h / 36) end
  return out
end
R.Hash = hash

local function canSend()
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  if C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return false end
  end
  return true
end

-- ------------------------------------------------------------------ outgoing queue
local queue, sentN = {}, 0
local function push(text, channel, target)
  if #queue > 200 then return end
  queue[#queue + 1] = { text, channel, target }
end
local function sendOne()
  if #queue == 0 or not canSend() then return false end
  local m = table.remove(queue, 1)
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, m[1], m[2], m[3])
  return true
end
R.SendOne = sendOne
local acc = 0
local pump = CreateFrame("Frame")
pump:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < GAP or #queue == 0 then return end
  acc = 0
  sendOne()
end)

local function groupChannel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

-- ------------------------------------------------------------------ what a player has to send
-- every item: id (stable), signature (changes when the value does), the message text
local function items()
  local c = QuesticusCollect or {}
  local out = {}
  local function add(id, sig, text)
    if #text <= 250 then out[#out + 1] = { id = hash(id), sig = sig, text = text } end
  end
  for src, e in pairs(type(c.resp) == "table" and c.resp or {}) do
    if type(e) == "table" and ((e.n or 0) > 0 or e.lo or e.hi) then
      local sig = ("%d:%d:%d:%d"):format(e.n or 0, math.floor(e.s or 0), math.floor(e.lo or 0), math.floor(e.hi or 0))
      add("r" .. src, sig, ("r|%s|%d|%d|%d|%d|%d"):format(src, e.n or 0, math.floor(e.s or 0), math.floor(e.lo or 0),
        math.floor(e.hi or 0), math.floor(e.min or 0)))
    end
  end
  for key, list in pairs(type(c.nspawn) == "table" and c.nspawn or {}) do
    for _, p in ipairs(type(list) == "table" and list or {}) do
      if p.i and p.x and p.y then
        add(("s%s:%d:%d:%d"):format(key, p.i, p.x, p.y), "1", ("s|%s|%d|%d|%d|%s|%s|%s"):format(key, p.i, p.x, p.y,
          tostring(p.m or ""), tostring(p.mx or ""), tostring(p.my or "")))
      end
    end
  end
  for inst, pairsT in pairs(type(c.zcross) == "table" and c.zcross or {}) do
    for pk, pts in pairs(type(pairsT) == "table" and pairsT or {}) do
      for j = 1, #pts - 1, 2 do
        add(("z%s:%s:%d:%d"):format(inst, pk, pts[j], pts[j + 1]), "1", ("z|%s|%s|%d|%d"):format(inst, pk, pts[j], pts[j + 1]))
      end
    end
  end
  for key, n in pairs(type(c.osummon) == "table" and c.osummon or {}) do
    add("o" .. key, tostring(n), ("o|%s|%s"):format(key, tostring(n)))
  end
  return out
end
R.Items = items

-- ------------------------------------------------------------------ sender side
local collector, collectorAt          -- who's collecting, and when we last heard it
local pending = {}                    -- [id] = sig of items sent, waiting for the "got it"
local function acked()
  QuesticusCollect.relayAck = type(QuesticusCollect.relayAck) == "table" and QuesticusCollect.relayAck or {}
  return QuesticusCollect.relayAck
end
function R.SendBacklog()
  if not on() or isCollector() or not collector then return 0 end
  if now() - (collectorAt or 0) > COLLECTOR_FRESH then return 0 end
  local ack, n = acked(), 0
  for _, it in ipairs(items()) do
    if sentN >= PER_SESSION then break end
    if ack[it.id] ~= it.sig and pending[it.id] ~= it.sig then
      pending[it.id] = it.sig
      push(it.id .. ";" .. it.text, "WHISPER", collector)
      sentN, n = sentN + 1, n + 1
    end
  end
  return n
end

-- ------------------------------------------------------------------ collector side
local function store(sender, text)
  local c = QuesticusCollect
  c.relay = type(c.relay) == "table" and c.relay or {}
  local h = hash(sender)
  local r = c.relay[h]
  if not r then
    local n = 0
    for _ in pairs(c.relay) do n = n + 1 end
    if n >= MAX_SENDERS then return false end
    r = {}
    c.relay[h] = r
  end
  r.t = now()
  local kind, rest = text:match("^(%a)|(.*)$")
  if kind == "r" then
    local src, n, s, lo, hi, mn = rest:match("^([co]%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$")
    if not src then return false end
    r.resp = r.resp or {}
    local e = { n = tonumber(n), s = tonumber(s) }
    if tonumber(lo) > 0 then e.lo = tonumber(lo) end
    if tonumber(hi) > 0 then e.hi = tonumber(hi) end
    if tonumber(mn) > 0 then e.min = tonumber(mn) end
    r.resp[src] = e                                   -- (their whole tally: the newest replaces it)
  elseif kind == "s" then
    local key, i, x, y, m, mx, my = rest:match("^([co]%d+)|(%d+)|(%-?%d+)|(%-?%d+)|([^|]*)|([^|]*)|([^|]*)$")
    if not key then return false end
    r.nspawn = r.nspawn or {}
    local l = r.nspawn[key] or {}
    r.nspawn[key] = l
    if #l >= 40 then return true end
    for _, p in ipairs(l) do if p.i == tonumber(i) and p.x == tonumber(x) and p.y == tonumber(y) then return true end end
    l[#l + 1] = { i = tonumber(i), x = tonumber(x), y = tonumber(y), m = tonumber(m), mx = tonumber(mx), my = tonumber(my) }
  elseif kind == "z" then
    local inst, pk, x, y = rest:match("^(%d+)|(%d+%-%d+)|(%-?%d+)|(%-?%d+)$")
    if not inst then return false end
    r.zcross = r.zcross or {}
    local ci = r.zcross[tonumber(inst)] or {}
    r.zcross[tonumber(inst)] = ci
    local l = ci[pk] or {}
    ci[pk] = l
    for j = 1, #l - 1, 2 do if l[j] == tonumber(x) and l[j + 1] == tonumber(y) then return true end end
    if #l < 24 then l[#l + 1] = tonumber(x); l[#l + 1] = tonumber(y) end
  elseif kind == "o" then
    local key, n = rest:match("^(o%d+)|(%d+)$")
    if not key then return false end
    r.osummon = r.osummon or {}
    r.osummon[key] = tonumber(n)
  else
    return false
  end
  return true
end
R.Store = store

local ackBuf, ackTo = {}, nil
local function flushAcks()
  if not ackTo or #ackBuf == 0 then return end
  local line = ""
  for _, id in ipairs(ackBuf) do
    if #line + #id + 1 > 240 then push("A|" .. line, "WHISPER", ackTo); line = "" end
    line = line == "" and id or (line .. ";" .. id)
  end
  if line ~= "" then push("A|" .. line, "WHISPER", ackTo) end
  wipe(ackBuf)
end

function R.Hello()
  if not (isCollector() and on() and canSend()) then return end
  if IsInGuild and IsInGuild() then push("C", "GUILD") end
  local g = groupChannel()
  if g then push("C", g) end
end

local function me()
  local n, realm = UnitName and UnitName("player")
  return n
end
function R.OnMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or type(text) ~= "string" or (Q.Secret and Q.Secret(text)) then return end
  if type(sender) ~= "string" or (Q.Secret and Q.Secret(sender)) then return end
  local short = sender:match("^([^%-]+)") or sender
  if short == me() then return end
  if text == "?" then
    -- someone just logged in and asks whether a collector is around
    if isCollector() and on() then push("C", "WHISPER", sender) end
    return
  end
  if text == "C" then
    -- a collector is around: send what it hasn't got (a moment later, so many senders don't all start at once)
    if isCollector() then return end
    collector, collectorAt = sender, now()
    Q.After(2 + math.random() * 8, function() R.SendBacklog() end)
  elseif text:sub(1, 2) == "A|" then
    if isCollector() then return end
    local ack = acked()
    for id in text:sub(3):gmatch("[^;]+") do
      if pending[id] then ack[id] = pending[id]; pending[id] = nil end
    end
  elseif isCollector() and on() and channel == "WHISPER" then
    local id, body = text:match("^(%w+);(.+)$")
    if id and store(sender, body) then
      ackBuf[#ackBuf + 1] = id
      ackTo = sender
      Q.Throttle("relayack", 1.5, flushAcks)
      R.got = (R.got or 0) + 1
    end
  end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
Q:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender) R.OnMessage(prefix, text, channel, sender) end)
function R.Ask()
  if isCollector() or not on() or not canSend() then return end
  if IsInGuild and IsInGuild() then push("?", "GUILD") end
end
Q:On("PLAYER_LOGIN", function()
  Q.After(20, function() R.Hello() end)
  Q.After(45, function() R.Ask() end)
  local t = CreateFrame("Frame")
  local a = 0
  t:SetScript("OnUpdate", function(_, el)
    a = a + el
    if a < HELLO_EVERY then return end
    a = 0
    R.Hello()
    R.SendBacklog()                 -- (things learned since: to a collector still around)
  end)
end)
Q:On("GROUP_ROSTER_UPDATE", function() Q.Throttle("relayhello", 10, function() R.Hello() end) end)

Q:Command("relay", "what the in-game relay to ForeverDB sent / received", function()
  local c = QuesticusCollect or {}
  if isCollector() then
    local senders, n = 0, 0
    for _, r in pairs(type(c.relay) == "table" and c.relay or {}) do senders = senders + 1 end
    Q:Print(("collecting: %d players' recordings kept, %d items received this session"):format(senders, R.got or 0))
  else
    local total, done = 0, 0
    local ack = type(c.relayAck) == "table" and c.relayAck or {}
    for _, it in ipairs(items()) do total = total + 1; if ack[it.id] == it.sig then done = done + 1 end end
    Q:Print(("%d of your %d findings reached ForeverDB's collector%s"):format(done, total,
      collector and (" (last heard " .. math.floor((now() - collectorAt) / 60) .. " min ago)") or " (none online yet)"))
  end
end)
