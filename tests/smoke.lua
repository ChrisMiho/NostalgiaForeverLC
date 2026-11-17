-- Smoke test: load Core + UI with a permissive WoW mock and exercise the UI.
local ROOT = arg[1]
local timers = {}
local function runTimers()
    for _ = 1, 5 do
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
G.GameTooltip_Hide = function() end
G.hooksecurefunc = function(a, b, c)
    if type(a) == "string" then local old = G[a]; G[a] = function(...) local r = old(...); b(...); return r end
    else local old = a[b]; a[b] = function(...) local r = old(...); c(...); return r end end
end
G.ChatEdit_InsertLink = function() return false end
local inRaid, leader = true, true
G.IsInRaid = function() return inRaid end
G.GetNumGroupMembers = function() return 3 end
local roster = { { "Me", 2, 1, 60, "Warrior", "WARRIOR" }, { "Bob", 0, 1, 60, "Mage", "MAGE" }, { "Ann-Realm", 0, 1, 60, "Priest", "PRIEST" } }
G.GetRaidRosterInfo = function(i) return unpack(roster[i]) end
G.UnitName = function() return "Me" end
G.UnitIsGroupLeader = function() return leader end
G.UnitIsGroupAssistant = function() return false end
G.Ambiguate = function(n) return (n:gsub("%-.*$", "")) end
G.GetBuildInfo = function() return "1.15", "1", "x", 11509 end
G.C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
local cache = { [19019] = { "Thunderfury", 5 }, [16800] = { "Arcanist Boots", 4 } }
G.GetItemInfo = function(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
    local c = cache[id]; if not c then return nil end
    return c[1], "|cffa335ee|Hitem:" .. id .. "::::|h[" .. c[1] .. "]|h|r", c[2], 60, 60, "Armor", "Cloth", 1, "INVTYPE_FEET", 12345
end
G.GetItemIcon = function() return 134400 end
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
G.SendChatMessage = function(m, c) table.insert(chat, c .. ": " .. m) end
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

local ns = {}
local files = { "Core/Engine.lua", "Core/Init.lua", "Data/Raids.lua", "Data/Forever.lua", "Core/RaidDataAPI.lua",
    "Core/Comm.lua", "Core/Reserves.lua", "Core/Loot.lua", "Core/Slash.lua",
    "UI/Widgets.lua", "UI/ReserveFrame.lua", "UI/LeaderFrame.lua", "UI/LootFrame.lua", "UI/RollPopup.lua" }
for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. "/" .. f))
    chunk("IDontWannaLC", ns)
end
local Addon, UI = ns.Addon, ns.UI
local function event(e, ...) Addon.frame._scripts.OnEvent(Addon.frame, e, ...) end
event("ADDON_LOADED", "IDontWannaLC")
Addon.session.raidKey = "MC"

local function check(cond, msg)
    if cond then
        print("ok   " .. msg)
    else
        print("ERROR check failed: " .. msg)
        G.ERRORS = (G.ERRORS or 0) + 1
    end
