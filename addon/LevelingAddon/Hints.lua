-- Hints: one line on an item's tooltip, "Needed for: <quest>", when a quest the character has
-- or can still do needs the item, so that it is not sold or deleted. The lookup is the one junk
-- selling uses (ns.QuestNeedsItem in Junk.lua): by item id, with nothing scanned when a
-- tooltip opens.
local _, ns = ...

ns.defaults.itemHint = true
ns.AddSetting({
    key = "itemHint",
    label = "Quest item hint",
    tooltip = "Say on an item's tooltip which quest needs it.",
    onChange = function() end, -- read when the next tooltip opens; nothing to redraw
})

local function hint(tooltip, itemID)
    -- Only the two tooltips that show an item on its own, not the comparison tooltips.
    if not itemID or not ns.db.itemHint or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
        return
    end
    local _, questID, count = ns.QuestNeedsItem(itemID)
    local quest = questID and ns.Data.quests and ns.Data.quests[questID]
    if quest and quest.name then
        tooltip:AddLine("Needed for: " .. quest.name .. (count > 1 and " and " .. count - 1 .. " more" or ""))
    end
end

-- Newer clients hand every tooltip's data to callbacks; older ones run a script on the tooltip
-- when it is given an item. Both only add a line, after the game has filled the tooltip.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        hint(tooltip, data and data.id)
    end)
else
    for _, tooltip in pairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip.HasScript and tooltip:HasScript("OnTooltipSetItem") then
            tooltip:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                hint(self, link and tonumber(link:match("item:(%d+)")))
            end)
        end
    end
end
