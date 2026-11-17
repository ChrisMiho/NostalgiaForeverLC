-- IDontWannaLC - Roll popup (raid members)
-- Shown when the raid leader puts an item up. Tells you how the item is
-- handled and whether you may roll; "Roll" does /roll 1-100 for you.
-- The raid leader uses the loot window instead, so the popup skips them.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Loot = ns.Loot
local MODE = Engine.MODE

local popup
local state   -- copy of ns.Loot.remote for the item shown
local phase   -- "up" | "rolled" | "won"
local hideTimer

local function sortedNames(set)
    local out = {}
    for n in pairs(set or {}) do out[#out + 1] = n end
    table.sort(out)
    return out
end

local function modeText(r)
    local names = sortedNames(r.eligible)
    local list = table.concat(names, ", ")
    if r.mode == MODE.RESTRICTED then
        return UI.Color(UI.MODE_COLORS.RESTRICTED, "Restricted (legendary+): the raid leader decides who gets it.")
    elseif r.mode == MODE.HARD then
        return UI.Color(UI.MODE_COLORS.HARD, "Hard reserved" .. (#names > 0 and (" by " .. list) or "") .. ".")
    elseif r.mode == MODE.SOFT then
        return UI.Color(UI.MODE_COLORS.SOFT, "Soft reserved - only "
            .. (#names > 0 and list or "soft reservers") .. " may roll.")
    end
    return UI.Color(UI.MODE_COLORS.OPEN, "Not reserved - open roll for everyone.")
end

local function setButtons(showRoll, rollEnabled, passText)
    popup.rollBtn:SetShown(showRoll)
    popup.rollBtn:SetEnabled(rollEnabled)
    popup.rollBtn:SetText(phase == "rolled" and "Rolled" or "Roll (1-100)")
    popup.passBtn:SetText(passText)
    popup.passBtn:Show()
end

local function refresh(self)
    if not state then return end
    self.item:SetItem(state.itemID)
    if phase == "won" then
        self.mode:SetText(UI.Color("40ff40", "You won!"))
        self.status:SetText("The raid leader will trade it to you.")
        popup.rollBtn:Hide()
        popup.passBtn:SetText("OK")
        return
    end
    self.mode:SetText(modeText(state))

    local can = Loot:CanIRoll()
    local names = sortedNames(state.eligible)
    if state.mode == MODE.HARD and #names == 1 and names[1] == Addon:PlayerName() then
        self.status:SetText(UI.Color("40ff40", "It's your hard reserve - no roll needed."))
        setButtons(false, false, "OK")
    elseif can == true then
        self.status:SetText(phase == "rolled" and "Roll sent - good luck!" or "You may roll for this item.")
        setButtons(true, phase ~= "rolled", "Pass")
    elseif can == false then
        self.status:SetText(state.mode == MODE.RESTRICTED
            and "Restricted - the raid leader decides."
            or UI.Color("ff9933", "Reserved by others - you can't roll."))
        setButtons(false, false, "OK")
    else
        self.status:SetText("Check raid chat to see who may roll.")
        setButtons(true, phase ~= "rolled", "Pass")
    end
end

local function create()
    local f = UI:CreateWindow("RollPopup", "Item up for roll", 340, 150, { "TOP", 0, -140 })
    popup = f
    f.Refresh = refresh
    f.item = UI:CreateItemButton(f, 24)
    f.item:SetPoint("TOPLEFT", 16, -34)
    f.item:SetPoint("RIGHT", -16, 0)
    f.mode = UI:Label(f)
    f.mode:SetPoint("TOPLEFT", 16, -66)
    f.mode:SetPoint("RIGHT", -16, 0)
    f.status = UI:Label(f, nil, "GameFontHighlight")
    f.status:SetPoint("TOPLEFT", 16, -86)
    f.status:SetPoint("RIGHT", -16, 0)
    f.rollBtn = UI:Button(f, "Roll (1-100)", 120, 24, function()
        Loot:DoRoll()
        phase = "rolled"
        f:Refresh()
    end)
    f.rollBtn:SetPoint("BOTTOMLEFT", 40, 14)
    f.passBtn = UI:Button(f, "Pass", 120, 24, function() f:Hide() end)
    f.passBtn:SetPoint("BOTTOMRIGHT", -40, 14)
    f:HookScript("OnHide", function()
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    end)
    return f
end

local function show()
    local f = popup or create()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if f:IsShown() then f:Refresh() else f:Show() end
end

Addon:On("ROLL_STARTED", function()
    if Addon:IsLeader() then return end
    local r = Loot.remote
    if not r then return end
    -- A tie re-roll reuses the id; let tied players roll again.
    state = { id = r.id, itemID = r.itemID, mode = r.mode, eligible = r.eligible, unknownList = r.unknownList }
    phase = "up"
    show()
end)

Addon:On("ROLL_ENDED", function(entry, winner)
    if Addon:IsLeader() then return end
    if winner and winner == Addon:PlayerName() then
        state = state or {}
        state.itemID = (entry and entry.itemID) or state.itemID
        phase = "won"
        show()
        hideTimer = C_Timer.NewTimer(8, function()
            hideTimer = nil
            if popup then popup:Hide() end
        end)
    elseif popup and popup:IsShown() and state and entry and state.id == entry.id then
        popup:Hide()
    end
end)
