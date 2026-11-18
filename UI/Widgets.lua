-- IDontWannaLC - UI widgets
-- Shared helpers for every window: movable titled windows, buttons, item
-- rows with tooltips / shift-click linking, pooled scroll lists, a small
-- custom popup menu (instead of UIDropDownMenu), shift-click link boxes and a
-- copyable text dialog. Only uses API present on both the modern client
-- (WoW Forever) and Classic Era.

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine

local UI = ns.UI or {}
ns.UI = UI

UI.windows = {} -- every window created via CreateWindow (refreshed while shown)

UI.HARD_COLOR = "ff9933"
UI.SOFT_COLOR = "66b3ff"
UI.GREY = "808080"
UI.MODE_COLORS = {
    RESTRICTED = "ff4040",
    HARD = "ff9933",
    SOFT = "66b3ff",
    OPEN = "40ff40",
}

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
UI.BACKDROP = BACKDROP

function UI.Color(hex, text)
    return "|cff" .. hex .. tostring(text) .. "|r"
end

---------------------------------------------------------------------------
-- Item info
---------------------------------------------------------------------------
local GetIconByID = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- name, link, quality, icon. name/link/quality are nil until the item is
-- cached; GET_ITEM_INFO_RECEIVED then triggers a refresh of shown windows.
function UI.ItemInfo(itemID)
    local name, link, quality, _, _, _, _, _, _, icon = Addon:GetItemInfo(itemID)
    if not icon and GetIconByID then icon = GetIconByID(itemID) end
    return name, link, quality, icon or QUESTION_MARK
end

function UI.QualityRGB(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

-- Quality-coloured item name for use inside longer strings.
function UI.ItemText(itemID)
    local name, _, quality = UI.ItemInfo(itemID)
    local r, g, b = UI.QualityRGB(quality)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255),
        math.floor(b * 255), name or ("item:" .. tostring(itemID)))
end

-- Put a link into the active chat edit box (or one of our link boxes).
function UI.InsertLink(link)
    if not link then return end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
end

function UI.SetTooltip(widget, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(text) == "function" and text(self) or text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
local function savePosition(f)
    local db = Addon.charDB
    if not db then return end
    db.framePositions = db.framePositions or {}
    local point, _, relPoint, x, y = f:GetPoint(1)
    db.framePositions[f.idwlcName] = { point, relPoint, x, y }
end

-- Movable, ESC-closable window with a title and a close button. Created
-- hidden; OnShow calls f:Refresh() when defined. defaultPoint = {point, x, y}.
function UI:CreateWindow(name, title, width, height, defaultPoint)
    local globalName = "IDWLC_" .. name
    local f = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    f.idwlcName = name
    f:SetSize(width, height)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local pos = Addon.charDB and Addon.charDB.framePositions and Addon.charDB.framePositions[name]
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif defaultPoint then
        f:SetPoint(defaultPoint[1], UIParent, defaultPoint[1], defaultPoint[2], defaultPoint[3])
    else
        f:SetPoint("CENTER")
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -10)
    f.title:SetText(title)

    f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeButton:SetPoint("TOPRIGHT", -2, -2)

    tinsert(UISpecialFrames, globalName)
    f:Hide()
    f:SetScript("OnShow", function(self) if self.Refresh then self:Refresh() end end)
    table.insert(self.windows, f)
    return f
end

function UI:ToggleWindow(f)
    if f:IsShown() then f:Hide() else f:Show() end
end

---------------------------------------------------------------------------
-- Basic widgets
---------------------------------------------------------------------------
function UI:Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

function UI:Button(parent, text, width, height, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 80, height or 22)
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", onClick) end
    if tooltip then UI.SetTooltip(b, tooltip) end
    return b
end

-- HR / SR style toggle: green text + locked highlight while active.
function UI.SetToggleState(btn, label, active, enabled)
    btn:SetText(active and ("|cff33ff33" .. label .. "|r") or label)
    if active then btn:LockHighlight() else btn:UnlockHighlight() end
    btn:SetEnabled(enabled and true or false)
end

