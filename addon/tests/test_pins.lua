-- The world-map and minimap pin for the current step, and the numbered world-map pins for the
-- places after it: where they are put, which steps share a pin, when they are placed again,
-- the setting, and standing back when TomTom has the waypoint.
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
local later = {} -- the numbered pins, in the order they were made
for i = before + 1, #T.frames do
    local f = T.frames[i]
    if f.parent == T.canvas and not world then
        world = f
    elseif f.parent == T.canvas then
        later[#later + 1] = f
    elseif f.parent == Minimap then
        mini = f
    end
end
assert(world and mini, "one pin on the world map canvas and one on the minimap")
assert(#later == 3, "and three for the places after the current step")
local lines = {} -- what a tooltip lists under its first line
rawset(GameTooltip, "AddLine", function(_, text)
    lines[#lines + 1] = text
end)
local function tooltip(pin)
    lines = {}
    pin.scripts.OnEnter(pin)
    return GameTooltip.text .. (lines[1] and ", " .. table.concat(lines, ", ") or "")
end
local function laterShown()
    return (later[1].shown and 1 or 0) + (later[2].shown and 1 or 0) + (later[3].shown and 1 or 0)
end
local created = #T.frames

-- Step 1 is Deputy Willem at 48.2, 42.9 on map 1429, which the world map shows.
assert(world.shown and near(world.point[4], 482) and near(world.point[5], -257.4))
world.scripts.OnEnter(world)
assert(GameTooltip.text == "Deputy Willem" and GameTooltip.shown)
world.scripts.OnLeave(world)
assert(not GameTooltip.shown)

-- The next three places have a numbered pin each. Steps within 2 percent of the map share a
-- pin: Marshal McBride stands by Deputy Willem, and the two kobold steps are side by side.
-- The fifth place of the route, the bandanas, has none yet.
assert(tooltip(world) == "Deputy Willem, Marshal McBride")
assert(tooltip(mini) == "Deputy Willem, Marshal McBride")
assert(later[1].shown and near(later[1].point[4], 489) and near(later[1].point[5], -241.2))
assert(tooltip(later[1]) == "Eagan Peltskinner")
assert(later[2].shown and near(later[2].point[4], 462) and tooltip(later[2]) == "Tough Wolf Meat")
assert(later[3].shown and near(later[3].point[4], 492) and tooltip(later[3]) == "Kobold Vermin, Kobold Worker")
assert(later[1].alpha == 0.7 and world.alpha == 1, "later pins are fainter")

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
assert(laterShown() == 3 and near(later[1].point[4], 494.5))
T.mapID = 99
WorldMapFrame:OnMapChanged()
assert(not world.shown and laterShown() == 0)
T.mapID = nil -- the map has not been opened yet
WorldMapFrame:OnMapChanged()
assert(not world.shown and laterShown() == 0)
T.mapID = 1429
WorldMapFrame:OnMapChanged()
assert(world.shown and laterShown() == 3)

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
world.point, mini.point, later[1].point = nil, nil, nil
ns.Refresh()
tick()
assert(world.point == nil and mini.point == nil and later[1].point == nil)

-- The pins follow the step.
T.log[783] = {}
fire("QUEST_ACCEPTED", 783)
assert(ns.Steps:CurrentIndex() == 2 and near(world.point[4], 489) and mini.point)
-- Eagan Peltskinner stands near enough to Marshal McBride to share the current pin.
assert(tooltip(world) == "Marshal McBride, Eagan Peltskinner, Deputy Willem")
assert(tooltip(later[1]) == "Tough Wolf Meat" and tooltip(later[3]) == "Red Burlap Bandana")

-- A skipped quest's steps are not pinned: without Eagan's quest the kobolds come first, and
-- the last kobolds of the route get the third pin.
ns.Steps:Skip(4)
ns.Refresh()
assert(tooltip(world) == "Marshal McBride, Deputy Willem")
assert(tooltip(later[1]) == "Kobold Vermin, Kobold Worker" and tooltip(later[2]) == "Red Burlap Bandana")
assert(tooltip(later[3]) == "Kobold Laborer")
ns.Steps:RestoreQuest(33)
ns.Refresh()
assert(tooltip(later[1]) == "Tough Wolf Meat")

-- /lvl pin switches both off and on.
cmd("pin")
assert(ns.db.pin == false and not world.shown and not mini.shown and laterShown() == 0)
T.px = 0.5
tick()
assert(not mini.shown, "nothing follows the player while the pins are off")
T.px = 0.492
cmd("pin")
assert(ns.db.pin and world.shown and mini.shown and laterShown() == 3)

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
assert(not world.shown and not mini.shown and laterShown() == 0)
TomTom = nil
ns.Refresh()
assert(world.shown and mini.shown)

-- Near the end of the route fewer places are left, and the pins left over are hidden.
for _, q in ipairs({ 783, 7, 33, 15, 18 }) do
    T.completed[q] = true
end
fire("QUEST_LOG_UPDATE")
assert(tooltip(world) == "Marshal McBride" and tooltip(later[1]) == "Kobold Laborer" and laterShown() == 1)

-- The route ends: nothing to pin.
for _, q in ipairs({ 783, 7, 33, 15, 18, 21 }) do
    T.completed[q] = true
end
fire("QUEST_LOG_UPDATE")
assert(ns.Steps:CurrentIndex() == nil and not world.shown and not mini.shown and laterShown() == 0)

assert(#T.frames == created, "the pin frames are made once")
print("ALL OK")
