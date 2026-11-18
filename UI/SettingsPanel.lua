-- NostalgiaForeverLC - Settings tab
-- Sub-tabs:
--   General      debug output, window positions, command reference
--   Master Loot  the defaults you use when you lead a raid: hard / soft
--                reserves per player (1-10, default 1 / 3) and the other
--                loot rules. The counts are what the approval prompt offers
--                the first time you run a raid; everything is saved account
--                wide.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI

local SUBTABS = { { key = "general", title = "General" }, { key = "masterloot", title = "Master Loot" } }
local currentSub = "masterloot"

local COMMANDS = table.concat({
    "|cffffd100/nflc|r  open this window",
    "|cffffd100/nflc hr <item>|r, |cffffd100/nflc sr <item>|r  add or remove an item on the live raid's lists",
    "|cffffd100/nflc status|r, |cffffd100/nflc list|r  your reserves / everyone's reserves",
    "Raid leader:",
    "|cffffd100/nflc roster|r  who has picked, whisper reminders",
    "|cffffd100/nflc approve [hard soft]|r  approve the reserve counts",
    "|cffffd100/nflc lock|r, |cffffd100/nflc unlock|r  lock or unlock reserves",
    "|cffffd100/nflc loot|r  loot session window",
}, "\n")

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
local function createGeneral(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.debug = UI:CheckButton(f, "Show debug messages in chat", function(v)
        Addon.db.debug = v
    end, "Prints ignored rolls, failed addon messages and similar details.")
    f.debug:SetPoint("TOPLEFT", 0, -4)
    f.resetPos = UI:Button(f, "Reset window positions", 180, 22, function()
        Addon.charDB.framePositions = {}
        Addon:Print("Window positions reset - they apply after /reload.")
    end, "Forget where you dragged the addon's windows.")
    f.tooltips = UI:CheckButton(f, "Show reserve info on item tooltips", function(v)
        Addon.db.tooltips = v
    end, "On any item tooltip in the game: where the item is on your lists and, in the live raid, who has it reserved.")
    f.tooltips:SetPoint("TOPLEFT", 0, -30)
    f.resetPos:SetPoint("TOPLEFT", 4, -66)
    local title = UI:Label(f, "Commands", "GameFontNormal")
    title:SetPoint("TOPLEFT", 4, -110)
    local text = UI:Label(f, COMMANDS, "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 4, -130)
    text:SetPoint("TOPRIGHT", -4, -130)
    text:SetSpacing(4)
    f.version = UI:Label(f, "Version " .. tostring(Addon.version), "GameFontDisableSmall")
    f.version:SetPoint("BOTTOMLEFT", 4, 4)
    f.Refresh = function(self)
        self.debug:SetChecked(Addon.db.debug and true or false)
        self.tooltips:SetChecked(Addon.db.tooltips and true or false)
    end
    return f
end

---------------------------------------------------------------------------
-- Master Loot
---------------------------------------------------------------------------
local CHANNELS = { RAID_WARNING = "Raid warning", RAID = "Raid chat" }

local function createMasterLoot(parent)
    local f = CreateFrame("Frame", nil, parent)
    local settings = function() return Addon.db.settings end

    local intro = UI:Label(f, "Defaults for the raids you lead. When you first enter a raid as raid leader you are asked "
        .. "to approve the hard / soft counts for it; these are the numbers offered.", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 4, -4)
    intro:SetPoint("TOPRIGHT", -4, -4)
    intro:SetTextColor(0.7, 0.7, 0.7)

    local tip = ("Between %d and %d."):format(Engine.MIN_RESERVES, Engine.MAX_RESERVES)
    f.hard = UI:CreateCounter(f, "Hard reserves per player:", Engine.MIN_RESERVES, Engine.MAX_RESERVES, function(v)
        settings().hardReserves = v
        Addon:Fire("MY_RESERVES_CHANGED") -- planning previews use the defaults
    end, 1, "Hard reserves beat soft reserves. " .. tip)
    f.hard.label:SetPoint("TOPLEFT", 4, -48)
    f.soft = UI:CreateCounter(f, "Soft reserves per player:", Engine.MIN_RESERVES, Engine.MAX_RESERVES, function(v)
        settings().softReserves = v
        Addon:Fire("MY_RESERVES_CHANGED")
    end, 1, "Soft reservers roll against each other. " .. tip)
    f.soft.label:SetPoint("TOPLEFT", 4, -78)

    f.double = UI:CheckButton(f, "Allow double soft reserve", function(v)
        settings().allowDoubleSoft = v
    end, "A player may spend two soft reserves on the same item.")
    f.double:SetPoint("TOPLEFT", 0, -108)
    f.consume = UI:CheckButton(f, "Winning an item uses up that reserve", function(v)
        settings().consumeOnAward = v
    end, "The winner's reserve on the item is removed when you award it.")
    f.consume:SetPoint("TOPLEFT", 0, -134)

    local chanLabel = UI:Label(f, "Announce rolls and awards in:", "GameFontNormal")
    chanLabel:SetPoint("TOPLEFT", 4, -172)
    f.channel = UI:Button(f, "", 130, 22, function()
        Addon.db.announceChannel = Addon.db.announceChannel == "RAID_WARNING" and "RAID" or "RAID_WARNING"
        f:Refresh()
    end, "Click to switch between a raid warning and normal raid chat.")
    f.channel:SetPoint("LEFT", chanLabel, "RIGHT", 8, 0)

    f.timeout = UI:CreateCounter(f, "Roll closes after (seconds, 0 = never):", 0, 120, function(v)
        Addon.db.rollTimeout = v
    end, 5, "How long players have to /roll before the roll closes by itself.")
    f.timeout.label:SetPoint("TOPLEFT", 4, -204)

    -- Unreserved items.
    f.msos = UI:CheckButton(f, "Main spec / off spec rolls on unreserved items", function(v)
        settings().msos = v
    end, "/roll 100 is a main-spec roll, /roll 99 an off-spec roll. Off spec only wins when nobody rolls main spec.")
    f.msos:SetPoint("TOPLEFT", 0, -232)
    f.plusOnes = UI:CheckButton(f, "Plus-ones on unreserved items", function(v)
        settings().plusOnes = v
    end, "A player who has won fewer unreserved items this run beats a higher roll.")
    f.plusOnes:SetPoint("TOPLEFT", 0, -258)

    -- Soft reserve bonus.
    f.bonus = UI:CreateCounter(f, "Soft reserve bonus per earlier run (0 = off):", 0, 50, function(v)
        settings().softBonus = v
    end, 5, "Added to a soft reserve roll for every earlier run of the same raid in which the player "
        .. "soft reserved the item and didn't get it. The streak ends when they win it or skip a run. "
        .. "Uses the loot master's ledger.")
    f.bonus.label:SetPoint("TOPLEFT", 4, -292)
    f.bonusCap = UI:CreateCounter(f, "Most the bonus can reach (0 = no limit):", 0, 100, function(v)
        settings().softBonusCap = v
    end, 5, "Upper limit for the soft reserve bonus.")
    f.bonusCap.label:SetPoint("TOPLEFT", 4, -320)

    -- Where unwanted items go.
    local function nameBox(label, key, y, tip)
        local l = UI:Label(f, label, "GameFontNormal")
        l:SetPoint("TOPLEFT", 4, y)
        local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        eb:SetSize(150, 20)
        eb:SetAutoFocus(false)
        eb:SetPoint("LEFT", l, "RIGHT", 12, 0)
        local function save(self)
            Addon.db[key] = ((self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        end
        eb:SetScript("OnEnterPressed", function(self) save(self) self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", save)
        eb:SetScript("OnEscapePressed", eb.ClearFocus)
        UI.SetTooltip(eb, tip)
        return eb
    end
    f.disenchanter = nameBox("Disenchanter:", "disenchanter", -352,
        "Player unwanted items go to for disenchanting. Empty, or not in the raid: the loot master keeps them.")
    f.banker = nameBox("Guild bank holder:", "banker", -380,
        "Player who holds items for the guild bank. Empty, or not in the raid: the loot master keeps them.")

    f.note = UI:Label(f, "Changes here apply the next time you approve counts for a raid. "
        .. "To change a raid that is already running, use the Roster tab.", "GameFontDisableSmall")
    f.note:SetPoint("TOPLEFT", 4, -412)
    f.note:SetPoint("TOPRIGHT", -4, -412)

    f.Refresh = function(self)
        local d = settings()
        -- Stored values from older versions may be out of range.
        d.hardReserves = Engine.ClampCount(d.hardReserves, Engine.DEFAULT_SETTINGS.hardReserves)
        d.softReserves = Engine.ClampCount(d.softReserves, Engine.DEFAULT_SETTINGS.softReserves)
        self.hard:SetValue(d.hardReserves)
        self.soft:SetValue(d.softReserves)
        self.double:SetChecked(d.allowDoubleSoft and true or false)
        self.consume:SetChecked(d.consumeOnAward and true or false)
        self.channel:SetText(CHANNELS[Addon.db.announceChannel] or CHANNELS.RAID)
        self.timeout:SetValue(Addon.db.rollTimeout or 0)
        self.msos:SetChecked(d.msos and true or false)
        self.plusOnes:SetChecked(d.plusOnes and true or false)
        self.bonus:SetValue(tonumber(d.softBonus) or 0)
        self.bonusCap:SetValue(tonumber(d.softBonusCap) or 0)
        -- Not while the player is typing in them.
        if self.disenchanter:HasFocus() ~= true then self.disenchanter:SetText(Addon.db.disenchanter or "") end
        if self.banker:HasFocus() ~= true then self.banker:SetText(Addon.db.banker or "") end
    end
    return f
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function create(parent)
    local f = CreateFrame("Frame", nil, parent)
    UI.settingsPanel = f
    f.subTabs, f.pages = {}, {}
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, -34)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    f.pages.general = createGeneral(body)
    f.pages.masterloot = createMasterLoot(body)
    for i, tab in ipairs(SUBTABS) do
        local b = UI:Button(f, tab.title, 110, 22, function()
            currentSub = tab.key
            f:Refresh()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * 114, -2)
        f.subTabs[tab.key] = b
        f.pages[tab.key]:SetAllPoints(body)
    end
    f.Refresh = function(self)
        for _, tab in ipairs(SUBTABS) do
            local page, button = self.pages[tab.key], self.subTabs[tab.key]
            if tab.key == currentSub then
                button:LockHighlight()
                page:Show()
                page:Refresh()
            else
                button:UnlockHighlight()
                page:Hide()
            end
        end
    end
    return f
end

-- Open the settings on a sub-tab ("general" / "masterloot").
function UI:ShowSettings(sub)
    if sub == "general" or sub == "masterloot" then currentSub = sub end
    UI:ShowMain("settings")
end

UI:RegisterPanel("settings", {
    title = "Settings",
    tooltip = "Addon settings, including your Master Loot defaults.",
    create = create,
})
