-- Junk selling: greys are sold at a vendor and totalled, a grey a quest still needs is kept,
-- and nothing is sold while the setting is off.
-- From the repository root: lua5.1 addon/tests/test_junk.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick, cmd = T.ns, T.fire, T.tick, T.cmd

-- The game API this feature calls: item facts and the bags.
local items = { -- [item id] = { quality, vendor price, item class }
    [1] = { 0, 25, 15 }, -- grey
    [2] = { 0, 110, 15 }, -- grey
    [3] = { 0, 40, 15 }, -- grey, an objective of quest 100
    [4] = { 1, 500, 0 }, -- white
    [5] = { 0, 10, 12 }, -- grey, and a quest item to the client
    [6] = { 0, 0, 15 }, -- grey that no vendor buys
    [7] = { 0, 30, 15 }, -- grey that starts quest 101
    [8] = { 0, 30, 15 }, -- grey related to quest 102
}
function GetItemInfo(id)
    local item = items[id]
    return "Item " .. id, nil, item[1], 1, 1, "", "", 20, "", 1, item[2], item[3], 0
end
local bags, used
local function fill()
    bags = { [0] = { { 1, 3 }, { 3, 1 }, false, { 4, 1 }, { 5, 1 }, { 8, 1 } }, { { 2, 1 }, { 6, 1 }, { 7, 1 } } }
    used = {}
end
C_Container = {
    GetContainerNumSlots = function(bag)
        return bags[bag] and #bags[bag] or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local stack = bags[bag][slot]
        if not stack then
            return nil
        end
        local id, count = stack[1], stack[2]
        return { itemID = id, stackCount = count, quality = items[id][1], hasNoValue = items[id][2] == 0 }
    end,
    UseContainerItem = function(bag, slot)
        used[#used + 1] = bag .. ":" .. slot
        bags[bag][slot] = false
    end,
}
-- The quest data as the Lua export lays it out.
ns.Data = {
    quests = { [100] = { objectives = { items = { { id = 3 } } } }, [101] = {}, [102] = {} },
    items = { [3] = {}, [7] = { startQuest = 101 }, [8] = { relatedQuests = { 102 } } },
}
T.load()
T.login()
cmd("hide") -- so that only the selling keeps the update loop running

local function visit()
    fill()
    T.chat = {}
    fire("MERCHANT_SHOW")
    for _ = 1, 20 do
        if not T.looping() then
            break
        end
        tick(0.1)
    end
    assert(not T.looping(), "the task stops when the queue is empty")
    table.sort(used)
    return table.concat(used, " ")
end

-- Off by default: nothing is sold.
assert(ns.db.junkSell == false)
assert(visit() == "" and #T.chat == 0)

-- On: the plain greys go, one per run of the task, and the total is printed.
cmd("junk")
assert(ns.db.junkSell and T.chat[#T.chat]:find("is on"))
assert(visit() == "0:1 1:1", used[1])
assert(#T.chat == 1 and T.chat[1]:find("sold 2 junk items for 1s 85c"), T.chat[1])

-- The lookup the tooltip will share.
assert(ns.QuestNeedsItem(3) and ns.QuestNeedsItem(5) and ns.QuestNeedsItem(7) and ns.QuestNeedsItem(8))
assert(not ns.QuestNeedsItem(1) and not ns.QuestNeedsItem(4))

-- Once its quests are handed in, a grey is junk again.
T.completed[100] = true
T.completed[102] = true
assert(not ns.QuestNeedsItem(3))
assert(visit() == "0:1 0:2 0:6 1:1")
assert(T.chat[1]:find("sold 4 junk items for 2s 55c"), T.chat[1])

-- Closing the vendor early stops the selling and reports what was sold.
items[2][2] = 20005
fill()
T.chat = {}
fire("MERCHANT_SHOW")
tick(0.1)
fire("MERCHANT_CLOSED")
assert(not T.looping() and #used == 1 and T.chat[1]:find("sold 1 junk item for 2g 5c%."), T.chat[1])

-- Without the quest data, the client's word still protects a quest item.
ns.Data = nil
assert(ns.QuestNeedsItem(5) and not ns.QuestNeedsItem(1))

-- Off again.
cmd("junk")
assert(visit() == "" and #T.chat == 0)
print("ALL OK")
