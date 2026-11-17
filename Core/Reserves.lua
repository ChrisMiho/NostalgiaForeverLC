-- IDontWannaLC - Reserves
--
-- Players: keep a tiered (ordered) wishlist of hard and soft picks for every
-- raid, built ahead of time from the raid catalogue. When they are in a raid,
-- the top entries that fit the leader's slot counts are sent as their
-- reserves automatically; everything else waits on standby. If the leader
-- changes the slot counts, selections are recomputed and re-sent.
--
-- Raid leader: the authority. Validates every player's set, syncs the full
-- reserve list, and keeps a saved settings preset per raid so a new raid
-- group starts with the right rules already in place.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine
local KIND = Engine.KIND

local Reserves = {}
ns.Reserves = Reserves
Addon.Reserves = Reserves

local pushTimer, syncTimer, announceTimer
local lastPushed -- "raidKey|encoded set" of the last set we sent

local function qualityLookup(itemID)
    return Addon:GetItemQuality(itemID)
end

local function itemText(id)
    return Addon:GetItemLink(id) or ("item:" .. tostring(id))
end

---------------------------------------------------------------------------
-- Wishlists (per character, per raid)
---------------------------------------------------------------------------
-- `create` stores a new empty list; otherwise browsing a raid doesn't
-- leave empty entries behind in SavedVariables.
function Reserves:GetWishlist(raidKey, create)
    raidKey = raidKey or Addon.session.raidKey
    if not raidKey then return { hard = {}, soft = {} } end
    local all = Addon.charDB.wishlists
    local w = all[raidKey]
    if not w then
        w = { hard = {}, soft = {} }
        if create then all[raidKey] = w end
    end
    w.hard = w.hard or {}
    w.soft = w.soft or {}
    return w
end

-- Settings used to preview a raid's selection. For the raid the leader has
-- set up we use the live rules; for other raids, the last rules seen for it.
function Reserves:SettingsFor(raidKey)
    local s = Addon.session
    if raidKey == s.raidKey then return s.settings end
    return Addon.charDB.lastSeenRules[raidKey] or s.settings
end

-- selectedHard, selectedSoft, standbyHard, standbySoft for a raid.
function Reserves:GetSelection(raidKey)
    raidKey = raidKey or Addon.session.raidKey
    return Engine.SelectFromWishlist(self:GetWishlist(raidKey), self:SettingsFor(raidKey), qualityLookup)
end

-- My active reserves in the current raid (what gets sent to the leader).
function Reserves:GetMine()
    if not Addon.session.raidKey then return {}, {} end
    local hard, soft = self:GetSelection(Addon.session.raidKey)
    return hard, soft
end

local function indexOf(list, id)
    for i, v in ipairs(list) do
        if v == id then return i end
    end
end

function Reserves:IsWished(itemID, kind, raidKey)
    local w = self:GetWishlist(raidKey)
    return indexOf(w[kind] or {}, itemID) ~= nil
end

-- Is the item one of my *selected* reserves for the current raid?
function Reserves:IsMine(itemID, kind)
    local hard, soft = self:GetMine()
    return indexOf(kind == KIND.HARD and hard or soft, itemID) ~= nil
end

-- Position (1-based) of an item in a tier, plus whether it is selected.
function Reserves:GetRank(itemID, kind, raidKey)
    local w = self:GetWishlist(raidKey)
    local rank = indexOf(w[kind] or {}, itemID)
    if not rank then return nil end
    local hard, soft = self:GetSelection(raidKey)
    local selected = indexOf(kind == KIND.HARD and hard or soft, itemID) ~= nil
    return rank, selected
end

local function editable(raidKey)
    if raidKey == Addon.session.raidKey and Addon.session.locked and IsInRaid() then
        Addon:Print("Reserves for this raid are locked by the raid leader.")
        return false
    end
    return true
end

function Reserves:Add(itemID, kind, raidKey)
    raidKey = raidKey or Addon.session.raidKey
    if not raidKey then
        Addon:Print("Pick a raid first.")
        return false, "no raid"
    end
    if not editable(raidKey) then return false, "locked" end
    local rules = self:SettingsFor(raidKey)
    local q = qualityLookup(itemID)
    local minQ = rules.restrictedMinQuality or Engine.DEFAULT_SETTINGS.restrictedMinQuality
    if q and q >= minQ then
        Addon:Print("|cffff5555Can't reserve|r %s: restricted (legendary or higher).", itemText(itemID))
        return false, "restricted"
    end
    local w = self:GetWishlist(raidKey, true)
    local list = w[kind]
    if #list >= Engine.MAX_WISHLIST then
        Addon:Print("Your %s list for this raid is full (%d).", kind, Engine.MAX_WISHLIST)
        return false, "full"
    end
    if kind == KIND.HARD then
        if indexOf(w.hard, itemID) then return false, "already in hard list" end
        local si = indexOf(w.soft, itemID)
        if si then table.remove(w.soft, si) end -- moving it up to hard
    else
        if indexOf(w.hard, itemID) then
            Addon:Print("%s is already in your hard list.", itemText(itemID))
            return false, "already hard"
        end
        if indexOf(w.soft, itemID) and not rules.allowDoubleSoft then
            return false, "already in soft list"
        end
    end
    table.insert(list, itemID)
    self:Changed(raidKey)
    return true
