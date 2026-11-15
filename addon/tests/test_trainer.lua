-- The "train" step (issue #17): a visit to the class trainer among the steps when the spells the
-- character could learn and pay for are worth the trip. A side task under the current step while
-- a trainer is near the way, the current step when a lot is waiting, skippable until the next
-- level, and over once a trainer window has been open. At the trainer, one line says what to buy.
-- From the repository root: lua5.1 addon/tests/test_trainer.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire = T.ns, T.fire

function UnitClass()
    return "Mage", "MAGE"
end
local raceId
function UnitRace()
    return "Human", "Human", raceId
end
local copper = 0
function GetMoney()
    return copper
end
local known = { [101] = true }
function IsPlayerSpell(id)
    return known[id] == true
end

-- A short spell list, in the shape Trainer.lua documents.
local SPELLS = {
    MAGE = {
        { id = 101, name = "Fireball", rank = 1, level = 1, cost = 10 },
        { id = 102, name = "Fireball", rank = 2, level = 6, cost = 100 },
        { id = 103, name = "Fireball", rank = 3, level = 12, cost = 600 },
        { id = 104, name = "Conjure Water", level = 4, cost = 100 },
        { id = 105, name = "Frost Nova", level = 6, cost = 200, key = true },
        { id = 106, name = "Arcane Missiles", level = 8, cost = 300, key = true },
    },
    WARRIOR = { { id = 201, name = "Charge", level = 4, cost = 100, key = true } },
}

-- South of Northshire's quest givers, as in test_sellstep.lua: one percent is 10 yards.
T.px, T.py = 0.482, 0.60
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", ns)
ns.Data.zones = { [12] = { uiMapId = 1429 } }
ns.Data.classSpells = SPELLS
ns.Data.npcs = {
    [1] = {
        name = "Near Mage",
        npcFlags = 16 + 2,
        subName = "Mage Trainer",
        friendlyTo = "A",
        spawns = { [12] = { 48.2, 75 } },
    },
    [2] = {
        name = "Horde Mage",
        npcFlags = 16,
        subName = "Mage Trainer",
        friendlyTo = "H",
        spawns = { [12] = { 48.2, 62 } },
    },
    [3] = {
        name = "Priest Nearby",
        npcFlags = 16,
        subName = "Priest Trainer",
        friendlyTo = "A",
        spawns = { [12] = { 48.2, 61 } },
    },
    [4] = {
        name = "Far Mage",
        npcFlags = 16,
        subName = "Mage Trainer",
        friendlyTo = "AH",
        spawns = { [12] = { -1, -1, 80, 60 } },
    },
    [5] = {
        name = "Mage Without Flag",
        npcFlags = 2,
        subName = "Mage Trainer",
        friendlyTo = "A",
        spawns = { [12] = { 48.2, 60.5 } },
    },
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
local function trainRow()
    for index, step in ipairs(S.list) do
        if step.kind == "train" and S:Status(index) == "pending" then
            return index
        end
    end
end
local function pass(event, ...)
    fire(event, ...)
    fire()
    fire() -- a debounced event, then the planner's own debounce
end
local function level(n)
    T.level = n
    pass("PLAYER_LEVEL_UP", n)
end
local function said()
    return T.chat[#T.chat] or ""
end

-- Level 1 with Fireball known: nothing new, no stop.
local first = current()
assert(first and first:find("^accept ") and not trainRow(), first)
assert(#ns.TrainSpells() == 0)

-- Level 6 and no money: two spells to learn, nothing affordable, so no stop.
level(6)
assert(not trainRow() and #ns.TrainSpells() == 3)
-- Enough for the two cheap ones: worth a stop on the way, under the current step, at the
-- side's mage trainer. The nearer trainers are the other side's, another class's, and an NPC
-- without the trainer flag.
copper = 250
pass("PLAYER_MONEY")
local index = S:CurrentIndex()
assert(current() == first and row(index + 1) == "train Near Mage", tostring(row(index + 1)))
assert(S.list[index + 1].questID == ns.TRAIN and S.list[index + 1].map == 1429 and S.list[index + 1].y == 75)
local _, weight, cost = ns.TrainSpells()
assert(weight == 2 and cost == 200, weight .. " " .. cost)

-- Money for the key spell too: the visit is the current step.
copper = 1000
pass("PLAYER_MONEY")
assert(current() == "train Near Mage", current())
assert(row(S:CurrentIndex() + 1) == first)

-- Skipped like any step, until the next level.
S:Skip(S:CurrentIndex())
assert(ns.char.skipped[ns.TRAIN] and current() == first and not trainRow())
pass("PLAYER_MONEY")
assert(not trainRow(), "a skip holds while the level does")

-- The next level brings the stop back; at the trainer the step is over and one line says what
-- to buy, cheapest first, Arcane Missiles too now.
level(8)
assert(current() == "train Near Mage", tostring(current()))
pass("TRAINER_SHOW")
assert(said():find("learn Fireball %(Rank 2%), Conjure Water, Frost Nova, Arcane Missiles, for 7s%.$"), said())
assert(current() == first and not trainRow(), "a visit at this level is enough")
fire("TRAINER_CLOSED")
-- Learning them all: nothing left, nothing suggested, also after the next level.
known[102], known[104], known[105], known[106] = true, true, true, true
pass("LEARNED_SPELL_IN_TAB")
level(9)
assert(not trainRow() and #ns.TrainSpells() == 0)

-- A rank below one the character knows is never suggested, also when it was never learned.
known[102] = nil
known[103] = true
assert(#ns.TrainSpells() == 0, "Fireball rank 2 is below the known rank 3")

-- A spell for some races only counts for those races, and for nobody where the client gives no
-- race id.
local teleport = { id = 107, name = "Teleport: Orgrimmar", level = 8, cost = 300, races = { 2, 5, 6, 8 } }
table.insert(SPELLS.MAGE, teleport)
assert(#ns.TrainSpells() == 0, "no race id")
raceId = 1
assert(#ns.TrainSpells() == 0, "a Human cannot learn Teleport: Orgrimmar")
raceId = 5
assert(#ns.TrainSpells() == 1 and ns.TrainSpells()[1] == teleport)
table.remove(SPELLS.MAGE)

-- At the trainer with too little money: says what the cheapest spell costs.
known[103], known[106] = nil, nil
T.level = 12
copper = 50
pass("TRAINER_SHOW")
assert(said():find("Fireball %(Rank 2%) costs 1s; not enough money yet%.$"), said())
fire("TRAINER_CLOSED")

-- Off: no stop, whatever is waiting.
level(13)
copper = 10000
pass("PLAYER_MONEY")
assert(current() == "train Near Mage")
ns.Set("trainer", false)
fire()
fire()
assert(not trainRow(), "off: no stop")
ns.Set("trainer", true)
fire()
fire()
assert(current() == "train Near Mage")

-- /lvl trainer list prints what is waiting; /lvl trainer turns the suggestions off.
local listed = #T.chat
T.cmd("trainer list")
assert(#T.chat == listed + 3, "one line per spell waiting")
assert(T.chat[listed + 1]:find("Fireball %(Rank 2%): level 6, 1s$"), T.chat[listed + 1])
assert(T.chat[listed + 2]:find("Arcane Missiles: level 8, 3s, key$"), T.chat[listed + 2])
T.cmd("trainer")
assert(not ns.db.trainer and said():find("not suggested"))

-- The trainers are read once: the side's trainers of the character's class with a place.
local list = ns.Trainers("alliance")
assert(#list == 2 and list[1][1] == "Near Mage" and list[2][1] == "Far Mage")
assert(#list[2] == 4 and list[2][3] == 80, "the point inside an instance is left out")
assert(ns.Stats().timers["trainers read"])

-- No spell data: nothing is suggested and nothing is said.
LevelingAddonDB, LevelingAddonCharDB = nil, nil
local P = dofile("addon/tests/stub.lua")
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", P.ns)
P.px, P.py, P.level = 0.482, 0.60, 10
P.load()
P.login()
P.fire("PLAYER_ENTERING_WORLD")
P.fire()
assert(P.ns.TrainStep() == nil and #P.ns.TrainSpells() == 0)
for _, line in ipairs(P.chat) do
    assert(not line:find("spell"), line)
end

-- Spell data and a visit due, but no trainer the planner can place nearby: one line a level.
LevelingAddonDB, LevelingAddonCharDB = nil, nil
local Q = dofile("addon/tests/stub.lua")
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", Q.ns)
Q.ns.Data.classSpells = SPELLS
Q.ns.Data.zones = { [12] = { uiMapId = 1429 }, [99] = { uiMapId = 9999 } }
Q.ns.Data.npcs = {
    [1] = { name = "Elsewhere", npcFlags = 16, subName = "Mage Trainer", spawns = { [99] = { 50, 50 } } },
}
Q.px, Q.py, Q.level = 0.482, 0.60, 8
known = { [101] = true } -- Fireball rank 1 only: four spells waiting, due
Q.load()
Q.login()
Q.fire("PLAYER_ENTERING_WORLD")
Q.fire()
Q.fire()
local lines = 0
for _, line in ipairs(Q.chat) do
    if line:find("4 new spells to learn at a trainer") then
        lines = lines + 1
    end
end
assert(lines == 1, "said once, not " .. lines)
local before = #Q.chat
Q.fire("PLAYER_MONEY")
Q.fire()
Q.fire()
for i = before + 1, #Q.chat do
    assert(not Q.chat[i]:find("new spells"), "said again at the same level")
end
print("ALL OK")
