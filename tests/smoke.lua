-- Smoke test: load Core + UI with a permissive WoW mock and exercise the UI.
local ROOT = arg[1]
local timers = {}
local round = 0 -- counts timer rounds, so tests can see what happened per tick
local function runTimers()
    for _ = 1, 5 do
        round = round + 1
        local t = timers; timers = {}
        for _, fn in ipairs(t) do fn() end
    end
end

local frameMT
local function newObj(kind, name)
    local o = { _kind = kind, _shown = kind ~= "Frame_hidden", _scripts = {}, _text = "", _w = 300, _name = name }
    return setmetatable(o, frameMT)
end
local methods = {}
function methods:Show() local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function methods:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:SetScript(k, fn) self._scripts[k] = fn end
function methods:GetScript(k) return self._scripts[k] end
function methods:HookScript(k, fn) local old = self._scripts[k]; self._scripts[k] = function(...) if old then old(...) end fn(...) end end
function methods:CreateTexture() return newObj("Texture") end
function methods:CreateFontString() return newObj("FontString") end
function methods:SetText(t) self._text = t end
function methods:GetText() return self._text end
function methods:GetWidth() return self._w end
function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetVerticalScroll() return 0 end
function methods:GetChecked() return self._checked end
function methods:SetChecked(v) self._checked = v end
function methods:HasFocus() return self._focus end
function methods:SetFocus() self._focus = true end
function methods:ClearFocus() self._focus = false end
function methods:IsMouseOver() return false end
function methods:SetEnabled(v) assert(v == true or v == false, "SetEnabled needs boolean, got " .. tostring(v)); self._enabled = v end
function methods:Click(btn) if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end end
frameMT = { __index = function(t, k)
    if methods[k] then return methods[k] end
    if k == "link" then return nil end -- addon data field on item buttons, nil until set, as in the game
    return function() end
end }

local G = _G
G.CreateFrame = function(kind, name, parent, template)
    local o = newObj(kind, name)
    if kind ~= "ScrollFrame" and kind ~= "EditBox" and kind ~= "CheckButton" and kind ~= "Button" then end
    if name then G[name] = o end
    return o
end
G.UIParent = newObj("Frame")
G.UISpecialFrames = {}
G.tinsert = table.insert
G.C_Timer = {
    After = function(d, fn) if d < 5 then table.insert(timers, fn) end end,
    NewTimer = function(d, fn) local t = { Cancel = function(self) self.c = true end }; if d >= 5 then return t end
        table.insert(timers, function() if not t.c then fn() end end); return t end,
    NewTicker = function() return { Cancel = function() end } end,
}
G.GameTooltip = newObj("GameTooltip")
G.GameTooltip._links, G.GameTooltip._owner, G.GameTooltip._link = 0, false, ""
G.GameTooltip.SetOwner = function(self, owner) self._owner = owner end
G.GameTooltip.GetOwner = function(self) return self._owner end
G.GameTooltip.SetHyperlink = function(self, link) self._links = (self._links or 0) + 1; self._link = link end
G.GameTooltip_Hide = function() end
G.hooksecurefunc = function(a, b, c)
    if type(a) == "string" then local old = G[a]; G[a] = function(...) local r = old(...); b(...); return r end
    else local old = a[b]; a[b] = function(...) local r = old(...); c(...); return r end end
end
G.ChatEdit_InsertLink = function() return false end
local inRaid, leader = true, true
G.IsInRaid = function() return inRaid end
local roster = { { "Me", 2, 1, 60, "Warrior", "WARRIOR" }, { "Bob", 0, 1, 60, "Mage", "MAGE" }, { "Ann-Realm", 0, 1, 60, "Priest", "PRIEST" } }
G.GetNumGroupMembers = function() return #roster end
G.GetRaidRosterInfo = function(i) return unpack(roster[i]) end
G.UnitName = function() return "Me" end
G.UnitClass = function() return "Warrior", "WARRIOR" end
G.UnitIsGroupLeader = function() return leader end
G.UnitIsGroupAssistant = function() return false end
G.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
G.GetBuildInfo = function() return "1.15", "1", "x", 11509 end
G.C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
local notOut = {} -- ids the mock client has never heard of (R8b)
local cache = { [19019] = { "Thunderfury", 5 }, [16800] = { "Arcanist Boots", 4 } }
G.GetItemInfo = function(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
    local c = cache[id]; if not c then return nil end
    return c[1], "|cffa335ee|Hitem:" .. id .. "::::|h[" .. c[1] .. "]|h|r", c[2], 60, 60, "Armor", "Cloth", 1, "INVTYPE_FEET", 12345
end
G.GetItemIcon = function() return 134400 end
local itemRequests = {} -- { id, round } per server request (R8a)
G.C_Item = {
    IsItemDataCachedByID = function(id) return cache[id] ~= nil end,
    RequestLoadItemDataByID = function(id) itemRequests[#itemRequests + 1] = { id = id, round = round } end,
    DoesItemExistByID = function(id) return not notOut[id] end,
}
G.ITEM_QUALITY_COLORS = {}
for q = 0, 7 do G.ITEM_QUALITY_COLORS[q] = { r = 1, g = 0.5, b = 0 } end
G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
G.StaticPopupDialogs = {}
G.StaticPopup_Show = function(n) G.StaticPopupDialogs[n].OnAccept() end
G.YES, G.NO = "Yes", "No"
G.IsModifiedClick = function() return false end
G.IsShiftKeyDown = function() return false end
G.IsMouseButtonDown = function() return false end
local chat = {}
G.SendChatMessage = function(m, c, _, target) table.insert(chat, c .. (target and ("@" .. target) or "") .. ": " .. m) end
G.C_ChatInfo = { SendAddonMessage = function() return 0 end, RegisterAddonMessagePrefix = function() end }
G.GetInstanceInfo = function() return "Molten Core", "raid", 9, "", 40, 0, false, 409 end
G.IsInInstance = function() return true, "raid" end
G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("CHAT", m) end }
G.geterrorhandler = function() return function(e) print("ERROR", e); G.ERRORS = (G.ERRORS or 0) + 1 end end
G.GetTime = os.clock
G.RandomRoll = function() print("RandomRoll") end
G.LOOT_ITEM_SELF = "You receive loot: %s."
G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
G.ChatFontNormal, G.GameFontHighlightSmall = {}, {}
G.SlashCmdList = {}
G.time = os.time

G.date = os.date
-- Equip slots for the fixed Lucifron rows used below (instant item info).
local equip = {
    [16800] = "INVTYPE_FEET", [16829] = "INVTYPE_FEET", [16837] = "INVTYPE_FEET", [16859] = "INVTYPE_FEET",
    [16805] = "INVTYPE_HAND", [16863] = "INVTYPE_HAND", [17109] = "INVTYPE_NECK", [18875] = "INVTYPE_LEGS",
}
local plate = {} -- item ids the mock treats as plate armor
G.GetItemInfoInstant = function(id) return id, "Armor", "Cloth", equip[id] or "", 134400, 4, plate[id] and 4 or 1 end

local ns = {}
local files = {}
for line in io.lines(ROOT .. "/NostalgiaForeverLC.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = (line:gsub("\\", "/")) end
end
for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. "/" .. f))
    chunk("NostalgiaForeverLC", ns)
end
local Addon, UI = ns.Addon, ns.UI
local R, RDA = ns.Reserves, ns.RaidDataAPI
-- Fixed Lucifron rows so the UI checks below don't depend on the order of the
-- generated loot data (Data/Raids.lua is regenerated from AtlasLoot).
assert(ns.RaidData.raids[1].key == "MC" and ns.RaidData.raids[1].bosses[1].name == "Lucifron")
ns.RaidData.raids[1].bosses[1].items = { 16800, 16829, 16837, 16859, 16805, 16863, 17109, 18875 }
local function event(e, ...) Addon.frame._scripts.OnEvent(Addon.frame, e, ...) end
event("ADDON_LOADED", "NostalgiaForeverLC")

local function check(cond, msg)
    if cond then
        print("ok   " .. msg)
    else
        print("ERROR check failed: " .. msg)
        G.ERRORS = (G.ERRORS or 0) + 1
    end
end
check(G.SLASH_NOSTALGIAFOREVERLC1 == "/nflc" and G.SLASH_NOSTALGIAFOREVERLC2 == "/reserve"
    and G.SLASH_NOSTALGIAFOREVERLC3 == "/idwlc" and G.SlashCmdList.NOSTALGIAFOREVERLC, "slash /nflc + aliases registered")
