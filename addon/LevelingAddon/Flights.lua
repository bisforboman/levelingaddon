-- Flights (#16): the flight time on the flight map's tooltip, the time left and the destination
-- in the arrow's place while flying, and which flight points the character knows. The client
-- reports no flight time, so times come from the collector's tables (ns.Data.taxiNodes and
-- taxiPaths, README "Flights") and are corrected by what this character's own flights took.
-- Everything here happens on the flight map's events; the one task runs only during a flight.
local _, ns = ...

ns.defaults.flightTimer = true
ns.AddSetting({
    key = "flightTimer",
    label = "Flight timer",
    tooltip = "While flying, show the time left and the destination where the arrow is.",
})
-- Per character: a perk makes one character's flights faster than another's.
ns.charDefaults.flights = {
    known = {}, -- [taxi node id] = true for the flight points seen as known on the flight map
    times = {}, -- [from][to] = seconds this character's last flight from one point to another took
    flown = 0, -- seconds of this character's measured direct flights, and what the table lists
    listed = 0, -- for the same flights: flown / listed scales the times not yet measured
}

local Flights = {}
ns.Flights = Flights

-- Another addon's flight timer; ours is not drawn while it is loaded.
local OTHER_TIMER = "EllesmereUIForeverEssentials"
local TAKE_OFF = 5 -- seconds within which losing control after asking for a flight is the take-off
local NOT_A_FLIGHT = 3 -- seconds without control and not on a taxi: it was something else

local slots = {} -- [button on the open flight map] = taxi node id
local here -- the taxi node the flight map was opened at
local hovered -- what the tooltip last showed: { slot, seconds, measured }
local pending -- the flight asked for: { from, to, name, seconds, at }
local flight -- the flight under way: the same table, with `lost` (when control was lost)

local function clock(seconds)
    seconds = math.floor(seconds + 0.5)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Seconds for one direct flight: the character's own measurement, else the table's time scaled
-- by how this character's flights have compared with the table so far.
local function hopSeconds(from, to)
    local saved = ns.char.flights
    local own = saved.times[from] and saved.times[from][to]
    local row = ns.Data and ns.Data.taxiPaths and ns.Data.taxiPaths[from]
    local listed = row and row.to[to]
    return own or listed and listed * (saved.listed > 0 and saved.flown / saved.listed or 1)
end

-- The quickest way over the table from one point to another. As in the game, a flight passes
-- only through points the character knows.
local function shortest(from, to)
    local paths = ns.Data and ns.Data.taxiPaths
    local known = ns.char.flights.known
    local best, done = { [from] = 0 }, {}
    while paths do
        local at, least
        for id, seconds in pairs(best) do
            if not done[id] and (not least or seconds < least) then
                at, least = id, seconds
            end
        end
        if not at or at == to then
            return at and least
        end
        done[at] = true
        for nextId in pairs((at == from or known[at]) and paths[at] and paths[at].to or {}) do
            local seconds = least + hopSeconds(at, nextId)
            if not best[nextId] or seconds < best[nextId] then
                best[nextId] = seconds
            end
        end
    end
end

-- Seconds from one flight point to another, and whether this character has flown and timed
-- that very route. `hops` are the points the game will pass, in order from `from`, where the
-- client says; without them the quickest way over the table is taken.
function Flights.Seconds(from, to, hops)
    local times = ns.char.flights.times
    if times[from] and times[from][to] then
        return times[from][to], true
    end
    local total = hops and hops[2] and 0
    for i = 2, total and #hops or 0 do
        local seconds = hopSeconds(hops[i - 1], hops[i])
        total = seconds and total and total + seconds
    end
    return total or shortest(from, to), false
end

