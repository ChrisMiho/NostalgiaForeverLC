-- IDontWannaLC - Roster tab (raid leader only, while in a raid group)
-- The leader's inventory of the raid: who has the addon, who has sent their
-- reserves, who is short - with a Whisper button per player to remind them.
-- Also the leader's live controls: approve / change the counts, lock and
-- unlock (both announced in raid chat), refresh, export. The leader cannot
-- change anyone's picks.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Reserves, RaidData, Roster = ns.Reserves, ns.RaidDataAPI, ns.Roster
local STATUS = Engine.STATUS

local ROW_H = 24
local GREEN, GREY, RED, ORANGE, YELLOW = "40ff40", "808080", "ff4040", "ff9933", "ffd100"

local STATUS_TEXT = {
    [STATUS.NOADDON] = UI.Color(RED, "No addon"),
    [STATUS.EMPTY] = UI.Color(ORANGE, "No picks"),
    [STATUS.PARTIAL] = UI.Color(YELLOW, "Incomplete"),
    [STATUS.READY] = UI.Color(GREEN, "Ready"),
}

StaticPopupDialogs["IDWLC_LOCK_ANYWAY"] = {
    text = "I Don't Wanna LC:\n%s.\n\nLock reserves anyway? Players who aren't ready keep what they have "
        .. "(a player with nothing sent can still send a first set).",
    button1 = "Lock",
    button2 = CANCEL or "Cancel",
    OnAccept = function() Reserves:LeaderSetLocked(true) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function classRGB(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.04)
    row.name = UI:Label(row, nil, "GameFontNormal")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetWidth(170)
    row.name:SetWordWrap(false)
    row.status = UI:Label(row, nil, "GameFontHighlight")
    row.status:SetPoint("LEFT", 184, 0)
    row.status:SetWidth(90)
    row.counts = UI:Label(row, nil, "GameFontHighlightSmall")
    row.counts:SetPoint("LEFT", 282, 0)
    row.counts:SetWidth(200)
    row.version = UI:Label(row, nil, "GameFontDisableSmall")
    row.version:SetPoint("LEFT", 490, 0)
    row.whisper = UI:Button(row, "Whisper", 90, 20, function()
        if row.data and Roster:Whisper(row.data) then
            Addon:Print("Reminder whispered to %s.", row.data.name)
            UI:RefreshShown()
        end
    end, function()
        local text = row.data and Roster:WhisperText(row.data)
        if not text then return "Nothing to remind this player about." end
        return "Sends this whisper:\n\n|cffffffff" .. text .. "|r"
    end)
    row.whisper:SetPoint("RIGHT", -6, 0)
    return row
end

local function updateRow(row, d, index)
    local set = Addon.session.settings
    local approved = Addon.session.approved
    row.bg:SetShown(index % 2 == 0)
    row.name:SetText(d.name .. (d.online and "" or " |cff808080(offline)|r"))
    row.name:SetTextColor(classRGB(d.class))
    -- A different addon version may not understand every message.
    local versionText = d.version and ("v" .. d.version) or ""
    if d.version and d.version ~= "?" and d.version ~= Addon.version then
        versionText = UI.Color(ORANGE, versionText .. " (differs from yours)")
    end
    row.version:SetText(versionText)

    local isMe = d.name == Addon:PlayerName()
    if not approved and d.status ~= STATUS.NOADDON then
        -- Nothing is being collected yet; all we know is that they have the addon.
        row.status:SetText(UI.Color(GREEN, "Has addon"))
        row.counts:SetText("")
        row.whisper:Hide()
        return
    end
    row.status:SetText(STATUS_TEXT[d.status])
    if d.status == STATUS.NOADDON then
        row.counts:SetText("")
    else
        row.counts:SetText(("HR %d/%d   SR %d/%d%s"):format(d.hard, set.hardReserves, d.soft, set.softReserves,
            d.imported and "  |cff808080(entered by you)|r" or ""))
    end
    local needs = d.status ~= STATUS.READY and not isMe
    row.whisper:SetShown(needs)
    if needs then
        local wait = Roster:WhisperCooldown(d)
        row.whisper:SetText(wait > 0 and "Sent" or "Whisper")
        row.whisper:SetEnabled(wait <= 0 and d.online)
    end
end

local function refresh(self)
    local s = Addon.session
    if s.approved then
        self.state:SetText(("%s   -   %d HR / %d SR per player   -   %s"):format(
            RaidData:GetName(s.raidKey), s.settings.hardReserves, s.settings.softReserves,
            s.locked and UI.Color(RED, "LOCKED") or UI.Color(GREEN, "Open")))
        self.approve:SetText("Change counts")
    else
        self.state:SetText(UI.Color(ORANGE, "Reserve counts not approved yet")
            .. " - approve them to start collecting everyone's picks.")
        self.approve:SetText("Approve counts")
    end
    self.approve:SetEnabled(not s.locked)
    self.lock:SetText(s.locked and "Unlock reserves" or "Lock reserves")
    self.lock:SetEnabled(s.approved and true or false)
    self.export:SetEnabled(s.approved and true or false)
    self.lootMaster:SetText("Loot master: " .. (Addon:GetLootMasterName() or "-"))
    self.lootMaster:SetEnabled(s.approved and true or false)
    self.import:SetEnabled(s.approved and true or false)
    local changes, late = #(s.log or {}), Reserves:LateChangeCount()
    self.changes:SetText(late > 0 and ("Changes (%d, |cffff4040%d late|r)"):format(changes, late)
        or ("Changes (%d)"):format(changes))
    self.changes:SetEnabled(changes > 0)

    local rows = Roster:GetRows()
    self.list:SetData(rows)
    local ready, pending = 0, 0
    for _, row in ipairs(rows) do
        if row.status == STATUS.READY then ready = ready + 1 end
        if row.online and row.name ~= Addon:PlayerName() and Roster:WhisperText(row)
            and Roster:WhisperCooldown(row) <= 0 then
            pending = pending + 1
        end
    end
    if s.approved then
        self.summary:SetText(("%s of %d ready"):format(UI.Color(ready == #rows and GREEN or YELLOW, ready), #rows))
    else
        self.summary:SetText(("%d in the raid"):format(#rows))
    end
    self.whisperAll:SetEnabled(pending > 0)
end

local function create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.Refresh = refresh
    UI.rosterPanel = f

    f.state = UI:Label(f, nil, "GameFontHighlight")
    f.state:SetPoint("TOPLEFT", 4, -4)
    f.state:SetPoint("TOPRIGHT", -4, -4)
    f.state:SetWordWrap(false)

    f.approve = UI:Button(f, "Approve counts", 120, 22, function()
        Reserves:RequestApproval()
    end, "Set how many hard and soft reserves each player gets for this raid. Announced in raid chat.")
    f.approve:SetPoint("TOPLEFT", 0, -28)
    f.chooseRaid = UI:Button(f, "Choose raid", 100, 22, function(btn)
        UI:ShowRaidMenu(btn, Addon.session.raidKey, function(key) Reserves:RequestApproval(key) end)
    end, "Start collecting reserves for a raid before you zone in.")
    f.chooseRaid:SetPoint("LEFT", f.approve, "RIGHT", 6, 0)
    f.lock = UI:Button(f, "Lock reserves", 120, 22, function()
        if Addon.session.locked then
            Reserves:LeaderSetLocked(false)
            return
        end
        -- Locking with people not ready is allowed, but never by accident.
        local n, text = Roster:NotReadySummary()
        if n > 0 then
            StaticPopup_Show("IDWLC_LOCK_ANYWAY", ("%d player(s) not ready: %s"):format(n, text))
        else
            Reserves:LeaderSetLocked(true)
        end
    end, "Lock before the first boss: nobody can change their lists while locked. "
        .. "Locking and unlocking are announced in raid chat.")
    f.lock:SetPoint("LEFT", f.chooseRaid, "RIGHT", 6, 0)
    f.whisperAll = UI:Button(f, "Whisper all", 100, 22, function()
        local n = Roster:WhisperAll()
        Addon:Print("Reminder whispered to %d player(s).", n)
        UI:RefreshShown()
    end, "Whisper every online player who isn't ready (no addon, no picks or incomplete).")
    f.whisperAll:SetPoint("LEFT", f.lock, "RIGHT", 6, 0)
    f.refreshBtn = UI:Button(f, "Refresh", 80, 22, function() Roster:Refresh() end,
        "Ask every client to report in again (silent).")
    f.refreshBtn:SetPoint("LEFT", f.whisperAll, "RIGHT", 6, 0)
    f.export = UI:Button(f, "Export", 80, 22, function()
        UI:ShowText("Reserves export", Reserves:Export())
    end, "Plain-text list of everyone's active reserves (copy into Discord etc.).")
    f.export:SetPoint("LEFT", f.refreshBtn, "RIGHT", 6, 0)
    f.summary = UI:Label(f, nil, "GameFontNormal")
    f.summary:SetPoint("TOPRIGHT", -4, -32)

    -- Second row: who runs loot, entering reserves for players without the
    -- addon, and the log of reserve changes.
    f.lootMaster = UI:Button(f, "Loot master", 200, 22, function(btn)
        local items = {}
        local current = Addon:GetLootMasterName()
        for _, row in ipairs(Roster:GetRows()) do
            if (row.rank or 0) >= 1 then
                local name = row.name
                items[#items + 1] = {
                    text = name .. (row.rank == 2 and " (raid leader)" or " (assistant)"),
                    checked = name == current,
                    func = function() Reserves:LeaderSetLootMaster(name) end,
                }
            end
        end
        UI:ShowMenu(btn, items, 220)
    end, "Who collects the drops, runs the rolls and awards: you, or a raid assistant. "
        .. "You stay in charge of the reserves. Announced in raid chat.")
    f.lootMaster:SetPoint("TOPLEFT", 0, -54)
    f.import = UI:Button(f, "Import reserves", 120, 22, function()
        UI:ShowInput("Enter reserves for players without the addon",
            "One reserve per line: Name, item ID or link, HR or SR - or paste a softres.it CSV export.\n"
            .. "Only players who don't have the addon are affected. Announced in raid chat.", "Import", function(text)
            local applied, skipped = Reserves:LeaderImport(text)
            if not applied then return end
            Addon:Print("Reserves entered for %d player(s).", #applied)
            for _, sk in ipairs(skipped) do Addon:Print("  skipped %s: %s", sk.name, sk.reason) end
        end)
    end, "Type or paste reserves for raid members who don't have the addon. "
        .. "Players with the addon always pick for themselves; this never changes their picks.")
    f.import:SetPoint("LEFT", f.lootMaster, "RIGHT", 6, 0)
    f.changes = UI:Button(f, "Changes", 150, 22, function()
        UI:ShowText("Reserve changes since approval", Reserves:GetChangeLog())
    end, "Every change to a player's active reserves since you approved the counts, "
        .. "with changes made after a boss died marked.")
    f.changes:SetPoint("LEFT", f.import, "RIGHT", 6, 0)

    local header = UI:Label(f, "Player", "GameFontDisableSmall")
    header:SetPoint("TOPLEFT", 10, -86)
    local h2 = UI:Label(f, "Status", "GameFontDisableSmall")
    h2:SetPoint("TOPLEFT", 188, -86)
    local h3 = UI:Label(f, "Active reserves", "GameFontDisableSmall")
    h3:SetPoint("TOPLEFT", 286, -86)
    local h4 = UI:Label(f, "Addon", "GameFontDisableSmall")
    h4:SetPoint("TOPLEFT", 494, -86)

    local inset = UI:Inset(f)
    inset:SetPoint("TOPLEFT", 0, -100)
    inset:SetPoint("BOTTOMRIGHT", 0, 22)
    f.list = UI:CreateScrollList(f, ROW_H, createRow, updateRow)
    f.list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)

    f.hint = UI:Label(f, "Only you can see this tab. You can lock and unlock reserves, but never change another player's picks.",
        "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 4, 4)
    return f
end

UI:RegisterPanel("roster", {
    title = "Roster",
    tooltip = "Raid leader: who has picked their reserves, reminders, lock.",
    visible = function() return IsInRaid() and Addon:IsLeader() end,
    create = create,
})
