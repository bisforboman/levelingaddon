-- Abandoning: each reason lists its quest with the right text and starting tick, the quests
-- that must never be listed are not, and only ticked rows are abandoned, only after the button.
-- From the repository root: lua5.1 addon/tests/test_abandon.lua
local T = dofile("addon/tests/stub.lua")
local ns, cmd = T.ns, T.cmd

-- The game API this feature calls beyond the stub: the character, the list of the quest log,
-- and abandoning.
function UnitClass()
    return "Warrior", "WARRIOR"
end
function UnitRace()
    return "Human", "Human"
end
local logOrder = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
function C_QuestLog.GetNumQuestLogEntries()
    return #logOrder + 1
end
function C_QuestLog.GetInfo(index)
    if index == 1 then
        return { isHeader = true, title = "Elwynn Forest" }
    end
    local id = logOrder[index - 1]
    return T.log[id] and { questID = id } or nil
end
local selected, abandoned, blocked = nil, {}, false
function C_QuestLog.SetSelectedQuest(id)
    selected = id
end
function C_QuestLog.SetAbandonQuest() end
function C_QuestLog.AbandonQuest()
    abandoned[#abandoned + 1] = selected
    if not blocked then
        T.log[selected] = nil
    end
end

-- Quest data in the planner index's layout. The character is level 20.
local here = { { "Someone", 1429, 50, 50 } }
local far = { { "Someone far away", 1426, 30, 70 } } -- another zone, nowhere near
local function quest(row)
    row.start, row.finish = row.start or here, row.finish or here
    return row
end
ns.Data = {
    plannerZones = {},
    plannerQuests = {
        [1] = quest({ name = "Old Chore", level = 5 }), -- too low
        [2] = quest({ name = "Old Errand", level = 5 }), -- too low, but leads to quest 20
        [3] = quest({ name = "Fresh Work", level = 19 }), -- skipped by hand
        [4] = quest({ name = "Deep Cave", level = 20, mark = "dungeon" }),
        [5] = quest({ name = "Big Ogre", level = 20, mark = "group" }),
        [6] = quest({ name = "Old Chore, Finished", level = 5 }), -- too low, ready to hand in
        [7] = quest({
            name = "Far Away",
            level = 20,
            start = far,
            finish = far,
            obj = { { "monster", "Wolf", 1426, 30, 70 } },
        }),
        [8] = quest({ name = "Plain", level = 20 }),
        [9] = quest({ name = "Ancient Start", level = 3 }), -- too low; leads to 21, which leads to 20
        [10] = quest({ name = "Old Chain Start", level = 4 }), -- too low; its follow-up is too low as well
        [11] = quest({ name = "Lair", level = 20, mark = "raid" }),
        -- 12 is in the log and not in the data.
        [20] = quest({ name = "Worth Doing", level = 21, pre = { 2 }, preAll = { 21 } }),
        [21] = quest({ name = "Old Link", level = 6, pre = { 9 } }),
        [22] = quest({ name = "Old Chain End", level = 6, pre = { 10 } }),
    },
}
T.level = 20
for id = 1, 12 do
    T.log[id] = { need = 4, have = id == 6 and 4 or 0 }
end

T.load()
T.login()
ns.char.skipped[3] = true

local function describe(rows)
    local parts = {}
    for i, row in ipairs(rows) do
        parts[i] = row.questID .. " " .. row.name .. ": " .. row.reason .. (row.ticked and " [x]" or " [ ]")
    end
    return table.concat(parts, "\n")
end

-- The list: each reason with its text and starting tick; too-low rows first, then by name.
local expected = table.concat({
    "10 Old Chain Start: too low level [x]",
    "1 Old Chore: too low level [x]",
    "5 Big Ogre: group quest [ ]",
    "4 Deep Cave: dungeon quest [ ]",
    "3 Fresh Work: skipped by you [ ]",
    "11 Lair: raid quest [ ]",
}, "\n")
local got = describe(ns.QuestsToAbandon())
assert(got == expected, got)
-- Not listed: 2 and 9 (low-level prerequisites of a follow-up worth doing, directly and through
-- a chain), 6 (ready to hand in), 7 (in a far zone), 8 (nothing against it), 12 (no data).

-- A kind the player allows is not listed.
ns.Planner.allow.dungeon = true
assert(not describe(ns.QuestsToAbandon()):find("Deep Cave"))
ns.Planner.allow.dungeon = nil

-- Once the follow-up is handed in, or skipped, its prerequisite is listed like any other.
T.completed[20] = true
assert(describe(ns.QuestsToAbandon()):find("2 Old Errand: too low level [x]", 1, true))
T.completed[20] = nil
ns.char.skipped[20] = true
assert(describe(ns.QuestsToAbandon()):find("9 Ancient Start: too low level [x]", 1, true))
ns.char.skipped[20] = nil

-- A quest that is both too low and skipped is listed once, as too low.
ns.char.skipped[1] = true
assert(describe(ns.QuestsToAbandon()) == expected)
ns.char.skipped[1] = nil

-- The window: one row per quest, and a button counting the ticked rows. Opening it abandons
-- nothing.
local before = #T.frames
cmd("abandon")
local window = ns.Abandon
assert(window.frame.name == "LevelingAddonAbandon" and window.frame.shown)
local function shownRows()
    local n = 0
    for _, row in ipairs(window.rows) do
        n = n + (row.shown and 1 or 0)
    end
    return n
end
assert(shownRows() == 6)
assert(window.rows[2].name.text == "Old Chore" and window.rows[2].reason.text == "too low level")
assert(window.rows[1].tick.shown and window.rows[2].tick.shown and not window.rows[3].tick.shown)
assert(window.button.text.text == "Abandon 2 quests", window.button.text.text)
assert(#abandoned == 0)

-- Ticks are the player's: untick the first row, tick the group quest.
local function click(widget)
    widget.scripts.OnClick(widget)
end
click(window.rows[1])
assert(window.button.text.text == "Abandon 1 quest")
click(window.rows[3])
assert(window.rows[3].tick.shown and window.button.text.text == "Abandon 2 quests")
assert(#abandoned == 0, "ticking abandons nothing")

-- The button abandons the ticked rows and nothing else, and the result is said a moment later.
local function runTimers()
    local run = T.timers
    T.timers = {}
    for _, f in ipairs(run) do
        f()
    end
end
T.chat = {}
click(window.button)
assert(table.concat(abandoned, " ") == "1 5", table.concat(abandoned, " "))
assert(not window.frame.shown)
runTimers()
assert(#T.chat == 1 and T.chat[1]:find("abandoned 2 quests%."), T.chat[1])

-- Opened again: the list is worked out anew, and the window and its rows are reused.
local frames = #T.frames
cmd("abandon")
assert(#T.frames == frames and frames > before, "no new frames the second time")
assert(shownRows() == 4 and window.rows[1].name.text == "Old Chain Start")
assert(window.button.text.text == "Abandon 1 quest")

-- With nothing ticked the button does nothing.
click(window.rows[1])
assert(window.button.text.text == "Abandon 0 quests")
abandoned = {}
click(window.button)
assert(#abandoned == 0 and window.frame.shown)

-- A quest finished or dropped while the window was open is left alone.
click(window.rows[1]) -- Old Chain Start, ticked again
click(window.rows[2]) -- Deep Cave
click(window.rows[3]) -- Fresh Work
T.log[4].have = 4 -- Deep Cave is now ready to hand in
T.log[3] = nil -- Fresh Work was abandoned by hand
-- A client that refuses: the quest stays, and the player is told.
blocked = true
T.chat = {}
click(window.button)
assert(table.concat(abandoned, " ") == "10")
runTimers()
assert(#T.chat == 1 and T.chat[1]:find("1 still in the quest log"), T.chat[1])
blocked = false

-- A client with neither form of the abandon API: nothing happens, and the player is told.
local keep = C_QuestLog.AbandonQuest
C_QuestLog.AbandonQuest = nil
cmd("abandon")
T.chat = {}
click(window.button)
runTimers()
assert(T.log[10] and T.chat[1]:find("1 still in the quest log"), T.chat[1])
C_QuestLog.AbandonQuest = keep

-- The older quest log API.
local info = C_QuestLog.GetInfo
C_QuestLog.GetInfo, C_QuestLog.SetSelectedQuest = nil, nil
function GetNumQuestLogEntries()
    return #logOrder
end
function GetQuestLogTitle(index)
    local id = logOrder[index]
    return "Quest " .. id, 1, nil, not T.log[id], false, nil, nil, T.log[id] and id
end
function GetQuestLogIndexByID(id)
    return T.log[id] and id or 0
end
local picked
function SelectQuestLogEntry(index)
    picked = index
end
function SetAbandonQuest() end
function AbandonQuest()
    T.log[picked] = nil
end
cmd("abandon")
assert(window.rows[1].name.text == "Old Chain Start" and window.rows[1].tick.shown)
T.chat = {}
click(window.button)
runTimers()
assert(not T.log[10] and T.chat[1]:find("abandoned 1 quest%."), T.chat[1])
C_QuestLog.GetInfo = info

-- An empty list says so in one line and opens nothing.
for id in pairs(T.log) do
    T.log[id] = nil
end
T.chat = {}
cmd("abandon")
assert(#T.chat == 1 and T.chat[1]:find("no quest in the log needs abandoning"), T.chat[1])
assert(not window.frame.shown)

-- Without the quest data nothing is listed either.
T.log[1] = { need = 4, have = 0 }
ns.Data = nil
assert(#ns.QuestsToAbandon() == 0)
print("ALL OK")
