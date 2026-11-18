-- WoW Forever raids (patch 1.60, first raid tier unlocks Dec 9, 2026).
--
-- Instance IDs and loot tables were not published at the time of writing, so:
--   * raids are matched by instance NAME (instanceNames) and the real
--     instance ID is learned the first time the leader zones in;
--   * bosses lists start empty and every epic+ item that drops is learned
--     into the reserve browser automatically ("Seen in raid").
-- When loot tables are known, fill in `bosses` exactly like Data/Raids.lua.
--
-- Roadmap (announced, unnamed): two new raids in spring 2027, a revamped
-- "iconic" raid plus another new raid in summer 2027. Add them here.

local _, ns = ...
ns = ns or {}
ns.RaidData = ns.RaidData or {}
local RD = ns.RaidData
RD.foreverRaids = RD.foreverRaids or {}

local function add(raid)
    raid.expansion = "forever"
    raid.bosses = raid.bosses or {}
    table.insert(RD.foreverRaids, raid)
end

add({
    key = "F_BARROW",
    name = "Barrow Deeps",
    size = 10,
    instanceIDs = {},
    instanceNames = { "Barrow Deeps" },
})

add({
    key = "F_HYJAL",
    name = "Hyjal Summit",
    size = 20,
    instanceIDs = {},
    instanceNames = { "Hyjal Summit" },
})

-- Until the Forever loot table is known, offer the Classic Onyxia loot
-- (shown with a "(classic)" tag) so players have something to reserve.
add({
    key = "F_ONY",
    name = "Onyxia's Lair (Forever)",
    size = 40,
    instanceIDs = {},
    instanceNames = { "Onyxia's Lair" },
    lootFrom = "ONY",
})

return RD
