-- The planner outside the game: a fresh character, a mid-level character with a half-finished
-- zone, a character who skipped ahead, skips, and the events that ask for a pass.
-- From the repository root: lua5.1 addon/tests/test_planner.lua
--
-- It loads Core, Steps and Planner against a small stub of the game API and the quest data in
-- planner_data.lua, which is cut from a real export. Every scenario starts a new session.

-- The world: each zone map as { north edge, west edge, width, height } in world yards, laid out
-- as the zones lie. World x runs north and world y runs west, as in the game.
local RECTS = {
    [1429] = { 0, 0, 3470, 2314 }, -- Elwynn Forest
    [1453] = { 1200, 900, 1737, 1158 }, -- Stormwind City, over Elwynn's north-west
    [1436] = { -800, 2600, 3500, 2333 }, -- Westfall, to the west
    [1431] = { -2100, -200, 2700, 1800 }, -- Duskwood, to the south
    [1433] = { 300, -2000, 2170, 1447 }, -- Redridge, to the east
    [1426] = { 9000, 0, 4900, 3270 }, -- Dun Morogh, far to the north
}

local T -- the session's game state
local chat = {}
SlashCmdList = {}

function print(...)
    chat[#chat + 1] = table.concat({ ... }, " ")
end
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
function strtrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
function strsplit(sep, s)
    local a, b = s:match("^([^" .. sep .. "]*)" .. sep .. "?(.*)$")
    return a, b ~= "" and b or nil
end
function GetTime()
    return 0
end
function CreateVector2D(x, y)
    return {
        x = x,
        y = y,
        GetXY = function(s)
            return s.x, s.y
        end,
    }
end
function UnitLevel()
    return T.level
end
function UnitClass()
    return "", T.class
end
function UnitRace()
    return "", T.race
end
function UnitFactionGroup()
    return T.faction
end
C_Timer = {
    After = function(_, f)
        T.timers[#T.timers + 1] = f
    end,
}
C_Map = {
    GetBestMapForUnit = function()
        return T.map
    end,
    GetMapInfo = function(map)
        return { parentMapID = T.parents[map] }
    end,
    GetPlayerMapPosition = function()
        return CreateVector2D(T.x / 100, T.y / 100)
    end,
    GetWorldPosFromMapPos = function(map, v)
        local r = RECTS[map]
        if not r then
            return nil
        end
        return 0, { x = r[1] - v.y * r[4], y = r[2] - v.x * r[3] }
    end,
}
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end
local function modernQuestLog()
    return {
        IsOnQuest = function(q)
            return T.log[q] ~= nil
        end,
        IsQuestFlaggedCompleted = function(q)
            return T.completed[q] == true
        end,
        -- T.log[q] is the list of objectives: { type =, have =, need = }.
        GetQuestObjectives = function(q)
            local out = {}
            for i, o in ipairs(T.log[q] or {}) do
                out[i] = { type = o.type, finished = o.have >= o.need, numFulfilled = o.have, numRequired = o.need }
            end
            return T.log[q] and out
        end,
        GetNumQuestLogEntries = function()
            return #sortedKeys(T.log) + 1
        end,
        GetInfo = function(i)
            if i == 1 then
                return { isHeader = true }
            end
            return { questID = sortedKeys(T.log)[i - 1] }
        end,
        GetAllCompletedQuestIDs = function()
            T.completedReads = T.completedReads + 1
            return sortedKeys(T.completed)
        end,
    }
end

-- Start a session: a character, where it stands, what it has done. Returns the addon's table
-- and a function that sends a game event and runs the timers it started.
local function boot(character)
    T = { log = {}, completed = {}, timers = {}, parents = {}, completedReads = 0, passes = 0 }
    for k, v in pairs(character) do
        T[k] = v
    end
    chat = {}
    C_QuestLog = modernQuestLog()
    GetQuestsCompleted, GetNumQuestLogEntries, GetQuestLogTitle = nil, nil, nil
    if character.setup then
        character.setup()
    end
    LevelingAddonDB, LevelingAddonCharDB = nil, character.saved
    local frame = { scripts = {} }
    function CreateFrame()
        return setmetatable(frame, {
            __index = function(_, k)
                if k == "SetScript" then
                    return function(self, name, f)
                        self.scripts[name] = f
                    end
                end
                return function() end
            end,
        })
    end
    local ns = {}
    for _, file in ipairs({ "Core", "Steps", "Planner" }) do
        assert(loadfile("addon/LevelingAddon/" .. file .. ".lua"))("LevelingAddon", ns)
    end
    if not character.noData then
        assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", ns)
    end
    ns.Window = { Create = function() end, Refresh = function() end, RestorePosition = function() end }
    ns.Arrow = { Create = function() end, StepChanged = function() end }
    local run = ns.Planner.Run
    ns.Planner.Run = function(...)
        T.passes = T.passes + 1
        return run(...)
    end
    local function fire(event, ...)
        if event then
            frame.scripts.OnEvent(frame, event, ...)
        end
        while T.timers[1] do
            table.remove(T.timers, 1)()
        end
    end
    fire("ADDON_LOADED", "LevelingAddon")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
    return ns, fire
end

local ns, fire

-- The list as text: "kind name quest", with a mark for done (v) and skipped (x).
local function row(index)
    local step = ns.Steps.list[index]
    local status = ns.Steps:Status(index)
    local mark = status == "done" and "v " or status == "skipped" and "x " or ""
    return mark .. step.kind .. " " .. step.name .. " " .. step.questID
end
local function rows()
    local out = {}
    for index = 1, ns.Steps:Count() do
        out[index] = row(index)
    end
    return out
end
local function find(kind, questID)
    for index, step in ipairs(ns.Steps.list) do
        if step.kind == kind and step.questID == questID then
            return index, step
        end
    end
end
local function show(title)
    io.write(title, "\n")
    for _, text in ipairs(rows()) do
        io.write("    ", text, "\n")
    end
end
local function current()
    local index = ns.Steps:CurrentIndex()
    return index and row(index)
end

-- What the game would do.
local function accept(questID, ...)
    T.log[questID] = { ... }
    fire("QUEST_ACCEPTED", questID)
end
local function progress(questID, objective, have)
    T.log[questID][objective].have = have
    fire("QUEST_LOG_UPDATE")
end
local function turnIn(questID)
    T.log[questID] = nil
    fire("QUEST_REMOVED", questID)
    fire("QUEST_TURNED_IN", questID) -- the completed flag is not set yet
    T.completed[questID] = true
end
local function monster(need, have)
    return { type = "monster", need = need, have = have or 0 }
end
local function item(need, have)
    return { type = "item", need = need, have = have or 0 }
end

local HUMAN = { level = 1, class = "WARRIOR", race = "Human", faction = "Alliance" }
local function human(fields)
    local character = {}
    for k, v in pairs(HUMAN) do
        character[k] = v
    end
    for k, v in pairs(fields) do
        character[k] = v
    end
    return character
end

-- 1. A fresh character ----------------------------------------------------------------------
-- A level 1 human warrior beside Deputy Willem in Northshire.
ns, fire = boot(human({ map = 1429, x = 48.2, y = 43.0 }))
show("fresh human warrior, Northshire")
assert(current() == "accept Deputy Willem 783", current())
assert(row(2) == "turnin Marshal McBride 783" and row(3) == "accept Marshal McBride 7", row(2))
assert(find("accept", 3100), "the warrior's class quest is offered")
assert(not find("accept", 3101), "the paladin's is not")
assert(not find("accept", 18), "Brotherhood of Thieves needs level 2")
assert(not find("accept", 179), "Dun Morogh is not a neighbour of Elwynn")
assert(not find("accept", 92745), "a level 9 quest in Westfall is not for a level 1")
-- Actions that share a place come together: both of McBride's before leaving for Eagan.
assert(find("accept", 33) > find("accept", 7) and find("kill", 7) > find("accept", 33))
local step = ns.Steps.list[1]
assert(step.map == 1429 and step.x == 48.17 and step.y == 42.94 and step.objective == nil)
assert(T.completedReads == 1 and ns.Stats().timers["planner pass"] and ns.Stats().timers["completed quests read"])

-- Accepting, progress and handing in move the list; what was done stays above as history.
accept(783)
assert(row(1) == "v accept Deputy Willem 783" and current() == "turnin Marshal McBride 783", current())
T.x, T.y = 48.9, 41.6 -- at Marshal McBride
turnIn(783)
assert(current() == "accept Marshal McBride 7", current())
accept(7, monster(10))
local index, kill = find("kill", 7)
assert(kill.name == "Kobold Vermin" and kill.need == 10 and kill.objective == 1, "the count comes from the log")
progress(7, 1, 4)
assert(ns.Steps:Progress(index) == 4)
local passes = T.passes
progress(7, 1, 5)
assert(T.passes == passes, "a count alone does not ask for a pass")
progress(7, 1, 10)
assert(T.passes == passes + 1 and find("turnin", 7), "a finished objective does")
assert(find("accept", 15) > find("turnin", 7), "the next in the chain is planned after the hand-in")
turnIn(7)
assert(current() == "accept Marshal McBride 15", current())
assert(T.completedReads == 1, "completed quests are read once, then kept current from events")

-- A burst of events is one pass.
passes = T.passes
fire(nil)
T.log[33] = { item(8) }
ns.Planner.Request()
ns.Planner.Request()
fire("QUEST_ACCEPTED", 33)
assert(T.passes == passes + 1, T.passes - passes)

-- The breadcrumb to Eagan is no longer offered once his quest is in the log.
assert(not find("accept", 5261))

-- Level 2 opens Brotherhood of Thieves; the event carries the level before UnitLevel has it.
assert(not find("accept", 18))
fire("PLAYER_LEVEL_UP", 2)
assert(find("accept", 18))

-- No zone (an instance): the steps stay as they are.
local before = table.concat(rows(), "\n")
T.map = nil
fire("ZONE_CHANGED_NEW_AREA")
assert(table.concat(rows(), "\n") == before)
-- A sub-map the data does not know resolves to its parent zone.
T.map, T.parents[425] = 425, 1429
fire("ZONE_CHANGED_NEW_AREA")
assert(table.concat(rows(), "\n") == before)
T.map = 1429

-- Skips: per quest, per character, restorable ------------------------------------------------
index = find("accept", 18)
ns.Steps:Skip(index)
show("after skipping Brotherhood of Thieves")
assert(ns.char.skipped[18] and LevelingAddonCharDB.skipped[18], "saved per character, by quest")
assert(row(find("accept", 18)) == "x accept Deputy Willem 18", "the skipped step stays, crossed out")
assert(not find("loot", 18) and not find("turnin", 18), "nothing else of the quest is suggested")
fire("PLAYER_LEVEL_UP", 3)
assert(row(find("accept", 18)) == "x accept Deputy Willem 18", "and it stays out, pass after pass")
chat = {}
SlashCmdList.LEVELINGADDON("skipped")
assert(chat[1]:find("18 Brotherhood of Thieves") and chat[2]:find("/lvl unskip"), chat[1])
SlashCmdList.LEVELINGADDON("unskip")
assert(ns.char.skipped[18], "/lvl unskip alone lists; it no longer brings everything back")
ns.Steps:Restore(find("accept", 18))
assert(not ns.char.skipped[18] and row(find("accept", 18)) == "accept Deputy Willem 18")
ns.Steps:Skip(find("accept", 18))
SlashCmdList.LEVELINGADDON("unskip 18")
assert(not ns.char.skipped[18] and find("accept", 18))
-- A skipped quest that is in the log is not worked on either.
ns.Steps:Skip(find("loot", 33))
assert(not find("turnin", 33) and row(find("loot", 33)) == "x loot Tough Wolf Meat 33")
SlashCmdList.LEVELINGADDON("unskip all")
assert(next(ns.char.skipped) == nil and ns.Steps:Status(find("loot", 33)) == "pending")

-- The skips of one character are that character's: a new session with them saved starts with
-- the quest left out.
ns, fire = boot(human({ map = 1429, x = 48.2, y = 43.0, saved = { skipped = { [783] = true } } }))
assert(not find("accept", 783) and ns.Steps:Count() > 0, "a saved skip holds after a relog")

-- 2. Mid-level, half a zone done -------------------------------------------------------------
-- A level 27 in Darkshire: the Elwynn quests and part of Duskwood done, two quests in the log,
-- one of them ready to hand in.
local function duskwood(fields)
    local character = human({ level = 27, map = 1431, x = 73.7, y = 44.5 })
    character.setup = function()
        for _, id in ipairs({ 783, 7, 33, 15, 18, 21, 54, 3100, 5261, 56, 163, 174, 175 }) do
            T.completed[id] = true
        end
        T.log[57] = { monster(15, 15), monster(15, 3) } -- The Night Watch, second part
        T.log[101] = { item(5, 5), item(5, 5), item(10, 10) } -- The Totem of Infliction, complete
    end
    for k, v in pairs(fields or {}) do
        character[k] = v
    end
    return character
end
ns, fire = boot(duskwood())
show("level 27 in Darkshire, half of Duskwood done")
assert(current() == "turnin Madame Eva 101" and not find("loot", 101), "a complete quest is handed in first")
assert(not find("kill", 57), "Raven Hill is a long way off: not among the next steps from Darkshire")
T.x, T.y = 22, 47 -- at Raven Hill
ns.Planner.Request()
fire(nil)
show("the same character at Raven Hill")
index, kill = find("kill", 57)
assert(
    kill.name == "Skeletal Horror" and kill.objective == 2 and kill.need == 15,
    "the open objective, not the finished one"
)
assert(ns.Steps:Progress(index) == 3)
T.x, T.y = 73.7, 44.5
ns.Planner.Request()
fire(nil)
assert(find("accept", 177), "the next part of a chain whose earlier parts are done")
for _, id in ipairs({ 56, 163, 174, 175, 783, 18, 54 }) do
    assert(not find("accept", id), "nothing already done is offered: " .. id)
end
assert(not find("accept", 58), "a quest whose prerequisite is only in the log waits")
assert(not find("accept", 254), "a quest that needs its parent in the log is not offered without it")
for _, s in ipairs(ns.Steps.list) do
    assert(s.map == 1431 or s.map == 1433 or s.map == 1429, "only this zone and its neighbours")
end
-- Every step is one of this character's quests and nothing is suggested twice.
local seen = {}
for i = 1, ns.Steps:Count() do
    assert(not seen[row(i)], row(i))
    seen[row(i)] = true
end
-- In Lakeshire, beside a wanted poster for an elite: group quests are left out by default, and a
-- changed preference asks for a pass through the one entry point.
T.map, T.x, T.y = 1433, 25, 46
fire("ZONE_CHANGED_NEW_AREA")
assert(not find("accept", 169), "group quests are left out by default")
ns.Planner.allow.group = true
ns.Planner.Request()
fire(nil)
assert(find("accept", 169), "an allowed mark lets the quest in")

-- 3. A character who skipped ahead ------------------------------------------------------------
-- Level 27 in Duskwood, but by another road: the second Night Watch done without the first on
-- record, Eagan's quest done without its breadcrumb, most of Elwynn never touched.
ns, fire = boot(human({
    level = 27,
    map = 1431,
    x = 73.7,
    y = 44.5,
    setup = function()
        for _, id in ipairs({ 33, 57 }) do
            T.completed[id] = true
        end
    end,
}))
show("level 27 who skipped ahead, Darkshire")
assert(find("accept", 58), "the third part follows the second, whatever came before")
assert(not find("accept", 56), "the first part is not offered once the second is done")
for _, s in ipairs(ns.Steps.list) do
    assert(s.map ~= 1429, "Elwynn's leftovers are far too low to suggest")
end
-- In Dun Morogh nothing in the zone or next to it fits level 27: the steps lead to the zone on
-- the continent that does.
T.map, T.x, T.y = 1426, 30, 71
fire("ZONE_CHANGED_NEW_AREA")
show("the same character in Dun Morogh")
assert(ns.Steps:Count() > 0, "somewhere to go")
for _, s in ipairs(ns.Steps.list) do
    assert(s.map == 1431, "the best-fitting zone on the continent: Duskwood")
end

-- Other clients, and no data -----------------------------------------------------------------
-- The older calls for completed quests and the quest log.
ns, fire = boot(duskwood({
    setup = function()
        duskwood().setup()
        local log = T.log
        C_QuestLog.GetAllCompletedQuestIDs, C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = nil, nil, nil
        function GetQuestsCompleted()
            return T.completed
        end
        function GetNumQuestLogEntries()
            return #sortedKeys(log)
        end
        function GetQuestLogTitle(i)
            return "", 0, nil, false, false, false, 0, sortedKeys(log)[i]
        end
    end,
}))
assert(find("turnin", 101) and find("accept", 177) and not find("accept", 56))
-- Neither way of listing: quests are asked about one at a time.
ns, fire = boot(duskwood({
    setup = function()
        duskwood().setup()
        C_QuestLog.GetAllCompletedQuestIDs, C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = nil, nil, nil
    end,
}))
assert(find("accept", 177) and not find("accept", 56) and not find("accept", 101))
-- A race the data does not list for a quest, and the other faction.
ns, fire = boot(human({ map = 1429, x = 48.2, y = 43.0, class = "PALADIN", race = "Dwarf" }))
assert(not find("accept", 3101), "the human paladin's letter is not for a dwarf")
ns, fire = boot(human({ map = 1429, x = 48.2, y = 43.0, faction = "Horde", race = "Orc" }))
assert(ns.Steps:Count() == 0, "no Alliance quest for a Horde character")
-- Without the quest data the addon says so once and shows nothing.
ns, fire = boot(human({ map = 1429, x = 48.2, y = 43.0, noData = true }))
fire("ZONE_CHANGED_NEW_AREA")
local told = 0
for _, line in ipairs(chat) do
    told = told + (line:find("no quest data") and 1 or 0)
end
assert(told == 1 and ns.Steps:Count() == 0)

io.write("ALL OK\n")
