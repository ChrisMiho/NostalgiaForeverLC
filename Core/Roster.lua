-- IDontWannaLC - Roster inventory (raid leader)
-- Who in the raid has the addon, who has sent reserves, and who still needs
-- a nudge. The leader can whisper a player (a real, visible whisper sent on
-- purpose by clicking a button) to ask them to install the addon or fill in
-- their picks. Everything else travels over hidden addon messages.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine
local STATUS = Engine.STATUS

local Roster = {}
ns.Roster = Roster
Addon.Roster = Roster

local WHISPER_COOLDOWN = 30 -- seconds between whispers to the same player
local WHISPER_SPACING = 0.1 -- seconds between whispers of a "whisper all"
local ORDER = { [STATUS.NOADDON] = 1, [STATUS.EMPTY] = 2, [STATUS.PARTIAL] = 3, [STATUS.READY] = 4 }
local lastWhisper = {} -- [name] = GetTime() of the last whisper

-- One row per raid member, players who need attention first.
-- { name, fullName, class, online, version, status, hard, soft }
function Roster:GetRows()
    local rows = {}
    if not IsInRaid() then return rows end
    local s = Addon.session
    local me = Addon:PlayerName()
    for i = 1, GetNumGroupMembers() do
        local fullName, _, _, _, _, classFile, _, online = GetRaidRosterInfo(i)
        if fullName then
            local name = Addon:NormalizeName(fullName)
            local reserve = s.approved and s.reserves[name] or nil
            local version = ns.Comm.versions[name]
            if name == me then version = Addon.version end
            rows[#rows + 1] = {
                name = name,
                fullName = fullName,
                class = classFile,
                online = online ~= false,
                version = version,
                status = Engine.MemberStatus(version ~= nil, reserve, s.settings),
                hard = reserve and #reserve.hard or 0,
                soft = reserve and #reserve.soft or 0,
                imported = s.imported[name] == true, -- reserves entered by the leader
                rank = select(2, GetRaidRosterInfo(i)) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        if ORDER[a.status] ~= ORDER[b.status] then return ORDER[a.status] < ORDER[b.status] end
        return a.name < b.name
    end)
    return rows
end

-- ready, total
function Roster:Summary()
    local rows = self:GetRows()
    local ready = 0
    for _, row in ipairs(rows) do
        if row.status == STATUS.READY then ready = ready + 1 end
    end
    return ready, #rows
end

-- Who isn't ready: count and a sentence like "2 without the addon, 1 with
-- no picks, 3 incomplete" (nil when everyone is ready).
function Roster:NotReadySummary()
    local n = { [STATUS.NOADDON] = 0, [STATUS.EMPTY] = 0, [STATUS.PARTIAL] = 0 }
    for _, row in ipairs(self:GetRows()) do
        if n[row.status] then n[row.status] = n[row.status] + 1 end
    end
    local total = n[STATUS.NOADDON] + n[STATUS.EMPTY] + n[STATUS.PARTIAL]
    if total == 0 then return 0, nil end
    local parts = {}
    if n[STATUS.NOADDON] > 0 then parts[#parts + 1] = n[STATUS.NOADDON] .. " without the addon" end
    if n[STATUS.EMPTY] > 0 then parts[#parts + 1] = n[STATUS.EMPTY] .. " with no picks" end
    if n[STATUS.PARTIAL] > 0 then parts[#parts + 1] = n[STATUS.PARTIAL] .. " incomplete" end
    return total, table.concat(parts, ", ")
end

-- The message a player gets, or nil when they need no reminder.
function Roster:WhisperText(row)
    local s = Addon.session
    -- Before approval nothing is being collected: only "install it" applies.
    if not s.approved and row.status ~= STATUS.NOADDON then return nil end
    local set = s.settings
    local raid = s.raidKey and ns.RaidDataAPI:GetName(s.raidKey) or "this raid"
    if row.status == STATUS.NOADDON then
        return ("[IDWLC] This raid hands out loot with the \"I Don't Wanna LC\" addon (%d hard / %d soft reserves each). Please install it and pick your reserves for %s with /idwlc.")
            :format(set.hardReserves, set.softReserves, raid)
    elseif row.status == STATUS.EMPTY then
        return ("[IDWLC] You have no reserves set for %s yet. Open /idwlc and add up to %d hard / %d soft picks.")
            :format(raid, set.hardReserves, set.softReserves)
    elseif row.status == STATUS.PARTIAL then
        return ("[IDWLC] Your reserves for %s are incomplete: %d/%d hard, %d/%d soft. Open /idwlc to add the rest.")
            :format(raid, row.hard, set.hardReserves, row.soft, set.softReserves)
    end
end

-- Seconds until this player can be whispered again (0 = now).
function Roster:WhisperCooldown(row)
    local last = lastWhisper[row.name]
    if not last then return 0 end
    return math.max(0, WHISPER_COOLDOWN - (GetTime() - last))
end

-- Whisper one player. Returns true when a message was sent.
function Roster:Whisper(row)
    if not (IsInRaid() and Addon:IsLeader()) then return false end
    if row.name == Addon:PlayerName() then return false end
    local text = self:WhisperText(row)
    if not text or self:WhisperCooldown(row) > 0 then return false end
    lastWhisper[row.name] = GetTime()
    Addon:SendChat(text, "WHISPER", row.fullName)
    -- Let the UI offer the button again once the cooldown is over.
    C_Timer.After(WHISPER_COOLDOWN + 1, function() Addon:Fire("ROSTER_CHANGED") end)
    return true
end

-- Whisper everyone who isn't ready, a few per second so the server's chat
-- throttle isn't tripped. Returns how many will be messaged.
function Roster:WhisperAll()
    local n = 0
    for _, row in ipairs(self:GetRows()) do
        if row.online and row.name ~= Addon:PlayerName() and self:WhisperText(row)
            and self:WhisperCooldown(row) <= 0 then
            if n == 0 then
                self:Whisper(row)
            else
                C_Timer.After(n * WHISPER_SPACING, function() Roster:Whisper(row) end)
            end
            n = n + 1
        end
    end
    return n
end

-- Ask every client to report its version again.
function Roster:Refresh()
    ns.Comm:SendPing(true)
    Addon:Fire("ROSTER_CHANGED")
end

Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function() Addon:Fire("ROSTER_CHANGED") end)
