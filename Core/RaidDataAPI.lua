-- IDontWannaLC - Raid data access
-- Lookups over Data/Raids.lua + Data/Forever.lua, plus loot learned at runtime
-- (WoW Forever raid loot tables aren't datamined yet, so every epic+ item seen
-- dropping in a raid is remembered and offered in the reserve browser).

local _, ns = ...
local Addon = ns.Addon
local RD = ns.RaidData

local RaidData = {}
ns.RaidDataAPI = RaidData
Addon.RaidData = RaidData

local LEARNED_BOSS = "Seen in raid"

-- WoW Forever reports interface 1600x; Classic Era 115xx etc.
function RaidData:IsForeverClient()
    local interface = select(4, GetBuildInfo()) or 0
    return interface >= 16000 and interface < 20000
end

-- Raids for the running client: WoW Forever raids on the Forever client,
-- Classic raids elsewhere (useful for testing on Classic Era).
function RaidData:GetAll()
    local list = self:IsForeverClient() and RD.foreverRaids or RD.raids
    local out = {}
    for _, raid in ipairs(list or {}) do table.insert(out, raid) end
    return out
end

function RaidData:Get(key)
    for _, raid in ipairs(self:GetAll()) do
        if raid.key == key then return raid end
    end
end

-- Map the current instance to a raid key using instance ID, a previously
-- learned ID, or the instance name (Forever instance IDs aren't published).
function RaidData:Detect()
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "raid" then return nil end
    local learned = Addon.db.learnedInstances[instanceID]
    if learned then return learned end
    for _, raid in ipairs(self:GetAll()) do
        for _, id in ipairs(raid.instanceIDs or {}) do
            if id == instanceID then return raid.key end
        end
    end
    for _, raid in ipairs(self:GetAll()) do
        local names = raid.instanceNames or { raid.name }
        for _, n in ipairs(names) do
            if n == name then
                Addon.db.learnedInstances[instanceID] = raid.key
                return raid.key
            end
        end
    end
    -- Unknown raid (e.g. a new WoW Forever raid not in the data yet).
    local key = "ID" .. tostring(instanceID)
    Addon.db.learnedInstances[instanceID] = key
    Addon.db.learnedNames = Addon.db.learnedNames or {}
    Addon.db.learnedNames[key] = name
    return key
end

function RaidData:GetName(key)
    local raid = self:Get(key)
    if raid then return raid.name end
    return (Addon.db.learnedNames and Addon.db.learnedNames[key]) or key or "?"
end

-- Bosses for the reserve browser: { {name=, items={ids}} ... } including learned loot.
function RaidData:GetBosses(key)
    local out = {}
    local known = {}
    local raid = self:Get(key)
    if raid then
        for _, boss in ipairs(raid.bosses or {}) do
            table.insert(out, boss)
            for _, id in ipairs(boss.items) do known[id] = true end
        end
    end
    local learned = Addon.db.learnedLoot[key]
    if learned then
        local extra = {}
        for id in pairs(learned) do
            if not known[id] then table.insert(extra, id) end
        end
        table.sort(extra)
        if #extra > 0 then table.insert(out, { name = LEARNED_BOSS, items = extra }) end
    end
    return out
end

-- Raids list for dropdowns, plus learned unknown raids.
function RaidData:GetChoices()
    local out = {}
    for _, raid in ipairs(self:GetAll()) do
        table.insert(out, { key = raid.key, name = raid.name, expansion = raid.expansion })
    end
    for key in pairs(Addon.db.learnedLoot) do
        if not self:Get(key) then
            table.insert(out, { key = key, name = self:GetName(key), expansion = "forever" })
        end
    end
    return out
end

function RaidData:Learn(key, itemID)
    if not key or not itemID then return end
    Addon.db.learnedLoot[key] = Addon.db.learnedLoot[key] or {}
    Addon.db.learnedLoot[key][itemID] = true
end
