-- IDontWannaLC - Loot
-- Loot master side (the raid leader, or the assistant the leader put in
-- charge of loot): collect drops (corpse loot window, items received, or
-- manually added links), decide who may roll using the reserve rules, track
-- /roll results, and record what the loot master decides: award to a player,
-- open a reserved item to everyone when no reserver takes it, send it to be
-- disenchanted or banked, undo a mistake, tick items off as handed out.
--
-- The addon NEVER hands out loot itself. The loot master loots / trades the
-- item; the addon only tells everyone who is entitled to it.
--
-- Everyone else: mirror the loot master's list (DROP / ROLL / AWARD ...
-- messages) so every loot window shows what dropped, who may roll and the
-- rolls as they come in (/roll results are public, so each client tracks
-- them).
--
-- Every drop and every award is written to the loot ledger (Core/Ledger.lua).

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine
local MODE = Engine.MODE

local Loot = {}
ns.Loot = Loot
Addon.Loot = Loot

Loot.entries = {}      -- { id, itemID, link, quality, source (boss), state, decision, roll, winner, special, traded }
Loot.active = nil      -- entry currently being rolled for
Loot.remote = nil      -- members: { id, itemID, mode, eligible = {set} | nil } for the roll popup

-- Outcomes that aren't a player winning the item.
Loot.SPECIAL = { DISENCHANT = "DISENCHANT", BANK = "BANK" }
local SPECIAL_TEXT = { DISENCHANT = "to be disenchanted", BANK = "for the guild bank" }

local nextId           -- loot master's drop ids; seeded from the clock so they don't repeat after /reload
local lastBoss, lastBossAt
local BOSS_WINDOW = 300 -- seconds after a kill that drops are credited to that boss
local OTHER_SOURCE = "Trash / other"
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
    Addon:SendChat(msg, channel)
end

local function linkFor(entry)
    return entry.link or Addon:GetItemLink(entry.itemID) or ("item:" .. entry.itemID)
end

local function isMaster()
    return Addon:IsLootMaster()
end

---------------------------------------------------------------------------
-- Collecting drops (loot master)
---------------------------------------------------------------------------
function Loot:ShouldTrack(quality)
    if quality == nil then return false end
    return quality >= Addon.db.minLootQuality or Addon.session:IsRestricted(quality)
end

-- Boss a drop is credited to: the last one killed, for a few minutes.
Addon:On("ENCOUNTER_ENDED", function(_, name, success)
    if success and name then lastBoss, lastBossAt = name, GetTime() end
end)

local function currentSource()
    if lastBoss and GetTime() - lastBossAt < BOSS_WINDOW then return lastBoss end
    return OTHER_SOURCE
end

function Loot:AddItem(itemID, link, quality, origin)
    if not itemID then return end
    quality = quality or Addon:GetItemQuality(itemID)
    local raidKey = Addon.session.raidKey or ns.RaidDataAPI:Detect()
    ns.RaidDataAPI:Learn(raidKey, itemID)

    nextId = nextId or (time() % 1000000) * 10
    nextId = nextId + 1
    local entry = {
        id = nextId,
        itemID = itemID,
        link = link,
        quality = quality,
        origin = origin, -- "corpse" | "bag" | "manual"
        source = currentSource(),
        state = STATE.PENDING,
    }
    entry.decision = Addon.session:Resolve(itemID, quality)
    table.insert(self.entries, entry)
    ns.Comm:SendDrop(entry.id, itemID, entry.source, ns.Ledger:Drop(entry))
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

