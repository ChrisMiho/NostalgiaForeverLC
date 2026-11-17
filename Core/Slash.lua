-- IDontWannaLC - Slash commands
local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine

local HELP = {
    "|cffffd100/idwlc|r - open the reserve window",
    "|cffffd100/idwlc hr <item>|r / |cffffd100sr <item>|r - toggle a hard / soft reserve (shift-click an item)",
    "|cffffd100/idwlc list|r - show reserves in chat",
    "|cffffd100/idwlc status|r - show raid settings and your reserves left",
    "Raid leader:",
    "|cffffd100/idwlc leader|r - leader panel (settings, all reserves)",
    "|cffffd100/idwlc loot|r - loot session window",
    "|cffffd100/idwlc set <hard> <soft>|r - reserves per player",
    "|cffffd100/idwlc lock|r / |cffffd100unlock|r - lock reserves",
    "|cffffd100/idwlc raid <key>|r - set the raid (keys: see /idwlc raids)",
    "|cffffd100/idwlc add <item>|r - add an item to the loot session",
    "|cffffd100/idwlc reset|r - clear all reserves",
    "|cffffd100/idwlc sync|r - re-broadcast settings and reserves",
}

local function itemArg(rest)
    local id = Engine.ItemIDFromLink(rest)
    if not id then Addon:Print("Shift-click an item or give an item ID.") end
    return id
end

local function requireLeader()
    if not Addon:IsLeader() then
        Addon:Print("Only the raid leader can do that.")
        return false
    end
    return true
end

local commands = {}

commands[""] = function() if ns.UI and ns.UI.ToggleReserve then ns.UI:ToggleReserve() end end
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
    local h, so = s:Remaining(Addon:PlayerName())
    local mh, ms = ns.Reserves:GetMine()
    Addon:Print("Raid: %s | HR %d, SR %d per player | %s",
        ns.RaidDataAPI:GetName(s.raidKey), s.settings.hardReserves, s.settings.softReserves,
        s.locked and "|cffff5555LOCKED|r" or "|cff55ff55open|r")
    Addon:Print("Your picks: %d hard, %d soft (leader has you at %d/%d left)", #mh, #ms, h, so)
end

commands.raids = function()
    for _, r in ipairs(ns.RaidDataAPI:GetChoices()) do
        Addon:Print("%s - %s", r.key, r.name)
    end
end

commands.leader = function() if ns.UI and ns.UI.ToggleLeader then ns.UI:ToggleLeader() end end
commands.loot = function() if ns.UI and ns.UI.ToggleLoot then ns.UI:ToggleLoot() end end

commands.set = function(rest)
    if not requireLeader() then return end
    local h, s = rest:match("^(%d+)%s+(%d+)$")
    if not h then Addon:Print("Usage: /idwlc set <hard> <soft>") return end
    ns.Reserves:LeaderSetCounts(tonumber(h), tonumber(s))
    Addon:Print("Reserves per player: %s hard, %s soft.", h, s)
end

commands.lock = function() if requireLeader() then ns.Reserves:LeaderSetLocked(true) end end
commands.unlock = function() if requireLeader() then ns.Reserves:LeaderSetLocked(false) end end

commands.raid = function(rest)
    if not requireLeader() then return end
    if not ns.RaidDataAPI:Get(rest) and not (Addon.db.learnedLoot[rest]) then
        Addon:Print("Unknown raid key %s. See /idwlc raids.", rest)
        return
    end
    ns.Reserves:LeaderSetRaid(rest)
    Addon:Print("Raid set to %s.", ns.RaidDataAPI:GetName(rest))
end

commands.add = function(rest)
    if ns.Loot:AddManual(rest) and ns.UI and ns.UI.ShowLoot then ns.UI:ShowLoot() end
end

commands.reset = function()
    if requireLeader() and ns.Reserves:LeaderReset() then Addon:Print("All reserves cleared.") end
end

commands.sync = function()
    if Addon:IsLeader() then
        ns.Comm:SendConfig()
        ns.Comm:SendSync()
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
