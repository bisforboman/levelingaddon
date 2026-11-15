-- The arrow beyond direction and distance (those are in test_ui.lua): the nearest of several
-- places from the quest data, moving on through a kill area, the arrived ring, the corpse,
-- another continent, and resting when there is nothing to point at.
-- From the repository root: lua5.1 addon/tests/test_arrow.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick = T.ns, T.fire, T.tick
T.load()
ns.Steps.list = dofile("addon/tests/northshire.lua") -- a fixed route; no planner data, so no planning
-- The plain tables the arrow reads, cut from a real export and bent a little: zone 9
-- (Northshire) is drawn on the map of zone 12 (Elwynn Forest, map 1429), zone 1 on another map,
-- zone 209 is a dungeon.
ns.Data = {
    zones = {
        [1] = { uiMapId = 1426 },
        [9] = { parentZoneId = 12 },
        [12] = { uiMapId = 1429 },
        [209] = { isDungeon = true },
    },
    quests = {
        [783] = { start = { npcs = { 823 } }, ["end"] = { npcs = { 197 } } },
        [7] = { start = { npcs = { 197 } }, ["end"] = { npcs = { 197 } }, objectives = { npcs = { { id = 6 } } } },
        [33] = { objectives = { items = { { id = 750 } } } },
    },
    npcs = {
        [6] = {
            name = "Kobold Vermin",
            spawns = { [12] = { 48.89, 36.44, 46.93, 35.67, 50.76, 37.47 }, [1] = { 10, 10 }, [209] = { -1, -1 } },
        },
        [69] = { name = "Timber Wolf", spawns = { [9] = { 46, 44 } } },
        [197] = { name = "Marshal McBride", spawns = { [12] = { 48.92, 41.61 } } },
        [299] = { name = "Young Wolf", spawns = { [12] = { 47, 40, 47.5, 40.5 } } },
        [823] = { name = "Deputy Willem", spawns = { [12] = { 48.17, 42.94 } } },
    },
    objects = {},
    items = { [750] = { name = "Tough Wolf Meat", npcDrops = { 69, 299 } } },
}
local conversions = 0
local convert = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function(...)
    conversions = conversions + 1
    return convert(...)
end
T.login()
local A, S = ns.Arrow, ns.Steps
local turn
A.texture.SetRotation = function(_, v)
    turn = v
end
local updates = 0
local update = A.Update
function A:Update()
    updates = updates + 1
    return update(self)
end
-- Stand at a map position (percent) and let the arrow look for the nearest place again.
local function standAt(x, y)
    T.px, T.py = x / 100, y / 100
    for _ = 1, 5 do
        tick()
    end
end
local function shows(text, ring)
    assert(A.distance.text == text, A.distance.text)
    assert(A.ring.shown == ring and A.texture.shown ~= ring)
end