end

function Reserves:Remove(itemID, kind, raidKey)
    raidKey = raidKey or Addon.session.raidKey
    if not editable(raidKey) then return false end
    local list = self:GetWishlist(raidKey)[kind]
    local i = indexOf(list, itemID)
    if not i then return false end
    table.remove(list, i)
    self:Changed(raidKey)
    return true
end

function Reserves:Toggle(itemID, kind, raidKey)
    if self:IsWished(itemID, kind, raidKey) then
        return self:Remove(itemID, kind, raidKey)
    end
    return self:Add(itemID, kind, raidKey)
end

-- Move an item up (delta < 0) or down (delta > 0) in its tier.
function Reserves:Move(itemID, kind, delta, raidKey)
    raidKey = raidKey or Addon.session.raidKey
    if not editable(raidKey) then return false end
    local list = self:GetWishlist(raidKey)[kind]
    local i = indexOf(list, itemID)
    if not i then return false end
    local j = math.max(1, math.min(#list, i + delta))
    if i == j then return false end
    table.remove(list, i)
    table.insert(list, j, itemID)
    self:Changed(raidKey)
    return true
end

function Reserves:ClearWishlist(raidKey)
    raidKey = raidKey or Addon.session.raidKey
    if not raidKey or not editable(raidKey) then return false end
    Addon.charDB.wishlists[raidKey] = { hard = {}, soft = {} }
    self:Changed(raidKey)
    return true
end

-- Remove an item I won from my wishlist so it doesn't come back next time.
function Reserves:RemoveWon(itemID, raidKey)
    local w = self:GetWishlist(raidKey)
    local i = indexOf(w.hard, itemID)
    if i then table.remove(w.hard, i) end
    i = indexOf(w.soft, itemID)
    if i then table.remove(w.soft, i) end
    Addon:Fire("MY_RESERVES_CHANGED")
end

---------------------------------------------------------------------------
-- Sending my selection
---------------------------------------------------------------------------
function Reserves:Changed(raidKey)
    Addon:Fire("MY_RESERVES_CHANGED")
    if raidKey and raidKey ~= Addon.session.raidKey then return end
    if pushTimer then pushTimer:Cancel() end
    pushTimer = C_Timer.NewTimer(1.0, function()
        pushTimer = nil
        Reserves:Push()
    end)
end

-- Send my current selection if it differs from what I last sent (or force).
function Reserves:Push(force)
    if not IsInRaid() or not Addon.session.raidKey then return end
    if Addon.session.locked then return end
    local hard, soft = self:GetMine()
    local key = Addon.session.raidKey .. "|" .. Engine.EncodeReserveSet(hard, soft)
    if key == lastPushed and not force then return end
    lastPushed = key
    if Addon:IsLeader() then
        self:LeaderApply(Addon:PlayerName(), hard, soft)
    else
        ns.Comm:SendMyReserves(Addon.session.raidKey, hard, soft)
    end
end

-- Short description of my selection, e.g. for notices.
function Reserves:DescribeMine()
    local hard, soft = self:GetMine()
    local function fmt(list)
        if #list == 0 then return "none" end
        local out = {}
        for _, id in ipairs(list) do out[#out + 1] = itemText(id) end
        return table.concat(out, ", ")
    end
    return ("HR: %s | SR: %s"):format(fmt(hard), fmt(soft))
end

-- The leader's rules changed (or arrived for the first time): tell the
-- player, remember the rules for this raid, and re-send the selection.
Addon:On("SETTINGS_CHANGED", function(old, new, oldRaid, newRaid, oldLocked, newLocked)
    if Addon:IsLeader() then return end
    if newRaid then
        Addon.charDB.lastSeenRules[newRaid] = {
            hardReserves = new.hardReserves, softReserves = new.softReserves,
            allowDoubleSoft = new.allowDoubleSoft, restrictedMinQuality = new.restrictedMinQuality,
        }
    end
    local lines = {}
    if oldRaid ~= newRaid then
        lines[#lines + 1] = ("Raid: %s (%d HR, %d SR per player)"):format(
            ns.RaidDataAPI:GetName(newRaid), new.hardReserves, new.softReserves)
    else
        for _, l in ipairs(Engine.DiffSettings(old, new)) do lines[#lines + 1] = l end
    end
    if oldLocked ~= newLocked then
        lines[#lines + 1] = newLocked and "Reserves LOCKED" or "Reserves OPEN"
    end
    if #lines > 0 then
        local msg = "Raid leader updated reserve rules: " .. table.concat(lines, "; ")
        Addon:Print(msg)
        Addon:Print("Your reserves: %s", Reserves:DescribeMine())
        Addon:Fire("RULES_NOTICE", msg)
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, "IDWLC: reserve rules changed - check /idwlc",
                ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
        end
    end
    Addon:Fire("MY_RESERVES_CHANGED")
    if oldRaid ~= newRaid then lastPushed = nil end
    Reserves:Push()
end)

-- If the leader's list doesn't have me at all (they reset, or a new leader
-- took over), send my selection again.
Addon:On("RESERVES_SYNCED", function()
    if pushTimer or Addon:IsLeader() then return end
    if not Addon.session.reserves[Addon:PlayerName()] then
        local hard, soft = Reserves:GetMine()
        if #hard + #soft > 0 then Reserves:Push(true) end
    end
end)

function Reserves:OnRemoteReset()
    Addon.session.reserves = {}
    Addon.session.awards = {}
    lastPushed = nil
    Addon:Fire("RESERVES_CHANGED")
    self:Changed()
end

-- Won an item: take it off my wishlist.
Addon:On("ROLL_ENDED", function(entry, winner)
    if winner and entry and entry.itemID and winner == Addon:PlayerName() then
        Reserves:RemoveWon(entry.itemID, Addon.session.raidKey)
    end
end)

---------------------------------------------------------------------------
-- Leader presets (per raid, saved in the leader's SavedVariables)
---------------------------------------------------------------------------
local PRESET_KEYS = { "hardReserves", "softReserves", "allowDoubleSoft", "consumeOnAward", "restrictedMinQuality" }

-- Saved rules for a raid, or the leader's general defaults.
function Reserves:GetPreset(raidKey)
    local p = raidKey and Addon.db.raidPresets[raidKey]
    local out = {}
    for _, k in ipairs(PRESET_KEYS) do
        local v
        if p and p[k] ~= nil then v = p[k] else v = Addon.db.settings[k] end
        out[k] = v
    end
    return out, p ~= nil
end

function Reserves:HasPreset(raidKey)
    return raidKey and Addon.db.raidPresets[raidKey] ~= nil
end

local function savePreset()
    local s = Addon.session
    local target = {}
    for _, k in ipairs(PRESET_KEYS) do target[k] = s.settings[k] end
    if s.raidKey then
        Addon.db.raidPresets[s.raidKey] = target
    end
    -- Also the general default for raids that have no preset yet.
    for k, v in pairs(target) do Addon.db.settings[k] = v end
end

-- Announce the rules in raid chat (debounced so +/- clicks don't spam).
function Reserves:AnnounceRules()
    if not IsInRaid() or not Addon:IsLeader() then return end
    if announceTimer then announceTimer:Cancel() end
    announceTimer = C_Timer.NewTimer(3.0, function()
        announceTimer = nil
        local s = Addon.session
        SendChatMessage(("[IDWLC] %s: %d hard / %d soft reserves per player%s. Reserves are %s - /idwlc to pick."):format(
            ns.RaidDataAPI:GetName(s.raidKey), s.settings.hardReserves, s.settings.softReserves,
            s.settings.allowDoubleSoft and ", double SR allowed" or "",
            s.locked and "LOCKED" or "open"), "RAID")
    end)
end

---------------------------------------------------------------------------
-- Leader authority
---------------------------------------------------------------------------
function Reserves:ScheduleSync()
    if not Addon:IsLeader() then return end
    if syncTimer then syncTimer:Cancel() end
    syncTimer = C_Timer.NewTimer(2.0, function()
        syncTimer = nil
        ns.Comm:SendSync()
    end)
end

function Reserves:LeaderApply(player, hard, soft)
    local ok, rejected = Addon.session:ReplacePlayer(player, hard, soft, qualityLookup)
    local me = Addon:PlayerName()
    for _, rej in ipairs(rejected or {}) do
        if player == me then
            Addon:Print("|cffff5555Reserve rejected|r %s: %s",
                rej.itemID and itemText(rej.itemID) or "", rej.reason)
        else
            ns.Comm:SendReject(player, rej.itemID, rej.kind, rej.reason)
        end
    end
    Addon:Fire("RESERVES_CHANGED")
    if ok then self:ScheduleSync() end
end

-- Incoming SET from a raid member.
function Reserves:LeaderApplyPlayerSet(sender, raidKey, encoded)
    if sender == Addon:PlayerName() then return end -- own echo; applied locally
    local hard, soft = Engine.DecodeReserveSet(encoded)
    if not hard then return end
    local session = Addon.session
    if session.raidKey and raidKey ~= "" and raidKey ~= session.raidKey then
        return -- stale set for a previous raid; they'll re-send after CFG
    end
    self:LeaderApply(sender, hard, soft)
end

-- Players who have more reserves than the current limits allow are trimmed
-- (they re-send a correct selection from their tiers right away anyway).
local function trimToLimits()
    local s = Addon.session
    for _, r in pairs(s.reserves) do
        while #r.hard > s.settings.hardReserves do table.remove(r.hard) end
        while #r.soft > s.settings.softReserves do table.remove(r.soft) end
    end
end

function Reserves:LeaderSetCounts(hard, soft)
    if not Addon:IsLeader() then return false end
    Addon.session:SetSettings({ hardReserves = hard, softReserves = soft })
    trimToLimits()
    savePreset()
    lastPushed = nil
    self:Push() -- re-select my own reserves from my tiers
    self:LeaderBroadcast(true)
    return true
end

function Reserves:LeaderSetOption(key, value)
    if not Addon:IsLeader() then return false end
    Addon.session:SetSettings({ [key] = value })
    savePreset()
    lastPushed = nil
    self:Push()
    self:LeaderBroadcast(true)
    return true
end

function Reserves:LeaderSetLocked(locked)
    if not Addon:IsLeader() then return false end
    Addon.session:SetLocked(locked)
    if not locked then
        lastPushed = nil
        self:Push()
    end
    self:LeaderBroadcast(true)
    return true
end

-- Switch raid: load the saved preset for it and start a fresh reserve list
-- (everyone re-sends their selection for the new raid automatically).
function Reserves:LeaderSetRaid(raidKey)
    if not Addon:IsLeader() then return false end
    local s = Addon.session
    if raidKey ~= s.raidKey then
        s.reserves = {}
        s.awards = {}
    end
    s.raidKey = raidKey
    s:SetSettings((self:GetPreset(raidKey)))
    lastPushed = nil
    self:LeaderBroadcast(true)
    self:Push()
    return true
end

function Reserves:LeaderReset()
    if not Addon:IsLeader() then return false end
    Addon.session.reserves = {}
    Addon.session.awards = {}
    Addon.session:SetLocked(false)
    lastPushed = nil
    Addon:Fire("RESERVES_CHANGED")
    ns.Comm:Raid("RESET")
    self:LeaderBroadcast(true)
    self:Push()
    return true
end

-- Leader override: remove someone's reserve (ignores lock).
function Reserves:LeaderRemove(player, itemID, kind)
    if not Addon:IsLeader() then return false end
    local ok = Addon.session:RemoveReserve(player, itemID, kind, true)
    if ok then
        Addon:Fire("RESERVES_CHANGED")
        self:ScheduleSync()
    end
    return ok
end

-- Send settings (and the reserve list) to the raid; announce if asked.
function Reserves:LeaderBroadcast(announce)
    Addon:Fire("SESSION_CHANGED")
    Addon:Fire("MY_RESERVES_CHANGED")
    if IsInRaid() then
        ns.Comm:SendConfig()
        self:ScheduleSync()
        if announce then self:AnnounceRules() end
    end
end

-- Plain-text export of all reserves (for pasting into Discord etc.).
function Reserves:Export()
    local lines = {}
    local names = {}
    for name in pairs(Addon.session.reserves) do table.insert(names, name) end
    table.sort(names)
    local function fmt(list)
        local parts = {}
        for _, id in ipairs(list) do
            local itemName = Addon:GetItemInfo(id)
            table.insert(parts, itemName or ("item:" .. id))
        end
        return table.concat(parts, ", ")
    end
    for _, name in ipairs(names) do
        local r = Addon.session.reserves[name]
        table.insert(lines, ("%s | HR: %s | SR: %s"):format(name, fmt(r.hard), fmt(r.soft)))
    end
    return table.concat(lines, "\n")
end

-- Becoming leader of a raid group: apply the saved preset for the raid,
-- broadcast it, and add my own selection.
Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function(self)
    if not IsInRaid() then
        lastPushed = nil
        Reserves.wasLeader = false
        return
    end
    if self:IsLeader() and not Reserves.wasLeader then
        Reserves.wasLeader = true
        if self.session.raidKey and not self.session.locked then
            self.session:SetSettings((Reserves:GetPreset(self.session.raidKey)))
        end
        lastPushed = nil
        Reserves:LeaderBroadcast(true)
        Reserves:Push()
    elseif not self:IsLeader() then
        Reserves.wasLeader = false
    end
end)
