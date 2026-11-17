-- IDontWannaLC - Engine
-- Pure loot-rules logic. No WoW API calls in this file so it can be unit
-- tested outside the game (see tests/). Everything WoW-specific lives in the
-- other Core/ files and calls into this module.

local _, ns = ...
ns = ns or {}

local Engine = {}
ns.Engine = Engine

-- Item quality constants (match Enum.ItemQuality)
Engine.QUALITY = {
    POOR = 0, COMMON = 1, UNCOMMON = 2, RARE = 3, EPIC = 4,
    LEGENDARY = 5, ARTIFACT = 6, HEIRLOOM = 7,
}

-- Loot modes produced by Resolve()
Engine.MODE = {
    RESTRICTED = "RESTRICTED", -- legendary+ : no rolls, raid leader decides
    HARD       = "HARD",       -- hard reserved : holder(s) get it
    SOFT       = "SOFT",       -- soft reserved : only SR holders may roll
    OPEN       = "OPEN",       -- nobody reserved : open roll for everyone
}

Engine.KIND = { HARD = "hard", SOFT = "soft" }

Engine.DEFAULT_SETTINGS = {
    hardReserves = 1,              -- hard reserves per player
    softReserves = 2,              -- soft reserves per player
    restrictedMinQuality = 5,      -- legendary and above are restricted
    allowDoubleSoft = false,      -- may a player spend 2 SRs on the same item
    consumeOnAward = true,         -- winning an item removes that reserve
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function count(list, value)
    local n = 0
    for i = 1, #list do
        if list[i] == value then n = n + 1 end
    end
    return n
end

local function removeFirst(list, value)
    for i = 1, #list do
        if list[i] == value then
            table.remove(list, i)
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Session: settings + everyone's reserves + award history
---------------------------------------------------------------------------
local Session = {}
Session.__index = Session
Engine.Session = Session

function Engine.NewSession(settings)
    local s = setmetatable({}, Session)
    s.settings = copy(Engine.DEFAULT_SETTINGS)
    for k, v in pairs(settings or {}) do s.settings[k] = v end
    s.reserves = {}  -- [player] = { hard = {itemID...}, soft = {itemID...} }
    s.awards = {}    -- { {itemID=, player=, mode=, time=} ... }
    s.locked = false
    s.raidKey = nil
    return s
end

function Session:SetSettings(settings)
    for k, v in pairs(settings) do self.settings[k] = v end
end

function Session:SetLocked(locked)
    self.locked = locked and true or false
end

function Session:IsRestricted(quality)
    return quality ~= nil and quality >= self.settings.restrictedMinQuality
end

function Session:GetPlayer(player, create)
    local r = self.reserves[player]
    if not r and create then
        r = { hard = {}, soft = {} }
        self.reserves[player] = r
    end
    return r
end

function Session:Remaining(player)
    local r = self.reserves[player]
    local usedH = r and #r.hard or 0
    local usedS = r and #r.soft or 0
    return self.settings.hardReserves - usedH, self.settings.softReserves - usedS
end

-- Validate a reserve without applying it. Returns ok, errorMessage.
-- `quality` may be nil if unknown (item not cached); restriction is then
-- re-checked when the item actually drops.
function Session:CanReserve(player, itemID, kind, quality, ignoreLock)
    if not player or player == "" then return false, "no player" end
    if type(itemID) ~= "number" then return false, "invalid item" end
    if kind ~= Engine.KIND.HARD and kind ~= Engine.KIND.SOFT then
        return false, "invalid reserve type"
    end
    if self.locked and not ignoreLock then
        return false, "reserves are locked"
    end
    if self:IsRestricted(quality) then
        return false, "item is restricted (legendary or higher)"
    end
    local r = self.reserves[player] or { hard = {}, soft = {} }
    local list = r[kind]
    local limit = kind == Engine.KIND.HARD and self.settings.hardReserves or self.settings.softReserves
    if #list >= limit then
        return false, ("no %s reserves left (%d max)"):format(kind, limit)
    end
    if kind == Engine.KIND.HARD then
        -- Several players may hard reserve the same item; they roll among
        -- themselves when it drops and soft reserves on it are ignored.
        if contains(r.hard, itemID) then return false, "already hard reserved" end
    else
        if contains(r.hard, itemID) then return false, "already hard reserved by you" end
        if contains(r.soft, itemID) and not self.settings.allowDoubleSoft then
            return false, "already soft reserved"
        end
    end
    return true
end

function Session:AddReserve(player, itemID, kind, quality, ignoreLock)
    local ok, err = self:CanReserve(player, itemID, kind, quality, ignoreLock)
    if not ok then return false, err end
    local r = self:GetPlayer(player, true)
    table.insert(r[kind], itemID)
    return true
end

function Session:RemoveReserve(player, itemID, kind, ignoreLock)
    if self.locked and not ignoreLock then return false, "reserves are locked" end
    local r = self.reserves[player]
    if not r then return false, "no reserves" end
    if not removeFirst(r[kind] or {}, itemID) then return false, "not reserved" end
    return true
end

function Session:ClearPlayer(player)
    self.reserves[player] = nil
end

-- Replace a player's whole reserve set (used when a player syncs their
-- list to the raid leader). Applies each entry through the normal rules and
-- returns a list of rejected entries {itemID=, kind=, reason=}.
function Session:ReplacePlayer(player, hard, soft, qualityLookup, ignoreLock)
    if self.locked and not ignoreLock then
        return false, { { reason = "reserves are locked" } }
    end
    self.reserves[player] = { hard = {}, soft = {} }
    local rejected = {}
    local function apply(list, kind)
        for _, itemID in ipairs(list or {}) do
            local q = qualityLookup and qualityLookup(itemID) or nil
            local ok, err = self:AddReserve(player, itemID, kind, q, ignoreLock)
            if not ok then
                table.insert(rejected, { itemID = itemID, kind = kind, reason = err })
            end
        end
    end
    apply(hard, Engine.KIND.HARD)
    apply(soft, Engine.KIND.SOFT)
    return true, rejected
