-- The target macro: made only when the player asks, its text for each kind of step, the
-- length limit, nothing written in combat, and other people's macros left alone.
-- From the repository root: lua5.1 addon/tests/test_target.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd

-- The game's macros: [name] = text, and what the addon called.
local macros, count, calls, cursor = {}, 0, {}, nil
local function did()
    local text = table.concat(calls, ", ")
    calls = {}
    return text
end
function GetMacroIndexByName(name)
    return macros[name] and 1 or 0
end
function GetMacroBody(name)
    return macros[name]
end
function GetNumMacros()
    return count, 0
end
function CreateMacro(name, icon, body)
    assert(not T.combat, "a macro made in combat")
    assert(#name <= 16 and icon and #body <= 255)
    macros[name] = body
    calls[#calls + 1] = "create"
end
function EditMacro(name, _, _, body)
    assert(not T.combat, "a macro edited in combat")
    assert(macros[name] and #body <= 255)
    macros[name] = body
    calls[#calls + 1] = "edit"
end
function PickupMacro(name)
    cursor = name
end

T.load()
ns.Steps.list = dofile("addon/tests/northshire.lua") -- a fixed route; no quest data, so no planning
T.login()
local NAME = "LvlTarget"
local function plan(step)
    ns.Steps:SetPlan({ step })
    ns.Refresh()
end
local function said(text)
    return T.chat[#T.chat]:find(text, 1, true) ~= nil
end

-- Nothing is made before the player asks, whatever the steps do.
T.log[783] = {}
fire("QUEST_ACCEPTED", 783)
assert(ns.Steps:CurrentIndex() == 2 and did() == "" and next(macros) == nil)

-- A macro of that name that is not ours stays as it is.
macros[NAME] = "/dance"
cmd("macro")
assert(did() == "" and macros[NAME] == "/dance" and cursor == nil and said("did not make"))
T.completed[783] = true
fire("QUEST_TURNED_IN", 783)
assert(did() == "" and macros[NAME] == "/dance")
macros[NAME] = nil

-- No free slot: nothing is made.
count = 120
cmd("macro")
assert(did() == "" and macros[NAME] == nil and said("no free slot"))
count = 3

-- Asked for: made for the current step, an accept, and put on the cursor.
assert(ns.Steps:Current().kind == "accept")
cmd("macro")
assert(did() == "create" and cursor == NAME and ns.db.targetMacro)
assert(macros[NAME] == "/cleartarget\n/targetexact Marshal McBride\n/tm 8")

-- It follows the step; a refresh that leaves the step alone writes nothing.
T.log[7] = { need = 10, have = 0 }
fire("QUEST_ACCEPTED", 7)
assert(did() == "edit" and macros[NAME] == "/cleartarget\n/targetexact Eagan Peltskinner\n/tm 8")
ns.Refresh()
assert(did() == "")
-- Asking again hands the same macro over; none is made twice.
cursor = nil
cmd("macro")
assert(did() == "" and cursor == NAME)

-- Without quest data a kill step is named after its creature, and a loot step has no name.
plan({ kind = "kill", name = "Kobold Vermin", questID = 7, map = 1429, x = 49.2, y = 36.3 })
assert(macros[NAME] == "/cleartarget\n/targetexact Kobold Vermin\n/tm 8")
plan({ kind = "loot", name = "Tough Wolf Meat", questID = 33, map = 1429, x = 46.2, y = 46.5 })
assert(macros[NAME] == "")

-- With quest data: every creature of the objective, nearest the step's point first. Zone 12
-- is drawn on map 1429, zone 9 is part of zone 12, zone 40 is another map.
local npcs = {
    [1] = { name = "Far Councilman", spawns = { [12] = { 10, 10, 80, 80 } } },
    [2] = { name = "Near Councilman", spawns = { [9] = { 90, 90, 51, 50 } } },
    [3] = { name = "Elsewhere Councilman", spawns = { [40] = { 50, 50 } } },
    [4] = { name = "Middle Councilman", spawns = { [12] = { 55, 50 } } },
    [5] = { name = "Young Wolf", spawns = { [12] = { 46, 46 } } },
    [6] = { name = "Timber Wolf", spawns = { [12] = { 46.2, 46.5 } } },
    [7] = { name = "Kobold Vermin" },
    [8] = { name = "Meat Vendor", spawns = { [12] = { 20, 20 } } },
}
ns.Data = {
    npcs = npcs,
    objects = {},
    zones = { [12] = { uiMapId = 1429 }, [9] = { parentZoneId = 12 }, [40] = { uiMapId = 1436 } },
    items = {
        [750] = { name = "Tough Wolf Meat", npcDrops = { 5, 6 }, vendors = { 8 } },
        [751] = { name = "Long List", npcDrops = {} },
    },
    quests = {
        [452] = { objectives = { killCredits = { { npcIds = { 1, 2, 3, 4 }, text = "Pyrewood Council" } } } },
        [7] = { objectives = { npcs = { { id = 7 }, { id = 5 } } } },
        [33] = { objectives = { items = { { id = 750 }, { id = 751 } } } },
    },
}
plan({ kind = "kill", name = "Pyrewood Council", questID = 452, map = 1429, x = 50, y = 50 })
assert(
    macros[NAME]
        == "/cleartarget\n/targetexact Near Councilman\n/targetexact Middle Councilman\n"
            .. "/targetexact Far Councilman\n/targetexact Elsewhere Councilman\n/tm 8"
)
-- Only the step's own objective: the quest's other creature is not in it.
plan({ kind = "kill", name = "Kobold Vermin", questID = 7, map = 1429, x = 49.2, y = 36.3 })
assert(macros[NAME] == "/cleartarget\n/targetexact Kobold Vermin\n/tm 8")
-- A loot step: whatever drops or sells the item.
plan({ kind = "loot", name = "Tough Wolf Meat", questID = 33, map = 1429, x = 46.2, y = 46.5 })
assert(
    macros[NAME] == "/cleartarget\n/targetexact Timber Wolf\n/targetexact Young Wolf\n/targetexact Meat Vendor\n/tm 8"
)

-- The length limit: the nearest names that fit, and the marker still at the end.
for i = 1, 30 do
    npcs[100 + i] = { name = "Defias Dropper Number " .. i, spawns = { [12] = { 50 + i, 50 } } }
    ns.Data.items[751].npcDrops[i] = 100 + i
end
plan({ kind = "loot", name = "Long List", questID = 33, map = 1429, x = 50, y = 50 })
local text = macros[NAME]
assert(#text <= 255 and #text > 255 - 40, #text)
assert(text:find("Number 1\n", 1, true) and text:find("Number 6\n", 1, true) and not text:find("Number 7", 1, true))
assert(text:sub(1, 13) == "/cleartarget\n" and text:sub(-6) == "\n/tm 8")

-- In combat nothing is written, by a step change or by the command; it is written after.
did()
T.combat = true
plan({ kind = "turnin", name = "Marshal McBride", questID = 7, map = 1429, x = 48.9, y = 41.6 })
plan({ kind = "accept", name = "Deputy Willem", questID = 18, map = 1429, x = 48.2, y = 42.9 })
cursor = nil
cmd("macro")
assert(did() == "" and macros[NAME] == text and cursor == nil and said("combat"))
T.combat = false
fire("PLAYER_REGEN_ENABLED")
assert(did() == "edit" and macros[NAME] == "/cleartarget\n/targetexact Deputy Willem\n/tm 8")
fire("PLAYER_REGEN_ENABLED")
assert(did() == "")

-- A step with nothing to target, and the end of the route: a macro that does nothing.
plan({ kind = "go", name = "Echo Ridge Mine", questID = 15, map = 1429, x = 10, y = 10 })
assert(did() == "edit" and macros[NAME] == "")
plan({ kind = "accept", name = "Deputy Willem", questID = 18, map = 1429, x = 48.2, y = 42.9 })
assert(macros[NAME] ~= "")
ns.Steps:SetPlan({})
ns.Refresh()
assert(ns.Steps:Current() == nil and macros[NAME] == "")

-- Deleted by the player: not made again until asked for.
macros[NAME] = nil
did()
plan({ kind = "accept", name = "Deputy Willem", questID = 18, map = 1429, x = 48.2, y = 42.9 })
assert(did() == "" and macros[NAME] == nil and ns.db.targetMacro == false)
cmd("macro")
assert(did() == "create" and macros[NAME] == "/cleartarget\n/targetexact Deputy Willem\n/tm 8")

print("ALL OK")
