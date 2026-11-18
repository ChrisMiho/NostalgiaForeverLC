-- IDontWannaLC - Reserves
--
-- Players: keep a tiered (ordered) wishlist of hard and soft picks for every
-- raid, built ahead of time from the raid catalogue. When they are in a raid,
-- the top entries that fit the leader's slot counts are sent as their
-- reserves automatically; everything else waits on standby. If the leader
-- changes the slot counts, selections are recomputed and re-sent.
--
-- Raid leader: the authority. Approves the hard / soft counts for the raid
-- (prompted on first entering it), validates every player's set, syncs the
-- full reserve list and locks / unlocks it. The leader never edits another
-- player's reserves.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine
local KIND = Engine.KIND

local Reserves = {}
ns.Reserves = Reserves
Addon.Reserves = Reserves

local pushTimer, syncTimer, announceTimer
local lastPushed -- "raidKey|encoded set" of the last set we sent
local promptedKey -- raid the leader was already asked to approve this session
-- [itemID] = { raidKey, kind, index } of items taken off my list by winning
-- them (saved, so an undo after a /reload still puts them back).
local function wonItems()
    Addon.charDB.lastWon = Addon.charDB.lastWon or {}
    return Addon.charDB.lastWon
end
local wasInRaid

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

-- Settings used to preview a raid's selection. For the live raid we use the
-- approved rules; for other raids, the counts I last approved for it as a
-- leader, else the last rules a leader used for it, else my defaults.
function Reserves:SettingsFor(raidKey)
    local s = Addon.session
    if raidKey ~= nil and raidKey == s.raidKey then return s.settings end
    local preset, saved = self:GetPreset(raidKey)
    if saved then return preset end
    return (raidKey and Addon.charDB.lastSeenRules[raidKey]) or preset
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
    -- Armor my class can never wear (a mage and plate) isn't a reserve.
    local classID, subclassID = Addon:GetItemClass(itemID)
    local _, myClass = UnitClass("player")
    if not Engine.CanClassWear(myClass, classID, subclassID) then
        Addon:Print("|cffff5555Can't reserve|r %s: your class can't wear it.", itemText(itemID))
        return false, "class"
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
    if i then
        table.remove(w.hard, i)
        wonItems()[itemID] = { raidKey = raidKey, kind = KIND.HARD, index = i }
    end
    i = indexOf(w.soft, itemID)
    if i then
        table.remove(w.soft, i)
        wonItems()[itemID] = wonItems()[itemID] or { raidKey = raidKey, kind = KIND.SOFT, index = i }
    end
    Addon:Fire("MY_RESERVES_CHANGED")
end