end
local function has(text, needle) return type(text) == "string" and text:find(needle, 1, true) ~= nil end
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
local function plain(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Reserve window (as leader of MC; defaults 1 HR / 2 SR)
UI:ToggleReserve(); runTimers()
local rf = G.IDWLC_Reserve
assert(rf:IsShown())
local R = ns.Reserves
local hardCol, softCol = rf.columns.hard, rf.columns.soft
check(has(rf.raidNote._text, "Live raid"), "live raid note: " .. rf.raidNote._text)
-- Lucifron: 16800 16829 16837 | 16859 16805 16863 ...
local rows = rf.itemList.rows
rows[1].hr:Click(); runTimers()
rows[2].hr:Click(); runTimers()
rows[3].hr:Click(); runTimers()
rows[4].sr:Click("LeftButton"); runTimers()
rows[5].sr:Click("LeftButton"); runTimers()
rows[6].sr:Click("LeftButton"); runTimers()
local w = R:GetWishlist("MC")
check(same(w.hard, { 16800, 16829, 16837 }) and same(w.soft, { 16859, 16805, 16863 }), "tiers filled from item rows")
check(has(rows[2].hr._text, "HR #2") and not has(rows[2].hr._text, "40ff40"), "row2 HR shows rank, standby: " .. rows[2].hr._text)
check(has(rows[1].hr._text, "HR #1") and has(rows[1].hr._text, "40ff40"), "row1 HR active: " .. rows[1].hr._text)
check(has(rows[5].sr._text, "SR #2"), "row5 SR rank: " .. rows[5].sr._text)
local function colDump(col)
    local out = {}
    for _, r in ipairs(col.list.rows) do
        if rawget(r, "data") then -- unused pooled rows fall through to the mock metatable
            out[#out + 1] = r.data.divider and ("[" .. plain(r.divider._text) .. "]")
                or (r.data.pos .. ":" .. r.item.itemID .. ":" .. plain(r.tag._text))
        end
    end
    return table.concat(out, " ")
end
print("hard col", colDump(hardCol)); print("soft col", colDump(softCol))
check(colDump(hardCol) == "1:16800:Active [-- 1 slot --] 2:16829:Standby 3:16837:Standby", "hard column active/standby + divider")
check(colDump(softCol) == "1:16859:Active 2:16805:Active [-- 2 slots --] 3:16863:Standby", "soft column active/standby + divider")
check(has(hardCol.header._text, "3 / 10"), "hard fill count: " .. hardCol.header._text)
check(has(rf.status._text, "Molten Core: 1 HR / 2 SR per player") and has(rf.status._text, "3 active") and has(rf.status._text, "3 standby"),
    "status line: " .. rf.status._text)
check(hardCol.list.rows[1].up._enabled == false and hardCol.list.rows[4].down._enabled == false, "arrow ends disabled")
-- Reorder: 16829 up to #1, then soft 16859 down to #2.
hardCol.list.rows[3].up:Click(); runTimers()
check(colDump(hardCol) == "1:16829:Active [-- 1 slot --] 2:16800:Standby 3:16837:Standby", "move up: " .. colDump(hardCol))
softCol.list.rows[1].down:Click(); runTimers()
check(same(R:GetWishlist("MC").soft, { 16805, 16859, 16863 }), "move down soft")
check(same(Addon.session.reserves.Me.hard, { 16829 }), "leader's own selection sent after reorder")
-- Leader changes counts: Active/Standby follow.
R:LeaderSetCounts(2, 1); runTimers()
print("hard col", colDump(hardCol)); print("soft col", colDump(softCol))
check(colDump(hardCol) == "1:16829:Active 2:16800:Active [-- 2 slots --] 3:16837:Standby", "counts 2/1 hard column")
check(colDump(softCol) == "1:16805:Active [-- 1 slot --] 2:16859:Standby 3:16863:Standby", "counts 2/1 soft column")
check(has(rf.status._text, "2 HR / 1 SR"), "status after counts: " .. rf.status._text)
check(R:HasPreset("MC"), "preset saved for MC")
print("leader own reserves after count change", table.concat(Addon.session.reserves.Me.hard, ","))
R:LeaderSetCounts(1, 2); runTimers()
-- Remove from the soft tier (row 4 = 16863 after the divider).
softCol.list.rows[4].remove:Click(); runTimers()
check(same(R:GetWishlist("MC").soft, { 16805, 16859 }), "remove x on soft row")
-- Other players' reserves are shown while browsing the live raid.
Addon.session.reserves.Bob = { hard = { 16837 }, soft = { 16829, 16800 } }
Addon:Fire("RESERVES_CHANGED"); runTimers()
check(has(rows[1].sub._text, "Bob"), "others shown on live raid: " .. rows[1].sub._text)
-- link box (browsing MC)
rf.linkBox:SetFocus(); G.ChatEdit_InsertLink(select(2, G.GetItemInfo(19019))); runTimers()
print("link item", rf.linkItem.itemID, rf.linkStatus._text, rf.linkHR._shown)
check(rf.linkHR._shown == false and has(rf.linkStatus._text, "Restricted"), "restricted link item")

-- Browse another raid and plan ahead.
rf.raidButton:Click(); UI.menu.buttons[2]:Click(); runTimers()
print("raid button", rf.raidButton._text, rf.raidNote._text)
check(has(rf.raidNote._text, "Planning ahead"), "planning note")
local otherKey = ns.RaidDataAPI:GetChoices()[2].key
rows[1].hr:Click(); runTimers()
local firstOther = rows[1].itemID
check(same(R:GetWishlist(otherKey).hard, { firstOther }), "pick added to browsed raid " .. otherKey)
check(#R:GetWishlist("MC").hard == 3, "live raid list untouched")
check(has(rows[1].hr._text, "HR #1") and not has(rows[1].sub._text, "Bob"), "browsed row: rank, no live names: " .. rows[1].sub._text)
check(has(rf.panelTitle._text, ns.RaidDataAPI:GetName(otherKey)) and has(hardCol.header._text, "1 / 10"), "panel follows browsed raid")
rf.linkBox:SetFocus(); G.ChatEdit_InsertLink(select(2, G.GetItemInfo(16800))); runTimers()
rf.linkSR:Click("LeftButton"); runTimers()
check(same(R:GetWishlist(otherKey).soft, { 16800 }) and has(rf.linkSR._text, "SR #1"), "link box adds to browsed raid soft tier")
rf.clearBtn:Click(); runTimers()
local ow = R:GetWishlist(otherKey)
check(#ow.hard == 0 and #ow.soft == 0 and #R:GetWishlist("MC").hard == 3, "clear list (browsed raid only)")
rows[2].hr:Click(); runTimers()
check(#R:GetWishlist(otherKey).hard == 1, "pick re-added after clear")
rf.raidButton:Click(); UI.menu.buttons[1]:Click(); runTimers()
check(has(rf.raidNote._text, "Live raid"), "back to live raid")

-- Rules notice: banner + window opens.
rf:Hide()
Addon:Fire("RULES_NOTICE", "test"); runTimers()
check(rf:IsShown() and rf.banner:IsShown() and rf.banner.text._text == "test", "rules notice banner opens window")
print("status", rf.status._text)
Addon:Fire("RESERVE_REJECTED", 16800, "hard", "test reason"); runTimers()

-- Leader window
UI:ToggleLeader(); runTimers()
local lf = G.IDWLC_Leader
check(has(lf.presetNote._text, "Saved rules for this raid"), "leader preset note: " .. lf.presetNote._text)
lf.hardPlus:Click(); lf.double:SetChecked(true); lf.double:Click(); lf.lockButton:Click(); runTimers()
print("leader rows", #lf.list.rows, lf.hardValue._text, Addon.session.settings.allowDoubleSoft, Addon.session.locked)
lf.export:Click(); print("export:", G.IDWLC_TextDialog.text)
lf.list.rows[2].remove:Click(); runTimers()
lf.reset:Click(); runTimers()

-- Loot window
local e = ns.Loot:AddManual("|cffa335ee|Hitem:16800::::|h[Arcanist Boots]|h|r"); Addon:Fire("LOOT_ADDED"); runTimers()
ns.Loot:AddManual(19019); runTimers()
local lo = G.IDWLC_Loot
assert(lo:IsShown())
lo.list.rows[1].btn1:Click(); runTimers()
event("CHAT_MSG_SYSTEM", "Bob rolls 55 (1-100)")
event("CHAT_MSG_SYSTEM", "Me rolls 77 (1-100)")
event("CHAT_MSG_SYSTEM", "Ann rolls 12 (1-50)")
runTimers()
print("standings:\n" .. lo.panel.standings._text .. "\nside:\n" .. lo.panel.side._text)
lo.panel.closeBtn:Click(); runTimers()
print("suggest", lo.panel.awardSuggested._text)
lo.panel.awardSuggested:Click(); runTimers()
print("row1", lo.list.rows[1].status._text)
lo.list.rows[2].btn1:Click(); runTimers()
print("restricted:", lo.panel.standings._text)
lo.panel.awardPick:Click(); UI.menu.buttons[2]:Click(); lo.panel.awardBtn:Click(); runTimers()
print("row2", lo.list.rows[2].status._text)
lo.clearBtn:Click(); runTimers()

-- Roll popup as a member
leader = false
roster[1][2] = 0; roster[2][2] = 2
ns.Loot:OnRemoteRoll(5, 16800, "SOFT", "Me,Bob"); runTimers()
local rp = G.IDWLC_RollPopup
print("popup", rp:IsShown(), rp.mode._text, rp.status._text, rp.rollBtn._shown)
rp.rollBtn:Click()
ns.Loot:OnRemoteAward(5, 16800, "Me"); runTimers()
print("won", rp.mode._text)
ns.Loot:OnRemoteRoll(6, 19019, "RESTRICTED", ""); runTimers()
print("restricted popup", rp.status._text, rp.rollBtn._shown)
ns.Loot:OnRemoteCancel(6); runTimers()
print("after cancel shown", rp:IsShown())
ns.Loot:OnRemoteRoll(7, 16800, "HARD", "+"); runTimers()
print("unknown popup", rp.status._text)
UI:ToggleLeader(); UI:ToggleLeader(); runTimers()
print("leader banner", lf.banner._text)

-- Member receives new rules from the leader (Bob) via the Comm path.
rf.banner:Hide(); rf:Hide()
local function cfg(h, so, locked)
    event("CHAT_MSG_ADDON", "IDWLC", ("CFG^%d,%d,5,0,1,%d,MC"):format(h, so, locked and 1 or 0), "RAID", "Bob"); runTimers()
end
cfg(3, 1, false)
print("member banner", rf.banner.text._text)
check(rf:IsShown() and rf.banner:IsShown() and has(rf.banner.text._text, "Raid leader updated reserve rules"), "member CFG -> banner")
check(has(rf.status._text, "3 HR / 1 SR"), "member status: " .. rf.status._text)
print("member hard col", colDump(hardCol))
check(Addon.charDB.lastSeenRules.MC and Addon.charDB.lastSeenRules.MC.hardReserves == 3, "last seen rules stored")
cfg(3, 1, true)
check(rf.itemList.rows[1].hr._enabled == false and has(rf.raidNote._text, "Locked"), "locked: buttons disabled, note")
cfg(3, 1, false)
Addon:Fire("SETTINGS_CHANGED", { hardReserves = 3, softReserves = 1 }, { hardReserves = 1, softReserves = 2 }, "MC", "MC", false, false); runTimers()
check(has(rf.banner.text._text, "Hard reserves 3 -> 1"), "SETTINGS_CHANGED diff banner: " .. rf.banner.text._text)
print("ERRORS", G.ERRORS or 0)
for _, c in ipairs(chat) do print(c) end
