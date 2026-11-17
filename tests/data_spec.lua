local RD = dofile("Data/Raids.lua")
-- Forever.lua appends to the same namespace table when run in-game; outside
-- the game each file returns its own table, so load it separately.
local FD = dofile("Data/Forever.lua")

local function checkRaid(raid, keys)
    truthy(type(raid.key) == "string" and raid.key ~= "", "raid key")
    falsy(keys[raid.key], "duplicate raid key " .. tostring(raid.key))
    keys[raid.key] = true
    truthy(type(raid.name) == "string", "raid name")
    truthy(type(raid.bosses) == "table", raid.key .. " bosses")
    for _, boss in ipairs(raid.bosses) do
        truthy(type(boss.name) == "string", raid.key .. " boss name")
        local seen = {}
        for _, id in ipairs(boss.items) do
            truthy(type(id) == "number" and id > 0, raid.key .. "/" .. boss.name .. " item id")
            falsy(seen[id], raid.key .. "/" .. boss.name .. " duplicate item " .. id)
            seen[id] = true
        end
    end
end

describe("raid data", function()
    local keys = {}
    it("classic raids are well formed", function()
        eq(#RD.raids, 7)
        for _, raid in ipairs(RD.raids) do
            eq(raid.expansion, "classic")
            truthy(#raid.instanceIDs > 0, raid.key .. " instance id")
            checkRaid(raid, keys)
        end
    end)
    it("forever raids are well formed", function()
        truthy(#FD.foreverRaids >= 3)
        for _, raid in ipairs(FD.foreverRaids) do
            eq(raid.expansion, "forever")
            truthy(#raid.instanceNames > 0, raid.key .. " instance names")
            checkRaid(raid, keys)
        end
    end)
end)
