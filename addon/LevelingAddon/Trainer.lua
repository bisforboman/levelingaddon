-- Trainer: suggests a visit to the class trainer when it is worth the trip (issue #17), as a
-- "train" step among the steps, and lists what to buy when the trainer window opens. Nothing is
-- bought: the player clicks "Train" in the trainer's window.
--
-- Worth the trip is weighed from the spells the character could learn now and does not know:
-- each one counts 1, and KEY_WEIGHT when the data marks it `key` (a spell that changes how the
-- class levels, such as a new attack, rather than a rank of one it has). The weight is held
-- against two thresholds:
--   NEAR_WEIGHT  the visit is a side task, under the current step, while a trainer is near the way
--   DUE_WEIGHT   the visit is the current step, at the nearest trainer
-- Only spells the character can pay for count, so a visit is never suggested that ends in
-- buying nothing. Both thresholds are first guesses, to be tuned in the game.
--
-- The spell list is ns.Data.classSpells, built by the collector from Wowhead's class ability
-- pages (README, "Fetching class spells"). Without it the feature says nothing and suggests
-- nothing.
--
--   ns.Data.classSpells[classToken] = {
--       { id = spellId, name = "Frostbolt", rank = 2, level = 8, cost = 200, key = true },
--       ...
--   }
--   classToken  the client's class token in upper case, as UnitClass returns it ("MAGE")
--   rank        optional: a rank of a spell with several, to skip ranks below one known
--   cost        in copper, before any reputation discount
--   races       optional: the race ids (UnitRace's third value) that can learn it; absent: all
--   key         optional: true for a spell worth a trip of its own (collector.json lists them)
--
-- The trainers are the data's NPCs with the trainer flag whose subtitle names the class, such
-- as "Mage Trainer". The data's subtitles are English whatever the client's language.
local _, ns = ...

local KEY_WEIGHT = 3 -- what a key spell counts, against 1 for any other
local NEAR_WEIGHT = 2 -- this much and a trainer near the way is a side task
local DUE_WEIGHT = 5 -- this much and the trainer is the current step
local TRAINER_FLAG = 16 -- in the data's npcFlags
local CLASS_NAME = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    DRUID = "Druid",
}

ns.TRAIN = -1 -- what a train step carries as its quest id: skips are kept by quest id
ns.defaults.trainer = true

local atTrainer = false
local visited -- the level at which a trainer window was last opened
local told -- the level for which "nothing near" was said, so it is said once a level
local trainers -- read from the NPC table once

-- Whether the character knows a spell; nil where the client can say neither way.
local function IsKnown(id)
    local known = IsPlayerSpell or IsSpellKnown
    return known and known(id)
end

local function classToken()
    local _, token = UnitClass("player")
    return token
end

-- Whether the character's race can learn a spell. Where the client gives no race id, a spell
-- for some races only is left out: better a spell too few than a trip for nothing.
local function forRace(spell, race)
    if not spell.races then
        return true
    end
    for _, id in ipairs(spell.races) do
        if id == race then
            return true
        end
    end
    return false
end

-- The spells the character could learn at its level and does not know yet, cheapest first, and
-- what the affordable ones weigh. A rank below a rank the character knows is left out, and so
-- is a spell for other races.
function ns.TrainSpells()
    local list = ns.Data and ns.Data.classSpells and ns.Data.classSpells[classToken() or ""]
    local spells, weight, cost = {}, 0, 0
    if not (list and (IsPlayerSpell or IsSpellKnown)) then
        return spells, weight, cost
    end
    local level = UnitLevel("player") or 1
    local _, _, race = UnitRace("player")
    local best = {} -- [name] = the highest rank known
    for _, spell in ipairs(list) do
        if spell.rank and IsKnown(spell.id) and spell.rank > (best[spell.name] or 0) then
            best[spell.name] = spell.rank
        end
    end
    for _, spell in ipairs(list) do
        local below = spell.rank and spell.rank <= (best[spell.name] or 0)
        if spell.level <= level and not below and forRace(spell, race) and not IsKnown(spell.id) then
            spells[#spells + 1] = spell
        end
    end
    table.sort(spells, function(a, b)
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.id < b.id
    end)
    local money = GetMoney and GetMoney() or 0
    for _, spell in ipairs(spells) do
        if cost + spell.cost <= money then
            cost = cost + spell.cost
            weight = weight + (spell.key and KEY_WEIGHT or 1)
        end
    end
    return spells, weight, cost
end

-- For the planner: "due" (the current step), "near" (a side task, only for a trainer near the
-- way), or nil: off, nothing worth the trip, skipped, or a trainer visited at this level.
function ns.TrainStep()
    local level = UnitLevel("player") or 1
    if not ns.db.trainer or visited == level or ns.char.skipped[ns.TRAIN] then
        return nil
    end
    local _, weight = ns.TrainSpells()
    return weight >= DUE_WEIGHT and "due" or weight >= NEAR_WEIGHT and "near" or nil
end

-- For the step: over once the player has had a trainer window open, and it stays over.
function ns.TrainDone()
    return atTrainer or visited == (UnitLevel("player") or 1)
end

-- The planner found no trainer it could place for a visit that is due: said once a level.
function ns.TrainNone()
    local level = UnitLevel("player") or 1
    if told ~= level then
        told = level
        local spells = ns.TrainSpells()
        ns.say(string.format("%d new spell%s to learn at a trainer.", #spells, #spells == 1 and "" or "s"))
    end
end

-- The class trainers the data knows that the character's side can use, each as the planner
-- takes a target: { name, map, x, y, map, x, y, ... }.
function ns.Trainers(side)
    if trainers then
        return trainers
    end
    local start = ns.Clock()
    trainers = {}
    local title = CLASS_NAME[classToken() or ""]
    local letter = side == "horde" and "H" or "A"
    local zones = ns.Data.zones or {}
    local ids = {}
    for id, npc in pairs(title and ns.Data.npcs or {}) do
        local usable = not npc.friendlyTo or npc.friendlyTo:find(letter)
        local flagged = (npc.npcFlags or 0) % (TRAINER_FLAG * 2) >= TRAINER_FLAG
        if usable and flagged and npc.spawns and npc.subName == title .. " Trainer" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local npc = ns.Data.npcs[id]
        local trainer = { npc.name }
        for zoneId, points in pairs(npc.spawns) do
            local map = zones[zoneId] and zones[zoneId].uiMapId
            for i = 1, map and #points or 0, 2 do
                if points[i] ~= -1 then -- -1, -1: inside an instance
                    trainer[#trainer + 1] = map
                    trainer[#trainer + 1] = points[i]
                    trainer[#trainer + 1] = points[i + 1]
                end
            end
        end
        trainers[#trainers + 1] = trainer
    end
    ns.Report("trainers read", ns.Clock() - start)
    return trainers
end

local function money(copper)
    local gold, silver = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if copper % 100 > 0 or not parts[1] then
        parts[#parts + 1] = copper % 100 .. "c"
    end
    return table.concat(parts, " ")
end

local function name(spell)
    return spell.rank and string.format("%s (Rank %d)", spell.name, spell.rank) or spell.name
end

-- At the trainer: what to buy, in one line.
ns.On("TRAINER_SHOW", function()
    atTrainer = true
    visited = UnitLevel("player") or 1
    ns.char.skipped[ns.TRAIN] = nil
    if ns.db.trainer then
        local spells, _, cost = ns.TrainSpells()
        local names, spent = {}, 0
        for _, spell in ipairs(spells) do
            if spent + spell.cost <= cost then
                spent = spent + spell.cost
                names[#names + 1] = name(spell)
            end
        end
        if names[1] then
            ns.say(string.format("learn %s, for %s.", table.concat(names, ", "), money(cost)))
        elseif spells[1] then
            ns.say(string.format("%s costs %s; not enough money yet.", name(spells[1]), money(spells[1].cost)))
        end
    end
    ns.Planner.Request()
end)

ns.On("TRAINER_CLOSED", function()
    atTrainer = false
end)

-- A new level can bring new spells: a skip lasts until then.
ns.On("PLAYER_LEVEL_UP", function()
    ns.char.skipped[ns.TRAIN] = nil
end)
-- Learning a spell, or money coming in, changes what is worth the trip.
ns.On("LEARNED_SPELL_IN_TAB", ns.Planner.Request)
ns.On("PLAYER_MONEY", ns.Debounce(5, ns.Planner.Request))

ns.AddSetting({
    key = "trainer",
    label = "Suggest trainer visits",
    tooltip = "A stop at the class trainer among the steps when there are spells worth the trip.",
    onChange = function()
        ns.Planner.Request()
    end,
})

ns.commands.trainer = function(arg)
    if arg == "list" then
        local spells = ns.TrainSpells()
        if not spells[1] then
            ns.say(ns.Data and ns.Data.classSpells and "nothing new to learn." or "has no spell data yet.")
        end
        for _, spell in ipairs(spells) do
            ns.say(
                string.format(
                    "%s: level %d, %s%s",
                    name(spell),
                    spell.level,
                    money(spell.cost),
                    spell.key and ", key" or ""
                )
            )
        end
        return
    end
    ns.Set("trainer", not ns.db.trainer)
    ns.say("trainer visits are " .. (ns.db.trainer and "suggested" or "not suggested") .. ".")
end
