-- IDontWannaLC - Slash commands
local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine

local HELP = {
    "|cffffd100/idwlc|r - open the addon (raids, your reserve lists, settings)",
    "|cffffd100/idwlc hr <item>|r / |cffffd100sr <item>|r - add/remove an item in your hard / soft tier for the current raid",
    "|cffffd100/idwlc list|r - show reserves in chat",
    "|cffffd100/idwlc loot|r - loot window (drops, who may roll, rolls)",
    "|cffffd100/idwlc ledger|r - past raids: what dropped and who got it",
    "|cffffd100/idwlc status|r - show raid settings and your reserves left",
    "Raid leader:",
    "|cffffd100/idwlc roster|r - who has the addon / has picked (whisper reminders)",
    "|cffffd100/idwlc approve [hard soft]|r - approve reserve counts (1-10) for the raid",
    "|cffffd100/idwlc lock|r / |cffffd100unlock|r - lock reserves (announced in raid)",
    "|cffffd100/idwlc raid <key>|r - start reserves for a raid (keys: see /idwlc raids)",
    "|cffffd100/idwlc add <item>|r - add an item to the loot session",
    "|cffffd100/idwlc reset|r - collect everyone's reserves again",
    "|cffffd100/idwlc sync|r - re-broadcast settings and reserves",
}

local function itemArg(rest)
    local id = Engine.ItemIDFromLink(rest)
    if not id then Addon:Print("Shift-click an item or give an item ID.") end
    return id
end

local function requireLeader()
    if not (IsInRaid() and Addon:IsLeader()) then
        Addon:Print("Only the raid leader of a raid group can do that.")
        return false
    end
    return true
end

local commands = {}

commands[""] = function() if ns.UI and ns.UI.ToggleMain then ns.UI:ToggleMain() end end
commands.help = function() for _, l in ipairs(HELP) do Addon:Print(l) end end

commands.hr = function(rest)
    local id = itemArg(rest)
    if id then ns.Reserves:Toggle(id, Engine.KIND.HARD) end
end

commands.sr = function(rest)
    local id = itemArg(rest)
    if id then ns.Reserves:Toggle(id, Engine.KIND.SOFT) end
end

commands.list = function()
    local text = ns.Reserves:Export()
    if text == "" then Addon:Print("No reserves yet.") return end
    for line in text:gmatch("[^\n]+") do Addon:Print(line) end
end

commands.status = function()
    local s = Addon.session
    if not s.raidKey then
        Addon:Print("No live raid - the raid leader hasn't approved reserve counts yet.")
        return
    end
    Addon:Print("Raid: %s | HR %d, SR %d per player | %s",
        ns.RaidDataAPI:GetName(s.raidKey), s.settings.hardReserves, s.settings.softReserves,
        s.locked and "|cffff5555LOCKED|r" or "|cff55ff55open|r")
    local _, _, sh, ss = ns.Reserves:GetSelection()
    Addon:Print("Your reserves: %s", ns.Reserves:DescribeMine())
    Addon:Print("On standby in your tiers: %d hard, %d soft", #(sh or {}), #(ss or {}))
end

commands.raids = function()
    for _, r in ipairs(ns.RaidDataAPI:GetChoices()) do
        Addon:Print("%s - %s", r.key, r.name)
    end
end

commands.roster = function()
    if not requireLeader() then return end
    if ns.UI and ns.UI.ShowMain then ns.UI:ShowMain("roster") end
end
commands.leader = commands.roster
commands.ledger = function() if ns.UI and ns.UI.ShowMain then ns.UI:ShowMain("ledger") end end
commands.settings = function() if ns.UI and ns.UI.ShowMain then ns.UI:ShowMain("settings") end end
commands.loot = function() if ns.UI and ns.UI.ToggleLoot then ns.UI:ToggleLoot() end end

-- "/idwlc approve" opens the prompt; "/idwlc approve 1 3" approves directly.
commands.approve = function(rest)
    if not requireLeader() then return end
    local h, so = rest:match("^(%d+)%s+(%d+)$")
    if not h then
        if rest ~= "" then Addon:Print("Usage: /idwlc approve [<hard> <soft>]  (1-10 each)") return end
        ns.Reserves:RequestApproval()
        return
    end
    local key = Addon.session.raidKey or (Addon:IsInRaidInstance() and ns.RaidDataAPI:Detect()) or nil
    if not key then Addon:Print("Choose a raid first: /idwlc raid <key>") return end
    if ns.Reserves:LeaderApprove(key, tonumber(h), tonumber(so)) then
        local set = Addon.session.settings
        Addon:Print("Approved for %s: %d hard, %d soft per player.", ns.RaidDataAPI:GetName(key),
            set.hardReserves, set.softReserves)
    end
end
commands.set = commands.approve

commands.lock = function()
    if not requireLeader() then return end
    local n, text = ns.Roster:NotReadySummary()
    if ns.Reserves:LeaderSetLocked(true) and n > 0 then
        Addon:Print("Locked with %d player(s) not ready: %s. /idwlc unlock to let them finish.", n, text)
    end
end
commands.unlock = function() if requireLeader() then ns.Reserves:LeaderSetLocked(false) end end

commands.raid = function(rest)
    if not requireLeader() then return end
    if not ns.RaidDataAPI:Get(rest) and not (Addon.db.learnedLoot[rest]) then
        Addon:Print("Unknown raid key %s. See /idwlc raids.", rest)
        return
    end
    ns.Reserves:RequestApproval(rest)
end

commands.add = function(rest)
    if ns.Loot:AddManual(rest) and ns.UI and ns.UI.ShowLoot then ns.UI:ShowLoot() end
end

commands.reset = function()
    if requireLeader() and ns.Reserves:LeaderReset() then Addon:Print("Reserve list reset; collecting picks again.") end
end

commands.sync = function()
    if IsInRaid() and Addon:IsLeader() then
        if Addon.session.approved then
            ns.Comm:SendConfig()
            ns.Comm:SendSync()
        end
        ns.Comm:SendPing(true)
    else
        ns.Comm:SendHello()
    end
end

commands.debug = function()
    Addon.db.debug = not Addon.db.debug
    Addon:Print("Debug %s.", Addon.db.debug and "on" or "off")
end

SLASH_IDONTWANNALC1 = "/idwlc"
SLASH_IDONTWANNALC2 = "/reserve"
SlashCmdList.IDONTWANNALC = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local fn = commands[cmd] or commands.help
    fn(rest or "")
end