local function has(text, needle) return type(text) == "string" and text:find(needle, 1, true) ~= nil end
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function plain(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function chatHas(needle, from)
    for i = from or 1, #chat do if has(chat[i], needle) then return true end end
    return false
end
-- Rows of a scroll list that currently hold data (pooled rows beyond the data
-- fall through to the mock metatable).
local function liveRows(list)
    local out = {}
    for _, r in ipairs(list.rows) do
        if rawget(r, "data") then out[#out + 1] = r end
    end
    return out
end

---------------------------------------------------------------------------
-- Defaults (PRD R18): 1 hard / 3 soft
---------------------------------------------------------------------------
check(Addon.db.settings.hardReserves == 1 and Addon.db.settings.softReserves == 3, "defaults are 1 HR / 3 SR")
check(Addon.session.approved == false and Addon.session.raidKey == nil, "nothing live before approval")

---------------------------------------------------------------------------
-- Approval prompt (R20-R22): leader, in a raid group, inside Molten Core
---------------------------------------------------------------------------
check(ns.Roster:WhisperText({ status = "empty", name = "Bob" }) == nil
    and has(ns.Roster:WhisperText({ status = "noaddon", name = "Ann" }), "install"),
    "before approval only the install reminder applies")
event("PLAYER_ENTERING_WORLD"); runTimers()
local ap = G.NFLC_Approve
check(ap ~= nil and ap:IsShown(), "leader is prompted on entering the raid")
check(ap.raid._text == "Molten Core" and ap.hard.value == 1 and ap.soft.value == 3, "prompt offers the defaults for the raid")
check(ap.hard.minus._enabled == false, "hard count can't go below 1")
ap.hard.minus:Click()
check(ap.hard.value == 1, "minus at 1 stays at 1")
ap.later:Click()
event("PLAYER_ENTERING_WORLD"); runTimers()
check(not ap:IsShown() and not Addon.session.approved, "dismissed prompt doesn't nag again")
R:RequestApproval(); runTimers()
check(ap:IsShown(), "prompt can be reopened")
ap.soft.plus:Click()
check(ap.soft.value == 4, "soft count adjustable in the prompt")
local chatMark = #chat + 1
ap.approve:Click(); runTimers()
local s = Addon.session
check(s.approved and s.raidKey == "MC" and s.settings.hardReserves == 1 and s.settings.softReserves == 4,
    "approval sets the raid and counts")
check(not ap:IsShown() and G.NFLC_Main:IsShown() and UI:CurrentTab() == "roster", "approval opens the roster tab")
check(chatHas("RAID: [NFLC] Molten Core: 1 hard / 4 soft", chatMark), "approval announced in raid chat")
check(R:HasPreset("MC") and select(2, R:GetProposal("MC")) == 4, "approved counts remembered for the raid")
R:LeaderApprove("MC", 0, 99); runTimers()
check(s.settings.hardReserves == 1 and s.settings.softReserves == 10, "counts clamp to 1-10")
event("PLAYER_LOGOUT")
check(G.NostalgiaForeverLCDB.session.approved == true and G.NostalgiaForeverLCDB.session.raidKey == "MC", "approval survives a reload")
R:LeaderApprove("MC", 1, 2); runTimers()

---------------------------------------------------------------------------
-- Raid cards (R1-R5)
---------------------------------------------------------------------------
UI:ShowRaidList(); runTimers()
local main = G.NFLC_Main
local rl, rf = UI.raidList, UI.raidView
check(rl:IsShown() and not rf:IsShown(), "raids tab opens on the raid cards")
local cards = liveRows(rl.list)
check(#cards == 7, "one card per raid (classic client): " .. #cards)
check(cards[1].data.key == "MC" and has(cards[1].tag._text, "LIVE"), "live raid first and marked LIVE")
check(has(cards[1].info._text, "40 players") and has(cards[1].info._text, "10 bosses")
    and has(cards[1].info._text, "1 HR / 2 SR"), "card info: " .. plain(cards[1].info._text))
check(cards[1].progress._text == "0/10" and has(cards[1].stats._text, "Not cleared yet"), "card starts at 0/10")
check(has(cards[1].picks._text, "No picks yet"), "card shows no picks yet")
event("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1); runTimers()
event("ENCOUNTER_END", 664, "Magmadar", 9, 40, 0); runTimers()
check(cards[1].progress._text == "1/10" and has(cards[1].stats._text, "Last kill"), "boss kill counted, wipe ignored: "
    .. cards[1].progress._text)
for _, boss in ipairs({ "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Golemagg the Incinerator",
    "Sulfuron Harbinger", "Majordomo Executus", "Ragnaros" }) do
    event("ENCOUNTER_END", 1, boss, 9, 40, 1)
end
runTimers()
check(cards[1].progress._text == "10/10" and has(cards[1].stats._text, "Cleared 1 time"), "full clear counted once: "
    .. plain(cards[1].stats._text))
check(cards[2].data.key ~= "MC" and cards[2].tag._text == "", "other raids are not live")

---------------------------------------------------------------------------
-- Catalogue (R6-R16)
---------------------------------------------------------------------------
cards[1]:Click(); runTimers()
check(rf:IsShown() and not rl:IsShown() and rf.title._text == "Molten Core", "clicking a card opens its catalogue")
check(has(rf.raidNote._text, "Live raid"), "live raid note: " .. rf.raidNote._text)

-- R8a: opening the catalogue asks for every uncached item, a few per tick, and retries once.
do
    runTimers(); runTimers(); runTimers(); runTimers(); runTimers(); runTimers()
    local want, perRound, asked = {}, {}, {}
    for _, boss in ipairs(RDA:GetBosses("MC")) do
        for _, id in ipairs(boss.items) do want[id] = true end
    end
    for _, r in ipairs(itemRequests) do
        asked[r.id] = (asked[r.id] or 0) + 1
        perRound[r.round] = (perRound[r.round] or 0) + 1
    end
    local missing, maxRound, extra = 0, 0, 0
    for id in pairs(want) do
        if cache[id] then
            if asked[id] then extra = extra + 1 end
        elseif asked[id] ~= 2 then missing = missing + 1 end
    end
    for _, n in pairs(perRound) do maxRound = math.max(maxRound, n) end
    check(#itemRequests > 0 and missing == 0, "every uncached MC item requested, then retried once (missing " .. missing .. ")")
    check(extra == 0, "cached items are not requested")
    check(maxRound <= UI.PRELOAD_BATCH, "item requests batched: " .. maxRound .. " in one tick")
end
local hardCol, softCol = rf.columns.hard, rf.columns.soft
local function lootDump()
    local out = {}
    for _, r in ipairs(liveRows(rf.itemList)) do
        out[#out + 1] = r.data.header and plain(r.header._text) or tostring(r.itemID)
    end
    return table.concat(out, " ")
end
check(lootDump() == "Neck (1) 17109 Hands (2) 16805 16863 Legs (1) 18875 Feet (4) 16800 16829 16837 16859",
    "loot grouped by gear slot: " .. lootDump())
local function itemRow(id)
    for _, r in ipairs(liveRows(rf.itemList)) do
        if r.itemID == id then return r end
    end
    error("no row for item " .. id)
end
-- R8a: a tooltip opened while the item was still loading is redrawn when it arrives.
do
    local row = itemRow(16805)
    row.item._scripts.OnEnter(row.item)
    local tt = G.GameTooltip
    local before = tt._links
    event("GET_ITEM_INFO_RECEIVED", 99999, true); runTimers()
    check(tt._links == before, "tooltip left alone when another item arrives")
    event("GET_ITEM_INFO_RECEIVED", 16805, true); runTimers()
    check(tt._links == before + 1 and has(tt._link, "item:16805"), "hovered tooltip redrawn when its item arrives")
    row.item._scripts.OnLeave(row.item)
    event("GET_ITEM_INFO_RECEIVED", 16805, true); runTimers()
    check(tt._links == before + 1, "no redraw after the mouse leaves")
end
-- R8b: items the client can't provide are left out, per session.
do
    local function hiddenCount() local _, h = RDA:GetLootRows(RDA:GetBosses("MC")[1]); return h end
    event("GET_ITEM_INFO_RECEIVED", 17109, false); event("GET_ITEM_INFO_RECEIVED", 16863, false); runTimers()
    check(Addon:IsItemUnavailable(17109) and hiddenCount() == 2, "refused items are unavailable (R8b)")
    event("GET_ITEM_INFO_RECEIVED", 16805); runTimers()
    check(not Addon:IsItemUnavailable(16805), "nil success is ignored")
    local before = #itemRequests
    UI.PreloadItems({ 16863, 17109 }); runTimers(); runTimers()
    check(#itemRequests == before, "refused items are not requested again (R8a)")
    notOut[16800] = true
    check(Addon:IsItemUnavailable(16800) and hiddenCount() == 3, "unknown to the client = unavailable")
    local fn = G.C_Item.DoesItemExistByID; G.C_Item.DoesItemExistByID = nil
    check(not Addon:IsItemUnavailable(16800) and Addon:IsItemUnavailable(16863), "no DoesItemExistByID: only refusals count")
    G.C_Item.DoesItemExistByID = fn; notOut[16800] = nil
    event("GET_ITEM_INFO_RECEIVED", 17109, true); event("GET_ITEM_INFO_RECEIVED", 16863, true); runTimers()
    check(hiddenCount() == 0, "availability clears on a later success")
    event("PLAYER_LOGOUT")
    check(not G.NostalgiaForeverLCDB.unavailableItems and not G.NostalgiaForeverLCCharDB.unavailableItems, "unavailable set is not saved")
end
local bosses = liveRows(rf.bossList)
check(#bosses == 11 and has(bosses[1].text._text, "Lucifron"), "boss catalogue listed")
bosses[2]:Click(); runTimers()
check(#liveRows(rf.itemList) > 0 and lootDump():find("Misc / Quest", 1, true) ~= nil, "another boss: ungrouped items under Misc / Quest")
bosses[1]:Click(); runTimers()

itemRow(16800).hr:Click(); runTimers()
itemRow(16829).hr:Click(); runTimers()
itemRow(16837).hr:Click(); runTimers()
itemRow(16859).sr:Click("LeftButton"); runTimers()
itemRow(16805).sr:Click("LeftButton"); runTimers()
itemRow(16863).sr:Click("LeftButton"); runTimers()
local w = R:GetWishlist("MC")
check(same(w.hard, { 16800, 16829, 16837 }) and same(w.soft, { 16859, 16805, 16863 }), "lists filled from item rows")
-- An item can't be on both lists (R11).
itemRow(16800).sr:Click("LeftButton"); runTimers()
check(same(w.soft, { 16859, 16805, 16863 }) and same(w.hard, { 16800, 16829, 16837 }), "SR refused for an item on the HR list")
itemRow(16863).hr:Click(); runTimers()
check(same(w.soft, { 16859, 16805 }) and w.hard[4] == 16863, "HR moves an item off the SR list")
itemRow(16863).hr:Click(); runTimers()
itemRow(16863).sr:Click("LeftButton"); runTimers()
check(same(w.hard, { 16800, 16829, 16837 }) and same(w.soft, { 16859, 16805, 16863 }), "lists restored")
-- Ten per list (R12).
local planKey = "BWL"
for id = 1, 10 do R:Add(900000 + id, "soft", planKey) end
check(#R:GetWishlist(planKey).soft == 10 and R:Add(900011, "soft", planKey) == false, "a list holds at most 10 items")
R:ClearWishlist(planKey)

check(has(itemRow(16829).hr._text, "HR #2") and not has(itemRow(16829).hr._text, "40ff40"), "HR shows rank, standby")
check(has(itemRow(16800).hr._text, "HR #1") and has(itemRow(16800).hr._text, "40ff40"), "HR #1 active")
check(has(itemRow(16805).sr._text, "SR #2"), "SR rank")
local function colDump(col)
    local out = {}
    for _, r in ipairs(liveRows(col.list)) do
        out[#out + 1] = r.data.divider and ("[" .. plain(r.divider._text) .. "]")
            or (r.data.pos .. ":" .. r.item.itemID .. ":" .. plain(r.tag._text))
    end
    return table.concat(out, " ")
end
check(colDump(hardCol) == "1:16800:Active [-- 1 slot --] 2:16829:Standby 3:16837:Standby", "hard column: " .. colDump(hardCol))
check(colDump(softCol) == "1:16859:Active 2:16805:Active [-- 2 slots --] 3:16863:Standby", "soft column: " .. colDump(softCol))
check(has(hardCol.header._text, "3 / 10"), "hard fill count: " .. hardCol.header._text)
check(has(rf.status._text, "1 HR / 2 SR per player") and has(rf.status._text, "3 active") and has(rf.status._text, "3 standby"),
    "status line: " .. rf.status._text)
check(hardCol.list.rows[1].up._enabled == false and hardCol.list.rows[4].down._enabled == false, "arrow ends disabled")
hardCol.list.rows[3].up:Click(); runTimers()
check(colDump(hardCol) == "1:16829:Active [-- 1 slot --] 2:16800:Standby 3:16837:Standby", "move up: " .. colDump(hardCol))
softCol.list.rows[1].down:Click(); runTimers()
check(same(R:GetWishlist("MC").soft, { 16805, 16859, 16863 }), "move down soft")
check(same(s.reserves.Me.hard, { 16829 }) and same(s.reserves.Me.soft, { 16805, 16859 }), "top picks sent as active reserves")
-- Leader changes the counts: Active / Standby follow.
R:LeaderApprove("MC", 2, 1); runTimers()
check(colDump(hardCol) == "1:16829:Active 2:16800:Active [-- 2 slots --] 3:16837:Standby", "counts 2/1 hard column")
check(colDump(softCol) == "1:16805:Active [-- 1 slot --] 2:16859:Standby 3:16863:Standby", "counts 2/1 soft column")
check(has(rf.status._text, "2 HR / 1 SR"), "status after counts: " .. rf.status._text)
R:LeaderApprove("MC", 1, 2); runTimers()
softCol.list.rows[4].remove:Click(); runTimers()
check(same(R:GetWishlist("MC").soft, { 16805, 16859 }), "remove x on soft row")
-- Everyone sees everyone's reserves in the live raid (R16).
s.reserves.Bob = { hard = { 16837 }, soft = { 16829, 16800 } }
Addon:Fire("RESERVES_CHANGED"); runTimers()
check(has(itemRow(16800).sub._text, "Bob"), "others' reserves shown: " .. itemRow(16800).sub._text)
s.reserves.Bob = nil
-- Link box: restricted item.
rf.linkBox:SetFocus(); G.ChatEdit_InsertLink(select(2, G.GetItemInfo(19019))); runTimers()
check(rf.linkHR._shown == false and has(rf.linkStatus._text, "Restricted"), "legendary can't be reserved")

-- Back to the cards, plan another raid ahead of time.
rf.back:Click(); runTimers()
check(rl:IsShown() and not rf:IsShown(), "back button returns to the raid cards")
cards = liveRows(rl.list)
check(has(plain(cards[1].picks._text), "3 HR, 2 SR"), "card shows my picks: " .. plain(cards[1].picks._text))
local otherKey = cards[2].data.key
cards[2]:Click(); runTimers()
check(rf.title._text == RDA:GetName(otherKey) and has(rf.raidNote._text, "Planning ahead"), "planning another raid")
local firstOther = liveRows(rf.itemList)[2]
firstOther.hr:Click(); runTimers()
check(same(R:GetWishlist(otherKey).hard, { firstOther.itemID }), "pick added to browsed raid " .. otherKey)
check(#R:GetWishlist("MC").hard == 3, "live raid list untouched")
check(has(rf.panelTitle._text, RDA:GetName(otherKey)) and has(hardCol.header._text, "1 / 10"), "panel follows browsed raid")
rf.linkBox:SetFocus(); G.ChatEdit_InsertLink(select(2, G.GetItemInfo(16800))); runTimers()
rf.linkSR:Click("LeftButton"); runTimers()
check(same(R:GetWishlist(otherKey).soft, { 16800 }) and has(rf.linkSR._text, "SR #1"), "link box adds to browsed raid")
rf.clearBtn:Click(); runTimers()
local ow = R:GetWishlist(otherKey)
check(#ow.hard == 0 and #ow.soft == 0 and #R:GetWishlist("MC").hard == 3, "clear lists (browsed raid only)")

-- Rules notice: banner + the live raid's catalogue opens.
main:Hide()
Addon:Fire("RULES_NOTICE", "test"); runTimers()
check(main:IsShown() and rf:IsShown() and UI.raidViewKey == "MC" and rf.banner:IsShown() and rf.banner.text._text == "test",
    "rules notice opens the live raid with a banner")
Addon:Fire("RESERVE_REJECTED", 16800, "hard", "test reason"); runTimers()

---------------------------------------------------------------------------
-- Settings: Master Loot (R17-R19)
---------------------------------------------------------------------------
UI:ShowSettings("masterloot"); runTimers()
local ml = UI.settingsPanel.pages.masterloot
check(UI:CurrentTab() == "settings" and ml:IsShown() and not UI.settingsPanel.pages.general:IsShown(), "master loot sub-tab shown")
check(ml.hard.value == 1 and ml.soft.value == 3, "master loot defaults 1 / 3")
ml.hard.minus:Click()
for _ = 1, 12 do ml.soft.plus:Click() end
check(Addon.db.settings.hardReserves == 1 and Addon.db.settings.softReserves == 10 and ml.soft.plus._enabled == false,
    "master loot counts limited to 1-10")
for _ = 1, 7 do ml.soft.minus:Click() end
check(Addon.db.settings.softReserves == 3, "soft default back to 3")
ml.double:SetChecked(true); ml.double:Click()
check(Addon.db.settings.allowDoubleSoft == true, "double soft option saved")
ml.double:SetChecked(false); ml.double:Click()
UI.settingsPanel.subTabs.general:Click(); runTimers()
check(UI.settingsPanel.pages.general:IsShown() and not ml:IsShown(), "general sub-tab")

---------------------------------------------------------------------------
-- Roster tab (R23-R31)
---------------------------------------------------------------------------
event("CHAT_MSG_ADDON", "NFLC", "VER^0.3.0", "RAID", "Bob"); runTimers()
check(ns.Comm.versions.Bob == "0.3.0", "version report recorded")
UI:ShowMain("roster"); runTimers()
local rp = UI.rosterPanel
check(main.tabs.roster._shown and rp:IsShown(), "leader sees the roster tab")
local function rosterDump()
    local out = {}
    for _, r in ipairs(liveRows(rp.list)) do
        out[#out + 1] = r.data.name .. "=" .. r.data.status
    end
    return table.concat(out, " ")
end
check(rosterDump() == "Ann=noaddon Bob=empty Me=ready", "roster states: " .. rosterDump())
check(has(plain(rp.summary._text), "1 of 3 ready"), "roster summary: " .. plain(rp.summary._text))
local annRow = liveRows(rp.list)[1]
check(annRow.whisper._shown and liveRows(rp.list)[3].whisper._shown == false, "whisper button only for players who need it")
chatMark = #chat + 1
annRow.whisper:Click(); runTimers()
check(chatHas("WHISPER@Ann-Realm: [NFLC]", chatMark) and chatHas("install", chatMark), "no-addon whisper sent to the player")
check(ns.Roster:Whisper(annRow.data) == false and liveRows(rp.list)[1].whisper._enabled == false, "whispers are throttled")
chatMark = #chat + 1
rp.whisperAll:Click(); runTimers()
check(chatHas("WHISPER@Bob: [NFLC] You have no reserves set", chatMark) and not chatHas("WHISPER@Ann", chatMark),
    "whisper all reaches the rest once")
-- Bob's client sends an incomplete set, then a full one.
event("CHAT_MSG_ADDON", "NFLC", "SET^MC^16837;16829", "RAID", "Bob"); runTimers()
check(rosterDump() == "Ann=noaddon Bob=partial Me=ready", "incomplete picks flagged: " .. rosterDump())
check(has(liveRows(rp.list)[2].counts._text, "HR 1/1") and has(liveRows(rp.list)[2].counts._text, "SR 1/2"), "roster shows counts")
event("CHAT_MSG_ADDON", "NFLC", "SET^MC^16837;16829,16800", "RAID", "Bob"); runTimers()
check(rosterDump() == "Ann=noaddon Bob=ready Me=ready", "complete picks ready: " .. rosterDump())
check(R.LeaderRemove == nil, "leader has no way to edit another player's reserves")
-- Lock / unlock, both announced. Locking with players not ready asks first.
local notReady, notReadyText = ns.Roster:NotReadySummary()
check(notReady == 1 and notReadyText == "1 without the addon", "not-ready summary: " .. tostring(notReadyText))
local popupText
local realPopup = G.StaticPopup_Show
G.StaticPopup_Show = function(name, arg) popupText = name .. ": " .. tostring(arg) return realPopup(name, arg) end
chatMark = #chat + 1
rp.lock:Click(); runTimers()
check(s.locked and chatHas("RAID: [NFLC] Reserves for Molten Core are now LOCKED", chatMark), "lock announced in raid chat")
check(has(popupText, "NFLC_LOCK_ANYWAY") and has(popupText, "1 player(s) not ready: 1 without the addon"),
    "leader is asked before locking with players not ready")
G.StaticPopup_Show = realPopup
check(has(liveRows(rp.list)[2].version._text, "0.3.0") and has(liveRows(rp.list)[2].version._text, "differs"),
    "a different addon version is flagged")
check(rp.lock._text == "Unlock reserves" and rp.approve._enabled == false, "locked: unlock offered, counts frozen")
check(R:Add(17109, "soft", "MC") == false, "lists can't change while locked")
chatMark = #chat + 1
rp.lock:Click(); runTimers()
check(not s.locked and chatHas("UNLOCKED", chatMark), "unlock announced in raid chat")
rp.export:Click(); print("export:", G.NFLC_TextDialog.text)
-- A player who joins after the lock still gets a first set in, but can't change it.
R:LeaderSetLocked(true); runTimers()
event("CHAT_MSG_ADDON", "NFLC", "SET^MC^17109;", "RAID", "Ann-Realm"); runTimers()
check(s.reserves.Ann and s.reserves.Ann.hard[1] == 17109, "late joiner's first set accepted while locked")
event("CHAT_MSG_ADDON", "NFLC", "SET^MC^18875;", "RAID", "Ann-Realm"); runTimers()
check(s.reserves.Ann.hard[1] == 17109, "no changes while locked")
R:LeaderSetLocked(false); runTimers()
-- Reserves of players who left the raid are dropped.
s.reserves.Gone = { hard = { 16800 }, soft = {} }
event("GROUP_ROSTER_UPDATE"); runTimers()
check(s.reserves.Gone == nil and s.reserves.Bob ~= nil, "departed player's reserves pruned")
-- Approving a different raid while locked starts a fresh, unlocked list.
R:LeaderSetLocked(true); runTimers()
check(R:LeaderApprove("MC", 3, 3) == false, "counts frozen while locked")
check(R:LeaderApprove("BWL", 1, 3) == true and s.raidKey == "BWL" and not s.locked and s.reserves.Bob == nil,
    "a different raid starts fresh and unlocked")
R:LeaderApprove("MC", 1, 2); runTimers()
event("CHAT_MSG_ADDON", "NFLC", "SET^MC^16837;16829,16800", "RAID", "Bob"); runTimers()

---------------------------------------------------------------------------
-- Loot window, rolls and the ledger (R32-R40) - as raid leader
---------------------------------------------------------------------------
local Loot, Ledger = ns.Loot, ns.Ledger
local function addon(msg, sender) event("CHAT_MSG_ADDON", "NFLC", msg, "RAID", sender or "Bob"); runTimers() end
-- Guild: Me, Bob and Cat are members; Ann is not.
local guildRoster = { "Me-Realm", "Bob-Realm", "Cat-Realm" }
G.IsInGuild = function() return true end
G.GetGuildInfo = function() return "Guildies", "Officer", 1 end
G.GetNumGuildMembers = function() return #guildRoster end
G.GetGuildRosterInfo = function(i) return guildRoster[i] end
check(#Ledger:GetRuns() == 0, "ledger starts empty")
event("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1); runTimers()
Loot:AddManual("|cffa335ee|Hitem:16800::::|h[Arcanist Boots]|h|r"); Addon:Fire("LOOT_ADDED"); runTimers()
Loot:AddManual(19019); runTimers()
local lo = G.NFLC_Loot
check(lo ~= nil and lo:IsShown(), "loot window pops up when loot drops")
local lrows = liveRows(lo.list)
check(#lrows == 3 and lrows[1].data.boss == "Lucifron" and has(lrows[1].boss._text, "Lucifron") and has(lrows[1].boss._text, "(2)"),
    "drops listed under the boss they came from")
check(has(lrows[2].sub._text, "SOFT RESERVED") and has(lrows[2].sub._text, "Bob"), "row shows who may roll: " .. plain(lrows[2].sub._text))
check(has(lrows[3].sub._text, "RESTRICTED"), "legendary is the leader's call")
local run = Ledger:GetRuns()[1]
check(run and run.raidKey == "MC" and run.raidName == "Molten Core" and run.leader == "Me" and #run.entries == 2
    and run.entries[1].boss == "Lucifron" and run.entries[1].winner == nil, "drops recorded in the ledger")
lrows[2].btn1:Click(); runTimers()
event("CHAT_MSG_SYSTEM", "Me rolls 77 (1-100)")
event("CHAT_MSG_SYSTEM", "Ann rolls 12 (1-50)")
event("CHAT_MSG_SYSTEM", "Bob rolls 55 (1-100)")
runTimers()
check(has(lo.panel.standings._text, "1. Bob  55") and not has(lo.panel.standings._text, "Me  77"),
    "only eligible rolls count: " .. plain(lo.panel.standings._text))
check(has(lo.panel.side._text, "not eligible"), "ignored rolls listed")
check(lo.panel.awardSuggested._shown and lo.panel.awardSuggested._text == "Award to Bob", "winner suggested to the leader")
check(Loot:Award(Loot.active.id, "Zed") == false and Loot.active ~= nil and run.entries[1].winner == nil,
    "an award to someone who isn't in the raid is refused")
chatMark = #chat + 1
lo.panel.awardSuggested:Click(); runTimers()
check(chatHas("awarded to Bob", chatMark), "award announced in raid chat")
check(has(liveRows(lo.list)[2].status._text, "Bob"), "row shows the winner")
local led = run.entries[1]
check(led.winner == "Bob" and led.mode == "SOFT" and led.rolls and led.rolls[1].name == "Bob" and led.rolls[1].value == 55
    and led.awardedAt ~= nil, "award, mode and rolls recorded in the ledger")
check(s.reserves.Bob and #s.reserves.Bob.soft == 1, "winning used up that reserve")
liveRows(lo.list)[3].btn1:Click(); runTimers()
lo.panel.awardPick:Click(); UI.menu.buttons[2]:Click(); lo.panel.awardBtn:Click(); runTimers()
check(run.entries[2].winner == "Bob" and run.entries[2].mode == "RESTRICTED", "leader's pick for a restricted item recorded")
-- A drop added by mistake and removed again leaves no trace.
local mistake = Loot:AddManual(17109); runTimers()
check(#run.entries == 3, "third drop recorded")
Loot:RemoveEntry(mistake.id); runTimers()
check(#run.entries == 2, "removed drop taken out of the ledger")
---------------------------------------------------------------------------
-- Loot master extras (R57-R68): hand-out tracking, undo, fallback roll,
-- main spec / off spec, plus-ones, disenchant / bank, soft reserve bonus
---------------------------------------------------------------------------
check(#Loot:Outstanding() == 2 and has(lo.handout._text, "2 to hand out")
    and has(liveRows(lo.list)[2].status._text, "to hand out"), "awarded items are listed as still to hand out")
lo.clearBtn:Click(); runTimers()
check(#Loot.entries == 2, "items still to hand out stay listed for the loot master")
Loot:OnTradeCompleted("Bob", { 16800 }); runTimers()
check(Loot.entries[1].traded == true and run.entries[1].traded == true and #Loot:Outstanding() == 1,
    "a completed trade with the winner ticks the item off")
liveRows(lo.list)[3].btn2:Click(); runTimers()
check(#Loot:Outstanding() == 0 and Loot.entries[2].traded == true, "items can be ticked off by hand")
-- Undo a mis-click: the item is pending again and the reserve is back.
chatMark = #chat + 1
liveRows(lo.list)[2].btn1:Click(); runTimers()
check(Loot.entries[1].state == "pending" and run.entries[1].winner == nil and #s.reserves.Bob.soft == 2
    and chatHas("the award to Bob was undone", chatMark), "undo: pending again, reserve returned, announced")
-- Fallback: the only reserver doesn't roll -> open it to everyone.
liveRows(lo.list)[2].btn1:Click(); runTimers()
check(lo.panel.openBtn._shown and lo.panel.deBtn._shown and lo.panel.bankBtn._shown, "loot master gets Open to all / Disenchant / Bank")
lo.panel.closeBtn:Click(); runTimers()
chatMark = #chat + 1
lo.panel.openBtn:Click(); runTimers()
check(Loot.active and Loot.active.decision.mode == "OPEN" and Loot.active.fallback == true
    and chatHas("no reserver took it: now open to everyone", chatMark) and lo.panel.openBtn._shown == false,
    "a reserved item nobody takes can be opened to everyone")
-- Main spec beats off spec on unreserved items.
event("CHAT_MSG_SYSTEM", "Ann rolls 98 (1-99)")
event("CHAT_MSG_SYSTEM", "Me rolls 5 (1-100)")
runTimers()
local standings = plain(lo.panel.standings._text)
check(has(standings, "1. Me  5") and has(standings, "2. Ann  98 (off spec)"), "main spec beats off spec: " .. standings)
lo.panel.closeBtn:Click(); runTimers()
check(lo.panel.awardSuggested._text == "Award to Me", "main-spec roller suggested")
lo.panel.awardSuggested:Click(); runTimers()
check(run.entries[1].winner == "Me" and run.entries[1].mode == "OPEN" and Loot.entries[1].traded == true
    and run.entries[1].traded == true,
    "fallback award recorded as an open roll; nothing to hand out when the loot master wins")
check(#R:GetWishlist("MC").hard == 2, "the item I won came off my list")
Loot:UndoAward(Loot.entries[1].id); runTimers()
check(same(R:GetWishlist("MC").hard, { 16829, 16800, 16837 }), "undoing my own win puts it back on my list in place")
-- Soft reserve bonus: Bob reserved these boots last week and lost.
s.settings.softBonus, s.settings.softBonusCap = 10, 30
table.insert(Addon.db.ledger.runs, 1, { id = 0, raidKey = "MC", raidName = "Molten Core", leader = "Me", started = 1,
    updated = 1, entries = {}, sr = { Bob = { [16800] = true } } })
check(Ledger:SoftBonus("Bob", 16800) == 10 and Ledger:SoftBonus("Me", 16800) == 0, "bonus from an earlier run")
chatMark = #chat + 1
liveRows(lo.list)[2].btn1:Click(); runTimers()
check(chatHas("bonus: Bob +10", chatMark), "bonus announced with the roll")
event("CHAT_MSG_SYSTEM", "Bob rolls 55 (1-100)"); runTimers()
check(has(plain(lo.panel.standings._text), "1. Bob  55 +10 = 65"), "bonus shown on the roll: " .. plain(lo.panel.standings._text))
lo.panel.awardSuggested:Click(); runTimers()
check(run.entries[1].winner == "Bob" and run.entries[1].mode == "SOFT" and #s.reserves.Bob.soft == 1, "re-awarded after the undo")
table.remove(Addon.db.ledger.runs, 1)
s.settings.softBonus = 0
Loot:SetTraded(Loot.entries[1].id, true); runTimers()
-- Plus-ones and disenchant on an unreserved item.
s.settings.plusOnes = true
table.insert(s.awards, { itemID = 1, player = "Ann", mode = "OPEN" })
local extra = Loot:AddManual(18875); runTimers()
Loot:StartRoll(extra.id); runTimers()
event("CHAT_MSG_SYSTEM", "Ann rolls 90 (1-100)")
event("CHAT_MSG_SYSTEM", "Bob rolls 10 (1-100)")
runTimers()
standings = plain(lo.panel.standings._text)
check(has(standings, "1. Bob  10 [+0]") and has(standings, "2. Ann  90 [+1]"), "plus-ones: fewer wins goes first: " .. standings)
s.settings.plusOnes = false
table.remove(s.awards)
Addon.db.disenchanter = "bob"
chatMark = #chat + 1
lo.panel.deBtn:Click(); runTimers()
check(extra.state == "done" and extra.special == "DISENCHANT" and extra.winner == "Bob" and run.entries[3].mode == "DISENCHANT"
    and chatHas("to be disenchanted (Bob)", chatMark) and #s.reserves.Bob.soft == 1,
    "disenchant: goes to the named player, recorded as such, no reserve used")
check(has(plain(liveRows(lo.list)[4].status._text), "Disenchant: Bob"), "row shows the disenchant outcome")
Addon.db.disenchanter = ""
Loot:UndoAward(extra.id); runTimers()
Loot:RemoveEntry(extra.id); runTimers()
check(#run.entries == 2 and #Loot.entries == 2, "undo + remove leaves no trace")
lo.clearBtn:Click(); runTimers()
check(#Loot.entries == 0 and #run.entries == 2, "clearing the window keeps the ledger")

-- Loot master: an assistant runs loot while the leader keeps the reserves.
check(R:LeaderSetLootMaster("Ann") == false, "the loot master must have raid assist")
roster[2][2] = 1
chatMark = #chat + 1
check(R:LeaderSetLootMaster("bob") == true and s.lootMaster == "Bob" and Addon:GetLootMasterName() == "Bob"
    and not Addon:IsLootMaster() and chatHas("Loot is now run by Bob", chatMark), "leader hands loot to an assistant, announced")
check(Loot:AddManual(17109) == nil, "the leader no longer collects loot")
addon("DROP^701^18875^Garr", "Ann-Realm")
check(#Loot.entries == 0, "loot messages only count from the loot master")
addon("DROP^701^18875^Garr")
check(#Loot.entries == 1 and liveRows(lo.list)[2].btn1._shown == false, "the leader watches the assistant's loot")
addon("AWARD^701^18875^Ann^OPEN")
check(s.awards[#s.awards].player == "Ann" and s.awards[#s.awards].mode == "OPEN", "the leader's reserves record the assistant's award")
local nAwards = #s.awards
addon("AWARD^701^18875^Ann^OPEN")
check(#s.awards == nAwards, "a repeated award for the same drop is recorded once")
event("CHAT_MSG_ADDON", "NFLC", "AWARD^702^16837^Bob^HARD", "WHISPER", "Bob"); runTimers()
check(#s.awards == nAwards and #s.reserves.Bob.hard == 1, "a whispered award is ignored")
addon("UNAWARD^701^18875^Ann^0")
addon("UNDROP^701")
check(#run.entries == 2 and s.awards[#s.awards].player ~= "Ann", "the assistant's undo reaches the leader")
R:LeaderSetLootMaster("Me"); runTimers()
roster[2][2] = 0
check(s.lootMaster == nil and Addon:IsLootMaster(), "loot goes back to the leader")

-- Reserve change log: changes after a boss died are flagged.
addon("SET^MC^16837;16829,17109")
addon("SET^MC^16837;16829")
check(#s.log == 2 and R:LateChangeCount() == 2 and has(R:GetChangeLog(), "Bob")
    and has(R:GetChangeLog(), "after 1 boss kill") and has(R:GetChangeLog(), "SR -"), "reserve changes are logged: " .. R:GetChangeLog():gsub("\n", " / "))
UI:ShowMain("roster"); runTimers()
check(has(rp.changes._text, "Changes (2") and has(rp.changes._text, "2 late"), "roster shows late changes: " .. plain(rp.changes._text))
check(has(rp.lootMaster._text, "Loot master: Me"), "roster shows the loot master")

-- Import: the leader enters reserves for a player without the addon.
roster[4] = { "Dan", 0, 1, 60, "Rogue", "ROGUE" }
event("GROUP_ROSTER_UPDATE"); runTimers()
chatMark = #chat + 1
rp.import:Click()
G.NFLC_InputDialog.edit:SetText("Dan, 16863, HR\nDan, 18875, SR\nBob, 17109, SR\nZed, 16800, SR")
G.NFLC_InputDialog.accept:Click(); runTimers()
check(s.reserves.Dan and s.reserves.Dan.hard[1] == 16863 and s.reserves.Dan.soft[1] == 18875 and s.imported.Dan == true,
    "reserves entered for a player without the addon")
check(#s.reserves.Bob.soft == 1 and s.reserves.Bob.soft[1] == 16829 and s.reserves.Zed == nil,
    "players with the addon and non-members are left alone")
check(chatHas("entered reserves for players without the addon: Dan", chatMark), "import announced in raid chat")
local danRow
for _, r in ipairs(liveRows(rp.list)) do if r.data.name == "Dan" then danRow = r end end
check(danRow and danRow.data.status == "partial" and has(danRow.counts._text, "entered by you"), "roster marks imported reserves")
addon("SET^MC^16805;", "Dan")
check(s.reserves.Dan.hard[1] == 16805 and s.imported.Dan == nil, "the player's own picks replace what the leader entered")
table.remove(roster)
event("GROUP_ROSTER_UPDATE"); runTimers()
check(s.reserves.Dan == nil, "imported player pruned on leaving")

-- Lists as text, class check, tooltips.
check(has(R:ExportWishlist("MC"), "NFLC1!MC!16829,16800,16837!"), "list export: " .. R:ExportWishlist("MC"))
local ikey, inh, ins = R:ImportWishlist("NFLC1!ZG!16800,19019!16800,16805")
check(ikey == "ZG" and inh == 1 and ins == 1 and same(R:GetWishlist("ZG").hard, { 16800 }) and same(R:GetWishlist("ZG").soft, { 16805 }),
    "list import skips legendaries and duplicates")
R:ClearWishlist("ZG")
check(R:ImportWishlist("nonsense") == nil, "bad import text is refused")
plate[900100] = true
G.UnitClass = function() return "Mage", "MAGE" end
check(R:Add(900100, "soft", "ZG") == false, "a mage can't reserve plate")
G.UnitClass = function() return "Warrior", "WARRIOR" end
check(R:Add(900100, "soft", "ZG") == true, "a warrior can")
R:ClearWishlist("ZG")
local tip = {}
for _, l in ipairs(UI.TooltipLines(16829)) do tip[#tip + 1] = l[1] end
tip = table.concat(tip, " | ")
check(has(tip, "Your hard reserve #1 - Molten Core") and has(tip, "HR: Me") and has(tip, "SR: Bob"), "tooltip lines: " .. tip)
check(#UI.TooltipLines(17109) == 0, "nothing added to tooltips of items nobody reserved")

-- Master Loot settings for the new rules.
UI:ShowSettings("masterloot"); runTimers()
check(ml.msos._checked == true and ml.plusOnes._checked == false and ml.bonus.value == 0, "new rules default: MS/OS on, plus-ones off, bonus off")
ml.bonus.plus:Click(); ml.bonus.plus:Click()
ml.plusOnes:SetChecked(true); ml.plusOnes:Click()
check(Addon.db.settings.softBonus == 10 and Addon.db.settings.plusOnes == true, "new rules saved from the settings tab")
ml.bonus.minus:Click(); ml.bonus.minus:Click()
ml.plusOnes:SetChecked(false); ml.plusOnes:Click()

-- Ledger tab.
UI:ShowMain("ledger"); runTimers()
local lp = UI.ledgerPanel
check(UI:CurrentTab() == "ledger" and lp:IsShown(), "ledger tab opens")
check(#liveRows(lp.runList) == 1 and has(liveRows(lp.runList)[1].title._text, "Molten Core")
    and has(liveRows(lp.runList)[1].info._text, "2 drops, 2 awarded"), "run listed with its totals")
local erows = liveRows(lp.entryList)
check(#erows == 3 and erows[1].data.header == "Lucifron" and erows[2].item.itemID == 16800
    and has(plain(erows[2].winner._text), "Bob") and has(plain(erows[2].winner._text), "SR"),
    "run shows boss, item and who got it")
check(has(Ledger:Export(run), "Lucifron | Arcanist Boots | Bob | SOFT"), "ledger export: " .. Ledger:Export(run))

---------------------------------------------------------------------------
-- Guild ledger sync and backups (R42-R48)
---------------------------------------------------------------------------
local Engine = ns.Engine
local sentMsgs = {}
local realSend = ns.Comm.Send
ns.Comm.Send = function(_, channel, target, ...)
    sentMsgs[#sentMsgs + 1] = { channel = channel, target = target, msg = table.concat({ ... }, "^") }
end
check(run.uid ~= nil and run.guild == "Guildies", "a run I lead carries a shared id and my guild")
-- As the leader who owns a run.
Ledger:OnQuery("Ann")
check(#sentMsgs == 0, "runs aren't offered to players outside the guild")
Ledger:OnQuery("Bob")
check(#sentMsgs == 1 and sentMsgs[1].channel == "WHISPER" and sentMsgs[1].target == "Bob"
    and has(sentMsgs[1].msg, "LI^" .. run.uid), "the raid leader offers the runs they led to a guild mate")
sentMsgs = {}
Ledger:OnRequest("Ann", run.uid)
check(#sentMsgs == 0, "runs aren't sent outside the guild")
Ledger:OnRequest("Bob", run.uid)
check(#sentMsgs >= 1 and has(sentMsgs[1].msg, "LD^" .. run.uid .. "^1^"), "the raid leader sends the run")
local echoed = {}
for _, m in ipairs(sentMsgs) do echoed[#echoed + 1] = m.msg:match("^LD%^[^%^]*%^%d+%^%d+%^%d+%^(.*)$") end
local echoedRun = Engine.DecodeRun(table.concat(echoed))
check(echoedRun and #echoedRun.entries == 2 and echoedRun.entries[1].winner == "Bob", "what is sent decodes back to the run")

-- As someone filling gaps: a run Bob led.
local bobRun = {
    uid = "Bob;500", raidKey = "BWL", raidName = "Blackwing Lair", leader = "Bob", guild = "Guildies",
    started = 500, updated = 600,
    entries = { { dropId = 1, itemID = 19003, boss = "Nefarian", time = 550, winner = "Ann", mode = "OPEN",
        awardedAt = 560, rolls = { { name = "Ann", value = 90 } } } },
}
local function feed(sender, uid, r, breakIt)
    local text = Engine.EncodeRun(r)
    local sum = Engine.Checksum(text)
    if breakIt then text = text:sub(1, -2) .. "X" end
    local half = math.floor(#text / 2)
    Ledger:OnData(sender, uid, 1, 2, sum, text:sub(1, half))
    Ledger:OnData(sender, uid, 2, 2, sum, text:sub(half + 1))
end
sentMsgs = {}
Ledger:OnIndex("Bob", "Bob;500", 500, 1, 1)
feed("Bob", "Bob;500", bobRun)
check(#sentMsgs == 0 and #Ledger:GetRuns() == 1, "nothing is accepted unless I asked for a sync")
local nBackups = #Ledger:GetBackups()
check(Ledger:Sync() == true and #Ledger:GetBackups() == nBackups + 1 and sentMsgs[1].channel == "GUILD"
    and sentMsgs[1].msg == "LQ", "sync takes a backup, then polls the guild silently")
check(Ledger:Sync() == false, "the poll is rate limited")
Ledger:OnIndex("Bob", run.uid, run.started, 2, 2)
Ledger:OnIndex("Ann", "Ann;1", 1, 5, 5)
Ledger:OnIndex("Bob", "Bob;500", 500, 1, 1)
check(#sentMsgs == 2 and sentMsgs[2].msg == "LR^Bob;500" and sentMsgs[2].target == "Bob",
    "only runs that are missing or less complete are requested, only from guild mates")
feed("Cat", "Bob;500", bobRun)
check(#Ledger:GetRuns() == 1, "a run is only taken from the player it was requested from")
feed("Bob", "Bob;500", bobRun, true)
check(#Ledger:GetRuns() == 1 and Ledger:SyncStatus().rejected == 1, "a damaged transfer is rejected")
Ledger:OnIndex("Bob", "Bob;500", 500, 1, 1)
feed("Bob", "Bob;500", bobRun)
local synced = Ledger:GetRuns()[2]
check(#Ledger:GetRuns() == 2 and synced.uid == "Bob;500" and synced.syncedFrom == "Bob"
    and synced.entries[1].winner == "Ann" and synced.entries[1].rolls[1].value == 90, "the missing run is added, oldest last")
check(#run.entries == 2 and run.entries[1].winner == "Bob", "my own records are untouched")
-- Only the run's own raid leader counts as its source; other guilds are refused.
local fake = Engine.DeepCopy(bobRun); fake.uid = "Cat;700"; fake.started = 700
Ledger:OnIndex("Cat", "Cat;700", 700, 1, 1)
feed("Cat", "Cat;700", fake)
check(#Ledger:GetRuns() == 2, "a run sent by someone other than its raid leader is refused")
local other = Engine.DeepCopy(bobRun); other.uid = "Cat;800"; other.leader = "Cat"; other.guild = "Other Guild"
Ledger:OnIndex("Cat", "Cat;800", 800, 1, 1)
feed("Cat", "Cat;800", other)
check(#Ledger:GetRuns() == 2 and Ledger:SyncStatus().rejected == 3, "a run led for another guild is refused")
UI:ShowMain("ledger"); runTimers()
check(has(lp.syncStatus._text, "1 run(s) synced") and #liveRows(lp.runList) == 2
    and has(liveRows(lp.runList)[2].info._text, "synced"), "ledger tab shows the sync result: " .. plain(lp.syncStatus._text))
lp.sync:Click(); runTimers()
check(has(lp.syncStatus._text, "Just asked"), "sync button reports why it didn't poll")
-- Backups: restore the copy taken before the sync.
lp.backups:Click()
check(has(UI.menu.buttons[1].text._text, "Back up now") and has(UI.menu.buttons[2].text._text, "before guild sync"),
    "backups menu lists the pre-sync backup")
UI.menu.buttons[2]:Click(); runTimers()
check(#Ledger:GetRuns() == 1 and Ledger:GetRuns()[1].uid == run.uid and #Ledger:GetBackups() == nBackups + 2,
    "restoring a backup undoes the sync, and is itself backed up")
run = Ledger:GetRuns()[1]
-- Damaged saved data is repaired on load, keeping a copy of what was there.
table.insert(Addon.db.ledger.runs, "junk")
table.insert(run.entries, { itemID = "broken" })
nBackups = #Ledger:GetBackups()
check(Ledger:Repair() == 2 and #Addon.db.ledger.runs == 1 and #Addon.db.ledger.runs[1].entries == 2 and #Ledger:GetBackups() == nBackups + 1
    and Ledger:GetBackups()[1].reason == "before repair", "damaged ledger data is repaired on load with a backup")
run = Ledger:GetRuns()[1]
ns.Comm.Send = realSend

---------------------------------------------------------------------------
-- As a raid member (Bob leads)
---------------------------------------------------------------------------
leader = false
roster[1][2] = 0; roster[2][2] = 2
event("GROUP_ROSTER_UPDATE"); runTimers()
check(main.tabs.roster._shown == false and main.tabs.ledger._shown, "roster tab hidden once no longer leader, ledger stays")
UI:ShowMain("roster"); runTimers()
check(UI:CurrentTab() == "raids", "non-leaders can't open the roster tab")
check(R:LeaderApprove("MC", 5, 5) == false and R:LeaderSetLocked(true) == false, "non-leaders can't approve or lock")
addon("PING")

-- The leader's drops show up in my loot window, with who may roll.
lo:Hide()
addon("DROP^501^16805^Magmadar", "Ann-Realm")
check(#Loot.entries == 0 and not lo:IsShown(), "drops from someone who isn't the leader are ignored")
addon("DROP^501^16805^Magmadar")
lrows = liveRows(lo.list)
check(lo:IsShown() and #lrows == 2 and has(lrows[1].boss._text, "Magmadar"), "member's loot window pops up with the drop")
check(has(lrows[2].sub._text, "SOFT RESERVED") and has(lrows[2].sub._text, "Me"), "member sees who may roll: " .. plain(lrows[2].sub._text))
check(lrows[2].btn1._shown == false and lrows[2].btn2._shown == false, "members can't start rolls or remove drops")
check(#run.entries == 3 and run.entries[3].boss == "Magmadar", "member's ledger records the drop")
addon("DROP^501^16805^Magmadar")
check(#Loot.entries == 1 and #run.entries == 3, "a repeated drop message isn't counted twice")
addon("ROLL^501^16805^SOFT^Me")
local pop = G.NFLC_RollPopup
check(lo.panel.rollBtn._shown and lo.panel.awardBtn._shown == false and lo.panel.closeBtn._shown == false,
    "member gets a Roll button, no award controls")
check(pop == nil or not pop:IsShown(), "no separate roll popup while the loot window is open")
lo.panel.rollBtn:Click()
event("CHAT_MSG_SYSTEM", "Me rolls 88 (1-100)")
event("CHAT_MSG_SYSTEM", "Bob rolls 99 (1-100)")
runTimers()
check(has(lo.panel.standings._text, "1. Me  88") and not has(lo.panel.standings._text, "Bob"), "member sees the rolls come in")
check(lo.panel.rollBtn._text == "Rolled" and lo.panel.rollBtn._enabled == false, "can't roll twice")
addon("AWARD^501^16805^Me")
check(has(liveRows(lo.list)[2].status._text, "Me") and lo.panel.rollBtn._shown == false, "member sees the award")
check(run.entries[3].winner == "Me" and run.entries[3].rolls[1].value == 88, "member's ledger records the award and rolls")
local stillListed = false
for _, id in ipairs(R:GetWishlist("MC").soft) do if id == 16805 then stillListed = true end end
check(not stillListed, "an item I won comes off my list")

-- With the loot window closed, the small roll popup is used instead.
addon("DROP^502^16800^Magmadar")
lo:Hide()
addon("ROLL^502^16800^SOFT^Me,Bob")
pop = G.NFLC_RollPopup
check(pop ~= nil and pop:IsShown() and not lo:IsShown() and pop.rollBtn._shown and has(pop.status._text, "You may roll"),
    "roll popup when the loot window is closed")
check(#Loot.entries == 2 and Loot.active and Loot.active.id == 502, "the roll is tracked in the loot window too")
pop.rollBtn:Click()
addon("CANCEL^502")
check(not pop:IsShown() and Loot.active == nil and Loot:GetEntry(502).state == "pending", "cancelled roll goes back to waiting")
addon("UNDROP^502")
check(Loot:GetEntry(502) == nil and #run.entries == 3, "removed drop disappears for members too")
addon("ROLL^503^19019^RESTRICTED^")
check(lo:IsShown() and Loot.active and Loot.active.id == 503 and lo.panel.rollBtn._shown == false,
    "a roll for an unseen drop opens the loot window; restricted: nobody rolls")
lo:Hide(); pop:Hide()
addon("ROLL^503^19019^RESTRICTED^")
check(not pop:IsShown() and not lo:IsShown(), "window closed: no popup for an item I can't roll on")
addon("CANCEL^503")
addon("UNDROP^503")
addon("DROP^504^16800^Magmadar")
lo:Hide()
addon("ROLL^504^16800^HARD^+")
check(has(pop.status._text, "Check raid chat"), "long eligible list falls back to raid chat")
addon("CANCEL^504")
addon("UNDROP^504")

-- Member view of the loot master extras: off-spec button, bonus, disenchant, undo.
local rolledRange
G.RandomRoll = function(low, high) rolledRange = low .. "-" .. high end
addon("DROP^610^18875^Garr")
addon("ROLL^610^18875^OPEN^*")
check(lo:IsShown() and lo.panel.rollBtn._shown and lo.panel.osBtn._shown and has(lo.panel.rollBtn._text, "Main spec"),
    "unreserved item: main spec and off spec buttons")
lo.panel.osBtn:Click()
check(rolledRange == "1-99", "off spec button rolls 1-99")
addon("AWARD^610^18875^Bob^DISENCHANT")
check(has(plain(liveRows(lo.list)[#liveRows(lo.list)].status._text), "Disenchant: Bob") and run.entries[#run.entries].mode == "DISENCHANT",
    "member sees and records a disenchant")
addon("UNAWARD^610^18875^Bob^1")
check(Loot:GetEntry(610).state == "pending" and run.entries[#run.entries].winner == nil, "member sees the undo")
addon("UNDROP^610")
addon("DROP^611^16859^Garr")
addon("ROLL^611^16859^SOFT^Me:10,Bob")
check(lo.panel.osBtn._shown == false, "reserved item: no off-spec roll")
addon("CLOSE^611")
check(Loot:GetEntry(611).roll.open == false and lo.panel.rollBtn._shown == false, "members see the roll close")
addon("ROLL^611^16859^SOFT^Me:10,Bob")
event("CHAT_MSG_SYSTEM", "Bob rolls 55 (1-100)")
event("CHAT_MSG_SYSTEM", "Me rolls 50 (1-100)")
runTimers()
check(has(plain(lo.panel.standings._text), "1. Me  50 +10 = 60"), "member sees the soft reserve bonus: " .. plain(lo.panel.standings._text))
local softBefore = table.concat(R:GetWishlist("MC").soft, ",")
addon("AWARD^611^16859^Me^SOFT")
check(table.concat(R:GetWishlist("MC").soft, ",") ~= softBefore, "winning takes the item off my list")
addon("UNAWARD^611^16859^Me^0")
check(table.concat(R:GetWishlist("MC").soft, ",") == softBefore, "an undone award puts it back")
addon("UNDROP^611")
check(#run.entries == 3, "member ledger back to where it was")
lo:Hide()

-- Closing the loot window keeps it closed while that loot is being handled.
pop:Hide()
addon("DROP^601^17109^Garr")
check(lo:IsShown(), "new loot opens the window")
lo:Hide()
check(UI:IsLootDismissed(), "closing it mid-loot is remembered")
addon("DROP^602^18875^Garr")
addon("ROLL^603^16863^OPEN^*")
check(not lo:IsShown() and #Loot.entries >= 3, "further drops and rolls don't reopen it")
check(pop:IsShown(), "but I'm still offered a roll I can take")
pop:Hide()
UI:ShowLoot(); runTimers()
check(lo:IsShown() and not UI:IsLootDismissed(), "/nflc loot reopens it")
lo:Hide()
addon("AWARD^601^17109^Bob"); addon("AWARD^602^18875^Bob"); addon("AWARD^603^16863^Bob")
check(not UI:IsLootDismissed() and not lo:IsShown(), "once that loot is handed out the block is lifted")
-- Never pops up over a fight.
G.UnitAffectingCombat = function() return true end
addon("DROP^604^16859^Garr")
check(not lo:IsShown(), "no popup while in combat")
G.UnitAffectingCombat = function() return false end
event("PLAYER_REGEN_ENABLED"); runTimers()
check(lo:IsShown(), "it opens once combat ends")
addon("AWARD^604^16859^Bob")
lo:Hide()

-- Member receives new rules from the leader via the Comm path.
rf.banner:Hide(); main:Hide()
local function cfg(h, so, locked)
    event("CHAT_MSG_ADDON", "NFLC", ("CFG^%d,%d,5,0,1,%d,MC"):format(h, so, locked and 1 or 0), "RAID", "Bob"); runTimers()
end
cfg(3, 1, false)
check(main:IsShown() and rf:IsShown() and rf.banner:IsShown() and has(rf.banner.text._text, "Raid leader updated reserve rules"),
    "member CFG -> banner on the live raid")
check(has(rf.status._text, "3 HR / 1 SR"), "member status: " .. rf.status._text)
check(Addon.charDB.lastSeenRules.MC and Addon.charDB.lastSeenRules.MC.hardReserves == 3, "last seen rules stored")
-- More slots than my lists can fill: the player is told, everywhere.
cfg(3, 3, false)
check(has(rf.banner.text._text, "Your lists are short") and has(rf.banner.text._text, "2 more soft"),
    "shortfall alert on rules change: " .. rf.banner.text._text)
check(has(plain(rf.status._text), "Add 2 SR more"), "catalogue header shows what is missing: " .. plain(rf.status._text))
local mh, ms = R:GetShortfall()
check(mh == 0 and ms == 2 and R:WarnShortfall() == true, "shortfall counted from active reserves")
UI:ShowRaidList(); runTimers()
check(has(plain(liveRows(rl.list)[1].picks._text), "you can add 2 SR more"), "live raid card shows the shortfall")
cfg(3, 3, true)
check(has(rf.banner.text._text, "Reserves are locked - you could have used 2 more soft"), "locked with unused slots: told once")
cfg(3, 3, false)
cfg(3, 1, false)
check(R:ShortfallText() == nil and not has(plain(rf.status._text), "more"), "no alert when the lists cover the counts")
cfg(3, 1, true)
local lockedRow
for _, r in ipairs(liveRows(rf.itemList)) do if r.data.itemID then lockedRow = r break end end
check(lockedRow.hr._enabled == false and has(rf.raidNote._text, "Locked"), "locked: buttons disabled, note")
cfg(3, 1, false)
Addon:Fire("SETTINGS_CHANGED", { hardReserves = 3, softReserves = 1 }, { hardReserves = 1, softReserves = 2 }, "MC", "MC", false, false); runTimers()
check(has(rf.banner.text._text, "Hard reserves 3 -> 1"), "SETTINGS_CHANGED diff banner: " .. rf.banner.text._text)

-- Leaving the raid group: nothing is live any more, lists are kept.
inRaid = false
event("GROUP_ROSTER_UPDATE"); runTimers()
check(s.raidKey == nil and s.approved == false and s.locked == false and next(s.reserves) == nil, "leaving the raid clears the live session")
check(#R:GetWishlist("MC").hard >= 1, "my lists survive leaving the raid")
UI:ShowRaidList(); runTimers()
check(liveRows(rl.list)[1].tag._text == "", "no raid is LIVE outside a raid group")
inRaid = true

-- Forever client: Forever raids first, then Classic ones; Forever Onyxia
-- borrows the Classic Onyxia loot and Classic Onyxia isn't listed twice.
G.GetBuildInfo = function() return "1.60", "1", "x", 16001 end
local choiceKeys = {}
for i, c in ipairs(RDA:GetChoices()) do choiceKeys[c.key] = i end
check(choiceKeys.F_BARROW == 1, "forever: Forever raids listed first")
check(choiceKeys.MC and choiceKeys.NAXX and choiceKeys.F_ONY, "forever: classic raids listed too")
check(choiceKeys.ONY == nil, "forever: classic Onyxia not listed twice")
local onyBosses = RDA:GetBosses("F_ONY")
check(#onyBosses >= 1 and has(onyBosses[1].name, "(classic)"), "forever Onyxia boss tagged classic")
local onyIDs = {}
for _, id in ipairs(onyBosses[1].items) do onyIDs[id] = true end
check(onyIDs[16921] and onyIDs[18423], "forever Onyxia has classic loot")
check(RDA:GetBossCount("F_ONY") == 1 and RDA:GetBossCount("F_BARROW") == 0, "boss counts: borrowed and unknown")
check(#RDA:GetBosses("F_BARROW") == 0, "Barrow Deeps still empty until it drops")
UI:ShowRaidList(); runTimers()
local fcards = liveRows(rl.list)
check(fcards[1].data.key == "F_BARROW" and fcards[1].progress._text == "-" and has(fcards[1].info._text, "bosses not known yet"),
    "forever card without boss data")
check(has(fcards[4].tag._text, "Classic"), "classic raids tagged on the Forever client")
for key in pairs(choiceKeys) do
    check(RDA:GetMeta(key) ~= ns.RaidData.defaultMeta, "raid card art defined for " .. key)
end
local onyName = ns.RaidData.raids[2].bosses[1].name
check(onyName == "Onyxia", "classic Onyxia boss name untouched: " .. onyName)
G.GetBuildInfo = function() return "1.15", "1", "x", 11509 end

print("ERRORS", G.ERRORS or 0)
for _, c in ipairs(chat) do print(c) end
os.exit((G.ERRORS or 0) == 0 and 0 or 1)
