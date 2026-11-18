-- NostalgiaForeverLC - Loot window (everyone in the raid)
-- Pops up when loot drops. Lists the drops under the boss they came from,
-- each with who may roll for it according to the hard / soft reserves, and
-- shows the rolls as they come in. The raid leader starts rolls and awards
-- from here; everyone else watches (and can roll when eligible). The addon
-- never distributes loot: awarding announces the winner in raid chat and
-- records it in the loot ledger; the leader still loots / trades the item.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Loot = ns.Loot
local STATE = Loot.STATE
local MODE = Engine.MODE

local WIDTH, HEIGHT = 620, 600
local ROW_H, BOSS_ROW_H = 40, 22
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
-- Drops grouped under the boss they came from, in the order they dropped:
-- { boss = "Lucifron", count = 3 }, entry, entry, entry, { boss = ... }, ...
local function buildRows()
    local order, groups = {}, {}
    for _, e in ipairs(Loot.entries) do
        local boss = e.source or "?"
        if not groups[boss] then
            groups[boss] = {}
            order[#order + 1] = boss
        end
        table.insert(groups[boss], e)
    end
    local rows = {}
    for _, boss in ipairs(order) do
        rows[#rows + 1] = { boss = boss, count = #groups[boss] }
        for _, e in ipairs(groups[boss]) do rows[#rows + 1] = e end
    end
    return rows
end

local function rowHeight(d)
    return d.boss and BOSS_ROW_H or ROW_H
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.boss = UI:Label(row, nil, "GameFontNormal")
    row.boss:SetPoint("BOTTOMLEFT", 4, 3)
    row.item = UI:CreateItemButton(row, 20)
    row.item:SetPoint("TOPLEFT", 4, -2)
    row.item:SetPoint("RIGHT", row, "RIGHT", -180, 0)
    row.sub = UI:Label(row)
    row.sub:SetPoint("TOPLEFT", 28, -24)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -180, 0)
    row.sub:SetWordWrap(false)
    -- Pending: [Start roll] [Remove].  Awarded: [Undo] [Handed out / Not yet].
    row.btn2 = UI:Button(row, "Remove", 84, 20, nil, function()
        if row.data and row.data.state == STATE.DONE then
            return "Tick this item off once you have traded it to the player (trades are also noticed automatically)."
        end
        return "Take this drop off the list (added by mistake)."
    end)
    row.btn2:SetPoint("RIGHT", -4, 0)
    row.btn2:SetScript("OnClick", function()
        local e = row.data
        if e.state == STATE.DONE then Loot:SetTraded(e.id, not e.traded) else Loot:RemoveEntry(e.id) end
    end)
    row.btn1 = UI:Button(row, "Start roll", 90, 20, nil, function()
        if row.data and row.data.state == STATE.DONE then
            return "Take this award back: the item is pending again and the player's reserve returns. Announced in raid chat."
        end
        return "Put this item up: announces who may roll."
    end)
    row.btn1:SetPoint("RIGHT", row.btn2, "LEFT", -4, 0)
    row.btn1:SetScript("OnClick", function()
        local e = row.data
        if e.state == STATE.DONE then Loot:UndoAward(e.id) else Loot:StartRoll(e.id) end
    end)
    row.status = UI:Label(row, nil, "GameFontNormal")
    row.status:SetPoint("RIGHT", row.btn2, "LEFT", -8, 0)
    return row
end

local SPECIAL_LABEL = { DISENCHANT = "Disenchant", BANK = "Bank" }

local function updateRow(row, e, index)
    local leader = Addon:IsLootMaster()
    local isBoss = e.boss ~= nil
    row.boss:SetShown(isBoss)
    row.item:SetShown(not isBoss)
    row.sub:SetShown(not isBoss)
    if isBoss then
        row.boss:SetText(("%s |cff808080(%d)|r"):format(e.boss, e.count))
        row.bg:SetColorTexture(1, 0.82, 0, 0.08)
        row.btn1:Hide()
        row.btn2:Hide()
        row.status:SetText("")
        return
    end
    row.item:SetItem(e.itemID, e.link)
    row.sub:SetText(decisionText(e.decision))
    if Loot.active == e then
        row.bg:SetColorTexture(1, 0.82, 0, 0.15)
    else
        row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
    end

    row.btn1:Hide()
    row.status:SetText("")
    row.status:ClearAllPoints()
    row.status:SetPoint("RIGHT", row.btn2, "LEFT", -8, 0)
    row.btn2:SetShown(leader and e.state ~= STATE.ROLLING)
    row.btn2:SetEnabled(leader)
    row.btn2:SetText("Remove")
    if e.state == STATE.PENDING then
        row.btn1:SetText("Start roll")
        row.btn1:SetShown(leader)
        row.btn1:SetEnabled(leader and Loot.active == nil)
        if not leader then row.status:SetText(UI.Color(UI.GREY, "Waiting")) end
    elseif e.state == STATE.ROLLING then
        row.status:SetText(UI.Color("ffd100", e.fallback and "Open to all..." or "Rolling..."))
    elseif e.state == STATE.DONE then
        local who = e.special and (SPECIAL_LABEL[e.special] .. ": " .. tostring(e.winner)) or ("-> " .. tostring(e.winner))
        local handed = e.traded and UI.Color(UI.GREY, " (handed out)") or UI.Color("ff9933", " (to hand out)")
        row.status:SetText(UI.Color(e.special and "c0c0c0" or "40ff40", who) .. handed)
        if leader then
            row.btn1:SetText("Undo")
            row.btn1:Show()
            row.btn1:SetEnabled(true)
            row.btn2:SetText(e.traded and "Not yet" or "Handed out")
            row.status:ClearAllPoints()
            row.status:SetPoint("RIGHT", row.btn1, "LEFT", -8, 0)
        end
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
    local how = roll.osMax and ("/roll 100 main spec, /roll %d off spec"):format(roll.osMax) or "/roll 1-100"
    local lines = { roll.open and UI.Color("40ff40", "Rolls open (" .. how .. ")") or UI.Color("ff9933", "Roll closed") }
    if roll.plus then lines[#lines + 1] = UI.Color(UI.GREY, "Plus-ones: fewer items won this run goes first.") end
    if d.mode == MODE.HARD then
        lines[#lines + 1] = UI.Color(UI.MODE_COLORS.HARD, "Multiple hard reserves - only they roll; soft reserves ignored.")
    end
    local standings = roll:Standings()
    if #standings == 0 then lines[#lines + 1] = UI.Color(UI.GREY, "No rolls yet.") end
    for i, s in ipairs(standings) do
        if i > MAX_STANDINGS then
            lines[#lines + 1] = UI.Color(UI.GREY, ("...and %d more"):format(#standings - MAX_STANDINGS))
            break
        end
        local line = ("%d. %s  %d"):format(i, s.name, s.value)
        if s.bonus > 0 then line = line .. UI.Color(UI.SOFT_COLOR, (" +%d = %d"):format(s.bonus, s.total)) end
        if s.tier == 2 then line = line .. UI.Color(UI.GREY, " (off spec)") end
        if roll.plus then line = line .. UI.Color(UI.GREY, (" [+%d]"):format(s.plus)) end
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
    local leader = Addon:IsLootMaster()
    local p = f.panel
    p.rollBtn:Hide()
    p.osBtn:Hide()
    p.openBtn:Hide()
    p.deBtn:Hide()
    p.bankBtn:Hide()
    if not entry then
        p.item:SetItem(nil)
        p.title:SetText(UI.Color(UI.GREY, leader and "No roll in progress - press Start roll on an item."
            or "No roll in progress - the loot master starts the rolls."))
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

    -- Raid leader: run the roll and award. Everyone else: watch, and roll
    -- when eligible.
    p.closeBtn:SetShown(leader)
    p.closeBtn:SetEnabled(leader and entry.roll ~= nil and entry.roll.open == true)
    p.cancelBtn:SetShown(leader)
    local winner = leader and suggestedWinner(entry) or nil
    if winner then
        p.awardSuggested:SetText("Award to " .. winner)
        p.awardSuggested.winnerName = winner
        p.awardSuggested:Show()
    else
        p.awardSuggested:Hide()
    end
    p.awardLabel:SetShown(leader)
    p.awardBox:SetShown(leader)
    p.awardPick:SetShown(leader)
    p.awardBtn:SetShown(leader)
    -- Loot master: other ways to settle the item.
    local mode = entry.decision and entry.decision.mode
    p.openBtn:SetShown(leader and (mode == MODE.HARD or mode == MODE.SOFT))
    p.openBtn:SetEnabled(not (entry.roll and entry.roll.open)) -- close the reservers' roll first
    p.deBtn:SetShown(leader)
    p.bankBtn:SetShown(leader)
    if not leader and entry.roll and entry.roll.open and Loot:CanIRoll() ~= false then
        local rolled = entry.roll.rolls[Addon:PlayerName()] ~= nil or entry.roll.rolls[Addon:FullPlayerName()] ~= nil
        local offSpec = Loot:AllowsOffSpec(entry)
        p.rollBtn:SetText(rolled and "Rolled" or (offSpec and "Main spec (100)" or "Roll (1-100)"))
        p.rollBtn:SetEnabled(not rolled)
        p.rollBtn:Show()
        p.osBtn:SetShown(offSpec)
        p.osBtn:SetEnabled(not rolled)
    end
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

    -- Raid members: roll for the item when eligible.
    p.rollBtn = UI:Button(p, "Roll (1-100)", 130, 24, function() Loot:DoRoll() end, "Does /roll 1-100 for you.")
    p.rollBtn:SetPoint("BOTTOMLEFT", 10, 14)
    p.osBtn = UI:Button(p, "Off spec (99)", 110, 24, function() Loot:DoRoll(true) end,
        "Does /roll 1-99 for you. An off-spec roll only wins when nobody rolls main spec.")
    p.osBtn:SetPoint("LEFT", p.rollBtn, "RIGHT", 6, 0)

    -- Loot master: when nobody takes it.
    p.bankBtn = UI:Button(p, "Bank", 60, 22, function()
        if Loot.active then Loot:AwardSpecial(Loot.active.id, Loot.SPECIAL.BANK) end
    end, "Nobody wants it: keep it for the guild bank. Recorded in the ledger as banked; uses nobody's reserve.")
    p.bankBtn:SetPoint("BOTTOMRIGHT", -10, 38)
    p.deBtn = UI:Button(p, "Disenchant", 84, 22, function()
        if Loot.active then Loot:AwardSpecial(Loot.active.id, Loot.SPECIAL.DISENCHANT) end
    end, "Nobody wants it: send it to be disenchanted. Recorded in the ledger as disenchanted; uses nobody's reserve.")
    p.deBtn:SetPoint("RIGHT", p.bankBtn, "LEFT", -4, 0)
    p.openBtn = UI:Button(p, "Open to all", 90, 22, function() Loot:OpenToAll() end,
        "No reserver took it (passed, offline, didn't roll): put it up for everyone as an unreserved item.")
    p.openBtn:SetPoint("RIGHT", p.deBtn, "LEFT", -4, 0)

    -- Buttons: close / cancel / suggested award.
    p.closeBtn = UI:Button(p, "Close roll", 90, 22, function() Loot:CloseRoll() end,
        "Stop accepting rolls and announce the highest roll (ties re-roll).")
    p.closeBtn:SetPoint("BOTTOMLEFT", 10, 38)
    p.cancelBtn = UI:Button(p, "Cancel", 80, 22, function() Loot:CancelRoll() end,
        "Cancel this roll; the item goes back to pending.")
    p.cancelBtn:SetPoint("LEFT", p.closeBtn, "RIGHT", 6, 0)
    p.awardSuggested = UI:Button(p, "Award", 170, 22, function(btn) awardTo(btn.winnerName) end,
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
    local leader = Addon:IsLootMaster()
    local waiting = #Loot:Outstanding()
    if leader then
        self.banner:SetText("")
        self.handout:SetText(waiting > 0 and UI.Color("ff9933", waiting .. " to hand out") or "")
    else
        self.banner:SetText(UI.Color("ff9933", ("%s runs the rolls and hands out the loot."):format(
            Addon:GetLootMasterName() or "The raid leader")))
        self.handout:SetText("")
    end
    self.addLabel:SetShown(leader)
    self.addBox:SetShown(leader)
    self.list:SetData(buildRows())
    self.empty:SetShown(#Loot.entries == 0)
    refreshActive(self)
end

local create
create = function()
    local f = UI:CreateWindow("Loot", "Nostalgia Forever LC - Loot", WIDTH, HEIGHT)
    frame = f
    f.Refresh = refresh

    local addLabel = UI:Label(f, "Add item (shift-click):", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 16, -38)
    f.addLabel = addLabel
    f.addBox = UI:CreateLinkBox(f, 160, function(id, link)
        Loot:AddManual(link or id)
        f.addBox:SetText("")
    end)
    f.addBox:SetPoint("LEFT", addLabel, "RIGHT", 10, 0)
    f.banner = UI:Label(f)
    f.banner:SetPoint("TOPLEFT", 16, -38)
    f.clearBtn = UI:Button(f, "Clear finished", 110, 22, function()
        -- The loot master keeps items still to be handed out; anyone else
        -- just tidies their own view.
        Loot:ClearDone(not Addon:IsLootMaster())
    end, "Remove finished items from this window. They stay in the loot ledger. "
        .. "For the loot master, awarded items that haven't been handed out yet stay listed.")
    f.ledgerBtn = UI:Button(f, "Ledger", 80, 22, function() UI:ShowMain("ledger") end,
        "Every raid's drops and who got them.")
    f.clearBtn:SetPoint("TOPRIGHT", -16, -34)
    f.ledgerBtn:SetPoint("RIGHT", f.clearBtn, "LEFT", -6, 0)
    f.handout = UI:Label(f, nil, "GameFontNormalSmall")
    f.handout:SetPoint("RIGHT", f.ledgerBtn, "LEFT", -10, 0)

    local inset = UI:Inset(f)
    inset:SetPoint("TOPLEFT", 12, -62)
    inset:SetPoint("BOTTOMRIGHT", -12, 276)
    f.list = UI:CreateScrollList(f, ROW_H, createRow, updateRow, rowHeight)
    f.list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
    f.empty = UI:Label(f, "No loot yet. Drops (epic+, restricted) appear here when the raid leader\nopens a corpse or receives them.", "GameFontDisable")
    f.empty:SetJustifyH("CENTER")
    f.empty:SetPoint("CENTER", inset, "CENTER")

    createPanel(f)

    local footer = UI:Label(f, "Close this window any time (X or Esc) - it stays closed until this loot is done. /nflc loot reopens it.", "GameFontDisableSmall")
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

function UI:IsLootShown()
    return frame ~= nil and frame:IsShown()
end

---------------------------------------------------------------------------
-- Popping up - and staying out of the way
--
-- The window opens by itself when loot drops, but never over a fight (it
-- waits until you are out of combat), and once you close it, it stays
-- closed for the rest of that batch of loot: new drops and rolls only leave
-- a line in chat. It opens by itself again after the current loot has all
-- been handed out. /nflc loot reopens it at any time.
---------------------------------------------------------------------------
local dismissed = false   -- the user closed the window while loot was still being handled
local pendingShow = false -- wanted to pop up during combat
local lastHint = -100

local function lootInProgress()
    for _, e in ipairs(Loot.entries) do
        if e.state == STATE.PENDING or e.state == STATE.ROLLING then return true end
    end
    return false
end

local function inCombat()
    return Addon.inEncounter == true or (UnitAffectingCombat ~= nil and UnitAffectingCombat("player") == true)
end

function UI:IsLootDismissed()
    return dismissed
end

local function autoShow()
    if dismissed then
        if GetTime() - lastHint > 20 then
            lastHint = GetTime()
            Addon:Print("New loot - |cffffd100/nflc loot|r to open the loot window.")
        end
        return
    end
    if inCombat() then
        pendingShow = true
        return
    end
    UI:ShowLoot()
end

local baseCreate = create
create = function()
    local f = baseCreate()
    f:HookScript("OnShow", function() dismissed, pendingShow = false, false end)
    f:HookScript("OnHide", function()
        if lootInProgress() then dismissed = true end
    end)
    return f
end

Addon:On("LOOT_ADDED", autoShow)

local function afterCombat()
    if pendingShow and not inCombat() then
        pendingShow = false
        if lootInProgress() then autoShow() end
    end
end
Addon:On("ENCOUNTER_ENDED", afterCombat)
Addon:RegisterEvent("PLAYER_REGEN_ENABLED", afterCombat)

-- Everything handed out: the next drop may open the window again.
Addon:On("LOOT_LIST_CHANGED", function()
    if dismissed and not lootInProgress() then dismissed = false end
end)
