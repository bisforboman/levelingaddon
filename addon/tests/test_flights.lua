-- Flights: the tooltip time for a direct and a multi-hop route, the timer counting down and
-- stopping, a measured flight correcting the next estimate, nothing drawn when another flight
-- timer is loaded, the flight points the character knows, and the suggested flight taken when
-- the flight map opens.
-- From the repository root: lua5.1 addon/tests/test_flights.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick = T.ns, T.fire, T.tick

-- The flight map of an Alliance character at Stormwind: Sentinel Hill and Lakeshire are known
-- and one flight away, Darkshire is known and reached through Sentinel Hill, Booty Bay is not
-- discovered, and one button is a point the data does not have.
local map = {
    { name = "Stormwind, Elwynn", kind = "CURRENT", x = 0.5, y = 0.5 },
    { name = "Sentinel Hill, Westfall", kind = "REACHABLE", x = 0.4, y = 0.3 },
    { name = "Lakeshire, Redridge", kind = "REACHABLE", x = 0.7, y = 0.4 },
    { name = "Darkshire, Duskwood", kind = "REACHABLE", x = 0.6, y = 0.2, via = { 1, 2, 4 } },
    { name = "Booty Bay, Stranglethorn", kind = "NONE", x = 0.3, y = 0.1 },
    { name = "Somewhere New", kind = "REACHABLE", x = 0.9, y = 0.9 },
}
local onTaxi, loadedAddons, routes = false, {}, true
function NumTaxiNodes()
    return #map
end
function TaxiNodeName(slot)
    return map[slot].name
end
function TaxiNodeGetType(slot)
    return map[slot].kind
end
function TaxiNodePosition(slot)
    return map[slot].x, map[slot].y
end
local function via(slot)
    return map[slot].via or { 1, slot }
end
function GetNumRoutes(slot)
    return routes and #via(slot) - 1 or 0
end
function TaxiGetSrcX(slot, leg)
    return map[via(slot)[leg]].x
end
function TaxiGetSrcY(slot, leg)
    return map[via(slot)[leg]].y
end
function TaxiGetDestX(slot, leg)
    return map[via(slot)[leg + 1]].x
end
function TaxiGetDestY(slot, leg)
    return map[via(slot)[leg + 1]].y
end
function GetTaxiMapID()
    return 1415
end
C_TaxiMap = {
    GetAllTaxiNodes = function()
        return nil -- this client names the points only; the ids come from the names
    end,
}
function UnitOnTaxi()
    return onTaxi
end
function IsAddOnLoaded(name)
    return loadedAddons[name] or false
