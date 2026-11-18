-- NostalgiaForeverLC - Ledger tab
-- The loot ledger: every raid run with the addon on the left (newest first),
-- and for the selected run what dropped on each boss and who the raid
-- leader gave it to. Read-only apart from deleting a whole run.
-- "Sync with guild" fetches the runs guild raid leaders have (manual poll);
-- "Backups" restores an earlier copy of the ledger.

local _, ns = ...
local Addon, UI = ns.Addon, ns.UI
local Ledger = ns.Ledger

local RUN_ROW_H, ITEM_ROW_H, BOSS_ROW_H = 36, 24, 22
local GREEN, GREY = "40ff40", "808080"

local selected        -- run shown on the right
local pendingDelete   -- run the delete popup will remove
local pendingRestore  -- backup the restore popup will put back
local syncNote        -- last message from pressing Sync (e.g. "not in a guild")

StaticPopupDialogs["NFLC_RESTORE_LEDGER"] = {
    text = "Nostalgia Forever LC:\nReplace the loot ledger with the backup from %s?\nThe ledger as it is now is backed up first.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingRestore and Ledger:Restore(pendingRestore) then
            selected = nil
            Addon:Print("Loot ledger restored.")
        end
        pendingRestore = nil
    end,
    OnCancel = function() pendingRestore = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function backupLabel(b)
    local runs = b.ledger and b.ledger.runs and #b.ledger.runs or 0
    return ("%s  -  %d runs  (%s)"):format(date("%Y-%m-%d %H:%M", b.time), runs, b.reason or "manual")
end

local function syncText()
    local st = Ledger:SyncStatus()
    if syncNote then return UI.Color("ff9933", syncNote) end
    if not st then return "" end
    local result
    if st.runs > 0 then
        result = UI.Color(GREEN, ("%d run(s) synced: %d new entries, %d completed"):format(st.runs, st.added, st.updated))
    elseif st.answers > 0 then
        result = "Nothing new - your ledger already has what guild leaders offered"
    else
        result = "No raid leader with runs for this guild has answered"
    end
    if st.waiting > 0 then
        result = ("Receiving %d run(s)..."):format(st.waiting)
    elseif st.active and st.answers == 0 then
        result = "Asked the guild - waiting for raid leaders who are online..."
    end
    if st.rejected > 0 then result = result .. UI.Color("ff9933", ("  (%d rejected)"):format(st.rejected)) end
    return result
end

StaticPopupDialogs["NFLC_DELETE_RUN"] = {
    text = "Nostalgia Forever LC:\nDelete the ledger of %s? This can't be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingDelete then
            Ledger:DeleteRun(pendingDelete)
            if selected == pendingDelete then selected = nil end
        end
        pendingDelete = nil
    end,
    OnCancel = function() pendingDelete = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function runTitle(run)
    return ("%s - %s"):format(run.raidName or run.raidKey or "?", date("%Y-%m-%d", run.started))
end

local function awardedCount(run)
    local n = 0
    for _, e in ipairs(run.entries) do
        if e.winner then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Runs (left)
---------------------------------------------------------------------------
local function createRunRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(0.2, 0.5, 1, 0.3)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.title = UI:Label(b, nil, "GameFontNormalSmall")
    b.title:SetPoint("TOPLEFT", 6, -4)
    b.title:SetPoint("TOPRIGHT", -4, -4)
    b.title:SetWordWrap(false)
    b.info = UI:Label(b, nil, "GameFontDisableSmall")
    b.info:SetPoint("TOPLEFT", 6, -19)
    b:SetScript("OnClick", function(self)
        selected = self.data
        UI:RefreshShown(0)
    end)
    return b
end

local function updateRunRow(row, run)
    row.title:SetText(runTitle(run))
    row.info:SetText(("%d drops, %d awarded%s"):format(#run.entries, awardedCount(run),
        run.syncedFrom and "  |  synced" or ""))
    row.sel:SetShown(run == selected)
end

---------------------------------------------------------------------------
-- Entries of the selected run (right), grouped by boss
---------------------------------------------------------------------------
local function buildEntryRows(run)
    local order, groups = {}, {}
    for _, e in ipairs(run and run.entries or {}) do
        local boss = e.boss or "?"
        if not groups[boss] then
            groups[boss] = {}
            order[#order + 1] = boss
        end
        table.insert(groups[boss], e)
    end
    local rows = {}
    for _, boss in ipairs(order) do
        rows[#rows + 1] = { header = boss, count = #groups[boss] }
        for _, e in ipairs(groups[boss]) do rows[#rows + 1] = e end
    end
    return rows
end

local function entryRowHeight(d)
    return d.header and BOSS_ROW_H or ITEM_ROW_H
end

local function createEntryRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.header = UI:Label(row, nil, "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 4, 3)
    row.winner = UI:Label(row, nil, "GameFontHighlight")
    row.winner:SetPoint("RIGHT", -6, 0)
    row.winner:SetWidth(200)
    row.winner:SetJustifyH("RIGHT")
    row.winner:SetWordWrap(false)
    row.item = UI:CreateItemButton(row, 18)
    row.item:SetPoint("LEFT", 6, 0)
    row.item:SetPoint("RIGHT", row.winner, "LEFT", -8, 0)
    -- Hovering the winner shows how it was decided and the rolls.
    row.hit = CreateFrame("Frame", nil, row)
    row.hit:SetAllPoints(row.winner)
    row.hit:EnableMouse(true)
    UI.SetTooltip(row.hit, function()
        local e = row.data
        if not e or e.header or not e.winner then return "Not awarded." end
        local lines = { ("%s - %s"):format(e.winner, e.mode or "awarded") }
        if e.awardedAt then lines[#lines + 1] = date("%Y-%m-%d %H:%M", e.awardedAt) end
        for i, r in ipairs(e.rolls or {}) do
            lines[#lines + 1] = ("%d. %s  %d"):format(i, r.name, r.value)
        end
        return table.concat(lines, "\n")
    end)
    return row
end

local MODE_LABEL = { HARD = "HR", SOFT = "SR", OPEN = "open roll", RESTRICTED = "leader's call",
    DISENCHANT = "disenchant", BANK = "bank", OS = "off spec" }

local function updateEntryRow(row, e, index)
    local isHeader = e.header ~= nil
    row.header:SetShown(isHeader)
    row.item:SetShown(not isHeader)
    row.winner:SetShown(not isHeader)
    row.hit:SetShown(not isHeader)
    if isHeader then
        row.header:SetText(("%s |cff808080(%d)|r"):format(e.header, e.count))
        row.bg:SetColorTexture(1, 0.82, 0, 0.08)
        return
    end
    row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
    row.item:SetItem(e.itemID, e.link)
    if e.winner then
        local how = MODE_LABEL[e.mode or ""]
        local special = e.mode == "DISENCHANT" or e.mode == "BANK"
        row.winner:SetText(UI.Color(special and "c0c0c0" or GREEN, e.winner) .. (how and UI.Color(GREY, "  " .. how) or ""))
    else
        row.winner:SetText(UI.Color(GREY, "not awarded"))
    end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function refresh(self)
    local runs = Ledger:GetRuns()
    local found = false
    for _, run in ipairs(runs) do
        if run == selected then found = true end
    end
    if not found then selected = runs[1] end

    self.runList:SetData(runs)
    self.noRuns:SetShown(#runs == 0)
    local rows = buildEntryRows(selected)
    self.entryList:SetData(rows)
    if selected then
        self.title:SetText(runTitle(selected))
        self.info:SetText(("Led by %s   |   %d drops, %d awarded%s"):format(selected.leader or "?",
            #selected.entries, awardedCount(selected),
            selected.syncedFrom and ("   |   synced from " .. selected.syncedFrom) or ""))
    else
        self.title:SetText("")
        self.info:SetText("")
    end
    self.noEntries:SetShown(selected ~= nil and #rows == 0)
    self.export:SetEnabled(selected ~= nil)
    self.delete:SetEnabled(selected ~= nil)
    self.syncStatus:SetText(syncText())
end

local function create(parent)
    local f = CreateFrame("Frame", nil, parent)
    UI.ledgerPanel = f
    f.Refresh = refresh

    -- Guild sync + backups.
    f.sync = UI:Button(f, "Sync with guild", 130, 22, function()
        local ok, err = Ledger:Sync()
        syncNote = not ok and err or nil
        f:Refresh()
        -- Answers trickle in; show the outcome when the window closes too.
        if ok then C_Timer.After(4, function() UI:RefreshShown() end) end
    end, "Ask guild mates who led raids for their record of those runs, to fill gaps in yours "
        .. "(raids you missed, drops you didn't see). Only a run's own raid leader is accepted as its source, "
        .. "and nothing you recorded yourself is overwritten. A backup is taken first.")
    f.sync:SetPoint("TOPLEFT", 0, 0)
    f.backups = UI:Button(f, "Backups", 90, 22, function(btn)
        local items = { { text = "Back up now", func = function()
            Ledger:Backup("manual")
            Addon:Print("Loot ledger backed up.")
        end } }
        for _, b in ipairs(Ledger:GetBackups()) do
            items[#items + 1] = { text = "Restore " .. backupLabel(b), func = function()
                pendingRestore = b
                StaticPopup_Show("NFLC_RESTORE_LEDGER", date("%Y-%m-%d %H:%M", b.time))
            end }
        end
        UI:ShowMenu(btn, items, 330)
    end, "Copies of the ledger, taken before every sync and on demand. Restore one if a sync went wrong "
        .. "or the data got damaged.")
    f.backups:SetPoint("LEFT", f.sync, "RIGHT", 6, 0)
    f.syncStatus = UI:Label(f, nil, "GameFontHighlightSmall")
    f.syncStatus:SetPoint("LEFT", f.backups, "RIGHT", 10, 0)
    f.syncStatus:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.syncStatus:SetWordWrap(false)

    local runInset = UI:Inset(f)
    runInset:SetPoint("TOPLEFT", 0, -28)
    runInset:SetPoint("BOTTOMLEFT", 0, 0)
    runInset:SetWidth(250)
    f.runList = UI:CreateScrollList(f, RUN_ROW_H, createRunRow, updateRunRow)
    f.runList:SetPoint("TOPLEFT", runInset, "TOPLEFT", 4, -4)
    f.runList:SetPoint("BOTTOMRIGHT", runInset, "BOTTOMRIGHT", -26, 4)
    f.noRuns = UI:Label(f, "No raids recorded yet.", "GameFontDisable")
    f.noRuns:SetPoint("CENTER", runInset, "CENTER")

    f.title = UI:Label(f, nil, "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", runInset, "TOPRIGHT", 10, 0)
    f.info = UI:Label(f, nil, "GameFontHighlightSmall")
    f.info:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.delete = UI:Button(f, "Delete", 70, 22, function()
        if not selected then return end
        pendingDelete = selected
        StaticPopup_Show("NFLC_DELETE_RUN", runTitle(selected))
    end, "Delete this run from your ledger.")
    f.delete:SetPoint("TOPRIGHT", 0, -28)
    f.export = UI:Button(f, "Export", 70, 22, function()
        if selected then UI:ShowText("Ledger - " .. runTitle(selected), Ledger:Export(selected)) end
    end, "Plain-text copy of this run (boss | item | winner | how).")
    f.export:SetPoint("RIGHT", f.delete, "LEFT", -6, 0)

    local entryInset = UI:Inset(f)
    entryInset:SetPoint("TOPLEFT", runInset, "TOPRIGHT", 6, -40)
    entryInset:SetPoint("BOTTOMRIGHT", 0, 0)
    f.entryList = UI:CreateScrollList(f, ITEM_ROW_H, createEntryRow, updateEntryRow, entryRowHeight)
    f.entryList:SetPoint("TOPLEFT", entryInset, "TOPLEFT", 4, -4)
    f.entryList:SetPoint("BOTTOMRIGHT", entryInset, "BOTTOMRIGHT", -26, 4)
    f.noEntries = UI:Label(f, "Nothing dropped in this run.", "GameFontDisable")
    f.noEntries:SetPoint("CENTER", entryInset, "CENTER")
    return f
end

UI:RegisterPanel("ledger", {
    title = "Ledger",
    tooltip = "Past raids: what dropped and who got what.",
    create = create,
})

Addon:On("LEDGER_CHANGED", function() UI:RefreshShown() end)
