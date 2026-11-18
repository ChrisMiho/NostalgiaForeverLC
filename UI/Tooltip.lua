-- NostalgiaForeverLC - Item tooltips
-- Adds reserve info to item tooltips everywhere in the game (bags, chat
-- links, the loot frame, other addons): where the item sits on your own
-- lists, and - in the live raid - who has it hard and soft reserved.
-- Can be switched off in Settings > General.

local _, ns = ...
local Addon, Engine, UI = ns.Addon, ns.Engine, ns.UI

local function indexOf(list, id)
    for i, v in ipairs(list or {}) do
        if v == id then return i end
    end
end

-- Lines to add for an item: { { text, r, g, b }, ... } (empty when the
-- addon has nothing to say about it).
function UI.TooltipLines(itemID)
    local lines = {}
    if not itemID or not Addon.charDB or not Addon.session then return lines end
    -- My own lists, for any raid.
    local keys = {}
    for raidKey in pairs(Addon.charDB.wishlists or {}) do keys[#keys + 1] = raidKey end
    table.sort(keys)
    for _, raidKey in ipairs(keys) do
        local w = Addon.charDB.wishlists[raidKey]
        local h, s = indexOf(w.hard, itemID), indexOf(w.soft, itemID)
        if h then
            lines[#lines + 1] = { ("Your hard reserve #%d - %s"):format(h, ns.RaidDataAPI:GetName(raidKey)), 1, 0.6, 0.2 }
        elseif s then
            lines[#lines + 1] = { ("Your soft reserve #%d - %s"):format(s, ns.RaidDataAPI:GetName(raidKey)), 0.4, 0.7, 1 }
        end
    end
    -- Everyone's active reserves in the live raid.
    local session = Addon.session
    if session.approved and IsInRaid() then
        local hard, soft = session:GetReservers(itemID)
        if #hard > 0 then lines[#lines + 1] = { "HR: " .. table.concat(hard, ", "), 1, 0.6, 0.2 } end
        if #soft > 0 then
            local counts, order = {}, {}
            for _, n in ipairs(soft) do
                if not counts[n] then order[#order + 1] = n end
                counts[n] = (counts[n] or 0) + 1
            end
            for i, n in ipairs(order) do
                if counts[n] > 1 then order[i] = n .. " x" .. counts[n] end
            end
            lines[#lines + 1] = { "SR: " .. table.concat(order, ", "), 0.4, 0.7, 1 }
        end
    end
    return lines
end

local function addLines(tooltip, itemID)
    if not Addon.db or not Addon.db.tooltips then return end
    local lines = UI.TooltipLines(itemID)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Nostalgia Forever LC", 0.2, 1, 0.6)
    for _, l in ipairs(lines) do tooltip:AddLine(l[1], l[2], l[3], l[4], true) end
    tooltip:Show()
end

local function isOurs(tooltip)
    return tooltip == GameTooltip or (ItemRefTooltip ~= nil and tooltip == ItemRefTooltip)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    -- Modern client.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if isOurs(tooltip) and data then addLines(tooltip, data.id) end
    end)
else
    -- Classic Era.
    -- Fires twice for some items (recipes): add our lines once per tooltip.
    local done = {}
    local function onSetItem(tooltip)
        if done[tooltip] or not tooltip.GetItem then return end
        local _, link = tooltip:GetItem()
        done[tooltip] = true
        addLines(tooltip, Engine.ItemIDFromLink(link))
    end
    local function onCleared(tooltip) done[tooltip] = nil end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip and tooltip.HookScript then
            tooltip:HookScript("OnTooltipSetItem", onSetItem)
            tooltip:HookScript("OnTooltipCleared", onCleared)
        end
    end
end
