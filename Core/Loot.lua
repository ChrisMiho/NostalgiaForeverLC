-- IDontWannaLC - Loot
-- Leader side: collect drops (corpse loot window, items the leader receives,
-- or manually added links), decide who may roll using the reserve rules,
-- track /roll results and announce the leader's decision.
--
-- The addon NEVER hands out loot itself. The raid leader loots / trades the
-- item; the addon only tells everyone who is entitled to it.
--
-- Member side: show the "item is up" popup and whether you may roll.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine
local MODE = Engine.MODE

local Loot = {}
ns.Loot = Loot
Addon.Loot = Loot

Loot.entries = {}      -- leader: { id, itemID, link, quality, source, state, decision, roll, winner }
Loot.active = nil      -- leader: entry currently being rolled for
Loot.remote = nil      -- members: { id, itemID, mode, eligible = {set} | nil }

local nextId = 1
local seenLootKeys = {}
local rollPattern
local closeTimer

local STATE = { PENDING = "pending", ROLLING = "rolling", DONE = "done", CANCELLED = "cancelled" }
Loot.STATE = STATE

local function announce(msg, channel)
    if not IsInRaid() then
        Addon:Print(msg)
        return
    end
    channel = channel or Addon.db.announceChannel
    if channel == "RAID_WARNING" and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        channel = "RAID"
    end
    SendChatMessage(msg, channel)
end

local function linkFor(entry)
    return entry.link or Addon:GetItemLink(entry.itemID) or ("item:" .. entry.itemID)
end

---------------------------------------------------------------------------
-- Collecting drops (leader)
---------------------------------------------------------------------------
function Loot:ShouldTrack(quality)
    if quality == nil then return false end
    return quality >= Addon.db.minLootQuality or Addon.session:IsRestricted(quality)
end

function Loot:AddItem(itemID, link, quality, source)
    if not itemID then return end
    quality = quality or Addon:GetItemQuality(itemID)
    local raidKey = Addon.session.raidKey or ns.RaidDataAPI:Detect()
    ns.RaidDataAPI:Learn(raidKey, itemID)

    local entry = {
        id = nextId,
        itemID = itemID,
        link = link,
        quality = quality,
        source = source,
        state = STATE.PENDING,
    }
    nextId = nextId + 1
    entry.decision = Addon.session:Resolve(itemID, quality)
    table.insert(self.entries, entry)
    Addon:Fire("LOOT_LIST_CHANGED")
    return entry
end

function Loot:GetEntry(id)
    for _, e in ipairs(self.entries) do
        if e.id == id then return e end
    end
end

-- Recompute decisions (e.g. after reserves changed or item info arrived).
function Loot:Refresh()
    for _, e in ipairs(self.entries) do
        if e.state == STATE.PENDING then
            e.quality = e.quality or Addon:GetItemQuality(e.itemID)
            e.decision = Addon.session:Resolve(e.itemID, e.quality)
        end
    end
    Addon:Fire("LOOT_LIST_CHANGED")
end

function Loot:ClearDone()
    local keep = {}
    for _, e in ipairs(self.entries) do
        if e.state == STATE.PENDING or e.state == STATE.ROLLING then table.insert(keep, e) end
    end
    self.entries = keep
    Addon:Fire("LOOT_LIST_CHANGED")
end

function Loot:RemoveEntry(id)
    for i, e in ipairs(self.entries) do
        if e.id == id then
            if self.active == e then self:CancelRoll() end
            table.remove(self.entries, i)
            Addon:Fire("LOOT_LIST_CHANGED")
            return true
        end
    end
end

local function scanLootWindow()
    if not Addon:IsLeader() or not Addon:IsActive() then return end
    local added = false
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = Engine.ItemIDFromLink(link)
        if itemID then
            local quality = select(3, Addon:GetItemInfo(link))
            if quality == nil then quality = select(5, GetLootSlotInfo(slot)) end
            local source = GetLootSourceInfo and GetLootSourceInfo(slot) or "?"
            local key = tostring(source) .. ":" .. itemID .. ":" .. slot
            if not seenLootKeys[key] and Loot:ShouldTrack(quality) then
                seenLootKeys[key] = true
                local entry = Loot:AddItem(itemID, link, quality, "corpse")
                entry.fromCorpse = true
                added = true
            end
        end
    end
    if added then Addon:Fire("LOOT_ADDED") end
end

Addon:RegisterEvent("LOOT_OPENED", scanLootWindow)