end
local taken, shiftDown = {}, false -- the flights asked for, by button; Shift as the map opens
function TakeTaxiNode(slot)
    taken[#taken + 1] = slot
end
function IsShiftKeyDown()
    return shiftDown
end
function TaxiNodeOnButtonEnter() end
local tooltip = {}
function GameTooltip:AddLine(text)
    tooltip[#tooltip + 1] = text
end
local function hover(slot)
    tooltip = {}
    TaxiNodeOnButtonEnter({
        GetID = function()
            return slot
        end,
    })
    return tooltip[1]
end

T.load()
ns.Steps.list = dofile("addon/tests/northshire.lua") -- a fixed route; no planner data, so no planning
-- Cut from a real export. Booty Bay has a point per side; the flight to Darkshire has no
-- measured time in the source.
ns.Data = {
    taxiNodes = {
        [2] = { name = "Stormwind, Elwynn", faction = "Alliance", map = 0, x = -8832.77, y = 478.623 },
        [4] = { name = "Sentinel Hill, Westfall", faction = "Alliance", map = 0, x = -10628.89, y = 1036.68 },
        [5] = { name = "Lakeshire, Redridge", faction = "Alliance", map = 0, x = -9429.1, y = -2231.4 },
        [12] = { name = "Darkshire, Duskwood", faction = "Alliance", map = 0, x = -10515.46, y = -1261.65 },
        [18] = { name = "Booty Bay, Stranglethorn", faction = "Horde", map = 0, x = -14444.29, y = 509.62 },
        [19] = { name = "Booty Bay, Stranglethorn", faction = "Alliance", map = 0, x = -14473.05, y = 464.15 },
    },
    taxiPaths = {
        [2] = { to = { [4] = 78, [5] = 113 } },
        [4] = { to = { [2] = 86, [12] = 100, [19] = 150 }, est = { [12] = true } },
        [5] = { to = { [2] = 113, [12] = 60 } },
        [12] = { to = { [4] = 95, [5] = 62 } },
        [19] = { to = { [12] = 140 } },
    },
}
T.login()
local A, saved = ns.Arrow, ns.char.flights
assert(ns.db.flightTimer == true, "the timer is on by default")
assert(ns.db.autoFlight == true, "taking the suggested flight is on by default")
assert(A.frame.shown and T.looping(), "the arrow points at the first step")

-- Nothing is known before the flight map has been opened, and hovering does nothing.
assert(next(saved.known) == nil and hover(2) == nil)

-- The flight map opens: the known points are remembered, by node id, for this side.
fire("TAXIMAP_OPENED")
assert(saved.known[2] and saved.known[4] and saved.known[5] and saved.known[12], "the four known points")
assert(not saved.known[19] and not saved.known[18], "an undiscovered point is not known")
local count = 0
for _ in pairs(saved.known) do
    count = count + 1
end
assert(count == 4, "a point the data does not have is left out")

-- The tooltip: a direct flight, and a route through another point as the game says it flies.
assert(hover(2) == "Flight time: about 1:18", hover(2))
assert(hover(3) == "Flight time: about 1:53", hover(3))
assert(hover(4) == "Flight time: about 2:58", "78 + 100 through Sentinel Hill: " .. tostring(hover(4)))
assert(hover(1) == nil and hover(5) == nil and hover(6) == nil, "not where the character is, nor an unknown point")
-- Where the client does not say which way a flight goes, the quickest way over the table is
-- taken: through Lakeshire, 113 + 60.
routes = false
assert(hover(4) == "Flight time: about 2:53", hover(4))
assert(hover(2) == "Flight time: about 1:18", hover(2))
-- A point the character does not know is not flown through.
saved.known[5] = nil
assert(hover(4) == "Flight time: about 2:58", hover(4))
saved.known[5] = true
routes = true

-- Taking the flight: the arrow's frame shows the time left and where to, and the arrow rests.
local shownTime, shownName, sets = nil, nil, 0
local setFlight = A.SetFlight
function A:SetFlight(time, name)
    shownTime, shownName, sets = time, name, sets + 1
    return setFlight(self, time, name)
end
local function fly(seconds, step)
    for _ = 1, seconds / (step or 0.2) do
        T.now = T.now + (step or 0.2)
        tick(step or 0.2)
    end
end
T.now = 100
hover(2)
TakeTaxiNode(2)
assert(shownTime == nil, "nothing before the flight has begun")
fire("PLAYER_CONTROL_LOST")
onTaxi = true
tick(0.2)
assert(shownTime == "1:18" and shownName == "Sentinel Hill", tostring(shownTime) .. " " .. tostring(shownName))
assert(A.frame.shown and A.flightTime.text == "1:18" and A.flightName.text == "Sentinel Hill")
assert(not A.texture.shown and not A.ring.shown, "no arrow in flight")
fly(10)
assert(shownTime == "1:08", shownTime)
assert(sets <= 12, "the frame is handed a text only when it changes: " .. sets)
fly(52.4)
assert(shownTime == "0:16", shownTime)

-- Landing after 62.4 seconds, 80% of the listed 78: the timer stops and the arrow is back.
onTaxi = false
fire("PLAYER_CONTROL_GAINED")
assert(shownTime == nil and A.flight == nil and A.flightTime.text == "", "the timer is gone")
assert(A.frame.shown and T.looping(), "the arrow points again")
tick(0.1)
assert(A.texture.shown, "and is drawn again")
sets = 0
fly(2, 0.1)
assert(sets == 0, "the flight task is off")

-- The measured flight corrects what comes next: that route is now exact, and the others are
-- scaled by what this character's flights take.
assert(math.abs(saved.times[2][4] - 62.4) < 0.01, saved.times[2][4])
assert(hover(2) == "Flight time: 1:02", hover(2))
assert(hover(3) == "Flight time: about 1:30", "113 * 0.8: " .. tostring(hover(3)))
assert(hover(4) == "Flight time: about 2:22", "62.4 + 100 * 0.8: " .. tostring(hover(4)))
T.chat = {}
T.cmd("flights")
assert(
    T.chat[1]:find("flight points known: 4. Flights timed: 1.", 1, true) and T.chat[2]:find("80%% of the listed time"),
    T.chat[1]
)

-- A route through another point is timed as a whole, and does not change the scale: it has no
-- landing in the middle, and one of its flights has only an estimated time in the table.
hover(4)
TakeTaxiNode(4)
fire("PLAYER_CONTROL_LOST")
onTaxi = true
tick(0.2)
assert(shownTime == "2:22" and shownName == "Darkshire", shownTime)
fly(150)
onTaxi = false
tick(0.2) -- no event this time: the task sees the landing itself
assert(shownTime == nil and A.flight == nil)
assert(math.abs(saved.times[2][12] - 150) < 0.01, saved.times[2][12])
assert(hover(4) == "Flight time: 2:30", hover(4))
assert(math.abs(saved.flown / saved.listed - 0.8) < 0.001, "the scale is unchanged")

-- With another addon's flight timer loaded ours is not drawn; the flight is still timed.
loadedAddons.EllesmereUIForeverEssentials = true
sets = 0
hover(3)
TakeTaxiNode(3)
fire("PLAYER_CONTROL_LOST")
onTaxi = true
fly(90)
assert(sets == 0 and A.flight == nil and A.flightTime.text == "", "nothing of ours is drawn")
assert(hover(3) == "Flight time: about 1:30", "the tooltip is still ours")
onTaxi = false
fire("PLAYER_CONTROL_GAINED")
assert(math.abs(saved.times[2][5] - 90) < 0.3, saved.times[2][5])
loadedAddons.EllesmereUIForeverEssentials = nil

-- The setting switches the timer off, in the middle of a flight too.
TakeTaxiNode(2)
fire("PLAYER_CONTROL_LOST")
onTaxi = true
fly(1)
assert(shownTime == "1:01", shownTime)
ns.Set("flightTimer", false)
assert(shownTime == nil and A.flight == nil, "switched off at once")
fly(1)
ns.Set("flightTimer", true)
assert(shownTime == "1:00", shownTime)
fly(1)
assert(shownTime == "0:59", shownTime)
-- Hidden with the window, and back with it.
T.cmd("hide")
assert(not A.frame.shown)
T.cmd("show")
assert(A.frame.shown and not A.texture.shown and A.flightTime.text == "0:59")
-- A flight that ends far too early (a disconnect, a stop on the way) is not kept as its time.
onTaxi = false
fire("PLAYER_CONTROL_GAINED")
assert(math.abs(saved.times[2][4] - 62.4) < 0.01, "the earlier time stands")

-- Losing control for another reason is not a flight: no timer, nothing measured.
sets = 0
fire("PLAYER_CONTROL_LOST") -- a fear, with no flight asked for
assert(sets == 0 and not T.looping() == not A.frame.shown)
TakeTaxiNode(3) -- asked for, but the game refused (no money): control is lost much later
T.now = T.now + 60
fire("PLAYER_CONTROL_LOST")
fire("PLAYER_CONTROL_GAINED")
assert(sets == 0, "too long after the request")
TakeTaxiNode(3) -- asked for, then feared at once and never in the air
fire("PLAYER_CONTROL_LOST")
fly(4)
assert(shownTime == nil, "given up after a few seconds on the ground")
sets = 0
fly(2, 0.1)
assert(sets == 0)

-- A flight with no time in the data counts up, and is timed for the next one.
ns.Data.taxiPaths[2].to[5], saved.times[2][5] = nil, nil
saved.known[4], saved.known[12] = nil, nil
routes = false
assert(hover(3) == nil, "no time, no line")
routes = true
TakeTaxiNode(3)
fire("PLAYER_CONTROL_LOST")
onTaxi = true
fly(65)
assert(shownTime == "+1:05" and shownName == "Lakeshire", shownTime)
onTaxi = false
fire("PLAYER_CONTROL_GAINED")
assert(hover(3) == "Flight time: 1:05", hover(3))

-- Another character starts with nothing known and nothing timed: both are saved per character.
assert(LevelingAddonCharDB.flights == saved and LevelingAddonDB.flights == nil)

-- For the arrow: the flight point to walk to for a step on another map. The stub's world is
-- one 1000 x 1000 yard map whose middle is at (-500, -500); the character stands at
-- (-100, -100).
local function world(id, x, y, uiMapId)
    local node = ns.Data.taxiNodes[id]
    node.map, node.x, node.y, node.uiMapId, node.mapX, node.mapY = 0, x, y, uiMapId, 40 + id, 50 + id
end
world(2, -110, -110, 1453) -- Stormwind: beside the character
world(4, -150, -150, 1436) -- Sentinel Hill: a little further
world(5, -510, -510, 1433) -- Lakeshire: nearest the middle of the map asked about
world(12, 9000, 9000, 1431)
world(19, 9000, 9000)
world(18, -505, -505) -- the other side's
ns.Data.taxiPaths[2].to[5] = 113
T.px, T.py = 0.1, 0.1
saved.known = { [2] = true, [4] = true, [5] = true }
local point = ns.Flights.PointTowards(1433)
assert(point and point.name == "Stormwind, Elwynn" and point.map == 1453, "walk to the nearest point with a route")
assert(point.x == 42 and point.y == 52, "the flight master's place, in map percent")
-- Without Stormwind the next nearest is Sentinel Hill, which has no direct flight to Lakeshire:
-- it counts only once Darkshire, the point on the way, is known.
saved.known[2] = nil
assert(ns.Flights.PointTowards(1433) == nil, "no known route, no point")
saved.known[12] = true
assert(ns.Flights.PointTowards(1433).name == "Sentinel Hill, Westfall")
-- Standing at the point nearest the destination: nothing to walk to.
saved.known = { [5] = true, [2] = true }
T.px, T.py = 0.51, 0.51
assert(ns.Flights.PointTowards(1433) == nil)
T.px, T.py = 0.1, 0.1
-- With no point known yet, all points of the character's side count, and none of the other's.
saved.known = {}
assert(ns.Flights.PointTowards(1433).name == "Stormwind, Elwynn")
-- A map the client has no world position for (an instance, another world) gives nothing.
local position = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function() end
assert(ns.Flights.PointTowards(1433) == nil)
C_Map.GetWorldPosFromMapPos = position
saved.known = { [2] = true, [5] = true }

-- The arrow (#5): when the planner chose the step's zone because a flight gets there soonest,
-- it points at the flight master to walk to, and at the step again after landing.
local step = ns.Steps:Current()
T.px, T.py = 0.1, 0.1
ns.Planner.byFlight = step.map
A:StepChanged()
assert(#A.target == 1 and A.target.map == 1453, "the arrow points at the flight master")
assert(math.abs(A.target[1].x + 520) < 0.01 and math.abs(A.target[1].y + 420) < 0.01, "at its own place")
-- A ghost is still shown the way to the corpse.
T.ghost, T.corpse = true, { 0.5, 0.5 }
A:StepChanged()
assert(A.target and A.target.map ~= 1453, "the corpse comes before the flight master")
T.ghost, T.corpse = false, nil
A:StepChanged()
assert(A.target.map == 1453)
-- A current step in another zone than the one flown to (a vendor on the way) is not detoured.
ns.Planner.byFlight = 1433
A:StepChanged()
assert(A.target.map == step.map, "only steps in the zone flown to are detoured")
-- Landed at the point nearest the zone: the step itself.
ns.Planner.byFlight = step.map
A:StepChanged()
assert(A.target.map == 1453)
T.px, T.py = 0.51, 0.51
A:StepChanged()
assert(A.target.map == step.map, "after landing the arrow points at the step")
ns.Planner.byFlight = nil
T.px, T.py = 0.492, 0.463
A:StepChanged()

-- The suggested flight (#78): the planner names the flight point the steps are reached by, and
-- the flight map takes it when it opens, from whichever flight master this is.
local function open()
    taken, T.chat = {}, {}
    fire("TAXIMAP_OPENED")
    return table.concat(taken, " ")
end
assert(open() == "", "no flight suggested, none taken")
ns.Planner.flightTo = 12 -- Darkshire: button 4
assert(open() == "4", "the suggested flight is taken")
assert(T.chat[1]:find("taking the suggested flight to Darkshire. Hold Shift", 1, true), T.chat[1])
-- Shift as the map opens: the player chooses.
shiftDown = true
assert(open() == "" and #T.chat == 0, "Shift: nothing taken")
-- The setting off: nothing, unless Shift is held.
ns.Set("autoFlight", false)
shiftDown = false
assert(open() == "")
shiftDown = true
assert(open() == "4", "off, with Shift: taken")
shiftDown = false
ns.Set("autoFlight", true)
-- Not a point this map can fly to: not discovered, or where the character stands.
ns.Planner.flightTo = 19 -- Booty Bay, not discovered
assert(open() == "")
ns.Planner.flightTo = 2 -- Stormwind, the point the map was opened at
assert(open() == "")
map[4].kind = "UNREACHABLE"
ns.Planner.flightTo = 12
assert(open() == "", "a point the game says cannot be reached")
map[4].kind = "REACHABLE"
ns.Planner.flightTo = nil

-- A client without the flight map's functions, or without flight data, raises no error.
ns.Data.taxiNodes = nil
fire("TAXIMAP_OPENED")
assert(hover(2) == nil)
TakeTaxiNode(2)
fire("PLAYER_CONTROL_LOST")
fire("PLAYER_CONTROL_GAINED")
print("ALL OK")
