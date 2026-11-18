-- IDontWannaLC - Comm
-- Addon-message protocol between raid members and the raid leader.
--
-- Messages are "^"-separated and always < 255 bytes:
--   HELLO^version                 anyone -> raid   request current state
--   CFG^<settings>                leader -> raid   settings, lock, raid key
--   SET^<raidKey>^<h;s>           player -> raid   my full reserve set (leader validates)
--   SYNC^seq^part^total^<blob>    leader -> raid   authoritative reserve list (chunked)
--   REJ^itemID^kind^reason        leader -> whisper  a reserve was refused
--   DROP^id^itemID^boss^run       leader -> raid   an item dropped (everyone's loot window); run = ledger run id
--   LQ / LI / LR / LD             guild ledger sync, see Core/Ledger.lua
--   UNDROP^id                     leader -> raid   that drop was removed again
--   CLEAR                         leader -> raid   finished items cleared from the loot window
--   ROLL^id^itemID^mode^names     leader -> raid   item is up; names = eligible (csv) or "*"
--   AWARD^id^itemID^winner^mode   loot master -> raid   who gets it; mode = how decided, or DISENCHANT / BANK
--   UNAWARD^id^itemID^winner^sp   loot master -> raid   that award was undone (sp = 1 for disenchant / bank)
--   TRADED^id^0|1                 loot master -> raid   item handed over (or not after all)
--   CLOSE^id                      loot master -> raid   no more rolls for that item
-- Loot messages (DROP ... TRADED) come from the loot master: the raid leader
-- or the assistant named in CFG.
--   CANCEL^id                     leader -> raid   roll cancelled
--   RESET                         leader -> raid   all reserves wiped
--   PING                          leader -> raid   who has the addon? (everyone answers VER)
--   VER^version                   anyone -> raid   my addon version
--
-- Sending is queued: the modern client throttles addon messages per prefix
-- (~10 burst, +1/sec) and blocks them during boss encounters, so the queue
-- pauses while restricted and drains afterwards.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine

local Comm = {}
ns.Comm = Comm
Addon.Comm = Comm

local SEP = "^"
local MAX_LEN = 250
local BURST = 8
local REGEN = 1.0

local queue = {}
local tokens = BURST
local ticker

-- [name] = addon version, for everyone we have heard from. The raid leader's
-- roster uses it to tell who has the addon installed.
Comm.versions = {}

local function heard(sender, version)
    if not sender then return end
    local old = Comm.versions[sender]
    if version and version ~= "" then
        Comm.versions[sender] = version
    elseif not old then
        Comm.versions[sender] = "?"
    end
    if Comm.versions[sender] ~= old then Addon:Fire("ROSTER_CHANGED") end
end

local function split(msg)
    local out = {}
    for part in (msg .. SEP):gmatch("(.-)%" .. SEP) do table.insert(out, part) end
    return out
end
Comm.Split = split

local function rawSend(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
    local result = send(Addon.PREFIX, msg, channel, target)
    -- Modern clients return an Enum.SendAddonMessageResult; 0 == Success.
    if type(result) == "number" and result ~= 0 then
        Addon:Debug("addon message failed (%d): %s", result, msg)
        return false
    end
    return true
end

local function pump()
    if Addon:IsRestricted() then return end
    while tokens >= 1 and #queue > 0 do
        local item = table.remove(queue, 1)
        if item.channel == "RAID" and not IsInRaid() then
            -- left the raid; drop it
        else
            rawSend(item.msg, item.channel, item.target)
            tokens = tokens - 1
        end
    end
end

function Comm:Send(channel, target, ...)
    local msg = table.concat({ ... }, SEP)
    if #msg > MAX_LEN then
        Addon:Debug("message too long, truncated: %s", msg:sub(1, 40))
        msg = msg:sub(1, MAX_LEN)
    end
    table.insert(queue, { msg = msg, channel = channel, target = target })
    pump()
end

function Comm:Raid(...)
    if not IsInRaid() then return end
    self:Send("RAID", nil, ...)
end

function Comm:Whisper(target, ...)
    self:Send("WHISPER", target, ...)
end

---------------------------------------------------------------------------
-- Outgoing helpers
---------------------------------------------------------------------------
function Comm:SendHello()
    self:Raid("HELLO", Addon.version)
end

function Comm:SendVersion()
    self:Raid("VER", Addon.version)
end

-- Leader: ask every client to report its version (throttled unless forced).
local lastPing = -100
function Comm:SendPing(force)
    if not IsInRaid() or not Addon:IsLeader() then return end
    if not force and GetTime() - lastPing < 5 then return end
    lastPing = GetTime()
    self:Raid("PING")
end

function Comm:SendConfig()
    local s = Addon.session
    self:Raid("CFG", Engine.EncodeSettings(s.settings, s.locked, s.raidKey, s.lootMaster))
end

function Comm:SendMyReserves(raidKey, hard, soft)
    self:Raid("SET", raidKey or "", Engine.EncodeReserveSet(hard, soft))
end

local syncSeq = 0
function Comm:SendSync()
    syncSeq = (syncSeq % 999) + 1
    local chunks, current = {}, {}
    local currentLen = 0
    local names = {}
    for name in pairs(Addon.session.reserves) do table.insert(names, name) end
    table.sort(names)
    local budget = MAX_LEN - 20
    for _, name in ipairs(names) do
        local r = Addon.session.reserves[name]
        local entry = name .. "=" .. Engine.EncodeReserveSet(r.hard, r.soft)
        if currentLen + #entry + 1 > budget and #current > 0 then
            table.insert(chunks, table.concat(current, "~"))
            current, currentLen = {}, 0
        end
        table.insert(current, entry)
        currentLen = currentLen + #entry + 1
    end
    table.insert(chunks, table.concat(current, "~")) -- may be "" (empty list)
    for i, blob in ipairs(chunks) do
        self:Raid("SYNC", syncSeq, i, #chunks, blob)
    end
end

function Comm:SendReject(target, itemID, kind, reason)
    self:Whisper(target, "REJ", itemID or 0, kind or "", reason or "")
end

function Comm:SendDrop(id, itemID, boss, runUid)
    self:Raid("DROP", id, itemID, ((boss or ""):gsub("%^", "")), runUid or "")
end

-- bonus = { [name] = n } (soft reserve bonus), sent as "Name:n".
function Comm:SendRoll(id, itemID, mode, eligible, bonus)
    local names = "*"
    if eligible then
        local parts = {}
        for _, name in ipairs(eligible) do
            local b = bonus and bonus[name]
            parts[#parts + 1] = (b and b > 0) and (name .. ":" .. b) or name
        end
        names = table.concat(parts, ",")
    end
    if #names > 180 then names = "+" end -- too many to list; clients just show the mode
    self:Raid("ROLL", id, itemID, mode, names)
end

function Comm:SendAward(id, itemID, winner, mode)
    self:Raid("AWARD", id, itemID, winner or "", mode or "")
end

function Comm:SendCancel(id)
    self:Raid("CANCEL", id)
end

---------------------------------------------------------------------------
-- Incoming
---------------------------------------------------------------------------
local handlers = {}
local RAID_ONLY -- message types that are only accepted over the raid channel (set below)
local syncBuffer = { seq = nil, parts = {}, total = 0 }

local function fromLeader(sender)
    return sender == Addon:GetLeaderName()
end

handlers.HELLO = function(sender, args)
    heard(sender, args[2])
    if Addon:IsLeader() and sender ~= Addon:PlayerName() and Addon.session.approved then
        Comm:SendConfig()
        Comm:SendSync()
    end
end

local lastVersionSent = -100
handlers.PING = function(sender)
    if not fromLeader(sender) or sender == Addon:PlayerName() then return end
    if GetTime() - lastVersionSent < 5 then return end
    lastVersionSent = GetTime()
    Comm:SendVersion()
end

handlers.VER = function(sender, args)
    heard(sender, args[2])
end

handlers.CFG = function(sender, args)
    if not fromLeader(sender) or Addon:IsLeader() then return end
    local settings, locked, raidKey, lootMaster = Engine.DecodeSettings(args[2])
    if not settings then return end
    local s = Addon.session
    local old = {}
    for k, v in pairs(s.settings) do old[k] = v end
    local oldRaid, oldLocked = s.raidKey, s.locked
    s:SetSettings(settings)
    s:SetLocked(locked)
    s.raidKey = raidKey
    s.approved = raidKey ~= nil -- the leader only sends rules once approved
    s.lootMaster = lootMaster
    Addon:Fire("SESSION_CHANGED")
    -- Reserves module notifies the player and re-sends their selection.
    Addon:Fire("SETTINGS_CHANGED", old, s.settings, oldRaid, raidKey, oldLocked, locked)
end

handlers.SET = function(sender, args)
    if not Addon:IsLeader() then return end
    ns.Reserves:LeaderApplyPlayerSet(sender, args[2], args[3])
end

handlers.SYNC = function(sender, args)
    if not fromLeader(sender) or Addon:IsLeader() then return end
    local seq, part, total = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not (seq and part and total) then return end
    if syncBuffer.seq ~= seq then
        syncBuffer.seq, syncBuffer.parts, syncBuffer.total = seq, {}, total
    end
    syncBuffer.parts[part] = args[5] or ""
    for i = 1, total do
        if syncBuffer.parts[i] == nil then return end
    end
    local reserves = {}
    for i = 1, total do
        for entry in (syncBuffer.parts[i] .. "~"):gmatch("(.-)~") do
            local name, set = entry:match("^(.-)=(.*)$")
            if name then
                local hard, soft = Engine.DecodeReserveSet(set)
                if hard then reserves[name] = { hard = hard, soft = soft } end
            end
        end
    end
    Addon.session.reserves = reserves
    syncBuffer.seq = nil
    Addon:Fire("RESERVES_CHANGED")
    Addon:Fire("RESERVES_SYNCED")
end

handlers.RESET = function(sender)
    if not fromLeader(sender) or Addon:IsLeader() then return end
    ns.Reserves:OnRemoteReset()
end

handlers.REJ = function(sender, args)
    if not fromLeader(sender) then return end
    local itemID, kind, reason = tonumber(args[2]), args[3], args[4]
    Addon:Fire("RESERVE_REJECTED", itemID, kind, reason)
    local link = itemID and itemID > 0 and (Addon:GetItemLink(itemID) or ("item " .. itemID)) or ""
    Addon:Print("|cffff5555Reserve rejected|r %s %s: %s", link, kind or "", reason or "")
end

local function fromLoot(sender)
    return sender == Addon:GetLootMasterName()
end

handlers.DROP = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteDrop(tonumber(args[2]), tonumber(args[3]), args[4], args[5])
end

-- Guild ledger sync. Who may send what is checked in Core/Ledger.lua.
handlers.LQ = function(sender, _, channel)
    if channel ~= "GUILD" then return end
    ns.Ledger:OnQuery(sender)
end

handlers.LI = function(sender, args, channel)
    if channel ~= "WHISPER" then return end
    ns.Ledger:OnIndex(sender, args[2], tonumber(args[3]), tonumber(args[4]), tonumber(args[5]))
end

handlers.LR = function(sender, args, channel)
    if channel ~= "WHISPER" then return end
    ns.Ledger:OnRequest(sender, args[2])
end

handlers.LD = function(sender, args, channel)
    if channel ~= "WHISPER" then return end
    ns.Ledger:OnData(sender, args[2], tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), args[6])
end

handlers.UNDROP = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteUndrop(tonumber(args[2]))
end

handlers.CLEAR = function(sender)
    if not fromLoot(sender) or Addon:IsLootMaster() then return end
    ns.Loot:ClearDone()
end

handlers.ROLL = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteRoll(tonumber(args[2]), tonumber(args[3]), args[4], args[5])
end

handlers.AWARD = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteAward(tonumber(args[2]), tonumber(args[3]), args[4], args[5] ~= "" and args[5] or nil)
end

handlers.UNAWARD = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteUnaward(tonumber(args[2]), tonumber(args[3]), args[4], args[5] == "1")
end

handlers.CLOSE = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteClose(tonumber(args[2]))
end

handlers.TRADED = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteTraded(tonumber(args[2]), args[3] == "1")
end

handlers.CANCEL = function(sender, args)
    if not fromLoot(sender) then return end
    ns.Loot:OnRemoteCancel(tonumber(args[2]))
end

RAID_ONLY = {
    HELLO = true, PING = true, VER = true, CFG = true, SET = true, SYNC = true, RESET = true,
    DROP = true, UNDROP = true, CLEAR = true, ROLL = true, CLOSE = true, AWARD = true, UNAWARD = true,
    TRADED = true, CANCEL = true,
}

Addon:OnInit(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(Addon.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(Addon.PREFIX)
    end
    -- Regain one send token per second, then drain what we can.
    ticker = C_Timer.NewTicker(REGEN, function()
        tokens = math.min(BURST, tokens + 1)
        pump()
    end)
end)

Addon:RegisterEvent("CHAT_MSG_ADDON", function(self, _, prefix, msg, channel, sender)
    if prefix ~= Addon.PREFIX then return end
    sender = self:NormalizeName(sender)
    local args = split(msg)
    if channel == "RAID" then heard(sender) end -- any raid message means they run the addon
    -- Raid business only counts when the whole raid can see it: a whispered
    -- AWARD or CFG must not be able to change anything.
    if RAID_ONLY[args[1]] and channel ~= "RAID" then return end
    local handler = handlers[args[1]]
    if handler then handler(sender, args, channel) end
end)

-- Ask the leader for state whenever we join / change raid roster.
local lastHello = 0
Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function(self)
    if not IsInRaid() then return end
    if self:IsLeader() then
        Comm:SendPing() -- new members may have joined (throttled)
    elseif GetTime() - lastHello > 10 then
        lastHello = GetTime()
        Comm:SendHello()
    end
end)

Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
    if IsInRaid() and not self:IsLeader() then
        C_Timer.After(5, function() Comm:SendHello() end)
    end
end)

Addon:On("ENCOUNTER_ENDED", pump)
