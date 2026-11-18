-- NostalgiaForeverLC - Raid catalogue (Raids tab, after clicking a raid card)
-- Bosses on the left; click one to see its loot grouped by gear slot, with
-- everything that isn't gear under "Misc / Quest". Every item has HR / SR
-- buttons that put it on your hard or soft list for this raid. The lists
-- span the whole raid, hold up to 10 items each and are ranked: in the live
-- raid your top picks that fit the approved counts are sent automatically
-- and the rest wait on standby. Reorder / remove picks in the panel at the
-- bottom. Shift-click any item link into the link box to add an item the
-- catalogue doesn't know yet (new raids start with empty loot tables).

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Reserves, RaidData = ns.Reserves, ns.RaidDataAPI
local HARD, SOFT = Engine.KIND.HARD, Engine.KIND.SOFT

local ITEM_ROW_H, SLOT_ROW_H, BOSS_ROW_H, PICK_ROW_H = 38, 22, 20, 18
local PICK_ROWS_VISIBLE = 9
local PICK_BUTTON_W = 60
local BANNER_SECONDS = 15
local ACTIVE_COLOR, STANDBY_COLOR, LOCKED_COLOR = "40ff40", "a0a0a0", "ff4040"
local EMPTY_TEXT = "No loot known for this raid yet - items are learned as they drop.\nShift-click an item link to add it to your list."
local NOT_OUT_TEXT = "This raid's loot isn't out on this client yet. It appears here on its own once it is."

local frame
local shownKey         -- raid the boss selection belongs to
local selectedBoss = 1
local linkItemID, linkItemLink
local view             -- snapshot of the browsed raid's lists, rebuilt every refresh
local bannerTimer
local pendingClearKey  -- raid whose list the "Clear list" popup will clear
local pendingNotice    -- rules notice that arrived during a boss encounter