-- The points the game will fly through to the button `slot`, as node ids starting where the
-- character is. The client gives each leg's ends as positions on the flight map; they are
-- matched to the buttons' own positions. Nil where the client does not say.
local function gameHops(slot)
    if not (GetNumRoutes and TaxiGetSrcX and TaxiGetSrcY and TaxiGetDestX and TaxiGetDestY and TaxiNodePosition) then
        return nil
    end
    local function nodeAt(x, y)
        for other, id in pairs(slots) do
            local ox, oy = TaxiNodePosition(other)
            if x and y and ox and oy and math.abs(ox - x) < 0.002 and math.abs(oy - y) < 0.002 then
                return id
            end
        end
    end
    local hops = {}
    for leg = 1, math.min(GetNumRoutes(slot) or 0, 20) do
        local from = nodeAt(TaxiGetSrcX(slot, leg), TaxiGetSrcY(slot, leg))
        local to = nodeAt(TaxiGetDestX(slot, leg), TaxiGetDestY(slot, leg))
        if not (from and to) or (hops[leg] or from) ~= from then
            return nil
        end
        hops[leg], hops[leg + 1] = from, to
    end
    return hops[1] == here and hops[#hops] == slots[slot] and hops or nil
end

-- The time to the button's flight point, for the tooltip and the timer.
local function estimate(slot)
    local seconds, measured = Flights.Seconds(here, slots[slot], gameHops(slot))
    return { slot = slot, seconds = seconds, measured = measured }
end

-- The flight map has opened: note which button is which flight point, where the character
-- is, and which points the character knows. The node id comes from C_TaxiMap where the client
-- has it, else from the name the button shows (which only matches in English).
local function readMap()
    wipe(slots)
    here, hovered = nil, nil
    local nodes = ns.Data and ns.Data.taxiNodes
    if not (nodes and NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then
        return
    end
    local side = UnitFactionGroup("player")
    local byName = {}
    for id, node in pairs(nodes) do
        if not node.faction or node.faction == side then
            byName[node.name] = id
        end
    end
    local ids = {}
    local ok, all = pcall(function()
        return C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())
    end)
    for _, node in ipairs(ok and type(all) == "table" and all or {}) do
        ids[node.slotIndex or 0] = node.nodeID
    end
    local known = ns.char.flights.known
    for slot = 1, NumTaxiNodes() or 0 do
        local kind = TaxiNodeGetType(slot)
        local id = nodes[ids[slot]] and ids[slot] or byName[TaxiNodeName(slot)]
        if id and kind ~= "NONE" then -- "NONE": a point the character has not discovered
            slots[slot] = id
            known[id] = true
            if kind == "CURRENT" then
                here = id
            end
        end
    end
end
ns.On("TAXIMAP_OPENED", readMap)

-- After the game has filled the tooltip of a flight map button: one more line.
local function onButtonEnter(button)
    local slot = button and button.GetID and button:GetID()
    if not (here and slots[slot]) or slots[slot] == here or TaxiNodeGetType(slot) ~= "REACHABLE" then
        return
    end
    hovered = estimate(slot)
    if hovered.seconds then
        local text = (hovered.measured and "" or "about ") .. clock(hovered.seconds)
        GameTooltip:AddLine("Flight time: " .. text, 0.95, 0.76, 0.19)
        GameTooltip:Show()
    end
end

-- After the game was asked for a flight. The estimate the tooltip just showed is used where
-- there is one: what the client says about routes may not outlive the request.
local function onTake(slot)
    pending = nil
    if here and slots[slot] and slots[slot] ~= here then
        local known = hovered and hovered.slot == slot and hovered or estimate(slot)
        local name = TaxiNodeName(slot) or ns.Data.taxiNodes[slots[slot]].name
        pending = { from = here, to = slots[slot], name = name, seconds = known.seconds, at = GetTime() }
    end
end

ns.On("PLAYER_LOGIN", function()
    if TakeTaxiNode then
        hooksecurefunc("TakeTaxiNode", onTake)
    end
    if TaxiNodeOnButtonEnter then
        hooksecurefunc("TaxiNodeOnButtonEnter", onButtonEnter)
    end
end)

local function otherTimer()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded(OTHER_TIMER) and true or false
end

local function stop()
    flight = nil
    ns.SetTask("flight", false)
    ns.Arrow:SetFlight(nil)
end

-- Landed: keep what the flight took, for this route and, if it was one direct flight with a
-- measured time in the table, for scaling the times not flown yet. A flight that took far from
-- what was expected did not end where it should have, and is not kept.
local function land()
    local done, took = flight, GetTime() - flight.lost
    stop()
    if not done.air or (done.seconds and (took < done.seconds * 0.5 or took > done.seconds * 1.5)) then
        return
    end
    local saved = ns.char.flights
    saved.times[done.from] = saved.times[done.from] or {}
    saved.times[done.from][done.to] = math.floor(took * 10 + 0.5) / 10
    local row = ns.Data.taxiPaths and ns.Data.taxiPaths[done.from]
    if row and row.to[done.to] and not (row.est and row.est[done.to]) then
        saved.flown, saved.listed = saved.flown + took, saved.listed + row.to[done.to]
    end
end

ns.On("PLAYER_CONTROL_LOST", function()
    if pending and GetTime() - pending.at <= TAKE_OFF then
        flight, pending = pending, nil
        flight.lost = GetTime()
        ns.SetTask("flight", true)
    end
end)

ns.On("PLAYER_CONTROL_GAINED", function()
    if flight then
        land()
    end
end)

-- During a flight: the time left, or the time flown where no time is known. The frame is
-- handed a new text only when the text changes, once a second.
ns.Task("flight", 0.2, function()
    local flown = GetTime() - flight.lost
    if UnitOnTaxi("player") then
        flight.air = true
    elseif flight.air then
        return land() -- landed without the event
    elseif flown > NOT_A_FLIGHT then
        return stop()
    end
    local text
    if ns.db.flightTimer and not otherTimer() then
        text = flight.seconds and clock(math.max(flight.seconds - flown, 0)) or "+" .. clock(flown)
    end
    if text ~= flight.text then
        flight.text = text
        ns.Arrow:SetFlight(text, flight.name:match("^[^,]+"))
    end
end)

function ns.commands.flights()
    local saved, known, timed = ns.char.flights, 0, 0
    for _ in pairs(saved.known) do
        known = known + 1
    end
    for _, row in pairs(saved.times) do
        for _ in pairs(row) do
            timed = timed + 1
        end
    end
    ns.say(string.format("flight points known: %d. Flights timed: %d.", known, timed))
    if saved.listed > 0 then
        local percent = math.floor(saved.flown / saved.listed * 100 + 0.5)
        ns.say("this character's flights take " .. percent .. "% of the listed time.")
    end
end
