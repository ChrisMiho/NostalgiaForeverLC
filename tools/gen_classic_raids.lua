-- Regenerates Data/Raids.lua from AtlasLootClassic's loot tables.
--
-- Usage (from repo root):
--   luajit tools/gen_classic_raids.lua "<path to AtlasLootClassic_DungeonsAndRaids>/data.lua" > Data/Raids.lua
--
-- AtlasLoot's data.lua is executed in a stubbed environment (no WoW API), so
-- the tables are read exactly as AtlasLoot builds them. Item names come from
-- the comments in the source file.

local SRC = assert(arg[1], "pass the path to AtlasLoot's data.lua")

-- Raids to export, in order: AtlasLoot key -> our key / name / size.
local RAIDS = {
    { al = "MoltenCore",          key = "MC",   name = "Molten Core",         size = 40 },
    { al = "Onyxia",              key = "ONY",  name = "Onyxia's Lair",       size = 40 },
    { al = "BlackwingLair",       key = "BWL",  name = "Blackwing Lair",      size = 40 },
    { al = "Zul'Gurub",           key = "ZG",   name = "Zul'Gurub",           size = 20 },
    { al = "TheRuinsofAhnQiraj",  key = "AQ20", name = "Ruins of Ahn'Qiraj",  size = 20 },
    { al = "TheTempleofAhnQiraj", key = "AQ40", name = "Temple of Ahn'Qiraj", size = 40 },
    { al = "Naxxramas",           key = "NAXX", name = "Naxxramas",           size = 40 },
}

---------------------------------------------------------------------------
-- Item names from source comments: "{ 1, 16800 }, -- Arcanist Boots"
---------------------------------------------------------------------------
local names = {}
local src = assert(io.open(SRC, "r")):read("*a")
for line in src:gmatch("[^\n]+") do
    local comment = line:match("%-%-%s*(.-)%s*$")
    if comment and comment ~= "" then
        for id in line:gmatch("(%d%d%d%d+)") do
            id = tonumber(id)
            names[id] = names[id] or comment
        end
    end
end

---------------------------------------------------------------------------
-- Stub environment
---------------------------------------------------------------------------
local nextDiff = 0
local db = {}
local dataObj = setmetatable({}, { __index = function(_, k)
    if k == "AddDifficulty" then
        return function() nextDiff = nextDiff + 1 return nextDiff end
    end
    return function() return k end -- AddContentType, AddItemTableType, ...
end })
-- data["X"] = {...} stores into db.
local dataProxy = setmetatable({}, {
    __index = dataObj,
    __newindex = function(_, k, v) db[k] = v end,
})

local any -- callable / indexable / concatenable / format-able dummy
any = setmetatable({}, {
    __index = function() return any end,
    __call = function() return any end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
    __tostring = function() return "" end,
})

local AL = setmetatable({}, { __index = function(_, k) return k end })

-- Pretend to be Classic Era with every content phase unlocked.
local CLASSIC = 1
local AtlasLoot = {
    ItemDB = { Add = function() return dataProxy end },
    Locales = AL,
    ReturnForGameVersion = function(...) return (select(1, ...)) end,
    CLASSIC_VERSION_NUM = CLASSIC, BC_VERSION_NUM = 2, WRATH_VERSION_NUM = 3,
    Data = { ContentPhase = { GetActivePhase = function() return 99 end } },
}
local function versionCheck(test)
    return function(_, v, a, b)
        if a == nil and b == nil then return test(CLASSIC, v) end
        if test(CLASSIC, v) then return a end
        return b
    end
end
AtlasLoot.GameVersion_EQ = versionCheck(function(c, v) return c == v end)
AtlasLoot.GameVersion_GE = versionCheck(function(c, v) return c >= v end)
AtlasLoot.GameVersion_GT = versionCheck(function(c, v) return c > v end)
AtlasLoot.GameVersion_LE = versionCheck(function(c, v) return c <= v end)
AtlasLoot.GameVersion_LT = versionCheck(function(c, v) return c < v end)

local env = setmetatable({
    AtlasLoot = AtlasLoot,
    UnitFactionGroup = function() return "Alliance" end,
    FACTION_HORDE = "Horde", FACTION_ALLIANCE = "Alliance",
    ATLASLOOT_IT_HORDE = "horde", ATLASLOOT_IT_ALLIANCE = "alliance",
}, { __index = function(_, k) return _G[k] or any end })
env._G = env
env.getfenv = function() return env end -- data.lua does `local _G = getfenv(0)`

local chunk = assert(loadfile(SRC))
setfenv(chunk, env)
chunk("AtlasLootClassic_DungeonsAndRaids")

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local NORMAL_DIFF = 1 -- first AddDifficulty call in data.lua

local function itemIDs(entry)
    local out = {}
    local list = entry[NORMAL_DIFF]
    if type(list) ~= "table" then return out end
    for _, row in ipairs(list) do
        if type(row) == "table" and row[1] ~= 0 then -- position 0 = hidden
            -- Faction items (Head of Onyxia) have one ID per faction: keep both.
            local candidates = { row[2], row.alliance, row.horde }
            for i = 1, 3 do -- not ipairs: row[2] is nil for faction items
                local id = candidates[i]
                if type(id) == "number" and id > 0 then out[#out + 1] = id end
            end
        end
    end
    return out
end

-- AtlasLoot "extra" pages worth reserving from (real drops). The rest - class
-- books, quest rewards, set summaries, "all bosses" repeats - are skipped.
local KEEP_EXTRA = { ["Trash"] = true, ["High Priest Shared loot"] = true }

local function wanted(boss)
    return type(boss) == "table" and (not boss.ExtraList or KEEP_EXTRA[tostring(boss.name)])
end

local function q(s) return ("%q"):format(s) end

local w = {}
local function p(fmt, ...) w[#w + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

p("-- Classic raid loot tables. GENERATED by tools/gen_classic_raids.lua from")
p("-- AtlasLootClassic's data - do not edit by hand, re-run the generator instead.")
p("local _, ns = ...")
p("ns = ns or {}")
p("ns.RaidData = ns.RaidData or {}")
p("local RD = ns.RaidData")
p("")
p("RD.raids = {")
for _, r in ipairs(RAIDS) do
    local raid = assert(db[r.al], "AtlasLoot has no raid " .. r.al)
    p("  ---------------------------------------------------------------------------")
    p("  -- %s", r.name)
    p("  ---------------------------------------------------------------------------")
    p("  {")
    p("    key = %s,", q(r.key))
    p("    name = %s,", q(r.name))
    p("    expansion = \"classic\",")
    p("    size = %d,", r.size)
    p("    instanceIDs = { %d },", assert(raid.InstanceID, r.al .. " instance id"))
    p("    bosses = {")
    for _, boss in ipairs(raid.items) do
        if wanted(boss) then
            local ids, seen = {}, {}
            for _, id in ipairs(itemIDs(boss)) do
                if not seen[id] then seen[id] = true ids[#ids + 1] = id end
            end
            if #ids > 0 then
                p("      { name = %s, items = {", q(tostring(boss.name)))
                for _, id in ipairs(ids) do
                    p("        %d, -- %s", id, names[id] or "?")
                end
                p("      } },")
            end
        end
    end
    p("    },")
    p("  },")
end
p("}")
p("")
p("return RD")

io.write(table.concat(w, "\n"), "\n")
