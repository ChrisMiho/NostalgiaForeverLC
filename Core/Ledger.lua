-- IDontWannaLC - Loot ledger
-- A permanent record (account wide) of every raid run with the addon: what
-- dropped, on which boss, who the raid leader gave it to, how it was decided
-- and the rolls. Every client in the raid keeps its own copy, written as the
-- drops and awards happen. The rules live in Core/Engine.lua (Ledger*).
--
-- Guild sync (manual): "Sync with guild" asks, over the hidden guild addon
-- channel, for the runs guild mates have LED. Only the raid leader of a run
-- hands it out, and a run is only accepted from its own leader, who must be
-- in my guild. So whoever led the raid that week is the single source for
-- it, and anyone who missed the raid can fill the gap. Nothing I recorded
-- myself is overwritten. A backup of the ledger is taken before every sync
-- and can be restored from the Ledger tab.
--
--   LQ                           me -> GUILD      which runs did you lead?
--   LI^uid^started^drops^awarded leader -> me     one per run they led for this guild
--   LR^uid                       me -> leader     send me that run
--   LD^uid^part^total^sum^text   leader -> me     the run, in chunks, with a checksum

local _, ns = ...
local Addon, Engine = ns.Addon, ns.Engine

local Ledger = {}
ns.Ledger = Ledger
Addon.Ledger = Ledger

local MAX_BACKUPS = 5
local OFFER_RUNS = 30    -- most recent led runs offered per query
local CHUNK = 170        -- payload bytes per LD message
local SYNC_WINDOW = 120  -- seconds a sync keeps listening for answers
local QUERY_COOLDOWN = 20

local sync -- { started, requested = {[uid] = sender}, buffers = {[uid] = {...}}, runs, added, updated, from = {} }
local lastQuery = -100
local lastAnswer = {} -- [requester] = GetTime(), so a leader isn't made to resend constantly

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
function Ledger:MyGuild()
    local name = GetGuildInfo and GetGuildInfo("player")
    if name and name ~= "" then return name end
end

-- The run loot belongs to right now (created on first use). uid is the
-- shared id the raid leader gave the run (members learn it with each drop).
local function currentRun(uid)
    local key = Addon.session.raidKey
    if not key and Addon:IsInRaidInstance() then key = ns.RaidDataAPI:Detect() end
    key = key or "?"
    local run = Engine.LedgerRun(Addon.db.ledger, key, ns.RaidDataAPI:GetName(key),
        Addon:GetLeaderName() or Addon:PlayerName(), time())
    if not run.uid then
        if uid and uid ~= "" then
            run.uid = uid
        elseif Addon:IsLeader() or not IsInRaid() then
            -- My run: I am its source for the guild.
            run.uid = Addon:PlayerName() .. ";" .. run.started
            run.guild = Ledger:MyGuild()
        end
    end
    return run
end

-- entry = a loot entry from Core/Loot.lua { id, itemID, link, source }.
-- Returns the run's shared id (the leader sends it along with the drop).
function Ledger:Drop(entry, uid)
    local run = currentRun(uid)
    Engine.LedgerDrop(run, entry.id, entry.itemID,
        entry.link or Addon:GetItemLink(entry.itemID), entry.source, time())
    -- Who had what soft reserved this run (for the soft reserve bonus in
    -- later runs), and the raid leader's log of reserve changes.
    Engine.LedgerNoteReserves(run, Addon.session.reserves)
    if Addon:IsLeader() and #Addon.session.log > 0 then run.changes = Engine.DeepCopy(Addon.session.log) end
    Addon:Fire("LEDGER_CHANGED")
    return run.uid
end

