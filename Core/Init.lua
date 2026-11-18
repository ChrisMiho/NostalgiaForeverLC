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
    settings = Engine.DEFAULT_SETTINGS, -- leader's default rules (raids without a preset)
    raidPresets = {},                   -- [raidKey] = leader's saved rules for that raid
    minLootQuality = 4,                 -- only track epic+ drops (restricted items always shown)
    announceChannel = "RAID_WARNING",   -- RAID_WARNING or RAID
    rollTimeout = 30,                   -- seconds; 0 = no auto-close
    learnedLoot = {},                   -- [raidKey] = { [itemID] = true } items seen dropping
    learnedInstances = {},              -- [instanceID] = raidKey (filled at runtime)
    session = nil,                      -- persisted session (reserves survive /reload)
    ledger = { runs = {} },             -- every raid run with the addon: drops and who got them
    ledgerBackups = {},                 -- { {time=, reason=, ledger=} ... } newest first
    disenchanter = "",                  -- who unwanted items go to for disenchanting (default: the loot master)
    banker = "",                        -- who holds items for the guild bank (default: the loot master)
    tooltips = true,                    -- show reserve info on item tooltips everywhere
    minimap = { hide = false },
}

local CHAR_DEFAULTS = {
    framePositions = {},
    wishlists = {},                     -- [raidKey] = { hard = {itemID...}, soft = {itemID...} } in priority order
    lastSeenRules = {},                 -- [raidKey] = last rules the raid leader used (for previews)
    raidStats = {},                     -- [raidKey] = Engine stats (clears, boss kills this lockout)
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
--   SETTINGS_CHANGED(old, new, oldRaid, newRaid, oldLocked, newLocked)  leader's rules arrived/changed (members)
--   RULES_NOTICE(text)         human-readable summary of a rules change (members)
--   APPROVAL_NEEDED(raidKey)   raid leader should approve the reserve counts
--   ROSTER_CHANGED             who has the addon / who has sent reserves changed
--   STATS_CHANGED              raid kill / clear stats changed
--   LEDGER_CHANGED             the loot ledger gained / lost an entry
--   AWARD_UNDONE(itemID, winner)  the loot master took an award back

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

-- Equip location ("INVTYPE_HEAD", "" for non-gear). Uses the instant API so
-- it works before the item is cached; nil only when the item is unknown.
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

function Addon:GetItemEquipLoc(itemID)
    if GetItemInfoInstant then
        local _, _, _, equipLoc = GetItemInfoInstant(itemID)
        if equipLoc then return equipLoc end
    end
    return (select(9, GetItemInfo(itemID)))
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

-- "Name-Realm": how clients on other realms know the local player.
function Addon:FullPlayerName()
    local name, realm = UnitName("player")
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Is this name (as another client wrote it) the local player?
function Addon:IsMe(name)
    return name ~= nil and (name == self:PlayerName() or name == self:FullPlayerName())
end

-- The key the local player is stored under in a name-keyed table, if any.
function Addon:MyKeyIn(tbl)
    local short, full = self:PlayerName(), self:FullPlayerName()
    if tbl[short] ~= nil then return short end
    if tbl[full] ~= nil then return full end
end

-- Chat output. The modern client moved SendChatMessage into C_ChatInfo.
function Addon:SendChat(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    return send(msg, channel, nil, target)
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

-- The raid member a typed name refers to (case-insensitive, realm optional),
-- as the roster knows them; nil when nobody in the raid matches.
function Addon:FindRaidMember(name)
    if not name or not IsInRaid() then return nil end
    local want = name:lower()
    local wantShort = want:gsub("%-.*$", "")
    local byShort
    for i = 1, GetNumGroupMembers() do
        local full = GetRaidRosterInfo(i)
        if full then
            local norm = self:NormalizeName(full)
            if norm:lower() == want or full:lower() == want then return norm end
            if norm:lower():gsub("%-.*$", "") == wantShort then byShort = byShort or norm end
        end
    end
    return byShort
end

-- Who runs loot: the raid leader, or the assistant the leader put in charge
-- (falls back to the leader when that player left or lost assist).
function Addon:GetLootMasterName()
    local leader = self:GetLeaderName()
    local lm = self.session and self.session.lootMaster
    if lm and lm ~= leader and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and self:NormalizeName(name) == lm and (rank or 0) >= 1 then return lm end
        end
    end
    return leader
end

function Addon:IsLootMaster()
    if not IsInRaid() then return self:IsLeader() end
    return self:IsMe(self:GetLootMasterName())
end

-- classID, subclassID of an item (4 = armor; 1-4 cloth..plate, 6 shield).
function Addon:GetItemClass(itemID)
    if GetItemInfoInstant then
        local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
        return classID, subclassID
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
        self.session.approved = saved.approved and saved.raidKey ~= nil or false
        self.session.lootMaster = saved.lootMaster
        self.session.log = saved.log or {}
        self.session.imported = saved.imported or {}
        self.session.kills = saved.kills or 0
    end
    self.session.log = self.session.log or {}           -- leader: reserve changes after approval
    self.session.imported = self.session.imported or {} -- leader: [player] = true, reserves entered by the leader
    self.session.kills = self.session.kills or 0        -- bosses killed since approval

    -- Migrate pre-0.2 flat picks into the current raid's wishlist.
    local old = self.charDB.myReserves
    if old and self.session.raidKey and ((old.hard and #old.hard > 0) or (old.soft and #old.soft > 0)) then
        if not self.charDB.wishlists[self.session.raidKey] then
            self.charDB.wishlists[self.session.raidKey] = { hard = old.hard or {}, soft = old.soft or {} }
        end
    end
    self.charDB.myReserves = nil

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
        approved = self.session.approved,
        lootMaster = self.session.lootMaster,
        log = self.session.log,
        imported = self.session.imported,
        kills = self.session.kills,
    }
end)

Addon:RegisterEvent("ENCOUNTER_START", function(self) self.inEncounter = true end)
Addon:RegisterEvent("ENCOUNTER_END", function(self, _, encounterID, encounterName, _, _, success)
    self.inEncounter = false
    self:Fire("ENCOUNTER_ENDED", encounterID, encounterName, success == 1 or success == true)
end)
