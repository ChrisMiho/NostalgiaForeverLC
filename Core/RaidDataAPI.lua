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

-- Catalogue entries that group loot but aren't a boss you can kill.
local function isRealBoss(name)
    return name ~= "Trash" and name ~= LEARNED_BOSS and not name:find("Shared loot", 1, true)
end

-- WoW Forever reports interface 1600x; Classic Era 115xx etc.
function RaidData:IsForeverClient()
    local interface = select(4, GetBuildInfo()) or 0
    return interface >= 16000 and interface < 20000
end

-- Raids for the running client. Forever client: the Forever raids first,
-- then the Classic raids (for planning / reference), minus any Classic raid a
-- Forever raid borrows its loot from (Onyxia), so it isn't listed twice.
-- Other clients (Classic Era testing): the Classic raids only.
function RaidData:GetAll()
    local out = {}
    if not self:IsForeverClient() then
        for _, raid in ipairs(RD.raids or {}) do table.insert(out, raid) end
        return out
    end
    local borrowed = {}
    for _, raid in ipairs(RD.foreverRaids or {}) do
        table.insert(out, raid)
        if raid.lootFrom then borrowed[raid.lootFrom] = true end
    end
    for _, raid in ipairs(RD.raids or {}) do
        if not borrowed[raid.key] then table.insert(out, raid) end
    end
    return out
end

-- Any raid in the data, whether or not this client lists it.
local function findAny(key)
    for _, list in ipairs({ RD.raids or {}, RD.foreverRaids or {} }) do
        for _, raid in ipairs(list) do
            if raid.key == key then return raid end
        end
    end
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
        local bosses, tag = raid.bosses or {}, nil
        -- No loot table of its own yet: borrow one (e.g. Classic Onyxia).
        local source = #bosses == 0 and raid.lootFrom and findAny(raid.lootFrom)
        if source then bosses, tag = source.bosses or {}, " (classic)" end
        for _, boss in ipairs(bosses) do
            table.insert(out, tag and { name = boss.name .. tag, items = boss.items } or boss)
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

-- Card art / colour for a raid (see Data/RaidMeta.lua).
function RaidData:GetMeta(key)
    return (RD.meta and RD.meta[key]) or RD.defaultMeta
end

-- Number of killable bosses we know of (0 = unknown, e.g. new Forever raids).
function RaidData:GetBossCount(key)
    local meta = RD.meta and RD.meta[key]
    if meta and meta.bossCount then return meta.bossCount end
    local n = 0
    for _, boss in ipairs(self:GetBosses(key)) do
        if isRealBoss((boss.name:gsub(" %(classic%)$", ""))) then n = n + 1 end
    end
    return n
end

-- Raid key for an instance name as the game reports it (saved-instance list).
function RaidData:KeyForName(name)
    if not name then return nil end
    for _, raid in ipairs(self:GetAll()) do
        for _, n in ipairs(raid.instanceNames or { raid.name }) do
            if n == name then return raid.key end
        end
        local meta = RD.meta and RD.meta[raid.key]
        for _, n in ipairs(meta and meta.names or {}) do
            if n == name then return raid.key end
        end
    end
    for key, learned in pairs(Addon.db.learnedNames or {}) do
        if learned == name then return key end
    end
end

-- A boss's loot as rows for the catalogue: slot headers followed by their
-- items, "Misc / Quest" last.
function RaidData:GetLootRows(boss)
    return ns.Engine.GroupBySlot(boss and boss.items or {}, function(id) return Addon:GetItemEquipLoc(id) end)
end

-- Raids list for the home screen, plus learned unknown raids.
function RaidData:GetChoices()
    local out = {}
    for _, raid in ipairs(self:GetAll()) do
        table.insert(out, { key = raid.key, name = raid.name, expansion = raid.expansion, size = raid.size })
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
