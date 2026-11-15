# In-game checks: flights (Flights)

None of this has been run in the game client yet. Tick each off in the game. `/lvl flights`
prints what the addon has remembered; `/lvl verbose` and `/lvl report` help with anything that
does not work.

The flight map

- [ ] Hovering a flight point that can be flown to adds a yellow line under the game's own
      tooltip: "Flight time: about 1:18". If no line appears on any point, the client's flight
      map does not call `TaxiNodeOnButtonEnter` (the classic flight map's function, hooked at
      login): say what the flight map looks like (the classic window with buttons, or the
      full-screen map with pins), since the second needs a different hook.
- [ ] No line on the point the character stands at, or on a point that cannot be flown to.
- [ ] After opening the flight map once, `/lvl flights` counts the flight points the character
      knows. The count should equal the points shown on the map of that continent, plus those
      seen on other continents before. If it is 0, the addon could not tell which button is
      which point: it takes the node id from `C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())`
      (`nodeID` and `slotIndex`), else matches `TaxiNodeName(slot)` to the English names in the
      data ("Stormwind, Elwynn"). Say what the tooltip calls a point, and the client language.
- [ ] Points the character has not discovered are not counted. The addon takes
      `TaxiNodeGetType(slot) == "NONE"` to mean "not discovered"; if undiscovered points are
      counted as known, that is wrong on this client.
- [ ] A flight through other points (one whose line on the map bends through another point):
      the time is close to the sum of the hops. The hops are read with `GetNumRoutes(slot)` and
      `TaxiGetSrcX/Y`, `TaxiGetDestX/Y`, matched to `TaxiNodePosition`; where that fails the
      quickest way over the table is used, which may be another way than the game flies.
- [ ] The four points with new flights in Forever (Rog'mar and Farholde Keep in Riverglades,
      and the two on Mount Hyjal) show a time; their 20 flights have estimated times in the
      data. Note how far off the first one is.
- [ ] A flight point the data does not have at all shows no line and raises no error. Note its
      name.

The timer

- [ ] On take-off the arrow's plate shows the time left, large and yellow, with the
      destination's name under it (the part before the comma), and no arrow. It counts down
      once a second.
- [ ] The plate is wide enough for the name, and stays centred where the arrow was.
- [ ] On landing the timer goes and the arrow comes back at once, pointing at the step.
- [ ] How close the first, unmeasured, time is: note the time shown on take-off and the time
      left on landing, for two or three flights. The table's times are InFlight's from Classic.
- [ ] With the "Frequent Flier" perk the first flights end early (about 20%); after one direct
      flight `/lvl flights` says about 80%, and the next unmeasured times are scaled by it.
- [ ] The same flight a second time shows its own measured time, without "about", and lands
      within a second or two of 0:00.
- [ ] The timer starts on take-off and not before: it waits for `PLAYER_CONTROL_LOST` within
      5 seconds of `TakeTaxiNode`, then for `UnitOnTaxi("player")`. If no timer ever shows, one
      of the three does not happen on this client; `/lvl report` after a flight helps.
- [ ] Refused flights (not enough money) show no timer, and a fear or a stun right after does
      not start one.
- [ ] `/reload` or a disconnect in the air: no timer for the rest of that flight, no error, and
      the flight is not measured.
- [ ] The setting "Flight timer" off: no timer, and the arrow is as it was before this feature
      (it keeps pointing at the step from the air). On again in the air: the timer shows.
- [ ] `/lvl hide` in the air hides it with the window; `/lvl` brings it back.
- [ ] With "Arrow" switched off, or with TomTom installed, the timer still shows in flight and
      nothing of ours shows on the ground.
- [ ] "Dim in combat" does not leave the timer dimmed after a fight that ended in the air.
- [ ] `/lvl debug` during a flight: the shared loop's time per frame is no higher than with
      the arrow on the ground.

Taking the suggested flight (#78)

- [ ] When the chat says "The next steps are in <zone>: fly from A to B", talking to the flight
      master at A takes the flight to B at once, and chat says "taking the suggested flight to
      B". The timer starts as for a flight clicked by hand. If the map stays open and nothing
      happens, or the game shows "action blocked", `TakeTaxiNode` cannot be called from the
      `TAXIMAP_OPENED` event on this client: note which, in #78.
- [ ] The same from another flight master than A, from which B can be reached: taken too.
- [ ] Shift held while right-clicking the flight master: the map stays open and nothing is
      taken. With "Take suggested flights automatically" off: nothing, unless Shift is held.
- [ ] With no flight suggested (the steps are near), opening the flight map takes nothing.
- [ ] Too little money for the flight: the game's own message, no error, and no timer.
- [ ] Note whether taking off as the map opens feels too sudden; the setting is on by default.

Ellesmere UI

- [ ] With Ellesmere UI's flight timer present, ours is not drawn (the arrow keeps pointing at
      the step, as before this feature). The addon looks for an addon named `EllesmereUIForeverEssentials`
      being loaded (`C_AddOns.IsAddOnLoaded`); if both timers show, give the folder name of
      the Ellesmere module that draws the timer.
- [ ] With Ellesmere UI installed but its flight timer switched off in its own settings, there
      is no timer at all (ours cannot see that switch). Say if that matters.
- [ ] Whether Ellesmere UI also adds a flight time to the flight map's tooltip. Ours is added
      either way; if there are two lines, say so.
- [ ] Flights are still measured with Ellesmere present: `/lvl flights` counts them.

Per character

- [ ] Another character on the same account starts with nothing known and nothing timed.

The planner

- [ ] Finish everything worth doing in a zone and its neighbours (or stand in a zone far below
      the character's level) with a few flight points known: the steps lead to a zone that
      fits the level and is quick to reach by flight, and one chat line names the flight:
      "nothing left to do around here. The next steps are in Duskwood: fly from Ironforge to
      Darkshire (about 4:10)."
- [ ] The line is said once, not on every quest event while the same flight is the way there.
- [ ] The flight named is one the flight master offers, and its start is the flight point
      nearest the character.
- [ ] With no flight points known (before the flight map was ever opened on this character)
      the steps are as before: the best-fitting zone, nearest first.
- [ ] The flight points are on the right continent: the planner takes a point's `map` (0 for
      the Eastern Kingdoms, 1 for Kalimdor) to be the continent id that
      `C_Map.GetWorldPosFromMapPos` returns, and its `x`, `y` to be in the same world yards.
      If flights are never suggested although points are known, one of the two differs.
- [ ] Say whether 7 yards a second (`RUN_SPEED` in `Planner.lua`) is a fair walking speed to
      hold a flight against, and whether the zone picked felt right. A mount is not known.
- [ ] The arrow points straight at the first step in the far zone, not at the flight master.
      Note whether a "take this flight" step is missed.

The data

- [ ] Flight masters: 61 of the 65 flight points carry the flight master QuestieDB has there
      (name and map position), linked by position. Nothing shows them yet; a "take this
      flight" step would use them. Spot-check a few in
      `addon/LevelingAddon/Data/taxiNodes-1.lua` against the game: the NPC named is the flight
      master standing at that point.
