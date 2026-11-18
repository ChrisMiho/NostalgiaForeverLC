-- NostalgiaForeverLC - Raid stats
-- Per character, per raid: bosses killed in the current lockout and how many
-- times the raid has been cleared. Fed by boss kills (ENCOUNTER_END) and
-- reconciled with the game's saved-instance list, which also knows the boss
-- count of raids we have no loot table for yet.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine
local RaidData = ns.RaidDataAPI

local Stats = {}
ns.Stats = Stats
Addon.Stats = Stats

local lockouts = {} -- [raidKey] = { progress = n, total = n } from the saved-instance list

local function now()
    return time()
end

local function statsFor(key, create)
    local all = Addon.charDB.raidStats
    local st = all[key]
    if not st and create then
        st = Engine.NewStats()
        all[key] = st
    end
    return st
end

-- { clears, killed, total, lastKill }. total is 0 when the boss count is unknown.
function Stats:Get(key)
    local st = statsFor(key)
    local out = {
        clears = st and st.clears or 0,
        killed = st and Engine.Progress(st, now()) or 0,
        total = RaidData:GetBossCount(key),
        lastKill = st and st.lastKill or nil,
    }
    local lock = lockouts[key]
    if lock then
        -- The game's own numbers win (optional bosses, unknown raids).
        out.total = lock.total
        out.killed = math.max(out.killed, lock.progress)
    end
    return out
end

function Stats:RecordKill(key, bossName)
    if not key or not bossName then return end
    local lock = lockouts[key]
    local total = lock and lock.total or RaidData:GetBossCount(key)
    Engine.RecordKill(statsFor(key, true), bossName, total, now())
    Addon:Fire("STATS_CHANGED")
end

-- Read the saved-instance list: lockout progress, and clears we didn't see
-- boss by boss (e.g. the addon was installed mid-lockout).
function Stats:ReadLockouts()
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    lockouts = {}
    for i = 1, GetNumSavedInstances() do
        local name, _, reset, _, locked, _, _, isRaid, _, _, numEncounters, progress = GetSavedInstanceInfo(i)
        local key = isRaid and locked and RaidData:KeyForName(name)
        if key and (numEncounters or 0) > 0 then
            lockouts[key] = { progress = progress or 0, total = numEncounters }
            local st = statsFor(key, (progress or 0) > 0)
            if st then
                local resetAt = reset and reset > 0 and (now() + reset) or nil
                if (progress or 0) >= numEncounters then
                    Engine.MarkCleared(st, now(), resetAt)
                elseif resetAt then
                    st.resetAt = resetAt
                end
            end
        end
    end
    Addon:Fire("STATS_CHANGED")
end

Addon:On("ENCOUNTER_ENDED", function(_, encounterName, success)
    if not success or not Addon:IsInRaidInstance() then return end
    Stats:RecordKill(RaidData:Detect(), encounterName)
    if RequestRaidInfo then RequestRaidInfo() end -- answers with UPDATE_INSTANCE_INFO
end)

Addon:RegisterEvent("UPDATE_INSTANCE_INFO", function() Stats:ReadLockouts() end)

Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if RequestRaidInfo then RequestRaidInfo() end
end)