StaticPopupDialogs["NFLC_CLEAR_WISHLIST"] = {
    text = "Nostalgia Forever LC:\nClear both of your reserve lists (hard and soft) for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if pendingClearKey then Reserves:ClearWishlist(pendingClearKey) end
        pendingClearKey = nil
    end,
    OnCancel = function() pendingClearKey = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------
-- The raid being browsed (chosen on the raid cards).
local function currentKey()
    return UI.raidViewKey
end

local function plural(n, word)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

-- Per position of a tier: "active", "standby" or "skipped" (restricted or a
-- duplicate). selected / standby are in-order subsequences of the list.
local function tierStatus(list, selected, standby)
    local out, si, bi, lastActive = {}, 1, 1, 0
    for i, id in ipairs(list) do
        if selected[si] == id then
            out[i], si, lastActive = "active", si + 1, i
        elseif standby[bi] == id then
            out[i], bi = "standby", bi + 1
        else
            out[i] = "skipped"
        end
    end
    return out, lastActive
end

local function buildView(key)
    local wish = Reserves:GetWishlist(key)
    local settings = Reserves:SettingsFor(key)
    local selH, selS, sbH, sbS = Reserves:GetSelection(key)
    local live = key ~= nil and key == Addon.session.raidKey and Addon.session.approved
    local v = {
        key = key, settings = settings, live = live,
        nActive = #selH + #selS, nStandby = #sbH + #sbS,
        editable = not (live and Addon.session.locked and IsInRaid()),
        tiers = {},
    }
    local function tier(kind, list, sel, sb, slots)
        local status, lastActive = tierStatus(list, sel, sb)
        local first, count = {}, {}
        for i, id in ipairs(list) do
            if not first[id] then first[id] = i end
            count[id] = (count[id] or 0) + 1
        end
        v.tiers[kind] = {
            list = list, status = status, lastActive = lastActive, first = first, count = count,
            slots = slots or 0, nActive = #sel,
        }
    end
    tier(HARD, wish.hard, selH, sbH, settings.hardReserves)
    tier(SOFT, wish.soft, selS, sbS, settings.softReserves)
    return v
end

-- Everything an item row needs to know about one item from my point of view.
local function itemState(itemID)
    local s = Addon.session
    local me = Addon:PlayerName()
    local _, _, quality = UI.ItemInfo(itemID)
    local h, so = view.tiers[HARD], view.tiers[SOFT]
    local st = {
        restricted = s:IsRestricted(quality),
        hardRank = h.first[itemID],
        softRank = so.first[itemID],
        softCount = so.count[itemID] or 0,
        otherHard = {}, otherSoft = {},
    }
    st.hardActive = st.hardRank ~= nil and h.status[st.hardRank] == "active"
    st.softActive = st.softRank ~= nil and so.status[st.softRank] == "active"
    -- Other players' reserves only exist for the raid the leader is running.
    if view.live then
        local hard, soft = s:GetReservers(itemID)
        for _, n in ipairs(hard) do
            if n ~= me then st.otherHard[#st.otherHard + 1] = n end
        end
        local counts, order = {}, {}
        for _, n in ipairs(soft) do
            if n ~= me then
                if not counts[n] then order[#order + 1] = n end
                counts[n] = (counts[n] or 0) + 1
            end
        end
        for _, n in ipairs(order) do
            st.otherSoft[#st.otherSoft + 1] = counts[n] > 1 and (n .. " x" .. counts[n]) or n
        end
    end
    return st
end

local function subText(st)
    if view.live then
        local parts = {}
        if #st.otherHard > 0 then
            parts[#parts + 1] = UI.Color(UI.HARD_COLOR, "HR: " .. table.concat(st.otherHard, ", "))
        end
        if #st.otherSoft > 0 then
            parts[#parts + 1] = UI.Color(UI.SOFT_COLOR, "SR: " .. table.concat(st.otherSoft, ", "))
        end
        if #parts == 0 then return UI.Color(UI.GREY, "no other reserves") end
        return table.concat(parts, "   ")
    end
    if st.hardRank then
        return UI.Color(UI.GREY, ("In your hard tier (#%d)"):format(st.hardRank))
    elseif st.softRank then
        return UI.Color(UI.GREY, ("In your soft tier (#%d)"):format(st.softRank))
    end
    return ""
end

-- HR / SR button: "HR #2" green when the pick is active, grey on standby.
local function setPickButton(btn, label, rank, active, enabled)
    if rank then
        btn:SetText(UI.Color(active and ACTIVE_COLOR or STANDBY_COLOR, ("%s #%d"):format(label, rank)))
        btn:LockHighlight()
    else
        btn:SetText(label)
        btn:UnlockHighlight()
    end
    btn:SetEnabled(enabled and true or false)
end

-- Left click toggles; right click adds an extra SR when double SR is allowed.
local function softClick(itemID, button)
    local key = currentKey()
    if button == "RightButton" and Reserves:SettingsFor(key).allowDoubleSoft then
        Reserves:Add(itemID, SOFT, key)
    else
        Reserves:Toggle(itemID, SOFT, key)
    end
end

-- Configure an HR/SR button pair + status label for an item.
local function applyButtons(hr, sr, status, st)
    if st.restricted then
        hr:Hide()
        sr:Hide()
        status:SetText(UI.Color(UI.MODE_COLORS.RESTRICTED, "Restricted"))
        status:Show()
        return
    end
    status:Hide()
    hr:Show()
    sr:Show()
    setPickButton(hr, "HR", st.hardRank, st.hardActive, view.editable)
    setPickButton(sr, st.softCount > 1 and ("SRx" .. st.softCount) or "SR", st.softRank, st.softActive, view.editable)
end

local function rankTooltip(kind, getItemID)
    return function()
        local t = kind == HARD
            and "Hard tier: beats every soft reserve. If several players hard reserve an item, only they roll."
            or "Soft tier: you roll against other soft reservers."
        local id = getItemID()
        local tier = view and view.tiers[kind]
        local rank = id and tier and tier.first[id]
        if rank then
            local active = tier.status[rank] == "active"
            t = t .. ("\n\n#%d in your %s tier - %s.\nClick to remove it."):format(rank, kind,
                active and "|cff40ff40active (sent to the leader)|r" or "|cffa0a0a0standby (no free slot)|r")
        else
            t = t .. "\n\nClick to add it to the end of your " .. kind .. " tier for the raid you are browsing."
        end
        if kind == SOFT and view and view.settings.allowDoubleSoft then
            t = t .. "\nRight-click to add another SR (extra entry)."
        end
        return t
    end
end

local function addReserveButtons(parent, getItemID)
    local sr = UI:Button(parent, "SR", PICK_BUTTON_W, 20, nil, rankTooltip(SOFT, getItemID))
    sr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sr:SetScript("OnClick", function(_, button)
        local id = getItemID()
        if id then softClick(id, button) end
    end)
    local hr = UI:Button(parent, "HR", PICK_BUTTON_W, 20, function()
        local id = getItemID()
        if id then Reserves:Toggle(id, HARD, currentKey()) end
    end, rankTooltip(HARD, getItemID))
    local status = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    return hr, sr, status
end

-- Small arrow button using the stock scroll-bar arrow textures.
local function arrowButton(parent, dir, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. dir .. "Button-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture(base .. "Highlight", "ADD")
    b:SetScript("OnClick", onClick)
    if tooltip then UI.SetTooltip(b, tooltip) end
    return b
end

---------------------------------------------------------------------------
-- Catalogue rows
---------------------------------------------------------------------------
local function createBossRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(0.2, 0.5, 1, 0.3)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = UI:Label(b, nil, "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        selectedBoss = self.index
        frame:Refresh()
    end)
    return b
end

local function updateBossRow(row, boss, index)
    row.text:SetText(("%s |cff808080(%d)|r"):format(boss.name, #boss.items))
    row.sel:SetShown(index == selectedBoss)
end

local function createItemRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    local buttonsW = PICK_BUTTON_W * 2 + 16
    -- Slot header ("Head", "Misc / Quest"): used instead of the item widgets.
    row.header = UI:Label(row, nil, "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 4, 3)
    row.headerLine = row:CreateTexture(nil, "ARTWORK")
    row.headerLine:SetHeight(1)
    row.headerLine:SetPoint("BOTTOMLEFT", 2, 0)
    row.headerLine:SetPoint("BOTTOMRIGHT", -2, 0)
    row.headerLine:SetColorTexture(1, 0.82, 0, 0.35)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.04)
    row.item = UI:CreateItemButton(row, 20)
    row.item:SetPoint("TOPLEFT", 4, -2)
    row.item:SetPoint("TOPRIGHT", row, "TOPRIGHT", -buttonsW, -2)
    row.sub = UI:Label(row)
    row.sub:SetPoint("TOPLEFT", 28, -24)
    row.sub:SetPoint("TOPRIGHT", row, "TOPRIGHT", -buttonsW, -24)
    row.sub:SetWordWrap(false)
    row.hr, row.sr, row.status = addReserveButtons(row, function() return row.itemID end)
    row.sr:SetPoint("RIGHT", -4, 0)
    row.hr:SetPoint("RIGHT", row.sr, "LEFT", -4, 0)
    row.status:SetPoint("RIGHT", -10, 0)
    return row
end

local function updateItemRow(row, d, index)
    local isHeader = d.header ~= nil
    row.header:SetShown(isHeader)
    row.headerLine:SetShown(isHeader and not d.muted)
    row.item:SetShown(not isHeader)
    row.sub:SetShown(not isHeader)
    if isHeader then
        row.itemID = nil
        row.bg:Hide()
        row.hr:Hide()
        row.sr:Hide()
        row.status:Hide()
        if d.muted then -- a note, not a gear slot: grey like EMPTY_TEXT
            row.header:SetText(UI.Color(UI.GREY, ("%s (%d)"):format(d.header, d.count)))
        else
            row.header:SetText(("%s |cff808080(%d)|r"):format(d.header, d.count))
        end
        return
    end
    row.itemID = d.itemID
    row.bg:SetShown(index % 2 == 0)
    row.item:SetItem(d.itemID)
    local st = itemState(d.itemID)
    row.sub:SetText(subText(st))
    applyButtons(row.hr, row.sr, row.status, st)
end

local function itemRowHeight(d)
    return d.header and SLOT_ROW_H or ITEM_ROW_H
end

---------------------------------------------------------------------------
-- "My priority list" panel: one ordered column per tier
---------------------------------------------------------------------------
local function createPickRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.rank = UI:Label(row, nil, "GameFontNormalSmall")
    row.rank:SetPoint("LEFT", 0, 0)
    row.rank:SetWidth(20)
    row.rank:SetJustifyH("RIGHT")
    row.remove = UI:Button(row, "x", 20, 16, function()
        local d = row.data
        if d and d.id then Reserves:Remove(d.id, d.kind, currentKey()) end
    end, "Remove from this list")
    row.remove:SetPoint("RIGHT", -2, 0)
    row.down = arrowButton(row, "Down", function()
        local d = row.data
        if d and d.id then Reserves:Move(d.id, d.kind, 1, currentKey()) end
    end, "Move down (lower priority)")
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.up = arrowButton(row, "Up", function()
        local d = row.data
        if d and d.id then Reserves:Move(d.id, d.kind, -1, currentKey()) end
    end, "Move up (higher priority)")
    row.up:SetPoint("RIGHT", row.down, "LEFT", 0, 0)
    row.tag = UI:Label(row, nil, "GameFontNormalSmall")
    row.tag:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
    row.tag:SetWidth(58)
    row.tag:SetJustifyH("RIGHT")
    row.item = UI:CreateItemButton(row, 16)
    row.item:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
    row.item:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
    row.item.text:SetFontObject(GameFontHighlightSmall)

    -- Divider after the last active pick: "-- 2 slots --" between two lines.
    row.divider = UI:Label(row, nil, "GameFontNormalSmall")
    row.divider:SetPoint("CENTER")
    row.divider:SetJustifyH("CENTER")
    row.lineL = row:CreateTexture(nil, "ARTWORK")
    row.lineL:SetHeight(1)
    row.lineL:SetPoint("LEFT", 4, 0)
    row.lineL:SetPoint("RIGHT", row.divider, "LEFT", -6, 0)
    row.lineL:SetColorTexture(0.25, 1, 0.25, 0.5)
    row.lineR = row:CreateTexture(nil, "ARTWORK")
    row.lineR:SetHeight(1)
    row.lineR:SetPoint("LEFT", row.divider, "RIGHT", 6, 0)
    row.lineR:SetPoint("RIGHT", -4, 0)
    row.lineR:SetColorTexture(0.25, 1, 0.25, 0.5)
    return row
end

local function statusTag(d)
    if d.status == "active" then return UI.Color(ACTIVE_COLOR, "Active") end
    if d.status == "standby" then return UI.Color(STANDBY_COLOR, "Standby") end
    local q = Addon:GetItemQuality(d.id)
    local minQ = view.settings.restrictedMinQuality or Engine.DEFAULT_SETTINGS.restrictedMinQuality
    if q and q >= minQ then return UI.Color(UI.MODE_COLORS.RESTRICTED, "Restricted") end
    return UI.Color(UI.GREY, "Duplicate")
end

local function updatePickRow(row, d)
    local isDivider = d.divider and true or false
    row.divider:SetShown(isDivider)
    row.lineL:SetShown(isDivider)
    row.lineR:SetShown(isDivider)
    row.rank:SetShown(not isDivider)
    row.item:SetShown(not isDivider)
    row.tag:SetShown(not isDivider)
    row.up:SetShown(not isDivider)
    row.down:SetShown(not isDivider)
    row.remove:SetShown(not isDivider)
    if isDivider then
        row.divider:SetText(d.text)
        return
    end
    row.rank:SetText(d.pos .. ".")
    row.item:SetItem(d.id)
    row.tag:SetText(statusTag(d))
    -- Move / Remove act on an item's first entry, so arrows are only offered
    -- there (a second entry only exists with double soft reserve).
    local canEdit = view.editable
    row.up:SetEnabled(canEdit and d.first and d.pos > 1)
    row.down:SetEnabled(canEdit and d.first and not d.last)
    row.remove:SetEnabled(canEdit)
end

local function pickData(kind)
    local t = view.tiers[kind]
    local data = {}
    if #t.list == 0 then return data end
    local function divider()
        local free = t.slots - t.nActive
        local text = "-- " .. plural(t.slots, "slot")
        if free > 0 then text = text .. (", %d free"):format(free) end
        data[#data + 1] = { divider = true, text = UI.Color(ACTIVE_COLOR, text .. " --") }
    end
    if t.lastActive == 0 then divider() end
    for i, id in ipairs(t.list) do
        data[#data + 1] = {
            id = id, kind = kind, pos = i, status = t.status[i],
            first = t.first[id] == i, last = i == #t.list,
        }
        if i == t.lastActive then divider() end
    end
    return data
end

local function updatePanel(f)
    f.panelTitle:SetText("My reserve lists - " .. (view.key and RaidData:GetName(view.key) or "no raid"))
    for _, kind in ipairs({ HARD, SOFT }) do
        local col, t = f.columns[kind], view.tiers[kind]
        col.header:SetText(col.title .. "   " .. UI.Color(UI.GREY, ("%d / %d"):format(#t.list, Engine.MAX_WISHLIST)))
        col.info:SetText(("%s, %s active"):format(plural(t.slots, "slot"), UI.Color(ACTIVE_COLOR, t.nActive)))
        col.list:SetData(pickData(kind))
        col.empty:SetShown(#t.list == 0)
    end
    local total = #view.tiers[HARD].list + #view.tiers[SOFT].list
    f.clearBtn:SetEnabled(view.editable and view.key ~= nil and total > 0)
    f.exportBtn:SetEnabled(view.key ~= nil and total > 0)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function refresh(self)
    local s = Addon.session
    local key = currentKey()
    view = buildView(key)

    -- Header: browsed raid, live rules, my picks.
    if key ~= shownKey then
        shownKey, selectedBoss = key, 1
    end
    self.title:SetText(key and RaidData:GetName(key) or "")
    local status
    if view.live then
        status = ("%d HR / %d SR per player - %s"):format(
            s.settings.hardReserves, s.settings.softReserves,
            s.locked and UI.Color(LOCKED_COLOR, "LOCKED") or UI.Color(ACTIVE_COLOR, "Open"))
    else
        status = UI.Color(UI.GREY, "Not the live raid")
    end
    local picks = ("Your picks: %s, %s"):format(
        UI.Color(ACTIVE_COLOR, view.nActive .. " active"), UI.Color(STANDBY_COLOR, view.nStandby .. " standby"))
    -- Live raid with slots going unused: make it hard to miss.
    local mh, ms = 0, 0
    if view.live then
        mh, ms = Engine.Shortfall(view.tiers[HARD].nActive, view.tiers[SOFT].nActive, view.settings)
    end
    if mh + ms > 0 then
        local need = {}
        if mh > 0 then need[#need + 1] = mh .. " HR" end
        if ms > 0 then need[#need + 1] = ms .. " SR" end
        picks = UI.Color(LOCKED_COLOR, (view.editable and "Add %s more" or "%s unused"):format(table.concat(need, " + ")))
            .. "   " .. picks
    end
    self.status:SetText(status .. "     " .. picks)

    local note
    local set = view.settings
    if view.live then
        if not view.editable then
            note = UI.Color(LOCKED_COLOR, "Locked by the raid leader") .. " - this raid's lists can't be changed right now."
        else
            note = UI.Color(ACTIVE_COLOR, "Live raid:") .. (" your top %d hard / %d soft picks are sent to the raid leader; the rest wait on standby.")
                :format(set.hardReserves, set.softReserves)
        end
    else
        local source = "default counts"
        if Reserves:HasPreset(key) then
            source = "the counts you last approved"
        elseif key and Addon.charDB.lastSeenRules[key] then
            source = "the last rules seen"
        end
        note = UI.Color(UI.SOFT_COLOR, "Planning ahead") .. (" - used when a leader runs this raid. Preview with %s: %d HR / %d SR.")
            :format(source, set.hardReserves, set.softReserves)
    end
    self.raidNote:SetText(note)

    -- Bosses + items.
    local bosses = key and RaidData:GetBosses(key) or {}
    if selectedBoss > #bosses then selectedBoss = 1 end
    self.bossList:SetData(bosses)
    local boss = bosses[selectedBoss]
    local rows, hidden = RaidData:GetLootRows(boss)
    if hidden > 0 and #rows > 0 then
        rows[#rows + 1] = { header = "Not out yet on this client", count = hidden, muted = true }
    end
    self.itemList:SetData(rows)
    self.empty:SetText(#rows == 0 and hidden > 0 and NOT_OUT_TEXT or EMPTY_TEXT)
    self.empty:SetShown(#rows == 0)

    -- Shift-click box.
    self.linkItem:SetItem(linkItemID, linkItemLink)
    if linkItemID then
        applyButtons(self.linkHR, self.linkSR, self.linkStatus, itemState(linkItemID))
    else
        self.linkHR:Hide()
        self.linkSR:Hide()
        self.linkStatus:Hide()
    end

    updatePanel(self)
end

local function createColumn(f, kind)
    local col = {}
    col.title = kind == HARD and UI.Color(UI.HARD_COLOR, "Hard reserves (HR)") or UI.Color(UI.SOFT_COLOR, "Soft reserves (SR)")
    local inset = UI:Inset(f)
    inset:SetHeight(PICK_ROWS_VISIBLE * PICK_ROW_H + 8)
    if kind == HARD then
        inset:SetPoint("BOTTOMLEFT", 0, 0)
        inset:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 0)
    else
        inset:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 0)
        inset:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    col.header = UI:Label(f, nil, "GameFontNormal")
    col.header:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 4, 3)
    col.info = UI:Label(f)
    col.info:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -6, 4)
    col.list = UI:CreateScrollList(f, PICK_ROW_H, createPickRow, updatePickRow)
    col.list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    col.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
    col.empty = UI:Label(f, ("Empty - use the %s buttons above to add items."):format(kind == HARD and "HR" or "SR"),
        "GameFontDisableSmall")
    col.empty:SetPoint("CENTER", inset, "CENTER")
    return col
end

function UI:CreateRaidView(parent)
    local f = CreateFrame("Frame", nil, parent)
    frame = f
    f.Refresh = refresh

    -- Header row: back to the raid cards, raid name, status.
    f.back = UI:Button(f, "< Raids", 80, 22, function() UI:ShowRaidList() end, "Back to the list of raids.")
    f.back:SetPoint("TOPLEFT", 0, 0)
    f.title = UI:Label(f, nil, "GameFontNormalLarge")
    f.title:SetPoint("LEFT", f.back, "RIGHT", 12, 0)
    f.status = UI:Label(f, nil, "GameFontHighlight")
    f.status:SetPoint("TOPRIGHT", -4, -5)
    f.status:SetWidth(480)
    f.status:SetJustifyH("RIGHT")
    f.status:SetWordWrap(false)
    f.raidNote = UI:Label(f)
    f.raidNote:SetPoint("TOPLEFT", 4, -28)
    f.raidNote:SetPoint("TOPRIGHT", -4, -28)
    f.raidNote:SetWordWrap(false)
    f.raidNote:SetTextColor(0.7, 0.7, 0.7)

    -- Rules-change banner (covers the note line for a while after the leader
    -- changes the rules).
    f.banner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.banner:SetPoint("TOPLEFT", 0, -23)
    f.banner:SetPoint("TOPRIGHT", 0, -23)
    f.banner:SetHeight(22)
    f.banner:SetBackdrop(UI.BACKDROP)
    f.banner:SetBackdropColor(0.45, 0.3, 0, 1)
    f.banner:SetBackdropBorderColor(1, 0.82, 0, 1)
    f.banner:EnableMouse(true)
    f.banner:SetScript("OnMouseUp", function(self) self:Hide() end)
    f.banner.text = UI:Label(f.banner, nil, "GameFontHighlight")
    f.banner.text:SetPoint("LEFT", 8, 0)
    f.banner.text:SetPoint("RIGHT", -8, 0)
    f.banner.text:SetWordWrap(false)
    UI.SetTooltip(f.banner, function() return (f.banner.text:GetText() or "") .. "\n\nClick to dismiss." end)
    f.banner:Hide()

    -- Bottom panel geometry (bottom-up): tier columns, panel title, link row.
    local columnsTop = PICK_ROWS_VISIBLE * PICK_ROW_H + 8
    local titleY = columnsTop + 24
    local linkY = titleY + 32
    local listsBottom = linkY + 28

    -- Boss catalogue (left).
    local bossInset = UI:Inset(f)
    bossInset:SetPoint("TOPLEFT", 0, -48)
    bossInset:SetPoint("BOTTOMLEFT", 0, listsBottom)
    bossInset:SetWidth(200)
    f.bossList = UI:CreateScrollList(f, BOSS_ROW_H, createBossRow, updateBossRow)
    f.bossList:SetPoint("TOPLEFT", bossInset, "TOPLEFT", 4, -4)
    f.bossList:SetPoint("BOTTOMRIGHT", bossInset, "BOTTOMRIGHT", -26, 4)

    -- The selected boss's loot, grouped by gear slot (right).
    local itemInset = UI:Inset(f)
    itemInset:SetPoint("TOPLEFT", bossInset, "TOPRIGHT", 6, 0)
    itemInset:SetPoint("BOTTOMRIGHT", 0, listsBottom)
    f.itemList = UI:CreateScrollList(f, ITEM_ROW_H, createItemRow, updateItemRow, itemRowHeight)
    f.itemList:SetPoint("TOPLEFT", itemInset, "TOPLEFT", 4, -4)
    f.itemList:SetPoint("BOTTOMRIGHT", itemInset, "BOTTOMRIGHT", -26, 4)
    f.empty = UI:Label(f, EMPTY_TEXT, "GameFontDisable")
    f.empty:SetJustifyH("CENTER")
    f.empty:SetPoint("LEFT", itemInset, "LEFT", 16, 0)
    f.empty:SetPoint("RIGHT", itemInset, "RIGHT", -16, 0)

    -- Shift-click box.
    local linkLabel = UI:Label(f, "Shift-click any item here to add it:", "GameFontNormalSmall")
    linkLabel:SetPoint("BOTTOMLEFT", 4, linkY + 4)
    f.linkBox = UI:CreateLinkBox(f, 120, function(id, link)
        linkItemID, linkItemLink = id, link
        f.linkBox:SetText("")
        f:Refresh()
    end)
    f.linkBox:SetPoint("LEFT", linkLabel, "RIGHT", 10, 0)
    f.linkItem = UI:CreateItemButton(f, 18)
    f.linkItem:SetPoint("LEFT", f.linkBox, "RIGHT", 8, 0)
    f.linkItem:SetWidth(220)
    f.linkHR, f.linkSR, f.linkStatus = addReserveButtons(f, function() return linkItemID end)
    f.linkSR:SetPoint("BOTTOMRIGHT", -4, linkY)
    f.linkHR:SetPoint("RIGHT", f.linkSR, "LEFT", -4, 0)
    f.linkStatus:SetPoint("RIGHT", f.linkSR, "RIGHT", 0, 0)

    -- My lists.
    f.panelTitle = UI:Label(f, "My reserve lists", "GameFontNormal")
    f.panelTitle:SetPoint("BOTTOMLEFT", 4, titleY + 4)
    f.clearBtn = UI:Button(f, "Clear lists", 90, 22, function()
        local key = currentKey()
        if not key then return end
        pendingClearKey = key
        StaticPopup_Show("NFLC_CLEAR_WISHLIST", RaidData:GetName(key))
    end, "Remove every pick (both lists) for this raid.")
    f.clearBtn:SetPoint("BOTTOMRIGHT", 0, titleY)
    f.importBtn = UI:Button(f, "Import", 70, 22, function()
        UI:ShowInput("Import reserve lists", "Paste a list exported from this addon (it names its raid). "
            .. "It replaces your lists for that raid.", "Import", function(text)
            local key, nh, nsoft = Reserves:ImportWishlist(text)
            if not key then
                if nh ~= "locked" then Addon:Print("|cffff5555Import failed:|r %s", tostring(nh)) end
                return
            end
            Addon:Print("Imported %d hard and %d soft picks for %s.", nh, nsoft, RaidData:GetName(key))
            UI:OpenRaid(key)
        end)
    end, "Replace your lists for a raid with a list exported from this addon (another character, a friend).")
    f.importBtn:SetPoint("RIGHT", f.clearBtn, "LEFT", -4, 0)
    f.exportBtn = UI:Button(f, "Export", 70, 22, function()
        local key = currentKey()
        if key then UI:ShowText("Your lists - " .. RaidData:GetName(key), Reserves:ExportWishlist(key)) end
    end, "Your lists for this raid as one line of text, to copy to another character or share.")
    f.exportBtn:SetPoint("RIGHT", f.importBtn, "LEFT", -4, 0)
    f.columns = { [HARD] = createColumn(f, HARD), [SOFT] = createColumn(f, SOFT) }

    -- Last rejection from the raid leader (cleared after a while).
    f.reject = UI:Label(f)
    f.reject:SetPoint("RIGHT", f.exportBtn, "LEFT", -12, 0)
    return f
end

Addon:On("RESERVE_REJECTED", function(itemID, kind, reason)
    if not frame then return end
    local what = (itemID and itemID > 0) and UI.ItemText(itemID) or ""
    frame.reject:SetText(UI.Color("ff5555", "Rejected ") .. what .. " " .. (kind or "") .. ": " .. (reason or ""))
    C_Timer.After(10, function() if frame then frame.reject:SetText("") end end)
end)

---------------------------------------------------------------------------
-- Rules-change notice: banner + open the window so players notice.
---------------------------------------------------------------------------
local function showNotice(text)
    UI:OpenRaid(Addon.session.raidKey) -- creates the view if needed
    if not frame then return end
    frame.banner.text:SetText(text or "")
    frame.banner:Show()
    if bannerTimer then bannerTimer:Cancel() end
    bannerTimer = C_Timer.NewTimer(BANNER_SECONDS, function()
        bannerTimer = nil
        if frame then frame.banner:Hide() end
    end)
end

Addon:On("RULES_NOTICE", function(text)
    -- Don't pop a window up mid boss fight; show it once the encounter ends.
    if Addon.inEncounter then
        pendingNotice = text
        return
    end
    showNotice(text)
end)

Addon:On("ENCOUNTER_ENDED", function()
    if pendingNotice then
        local text = pendingNotice
        pendingNotice = nil
        showNotice(text)
    end
end)