-- Awarded items the loot master still has to hand over.
function Loot:Outstanding()
    local out = {}
    for _, e in ipairs(self.entries) do
        if e.state == STATE.DONE and not e.traded then out[#out + 1] = e end
    end
    return out
end

-- Tidy the window: items that are done AND handed out go (the ledger keeps
-- them); awarded items still to be traded stay as the "to hand out" list.
-- The loot master's clear is mirrored by everyone. all = true clears every
-- finished item regardless (a member tidying their own view).
function Loot:ClearDone(all)
    local master = isMaster()
    local keep = {}
    for _, e in ipairs(self.entries) do
        local finished = e.state == STATE.DONE and (e.traded or all)
        if not finished then table.insert(keep, e) end
    end
    self.entries = keep
    if master then ns.Comm:Raid("CLEAR") end
    Addon:Fire("LOOT_LIST_CHANGED")
end

-- Loot master: take a drop off the list again (added by mistake).
function Loot:RemoveEntry(id)
    if not isMaster() then return end
    for i, e in ipairs(self.entries) do
        if e.id == id then
            if self.active == e then self:CancelRoll() end
            table.remove(self.entries, i)
            ns.Comm:Raid("UNDROP", id)
            ns.Ledger:Remove(e)
            Addon:Fire("LOOT_LIST_CHANGED")
            return true
        end
    end
end

local function scanLootWindow()
    if not isMaster() or not Addon:IsActive() then return end
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

-- The loot master received an item (group/personal loot style). Add it
-- unless it matches an item already collected from a corpse.
local function onChatLoot(self, _, msg)
    if not isMaster() or not self:IsActive() then return end
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

-- Manual add (shift-click an item into the loot window / slash command).
function Loot:AddManual(linkOrID)
    if not isMaster() then
        Addon:Print("Only the loot master can add loot.")
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
-- Rolling (loot master)
---------------------------------------------------------------------------
local function describe(decision)
    if decision.mode == MODE.RESTRICTED then
        return "RESTRICTED - raid leader decides"
    elseif decision.mode == MODE.HARD and decision.eligible then
        if #decision.eligible == 1 then
            return "HARD RESERVED by " .. decision.eligible[1]
        end
        return "HARD RESERVED - only " .. table.concat(decision.eligible, ", ")
            .. " may /roll (soft reserves don't count)"
    elseif decision.mode == MODE.SOFT and decision.eligible then
        return "SOFT RESERVED - only " .. table.concat(decision.eligible, ", ") .. " may /roll"
    end
    if Addon.session.settings.msos then
        return ("not reserved - /roll 100 main spec, /roll %d off spec"):format(Engine.OS_ROLL)
    end
    return "not reserved - open /roll"
end
Loot.Describe = describe

-- A roll for a decision under the current rules: off-spec rolls and
-- plus-ones apply to unreserved items only.
local function newRoll(decision)
    local set = Addon.session.settings
    local opts = {}
    -- Only when it is open to everyone; a tie re-roll (named players) is a
    -- plain /roll 100 between equals.
    if decision.mode == MODE.OPEN and not decision.eligible then
        if set.msos then opts.osMax = Engine.OS_ROLL end
        if set.plusOnes then decision.plus = Addon.session:PlusOnes() end
    end
    return Engine.NewRoll(decision, opts)
end

-- Does the item up for roll take off-spec rolls?
function Loot:AllowsOffSpec(entry)
    entry = entry or self.active
    return entry ~= nil and entry.roll ~= nil and entry.roll.osMax ~= nil
end

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
    if not isMaster() then return end
    local entry = self:GetEntry(id)
    if not entry or entry.state ~= STATE.PENDING then return end
    if self.active and self.active ~= entry then
        Addon:Print("Finish the current roll first (%s).", linkFor(self.active))
        return
    end
    entry.quality = entry.quality or Addon:GetItemQuality(entry.itemID)
    local d = Addon.session:Resolve(entry.itemID, entry.quality)
    -- Soft reserve bonus for players who reserved this before and lost.
    if d.mode == MODE.SOFT then
        local bonus, any = {}, false
        for _, name in ipairs(d.eligible) do
            local b = ns.Ledger:SoftBonus(name, entry.itemID)
            if b > 0 then bonus[name], any = b, true end
        end
        if any then d.bonus = bonus end
    end
    entry.decision = d
    entry.roll = newRoll(d)
    entry.state = STATE.ROLLING
    entry.suggested, entry.fallback = nil, nil
    self.active = entry

    local link = linkFor(entry)
    local text = describe(d)
    if d.bonus then
        local parts = {}
        for _, name in ipairs(d.eligible) do
            if d.bonus[name] then parts[#parts + 1] = ("%s +%d"):format(name, d.bonus[name]) end
        end
        text = text .. " (bonus: " .. table.concat(parts, ", ") .. ")"
    end
    announce(("%s - %s"):format(link, text))
    if d.mode == MODE.RESTRICTED or (d.mode == MODE.HARD and #d.eligible == 1) then
        entry.roll:Close() -- no roll needed; the loot master confirms with Award
    else
        self:StartTimer(entry)
    end
    ns.Comm:SendRoll(entry.id, entry.itemID, d.mode, d.eligible, d.bonus)
    Addon:Fire("ROLL_STARTED", entry)
    Addon:Fire("LOOT_LIST_CHANGED")
end

-- Stop accepting rolls and announce the result (the loot master still has to Award).
function Loot:CloseRoll()
    if not isMaster() then return end -- e.g. loot was handed to someone else mid-roll
    local entry = self.active
    if not entry or not entry.roll then return end
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    if not entry.roll.open then return end -- already closed and announced
    entry.roll:Close()
    local winner, tied = entry.roll:Winner()
    local link = linkFor(entry)
    if winner then
        local top = entry.roll:Standings()[1]
        local score = top and (top.bonus > 0 and ("%d+%d"):format(top.value, top.bonus) or tostring(top.value)) or "-"
        if top and top.tier == 2 then score = score .. " off spec" end
        announce(("%s - %s wins the roll (%s). Awaiting the loot master."):format(link, winner, score), "RAID")
        entry.suggested = winner
        ns.Comm:Raid("CLOSE", entry.id)
    elseif tied then
        announce(("%s - TIE between %s. Re-roll!"):format(link, table.concat(tied, ", ")), "RAID")
        -- Re-roll among the tied players only (same footing: no bonus).
        local d = entry.decision
        entry.decision = { mode = d.mode, itemID = d.itemID, eligible = tied, hard = d.hard, soft = d.soft }
        entry.roll = newRoll(entry.decision)
        ns.Comm:SendRoll(entry.id, entry.itemID, d.mode, tied)
        self:StartTimer(entry)
        Addon:Fire("ROLL_STARTED", entry)
    else
        local reserved = entry.decision.mode == MODE.HARD or entry.decision.mode == MODE.SOFT
        announce(("%s - nobody rolled.%s"):format(link,
            reserved and " The loot master can open it to everyone." or ""), "RAID")
        ns.Comm:Raid("CLOSE", entry.id)
    end
    Addon:Fire("ROLL_UPDATED", entry)
end

-- No reserver took a reserved item (passed, offline, didn't roll): put it up
-- for everyone as an unreserved item.
function Loot:OpenToAll()
    if not isMaster() then return false end
    local entry = self.active
    if not entry or not entry.decision then return false end
    local mode = entry.decision.mode
    if mode ~= MODE.HARD and mode ~= MODE.SOFT then return false end
    if entry.roll and entry.roll.open then
        Addon:Print("Close the roll first - the reservers may still be rolling.")
        return false
    end
    local d = entry.decision
    entry.decision = { mode = MODE.OPEN, itemID = d.itemID, hard = d.hard, soft = d.soft }
    entry.roll = newRoll(entry.decision)
    entry.suggested, entry.fallback = nil, true
    announce(("%s - no reserver took it: now open to everyone. %s"):format(linkFor(entry), describe(entry.decision)))
    ns.Comm:SendRoll(entry.id, entry.itemID, MODE.OPEN, nil)
    self:StartTimer(entry)
    Addon:Fire("ROLL_STARTED", entry)
    Addon:Fire("LOOT_LIST_CHANGED")
    return true
end

local function finish(entry, winner)
    if closeTimer and Loot.active == entry then closeTimer:Cancel(); closeTimer = nil end
    entry.state = STATE.DONE
    entry.winner = winner
    if entry.roll then entry.roll:Close() end
    if Loot.active == entry then Loot.active = nil end
    -- Nothing to hand over when the loot master keeps it.
    entry.traded = Addon:IsMe(winner) or nil
end

-- The loot master's final call. Records the award and announces it; the
-- loot master then loots / trades the item to the player by hand.
function Loot:Award(id, player)
    if not isMaster() then return end
    local entry = self:GetEntry(id)
    if not entry or not player or player == "" then return end
    -- The winner has to be someone in the raid (a typo would otherwise be
    -- announced and written to the ledger).
    if IsInRaid() then
        local member = Addon:FindRaidMember(player)
        if not member then
            Addon:Print("|cffff5555%s is not in the raid|r - nothing awarded.", player)
            return false
        end
        player = member
    end
    local mode = entry.decision and entry.decision.mode
    -- An off-spec roll that won an open item is recorded as such (and
    -- doesn't count as a plus-one).
    if mode == MODE.OPEN and entry.roll and entry.roll.tiers[player] == 2 then mode = Engine.MODE_OFFSPEC end
    finish(entry, player)
    entry.special = nil
    Addon.session:RecordAward(entry.itemID, player, mode, time()).dropId = entry.id
    ns.Ledger:Award(entry, player, mode)
    announce(("%s awarded to %s."):format(linkFor(entry), player))
    ns.Comm:SendAward(entry.id, entry.itemID, player, mode)
    if entry.traded then
        ns.Ledger:SetTraded(entry, true)
        ns.Comm:Raid("TRADED", entry.id, 1)
    end
    ns.Reserves:ScheduleSync()
    Addon:Fire("ROLL_ENDED", entry, player)
    Addon:Fire("RESERVES_CHANGED")
    self:Refresh()
    return true
end

-- Nobody wants it: send it to be disenchanted or to the bank. Goes to the
-- player named in the Master Loot settings if they are in the raid, else it
-- stays with the loot master. Uses up nobody's reserve.
function Loot:AwardSpecial(id, kind)
    if not isMaster() or not Loot.SPECIAL[kind] then return false end
    local entry = self:GetEntry(id)
    if not entry then return false end
    local configured = kind == Loot.SPECIAL.BANK and Addon.db.banker or Addon.db.disenchanter
    local holder = (configured and configured ~= "" and Addon:FindRaidMember(configured)) or Addon:PlayerName()
    finish(entry, holder)
    entry.special = kind
    ns.Ledger:Award(entry, holder, kind)
    announce(("%s - %s (%s)."):format(linkFor(entry), SPECIAL_TEXT[kind], holder))
    ns.Comm:SendAward(entry.id, entry.itemID, holder, kind)
    if entry.traded then
        ns.Ledger:SetTraded(entry, true)
        ns.Comm:Raid("TRADED", entry.id, 1)
    end
    Addon:Fire("ROLL_ENDED", entry, nil)
    self:Refresh()
    return true
end

-- Take an award back (mis-click, wrong player): the item is pending again,
-- the winner's reserve returns and the ledger entry is cleared.
function Loot:UndoAward(id)
    if not isMaster() then return false end
    local entry = self:GetEntry(id)
    if not entry or entry.state ~= STATE.DONE then return false end
    local winner, special = entry.winner, entry.special
    entry.state, entry.winner, entry.special, entry.traded, entry.roll, entry.suggested = STATE.PENDING, nil, nil, nil, nil, nil
    if not special then Addon.session:RevertAward(entry.itemID, winner) end
    ns.Ledger:Unaward(entry)
    announce(("%s - the award to %s was undone."):format(linkFor(entry), tostring(winner)))
    ns.Comm:Raid("UNAWARD", entry.id, entry.itemID, winner or "", special and 1 or 0)
    ns.Reserves:ScheduleSync()
    Addon:Fire("AWARD_UNDONE", entry.itemID, winner)
    Addon:Fire("RESERVES_CHANGED")
    self:Refresh()
    return true
end

-- Tick an awarded item off as handed over (or untick it).
function Loot:SetTraded(id, traded)
    if not isMaster() then return false end
    local entry = self:GetEntry(id)
    if not entry or entry.state ~= STATE.DONE then return false end
    entry.traded = traded and true or nil
    ns.Ledger:SetTraded(entry, entry.traded)
    ns.Comm:Raid("TRADED", entry.id, traded and 1 or 0)
    Addon:Fire("LOOT_LIST_CHANGED")
    return true
end

function Loot:CancelRoll()
    local entry = self.active
    if not entry then return end
    if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    entry.state = STATE.PENDING
    entry.roll = nil
    entry.fallback = nil
    self.active = nil
    ns.Comm:SendCancel(entry.id)
    Addon:Fire("ROLL_ENDED", entry, nil)
    Addon:Fire("LOOT_LIST_CHANGED")
end

-- Parse /roll results from system chat.
Addon:RegisterEvent("CHAT_MSG_SYSTEM", function(self, _, msg)
    local entry = Loot.active
    if not entry or not entry.roll or not entry.roll.open then return end
    rollPattern = rollPattern or Engine.FormatToPattern(RANDOM_ROLL_RESULT)
    local name, value, low, high = Engine.ParseRoll(msg, rollPattern)
    if not name then return end
    name = self:NormalizeName(name)
    local ok, reason = entry.roll:Record(name, value, low, high)
    if not ok then self:Debug("ignored roll %s %d: %s", name, value, reason) end
    Addon:Fire("ROLL_UPDATED", entry)
    -- Loot master: auto-close once every eligible player has rolled.
    local missing = entry.roll:Missing()
    if isMaster() and ok and missing and #missing == 0 then Loot:CloseRoll() end
end)

-- Re-resolve pending items when reserves change.
Addon:On("RESERVES_CHANGED", function()
    if #Loot.entries > 0 then Loot:Refresh() end
end)

---------------------------------------------------------------------------
-- Trade tracking (loot master): a completed trade that contained an awarded
-- item, with the player it was awarded to, ticks it off as handed out.
---------------------------------------------------------------------------
local tradeTarget, tradeItems

Addon:RegisterEvent("TRADE_SHOW", function(self)
    local name = (GetUnitName and GetUnitName("NPC", true)) or UnitName("NPC")
    tradeTarget, tradeItems = name and self:NormalizeName(name) or nil, nil
end)

Addon:RegisterEvent("TRADE_ACCEPT_UPDATE", function(_, _, playerAccepted)
    if playerAccepted ~= 1 or not GetTradePlayerItemLink then return end
    tradeItems = {}
    for slot = 1, 6 do
        local id = Engine.ItemIDFromLink(GetTradePlayerItemLink(slot))
        if id then tradeItems[#tradeItems + 1] = id end
    end
end)

-- Called when a trade with `target` completed and included these items.
function Loot:OnTradeCompleted(target, itemIDs)
    if not isMaster() or not target then return end
    local short = Engine.ShortName(target)
    for _, itemID in ipairs(itemIDs or {}) do
        for _, e in ipairs(self.entries) do
            if e.state == STATE.DONE and not e.traded and e.itemID == itemID
                and Engine.ShortName(e.winner) == short then
                self:SetTraded(e.id, true)
                break
            end
        end
    end
end

Addon:RegisterEvent("UI_INFO_MESSAGE", function(_, _, _, message)
    if message and message == ERR_TRADE_COMPLETE and tradeTarget and tradeItems then
        Loot:OnTradeCompleted(tradeTarget, tradeItems)
        tradeItems = nil
    end
end)

---------------------------------------------------------------------------
-- Everyone else: mirror the loot master
---------------------------------------------------------------------------
-- The loot master collected a drop: show it in my loot window too.
function Loot:OnRemoteDrop(id, itemID, boss, runUid)
    if isMaster() or not id or not itemID then return end
    local old = self:GetEntry(id)
    if old and old.itemID == itemID then return old end
    if old then -- the loot master's ids restarted; the old entry is stale
        for i, e in ipairs(self.entries) do
            if e == old then table.remove(self.entries, i) break end
        end
    end
    local quality = Addon:GetItemQuality(itemID)
    local entry = {
        id = id, itemID = itemID, quality = quality,
        source = (boss and boss ~= "") and boss or OTHER_SOURCE,
        state = STATE.PENDING,
        decision = Addon.session:Resolve(itemID, quality),
    }
    table.insert(self.entries, entry)
    ns.Ledger:Drop(entry, runUid)
    Addon:Fire("LOOT_LIST_CHANGED")
    Addon:Fire("LOOT_ADDED")
    return entry
end

function Loot:OnRemoteUndrop(id)
    if isMaster() then return end
    for i, e in ipairs(self.entries) do
        if e.id == id then
            if self.active == e then self.active = nil end
            table.remove(self.entries, i)
            ns.Ledger:Remove(e)
            Addon:Fire("LOOT_LIST_CHANGED")
            return
        end
    end
end

-- The loot master started a roll (or a tie re-roll, or opened it to all).
-- names: "*" everyone, "+" too many to list, else "Ann,Bob:10" (":n" = bonus).
function Loot:OnRemoteRoll(id, itemID, mode, names)
    if isMaster() or not id then return end
    local eligible, list, bonus
    if names ~= "*" and names ~= "+" then
        eligible, list = {}, {}
        for token in (names or ""):gmatch("[^,]+") do
            local n, b = token:match("^(.-):(%d+)$")
            n = n or token
            eligible[n] = true
            list[#list + 1] = n
            if b then
                bonus = bonus or {}
                bonus[n] = tonumber(b)
            end
        end
        table.sort(list)
    end
    self.remote = { id = id, itemID = itemID, mode = mode, eligible = eligible, unknownList = names == "+" }

    -- Mirror it in the loot window and track the public /roll results.
    local entry = self:GetEntry(id)
    if not entry or entry.itemID ~= itemID then entry = self:OnRemoteDrop(id, itemID) end
    if entry then
        -- The loot master's word on mode and who may roll; when the list was
        -- too long to send ("+") fall back to what my copy of the reserves says.
        local d = Addon.session:Resolve(itemID, entry.quality or Addon:GetItemQuality(itemID))
        if list then
            d.mode, d.eligible = mode or d.mode, list
        elseif names == "*" then
            d.mode, d.eligible = mode or d.mode, nil
        end
        d.bonus = bonus
        entry.decision = d
        entry.roll = newRoll(d)
        if d.mode == MODE.RESTRICTED or (d.mode == MODE.HARD and d.eligible and #d.eligible == 1) then
            entry.roll:Close()
        end
        -- One roll at a time: anything else still marked as rolling is stale
        -- (the loot master reloaded, or I missed its end).
        for _, other in ipairs(self.entries) do
            if other ~= entry and other.state == STATE.ROLLING then other.state, other.roll = STATE.PENDING, nil end
        end
        entry.state = STATE.ROLLING
        self.active = entry
        Addon:Fire("LOOT_LIST_CHANGED")
    end
    Addon:Fire("ROLL_STARTED", self.remote)
end

-- Can the local player roll on the item currently up? true/false/nil(unknown)
function Loot:CanIRoll()
    local r = self.remote
    if not r then return false end
    if r.mode == MODE.RESTRICTED then return false end
    local listed = r.eligible and Addon:MyKeyIn(r.eligible) ~= nil
    if r.mode == MODE.HARD and r.eligible and not listed then return false end
    if r.unknownList then return nil end
    if not r.eligible then return true end
    return listed
end

-- mode: how it was decided, or DISENCHANT / BANK (nobody "won" it).
function Loot:OnRemoteAward(id, itemID, winner, mode)
    if isMaster() then return end
    if self.remote and self.remote.id == id then self.remote = nil end
    local special = mode and Loot.SPECIAL[mode] or nil
    local entry = self:GetEntry(id)
    if not entry or entry.itemID ~= itemID then entry = self:OnRemoteDrop(id, itemID) end
    if entry then
        if entry.roll then entry.roll:Close() end
        entry.state, entry.winner, entry.special = STATE.DONE, winner, special
        if self.active == entry then self.active = nil end
        ns.Ledger:Award(entry, winner, special or mode or (entry.decision and entry.decision.mode))
    end
    if special then
        Addon:Fire("ROLL_ENDED", { id = id, itemID = itemID }, nil)
        Addon:Fire("LOOT_LIST_CHANGED")
        return
    end
    if Addon:IsMe(winner) then
        Addon:Print("You were awarded %s - the loot master will trade it to you.",
            Addon:GetItemLink(itemID) or ("item:" .. tostring(itemID)))
    end
    -- Mirror the award (the raid leader's copy is the authoritative one and
    -- is synced out afterwards). The loot master repeats awards the leader
    -- may have missed, so the same drop is only ever recorded once.
    local known = false
    for _, a in ipairs(Addon.session.awards) do
        if a.dropId == id then known = true break end
    end
    if not known then
        Addon.session:RecordAward(itemID, winner, mode or (entry and entry.decision and entry.decision.mode), time()).dropId = id
    end
    if Addon:IsLeader() then ns.Reserves:ScheduleSync() end
    Addon:Fire("ROLL_ENDED", { id = id, itemID = itemID }, winner)
    Addon:Fire("RESERVES_CHANGED")
    Addon:Fire("LOOT_LIST_CHANGED")
end

function Loot:OnRemoteUnaward(id, itemID, winner, special)
    if isMaster() then return end
    local entry = self:GetEntry(id)
    if entry and entry.itemID == itemID then
        entry.state, entry.winner, entry.special, entry.traded, entry.roll = STATE.PENDING, nil, nil, nil, nil
        ns.Ledger:Unaward(entry)
    else
        ns.Ledger:Unaward({ id = id, itemID = itemID })
    end
    if not special then Addon.session:RevertAward(itemID, winner) end
    if Addon:IsLeader() then ns.Reserves:ScheduleSync() end
    Addon:Fire("AWARD_UNDONE", itemID, winner)
    Addon:Fire("RESERVES_CHANGED")
    self:Refresh()
end

-- The loot master stopped taking rolls for an item.
function Loot:OnRemoteClose(id)
    if isMaster() then return end
    local entry = self:GetEntry(id)
    if entry and entry.roll and entry.roll.open then
        entry.roll:Close()
        Addon:Fire("ROLL_UPDATED", entry)
    end
end

function Loot:OnRemoteTraded(id, traded)
    if isMaster() then return end
    local entry = self:GetEntry(id)
    if not entry then return end
    entry.traded = traded and true or nil
    ns.Ledger:SetTraded(entry, entry.traded)
    Addon:Fire("LOOT_LIST_CHANGED")
end

function Loot:OnRemoteCancel(id)
    if isMaster() then return end
    local entry = self:GetEntry(id)
    if entry and entry.state == STATE.ROLLING then
        entry.state, entry.roll = STATE.PENDING, nil
        if self.active == entry then self.active = nil end
        Addon:Fire("LOOT_LIST_CHANGED")
    end
    if self.remote and self.remote.id == id then
        self.remote = nil
        Addon:Fire("ROLL_ENDED", { id = id }, nil)
    end
end

-- /roll for me: main spec (1-100) or off spec (1-99).
function Loot:DoRoll(offSpec)
    RandomRoll(1, offSpec and Engine.OS_ROLL or 100)
end

-- Item info may arrive late; refresh decisions once it does.
Addon:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if #Loot.entries > 0 then
        if Loot.refreshPending then return end
        Loot.refreshPending = true
        C_Timer.After(0.5, function()
            Loot.refreshPending = false
            Loot:Refresh()
        end)
    end
end)

---------------------------------------------------------------------------
-- Surviving a /reload as loot master, and awards the raid leader missed
---------------------------------------------------------------------------
-- Keep the loot master's list across a reload (drops still to roll, items
-- still to hand out). A roll that was running is cancelled for everyone.
Addon:RegisterEvent("PLAYER_LOGOUT", function(self)
    if not (IsInRaid() and isMaster()) or #Loot.entries == 0 then
        self.db.lootState = nil
        return
    end
    local saved = {}
    for _, e in ipairs(Loot.entries) do
        saved[#saved + 1] = {
            id = e.id, itemID = e.itemID, link = e.link, quality = e.quality, source = e.source,
            state = e.state == STATE.ROLLING and STATE.PENDING or e.state,
            wasRolling = e.state == STATE.ROLLING or nil,
            winner = e.winner, special = e.special, traded = e.traded,
        }
    end
    self.db.lootState = { nextId = nextId, entries = saved }
end)

Addon:OnInit(function(self)
    local saved = self.db.lootState
    self.db.lootState = nil
    if type(saved) ~= "table" or type(saved.entries) ~= "table" then return end
    C_Timer.After(3, function()
        if not (IsInRaid() and isMaster()) or #Loot.entries > 0 then return end
        nextId = saved.nextId
        for _, e in ipairs(saved.entries) do
            if e.wasRolling then
                ns.Comm:SendCancel(e.id)
                e.wasRolling = nil
            end
            table.insert(Loot.entries, e)
        end
        Loot:Refresh()
    end)
end)

-- An assistant loot master repeats its awards whenever the raid leader sends
-- the rules again (the leader reloaded or reconnected and may have missed
-- some). The leader records each drop only once.
local lastReplay = -100
Addon:On("SETTINGS_CHANGED", function()
    if not (IsInRaid() and isMaster()) or Addon:IsLeader() then return end
    if GetTime() - lastReplay < 30 then return end
    lastReplay = GetTime()
    for _, e in ipairs(Loot.entries) do
        if e.state == STATE.DONE and e.winner then
            local a
            for _, rec in ipairs(Addon.session.awards) do
                if rec.dropId == e.id then a = rec break end
            end
            ns.Comm:SendAward(e.id, e.itemID, e.winner, e.special or (a and a.mode) or nil)
        end
    end
end)