-- Leader received an item (group/personal loot style). Add it unless it
-- matches an item already collected from a corpse.
local function onChatLoot(self, _, msg)
    if not self:IsLeader() or not self:IsActive() then return end
    if not (msg:find(LOOT_ITEM_SELF:gsub("%%s.*", ""), 1, true) == 1) then return end
    local link = msg:match("(|c.-|h|r)")
    local itemID = Engine.ItemIDFromLink(link)
    if not itemID then return end
    local quality = select(3, Addon:GetItemInfo(link))
    if not Loot:ShouldTrack(quality) then return end
    for _, e in ipairs(Loot.entries) do
        if e.itemID == itemID and e.fromCorpse and not e.matchedBag then
            e.matchedBag = true
            return
        end
    end
    Loot:AddItem(itemID, link, quality, "bag")
    Addon:Fire("LOOT_ADDED")
end
Addon:RegisterEvent("CHAT_MSG_LOOT", onChatLoot)

-- Manual add (leader shift-clicks an item into the loot window / slash cmd).
function Loot:AddManual(linkOrID)
    if not Addon:IsLeader() then
        Addon:Print("Only the raid leader can add loot.")
        return
    end
    local itemID = Engine.ItemIDFromLink(linkOrID)
    if not itemID then
        Addon:Print("Not an item link: %s", tostring(linkOrID))
        return
    end
    local link = type(linkOrID) == "string" and linkOrID:find("|H") and linkOrID or nil
    return self:AddItem(itemID, link, nil, "manual")
end

---------------------------------------------------------------------------
-- Rolling (leader)
---------------------------------------------------------------------------
local function describe(decision)
    if decision.mode == MODE.RESTRICTED then
        return "RESTRICTED - raid leader decides"
    elseif decision.mode == MODE.HARD then
        return "HARD RESERVED by " .. table.concat(decision.eligible, ", ")
    elseif decision.mode == MODE.SOFT then
        return "SOFT RESERVED - only " .. table.concat(decision.eligible, ", ") .. " may /roll"
    end
    return "not reserved - open /roll"
end
Loot.Describe = describe

-- Auto-close the active roll after the configured timeout.
function Loot:StartTimer(entry)
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    local timeout = Addon.db.rollTimeout or 0
    if timeout <= 0 then return end
    local roll = entry.roll
    closeTimer = C_Timer.NewTimer(timeout, function()
        closeTimer = nil
        if Loot.active == entry and entry.roll == roll then Loot:CloseRoll() end
    end)
end