-- Step 1 is Deputy Willem, one place: 35 yards from the start, and on arrival the arrow
-- becomes a ring with no distance.
assert(#A.target == 1 and not A.ring.shown)
standAt(49.2, 46.3)
shows("35 yd", false)
standAt(48.2, 43)
shows("", true)

-- Step 6, the kobolds: three places on this map in the data (the one on another map and the
-- one in a dungeon are left out). They are turned into world coordinates once.
T.completed[783] = true
T.log[7] = { need = 10, have = 0 }
T.log[33] = { need = 8, have = 8 }
fire("QUEST_LOG_UPDATE")
assert(S:CurrentIndex() == 6 and #A.target == 3 and A.target.area)
local converted = conversions
standAt(44, 34)
shows("33 yd", false) -- the nearest: 46.93, 35.67
ns.Refresh()
standAt(44.1, 34)
assert(conversions == converted, "nothing is converted again while the step stays")

-- Inside 30 yards a place counts as reached and the arrow moves on to the next nearest, with
-- no ring; after the last place it goes round again.
standAt(46.5, 35.5)
shows("25 yd", false) -- 48.89, 36.44, which is in reach as well
standAt(46.5, 35.5)
shows("46 yd", false) -- 50.76, 37.47
standAt(50.76, 37.47)
shows("21 yd", false) -- round again: 48.89, 36.44

-- An item: the places of whatever drops it. A new plan with the same step keeps the target.
T.log[33].have = 0
T.log[7].have = 10
fire("QUEST_LOG_UPDATE")
assert(S:CurrentIndex() == 5 and #A.target == 3)
standAt(49.2, 46.3)
shows("39 yd", false) -- the Timber Wolf at 46, 44

-- A ghost is shown the way to the corpse: 100 yards south, behind a player facing north.
T.ghost, T.corpse = true, { 0.5, 0.5 }
fire("PLAYER_ALIVE") -- the spirit was released
standAt(50, 40)
shows("100 yd", false)
assert(math.abs(math.abs(turn) - math.pi) < 0.01)
standAt(50, 49.7)
shows("", true)
T.ghost = false
fire("PLAYER_UNGHOST")
standAt(49.2, 46.3)
shows("39 yd", false)

-- Another continent: nothing is drawn, and the task rests until the player arrives somewhere.
local position = UnitPosition
function UnitPosition()
    return 500, 500, 0, 1
end
tick()
assert(A.frame.alpha == 0)
updates = 0
standAt(49.2, 46.3)
assert(updates == 0, "no updates while the target is on another continent")
UnitPosition = position
fire("PLAYER_ENTERING_WORLD")
tick()
assert(A.frame.alpha == 1 and updates > 0)

-- Where the client names its maps, the step's zone and its continent take the arrow's place,
-- the frame grows to fit them, and the task still rests.
C_Map.GetMapInfo = function(map)
    local maps = {
        [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13 },
        [13] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    }
    return maps[map]
end
local width
A.frame.SetWidth = function(_, v)
    width = v
end
function UnitPosition()
    return 500, 500, 0, 1
end
tick()
assert(A.frame.alpha == 1 and A.zone.text == "Elwynn Forest" and A.continent.text == "Eastern Kingdoms")
assert(width == 92 and not A.texture.shown and not A.ring.shown and A.distance.text == "")
A.frame.scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
assert(A.frame.alpha == 0.4)
A.frame.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
updates = 0
tick()
assert(updates == 0, "the name needs no updates")
-- A flight borrows the frame; the name is back after landing.
A:SetFlight("1:00", "Ironforge")
assert(A.zone.text == "" and A.flightTime.text == "1:00")
A:SetFlight(nil)
tick()
assert(A.zone.text == "Elwynn Forest")
UnitPosition = position
fire("PLAYER_ENTERING_WORLD")
tick()
assert(A.zone.text == "" and A.continent.text == "" and width == 56)
shows("39 yd", false)

-- Other features can ask for a step's places: positions on its map, from 0 to 1.
local places = A.Places(S:Current())
assert(#places == 6 and places[1] == 0.46 and places[2] == 0.44)

-- An instance: no position. The same, and one frame without a position elsewhere only hides.
function UnitPosition() end
tick()
updates = 0
tick()
assert(A.frame.alpha == 0 and updates == 1, "a missing position alone does not stop the task")
T.instance = true
tick()
updates = 0
tick()
assert(updates == 0, "no updates in an instance")
UnitPosition, T.instance = position, false
fire("ZONE_CHANGED_NEW_AREA")
tick()
assert(A.frame.alpha == 1)
shows("39 yd", false)

-- Combat dims the arrow if "Dim in combat" is on, and never brings back a hidden one.
A.frame.scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
assert(A.frame.alpha == 0.4)
ns.db.combatDim = false
ns.Refresh()
assert(A.frame.alpha == 1)
ns.db.combatDim = true
function UnitPosition() end
tick()
assert(A.frame.alpha == 0)
A.frame.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
assert(A.frame.alpha == 0)
UnitPosition = position
tick()
assert(A.frame.alpha == 1)

-- Moving the arrow (#76): dragged while unlocked and kept as the middle of its top edge;
-- locked, it does not move and lets clicks through; /lvl reset puts it back.
local F = A.frame
local moved, mouse = 0, nil
rawset(F, "StartMoving", function()
    moved = moved + 1
end)
rawset(F, "StopMovingOrSizing", function() end)
rawset(F, "GetCenter", function()
    return 300, 200
end)
rawset(F, "GetTop", function()
    return 450
end)
rawset(F, "EnableMouse", function(_, on)
    mouse = on
end)
A.movable = nil
A:StepChanged()
assert(mouse == true, "unlocked: the arrow takes the mouse")
F.scripts.OnDragStart()
F.scripts.OnDragStop()
assert(moved == 1 and ns.db.arrowPoint[1] == 300 and ns.db.arrowPoint[2] == 450, "the place is saved")
assert(F.point[1] == "TOP" and F.point[3] == "BOTTOMLEFT" and F.point[4] == 300 and F.point[5] == 450)
T.cmd("lock")
assert(mouse == false, "locked: clicks go through")
F.scripts.OnDragStart()
F.scripts.OnDragStop()
assert(moved == 1, "locked: no move")
T.cmd("lock")
assert(mouse == true)
F.point = nil
A:RestorePosition()
assert(F.point[4] == 300 and F.point[5] == 450, "restored where it was put")
T.cmd("reset")
assert(ns.db.arrowPoint == nil and F.point[1] == "TOP" and F.point[3] == "TOP" and F.point[5] == -110, "reset")

-- /lvl arrow still switches it off.
T.cmd("arrow")
assert(not A.frame.shown)
print("ALL OK")
