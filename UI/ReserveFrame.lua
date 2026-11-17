-- IDontWannaLC - Reserve window (every raider)
-- Browse a raid's loot by boss, toggle hard / soft reserves, reserve any
-- item by shift-clicking its link (WoW Forever loot tables start empty) and
-- review / remove your own picks.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Reserves, RaidData = ns.Reserves, ns.RaidDataAPI
local HARD, SOFT = Engine.KIND.HARD, Engine.KIND.SOFT

local WIDTH, HEIGHT = 680, 560
local ITEM_ROW_H, BOSS_ROW_H = 38, 20
local CHIPS_PER_ROW, CHIP_ROWS, CHIP_W = 4, 2, 160
local EMPTY_TEXT = "No loot known for this raid yet - items are learned as they drop.\nShift-click an item link to reserve it."

local frame
local viewKey          -- raid being browsed; nil = follow the raid leader's pick
local followedKey      -- leader raid key at the time viewKey was chosen
local selectedBoss = 1
local linkItemID, linkItemLink

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------
local function currentKey()
    local leaderKey = Addon.session.raidKey
    -- If the leader switches raids, follow them again.
    if viewKey and leaderKey ~= followedKey then viewKey = nil end
    if viewKey then return viewKey end
    if leaderKey then return leaderKey end
    local first = RaidData:GetChoices()[1]
    return first and first.key
end

local function countOf(list, id)
    local n = 0
    for _, v in ipairs(list) do if v == id then n = n + 1 end end
    return n
end

-- Everything a row needs to know about one item from my point of view.
local function itemState(itemID)
    local s = Addon.session
    local me = Addon:PlayerName()
    local myHard, mySoft = Reserves:GetMine()
    local _, _, quality = UI.ItemInfo(itemID)
    local st = {
        restricted = s:IsRestricted(quality),
        myHR = countOf(myHard, itemID) > 0,
        mySR = countOf(mySoft, itemID),
        otherHard = {}, otherSoft = {},
    }
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
    st.hrBlocked = s.settings.exclusiveHardReserves and #st.otherHard > 0
    return st
end

local function reserversText(st)
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

-- Left click toggles; right click adds an extra SR when double SR is allowed.
local function softClick(itemID, button)
    if button == "RightButton" and Addon.session.settings.allowDoubleSoft then
        Reserves:Add(itemID, SOFT)
    else
        Reserves:Toggle(itemID, SOFT)
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
    local open = not Addon.session.locked
    UI.SetToggleState(hr, "HR", st.myHR, open and (st.myHR or not st.hrBlocked))
    UI.SetToggleState(sr, st.mySR > 1 and ("SRx" .. st.mySR) or "SR", st.mySR > 0, open)
end

local function addReserveButtons(parent, getItemID)
    local sr = UI:Button(parent, "SR", 44, 20, nil, function()
        local t = "Soft reserve: you roll against other soft reservers."
        if Addon.session.settings.allowDoubleSoft then t = t .. "\nRight-click to add another SR (extra entry)." end
        return t
    end)
    sr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sr:SetScript("OnClick", function(_, button)
        local id = getItemID()
        if id then softClick(id, button) end
    end)
    local hr = UI:Button(parent, "HR", 44, 20, function()
        local id = getItemID()
        if id then Reserves:Toggle(id, HARD) end
    end, function()
        return Addon.session.settings.exclusiveHardReserves
            and "Hard reserve: the item is yours (only one player may hard reserve it)."
            or "Hard reserve: hard reservers get the item (roll among them)."
    end)
    local status = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    return hr, sr, status
end

---------------------------------------------------------------------------
-- Rows
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
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.04)
    row.item = UI:CreateItemButton(row, 20)
    row.item:SetPoint("TOPLEFT", 4, -2)
    row.item:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.sub = UI:Label(row)
    row.sub:SetPoint("TOPLEFT", 28, -24)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.sub:SetWordWrap(false)
    row.hr, row.sr, row.status = addReserveButtons(row, function() return row.itemID end)
    row.sr:SetPoint("RIGHT", -4, 0)
    row.hr:SetPoint("RIGHT", row.sr, "LEFT", -4, 0)
    row.status:SetPoint("RIGHT", -10, 0)
    return row
end

local function updateItemRow(row, itemID, index)
    row.itemID = itemID
    row.bg:SetShown(index % 2 == 0)
    row.item:SetItem(itemID)
    local st = itemState(itemID)
    row.sub:SetText(reserversText(st))
    applyButtons(row.hr, row.sr, row.status, st)
