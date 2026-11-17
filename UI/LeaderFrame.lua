-- IDontWannaLC - Leader window (raid leader; read-only for everyone else)
-- Reserve settings, lock, raid choice, broadcast / reset / export, and a
-- table of every player's reserves with leader removal.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Reserves, RaidData = ns.Reserves, ns.RaidDataAPI
local HARD, SOFT = Engine.KIND.HARD, Engine.KIND.SOFT

local WIDTH, HEIGHT = 560, 594
local ROW_H = 20
local MAX_COUNT = 10
local SAVED_TIP = "Saved for this raid and announced to the raid automatically."

local frame

StaticPopupDialogs["IDWLC_RESET_ALL"] = {
    text = "I Don't Wanna LC:\nClear ALL reserves and award history and unlock reserves?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if ns.Reserves:LeaderReset() then Addon:Print("All reserves cleared.") end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Player table
---------------------------------------------------------------------------
-- [shortName] = classFile for current raid members.
local function rosterClasses()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if name then out[Addon:NormalizeName(name)] = classFile or "" end
        end
    end
    return out
end

local function classRGB(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

-- Flatten reserves into rows: player header, then one row per reserve;
-- raid members without reserves at the end (greyed).
local function buildRows()
    local s = Addon.session
    local roster = rosterClasses()
    local rows, names = {}, {}
    for name in pairs(s.reserves) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local r = s.reserves[name]
        local inRaid = roster[name] ~= nil
        rows[#rows + 1] = { type = "player", name = name, r = r, class = roster[name], away = IsInRaid() and not inRaid }
        for _, id in ipairs(r.hard) do rows[#rows + 1] = { type = "item", name = name, itemID = id, kind = HARD } end
        for _, id in ipairs(r.soft) do rows[#rows + 1] = { type = "item", name = name, itemID = id, kind = SOFT } end
    end
    local missing = {}
    for name, class in pairs(roster) do
        if not s.reserves[name] then missing[#missing + 1] = { name = name, class = class } end
    end
    table.sort(missing, function(a, b) return a.name < b.name end)
    for _, m in ipairs(missing) do
        rows[#rows + 1] = { type = "none", name = m.name, class = m.class }
    end
    return rows
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = UI:Label(row, nil, "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.info = UI:Label(row)
    row.info:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.tag = UI:Label(row, nil, "GameFontNormalSmall")
    row.tag:SetPoint("LEFT", 22, 0)
    row.item = UI:CreateItemButton(row, 16)
    row.item:SetPoint("LEFT", 46, 0)
    row.item:SetPoint("RIGHT", row, "RIGHT", -30, 0)
    row.remove = UI:Button(row, "x", 20, 18, function()
        Reserves:LeaderRemove(row.data.name, row.data.itemID, row.data.kind)
    end, "Remove this reserve (raid leader override, ignores lock)")
    row.remove:SetPoint("RIGHT", -4, 0)
    return row
end

local function updateRow(row, d)
    local isItem = d.type == "item"
    row.name:SetShown(not isItem)
    row.info:SetShown(not isItem)
    row.tag:SetShown(isItem)
    row.item:SetShown(isItem)
    row.remove:SetShown(isItem and Addon:IsLeader())
    if isItem then
        row.tag:SetText(d.kind == HARD and UI.Color(UI.HARD_COLOR, "HR") or UI.Color(UI.SOFT_COLOR, "SR"))
        row.item:SetItem(d.itemID)
        return
    end
    row.name:SetText(d.name)
    if d.type == "none" then
        row.name:SetTextColor(0.5, 0.5, 0.5)
        row.info:SetText(UI.Color(UI.GREY, "no reserves yet"))
    else
        row.name:SetTextColor(classRGB(d.class))
        local set = Addon.session.settings
        local info = ("HR %d/%d   SR %d/%d"):format(#d.r.hard, set.hardReserves, #d.r.soft, set.softReserves)
        if d.away then info = info .. "   " .. UI.Color(UI.GREY, "(not in raid)") end
        row.info:SetText(info)
    end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function refresh(self)
    local s = Addon.session
    local leader = Addon:IsLeader()
    self.banner:SetText(leader and UI.Color("40ff40", "You are the raid leader.")
        or UI.Color("ff9933", "Read-only: only the raid leader can change these settings."))

    self.raidButton:SetText(s.raidKey and RaidData:GetName(s.raidKey) or "(choose raid)")
    if not leader then
        self.presetNote:SetText(UI.Color(UI.GREY, "Rules are set by the raid leader."))
    elseif not s.raidKey then
        self.presetNote:SetText(UI.Color(UI.GREY, "Choose a raid - its rules are saved per raid."))
    elseif Reserves:HasPreset(s.raidKey) then
        self.presetNote:SetText(UI.Color("40ff40", "Saved rules for this raid"))
    else
        self.presetNote:SetText(UI.Color(UI.GREY, "Using your default rules - changes will be saved for this raid"))
    end
    self.lockButton:SetText(s.locked and "Unlock reserves" or "Lock reserves")
    self.lockState:SetText(s.locked and UI.Color("ff4040", "LOCKED") or UI.Color("40ff40", "Open"))
    self.hardValue:SetText(s.settings.hardReserves)
    self.softValue:SetText(s.settings.softReserves)
    self.double:SetChecked(s.settings.allowDoubleSoft)
    self.consume:SetChecked(s.settings.consumeOnAward)

    for _, c in ipairs(self.leaderControls) do c:SetEnabled(leader) end
    self.hardMinus:SetEnabled(leader and s.settings.hardReserves > 0)
    self.hardPlus:SetEnabled(leader and s.settings.hardReserves < MAX_COUNT)
    self.softMinus:SetEnabled(leader and s.settings.softReserves > 0)
    self.softPlus:SetEnabled(leader and s.settings.softReserves < MAX_COUNT)

    local rows = buildRows()
    self.list:SetData(rows)
    self.empty:SetShown(#rows == 0)
    local players = 0
    for _ in pairs(s.reserves) do players = players + 1 end
    self.count:SetText(("%d player(s) with reserves"):format(players))
end

local function setCounts(dh, ds)
    local set = Addon.session.settings
    local h = math.max(0, math.min(MAX_COUNT, set.hardReserves + dh))
    local so = math.max(0, math.min(MAX_COUNT, set.softReserves + ds))
    Reserves:LeaderSetCounts(h, so)
end

-- "Label: [-] n [+]" control. Returns minus, value, plus.
local function counter(f, label, x, y, onMinus, onPlus)
    local l = UI:Label(f, label, "GameFontNormal")
    l:SetPoint("TOPLEFT", x, y)
    local minus = UI:Button(f, "-", 22, 20, onMinus, SAVED_TIP)
    minus:SetPoint("LEFT", l, "RIGHT", 8, 0)
    local value = UI:Label(f, "0", "GameFontHighlight")
    value:SetJustifyH("CENTER")
    value:SetWidth(24)
    value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = UI:Button(f, "+", 22, 20, onPlus, SAVED_TIP)
    plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
    return minus, value, plus
end

local function create()
    local f = UI:CreateWindow("Leader", "I Don't Wanna LC - Raid Leader", WIDTH, HEIGHT)
    frame = f
    f.Refresh = refresh

    f.banner = UI:Label(f)
    f.banner:SetPoint("TOPLEFT", 16, -32)

    -- Raid + lock.
    local raidLabel = UI:Label(f, "Raid:", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 16, -56)
    f.raidButton = UI:Button(f, "", 200, 22, function(btn)
        UI:ShowRaidMenu(btn, Addon.session.raidKey, function(key) Reserves:LeaderSetRaid(key) end)
    end, "Raid everyone reserves for. Picking a raid loads the rules you saved for it.")
    f.raidButton:SetPoint("LEFT", raidLabel, "RIGHT", 8, 0)
    f.lockButton = UI:Button(f, "Lock reserves", 120, 22, function()
        Reserves:LeaderSetLocked(not Addon.session.locked)
    end, "Lock: nobody can change reserves (announced in raid chat).")
    f.lockButton:SetPoint("LEFT", f.raidButton, "RIGHT", 10, 0)
    f.lockState = UI:Label(f, nil, "GameFontHighlight")
    f.lockState:SetPoint("LEFT", f.lockButton, "RIGHT", 8, 0)
    f.presetNote = UI:Label(f)
    f.presetNote:SetPoint("TOPLEFT", 60, -82)

    -- Counts.
    f.hardMinus, f.hardValue, f.hardPlus = counter(f, "Hard reserves:", 16, -102,
        function() setCounts(-1, 0) end, function() setCounts(1, 0) end)
    f.softMinus, f.softValue, f.softPlus = counter(f, "Soft reserves:", 260, -102,
        function() setCounts(0, -1) end, function() setCounts(0, 1) end)

    -- Options.
    f.double = UI:CheckButton(f, "Allow double soft reserve", function(v)
        Reserves:LeaderSetOption("allowDoubleSoft", v)
    end, "A player may spend two soft reserves on the same item (two entries).\n" .. SAVED_TIP)
    f.double:SetPoint("TOPLEFT", 12, -126)
    f.consume = UI:CheckButton(f, "Consume on award", function(v)
        Reserves:LeaderSetOption("consumeOnAward", v)
    end, "Winning an item removes the winner's reserve on it.\n" .. SAVED_TIP)
    f.consume:SetPoint("TOPLEFT", 236, -126)

    -- Actions.
    f.broadcast = UI:Button(f, "Broadcast", 100, 22, function()
        ns.Comm:SendConfig()
        ns.Comm:SendSync()
        Addon:Print("Settings and reserves broadcast to the raid.")
    end, "Re-send settings and the full reserve list to the raid.")
    f.broadcast:SetPoint("TOPLEFT", 16, -158)
    f.export = UI:Button(f, "Export", 100, 22, function()
        UI:ShowText("Reserves export", Reserves:Export())
    end, "Plain-text list of all reserves (copy into Discord etc.).")
    f.export:SetPoint("LEFT", f.broadcast, "RIGHT", 8, 0)
    f.reset = UI:Button(f, "Reset all", 100, 22, function()
        StaticPopup_Show("IDWLC_RESET_ALL")
    end, "Clear every reserve and the award history.")
    f.reset:SetPoint("LEFT", f.export, "RIGHT", 8, 0)
    f.count = UI:Label(f)
    f.count:SetPoint("LEFT", f.reset, "RIGHT", 12, 0)

    -- Export works for everyone; the rest is leader-only.
    f.leaderControls = { f.raidButton, f.lockButton, f.double, f.consume, f.broadcast, f.reset }

    -- Player table.
    local inset = UI:Inset(f)
    inset:SetPoint("TOPLEFT", 12, -190)
    inset:SetPoint("BOTTOMRIGHT", -12, 12)
    f.list = UI:CreateScrollList(f, ROW_H, createRow, updateRow)
    f.list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
    f.empty = UI:Label(f, "No reserves yet.", "GameFontDisable")
    f.empty:SetPoint("CENTER", inset, "CENTER")
    return f
end

function UI:ToggleLeader()
    UI:ToggleWindow(frame or create())
end