function UI:CheckButton(parent, label, onClick, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    -- Template label is .Text on modern clients, .text on some older ones.
    local fs = cb.Text or cb.text
    if type(fs) ~= "table" or not fs.SetText then
        fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    end
    fs:SetText(label)
    cb.label = fs
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    if tooltip then UI.SetTooltip(cb, tooltip) end
    return cb
end

---------------------------------------------------------------------------
-- Item button: icon + quality-coloured name, tooltip, shift-click to link
---------------------------------------------------------------------------
local function itemLinkString(self)
    if self.link then
        return self.link:match("|H(item:[^|]+)|h") or ("item:" .. self.itemID)
    end
    return "item:" .. self.itemID
end

local function itemOnEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(itemLinkString(self))
    GameTooltip:Show()
end

local function itemOnClick(self, button)
    if not self.itemID then return end
    if IsModifiedClick("CHATLINK") or IsShiftKeyDown() then
        local link = self.link or select(2, UI.ItemInfo(self.itemID))
        UI.InsertLink(link)
    elseif self.onClick then
        self:onClick(button)
    end
end

local function itemSetItem(self, itemID, link)
    self.itemID, self.link = itemID, nil
    if not itemID then
        self.icon:SetTexture(nil)
        self.text:SetText("")
        return
    end
    local name, ilink, quality, icon = UI.ItemInfo(itemID)
    self.link = link or ilink
    self.icon:SetTexture(icon)
    self.text:SetText(name or ("item:" .. itemID))
    self.text:SetTextColor(UI.QualityRGB(quality))
end

function UI:CreateItemButton(parent, iconSize)
    iconSize = iconSize or 18
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(iconSize)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(iconSize, iconSize)
    b.icon:SetPoint("LEFT")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    b.text:SetPoint("RIGHT")
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", itemOnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", itemOnClick)
    b.SetItem = itemSetItem
    return b
end

---------------------------------------------------------------------------
-- Scroll list with row pooling (fixed row height; all rows laid out)
---------------------------------------------------------------------------
local scrollCount = 0

