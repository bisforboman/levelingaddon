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
    for _, list in pairs(questsByItem) do
        table.sort(list) -- so that the quest the tooltip names is the same every session
        for i = #list, 2, -1 do
            if list[i] == list[i - 1] then -- the data can link a pair in more than one way
                table.remove(list, i)
            end
        end
    end
    ns.Report("junk index", ns.Clock() - start)
end

local OTHER_SIDE = { Alliance = "horde", Horde = "alliance" }

-- True when a quest the character has not handed in needs the item: as an objective, as an
-- item to hold or use for it, or as the item that starts it. Quests of the other faction do
-- not count. Also true for anything the client classes as a quest item, which covers what the
-- data lacks. Shared: the bags, the vendor and the item tooltip all ask here. The tooltip also
-- takes the second and third value: one of those quests, from the quest log if any is there,
-- and how many they are.
function ns.QuestNeedsItem(itemID)
    local first, count = nil, 0
    local items = ns.Data and ns.Data.items
    if items and items[itemID] then
        if not questsByItem then
            buildIndex()
        end
        local otherSide = OTHER_SIDE[UnitFactionGroup("player")]
        local firstInLog
        for _, questID in ipairs(questsByItem[itemID] or {}) do
            local quest = ns.Data.quests and ns.Data.quests[questID]
            if not C_QuestLog.IsQuestFlaggedCompleted(questID) and not (quest and quest.side == otherSide) then
                count = count + 1
                if not firstInLog then
                    firstInLog = C_QuestLog.IsOnQuest(questID)
                    first = (firstInLog or not first) and questID or first
                end
            end
        end
    end
    return count > 0 or select(12, GetItemInfo(itemID)) == QUEST_CLASS, first, count
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

local atVendor = false

-- Queue the greys in the bags, if a vendor window is open and the player wants them sold.
local function scan()
    if not (atVendor and ns.db.junkSell and C_Container) then
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
end

-- Bag space: a stop at a vendor among the steps -------------------------------------------
-- When the bags run low the planner adds a "sell" step for the nearest vendor the data knows
-- (Planner.lua asks ns.SellStep and ns.Vendors; the step kind is in Steps.lua).

local LOW_SLOTS = 3 -- free bag slots at which a vendor near the way is suggested
local VENDOR_FLAG = 4 -- in the data's npcFlags
ns.SELL = 0 -- what a sell step carries as its quest id: skips are kept by quest id

local visited = false -- a vendor window was opened while the bags were low: said enough
local space -- the bag space the planner last heard of

-- Free slots in the backpack and the ordinary bags; a quiver or a bag for one kind of item does
-- not count. Plenty where the client cannot say.
local function freeSlots()
    if not (C_Container and C_Container.GetContainerNumFreeSlots) then
        return math.huge
    end
    local free = 0
    for bag = 0, 4 do
        local slots, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then
            free = free + (slots or 0)
        end
    end
    return free
end

local function bagSpace()
    local free = freeSlots()
    return free == 0 and "full" or free <= LOW_SLOTS and "low" or nil
end

-- For the planner: "full", "low", or nil when there is no stop to suggest: the bags have room,
-- the player skipped the stop, or has been to a vendor since the bags ran low.
function ns.SellStep()
    space = bagSpace()
    return not visited and not ns.char.skipped[ns.SELL] and space or nil
end

-- For the step: over once the player is at a vendor or has room again.
function ns.SellDone()
    return atVendor or not bagSpace()
end

-- The vendors the data knows that the character's side can use, each as the planner takes a
-- target: { name, map, x, y, map, x, y, ... }. Read from the NPC table once.
local vendors
function ns.Vendors(side)
    if vendors then
        return vendors
    end
    local start = ns.Clock()
    vendors = {}
    local letter = side == "horde" and "H" or "A"
    local zones = ns.Data.zones or {}
    local ids = {}
    for id, npc in pairs(ns.Data.npcs or {}) do
        local usable = not npc.friendlyTo or npc.friendlyTo:find(letter)
        if usable and npc.spawns and (npc.npcFlags or 0) % (VENDOR_FLAG * 2) >= VENDOR_FLAG then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local npc = ns.Data.npcs[id]
        local vendor = { npc.name }
        for zoneId, points in pairs(npc.spawns) do
            local map = zones[zoneId] and zones[zoneId].uiMapId
            for i = 1, map and #points or 0, 2 do
                if points[i] ~= -1 then -- -1, -1: inside an instance
                    vendor[#vendor + 1] = map
                    vendor[#vendor + 1] = points[i]
                    vendor[#vendor + 1] = points[i + 1]
                end
            end
        end
        vendors[#vendors + 1] = vendor
    end
    ns.Report("vendors read", ns.Clock() - start)
    return vendors
end

-- The bags changed: with room again the stop may be suggested the next time, and a change
-- between room, low and full is a reason for a planner pass.
ns.On("BAG_UPDATE_DELAYED", function()
    local now = bagSpace()
    if not now then
        visited = false
        ns.char.skipped[ns.SELL] = nil
    end
    if now ~= space then
        ns.Planner.Request()
    end
end)

ns.On("MERCHANT_SHOW", function()
    atVendor = true
    visited = bagSpace() ~= nil
    scan()
end)

ns.On("MERCHANT_CLOSED", function()
    atVendor = false
    finish()
end)

-- At an open vendor a change counts at once: on sells now, off stops what is left.
ns.AddSetting({
    key = "junkSell",
    label = "Sell junk",
    tooltip = "Sell the grey items in the bags at a vendor. An item a quest needs is kept.",
    onChange = function()
        finish()
        scan()
    end,
})

ns.commands.junk = function()
    ns.Set("junkSell", not ns.db.junkSell)
    ns.say("selling grey items at a vendor is " .. (ns.db.junkSell and "on" or "off") .. ".")
end
