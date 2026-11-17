-- IDontWannaLC - Comm
-- Addon-message protocol between raid members and the raid leader.
--
-- Messages are "^"-separated and always < 255 bytes:
--   HELLO^version                 anyone -> raid   request current state
--   CFG^<settings>                leader -> raid   settings, lock, raid key
--   SET^<raidKey>^<h;s>           player -> raid   my full reserve set (leader validates)
--   SYNC^seq^part^total^<blob>    leader -> raid   authoritative reserve list (chunked)
--   REJ^itemID^kind^reason        leader -> whisper  a reserve was refused
--   ROLL^id^itemID^mode^names     leader -> raid   item is up; names = eligible (csv) or "*"
--   AWARD^id^itemID^winner        leader -> raid   leader decided who gets it
--   CANCEL^id                     leader -> raid   roll cancelled
--   RESET                         leader -> raid   all reserves wiped
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

function Comm:SendConfig()
    local s = Addon.session
    self:Raid("CFG", Engine.EncodeSettings(s.settings, s.locked, s.raidKey))
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

function Comm:SendRoll(id, itemID, mode, eligible)
    local names = eligible and table.concat(eligible, ",") or "*"
    if #names > 180 then names = "+" end -- too many to list; clients just show the mode
    self:Raid("ROLL", id, itemID, mode, names)
end

function Comm:SendAward(id, itemID, winner)
    self:Raid("AWARD", id, itemID, winner or "")
end

function Comm:SendCancel(id)
    self:Raid("CANCEL", id)
end

---------------------------------------------------------------------------
-- Incoming
---------------------------------------------------------------------------
local handlers = {}
local syncBuffer = { seq = nil, parts = {}, total = 0 }

local function fromLeader(sender)
    return sender == Addon:GetLeaderName()
end

handlers.HELLO = function(sender)
    if Addon:IsLeader() and sender ~= Addon:PlayerName() then
        Comm:SendConfig()
        Comm:SendSync()
    end
end

handlers.CFG = function(sender, args)
    if not fromLeader(sender) or Addon:IsLeader() then return end
    local settings, locked, raidKey = Engine.DecodeSettings(args[2])
    if not settings then return end
    Addon.session:SetSettings(settings)
    Addon.session:SetLocked(locked)
    Addon.session.raidKey = raidKey
    Addon:Fire("SESSION_CHANGED")
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

handlers.ROLL = function(sender, args)
    if not fromLeader(sender) then return end
    ns.Loot:OnRemoteRoll(tonumber(args[2]), tonumber(args[3]), args[4], args[5])
end

handlers.AWARD = function(sender, args)
    if not fromLeader(sender) then return end
    ns.Loot:OnRemoteAward(tonumber(args[2]), tonumber(args[3]), args[4])
end

handlers.CANCEL = function(sender, args)
    if not fromLeader(sender) then return end
    ns.Loot:OnRemoteCancel(tonumber(args[2]))
end

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
    local handler = handlers[args[1]]
    if handler then handler(sender, args, channel) end
end)

-- Ask the leader for state whenever we join / change raid roster.
local lastHello = 0
Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function(self)
    if not IsInRaid() then return end
    if GetTime() - lastHello > 10 and not self:IsLeader() then
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