end

-- All reservers of an item. Soft list may contain a name twice when
-- allowDoubleSoft is on (that player gets two entries / a bonus).
function Session:GetReservers(itemID)
    local hard, soft = {}, {}
    for name, r in pairs(self.reserves) do
        if contains(r.hard, itemID) then table.insert(hard, name) end
        for _ = 1, count(r.soft, itemID) do table.insert(soft, name) end
    end
    table.sort(hard)
    table.sort(soft)
    return hard, soft
end

-- Decide how an item that just dropped is handled.
-- Returns { mode=, itemID=, eligible = {names} | nil (nil = everyone),
--           hard = {names}, soft = {names}, softCount = {[name]=n} }
function Session:Resolve(itemID, quality)
    local hard, soft = self:GetReservers(itemID)
    local decision = { itemID = itemID, hard = hard, soft = soft }

    if self:IsRestricted(quality) then
        decision.mode = Engine.MODE.RESTRICTED
        decision.eligible = {}
        return decision
    end

    -- Any hard reserve takes precedence: soft reservers are shut out and only
    -- the hard reservers roll (a single hard reserver gets it without a roll).
    if #hard > 0 then
        decision.mode = Engine.MODE.HARD
        decision.eligible = hard
        return decision
    end

    if #soft > 0 then
        decision.mode = Engine.MODE.SOFT
        local unique, seen, softCount = {}, {}, {}
        for _, name in ipairs(soft) do
            softCount[name] = (softCount[name] or 0) + 1
            if not seen[name] then
                seen[name] = true
                table.insert(unique, name)
            end
        end
        decision.eligible = unique
        decision.softCount = softCount
        return decision
    end

    decision.mode = Engine.MODE.OPEN
    decision.eligible = nil
    return decision
end

-- Record that the raid leader handed an item out. Consumes the winner's
-- reserve on that item (hard first, then soft) when consumeOnAward is set.
function Session:RecordAward(itemID, player, mode, timestamp)
    table.insert(self.awards, { itemID = itemID, player = player, mode = mode, time = timestamp })
    if self.settings.consumeOnAward then
        local r = self.reserves[player]
        if r then
            if not removeFirst(r.hard, itemID) then
                removeFirst(r.soft, itemID)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tiered wishlists
-- Players keep an ordered priority list of hard and soft picks per raid
-- (longer than the slots they may get). When they join a raid, the top
-- N entries that fit the raid leader's slot counts become their reserves;
-- the rest wait on standby and move up if slots open.
---------------------------------------------------------------------------
Engine.MAX_WISHLIST = 10 -- entries per list (hard / soft) per raid

