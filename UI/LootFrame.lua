-- IDontWannaLC - Loot window (raid leader)
-- Lists collected drops with the reserve decision, runs rolls and records
-- the leader's award. The addon never distributes loot: awarding only
-- announces the winner; the leader still loots / trades the item.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Loot = ns.Loot
local STATE = Loot.STATE
local MODE = Engine.MODE

local WIDTH, HEIGHT = 620, 600
local ROW_H = 40
local MAX_STANDINGS = 7

local frame

local function modeColor(decision)
    return UI.MODE_COLORS[decision and decision.mode or ""] or "ffffff"
end

local function decisionText(decision)
    if not decision then return "" end
    return UI.Color(modeColor(decision), Loot.Describe(decision))
end

local function suggestedWinner(entry)
    if entry.suggested then return entry.suggested end
    if entry.roll then return (entry.roll:Winner()) end
end

---------------------------------------------------------------------------
-- Entry rows
---------------------------------------------------------------------------
local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.item = UI:CreateItemButton(row, 20)
    row.item:SetPoint("TOPLEFT", 4, -2)
    row.item:SetPoint("RIGHT", row, "RIGHT", -180, 0)
    row.sub = UI:Label(row)
    row.sub:SetPoint("TOPLEFT", 28, -24)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -180, 0)
    row.sub:SetWordWrap(false)
    row.btn2 = UI:Button(row, "Remove", 70, 20)
    row.btn2:SetPoint("RIGHT", -4, 0)
    row.btn2:SetScript("OnClick", function() Loot:RemoveEntry(row.data.id) end)
    row.btn1 = UI:Button(row, "Start roll", 90, 20)
    row.btn1:SetPoint("RIGHT", row.btn2, "LEFT", -4, 0)
    row.btn1:SetScript("OnClick", function() Loot:StartRoll(row.data.id) end)
    row.status = UI:Label(row, nil, "GameFontNormal")
    row.status:SetPoint("RIGHT", row.btn2, "LEFT", -8, 0)
    return row
end

local function updateRow(row, e, index)
    local leader = Addon:IsLeader()
    row.item:SetItem(e.itemID, e.link)
    row.sub:SetText(("%s  %s  %s"):format(
        UI.Color(UI.GREY, e.source or "?"), UI.Color("ffd100", e.state), decisionText(e.decision)))
    if Loot.active == e then
        row.bg:SetColorTexture(1, 0.82, 0, 0.15)
    else
        row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
    end

    row.btn1:Hide()
    row.status:SetText("")
    row.btn2:SetShown(leader and e.state ~= STATE.ROLLING)
    row.btn2:SetEnabled(leader)
    if e.state == STATE.PENDING then
        row.btn1:Show()
        row.btn1:SetEnabled(leader and Loot.active == nil)
    elseif e.state == STATE.ROLLING then
        row.status:SetText(UI.Color("ffd100", "Rolling..."))
    elseif e.state == STATE.DONE then
        row.status:SetText(UI.Color("40ff40", "-> " .. tostring(e.winner)))
    end
end

