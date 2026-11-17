-- IDontWannaLC - Init
-- Addon namespace, saved variables, event dispatch and small WoW API
-- compatibility wrappers (WoW Forever runs the modern client; Classic Era
-- clients are supported for testing).

local ADDON_NAME, ns = ...
local Engine = ns.Engine

local Addon = {}
ns.Addon = Addon
_G.IDontWannaLC = Addon -- public handle for macros / debugging

Addon.name = ADDON_NAME
Addon.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "dev"
Addon.PREFIX = "IDWLC"
Addon.COLOR = "|cff33ff99"

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DB_DEFAULTS = {
    settings = Engine.DEFAULT_SETTINGS, -- leader's preferred settings
    minLootQuality = 4,                 -- only track epic+ drops (restricted items always shown)
    announceChannel = "RAID_WARNING",   -- RAID_WARNING or RAID
    rollTimeout = 30,                   -- seconds; 0 = no auto-close
    learnedLoot = {},                   -- [raidKey] = { [itemID] = true } items seen dropping
    learnedInstances = {},              -- [instanceID] = raidKey (filled at runtime)
    session = nil,                      -- persisted session (reserves survive /reload)
    minimap = { hide = false },
}

local CHAR_DEFAULTS = {
    framePositions = {},
    myReserves = {},                    -- { hard = {itemID}, soft = {itemID} } this character's picks
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
end

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
function Addon:Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage(Addon.COLOR .. "IDWLC|r: " .. tostring(msg))
end

function Addon:Debug(msg, ...)
    if self.db and self.db.debug then self:Print("|cff999999" .. msg .. "|r", ...) end
end

---------------------------------------------------------------------------
-- Callbacks (simple internal pub/sub so UI can react to state changes)
---------------------------------------------------------------------------
local callbacks = {}

function Addon:On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

function Addon:Fire(event, ...)
    for _, fn in ipairs(callbacks[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- Internal events fired:
--   SESSION_CHANGED            settings / lock / raid changed
--   RESERVES_CHANGED           any reserve list changed
--   MY_RESERVES_CHANGED        local player's picks changed
--   LOOT_LIST_CHANGED          leader's pending loot list changed
--   ROLL_STARTED(entry)        an item roll started (everyone)
--   ROLL_UPDATED(entry)        a roll was recorded (leader)
--   ROLL_ENDED(entry, winner)  item awarded / roll ended
--   RESERVE_REJECTED(itemID, kind, reason)

---------------------------------------------------------------------------
-- WoW API compatibility
---------------------------------------------------------------------------
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

function Addon:GetItemInfo(itemID)
    return GetItemInfo(itemID)
end

-- Returns quality or nil if item isn't cached yet.
function Addon:GetItemQuality(itemID)
    local _, _, quality = GetItemInfo(itemID)
    return quality
end

function Addon:GetItemLink(itemID)
    local _, link = GetItemInfo(itemID)
    return link
end

function Addon:GetLootMethod()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        return C_PartyInfo.GetLootMethod()
    elseif _G.GetLootMethod then
        return _G.GetLootMethod()
    end
end

-- Strip realm from names coming from the same realm; keep "Name-Realm" otherwise.
-- Comparisons always use the short form returned by Ambiguate("none").
function Addon:NormalizeName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end

function Addon:PlayerName()
    return self:NormalizeName(UnitName("player"))
end

function Addon:IsLeader()
    return UnitIsGroupLeader("player") and true or false
end

-- The authority is the raid leader. (Assistants could be added later.)
function Addon:GetLeaderName()
    if not IsInRaid() then return nil end
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if rank == 2 then return self:NormalizeName(name) end
    end
end

function Addon:IsInRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

-- Raids only: the addon does nothing with loot outside raid groups in raid instances.
function Addon:IsActive()
    return IsInRaid() and self:IsInRaidInstance()
end

-- Is an addon-restriction (encounter lockdown on the modern client) active?
function Addon:IsRestricted()
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive)
        if ok and active then return true end
    end
    return self.inEncounter == true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
Addon.frame = frame
local handlers = {}

function Addon:RegisterEvent(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, Addon, event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Modules register an init function to run after saved variables load.
local initQueue = {}
function Addon:OnInit(fn) table.insert(initQueue, fn) end

Addon:RegisterEvent("ADDON_LOADED", function(self, _, name)
    if name ~= ADDON_NAME then return end
    IDontWannaLCDB = IDontWannaLCDB or {}
    IDontWannaLCCharDB = IDontWannaLCCharDB or {}
    applyDefaults(IDontWannaLCDB, DB_DEFAULTS)
    applyDefaults(IDontWannaLCCharDB, CHAR_DEFAULTS)
    self.db = IDontWannaLCDB
    self.charDB = IDontWannaLCCharDB

    -- Restore or create the reserve session.
    self.session = Engine.NewSession(self.db.settings)
    local saved = self.db.session
    if saved then
        self.session:SetSettings(saved.settings or {})
        self.session.reserves = saved.reserves or {}
        self.session.awards = saved.awards or {}
        self.session.locked = saved.locked or false
        self.session.raidKey = saved.raidKey
    end

    for _, fn in ipairs(initQueue) do
        local ok, err = pcall(fn, self)
        if not ok then geterrorhandler()(err) end
    end
end)

Addon:RegisterEvent("PLAYER_LOGOUT", function(self)
    if not self.session then return end
    self.db.session = {
        settings = self.session.settings,
        reserves = self.session.reserves,
        awards = self.session.awards,
        locked = self.session.locked,
        raidKey = self.session.raidKey,
    }
end)

Addon:RegisterEvent("ENCOUNTER_START", function(self) self.inEncounter = true end)
Addon:RegisterEvent("ENCOUNTER_END", function(self)
    self.inEncounter = false
    self:Fire("ENCOUNTER_ENDED")
end)
