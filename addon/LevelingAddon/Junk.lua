-- Junk: sells the grey items in the bags when a vendor window opens, and prints the total.
-- Off until the player turns it on with /lvl junk. Nothing is ever deleted, and an item a quest
-- still needs is never sold. Only the container API is used, so it does not matter which addon
-- draws the bags.
local _, ns = ...

ns.defaults.junkSell = false -- automation is opt-in

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local QUEST_CLASS = 12 -- the game's item class for quest items
local POOR = 0 -- grey quality
local SELL_EVERY = 0.05 -- seconds between two sales; a first guess, the client throttles sales

-- Item to quests, from the quest data (ns.Data, once the addon loads it). Built the first time
-- an item the data knows is asked about: every item a quest refers to has a row in
-- ns.Data.items, so for any other item nothing needs building.
local questsByItem

local function buildIndex()
    local start = ns.Clock()
    questsByItem = {}
    local function link(itemID, questID)
        local list = questsByItem[itemID]
        if not list then
            list = {}
            questsByItem[itemID] = list
        end
        list[#list + 1] = questID
    end
    for questID, quest in pairs(ns.Data.quests or {}) do
        for _, objective in ipairs(quest.objectives and quest.objectives.items or {}) do
            link(objective.id, questID)
        end
        if quest.sourceItemId then
            link(quest.sourceItemId, questID)
        end
        for _, itemID in ipairs(quest.requiredSourceItems or {}) do
            link(itemID, questID)
        end
    end
    for itemID, item in pairs(ns.Data.items) do
        for _, questID in ipairs(item.relatedQuests or {}) do
            link(itemID, questID)
        end
        if item.startQuest then
            link(itemID, item.startQuest)
        end
    end
    ns.Report("junk index", ns.Clock() - start)
end

-- True when a quest the character has not handed in needs the item: as an objective, as an
-- item to hold or use for it, or as the item that starts it. Also true for anything the client
-- classes as a quest item, which covers what the data lacks. Shared: the bags, the vendor and
-- the item tooltip all ask here.
function ns.QuestNeedsItem(itemID)
    if select(12, GetItemInfo(itemID)) == QUEST_CLASS then
        return true
    end
    local items = ns.Data and ns.Data.items
    if not items or not items[itemID] then
        return false
    end
    if not questsByItem then
        buildIndex()
    end
    for _, questID in ipairs(questsByItem[itemID] or {}) do
        if not C_QuestLog.IsQuestFlaggedCompleted(questID) then
            return true
        end
    end
    return false
end

local function money(copper)
    local gold, silver = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if copper % 100 > 0 then
        parts[#parts + 1] = copper % 100 .. "c"
    end
    return table.concat(parts, " ")
end

local queue = {} -- { bag, slot, itemID, copper } still to sell at the open vendor
local sold, earned = 0, 0

local function finish()
    ns.SetTask("junk", false)
    wipe(queue)
    if sold > 0 then
        ns.say(string.format("sold %d junk item%s for %s.", sold, sold == 1 and "" or "s", money(earned)))
    end
    sold, earned = 0, 0
end

-- One sale per run, so a full bag of junk is spread over a second or two.
ns.Task("junk", SELL_EVERY, function()
    local entry = table.remove(queue)
    if not entry then
        finish()
        return
    end
    -- Only if the slot still holds what was found when the vendor opened.
    local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
    if info and info.itemID == entry.itemID and not info.isLocked then
        C_Container.UseContainerItem(entry.bag, entry.slot)
        sold = sold + 1
        earned = earned + entry.copper
    end
end)

ns.On("MERCHANT_SHOW", function()
    if not ns.db.junkSell or not C_Container then
        return
    end
    wipe(queue) -- the event can come twice for one visit
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == POOR and not info.hasNoValue then
                local price = select(11, GetItemInfo(info.itemID))
                if price and price > 0 and not ns.QuestNeedsItem(info.itemID) then
                    queue[#queue + 1] =
                        { bag = bag, slot = slot, itemID = info.itemID, copper = price * info.stackCount }
                end
            end
        end
    end
    if queue[1] then
        ns.SetTask("junk", true)
    end
end)

ns.On("MERCHANT_CLOSED", finish)

ns.commands.junk = function()
    ns.db.junkSell = not ns.db.junkSell
    ns.say("selling grey items at a vendor is " .. (ns.db.junkSell and "on" or "off") .. ".")
end
