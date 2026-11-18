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
Engine.MODE_OFFSPEC = "OS"     -- how an award is recorded when an off-spec roll won an open item

Engine.KIND = { HARD = "hard", SOFT = "soft" }

Engine.DEFAULT_SETTINGS = {
    hardReserves = 1,              -- hard reserves per player
    softReserves = 3,              -- soft reserves per player
    restrictedMinQuality = 5,      -- legendary and above are restricted
    allowDoubleSoft = false,      -- may a player spend 2 SRs on the same item
    consumeOnAward = true,         -- winning an item removes that reserve
    msos = true,                   -- unreserved items: /roll 100 main spec beats /roll 99 off spec
    plusOnes = false,              -- unreserved items: fewer items won this run beats a higher roll
    softBonus = 0,                 -- added to a soft reserve roll per earlier run reserved without winning (0 = off)
    softBonusCap = 30,             -- most that bonus can reach
}

Engine.OS_ROLL = 99 -- /roll 99 = off spec

-- Reserves per player the raid leader may approve (hard and soft alike).
Engine.MIN_RESERVES = 1
Engine.MAX_RESERVES = 10

-- Whole number in MIN_RESERVES..MAX_RESERVES; `default` when n isn't a number.
function Engine.ClampCount(n, default)
    n = tonumber(n)
    if not n then return default end
    n = math.floor(n)
    if n < Engine.MIN_RESERVES then return Engine.MIN_RESERVES end
    if n > Engine.MAX_RESERVES then return Engine.MAX_RESERVES end
    return n
end

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
    s.approved = false -- raid leader approved the counts for raidKey
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
    local record = { itemID = itemID, player = player, mode = mode, time = timestamp }
    table.insert(self.awards, record)
    if self.settings.consumeOnAward then
        local r = self.reserves[player]
        if r then
            if removeFirst(r.hard, itemID) then
                record.consumed = Engine.KIND.HARD
            elseif removeFirst(r.soft, itemID) then
                record.consumed = Engine.KIND.SOFT
            end
        end
    end
    return record
end

-- Undo the latest award of an item to a player: the record goes and the
-- reserve it used up comes back (at the top). Returns the record or nil.
function Session:RevertAward(itemID, player)
    for i = #self.awards, 1, -1 do
        local a = self.awards[i]
        if a.itemID == itemID and a.player == player then
            table.remove(self.awards, i)
            if a.consumed then
                local r = self:GetPlayer(player, true)
                table.insert(r[a.consumed], 1, itemID)
            end
            return a
        end
    end
end

-- [player] = unreserved items won this run (the "+1" count).
function Session:PlusOnes()
    local out = {}
    for _, a in ipairs(self.awards) do
        if a.mode == Engine.MODE.OPEN and a.player then out[a.player] = (out[a.player] or 0) + 1 end
    end
    return out
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
    flag("msos", "Main spec / off spec rolls")
    flag("plusOnes", "Plus-ones")
    num("softBonus", "Soft reserve bonus")
    if (old.restrictedMinQuality or 5) ~= (new.restrictedMinQuality or 5) then
        out[#out + 1] = "Restricted quality changed"
    end
    return out
end

---------------------------------------------------------------------------
-- Gear slots: the catalogue lists a boss's loot grouped by slot, with
-- everything that isn't equippable gear under "Misc / Quest" at the end.
---------------------------------------------------------------------------
Engine.MISC_SLOT = "Misc / Quest"
Engine.SLOT_ORDER = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger", "Trinket", "Weapon", "Off-hand", "Ranged",
    Engine.MISC_SLOT,
}

local SLOT_OF = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CLOAK = "Back", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
    INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "Weapon", INVTYPE_2HWEAPON = "Weapon",
    INVTYPE_WEAPONMAINHAND = "Weapon", INVTYPE_WEAPONOFFHAND = "Weapon",
    INVTYPE_SHIELD = "Off-hand", INVTYPE_HOLDABLE = "Off-hand",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged",
}

function Engine.SlotGroup(equipLoc)
    return SLOT_OF[equipLoc or ""] or Engine.MISC_SLOT