function Ledger:Award(entry, winner, mode)
    local rolls
    if entry.roll then
        rolls = {}
        for _, r in ipairs(entry.roll:Standings()) do rolls[#rolls + 1] = { name = r.name, value = r.value } end
    end
    local e = Engine.LedgerAward(currentRun(), entry.id, entry.itemID, winner, mode, time(), rolls)
    e.link = e.link or entry.link or Addon:GetItemLink(entry.itemID)
    e.boss = e.boss or entry.source
    Addon:Fire("LEDGER_CHANGED")
end

-- The loot master took an award back.
function Ledger:Unaward(entry)
    local runs = Addon.db.ledger.runs
    local run = runs and runs[#runs]
    if run and Engine.LedgerUnaward(run, entry.id, entry.itemID) then Addon:Fire("LEDGER_CHANGED") end
end

-- The item was handed over (or not after all).
function Ledger:SetTraded(entry, traded)
    local runs = Addon.db.ledger.runs
    local run = runs and runs[#runs]
    for _, e in ipairs(run and run.entries or {}) do
        if e.dropId == entry.id and e.itemID == entry.itemID then
            e.traded = traded and true or nil
            Addon:Fire("LEDGER_CHANGED")
            return
        end
    end
end

-- Bonus on a soft reserve roll for the live raid, from my ledger's history
-- (earlier runs of this raid where the player reserved the item and lost).
function Ledger:SoftBonus(player, itemID)
    local set = Addon.session.settings
    if not set.softBonus or set.softBonus <= 0 or not Addon.session.raidKey then return 0 end
    local runs = Addon.db.ledger.runs or {}
    return Engine.SoftBonus(Addon.db.ledger, Addon.session.raidKey, player, itemID, runs[#runs],
        set.softBonus, set.softBonusCap)
end

-- A drop the leader removed again (added by mistake).
function Ledger:Remove(entry)
    local runs = Addon.db.ledger.runs
    local run = runs and runs[#runs]
    if run and Engine.LedgerRemove(run, entry.id, entry.itemID) then Addon:Fire("LEDGER_CHANGED") end
end

-- Runs, newest first.
function Ledger:GetRuns()
    local out = {}
    local runs = Addon.db.ledger.runs or {}
    for i = #runs, 1, -1 do out[#out + 1] = runs[i] end
    return out
end

function Ledger:DeleteRun(run)
    local runs = Addon.db.ledger.runs or {}
    for i, r in ipairs(runs) do
        if r == run then
            table.remove(runs, i)
            Addon:Fire("LEDGER_CHANGED")
            return true
        end
    end
    return false
end

-- Plain text for one run (pasting into Discord, a spreadsheet, ...).
function Ledger:Export(run)
    local lines = { ("%s - %s - led by %s"):format(run.raidName or run.raidKey or "?",
        date("%Y-%m-%d", run.started), run.leader or "?") }
    for _, e in ipairs(run.entries) do
        local name = Addon:GetItemInfo(e.itemID) or (e.link and e.link:match("%[(.-)%]")) or ("item:" .. e.itemID)
        lines[#lines + 1] = ("%s | %s | %s | %s"):format(e.boss or "?", name,
            e.winner or "not awarded", e.mode or "")
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Backups (account wide, newest first)
---------------------------------------------------------------------------
function Ledger:Backup(reason)
    local backups = Addon.db.ledgerBackups
    table.insert(backups, 1, { time = time(), reason = reason, ledger = Engine.DeepCopy(Addon.db.ledger) })
    while #backups > MAX_BACKUPS do table.remove(backups) end
    Addon:Fire("LEDGER_CHANGED")
    return backups[1]
end

function Ledger:GetBackups()
    return Addon.db.ledgerBackups
end

-- Put a backup back. The ledger as it is now is backed up first, so a
-- restore can itself be undone.
function Ledger:Restore(backup)
    if type(backup) ~= "table" or type(backup.ledger) ~= "table" then return false end
    local copy = Engine.DeepCopy(backup.ledger)
    Engine.LedgerSanitize(copy)
    self:Backup("before restore")
    Addon.db.ledger = copy
    sync = nil
    Addon:Fire("LEDGER_CHANGED")
    return true
end

-- Saved data that got damaged: keep a copy of it as it was, then drop the
-- records that can't be read. Runs when the addon loads. Returns how many
-- records were removed.
function Ledger:Repair()
    local db = Addon.db
    if type(db.ledger) ~= "table" then db.ledger = { runs = {} } end
    if type(db.ledgerBackups) ~= "table" then db.ledgerBackups = {} end
    local before = Engine.DeepCopy(db.ledger)
    local dropped = Engine.LedgerSanitize(db.ledger)
    if dropped > 0 then
        table.insert(db.ledgerBackups, 1, { time = time(), reason = "before repair", ledger = before })
        while #db.ledgerBackups > MAX_BACKUPS do table.remove(db.ledgerBackups) end
        Addon:Print("Loot ledger: %d damaged record(s) removed. The ledger as it was is kept under Ledger > Backups.", dropped)
        Addon:Fire("LEDGER_CHANGED")
    end
    return dropped
end

Addon:OnInit(function() Ledger:Repair() end)

---------------------------------------------------------------------------
-- Guild sync
---------------------------------------------------------------------------
-- Is this player in my guild? nil when the guild roster isn't loaded yet.
function Ledger:IsGuildMember(name)
    if not IsInGuild or not IsInGuild() or not GetNumGuildMembers then return false end
    local n = GetNumGuildMembers() or 0
    if n == 0 then return nil end
    local short = Engine.ShortName(name)
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full and (full == name or Engine.ShortName(full) == short) then return true end
    end
    return false
end

local function requestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif _G.GuildRoster then
        _G.GuildRoster()
    end
end

local function awardedCount(run)
    local n = 0
    for _, e in ipairs(run.entries) do
        if e.winner then n = n + 1 end
    end
    return n
end

local function findByUid(uid)
    for _, run in ipairs(Addon.db.ledger.runs or {}) do
        if run.uid == uid then return run end
    end
end

-- Did I lead this run, for the guild I'm in now?
local function ledByMeForGuild(run)
    local guild = Ledger:MyGuild()
    return guild ~= nil and run.uid ~= nil and run.guild == guild
        and Engine.ShortName(run.leader) == Engine.ShortName(Addon:PlayerName())
end

-- What the last / current sync did, for the Ledger tab.
function Ledger:SyncStatus()
    if not sync then return nil end
    local waiting = 0
    for _ in pairs(sync.requested) do waiting = waiting + 1 end
    return {
        active = GetTime() - sync.started < SYNC_WINDOW,
        answers = sync.answers, waiting = waiting,
        runs = sync.runs, added = sync.added, updated = sync.updated, rejected = sync.rejected,
    }
end

-- Manual poll: ask the guild which runs its raid leaders have.
function Ledger:Sync()
    if not self:MyGuild() then
        return false, "You are not in a guild."
    end
    if GetTime() - lastQuery < QUERY_COOLDOWN then
        return false, "Just asked - give the guild a moment to answer."
    end
    lastQuery = GetTime()
    self:Backup("before guild sync")
    requestRoster()
    sync = { started = GetTime(), requested = {}, buffers = {}, answers = 0, runs = 0, added = 0, updated = 0, rejected = 0 }
    ns.Comm:Send("GUILD", nil, "LQ")
    Addon:Fire("LEDGER_CHANGED")
    return true
end

local function syncActive()
    return sync ~= nil and GetTime() - sync.started < SYNC_WINDOW
end

-- Someone in the guild is polling: offer the runs I led.
function Ledger:OnQuery(sender)
    if Addon:IsMe(sender) or not self:MyGuild() then return end
    if lastAnswer[sender] and GetTime() - lastAnswer[sender] < QUERY_COOLDOWN then return end
    if self:IsGuildMember(sender) == false then return end
    lastAnswer[sender] = GetTime()
    local offered = 0
    for _, run in ipairs(self:GetRuns()) do
        if ledByMeForGuild(run) and #run.entries > 0 then
            ns.Comm:Whisper(sender, "LI", run.uid, run.started, #run.entries, awardedCount(run))
            offered = offered + 1
            if offered >= OFFER_RUNS then break end
        end
    end
end

-- A leader offers a run: ask for it when mine is missing or less complete.
function Ledger:OnIndex(sender, uid, started, drops, awarded)
    if not syncActive() or not uid or uid == "" then return end
    if sync.requested[uid] or self:IsGuildMember(sender) == false then return end
    sync.answers = sync.answers + 1
    local mine = findByUid(uid)
    if mine and #mine.entries >= (drops or 0) and awardedCount(mine) >= (awarded or 0) then return end
    sync.requested[uid] = sender
    ns.Comm:Whisper(sender, "LR", uid)
    Addon:Fire("LEDGER_CHANGED")
end

-- A guild mate wants a run I led.
function Ledger:OnRequest(sender, uid)
    local run = uid and findByUid(uid)
    if not run or not ledByMeForGuild(run) then return end
    if self:IsGuildMember(sender) == false then return end
    local text = Engine.EncodeRun(run)
    local sum = Engine.Checksum(text)
    local total = math.max(1, math.ceil(#text / CHUNK))
    for part = 1, total do
        ns.Comm:Whisper(sender, "LD", uid, part, total, sum, text:sub((part - 1) * CHUNK + 1, part * CHUNK))
    end
end

local function reject(uid, why)
    sync.requested[uid], sync.buffers[uid] = nil, nil
    sync.rejected = sync.rejected + 1
    Addon:Debug("ledger sync: run %s rejected (%s)", tostring(uid), why)
    Addon:Fire("LEDGER_CHANGED")
end

-- A chunk of a run I asked for.
function Ledger:OnData(sender, uid, part, total, sum, text)
    if not sync or not uid or sync.requested[uid] ~= sender then return end
    if not (part and total and sum) or part < 1 or part > total then return end
    local buf = sync.buffers[uid]
    if not buf or buf.total ~= total or buf.sum ~= sum then
        buf = { total = total, sum = sum, parts = {} }
        sync.buffers[uid] = buf
    end
    buf.parts[part] = text or ""
    for i = 1, total do
        if buf.parts[i] == nil then return end
    end
    local whole = table.concat(buf.parts)
    if Engine.Checksum(whole) ~= sum then return reject(uid, "checksum") end
    local run = Engine.DecodeRun(whole)
    if not run or run.uid ~= uid then return reject(uid, "unreadable") end
    -- Only the run's own raid leader, and only for my guild.
    if Engine.ShortName(run.leader) ~= Engine.ShortName(sender) then return reject(uid, "not from its raid leader") end
    if run.guild ~= self:MyGuild() then return reject(uid, "another guild") end
    if self:IsGuildMember(sender) ~= true then return reject(uid, "sender not in guild") end
    local added, updated = Engine.MergeRun(Addon.db.ledger, run, sender)
    sync.requested[uid], sync.buffers[uid] = nil, nil
    if added + updated > 0 then
        sync.runs = sync.runs + 1
        sync.added, sync.updated = sync.added + added, sync.updated + updated
        Addon:Print("Ledger: %s (%s) synced from %s - %d new, %d completed.", run.raidName or run.raidKey,
            date("%Y-%m-%d", run.started), sender, added, updated)
    end
    Addon:Fire("LEDGER_CHANGED")
end