-- wish = { hard = {itemID...}, soft = {itemID...} } in priority order.
-- Returns selectedHard, selectedSoft, standbyHard, standbySoft.
-- Restricted items (when quality is known) and duplicates are skipped; an
-- item already selected as a hard reserve is never also used as a soft one.
function Engine.SelectFromWishlist(wish, settings, qualityLookup)
    local hard, soft, standbyH, standbyS = {}, {}, {}, {}
    local minQ = settings.restrictedMinQuality or Engine.DEFAULT_SETTINGS.restrictedMinQuality
    local function restricted(id)
        local q = qualityLookup and qualityLookup(id) or nil
        return q ~= nil and q >= minQ
    end
    local inHard = {}
    for _, id in ipairs(wish and wish.hard or {}) do
        if not restricted(id) and not inHard[id] then
            if #hard < (settings.hardReserves or 0) then
                hard[#hard + 1] = id
                inHard[id] = true
            else
                standbyH[#standbyH + 1] = id
            end
        end
    end
    local softCount = {}
    for _, id in ipairs(wish and wish.soft or {}) do
        local dupOk = settings.allowDoubleSoft and (softCount[id] or 0) < 2
        if not restricted(id) and not inHard[id] and (not softCount[id] or dupOk) then
            if #soft < (settings.softReserves or 0) then
                soft[#soft + 1] = id
                softCount[id] = (softCount[id] or 0) + 1
            else
                standbyS[#standbyS + 1] = id
            end
        end
    end
    return hard, soft, standbyH, standbyS
end

-- Human-readable list of what changed between two settings tables.
function Engine.DiffSettings(old, new)
    local out = {}
    local function num(key, label)
        if (old[key] or 0) ~= (new[key] or 0) then
            out[#out + 1] = ("%s %d -> %d"):format(label, old[key] or 0, new[key] or 0)
        end
    end
    local function flag(key, label)
        if (old[key] and true or false) ~= (new[key] and true or false) then
            out[#out + 1] = ("%s %s"):format(label, new[key] and "on" or "off")
        end
    end
    num("hardReserves", "Hard reserves")
    num("softReserves", "Soft reserves")
    flag("allowDoubleSoft", "Double soft reserve")
    flag("consumeOnAward", "Consume on award")
    if (old.restrictedMinQuality or 5) ~= (new.restrictedMinQuality or 5) then
        out[#out + 1] = "Restricted quality changed"
    end
    return out
end

---------------------------------------------------------------------------
-- Roll tracking for a single item
---------------------------------------------------------------------------
local Roll = {}
Roll.__index = Roll
Engine.Roll = Roll

-- decision: result of Session:Resolve
-- opts: { min = 1, max = 100 }
function Engine.NewRoll(decision, opts)
    opts = opts or {}
    local r = setmetatable({}, Roll)
    r.decision = decision
    r.min = opts.min or 1
    r.max = opts.max or 100
    r.rolls = {}      -- [name] = value
    r.order = {}      -- names in the order they rolled
    r.ignored = {}    -- { {name=, value=, reason=} }
    r.open = true
    if decision.eligible then
        r.eligibleSet = {}
        for _, name in ipairs(decision.eligible) do r.eligibleSet[name] = true end
    end
    return r
end

function Roll:IsEligible(name)
    if self.decision.mode == Engine.MODE.RESTRICTED then return false end
    if not self.eligibleSet then return true end
    return self.eligibleSet[name] == true
end

-- Returns accepted(bool), reason
function Roll:Record(name, value, low, high)
    local function ignore(reason)
        table.insert(self.ignored, { name = name, value = value, reason = reason })
        return false, reason
    end
    if not self.open then return ignore("roll closed") end
    if low ~= self.min or high ~= self.max then
        return ignore(("wrong range (%d-%d)"):format(low or -1, high or -1))
    end
    if not self:IsEligible(name) then return ignore("not eligible") end
    if self.rolls[name] then return ignore("already rolled") end
    self.rolls[name] = value
    table.insert(self.order, name)
    return true
end

function Roll:Close()
    self.open = false
end

-- Sorted standings: { {name=, value=}, ... } highest first; ties keep roll order.
function Roll:Standings()
    local out = {}
    for i, name in ipairs(self.order) do
        out[#out + 1] = { name = name, value = self.rolls[name], idx = i }
    end
    table.sort(out, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.idx < b.idx
    end)
    return out
end

-- Returns winnerName or nil, plus list of tied names when there is a tie for first.
function Roll:Winner()
    -- Single hard reserver needs no roll.
    if self.decision.mode == Engine.MODE.HARD and #self.decision.eligible == 1 then
        return self.decision.eligible[1], nil
    end
    local s = self:Standings()
    if #s == 0 then return nil, nil end
    local top = s[1].value
    local tied = {}
    for _, e in ipairs(s) do
        if e.value == top then table.insert(tied, e.name) end
    end
    if #tied > 1 then return nil, tied end
    return s[1].name, nil
end

-- Names that are eligible but haven't rolled yet (nil when everyone is eligible).
function Roll:Missing()
    if not self.decision.eligible then return nil end
    local out = {}
    for _, name in ipairs(self.decision.eligible) do
        if not self.rolls[name] then table.insert(out, name) end
    end
    return out
end

---------------------------------------------------------------------------
-- Parsing helpers
---------------------------------------------------------------------------

-- Turn a WoW global format string like RANDOM_ROLL_RESULT ("%s rolls %d (%d-%d)")
-- into a Lua pattern with captures. Handles positional args like %1$s.
function Engine.FormatToPattern(fmt)
    -- Escape every magic char (including %), so "%s" becomes "%%s" etc.
    local pattern = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%%%%d%%%$s", "(.-)")
    pattern = pattern:gsub("%%%%%d%%%$d", "(%%d+)")
    pattern = pattern:gsub("%%%%s", "(.-)")
    pattern = pattern:gsub("%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

-- Parse a system roll message. Returns name, value, low, high or nil.
function Engine.ParseRoll(msg, rollPattern)
    local name, value, low, high = msg:match(rollPattern)
    if not name then return nil end
    return name, tonumber(value), tonumber(low), tonumber(high)
end

-- Extract numeric item ID from an item link or "item:1234" string.
function Engine.ItemIDFromLink(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    if id then return tonumber(id) end
    if link:match("^%d+$") then return tonumber(link) end
    return nil
end

---------------------------------------------------------------------------
-- Serialization (compact, addon-message friendly; each line < 255 bytes)
---------------------------------------------------------------------------

local function joinIDs(list)
    local parts = {}
    for i = 1, #list do parts[i] = tostring(list[i]) end
    return table.concat(parts, ",")
end

local function splitIDs(str)
    local out = {}
    if not str or str == "" then return out end
    for id in str:gmatch("%d+") do table.insert(out, tonumber(id)) end
    return out
end

Engine.JoinIDs = joinIDs
Engine.SplitIDs = splitIDs

-- "hard1,hard2;soft1,soft2"
function Engine.EncodeReserveSet(hard, soft)
    return joinIDs(hard or {}) .. ";" .. joinIDs(soft or {})
end

function Engine.DecodeReserveSet(str)
    local h, s = (str or ""):match("^([%d,]*);([%d,]*)$")
    if not h then return nil end
    return splitIDs(h), splitIDs(s)
end

function Engine.EncodeSettings(settings, locked, raidKey)
    return table.concat({
        settings.hardReserves,
        settings.softReserves,
        settings.restrictedMinQuality,
        settings.allowDoubleSoft and 1 or 0,
        settings.consumeOnAward and 1 or 0,
        locked and 1 or 0,
        raidKey or "",
    }, ",")
end

function Engine.DecodeSettings(str)
    local parts = {}
    for p in ((str or "") .. ","):gmatch("([^,]*),") do table.insert(parts, p) end
    if #parts < 6 then return nil end
    local settings = {
        hardReserves = tonumber(parts[1]) or 0,
        softReserves = tonumber(parts[2]) or 0,
        restrictedMinQuality = tonumber(parts[3]) or 5,
        allowDoubleSoft = parts[4] == "1",
        consumeOnAward = parts[5] == "1",
    }
    local locked = parts[6] == "1"
    local raidKey = parts[7] ~= "" and parts[7] or nil
    return settings, locked, raidKey
end

return Engine
