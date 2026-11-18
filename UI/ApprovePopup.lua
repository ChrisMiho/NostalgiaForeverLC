-- NostalgiaForeverLC - Approval prompt (raid leader)
-- Shown the first time the raid leader enters a raid (or when they ask for
-- it from the Roster tab): confirm how many hard and soft reserves each
-- player gets. Approving starts the inventory - the rules go to every client
-- silently, everyone's picks come back, and the rules are announced in raid
-- chat. "Later" just closes it; it can be reopened from the Roster tab.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI
local Reserves, RaidData = ns.Reserves, ns.RaidDataAPI

local frame
local pendingKey   -- raid being approved
local queuedKey    -- prompt held back during a boss encounter

local function refresh(self)
    local s = Addon.session
    local changing = s.approved and s.raidKey == pendingKey
    self.title:SetText(changing and "Change reserve counts" or "Approve reserve counts")
    self.raid:SetText(pendingKey and RaidData:GetName(pendingKey) or "")
    self.approve:SetText(changing and "Apply" or "Approve")
    -- Counts of a locked raid are frozen; a different raid starts fresh.
    self.approve:SetEnabled(pendingKey ~= nil and not (s.locked and s.raidKey == pendingKey))
end

local function create()
    local f = UI:CreateWindow("Approve", "Approve reserve counts", 380, 216, { "TOP", 0, -160 })
    frame = f
    UI.approvePopup = f
    f.Refresh = refresh

    f.raid = UI:Label(f, nil, "GameFontNormalLarge")
    f.raid:SetPoint("TOP", 0, -34)
    local text = UI:Label(f, "How many reserves does each player get in this raid?", "GameFontHighlightSmall")
    text:SetPoint("TOP", 0, -58)

    local tip = ("Between %d and %d."):format(Engine.MIN_RESERVES, Engine.MAX_RESERVES)
    f.hard = UI:CreateCounter(f, "Hard reserves:", Engine.MIN_RESERVES, Engine.MAX_RESERVES, nil, 1, tip)
    f.hard.label:SetPoint("TOPLEFT", 90, -84)
    f.hard.label:SetWidth(110)
    f.soft = UI:CreateCounter(f, "Soft reserves:", Engine.MIN_RESERVES, Engine.MAX_RESERVES, nil, 1, tip)
    f.soft.label:SetPoint("TOPLEFT", 90, -112)
    f.soft.label:SetWidth(110)

    local note = UI:Label(f, "Announced in raid chat. Everyone's picks are then collected automatically; "
        .. "lock reserves from the Roster tab before the first boss.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 16, -142)
    note:SetPoint("TOPRIGHT", -16, -142)
    note:SetJustifyH("CENTER")

    f.approve = UI:Button(f, "Approve", 110, 24, function()
        local key = pendingKey
        if key and Reserves:LeaderApprove(key, f.hard:GetValue(), f.soft:GetValue()) then
            local set = Addon.session.settings
            Addon:Print("Approved for %s: %d hard, %d soft per player.", RaidData:GetName(key),
                set.hardReserves, set.softReserves)
            f:Hide()
            UI:ShowMain("roster")
        end
    end, "Send these counts to the raid and start collecting everyone's reserves.")
    f.approve:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
    f.later = UI:Button(f, "Later", 110, 24, function() f:Hide() end,
        "Close without approving. Reopen from the Roster tab (/nflc roster).")
    f.later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
    return f
end

function UI:ShowApproval(raidKey)
    if not raidKey then return end
    local f = frame or create()
    pendingKey = raidKey
    local s = Addon.session
    local hard, soft
    if s.approved and s.raidKey == raidKey then
        hard, soft = s.settings.hardReserves, s.settings.softReserves
    else
        hard, soft = Reserves:GetProposal(raidKey)
    end
    f.hard:SetValue(hard)
    f.soft:SetValue(soft)
    if f:IsShown() then f:Refresh() else f:Show() end
end

Addon:On("APPROVAL_NEEDED", function(raidKey)
    -- Never pop a window up mid boss fight.
    if Addon.inEncounter then
        queuedKey = raidKey
        return
    end
    UI:ShowApproval(raidKey)
end)

Addon:On("ENCOUNTER_ENDED", function()
    if queuedKey then
        local key = queuedKey
        queuedKey = nil
        if Reserves:IsRaidLeader() then UI:ShowApproval(key) end
    end
end)

-- Lost leadership or left the raid with the prompt open: close it.
Addon:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if frame and frame:IsShown() and not Reserves:IsRaidLeader() then frame:Hide() end
end)