local function scrollSetData(sf, data)
    for i, item in ipairs(data) do
        local row = sf.rows[i]
        if not row then
            row = sf.createRow(sf.content)
            row:SetHeight(sf.rowHeight)
            row:SetPoint("TOPLEFT", sf.content, "TOPLEFT", 0, -(i - 1) * sf.rowHeight)
            row:SetPoint("RIGHT", sf.content, "RIGHT")
            sf.rows[i] = row
        end
        row.index, row.data = i, item
        sf.updateRow(row, item, i)
        row:Show()
    end
    for i = #data + 1, #sf.rows do
        sf.rows[i]:Hide()
        sf.rows[i].data = nil
    end
    sf.content:SetHeight(math.max(1, #data * sf.rowHeight))
    sf:UpdateScrollChildRect()
    local range = sf:GetVerticalScrollRange()
    if sf:GetVerticalScroll() > range then sf:SetVerticalScroll(range) end
end

-- createRow(content) -> frame; updateRow(row, data, index).
-- The template's scroll bar sits ~24px to the right of the frame.
function UI:CreateScrollList(parent, rowHeight, createRow, updateRow)
    scrollCount = scrollCount + 1
    -- Named: older UIPanelScrollFrameTemplate code looks up $parentScrollBar.
    local sf = CreateFrame("ScrollFrame", "IDWLC_Scroll" .. scrollCount, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf:HookScript("OnSizeChanged", function(_, w) content:SetWidth(math.max(1, w or 1)) end)
    sf.content, sf.rows, sf.rowHeight = content, {}, rowHeight
    sf.createRow, sf.updateRow = createRow, updateRow
    sf.SetData = scrollSetData
    return sf
end

-- Thin dark background behind a list area.
function UI:Inset(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0.5)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    return f
end

---------------------------------------------------------------------------
-- Popup menu (replacement for UIDropDownMenu)
-- items = { {text=, func=, checked=, disabled=}, ... }; wraps into columns.
---------------------------------------------------------------------------
local MENU_ROW, MENU_COL_W, MENU_MAX_ROWS = 16, 170, 20

local function createMenu()
    local m = CreateFrame("Frame", "IDWLC_Menu", UIParent, "BackdropTemplate")
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:SetBackdrop(BACKDROP)
    m:SetBackdropColor(0, 0, 0, 0.95)
    m.buttons = {}
    -- Close when clicking anywhere else or when the anchor disappears.
    m:SetScript("OnUpdate", function(self)
        if self.anchor and not self.anchor:IsVisible() then self:Hide() return end
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
            self:Hide()
        end
    end)
    tinsert(UISpecialFrames, "IDWLC_Menu")
    m:Hide()
    return m
end

function UI:ShowMenu(anchor, items)
    local m = self.menu or createMenu()
    self.menu = m
    if m:IsShown() and m.anchor == anchor then m:Hide() return end
    m.anchor = anchor
    if #items == 0 then items = { { text = "(none)", disabled = true } } end

    for i, it in ipairs(items) do
        local b = m.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetSize(MENU_COL_W - 8, MENU_ROW)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:SetScript("OnClick", function(self)
                m:Hide()
                if self.func then self.func() end
            end)
            m.buttons[i] = b
        end
        local col, row = math.floor((i - 1) / MENU_MAX_ROWS), (i - 1) % MENU_MAX_ROWS
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6 + col * MENU_COL_W, -6 - row * MENU_ROW)
        b.text:SetText((it.checked and "|cff40ff40>|r " or "  ") .. it.text)
        if it.disabled then b.text:SetTextColor(0.5, 0.5, 0.5) else b.text:SetTextColor(1, 1, 1) end
        b.func = it.func
        b:SetEnabled(not it.disabled)
        b:Show()
    end
    for i = #items + 1, #m.buttons do m.buttons[i]:Hide() end

    local cols = math.ceil(#items / MENU_MAX_ROWS)
    m:SetSize(cols * MENU_COL_W + 4, math.min(#items, MENU_MAX_ROWS) * MENU_ROW + 12)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    m:Show()
end

-- Raid picker menu shared by the reserve and leader windows.
function UI:ShowRaidMenu(anchor, currentKey, onPick)
    local leaderKey = Addon.session.raidKey
    local tagClassic = ns.RaidDataAPI:IsForeverClient()
    local items = {}
    for _, c in ipairs(ns.RaidDataAPI:GetChoices()) do
        local key = c.key
        local text = c.name
        if tagClassic and c.expansion == "classic" then text = text .. " |cff9d9d9d(Classic)|r" end
        if key == leaderKey then text = text .. " |cff40ff40(raid)|r" end
        items[#items + 1] = { text = text, checked = key == currentKey, func = function() onPick(key) end }
    end
    self:ShowMenu(anchor, items)
end

-- Sorted list of raid member names (or just me when not in a raid).
function UI.RosterNames()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name then out[#out + 1] = Addon:NormalizeName(name) end
        end
    else
        out[1] = Addon:PlayerName()
    end
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- Link boxes: shift-clicking an item link while the box has focus fills it.
---------------------------------------------------------------------------
local linkBoxes = {}

local function onInsertLink(link)
    if type(link) ~= "string" or not link:find("item:", 1, true) then return end
    for _, box in ipairs(linkBoxes) do
        if box:IsVisible() and box:HasFocus() then
            local id = Engine.ItemIDFromLink(link)
            if id then
                box:SetText(link)
                box:ClearFocus()
                box.onItem(id, link)
            end
        end
    end
end

if ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
end
-- Newer Mainline builds route insertion through ChatFrameUtil; hook it too
-- (a second call with the same link is harmless).
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
end

-- onItem(itemID, linkOrNil). Typing an item ID / link + Enter also works.
function UI:CreateLinkBox(parent, width, onItem)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb.onItem = onItem
    eb:SetScript("OnEnterPressed", function(self)
        local text = self:GetText() or ""
        local id = Engine.ItemIDFromLink(text)
        self:ClearFocus()
        if id then self.onItem(id, text:find("|H", 1, true) and text or nil) end
    end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    UI.SetTooltip(eb, "Click here, then shift-click an item link (bags, chat, loot, this window) - or type an item ID and press Enter.")
    table.insert(linkBoxes, eb)
    return eb
end

---------------------------------------------------------------------------
-- Copyable text dialog (export)
---------------------------------------------------------------------------
function UI:ShowText(title, text)
    local f = self.textDialog
    if not f then
        f = self:CreateWindow("TextDialog", title, 480, 340)
        local sf = CreateFrame("ScrollFrame", "IDWLC_TextScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, -32)
        sf:SetPoint("BOTTOMRIGHT", -34, 34)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(420)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Read-only: undo user edits but keep it selectable / copyable.
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(f.text or "")
                self:HighlightText()
            end
        end)
        sf:SetScrollChild(eb)
        sf:HookScript("OnSizeChanged", function(_, w) eb:SetWidth(math.max(1, w or 1)) end)
        local hint = self:Label(f, "Ctrl+C to copy.", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", 14, 14)
        f.edit = eb
        self.textDialog = f
    end
    f.title:SetText(title)
    f.text = (text and text ~= "") and text or "(nothing to export)"
    f:Show()
    f.edit:SetText(f.text)
    f.edit:HighlightText()
    f.edit:SetFocus()
end

---------------------------------------------------------------------------
-- Refresh plumbing: re-render shown windows on state changes (debounced).
---------------------------------------------------------------------------
local refreshPending = false

function UI:RefreshShown(delay)
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(delay or 0.05, function()
        refreshPending = false
        for _, f in ipairs(UI.windows) do
            if f:IsShown() and f.Refresh then
                local ok, err = pcall(f.Refresh, f)
                if not ok then geterrorhandler()(err) end
            end
        end
    end)
end

for _, event in ipairs({
    "SESSION_CHANGED", "RESERVES_CHANGED", "MY_RESERVES_CHANGED", "LOOT_LIST_CHANGED",
    "LOOT_ADDED", "ROLL_STARTED", "ROLL_UPDATED", "ROLL_ENDED", "RESERVE_REJECTED",
}) do
    Addon:On(event, function() UI:RefreshShown() end)
end

-- Item names / icons arrive asynchronously; batch them up.
Addon:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() UI:RefreshShown(0.3) end)
Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function() UI:RefreshShown(0.3) end)
