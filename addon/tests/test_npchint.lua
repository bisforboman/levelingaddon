-- The quest giver hint and the quest log marks (issue #80): one line per quest the character can
-- pick up or hand in at the NPC under the pointer, the suggested ones first, at most three and
-- then "and N more"; nothing for players, a hidden unit or with the setting off. In the quest
-- log, a mark on the rows whose quest is in the guide's current steps.
-- From the repository root: lua5.1 addon/tests/test_npchint.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire = T.ns, T.fire

function UnitClass()
    return "Warrior", "WARRIOR"
end
function UnitRace()
    return "Human", "Human"
end

-- The unit tooltip: every callback the addon adds, and the lines they add.
local unitCalls, lines = {}, {}
Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        if kind == 2 then
            unitCalls[#unitCalls + 1] = fn
        end
    end,
}
rawset(GameTooltip, "GetUnit", function()
    return "Someone", "mouseover"
end)
rawset(GameTooltip, "AddLine", function(_, text)
    lines[#lines + 1] = text
end)
local function hover(guid)
    T.guids.mouseover, lines = guid, {}
    for _, fn in ipairs(unitCalls) do
        fn(GameTooltip, {})
    end
    return table.concat(lines, "; ")
end
local WILLEM, MCBRIDE = "Creature-0-1-0-12-823-00001", "Creature-0-1-0-12-197-00002"

-- The classic quest log: three rows, and the log they show.
local logRows = {}
GetNumQuestLogEntries = function()
    return #logRows
end
GetQuestLogTitle = function(index)
    local row = logRows[index]
    return row.title, 1, nil, row.header or false, nil, nil, nil, row.id
end
QUESTS_DISPLAYED = 3
local marks = {}
for i = 1, QUESTS_DISPLAYED do
    local button = CreateFrame("Button", "QuestLogTitle" .. i)
    rawset(button, "GetID", function()
        return i
    end)
    rawset(button, "CreateTexture", function()
        marks[i] = CreateFrame("Texture")
        return marks[i]
    end)
    _G["QuestLogTitle" .. i] = button
end
T.frames = {} -- so that Core's frame is the first
QuestLog_Update = function() end
local function marked()
    QuestLog_Update()
    local rows = {}
    for i = 1, QUESTS_DISPLAYED do
        rows[i] = marks[i] and marks[i].shown and "x" or "-"
    end
    return table.concat(rows)
end

-- A fresh human in Northshire, south of the quest givers. Deputy Willem gives A Threat Within
-- (783) and Brotherhood of Thieves (18, level 2); Marshal McBride takes 783 back and gives
-- Kobold Camp Cleanup (7, after 783), and four quests the planner's zones do not hold.
T.px, T.py = 0.482, 0.60
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", ns)
for id = 9001, 9004 do
    ns.Data.plannerQuests[id] = { name = "Extra " .. id, level = 1, req = 1, side = "alliance" }
end
ns.Data.npcs = {
    [823] = { name = "Deputy Willem", questStarts = { 783, 18 } },
    [197] = { name = "Marshal McBride", questStarts = { 7, 9001, 9002, 9003, 9004 }, questEnds = { 783 } },
}
T.load()
T.login()
fire("PLAYER_ENTERING_WORLD")
fire()
assert(ns.db.npcHint == true and ns.db.questLogMark == true, "both on by default")

-- Only what can be taken now: Brotherhood of Thieves needs level 2, and McBride's first quest
-- needs A Threat Within done. The extras have no prerequisite.
assert(hover(WILLEM) == "! A Threat Within", hover(WILLEM))
assert(hover(MCBRIDE) == "! Extra 9001; ! Extra 9002; ! Extra 9003;   and 1 more", hover(MCBRIDE))
-- Not a creature, no unit, an NPC the data does not have, a unit kept from addons: nothing.
assert(hover("Player-1-00000001") == "")
assert(hover(nil) == "")
assert(hover("Creature-0-1-0-12-99999-00003") == "")
issecretvalue = function(value)
    return value == "mouseover"
end
assert(hover(WILLEM) == "", "a secret unit")
issecretvalue = nil

-- A Threat Within in the log: not offered again; once ready, McBride takes it back, first.
T.log[783] = { need = 1, have = 0 }
fire("QUEST_ACCEPTED", 783)
fire()
assert(hover(WILLEM) == "", hover(WILLEM))
assert(not hover(MCBRIDE):find("A Threat Within"), "not ready: no hand-in line")
T.log[783].have = 1
fire("QUEST_LOG_UPDATE")
fire()
assert(hover(MCBRIDE):find("^%? A Threat Within; ! Extra 9001"), hover(MCBRIDE))

-- Handed in: Kobold Camp Cleanup can be taken. The steps suggest it, so it comes first.
T.log[783], T.completed[783] = nil, true
fire("QUEST_TURNED_IN", 783)
fire()
assert(hover(MCBRIDE) == "! Kobold Camp Cleanup; ! Extra 9001; ! Extra 9002;   and 2 more", hover(MCBRIDE))

-- The setting off: nothing.
ns.Set("npcHint", false)
assert(hover(MCBRIDE) == "")
ns.Set("npcHint", true)

-- The quest log: a header, Kobold Camp Cleanup (in the steps once accepted), and an extra the
-- steps do not hold.
T.log[7] = { need = 10, have = 0 }
logRows = {
    { title = "Northshire", header = true },
    { title = "Kobold Camp Cleanup", id = 7 },
    { title = "Extra 9001", id = 9001 },
}
fire("QUEST_ACCEPTED", 7)
fire()
assert(marked() == "-x-", marked())
-- Fewer rows shown: the row's mark goes with it.
rawset(QuestLogTitle2, "IsShown", function()
    return false
end)
assert(marked() == "---")
rawset(QuestLogTitle2, "IsShown", nil)
-- The setting off: no marks; on again: back.
ns.Set("questLogMark", false)
assert(marked() == "---")
ns.Set("questLogMark", true)
assert(marked() == "-x-")
-- Done with the quest: off the trail, so the mark goes.
T.log[7], T.completed[7] = nil, true
logRows[2] = { title = "Extra 9002", id = 9002 }
fire("QUEST_TURNED_IN", 7)
fire()
assert(marked() == "---", marked())

print("ALL OK")
