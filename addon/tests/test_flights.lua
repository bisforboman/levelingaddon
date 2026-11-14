-- Flights: the tooltip time for a direct and a multi-hop route, the timer counting down and
-- stopping, a measured flight correcting the next estimate, nothing drawn when another flight
-- timer is loaded, and the flight points the character knows.
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
function TakeTaxiNode() end
function TaxiNodeOnButtonEnter() end
-- The game's own: hooks a global function by its name.
function hooksecurefunc(name, hook)
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        hook(...)
    end
end
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
fly(1)
assert(shownTime == nil and A.flight == nil, "switched off at once")
ns.Set("flightTimer", true)
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

-- A client without the flight map's functions, or without flight data, raises no error.
ns.Data.taxiNodes = nil
fire("TAXIMAP_OPENED")
assert(hover(2) == nil)
TakeTaxiNode(2)
fire("PLAYER_CONTROL_LOST")
fire("PLAYER_CONTROL_GAINED")
print("ALL OK")
