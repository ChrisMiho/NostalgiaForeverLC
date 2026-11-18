-- NostalgiaForeverLC - Raids tab (home screen)
-- A stack of wide raid cards: name, the raid's graphic, size, lockout
-- progress (X/N bosses), times cleared, last kill and how many picks you
-- have saved for it. The raid the leader is running is first and marked
-- LIVE. Clicking a card opens that raid's catalogue (UI/RaidView.lua).

local _, ns = ...
local Addon, UI = ns.Addon, ns.UI
local Reserves, RaidData = ns.Reserves, ns.RaidDataAPI

local CARD_H, CARD_GAP = 96, 6
local ICON = 64
local GREEN, GREY, RED = "40ff40", "808080", "ff4040"

local GetIconByID = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon

local QUESTION_MARK_ID = 134400 -- what the client returns for an item it doesn't know

local function cardIcon(meta)
    local icon = meta.artItem and GetIconByID and GetIconByID(meta.artItem)
    if icon == QUESTION_MARK_ID then icon = nil end
    return icon or meta.icon
end

local function plural(n, word)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

-- One table per card, live raid first.
local function buildCards()
    local s = Addon.session
    local liveKey = s.approved and IsInRaid() and s.raidKey or nil
    local cards, seen = {}, {}
    local function add(key, name, expansion, size)
        local wish = Reserves:GetWishlist(key)
        local card = {
            key = key, name = name, expansion = expansion, size = size,
            stats = ns.Stats:Get(key), meta = RaidData:GetMeta(key),
            nHard = #wish.hard, nSoft = #wish.soft, live = key == liveKey,
        }
        seen[key] = true
        if card.live then table.insert(cards, 1, card) else cards[#cards + 1] = card end
    end
    for _, c in ipairs(RaidData:GetChoices()) do add(c.key, c.name, c.expansion, c.size) end
    -- A live raid we have no data for at all (brand new instance).
    if liveKey and not seen[liveKey] then add(liveKey, RaidData:GetName(liveKey), "forever") end
    return cards
end

local function createCard(parent)
    local row = CreateFrame("Button", nil, parent)
    local body = CreateFrame("Frame", nil, row, "BackdropTemplate")
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", 0, CARD_GAP)
    body:SetBackdrop(UI.BACKDROP)
    row.body = body

    -- Optional wide artwork behind everything (Data/RaidMeta.lua `art`).
    row.art = body:CreateTexture(nil, "BACKGROUND", nil, 2) -- above the backdrop's own fill
    row.art:SetPoint("TOPLEFT", 4, -4)
    row.art:SetPoint("BOTTOMRIGHT", -4, 4)
    row.art:SetAlpha(0.35)

    row.stripe = body:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", 4, -4)
    row.stripe:SetPoint("BOTTOMLEFT", 4, 4)
    row.stripe:SetWidth(6)

    row.icon = body:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 20, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.hover = body:CreateTexture(nil, "ARTWORK")
    row.hover:SetPoint("TOPLEFT", 4, -4)
    row.hover:SetPoint("BOTTOMRIGHT", -4, 4)
    row.hover:SetColorTexture(1, 1, 1, 0.06)
    row.hover:Hide()

    row.name = UI:Label(body, nil, "GameFontNormalLarge")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 14, 2)
    row.tag = UI:Label(body, nil, "GameFontNormal")
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.info = UI:Label(body, nil, "GameFontHighlightSmall")
    row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
    row.stats = UI:Label(body, nil, "GameFontHighlightSmall")
    row.stats:SetPoint("TOPLEFT", row.info, "BOTTOMLEFT", 0, -4)
    row.picks = UI:Label(body, nil, "GameFontHighlightSmall")
    row.picks:SetPoint("TOPLEFT", row.stats, "BOTTOMLEFT", 0, -4)

    row.progress = UI:Label(body, nil, "GameFontNormalHuge")
    row.progress:SetPoint("RIGHT", -24, 8)
    row.progress:SetJustifyH("RIGHT")
    row.progressNote = UI:Label(body, nil, "GameFontDisableSmall")
    row.progressNote:SetPoint("TOPRIGHT", row.progress, "BOTTOMRIGHT", 0, -4)
    row.progressNote:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.data then UI:OpenRaid(self.data.key) end
    end)
    return row
end

