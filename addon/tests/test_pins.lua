-- The world-map and minimap pin for the current step: where they are put, when they are
-- placed again, the setting, and standing back when TomTom has the waypoint.
-- From the repository root: lua5.1 addon/tests/test_pins.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick, cmd = T.ns, T.fire, T.tick, T.cmd
T.load()
ns.Steps.list = dofile("addon/tests/northshire.lua") -- a fixed route; no quest data, so no planning
local before = #T.frames
T.login()
local function near(a, b)
    return math.abs(a - b) < 0.01
end
local world, mini
for i = before + 1, #T.frames do
    local f = T.frames[i]
    if f.parent == T.canvas then
        world = f
    elseif f.parent == Minimap then
        mini = f
    end
end
assert(world and mini, "one pin on the world map canvas and one on the minimap")
local created = #T.frames

-- Step 1 is Deputy Willem at 48.2, 42.9 on map 1429, which the world map shows.
assert(world.shown and near(world.point[4], 482) and near(world.point[5], -257.4))
world.scripts.OnEnter(world)
assert(GameTooltip.text == "Deputy Willem" and GameTooltip.shown)
world.scripts.OnLeave(world)
assert(not GameTooltip.shown)

-- The pin keeps its screen size when the map is zoomed, and its place on the canvas.
T.canvasScale = 0.5
local scale
world.SetScale = function(_, v)
    scale = v
end
WorldMapFrame:OnCanvasScaleChanged()
assert(scale == 2 and near(world.point[4], 241) and near(world.point[5], -128.7))
T.canvasScale = 1

-- On the continent map the pin is where the spot is there; on an unrelated map there is none.
T.mapID = 13
WorldMapFrame:OnMapChanged()
assert(world.shown and near(world.point[4], 491) and near(world.point[5], 0.4645 * -600))
T.mapID = 99
WorldMapFrame:OnMapChanged()
assert(not world.shown)
T.mapID = nil -- the map has not been opened yet
WorldMapFrame:OnMapChanged()
assert(not world.shown)
T.mapID = 1429
WorldMapFrame:OnMapChanged()
assert(world.shown)

-- Minimap: the player is at 49.2, 46.3, so the step is 10 yards west and 34 north. At zoom 0
-- the minimap shows 233.33 yards each way and is 70 pixels each way.
assert(mini.shown and near(mini.point[4], -10 / 233.33 * 70) and near(mini.point[5], 34 / 233.33 * 70))
assert(T.looping(), "the minimap pin follows the player on the shared loop")

-- Standing still places nothing again; moving does.
mini.point = nil
tick()
assert(mini.point == nil)
T.px = 0.482
tick()
assert(near(mini.point[4], 0))
T.px = 0.492

-- Zoomed in, indoors: 50 yards across. The step is further than that, so the pin is on the rim.
T.zoom, T.indoors = 5, true
tick()
local x, y = mini.point[4], mini.point[5]
assert(near(math.sqrt(x * x + y * y), 70) and near(x / y, -10 / 34))
-- A square minimap has room in its corners.
function GetMinimapShape()
    return "SQUARE"
end
tick()
assert(near(mini.point[5], 70) and near(mini.point[4], -10 / 34 * 70))
GetMinimapShape = nil
T.zoom, T.indoors = 0, false

-- A rotating minimap: facing west, the step 10 yards west is straight up.
T.px, T.py = 0.492, 0.429
T.cvars.rotateMinimap = "1"
T.facing = math.pi / 2
tick()
assert(near(mini.point[4], 0) and near(mini.point[5], 10 / 233.33 * 70))
T.cvars.rotateMinimap, T.facing = "0", 0
T.px, T.py = 0.492, 0.463
tick()

-- A refresh that leaves the step alone places nothing again.
world.point, mini.point = nil, nil
ns.Refresh()
tick()
assert(world.point == nil and mini.point == nil)

-- The pins follow the step.
T.log[783] = {}
fire("QUEST_ACCEPTED", 783)
assert(ns.Steps:CurrentIndex() == 2 and near(world.point[4], 489) and mini.point)
world.scripts.OnEnter(world)
assert(GameTooltip.text == "Marshal McBride")

-- /lvl pin switches both off and on.
cmd("pin")
assert(ns.db.pin == false and not world.shown and not mini.shown)
T.px = 0.5
tick()
assert(not mini.shown, "nothing follows the player while the pins are off")
T.px = 0.492
cmd("pin")
assert(ns.db.pin and world.shown and mini.shown)

-- Hidden with the rest of the addon.
cmd("hide")
assert(not world.shown and not mini.shown)
cmd("show")
assert(world.shown and mini.shown)

-- No position where the game gives none (an instance).
local unitPosition = UnitPosition
function UnitPosition() end
tick()
assert(not mini.shown)
UnitPosition = unitPosition
tick()
assert(mini.shown)

-- TomTom has the waypoint and draws its own icons: none of ours.
TomTom = {
    AddWaypoint = function()
        return 1
    end,
    RemoveWaypoint = function() end,
}
ns.Refresh()
assert(not world.shown and not mini.shown)
TomTom = nil
ns.Refresh()
assert(world.shown and mini.shown)

-- The route ends: nothing to pin.
for _, q in ipairs({ 783, 7, 33, 15, 18, 21 }) do
    T.completed[q] = true
end
fire("QUEST_LOG_UPDATE")
assert(ns.Steps:CurrentIndex() == nil and not world.shown and not mini.shown)

assert(#T.frames == created, "the pin frames are made once")
print("ALL OK")