---------------------------------------------------------------------------
-- Active roll panel
---------------------------------------------------------------------------
local function rollSummary(entry)
    local roll, d = entry.roll, entry.decision
    if not roll then return "" end
    if d.mode == MODE.RESTRICTED then
        return UI.Color(UI.MODE_COLORS.RESTRICTED, "Restricted item - no roll. Pick a player with Award to...")
    end
    if d.mode == MODE.HARD and #d.eligible == 1 then
        return UI.Color(UI.MODE_COLORS.HARD, "Hard reserved by " .. d.eligible[1] .. " - no roll needed.")
    end
    local lines = { roll.open and UI.Color("40ff40", "Rolls open (/roll 1-100)") or UI.Color("ff9933", "Roll closed") }
    local standings = roll:Standings()
    if #standings == 0 then lines[#lines + 1] = UI.Color(UI.GREY, "No rolls yet.") end
    for i, s in ipairs(standings) do
        if i > MAX_STANDINGS then
            lines[#lines + 1] = UI.Color(UI.GREY, ("...and %d more"):format(#standings - MAX_STANDINGS))
            break
        end
        local line = ("%d. %s  %d"):format(i, s.name, s.value)
        local sc = d.softCount and d.softCount[s.name]
        if sc and sc > 1 then line = line .. UI.Color(UI.SOFT_COLOR, (" (SR x%d)"):format(sc)) end
        lines[#lines + 1] = i == 1 and UI.Color("ffd100", line) or line
    end
    return table.concat(lines, "\n")
end

local function rollSide(entry)
    local roll = entry.roll
    if not roll then return "" end
    local lines = {}
    local missing = roll:Missing()
    if missing and #missing > 0 then
        lines[#lines + 1] = "Waiting on: " .. table.concat(missing, ", ")
    elseif not missing and roll.open then
        lines[#lines + 1] = UI.Color(UI.GREY, "Anyone may roll.")
    end
    local _, tied = roll:Winner()
    if tied then lines[#lines + 1] = UI.Color("ff9933", "Tied: " .. table.concat(tied, ", ")) end
    if #roll.ignored > 0 then
        lines[#lines + 1] = UI.Color(UI.GREY, "Ignored rolls:")
        local first = math.max(1, #roll.ignored - 3) -- show the latest few
        for i = first, #roll.ignored do
            local ig = roll.ignored[i]
            lines[#lines + 1] = UI.Color(UI.GREY, ("  %s %s - %s"):format(ig.name or "?", tostring(ig.value or ""), ig.reason or ""))
        end
    end
    return table.concat(lines, "\n")
end

local function refreshActive(f)
    local entry = Loot.active
    local leader = Addon:IsLeader()
    local p = f.panel
    if not entry then
        p.item:SetItem(nil)
        p.title:SetText(UI.Color(UI.GREY, "No roll in progress - press Start roll on an item."))
        p.decision:SetText("")
        p.standings:SetText("")
        p.side:SetText("")
        p.closeBtn:Hide()
        p.cancelBtn:Hide()
        p.awardSuggested:Hide()
        p.awardBox:Hide()
        p.awardPick:Hide()
        p.awardBtn:Hide()
        p.awardLabel:Hide()
        return
    end
    p.title:SetText("Now rolling:")
    p.item:SetItem(entry.itemID, entry.link)
    p.decision:SetText(decisionText(entry.decision))
    p.standings:SetText(rollSummary(entry))
    p.side:SetText(rollSide(entry))

    p.closeBtn:Show()
    p.closeBtn:SetEnabled(leader and entry.roll and entry.roll.open)
    p.cancelBtn:Show()
    p.cancelBtn:SetEnabled(leader)
    local winner = suggestedWinner(entry)
    if winner then
        p.awardSuggested:SetText("Award to " .. winner)
        p.awardSuggested.winnerName = winner
        p.awardSuggested:Show()
        p.awardSuggested:SetEnabled(leader)
    else
        p.awardSuggested:Hide()
    end
    p.awardLabel:Show()
    p.awardBox:Show()
    p.awardPick:Show()
    p.awardBtn:Show()
    p.awardPick:SetEnabled(leader)
    p.awardBtn:SetEnabled(leader)
end

local function awardTo(name)
    local entry = Loot.active
    name = type(name) == "string" and name:match("^%s*(.-)%s*$")
    if not entry or not name or name == "" then return end
    Loot:Award(entry.id, name)
    frame.panel.awardBox:SetText("")
end

local function createPanel(f)
    local p = UI:Inset(f)
    p:SetPoint("BOTTOMLEFT", 12, 34)
    p:SetPoint("BOTTOMRIGHT", -12, 34)
    p:SetHeight(236)
    f.panel = p

    p.title = UI:Label(p, nil, "GameFontNormal")
    p.title:SetPoint("TOPLEFT", 10, -10)
    p.item = UI:CreateItemButton(p, 20)
    p.item:SetPoint("LEFT", p.title, "RIGHT", 8, 0)
    p.item:SetWidth(300)
    p.decision = UI:Label(p)
    p.decision:SetPoint("TOPLEFT", 10, -34)
    p.decision:SetPoint("RIGHT", -10, 0)
    p.decision:SetWordWrap(false)

    p.standings = UI:Label(p)
    p.standings:SetPoint("TOPLEFT", 10, -54)
    p.standings:SetWidth(280)
    p.standings:SetJustifyV("TOP")
    p.side = UI:Label(p)
    p.side:SetPoint("TOPLEFT", 300, -54)
    p.side:SetPoint("RIGHT", -10, 0)
    p.side:SetJustifyV("TOP")

    -- Buttons: close / cancel / suggested award.
    p.closeBtn = UI:Button(p, "Close roll", 90, 22, function() Loot:CloseRoll() end,
        "Stop accepting rolls and announce the highest roll (ties re-roll).")
    p.closeBtn:SetPoint("BOTTOMLEFT", 10, 38)
    p.cancelBtn = UI:Button(p, "Cancel", 80, 22, function() Loot:CancelRoll() end,
        "Cancel this roll; the item goes back to pending.")
    p.cancelBtn:SetPoint("LEFT", p.closeBtn, "RIGHT", 6, 0)
    p.awardSuggested = UI:Button(p, "Award", 200, 22, function(btn) awardTo(btn.winnerName) end,
        "Announce this player as the winner.")
    p.awardSuggested:SetPoint("LEFT", p.cancelBtn, "RIGHT", 6, 0)

    -- Award to anyone (restricted items, leader overrides).
    p.awardLabel = UI:Label(p, "Award to...", "GameFontNormalSmall")
    p.awardLabel:SetPoint("BOTTOMLEFT", 12, 16)
    p.awardBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    p.awardBox:SetSize(140, 20)
    p.awardBox:SetAutoFocus(false)
    p.awardBox:SetPoint("LEFT", p.awardLabel, "RIGHT", 12, 0)
    p.awardBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        awardTo(self:GetText())
    end)
    p.awardPick = UI:Button(p, "Pick...", 70, 22, function(btn)
        local items = {}
        for _, name in ipairs(UI.RosterNames()) do
            items[#items + 1] = { text = name, func = function() p.awardBox:SetText(name) end }
        end
        UI:ShowMenu(btn, items)
    end, "Choose any raid member.")
    p.awardPick:SetPoint("LEFT", p.awardBox, "RIGHT", 6, 0)
    p.awardBtn = UI:Button(p, "Award", 70, 22, function() awardTo(p.awardBox:GetText()) end,
        "Announce the typed / picked player as the winner.")
    p.awardBtn:SetPoint("LEFT", p.awardPick, "RIGHT", 4, 0)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function refresh(self)
    local leader = Addon:IsLeader()
    self.banner:SetText(leader and "" or UI.Color("ff9933", "Only the raid leader manages loot."))
    self.addBox:SetEnabled(leader)
    self.clearBtn:SetEnabled(leader)
    self.list:SetData(Loot.entries)
    self.empty:SetShown(#Loot.entries == 0)
    refreshActive(self)
end

local function create()
    local f = UI:CreateWindow("Loot", "I Don't Wanna LC - Loot", WIDTH, HEIGHT)
    frame = f
    f.Refresh = refresh

    local addLabel = UI:Label(f, "Add item (shift-click):", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 16, -38)
    f.addBox = UI:CreateLinkBox(f, 160, function(id, link)
        Loot:AddManual(link or id)
        f.addBox:SetText("")
    end)
    f.addBox:SetPoint("LEFT", addLabel, "RIGHT", 10, 0)
    f.banner = UI:Label(f)
    f.banner:SetPoint("LEFT", f.addBox, "RIGHT", 10, 0)
    f.clearBtn = UI:Button(f, "Clear finished", 110, 22, function() Loot:ClearDone() end,
        "Remove awarded items from the list.")
    f.clearBtn:SetPoint("TOPRIGHT", -16, -34)

    local inset = UI:Inset(f)
    inset:SetPoint("TOPLEFT", 12, -62)
    inset:SetPoint("BOTTOMRIGHT", -12, 276)
    f.list = UI:CreateScrollList(f, ROW_H, createRow, updateRow)
    f.list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
    f.empty = UI:Label(f, "No loot yet. Drops (epic+, restricted) are added when you open a corpse\nor receive them - or shift-click an item into the box above.", "GameFontDisable")
    f.empty:SetJustifyH("CENTER")
    f.empty:SetPoint("CENTER", inset, "CENTER")

    createPanel(f)

    local footer = UI:Label(f, "Award announces the winner - you still loot/trade the item. The addon never distributes loot.", "GameFontDisableSmall")
    footer:SetPoint("BOTTOM", 0, 14)
    footer:SetJustifyH("CENTER")
    return f
end

function UI:ToggleLoot()
    UI:ToggleWindow(frame or create())
end

function UI:ShowLoot()
    local f = frame or create()
    if f:IsShown() then f:Refresh() else f:Show() end
end

-- Pop the window up for the raid leader whenever new loot is collected.
Addon:On("LOOT_ADDED", function()
    if Addon:IsLeader() then UI:ShowLoot() end
end)
