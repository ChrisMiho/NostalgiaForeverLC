-- IDontWannaLC - Reserves
-- Player-side reserve picking and leader-side authority over the reserve list.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine

local Reserves = {}
ns.Reserves = Reserves
Addon.Reserves = Reserves

local pushTimer, syncTimer

local function qualityLookup(itemID)
    return Addon:GetItemQuality(itemID)
end

---------------------------------------------------------------------------
-- Local player picks
---------------------------------------------------------------------------
function Reserves:GetMine()
    local mine = Addon.charDB.myReserves
    mine.hard = mine.hard or {}
    mine.soft = mine.soft or {}
    return mine.hard, mine.soft
end

function Reserves:IsMine(itemID, kind)
    local hard, soft = self:GetMine()
    local list = kind == Engine.KIND.HARD and hard or soft
    for _, id in ipairs(list) do
        if id == itemID then return true end
    end
    return false
end

-- Validate against the shared session (limits, lock, other players' HRs)
-- using a scratch copy of my reserves so local picks stay authoritative here.
local function validate(itemID, kind)
    local session = Addon.session
    local me = Addon:PlayerName()
    local saved = session.reserves[me]
    local hard, soft = Reserves:GetMine()
    session.reserves[me] = { hard = { unpack(hard) }, soft = { unpack(soft) } }
    local ok, err = session:CanReserve(me, itemID, kind, qualityLookup(itemID))
    session.reserves[me] = saved
    return ok, err
end

function Reserves:Add(itemID, kind)
    local ok, err = validate(itemID, kind)
    if not ok then
        Addon:Print("|cffff5555Can't reserve|r %s: %s", Addon:GetItemLink(itemID) or itemID, err)
        return false, err
    end
    local hard, soft = self:GetMine()
    table.insert(kind == Engine.KIND.HARD and hard or soft, itemID)
    self:Changed()
    return true
end

function Reserves:Remove(itemID, kind)
    if Addon.session.locked then
        Addon:Print("Reserves are locked by the raid leader.")
        return false
    end
    local hard, soft = self:GetMine()
    local list = kind == Engine.KIND.HARD and hard or soft
    for i, id in ipairs(list) do
        if id == itemID then
            table.remove(list, i)
            self:Changed()
            return true
        end
    end
    return false
end

function Reserves:Toggle(itemID, kind)
    if self:IsMine(itemID, kind) then
        return self:Remove(itemID, kind)
    end
    return self:Add(itemID, kind)
end

function Reserves:ClearMine()
    if Addon.session.locked then return false end
    Addon.charDB.myReserves = { hard = {}, soft = {} }
    self:Changed()
    return true
end

-- Debounced push of my full set to the raid (leader applies it).
function Reserves:Changed()
    Addon:Fire("MY_RESERVES_CHANGED")
    if pushTimer then pushTimer:Cancel() end
    pushTimer = C_Timer.NewTimer(1.0, function()
        pushTimer = nil
        Reserves:Push()
    end)
end

function Reserves:Push()
    if not IsInRaid() then return end
    local hard, soft = self:GetMine()
    if Addon:IsLeader() then
        self:LeaderApply(Addon:PlayerName(), hard, soft)
    else
        ns.Comm:SendMyReserves(Addon.session.raidKey, hard, soft)
    end
end

-- After the leader syncs, make local picks match what the leader accepted.
-- If the leader doesn't have me at all yet, (re)send my picks.
Addon:On("RESERVES_SYNCED", function()
    if pushTimer or Addon:IsLeader() then return end
    local r = Addon.session.reserves[Addon:PlayerName()]
    if r then
        Addon.charDB.myReserves = { hard = { unpack(r.hard) }, soft = { unpack(r.soft) } }
        Addon:Fire("MY_RESERVES_CHANGED")
    else
        local hard, soft = Reserves:GetMine()
        if #hard + #soft > 0 and not Addon.session.locked then Reserves:Changed() end
    end
end)

-- Leader wiped all reserves: drop my local picks too.
function Reserves:OnRemoteReset()
    Addon.charDB.myReserves = { hard = {}, soft = {} }
    Addon.session.reserves = {}
    Addon.session.awards = {}
    Addon:Fire("MY_RESERVES_CHANGED")
    Addon:Fire("RESERVES_CHANGED")
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
                rej.itemID and (Addon:GetItemLink(rej.itemID) or rej.itemID) or "", rej.reason)
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
        ns.Comm:SendReject(sender, 0, "", "reserves are for a different raid (" .. session.raidKey .. ")")
        return
    end
    self:LeaderApply(sender, hard, soft)
end

function Reserves:LeaderSetCounts(hard, soft)
    if not Addon:IsLeader() then return false end
    Addon.session:SetSettings({ hardReserves = hard, softReserves = soft })
    Addon.db.settings.hardReserves, Addon.db.settings.softReserves = hard, soft
    self:LeaderBroadcast()
    return true
end

function Reserves:LeaderSetOption(key, value)
    if not Addon:IsLeader() then return false end
    Addon.session:SetSettings({ [key] = value })
    Addon.db.settings[key] = value
    self:LeaderBroadcast()
    return true
end

function Reserves:LeaderSetLocked(locked)
    if not Addon:IsLeader() then return false end
    Addon.session:SetLocked(locked)
    self:LeaderBroadcast()
    if IsInRaid() then
        SendChatMessage(("[IDWLC] Reserves are now %s."):format(locked and "LOCKED" or "OPEN"), "RAID")
    end
    return true
end

function Reserves:LeaderSetRaid(raidKey)
    if not Addon:IsLeader() then return false end
    Addon.session.raidKey = raidKey
    self:LeaderBroadcast()
    return true
end

function Reserves:LeaderReset()
    if not Addon:IsLeader() then return false end
    Addon.session.reserves = {}
    Addon.session.awards = {}
    Addon.session:SetLocked(false)
    Addon.charDB.myReserves = { hard = {}, soft = {} }
    Addon:Fire("MY_RESERVES_CHANGED")
    Addon:Fire("RESERVES_CHANGED")
    ns.Comm:Raid("RESET")
    self:LeaderBroadcast()
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

function Reserves:LeaderBroadcast()
    Addon:Fire("SESSION_CHANGED")
    if IsInRaid() then
        ns.Comm:SendConfig()
        self:ScheduleSync()
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

-- When the leader (re)becomes leader or joins, announce config.
-- When a member joins, push their picks once config arrives.
Addon:On("SESSION_CHANGED", function()
    if not Addon:IsLeader() and IsInRaid() and not Addon.session.locked then
        local hard, soft = Reserves:GetMine()
        if #hard + #soft > 0 and not Reserves.pushedOnce then
            Reserves.pushedOnce = true
            Reserves:Changed()
        end
    end
end)

Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function(self)
    if not IsInRaid() then
        Reserves.pushedOnce = false
        return
    end
    if self:IsLeader() and not Reserves.wasLeader then
        Reserves.wasLeader = true
        Reserves:LeaderBroadcast()
        local hard, soft = Reserves:GetMine()
        Reserves:LeaderApply(self:PlayerName(), hard, soft)
    elseif not self:IsLeader() then
        Reserves.wasLeader = false
    end
end)