end

---------------------------------------------------------------------------
-- "My reserves" chips
---------------------------------------------------------------------------
local function createChip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(CHIP_W - 6, 20)
    c.tag = UI:Label(c, nil, "GameFontNormalSmall")
    c.tag:SetPoint("LEFT", 0, 0)
    c.tag:SetWidth(22)
    c.remove = UI:Button(c, "x", 20, 18, function()
        Reserves:Remove(c.itemID, c.kind)
    end, "Remove this reserve")
    c.remove:SetPoint("RIGHT", 0, 0)
    c.item = UI:CreateItemButton(c, 16)
    c.item:SetPoint("LEFT", c.tag, "RIGHT", 0, 0)
    c.item:SetPoint("RIGHT", c.remove, "LEFT", -2, 0)
    c.item.text:SetFontObject(GameFontHighlightSmall)
    return c
end

local function updateChips()
    local myHard, mySoft = Reserves:GetMine()
    local list = {}
    for _, id in ipairs(myHard) do list[#list + 1] = { id = id, kind = HARD } end
    for _, id in ipairs(mySoft) do list[#list + 1] = { id = id, kind = SOFT } end
    local max = CHIPS_PER_ROW * CHIP_ROWS
    for i = 1, max do
        local c = frame.chips[i]
        local e = list[i]
        if e then
            c.itemID, c.kind = e.id, e.kind
            c.tag:SetText(e.kind == HARD and UI.Color(UI.HARD_COLOR, "HR") or UI.Color(UI.SOFT_COLOR, "SR"))
            c.item:SetItem(e.id)
            c.remove:SetEnabled(not Addon.session.locked)
            c:Show()
        else
            c:Hide()
        end
    end
    local label = "My reserves:"
    if #list == 0 then
        label = label .. UI.Color(UI.GREY, "  none yet")
    elseif #list > max then
        label = label .. UI.Color(UI.GREY, ("  (+%d more - see /idwlc status)"):format(#list - max))
    end
    frame.myLabel:SetText(label)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function refresh(self)
    local s = Addon.session
    local key = currentKey()

    -- Header: raid + lock + remaining.
    self.raidButton:SetText(RaidData:GetName(key))
    local note
    if s.raidKey and key ~= s.raidKey then
        note = "Browsing - the raid leader picked " .. RaidData:GetName(s.raidKey) .. "."
    elseif s.raidKey then
        note = "Raid leader's pick."
    else
        note = "No raid set by the raid leader yet."
    end
    if not IsInRaid() then
        note = note .. "  Not in a raid: your picks are kept and sent to the leader when you join."
    end
    self.raidNote:SetText(UI.Color(UI.GREY, note))
    local myHard, mySoft = Reserves:GetMine()
    local set = s.settings
    self.status:SetText(("%s    Hard: %d/%d   Soft: %d/%d left"):format(
        s.locked and UI.Color("ff4040", "LOCKED") or UI.Color("40ff40", "Open"),
        set.hardReserves - #myHard, set.hardReserves, set.softReserves - #mySoft, set.softReserves))

    -- Bosses + items.
    local bosses = key and RaidData:GetBosses(key) or {}
    if selectedBoss > #bosses then selectedBoss = 1 end
    self.bossList:SetData(bosses)
    local boss = bosses[selectedBoss]
    local items = boss and boss.items or {}
    self.itemList:SetData(items)
    self.empty:SetShown(#items == 0)

    -- Shift-click box.
    self.linkItem:SetItem(linkItemID, linkItemLink)
    if linkItemID then
        applyButtons(self.linkHR, self.linkSR, self.linkStatus, itemState(linkItemID))
    else
        self.linkHR:Hide()
        self.linkSR:Hide()
        self.linkStatus:Hide()
    end

    updateChips()
end

local function create()
    local f = UI:CreateWindow("Reserve", "I Don't Wanna LC - Reserves", WIDTH, HEIGHT)
    frame = f
    f.Refresh = refresh

    -- Header row: raid selector, status.
    local raidLabel = UI:Label(f, "Raid:", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 16, -38)
    f.raidButton = UI:Button(f, "", 200, 22)
    f.raidButton:SetPoint("LEFT", raidLabel, "RIGHT", 8, 0)
    f.raidButton:SetScript("OnClick", function(btn)
        UI:ShowRaidMenu(btn, currentKey(), function(key)
            viewKey = (key ~= Addon.session.raidKey) and key or nil
            followedKey = Addon.session.raidKey
            selectedBoss = 1
            f:Refresh()
        end)
    end)
    f.status = UI:Label(f, nil, "GameFontHighlight")
    f.status:SetPoint("TOPRIGHT", -16, -42)
    f.raidNote = UI:Label(f)
    f.raidNote:SetPoint("TOPLEFT", 16, -62)
    f.raidNote:SetPoint("RIGHT", -16, 0)
    f.raidNote:SetWordWrap(false)

    -- Boss list (left).
    local bossInset = UI:Inset(f)
    bossInset:SetPoint("TOPLEFT", 12, -78)
    bossInset:SetPoint("BOTTOMLEFT", 12, 120)
    bossInset:SetWidth(196)
    f.bossList = UI:CreateScrollList(f, BOSS_ROW_H, createBossRow, updateBossRow)
    f.bossList:SetPoint("TOPLEFT", bossInset, "TOPLEFT", 4, -4)
    f.bossList:SetPoint("BOTTOMRIGHT", bossInset, "BOTTOMRIGHT", -26, 4)

    -- Item list (right).
    local itemInset = UI:Inset(f)
    itemInset:SetPoint("TOPLEFT", bossInset, "TOPRIGHT", 6, 0)
    itemInset:SetPoint("BOTTOMRIGHT", -12, 120)
    f.itemList = UI:CreateScrollList(f, ITEM_ROW_H, createItemRow, updateItemRow)
    f.itemList:SetPoint("TOPLEFT", itemInset, "TOPLEFT", 4, -4)
    f.itemList:SetPoint("BOTTOMRIGHT", itemInset, "BOTTOMRIGHT", -26, 4)
    f.empty = UI:Label(f, EMPTY_TEXT, "GameFontDisable")
    f.empty:SetJustifyH("CENTER")
    f.empty:SetPoint("LEFT", itemInset, "LEFT", 16, 0)
    f.empty:SetPoint("RIGHT", itemInset, "RIGHT", -16, 0)

    -- Shift-click reserve box.
    local linkLabel = UI:Label(f, "Shift-click any item here to reserve:", "GameFontNormalSmall")
    linkLabel:SetPoint("BOTTOMLEFT", 16, 94)
    f.linkBox = UI:CreateLinkBox(f, 120, function(id, link)
        linkItemID, linkItemLink = id, link
        f.linkBox:SetText("")
        f:Refresh()
    end)
    f.linkBox:SetPoint("LEFT", linkLabel, "RIGHT", 10, 0)
    f.linkItem = UI:CreateItemButton(f, 18)
    f.linkItem:SetPoint("LEFT", f.linkBox, "RIGHT", 8, 0)
    f.linkItem:SetWidth(170)
    f.linkHR, f.linkSR, f.linkStatus = addReserveButtons(f, function() return linkItemID end)
    f.linkSR:SetPoint("BOTTOMRIGHT", -16, 92)
    f.linkHR:SetPoint("RIGHT", f.linkSR, "LEFT", -4, 0)
    f.linkStatus:SetPoint("RIGHT", f.linkSR, "RIGHT", 0, 0)

    -- My reserves strip.
    f.myLabel = UI:Label(f, "My reserves:", "GameFontNormal")
    f.myLabel:SetPoint("BOTTOMLEFT", 16, 62)
    f.chips = {}
    for i = 1, CHIPS_PER_ROW * CHIP_ROWS do
        local c = createChip(f)
        local col, row = (i - 1) % CHIPS_PER_ROW, math.floor((i - 1) / CHIPS_PER_ROW)
        c:SetPoint("BOTTOMLEFT", 16 + col * CHIP_W, 36 - row * 24)
        f.chips[i] = c
    end

    -- Last rejection from the raid leader (cleared after a while).
    f.reject = UI:Label(f)
    f.reject:SetPoint("BOTTOMRIGHT", -16, 64)
    return f
end

function UI:ToggleReserve()
    UI:ToggleWindow(frame or create())
end

function UI:ShowReserve()
    (frame or create()):Show()
end

Addon:On("RESERVE_REJECTED", function(itemID, kind, reason)
    if not frame then return end
    local what = (itemID and itemID > 0) and UI.ItemText(itemID) or ""
    frame.reject:SetText(UI.Color("ff5555", "Rejected ") .. what .. " " .. (kind or "") .. ": " .. (reason or ""))
    C_Timer.After(10, function() if frame then frame.reject:SetText("") end end)
end)