-- The award was undone: put the item back where it was on my list.
Addon:On("AWARD_UNDONE", function(itemID, winner)
    local won = wonItems()[itemID]
    if not won or not Addon:IsMe(winner) then return end
    wonItems()[itemID] = nil
    local w = Reserves:GetWishlist(won.raidKey, true)
    if indexOf(w.hard, itemID) or indexOf(w.soft, itemID) then return end
    local list = w[won.kind]
    table.insert(list, math.min(won.index, #list + 1), itemID)
    Addon:Print("The award of %s was undone - it is back on your list.", itemText(itemID))
    Reserves:Changed(won.raidKey)
end)

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
    -- Locked means no changes; a first set from someone the leader has
    -- nothing for yet (joined after the lock) is still accepted.
    if Addon.session.locked and Addon:MyKeyIn(Addon.session.reserves) then return end
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

-- Unused reserve slots in the live raid: missingHard, missingSoft.
function Reserves:GetShortfall()
    local s = Addon.session
    if not (s.approved and s.raidKey and IsInRaid()) then return 0, 0 end
    local hard, soft = self:GetMine()
    return Engine.Shortfall(#hard, #soft, s.settings)
end

-- What to tell the player about unused slots, or nil when their lists
-- cover everything the leader allows.
function Reserves:ShortfallText()
    local mh, ms = self:GetShortfall()
    if mh + ms == 0 then return nil end
    local parts = {}
    if mh > 0 then parts[#parts + 1] = mh .. " more hard" end
    if ms > 0 then parts[#parts + 1] = ms .. " more soft" end
    local what = table.concat(parts, " and ")
    if Addon.session.locked then
        return ("Reserves are locked - you could have used %s reserve(s)."):format(what)
    end
    return ("Your lists are short: you can still add %s reserve(s) - /idwlc."):format(what)
end

-- Tell the player (chat + on-screen notice) that slots are going unused.
function Reserves:WarnShortfall()
    local text = self:ShortfallText()
    if not text then return false end
    Addon:Print("|cffff9933%s|r", text)
    if not Addon.session.locked and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, "IDWLC: " .. text,
            ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
    end
    return true
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
        -- Not enough on my lists to use every slot? Say so, loudly.
        local short = Reserves:ShortfallText()
        if short then
            Addon:Print("|cffff9933%s|r", short)
            msg = short .. "   (" .. table.concat(lines, "; ") .. ")"
        end
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
    if not Addon:MyKeyIn(Addon.session.reserves) then
        local hard, soft = Reserves:GetMine()
        if #hard + #soft > 0 then Reserves:Push(true) end
    end
end)

function Reserves:OnRemoteReset()
    Addon.session.reserves = {}
    lastPushed = nil
    Addon:Fire("RESERVES_CHANGED")
    self:Changed()
end

-- Won an item: take it off my wishlist.
Addon:On("ROLL_ENDED", function(entry, winner)
    if winner and entry and entry.itemID and Addon:IsMe(winner) then
        Reserves:RemoveWon(entry.itemID, Addon.session.raidKey)
    end
end)

---------------------------------------------------------------------------
-- Leader rules: defaults live in the Master Loot settings (Addon.db.settings);
-- the counts last approved for each raid are remembered to pre-fill the
-- approval prompt next time.
---------------------------------------------------------------------------
local RULE_KEYS = { "hardReserves", "softReserves", "allowDoubleSoft", "consumeOnAward", "restrictedMinQuality",
    "msos", "plusOnes", "softBonus", "softBonusCap" }

-- Rules a raid would start with, and whether counts were approved for it before.
function Reserves:GetPreset(raidKey)
    local p = raidKey and Addon.db.raidPresets[raidKey]
    local d = Addon.db.settings
    local out = {}
    for _, k in ipairs(RULE_KEYS) do out[k] = d[k] end
    out.hardReserves = Engine.ClampCount(p and p.hardReserves or d.hardReserves, Engine.DEFAULT_SETTINGS.hardReserves)
    out.softReserves = Engine.ClampCount(p and p.softReserves or d.softReserves, Engine.DEFAULT_SETTINGS.softReserves)
    return out, p ~= nil
end

function Reserves:HasPreset(raidKey)
    return raidKey ~= nil and Addon.db.raidPresets[raidKey] ~= nil
end

-- Counts to offer in the approval prompt for a raid.
function Reserves:GetProposal(raidKey)
    local p = self:GetPreset(raidKey)
    return p.hardReserves, p.softReserves
end

local function announceNow(text)
    if IsInRaid() then Addon:SendChat("[IDWLC] " .. text, "RAID") end
end

-- Announce the rules in raid chat (debounced so repeated changes don't spam).
function Reserves:AnnounceRules()
    if not IsInRaid() or not Addon:IsLeader() then return end
    if announceTimer then announceTimer:Cancel() end
    announceTimer = C_Timer.NewTimer(3.0, function()
        announceTimer = nil
        local s = Addon.session
        if not s.approved then return end
        announceNow(("%s: %d hard / %d soft reserves per player%s. Reserves are %s - /idwlc to pick."):format(
            ns.RaidDataAPI:GetName(s.raidKey), s.settings.hardReserves, s.settings.softReserves,
            s.settings.allowDoubleSoft and ", double SR allowed" or "",
            s.locked and "LOCKED" or "open"))
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

-- imported = true when the leader typed these in for a player without the addon.
function Reserves:LeaderApply(player, hard, soft, imported)
    local s = Addon.session
    local before = s.reserves[player]
    -- While locked only a player's first set gets in (late joiner), or their
    -- own set replacing one the leader entered for them.
    local firstSet = before == nil or s.imported[player] == true or imported == true
    local ok, rejected = s:ReplacePlayer(player, hard, soft, qualityLookup, firstSet)
    if ok then
        s.imported[player] = imported and true or nil
        -- Change log: what moved, and whether a boss had already died.
        local now = s.reserves[player] or { hard = {}, soft = {} }
        local ha, hr = Engine.DiffSets(before and before.hard, now.hard)
        local sa, sr = Engine.DiffSets(before and before.soft, now.soft)
        if before and (#ha + #hr + #sa + #sr) > 0 then
            table.insert(s.log, {
                time = time(), player = player, hardAdded = ha, hardRemoved = hr, softAdded = sa, softRemoved = sr,
                kills = s.kills or 0, imported = imported and true or nil,
            })
            while #s.log > 300 do table.remove(s.log, 1) end
        end
    end
    local me = Addon:PlayerName()
    for _, rej in ipairs(rejected or {}) do
        if player == me or imported then
            -- Tell the leader, not a player who has no addon to read it.
            Addon:Print("|cffff5555Reserve rejected|r%s %s: %s", imported and (" for " .. player) or "",
                rej.itemID and itemText(rej.itemID) or "", rej.reason)
        else
            ns.Comm:SendReject(player, rej.itemID, rej.kind, rej.reason)
        end
    end
    Addon:Fire("RESERVES_CHANGED")
    Addon:Fire("ROSTER_CHANGED")
    if ok then self:ScheduleSync() end
end

-- Incoming SET from a raid member.
function Reserves:LeaderApplyPlayerSet(sender, raidKey, encoded)
    if sender == Addon:PlayerName() then return end -- own echo; applied locally
    local session = Addon.session
    if not session.approved then return end
    local hard, soft = Engine.DecodeReserveSet(encoded)
    if not hard then return end
    if session.raidKey and raidKey ~= "" and raidKey ~= session.raidKey then
        return -- stale set for a previous raid; they'll re-send after CFG
    end
    -- Freshly installed addon with empty lists: keep what the leader entered.
    if session.imported[sender] and #hard + #soft == 0 then return end
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

-- Is the local player the leader of a raid group (the only authority)?
function Reserves:IsRaidLeader()
    return IsInRaid() and Addon:IsLeader()
end

-- The leader approves the hard / soft counts for a raid. This starts (or
-- updates) the inventory: everyone's client gets the rules silently and
-- answers with its selection, and the rules are announced in raid chat.
function Reserves:LeaderApprove(raidKey, hard, soft)
    if not self:IsRaidLeader() then return false, "not raid leader" end
    local s = Addon.session
    raidKey = raidKey or s.raidKey
    if not raidKey then return false, "no raid" end
    if s.locked and raidKey == s.raidKey then
        Addon:Print("Unlock reserves before changing the counts.")
        return false, "locked"
    end
    local d = Addon.db.settings
    if raidKey ~= s.raidKey then
        -- A different raid: a fresh, unlocked reserve list.
        s.reserves, s.awards = {}, {}
        s.log, s.imported, s.kills = {}, {}, 0
        s:SetLocked(false)
    end
    s.raidKey = raidKey
    s:SetSettings({
        hardReserves = Engine.ClampCount(hard, Engine.ClampCount(d.hardReserves, Engine.DEFAULT_SETTINGS.hardReserves)),
        softReserves = Engine.ClampCount(soft, Engine.ClampCount(d.softReserves, Engine.DEFAULT_SETTINGS.softReserves)),
        allowDoubleSoft = d.allowDoubleSoft and true or false,
        consumeOnAward = d.consumeOnAward and true or false,
        restrictedMinQuality = d.restrictedMinQuality or Engine.DEFAULT_SETTINGS.restrictedMinQuality,
        msos = d.msos and true or false,
        plusOnes = d.plusOnes and true or false,
        softBonus = tonumber(d.softBonus) or 0,
        softBonusCap = tonumber(d.softBonusCap) or 0,
    })
    s.approved = true
    promptedKey = raidKey
    trimToLimits()
    Addon.db.raidPresets[raidKey] = {
        hardReserves = s.settings.hardReserves, softReserves = s.settings.softReserves,
    }
    lastPushed = nil
    self:LeaderBroadcast(true)
    self:Push() -- my own selection
    ns.Comm:SendPing(true) -- who has the addon?
    self:WarnShortfall() -- the leader is a raider too
    return true
end

-- Ask the leader to approve counts for a raid (opens the prompt).
function Reserves:RequestApproval(raidKey)
    if not self:IsRaidLeader() then
        Addon:Print("Only the raid leader of a raid group can do that.")
        return false
    end
    raidKey = raidKey or Addon.session.raidKey or (Addon:IsInRaidInstance() and ns.RaidDataAPI:Detect()) or nil
    if not raidKey then
        Addon:Print("Choose a raid first.")
        return false
    end
    promptedKey = raidKey
    Addon:Fire("APPROVAL_NEEDED", raidKey)
    return true
end

-- First time the leader is inside a raid instance with no approved rules for
-- it: prompt once (they can dismiss it and approve later from the Roster tab).
function Reserves:CheckApproval()
    if not self:IsRaidLeader() or not Addon:IsInRaidInstance() then return false end
    local s = Addon.session
    local key = ns.RaidDataAPI:Detect()
    if not key then return false end
    if s.approved and s.raidKey == key then return false end
    if promptedKey == key then return false end
    return self:RequestApproval(key)
end

-- Lock / unlock. Announced in raid chat straight away, every time.
function Reserves:LeaderSetLocked(locked)
    if not self:IsRaidLeader() then return false end
    local s = Addon.session
    if not s.approved then
        Addon:Print("Approve the reserve counts first.")
        return false
    end
    locked = locked and true or false
    if s.locked == locked then return false end
    s:SetLocked(locked)
    if locked then
        announceNow(("Reserves for %s are now LOCKED by the raid leader. Lists can no longer be changed."):format(
            ns.RaidDataAPI:GetName(s.raidKey)))
    else
        announceNow(("Reserves for %s were UNLOCKED by the raid leader. You can change your lists again (/idwlc)."):format(
            ns.RaidDataAPI:GetName(s.raidKey)))
        lastPushed = nil
        self:Push()
    end
    self:LeaderBroadcast(false)
    return true
end

-- Throw away the collected reserves and have every client send its
-- selection again. Nobody's lists are touched.
function Reserves:LeaderReset()
    if not self:IsRaidLeader() or not Addon.session.approved then return false end
    Addon.session.reserves = {}
    local wasLocked = Addon.session.locked
    Addon.session:SetLocked(false)
    lastPushed = nil
    Addon:Fire("RESERVES_CHANGED")
    announceNow("The raid leader reset the reserve list" .. (wasLocked and " and unlocked reserves" or "")
        .. ". Everyone's picks are being collected again.")
    ns.Comm:Raid("RESET")
    self:LeaderBroadcast(false)
    self:Push()
    return true
end

-- Send the rules (and the reserve list) to the raid; announce if asked.
function Reserves:LeaderBroadcast(announce)
    Addon:Fire("SESSION_CHANGED")
    Addon:Fire("MY_RESERVES_CHANGED")
    Addon:Fire("ROSTER_CHANGED")
    if IsInRaid() and Addon.session.approved then
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

---------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------
-- Leader: drop the reserves of players who are no longer in the raid, so an
-- item is never held for someone who left. (If they come back, their client
-- sends its selection again.)
function Reserves:PruneDeparted()
    local present = {}
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then present[Addon:NormalizeName(name)] = true end
    end
    if not next(present) then return end -- roster not loaded yet
    local changed = false
    for name in pairs(Addon.session.reserves) do
        if not present[name] then
            Addon.session.reserves[name] = nil
            changed = true
        end
    end
    if changed then
        Addon:Fire("RESERVES_CHANGED")
        Addon:Fire("ROSTER_CHANGED")
        self:ScheduleSync()
    end
end

-- Out of the raid group: nothing is live any more. My lists are untouched.
function Reserves:ResetSession()
    local s = Addon.session
    s.reserves, s.awards = {}, {}
    s.locked, s.raidKey, s.approved = false, nil, false
    s.lootMaster, s.log, s.imported, s.kills = nil, {}, {}, 0
    s:SetSettings((self:GetPreset(nil)))
    lastPushed, promptedKey = nil, nil
    Addon:Fire("SESSION_CHANGED")
    Addon:Fire("RESERVES_CHANGED")
    Addon:Fire("MY_RESERVES_CHANGED")
    Addon:Fire("ROSTER_CHANGED")
end

Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function(self)
    if not IsInRaid() then
        if wasInRaid then Reserves:ResetSession() end
        wasInRaid = false
        lastPushed = nil
        Reserves.wasLeader = false
        return
    end
    wasInRaid = true
    if self:IsLeader() and self.session.approved then Reserves:PruneDeparted() end
    if self:IsLeader() and not Reserves.wasLeader then
        -- Became leader (or logged in as one): carry on with the approved
        -- rules, or ask for approval if we're already inside the raid.
        Reserves.wasLeader = true
        if self.session.approved then
            lastPushed = nil
            Reserves:LeaderBroadcast(false)
            Reserves:Push()
        else
            Reserves:CheckApproval()
        end
    elseif not self:IsLeader() then
        Reserves.wasLeader = false
    end
end)

-- Zoning: prompt the leader on entering a raid; drop a stale session when we
-- log in outside a raid group. Delayed so group info has settled.
Addon:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
    C_Timer.After(2, function()
        if not IsInRaid() then
            if self.session.raidKey or self.session.approved then Reserves:ResetSession() end
            wasInRaid = false
            return
        end
        wasInRaid = true
        if self:IsLeader() then ns.Comm:SendPing(true) end -- versions aren't saved across /reload
        Reserves:CheckApproval()
        -- Zoning in with unused slots and reserves still open: last call.
        if self:IsInRaidInstance() and not self.session.locked then Reserves:WarnShortfall() end
    end)
end)

-- First pull with reserves still open: nudge the leader (nothing is forced).
Addon:RegisterEvent("ENCOUNTER_START", function(self)
    if Reserves:IsRaidLeader() and self.session.approved and not self.session.locked then
        self:Print("Reserves are still |cff55ff55open|r - lock them from the Roster tab (/idwlc roster) if picks should be final.")
    end
end)

---------------------------------------------------------------------------
-- Loot master, change log, imports, lists as text
---------------------------------------------------------------------------
-- Bosses killed since approval (the change log marks changes made after one).
Addon:On("ENCOUNTER_ENDED", function(_, _, success)
    if success and Addon.session.approved then Addon.session.kills = (Addon.session.kills or 0) + 1 end
end)

-- Raid leader: put an assistant (or yourself again) in charge of loot. The
-- leader stays the authority for reserves; the loot master collects drops,
-- runs rolls and awards. Announced in raid chat.
function Reserves:LeaderSetLootMaster(name)
    if not self:IsRaidLeader() then return false end
    local s = Addon.session
    if not s.approved then
        Addon:Print("Approve the reserve counts first.")
        return false
    end
    local member = name and Addon:FindRaidMember(name)
    if not member then return false end
    if member == Addon:PlayerName() then member = nil end -- back to the leader
    if member then
        local isAssist = false
        for i = 1, GetNumGroupMembers() do
            local full, rank = GetRaidRosterInfo(i)
            if full and Addon:NormalizeName(full) == member and (rank or 0) >= 1 then isAssist = true end
        end
        if not isAssist then
            Addon:Print("%s needs raid assist to run loot.", member)
            return false
        end
    end
    if s.lootMaster == member then return false end
    s.lootMaster = member
    Addon:SendChat(("[IDWLC] Loot is now run by %s."):format(member or (Addon:PlayerName() .. " (raid leader)")), "RAID")
    self:LeaderBroadcast(false)
    return true
end

-- The leader's log of reserve changes after approval, newest first, as text.
function Reserves:GetChangeLog()
    local lines = {}
    local function names(list)
        local out = {}
        for _, id in ipairs(list or {}) do out[#out + 1] = (Addon:GetItemInfo(id)) or ("item:" .. id) end
        return table.concat(out, ", ")
    end
    local log = Addon.session.log or {}
    for i = #log, 1, -1 do
        local c = log[i]
        local parts = {}
        if #(c.hardAdded or {}) > 0 then parts[#parts + 1] = "HR + " .. names(c.hardAdded) end
        if #(c.hardRemoved or {}) > 0 then parts[#parts + 1] = "HR - " .. names(c.hardRemoved) end
        if #(c.softAdded or {}) > 0 then parts[#parts + 1] = "SR + " .. names(c.softAdded) end
        if #(c.softRemoved or {}) > 0 then parts[#parts + 1] = "SR - " .. names(c.softRemoved) end
        lines[#lines + 1] = ("%s  %s%s%s: %s"):format(date("%H:%M", c.time), c.player,
            c.imported and " (entered by leader)" or "",
            (c.kills or 0) > 0 and (" [after %d boss kill(s)]"):format(c.kills) or "",
            table.concat(parts, "; "))
    end
    return table.concat(lines, "\n")
end

-- How many logged changes were made after a boss had died.
function Reserves:LateChangeCount()
    local n = 0
    for _, c in ipairs(Addon.session.log or {}) do
        if (c.kills or 0) > 0 then n = n + 1 end
    end
    return n
end

-- Raid leader: enter reserves for players who don't have the addon, from
-- pasted text ("Name, item, HR|SR" lines or a softres.it CSV). Never touches
-- a player whose own client has reported in or sent reserves. Announced.
-- Returns namesApplied, skipped = { {name=, reason=} ... }.
function Reserves:LeaderImport(text)
    if not self:IsRaidLeader() then return nil end
    local s = Addon.session
    if not s.approved then
        Addon:Print("Approve the reserve counts first.")
        return nil
    end
    local players = Engine.ParseReserveImport(text)
    local applied, skipped = {}, {}
    local names = {}
    for name in pairs(players) do names[#names + 1] = name end
    table.sort(names)
    for _, typed in ipairs(names) do
        local member = Addon:FindRaidMember(typed)
        if not member then
            skipped[#skipped + 1] = { name = typed, reason = "not in the raid" }
        elseif ns.Comm.versions[member] or member == Addon:PlayerName() then
            skipped[#skipped + 1] = { name = member, reason = "has the addon - they pick themselves" }
        elseif s.reserves[member] and not s.imported[member] then
            skipped[#skipped + 1] = { name = member, reason = "already sent their own reserves" }
        else
            local set = players[typed]
            -- Trim to the approved counts (first entries win).
            local hard, soft = {}, {}
            for i = 1, math.min(#set.hard, s.settings.hardReserves) do hard[i] = set.hard[i] end
            for i = 1, math.min(#set.soft, s.settings.softReserves) do soft[i] = set.soft[i] end
            self:LeaderApply(member, hard, soft, true)
            applied[#applied + 1] = member
        end
    end
    if #applied > 0 then
        Addon:SendChat(("[IDWLC] The raid leader entered reserves for players without the addon: %s."):format(
            table.concat(applied, ", ")), "RAID")
    end
    return applied, skipped
end

-- My lists for a raid as one line of text.
function Reserves:ExportWishlist(raidKey)
    return Engine.EncodeWishlist(raidKey, self:GetWishlist(raidKey))
end

-- Replace my lists for the raid named in the text. Restricted items, armor
-- my class can't wear and anything beyond 10 per list are left out.
-- Returns raidKey, hardCount, softCount - or nil, reason.
function Reserves:ImportWishlist(text)
    local raidKey, hard, soft = Engine.DecodeWishlist(text)
    if not raidKey then return nil, "That isn't a list exported from this addon." end
    if not editable(raidKey) then return nil, "locked" end
    local rules = self:SettingsFor(raidKey)
    local minQ = rules.restrictedMinQuality or Engine.DEFAULT_SETTINGS.restrictedMinQuality
    local _, myClass = UnitClass("player")
    local seen = {}
    local function clean(list)
        local out = {}
        for _, id in ipairs(list) do
            local q = qualityLookup(id)
            local classID, subclassID = Addon:GetItemClass(id)
            if not seen[id] and #out < Engine.MAX_WISHLIST and not (q and q >= minQ)
                and Engine.CanClassWear(myClass, classID, subclassID) then
                seen[id] = true
                out[#out + 1] = id
            end
        end
        return out
    end
    local w = { hard = clean(hard) }
    w.soft = clean(soft) -- an item on the hard list is not repeated on the soft list
    Addon.charDB.wishlists[raidKey] = w
    self:Changed(raidKey)
    return raidKey, #w.hard, #w.soft
end
