-- NostalgiaForeverLC - Main window
-- One window for everything a raider does: a row of tabs across the top and
-- one panel per tab underneath. Panels register themselves (RaidList,
-- RosterPanel, SettingsPanel) and are created the first time they are shown.
--
--   Raids     home screen: raid cards -> a raid's boss / loot catalogue
--   Roster    raid leader only, in a raid group: who has picked, reminders
--   Settings  General / Master Loot

local _, ns = ...
local Addon, UI = ns.Addon, ns.UI

local WIDTH, HEIGHT = 840, 720
local TAB_W, TAB_H = 110, 22
local MARGIN = 12
local CONTENT_TOP = 62

local frame
local order, defs = {}, {} -- registered panels
local current = "raids"

-- def = { title = "Raids", create = function(parent) -> frame with :Refresh(),
--         visible = function() -> bool (optional; default always) }
function UI:RegisterPanel(key, def)
    def.key = key
    defs[key] = def
    order[#order + 1] = key
end

local function isVisible(def)
    return def.visible == nil or def.visible() == true
end

local function refresh(self)
    if not (defs[current] and isVisible(defs[current])) then current = "raids" end
    local x = MARGIN
    for _, key in ipairs(order) do
        local def = defs[key]
        local tab = self.tabs[key]
        if isVisible(def) then
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", x, -32)
            tab:Show()
            if key == current then tab:LockHighlight() else tab:UnlockHighlight() end
            x = x + TAB_W + 4
        else
            tab:Hide()
        end
        if key == current then
            if not def.frame then
                def.frame = def.create(self.content)
                def.frame:SetAllPoints(self.content)
            end
            def.frame:Show()
            def.frame:Refresh()
        elseif def.frame then
            def.frame:Hide()
        end
    end
end

local function create()
    local f = UI:CreateWindow("Main", "Nostalgia Forever LC", WIDTH, HEIGHT, nil, "MEDIUM")
    frame = f
    f.Refresh = refresh

    f.tabs = {}
    for _, key in ipairs(order) do
        local def = defs[key]
        f.tabs[key] = UI:Button(f, def.title, TAB_W, TAB_H, function()
            current = key
            f:Refresh()
        end, def.tooltip)
    end

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", MARGIN, -(CONTENT_TOP - 4))
    line:SetPoint("TOPRIGHT", -MARGIN, -(CONTENT_TOP - 4))
    line:SetColorTexture(0.6, 0.6, 0.6, 0.4)

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", MARGIN, -CONTENT_TOP)
    f.content:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
    return f
end

-- Show the window on a tab (default: the tab last used).
function UI:ShowMain(key)
    local f = frame or create()
    if key and defs[key] then current = key end
    if f:IsShown() then f:Refresh() else f:Show() end
end

function UI:ToggleMain()
    local f = frame or create()
    if f:IsShown() then f:Hide() else f:Show() end
end

function UI:CurrentTab()
    return current
end

-- Open a raid's catalogue / back to the raid cards.
function UI:OpenRaid(raidKey)
    UI.raidViewKey = raidKey
    UI:ShowMain("raids")
end

function UI:ShowRaidList()
    UI.raidViewKey = nil
    UI:ShowMain("raids")
end

---------------------------------------------------------------------------
-- "Label  [-] n [+]" number control shared by the settings and the approval
-- prompt. onChange(value) fires on user clicks only.
---------------------------------------------------------------------------
function UI:CreateCounter(parent, label, min, max, onChange, step, tooltip)
    step = step or 1
    local c = { min = min, max = max, value = min }
    c.label = UI:Label(parent, label, "GameFontNormal")
    c.minus = UI:Button(parent, "-", 22, 20, nil, tooltip)
    c.minus:SetPoint("LEFT", c.label, "RIGHT", 8, 0)
    c.text = UI:Label(parent, tostring(min), "GameFontHighlight")
    c.text:SetJustifyH("CENTER")
    c.text:SetWidth(30)
    c.text:SetPoint("LEFT", c.minus, "RIGHT", 2, 0)
    c.plus = UI:Button(parent, "+", 22, 20, nil, tooltip)
    c.plus:SetPoint("LEFT", c.text, "RIGHT", 2, 0)

    function c:SetValue(v)
        v = math.max(self.min, math.min(self.max, tonumber(v) or self.min))
        self.value = v
        self.text:SetText(tostring(v))
        self.minus:SetEnabled(v > self.min)
        self.plus:SetEnabled(v < self.max)
    end

    function c:GetValue()
        return self.value
    end

    local function bump(delta)
        local old = c.value
        c:SetValue(old + delta)
        if c.value ~= old and onChange then onChange(c.value) end
    end
    c.minus:SetScript("OnClick", function() bump(-step) end)
    c.plus:SetScript("OnClick", function() bump(step) end)
    c:SetValue(min)
    return c
end