local function updateCard(row, card)
    local s = Addon.session
    local r, g, b = card.meta.color[1], card.meta.color[2], card.meta.color[3]
    row.body:SetBackdropColor(r * 0.16, g * 0.16, b * 0.16, 0.95)
    if card.live then
        row.body:SetBackdropBorderColor(0.25, 1, 0.25, 1)
    else
        row.body:SetBackdropBorderColor(r * 0.7, g * 0.7, b * 0.7, 1)
    end
    row.stripe:SetColorTexture(r, g, b, 1)
    row.icon:SetTexture(cardIcon(card.meta))
    if card.meta.art then
        row.art:SetTexture(card.meta.art)
        row.art:Show()
    else
        row.art:Hide()
    end

    row.name:SetText(card.name)
    row.name:SetTextColor(r * 0.5 + 0.5, g * 0.5 + 0.5, b * 0.5 + 0.5)
    if card.live then
        row.tag:SetText(UI.Color(GREEN, "LIVE"))
    elseif card.expansion == "classic" and RaidData:IsForeverClient() then
        row.tag:SetText(UI.Color(GREY, "Classic"))
    else
        row.tag:SetText("")
    end

    local st = card.stats
    local info = {}
    if card.size then info[#info + 1] = card.size .. " players" end
    if st.total > 0 then
        info[#info + 1] = st.total == 1 and "1 boss" or (st.total .. " bosses")
    else
        info[#info + 1] = "bosses not known yet"
    end
    if card.live then
        info[#info + 1] = ("%d HR / %d SR per player - %s"):format(s.settings.hardReserves, s.settings.softReserves,
            s.locked and UI.Color(RED, "LOCKED") or UI.Color(GREEN, "open"))
    end
    row.info:SetText(table.concat(info, "   |   "))

    local stats = st.clears > 0 and ("Cleared " .. plural(st.clears, "time")) or UI.Color(GREY, "Not cleared yet")
    if st.lastKill then stats = stats .. "   |   Last kill " .. date("%Y-%m-%d", st.lastKill) end
    row.stats:SetText(stats)

    local picks
    if card.nHard + card.nSoft > 0 then
        picks = ("Your lists: %s, %s"):format(UI.Color(UI.HARD_COLOR, card.nHard .. " HR"),
            UI.Color(UI.SOFT_COLOR, card.nSoft .. " SR"))
    else
        picks = UI.Color(GREY, "No picks yet - click to choose your reserves")
    end
    if card.live then
        local mh, ms = Reserves:GetShortfall()
        if mh + ms > 0 then
            local need = {}
            if mh > 0 then need[#need + 1] = mh .. " HR" end
            if ms > 0 then need[#need + 1] = ms .. " SR" end
            picks = picks .. "   " .. UI.Color(RED, (s.locked and "%s unused" or "you can add %s more"):format(
                table.concat(need, " + ")))
        end
    end
    row.picks:SetText(picks)

    if st.total > 0 then
        row.progress:SetText(("%d/%d"):format(math.min(st.killed, st.total), st.total))
    else
        row.progress:SetText(st.killed > 0 and tostring(st.killed) or "-")
    end
    row.progressNote:SetText("bosses this lockout")
end

local function createList(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.hint = UI:Label(f, "Pick a raid to browse its bosses and loot and build your hard / soft reserve lists. "
        .. "You can do this any time - your lists are used automatically when you join the raid.", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 4, -2)
    f.hint:SetPoint("TOPRIGHT", -4, -2)
    f.hint:SetTextColor(0.7, 0.7, 0.7)
    f.list = UI:CreateScrollList(f, CARD_H + CARD_GAP, createCard, updateCard)
    f.list:SetPoint("TOPLEFT", 0, -34)
    f.list:SetPoint("BOTTOMRIGHT", -24, 0)
    f.Refresh = function(self) self.list:SetData(buildCards()) end
    return f
end

UI:RegisterPanel("raids", {
    title = "Raids",
    tooltip = "Every raid, your progress in it and your reserve lists.",
    create = function(parent)
        local f = CreateFrame("Frame", nil, parent)
        local list = createList(f)
        list:SetAllPoints(f)
        local view = UI:CreateRaidView(f) -- UI/RaidView.lua
        view:SetAllPoints(f)
        UI.raidList, UI.raidView = list, view
        f.Refresh = function()
            if UI.raidViewKey then
                list:Hide()
                view:Show()
                view:Refresh()
            else
                view:Hide()
                list:Show()
                list:Refresh()
            end
        end
        return f
    end,
})
