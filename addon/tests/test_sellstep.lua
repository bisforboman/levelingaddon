-- The "sell" step (issue #15): a stop at a vendor among the steps when the bags run low. Under
-- the current step while a vendor is near the way, the current step when the bags are full,
-- skippable, and over once the player is at a vendor or has room again.
-- From the repository root: lua5.1 addon/tests/test_sellstep.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire = T.ns, T.fire

function UnitClass()
    return "Warrior", "WARRIOR"
end
function UnitRace()
    return "Human", "Human"
end
-- The bags: free slots per bag; bag 2 is a quiver, which does not count.
local free = { [0] = 10, 0, 5, 0, 0 }
C_Container = {
    GetContainerNumFreeSlots = function(bag)
        return free[bag], bag == 2 and 1 or 0
    end,
    GetContainerNumSlots = function()
        return 0
    end,
}

-- A fresh human south of Northshire's quest givers (around 48, 42). The stub's map is 1000 yards
-- across, so one percent is 10 yards: they are some 180 yards to the north.
T.px, T.py = 0.482, 0.60
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", ns)
ns.Data.zones = { [12] = { uiMapId = 1429 } }
ns.Data.npcs = {
    [1] = { name = "Near Vendor", npcFlags = 4 + 1, friendlyTo = "AH", spawns = { [12] = { 48.2, 75 } } },
    [2] = { name = "Horde Vendor", npcFlags = 4, friendlyTo = "H", spawns = { [12] = { 48.2, 62 } } },
    [3] = { name = "Far Vendor", npcFlags = 4, friendlyTo = "A", spawns = { [12] = { -1, -1, 80, 60 } } },
    [4] = { name = "Not A Vendor", npcFlags = 2, friendlyTo = "A", spawns = { [12] = { 48.2, 61 } } },
}
T.load()
T.login()
fire("PLAYER_ENTERING_WORLD")

local S = ns.Steps
local function row(index)
    local step = S.list[index]
    return step and step.kind .. " " .. step.name
end
local function current()
    return row(S:CurrentIndex())
end
local function sellRow()
    for index, step in ipairs(S.list) do
        if step.kind == "sell" then
            return index
        end
    end
end
local function bags(slots)
    free[0] = slots
    fire("BAG_UPDATE_DELAYED")
    fire() -- the planner's pass, a moment later
end

-- Room in the bags: no stop.
local first = current()
assert(first and first:find("^accept ") and not sellRow(), first)

-- Little room left: the vendor near the way is the row under the current step. The nearer one
-- is the other side's, and the nearest NPC is no vendor.
bags(3)
local index = S:CurrentIndex()
assert(current() == first and row(index + 1) == "sell Near Vendor", row(index + 1))
assert(S.list[index + 1].map == 1429 and S.list[index + 1].y == 75 and S.list[index + 1].questID == ns.SELL)

-- Skipped like any step: it stays in the list crossed out, above the plan, and nothing is
-- suggested in its place; the restore arrow brings it back.
S:Skip(index + 1)
local skipped = sellRow()
assert(S:Status(skipped) == "skipped" and current() == first and ns.char.skipped[ns.SELL])
assert(row(S:CurrentIndex() + 1) ~= "sell Near Vendor")
S:Restore(skipped)
index = S:CurrentIndex()
assert(current() == first and row(index + 1) == "sell Near Vendor" and S:Status(index + 1) == "pending")
-- A skip lasts until there is room again.
S:Skip(index + 1)
bags(2)
assert(S:Status(sellRow()) == "skipped")
bags(10)
assert(not ns.char.skipped[ns.SELL] and S:Status(sellRow()) == "done", "with room again it is over")
bags(3)
index = S:CurrentIndex()
assert(row(index + 1) == "sell Near Vendor" and S:Status(index + 1) == "pending", row(index + 1))

-- Bags full: the stop is the current step, at the nearest vendor.
bags(0)
assert(current() == "sell Near Vendor", current())
assert(row(S:CurrentIndex() + 1) == first)

-- At the vendor the step is over, and it is not suggested again while the bags stay as they
-- are, however full.
fire("MERCHANT_SHOW")
fire()
assert(current() == first, current())
index = sellRow()
assert(S:Status(index) == "done" and index < S:CurrentIndex(), "the stop is history")
fire("MERCHANT_CLOSED")
fire("BAG_UPDATE_DELAYED")
fire()
assert(current() == first and sellRow() == index)
-- Room again, and low again later: suggested again.
bags(10)
bags(3)
assert(row(S:CurrentIndex() + 1) == "sell Near Vendor")

-- No vendor near the way: no stop with little room, and the nearest vendor once full. Beside
-- the quest givers the near vendor is 320 yards away.
bags(10)
T.py = 0.43
bags(3)
assert(current() == first and S:Status(sellRow()) == "done", "only the old stop, in the history")
bags(0)
assert(current() == "sell Near Vendor", current())

-- The vendors are read once, and only those the character can use and the data can place.
local list = ns.Vendors("alliance")
assert(#list == 2 and list[1][1] == "Near Vendor" and list[2][1] == "Far Vendor")
assert(#list[2] == 4 and list[2][2] == 1429 and list[2][3] == 80, "the point inside an instance is left out")
assert(ns.Stats().timers["vendors read"])
print("ALL OK")