function Loot:StartRoll(id)
    if not Addon:IsLeader() then return end
    local entry = self:GetEntry(id)
    if not entry or entry.state ~= STATE.PENDING then return end
    if self.active and self.active ~= entry then
        Addon:Print("Finish the current roll first (%s).", linkFor(self.active))
        return
    end
    entry.quality = entry.quality or Addon:GetItemQuality(entry.itemID)
    entry.decision = Addon.session:Resolve(entry.itemID, entry.quality)
    entry.roll = Engine.NewRoll(entry.decision)
    entry.state = STATE.ROLLING
    self.active = entry

    local d = entry.decision
    local link = linkFor(entry)
    announce(("%s - %s"):format(link, describe(d)))
    if d.mode == MODE.RESTRICTED or (d.mode == MODE.HARD and #d.eligible == 1) then
        entry.roll:Close() -- no roll needed; leader confirms with Award
    else
        self:StartTimer(entry)
    end
    ns.Comm:SendRoll(entry.id, entry.itemID, d.mode, d.eligible)
    Addon:Fire("ROLL_STARTED", entry)
    Addon:Fire("LOOT_LIST_CHANGED")
end

-- Stop accepting rolls and announce the result (leader still has to Award).
function Loot:CloseRoll()
    local entry = self.active
    if not entry or not entry.roll then return end
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    entry.roll:Close()
    local winner, tied = entry.roll:Winner()
    local link = linkFor(entry)
    if winner then
        announce(("%s - highest roll: %s (%d). Awaiting raid leader."):format(
            link, winner, entry.roll.rolls[winner] or 0), "RAID")
        entry.suggested = winner
    elseif tied then
        announce(("%s - TIE between %s. Re-roll!"):format(link, table.concat(tied, ", ")), "RAID")
        -- Re-roll among the tied players only.
        local d = entry.decision
        entry.roll = Engine.NewRoll({ mode = d.mode, itemID = d.itemID, eligible = tied, hard = d.hard, soft = d.soft })
        ns.Comm:SendRoll(entry.id, entry.itemID, d.mode, tied)
        self:StartTimer(entry)
        Addon:Fire("ROLL_STARTED", entry)
    else
        announce(("%s - nobody rolled."):format(link), "RAID")
    end
    Addon:Fire("ROLL_UPDATED", entry)
end

-- The raid leader's final call. Records the award and announces it; the
-- leader then loots/trades the item to the player manually.
function Loot:Award(id, player)
    if not Addon:IsLeader() then return end
    local entry = self:GetEntry(id)
    if not entry or not player or player == "" then return end
    if closeTimer and self.active == entry then closeTimer:Cancel(); closeTimer = nil end
    entry.state = STATE.DONE
    entry.winner = player
    if entry.roll then entry.roll:Close() end
    if self.active == entry then self.active = nil end
    Addon.session:RecordAward(entry.itemID, player, entry.decision and entry.decision.mode, time())
    announce(("%s awarded to %s."):format(linkFor(entry), player))
    ns.Comm:SendAward(entry.id, entry.itemID, player)
    ns.Reserves:ScheduleSync()
    Addon:Fire("ROLL_ENDED", entry, player)
    Addon:Fire("RESERVES_CHANGED")
    self:Refresh()
end

function Loot:CancelRoll()
    local entry = self.active
    if not entry then return end
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    entry.state = STATE.PENDING
    entry.roll = nil
    self.active = nil
    ns.Comm:SendCancel(entry.id)
    Addon:Fire("ROLL_ENDED", entry, nil)
    Addon:Fire("LOOT_LIST_CHANGED")
end

-- Parse /roll results from system chat.
Addon:RegisterEvent("CHAT_MSG_SYSTEM", function(self, _, msg)
    local entry = Loot.active
    if not entry or not entry.roll or not entry.roll.open or not self:IsLeader() then return end
    rollPattern = rollPattern or Engine.FormatToPattern(RANDOM_ROLL_RESULT)
    local name, value, low, high = Engine.ParseRoll(msg, rollPattern)
    if not name then return end
    name = self:NormalizeName(name)
    local ok, reason = entry.roll:Record(name, value, low, high)
    if not ok then self:Debug("ignored roll %s %d: %s", name, value, reason) end
    Addon:Fire("ROLL_UPDATED", entry)
    -- Auto-close once every eligible player has rolled.
    local missing = entry.roll:Missing()
    if ok and missing and #missing == 0 then Loot:CloseRoll() end
end)

-- Re-resolve pending items when reserves change.
Addon:On("RESERVES_CHANGED", function()
    if Addon:IsLeader() and #Loot.entries > 0 then Loot:Refresh() end
end)

---------------------------------------------------------------------------
-- Member side
---------------------------------------------------------------------------
function Loot:OnRemoteRoll(id, itemID, mode, names)
    if Addon:IsLeader() or not id then return end
    local eligible
    if names ~= "*" and names ~= "+" then
        eligible = {}
        for n in (names or ""):gmatch("[^,]+") do eligible[n] = true end
    end
    self.remote = { id = id, itemID = itemID, mode = mode, eligible = eligible, unknownList = names == "+" }
    Addon:Fire("ROLL_STARTED", self.remote)
end

-- Can the local player roll on the item currently up? true/false/nil(unknown)
function Loot:CanIRoll()
    local r = self.remote
    if not r then return false end
    if r.mode == MODE.RESTRICTED then return false end
    if r.mode == MODE.HARD and r.eligible and not r.eligible[Addon:PlayerName()] then return false end
    if r.unknownList then return nil end
    if not r.eligible then return true end
    return r.eligible[Addon:PlayerName()] == true
end

function Loot:OnRemoteAward(id, itemID, winner)
    if Addon:IsLeader() then return end
    if self.remote and self.remote.id == id then self.remote = nil end
    if winner == Addon:PlayerName() then
        Addon:Print("You were awarded %s - the raid leader will trade it to you.",
            Addon:GetItemLink(itemID) or ("item:" .. tostring(itemID)))
    end
    -- Mirror the award locally so reserve views stay current until the next SYNC.
    Addon.session:RecordAward(itemID, winner, nil, time())
    Addon:Fire("ROLL_ENDED", { id = id, itemID = itemID }, winner)
end

function Loot:OnRemoteCancel(id)
    if Addon:IsLeader() then return end
    if self.remote and self.remote.id == id then
        self.remote = nil
        Addon:Fire("ROLL_ENDED", { id = id }, nil)
    end
end

function Loot:DoRoll()
    RandomRoll(1, 100)
end

-- Item info may arrive late; refresh decisions once it does.
Addon:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if Addon:IsLeader() and #Loot.entries > 0 then
        if Loot.refreshPending then return end
        Loot.refreshPending = true
        C_Timer.After(0.5, function()
            Loot.refreshPending = false
            Loot:Refresh()
        end)
    end
end)

-- Set the session raid automatically when the leader zones into a raid.
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
    if not self:IsLeader() or not self:IsInRaidInstance() then return end
    local key = ns.RaidDataAPI:Detect()
    if key and key ~= self.session.raidKey and not self.session.raidKey then
        ns.Reserves:LeaderSetRaid(key)
    end
end)