end

-- Flat list for the loot view: { header = "Head", count = 2 }, { itemID = 1 },
-- { itemID = 2 }, { header = "Feet", ... }. Groups follow SLOT_ORDER; items
-- keep their order within a group. equipLocOf(itemID) may return nil.
function Engine.GroupBySlot(items, equipLocOf)
    local groups = {}
    for _, id in ipairs(items or {}) do
        local g = Engine.SlotGroup(equipLocOf and equipLocOf(id) or nil)
        groups[g] = groups[g] or {}
        table.insert(groups[g], id)
    end
    local rows = {}
    for _, name in ipairs(Engine.SLOT_ORDER) do
        local list = groups[name]
        if list then
            rows[#rows + 1] = { header = name, count = #list }
            for _, id in ipairs(list) do rows[#rows + 1] = { itemID = id } end
        end
    end
    return rows
end

---------------------------------------------------------------------------
-- Roster inventory: where a raid member stands for the raid leader.
---------------------------------------------------------------------------
Engine.STATUS = {
    NOADDON = "noaddon", -- never heard from their client
    EMPTY   = "empty",   -- has the addon, no active reserves
    PARTIAL = "partial", -- fewer active reserves than the approved counts
    READY   = "ready",
}

-- How many more hard / soft reserves a player could still use.
function Engine.Shortfall(nHard, nSoft, settings)
    return math.max(0, (settings.hardReserves or 0) - (nHard or 0)),
        math.max(0, (settings.softReserves or 0) - (nSoft or 0))
end

-- reserve = { hard = {...}, soft = {...} } or nil. Anyone who sent reserves
-- has the addon, whatever hasAddon says.
function Engine.MemberStatus(hasAddon, reserve, settings)
    local h = reserve and #(reserve.hard or {}) or 0
    local s = reserve and #(reserve.soft or {}) or 0
    if h + s == 0 then
        if not hasAddon and not reserve then return Engine.STATUS.NOADDON end
        return Engine.STATUS.EMPTY
    end
    if h < (settings.hardReserves or 0) or s < (settings.softReserves or 0) then
        return Engine.STATUS.PARTIAL
    end
    return Engine.STATUS.READY
end

---------------------------------------------------------------------------
-- Raid stats (per character, per raid): boss kills in the current lockout
-- and how many times the raid has been cleared.
---------------------------------------------------------------------------
local LOCKOUT_FALLBACK = 7 * 24 * 60 * 60 -- when the real reset time is unknown

function Engine.NewStats()
    return { clears = 0, kills = 0, killed = {} }
end

-- Without a known reset time a lockout is taken to last a week from its
-- first kill (not the latest one, or weekly raiding would never roll over).
local function lockoutExpired(stats, now)
    if stats.resetAt then return now >= stats.resetAt end
    local start = stats.lockStart or stats.lastKill
    return start ~= nil and now - start >= LOCKOUT_FALLBACK
end

local function rollLockout(stats, now)
    if lockoutExpired(stats, now) then
        stats.killed, stats.cleared, stats.resetAt, stats.lockStart = {}, false, nil, nil
    end
end

local function killedCount(stats)
    local n = 0
    for _ in pairs(stats.killed or {}) do n = n + 1 end
    return n
end

-- Count a clear once per lockout. resetAt (optional) is when the lockout ends.
function Engine.MarkCleared(stats, now, resetAt)
    rollLockout(stats, now)
    if resetAt then stats.resetAt = resetAt end
    if not stats.cleared then
        stats.clears = (stats.clears or 0) + 1
        stats.cleared = true
    end
end

-- total = number of bosses in the raid, 0 when unknown (then a clear is only
-- counted through MarkCleared, from the game's own lockout data).
function Engine.RecordKill(stats, boss, total, now)
    rollLockout(stats, now)
    stats.killed = stats.killed or {}
    if not stats.lockStart then stats.lockStart = now end
    if not stats.killed[boss] then
        stats.killed[boss] = true
        stats.kills = (stats.kills or 0) + 1
    end
    stats.lastKill = now
    if (total or 0) > 0 and killedCount(stats) >= total then
        Engine.MarkCleared(stats, now)
    end
end

-- Bosses killed in the current lockout (0 once it has reset).
function Engine.Progress(stats, now)
    if lockoutExpired(stats, now) then return 0 end
    return killedCount(stats)
end

---------------------------------------------------------------------------
-- Loot ledger: every raid run with the addon, what dropped and who got it.
--   ledger = { nextId = n, runs = { run, ... } }            oldest first
--   run    = { id, raidKey, raidName, leader, started, updated, entries }
--   entry  = { dropId, itemID, link, boss, time, winner, mode, awardedAt,
--              rolls = { {name=, value=}, ... } }
---------------------------------------------------------------------------
Engine.LEDGER_MAX_RUNS = 200
Engine.LEDGER_RUN_GAP = 12 * 60 * 60 -- quiet time after which the same raid is a new run

-- The run that loot at `now` belongs to (created when needed).
function Engine.LedgerRun(ledger, raidKey, raidName, leader, now)
    ledger.runs = ledger.runs or {}
    local last = ledger.runs[#ledger.runs]
    if last and last.raidKey == raidKey and now - (last.updated or last.started) < Engine.LEDGER_RUN_GAP then
        return last
    end
    local run = {
        id = ledger.nextId or 1, raidKey = raidKey, raidName = raidName, leader = leader,
        started = now, updated = now, entries = {},
    }
    ledger.nextId = run.id + 1
    table.insert(ledger.runs, run)
    while #ledger.runs > Engine.LEDGER_MAX_RUNS do table.remove(ledger.runs, 1) end
    return run
end

local function ledgerFind(run, dropId, itemID)
    for _, e in ipairs(run.entries) do
        if e.dropId == dropId and e.itemID == itemID then return e end
    end
end

-- An item dropped. Recording the same drop twice returns the first entry.
function Engine.LedgerDrop(run, dropId, itemID, link, boss, now)
    local e = ledgerFind(run, dropId, itemID)
    if e then return e end
    e = { dropId = dropId, itemID = itemID, link = link, boss = boss, time = now }
    table.insert(run.entries, e)
    run.updated = now
    return e
end

-- The raid leader handed an item out. Matches the drop by id, else the first
-- copy of the item nobody has yet, else records a new entry.
function Engine.LedgerAward(run, dropId, itemID, winner, mode, now, rolls)
    local e = ledgerFind(run, dropId, itemID)
    -- The same award arriving again (the loot master repeats awards the raid
    -- leader may have missed) changes nothing.
    if e and e.winner == winner then return e end
    if not e or e.winner then
        e = nil
        for _, cand in ipairs(run.entries) do
            if cand.itemID == itemID and not cand.winner then e = cand break end
        end
    end
    if not e then
        e = { dropId = dropId, itemID = itemID, time = now }
        table.insert(run.entries, e)
    end
    e.winner, e.mode, e.awardedAt, e.rolls = winner, mode, now, rolls
    run.updated = now
    return e
end

-- Take back a drop that was added by mistake. Awarded items stay.
function Engine.LedgerRemove(run, dropId, itemID)
    for i, e in ipairs(run.entries) do
        if e.dropId == dropId and e.itemID == itemID and not e.winner then
            table.remove(run.entries, i)
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Ledger sync: a run as text (to send to guild mates), merging a received
-- run into the local ledger, and clean-up / copies for backups.
--   run text  = header ~ entry ~ entry ...
--   header    = uid,raidKey,raidName,started,updated,leader,guild
--   entry     = dropId,itemID,time,boss,winner,mode,awardedAt,rolls
--   rolls     = name:value/name:value
-- Run ids use ";" between leader and start time so they survive cleaning.
---------------------------------------------------------------------------
local function cleanField(v)
    if v == nil then return "" end
    return (tostring(v):gsub("[,~%^/:|]", " "))
end

local function splitKeep(str, sep)
    local out = {}
    for part in (str .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return out
end

local function optional(v)
    if v ~= "" then return v end
end

function Engine.EncodeRun(run)
    local parts = { table.concat({
        cleanField(run.uid), cleanField(run.raidKey), cleanField(run.raidName), cleanField(run.started),
        cleanField(run.updated or run.started), cleanField(run.leader), cleanField(run.guild),
    }, ",") }
    for _, e in ipairs(run.entries or {}) do
        local rolls = {}
        for _, r in ipairs(e.rolls or {}) do rolls[#rolls + 1] = cleanField(r.name) .. ":" .. cleanField(r.value) end
        parts[#parts + 1] = table.concat({
            cleanField(e.dropId), cleanField(e.itemID), cleanField(e.time), cleanField(e.boss),
            cleanField(e.winner), cleanField(e.mode), cleanField(e.awardedAt), table.concat(rolls, "/"),
        }, ",")
    end
    return table.concat(parts, "~")
end

-- Returns a run table, or nil when the text is damaged.
function Engine.DecodeRun(text)
    if type(text) ~= "string" or text == "" then return nil end
    local parts = splitKeep(text, "~")
    local h = splitKeep(parts[1], ",")
    if #h ~= 7 or h[1] == "" or h[2] == "" or not tonumber(h[4]) then return nil end
    local run = {
        uid = h[1], raidKey = h[2], raidName = optional(h[3]), started = tonumber(h[4]),
        updated = tonumber(h[5]) or tonumber(h[4]), leader = optional(h[6]), guild = optional(h[7]), entries = {},
    }
    for i = 2, #parts do
        local f = splitKeep(parts[i], ",")
        local itemID = tonumber(f[2])
        if #f ~= 8 or not itemID then return nil end
        local e = {
            dropId = tonumber(f[1]), itemID = itemID, time = tonumber(f[3]), boss = optional(f[4]),
            winner = optional(f[5]), mode = optional(f[6]), awardedAt = tonumber(f[7]),
        }
        if f[8] ~= "" then
            e.rolls = {}
            for name, value in f[8]:gmatch("([^/:]+):(%d+)") do
                e.rolls[#e.rolls + 1] = { name = name, value = tonumber(value) }
            end
        end
        run.entries[#run.entries + 1] = e
    end
    return run
end

-- Small order-sensitive checksum to catch a damaged or incomplete transfer.
function Engine.Checksum(text)
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + text:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

-- "Name-Realm" -> "Name"
function Engine.ShortName(name)
    return name and (name:gsub("%-.*$", "")) or nil
end

function Engine.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Engine.DeepCopy(x) end
    return out
end

-- Merge a run received from its raid leader. What was recorded locally is
-- never overwritten: missing drops are added and missing winners filled in.
-- Returns entriesAdded, entriesUpdated.
function Engine.MergeRun(ledger, incoming, from)
    ledger.runs = ledger.runs or {}
    local mine
    for _, run in ipairs(ledger.runs) do
        if run.uid and run.uid == incoming.uid then mine = run break end
    end
    if not mine then
        -- A local record of the same raid that never learned the shared id.
        for _, run in ipairs(ledger.runs) do
            if not run.uid and run.raidKey == incoming.raidKey
                and Engine.ShortName(run.leader) == Engine.ShortName(incoming.leader)
                and math.abs((run.started or 0) - (incoming.started or 0)) < Engine.LEDGER_RUN_GAP then
                mine = run
                break
            end
        end
    end
    if not mine then
        local run = Engine.DeepCopy(incoming)
        run.id = ledger.nextId or 1
        ledger.nextId = run.id + 1
        run.syncedFrom = from
        local at = #ledger.runs + 1
        for i, other in ipairs(ledger.runs) do
            if (other.started or 0) > (run.started or 0) then at = i break end
        end
        table.insert(ledger.runs, at, run)
        while #ledger.runs > Engine.LEDGER_MAX_RUNS do table.remove(ledger.runs, 1) end
        return #run.entries, 0
    end
    mine.uid, mine.guild = incoming.uid, mine.guild or incoming.guild
    local added, updated = 0, 0
    for _, inc in ipairs(incoming.entries) do
        local e = ledgerFind(mine, inc.dropId, inc.itemID)
        if not e then
            table.insert(mine.entries, Engine.DeepCopy(inc))
            added = added + 1
        elseif not e.winner and inc.winner then
            e.winner, e.mode, e.awardedAt, e.rolls = inc.winner, inc.mode, inc.awardedAt, Engine.DeepCopy(inc.rolls)
            e.boss = e.boss or inc.boss
            updated = updated + 1
        end
    end
    if added + updated > 0 then
        mine.syncedFrom = from
        mine.updated = math.max(mine.updated or 0, incoming.updated or 0)
    end
    return added, updated
end

-- Remove records that can't be used (damaged saved data). Returns how many
-- runs / entries were dropped.
function Engine.LedgerSanitize(ledger)
    local dropped = 0
    if type(ledger.runs) ~= "table" then ledger.runs = {} end
    local runs = {}
    for _, run in ipairs(ledger.runs) do
        if type(run) == "table" and type(run.entries) == "table" and run.raidKey ~= nil and tonumber(run.started) then
            local entries = {}
            for _, e in ipairs(run.entries) do
                if type(e) == "table" and type(e.itemID) == "number" then
                    entries[#entries + 1] = e
                else
                    dropped = dropped + 1
                end
            end
            run.entries = entries
            runs[#runs + 1] = run
        else
            dropped = dropped + 1
        end
    end
    ledger.runs = runs
    return dropped
end

---------------------------------------------------------------------------
-- Rules behind the loot-master extras: undoing awards in the ledger, the
-- soft reserve bonus, the reserve change log, reserve imports, sharing a
-- list as text, and which armor a class can wear.
---------------------------------------------------------------------------

-- Take an award back out of a ledger run (the drop stays, unawarded).
function Engine.LedgerUnaward(run, dropId, itemID)
    local e = ledgerFind(run, dropId, itemID)
    if not e or not e.winner then return false end
    e.winner, e.mode, e.awardedAt, e.rolls, e.traded = nil, nil, nil, nil, nil
    return true
end

-- Remember who had which items soft reserved in a run (add-only, so a
-- reserve that was used up by winning still counts as "was reserved").
--   run.sr = { [player] = { [itemID] = true } }
function Engine.LedgerNoteReserves(run, reserves)
    run.sr = run.sr or {}
    for player, r in pairs(reserves or {}) do
        for _, itemID in ipairs(r.soft or {}) do
            run.sr[player] = run.sr[player] or {}
            run.sr[player][itemID] = true
        end
    end
end

-- Soft reserve bonus: perRun for every earlier run of the same raid in which
-- the player had the item soft reserved and did not get it, counting back
-- from the most recent run and stopping at the first run where they won it
-- or didn't reserve it. Capped at `cap` (0 / nil = no cap).
function Engine.SoftBonus(ledger, raidKey, player, itemID, currentRun, perRun, cap)
    if not perRun or perRun <= 0 then return 0 end
    local streak = 0
    local runs = ledger.runs or {}
    for i = #runs, 1, -1 do
        local run = runs[i]
        if run ~= currentRun and run.raidKey == raidKey then
            local reserved = run.sr and run.sr[player] and run.sr[player][itemID]
            if not reserved then break end
            local won = false
            for _, e in ipairs(run.entries or {}) do
                if e.itemID == itemID and e.winner == player then won = true break end
            end
            if won then break end
            streak = streak + 1
        end
    end
    local bonus = streak * perRun
    if cap and cap > 0 and bonus > cap then bonus = cap end
    return bonus
end

-- Items in `new` that weren't in `old`, and the other way round.
function Engine.DiffSets(old, new)
    local function counts(list)
        local c = {}
        for _, id in ipairs(list or {}) do c[id] = (c[id] or 0) + 1 end
        return c
    end
    local co, cn = counts(old), counts(new)
    local added, removed = {}, {}
    for _, id in ipairs(new or {}) do
        if (co[id] or 0) < cn[id] then
            added[#added + 1] = id
            co[id] = (co[id] or 0) + 1
        end
    end
    co = counts(old)
    for _, id in ipairs(old or {}) do
        if (cn[id] or 0) < co[id] then
            removed[#removed + 1] = id
            cn[id] = (cn[id] or 0) + 1
        end
    end
    return added, removed
end

-- Reserves pasted by the raid leader for players without the addon.
-- One reserve per line, either
--   Name, itemID-or-link, HR|SR        (SR when the third field is missing)
-- or a softres.it style CSV export (a header line naming "ItemId" and "Name"
-- columns; every row is a soft reserve).
-- Returns { [name] = { hard = {...}, soft = {...} } }, linesRead, linesSkipped.
function Engine.ParseReserveImport(text)
    local players, read, skipped = {}, 0, 0
    local spelled = {} -- [lowercase name] = spelling first seen
    local idCol, nameCol
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
        if line:match("%S") then
            -- Split on , ; or tab, keeping separators inside "quoted fields".
            local fields, cur, quoted = {}, {}, false
            for i = 1, #line do
                local c = line:sub(i, i)
                if c == '"' then
                    quoted = not quoted
                elseif not quoted and (c == "," or c == ";" or c == "\t") then
                    fields[#fields + 1] = table.concat(cur)
                    cur = {}
                else
                    cur[#cur + 1] = c
                end
            end
            fields[#fields + 1] = table.concat(cur)
            for i, f in ipairs(fields) do fields[i] = (f:gsub("^%s+", ""):gsub("%s+$", "")) end
            local header = false
            if not idCol then
                for i, f in ipairs(fields) do
                    local key = f:lower():gsub("%s", "")
                    if key == "itemid" then idCol, header = i, true end
                    if key == "name" then nameCol = i end
                end
                if header and not nameCol then idCol = nil end
            end
            if not header then
                local name, itemID, kind
                if idCol then
                    name, itemID, kind = fields[nameCol], tonumber(fields[idCol]), Engine.KIND.SOFT
                else
                    name = fields[1]
                    itemID = Engine.ItemIDFromLink(fields[2]) or tonumber((line:match("item:(%d+)")))
                    local k = (fields[3] or ""):lower()
                    kind = (k == "hr" or k == "hard") and Engine.KIND.HARD or Engine.KIND.SOFT
                end
                if name and name ~= "" and itemID then
                    -- "ann" and "Ann" are the same player.
                    local key = spelled[name:lower()] or name
                    spelled[name:lower()] = key
                    name = key
                    players[name] = players[name] or { hard = {}, soft = {} }
                    table.insert(players[name][kind], itemID)
                    read = read + 1
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    return players, read, skipped
end

-- A player's lists for one raid as a line of text (copy between characters,
-- paste to a friend): "IDWLC1!MC!16800,16829!16805".
function Engine.EncodeWishlist(raidKey, wish)
    return table.concat({ "IDWLC1", tostring(raidKey), Engine.JoinIDs(wish.hard or {}), Engine.JoinIDs(wish.soft or {}) }, "!")
end

-- Returns raidKey, hard, soft - or nil when the text isn't a list.
function Engine.DecodeWishlist(text)
    local key, h, s = tostring(text or ""):match("IDWLC1!([^!%s]+)!([%d,]*)!([%d,]*)")
    if not key then return nil end
    return key, Engine.SplitIDs(h), Engine.SplitIDs(s)
end

-- Armor a class can never wear (cloth < leather < mail < plate, shields).
-- classID / subclassID as returned by GetItemInfoInstant: 4 = Armor;
-- 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield. Cloaks are cloth for
-- everyone. Anything else (weapons, trinkets, tokens) is not judged.
local ARMOR_RANK = {
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
}
local SHIELD_USERS = { WARRIOR = true, PALADIN = true, SHAMAN = true }

function Engine.CanClassWear(classFile, classID, subclassID)
    if classID ~= 4 or not classFile then return true end
    if subclassID == 6 then return SHIELD_USERS[classFile] == true end
    if subclassID and subclassID >= 1 and subclassID <= 4 then
        local rank = ARMOR_RANK[classFile]
        return rank == nil or subclassID <= rank
    end
    return true
end

---------------------------------------------------------------------------
-- Roll tracking for a single item
---------------------------------------------------------------------------
local Roll = {}
Roll.__index = Roll
Engine.Roll = Roll

-- decision: result of Session:Resolve, optionally with
--   bonus = { [name] = n }   added to that player's roll (soft reserve bonus)
--   plus  = { [name] = n }   unreserved items won this run; fewer wins first
-- opts: { min = 1, max = 100, osMax = 99 }  osMax: /roll <osMax> is an
--   off-spec roll, which only wins when nobody rolled main spec.
function Engine.NewRoll(decision, opts)
    opts = opts or {}
    local r = setmetatable({}, Roll)
    r.decision = decision
    r.min = opts.min or 1
    r.max = opts.max or 100
    r.osMax = opts.osMax
    r.bonus = decision.bonus or {}
    r.plus = decision.plus
    r.rolls = {}      -- [name] = value
    r.tiers = {}      -- [name] = 1 (main spec) | 2 (off spec)
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
    local tier
    if low == self.min and high == self.max then
        tier = 1
    elseif self.osMax and low == self.min and high == self.osMax then
        tier = 2
    else
        return ignore(("wrong range (%d-%d)"):format(low or -1, high or -1))
    end
    if not self:IsEligible(name) then return ignore("not eligible") end
    if self.rolls[name] then return ignore("already rolled") end
    self.rolls[name] = value
    self.tiers[name] = tier
    table.insert(self.order, name)
    return true
end

function Roll:Close()
    self.open = false
end

-- Sorted standings, best first:
--   { name=, value= (as rolled), bonus=, total=, tier=, plus= }
-- Main spec before off spec, then (with plus-ones) fewest items won, then
-- highest total; ties keep roll order.
function Roll:Standings()
    local out = {}
    for i, name in ipairs(self.order) do
        local bonus = self.bonus[name] or 0
        out[#out + 1] = {
            name = name, value = self.rolls[name], bonus = bonus, total = self.rolls[name] + bonus,
            tier = self.tiers[name] or 1, plus = self.plus and (self.plus[name] or 0) or 0, idx = i,
        }
    end
    table.sort(out, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.plus ~= b.plus then return a.plus < b.plus end
        if a.total ~= b.total then return a.total > b.total end
        return a.idx < b.idx
    end)
    return out
end

-- Returns winnerName or nil, plus list of tied names when there is a tie for first.
function Roll:Winner()
    -- Single hard reserver needs no roll.
    if self.decision.mode == Engine.MODE.HARD and self.decision.eligible and #self.decision.eligible == 1 then
        return self.decision.eligible[1], nil
    end
    local s = self:Standings()
    if #s == 0 then return nil, nil end
    local top = s[1]
    local tied = {}
    for _, e in ipairs(s) do
        if e.tier == top.tier and e.plus == top.plus and e.total == top.total then table.insert(tied, e.name) end
    end
    if #tied > 1 then return nil, tied end
    return top.name, nil
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

-- Fields after raidKey were added later; older clients ignore them.
function Engine.EncodeSettings(settings, locked, raidKey, lootMaster)
    return table.concat({
        settings.hardReserves,
        settings.softReserves,
        settings.restrictedMinQuality,
        settings.allowDoubleSoft and 1 or 0,
        settings.consumeOnAward and 1 or 0,
        locked and 1 or 0,
        raidKey or "",
        settings.msos and 1 or 0,
        settings.plusOnes and 1 or 0,
        settings.softBonus or 0,
        settings.softBonusCap or 0,
        lootMaster or "",
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
    if parts[8] ~= nil and parts[8] ~= "" then
        settings.msos = parts[8] == "1"
        settings.plusOnes = parts[9] == "1"
        settings.softBonus = tonumber(parts[10]) or 0
        settings.softBonusCap = tonumber(parts[11]) or 0
    end
    local lootMaster = (parts[12] ~= nil and parts[12] ~= "") and parts[12] or nil
    return settings, locked, raidKey, lootMaster
end

return Engine
