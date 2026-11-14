-- Steps that complete themselves (issue #7), on a fixed list with no quest data loaded, so the
-- planner leaves the list alone: each kind on its event, the right objective of a quest with
-- several, the grace period, steps already done, and that only the steps in view are read.
-- From the repository root: lua5.1 addon/tests/test_steps.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick = T.ns, T.fire, T.tick
local log, completed = T.log, T.completed

-- A quest log with any number of objectives per quest, { have, need } each, that remembers
-- which quests were asked about.
local objectives, asked = {}, {}
local function asking(fn)
    return function(q)
        asked[q] = true
        return fn(q)
    end
end
C_QuestLog = {
    IsOnQuest = asking(function(q)
        return log[q] ~= nil
    end),
    IsQuestFlaggedCompleted = asking(function(q)
        return completed[q] == true
    end),
    GetQuestObjectives = asking(function(q)
        local list = log[q] and {}
        for i, o in ipairs(log[q] and objectives[q] or {}) do
            list[i] = { finished = o[1] >= o[2], numFulfilled = o[1], numRequired = o[2] }
        end
        return list
    end),
}

local function step(kind, questID, objective, need, x, y)
    local row = { kind = kind, name = kind .. " " .. questID, questID = questID, objective = objective, need = need }
    row.map, row.x, row.y = 1429, x or 10, y or 10
    return row
end

T.load()
local S = ns.Steps
S.list = {
    step("accept", 1),
    step("kill", 1, 1, 2),
    step("loot", 1, 2, 3),
    step("go", 1, 3, nil, 60, 60),
    step("turnin", 1),
    step("accept", 2),
    step("turnin", 2),
    step("accept", 3),
    step("accept", 4),
    step("accept", 5),
    step("kill", 5, nil, 1), -- planned before the quest was in the log: no objective index
    step("turnin", 5),
    step("accept", 6),
    step("turnin", 6),
}
log[3] = {} -- already in the log
completed[4] = true -- already handed in
T.login()

-- Eight rows: steps 1 to 6 are in view, and nothing else was read.
assert(S:CurrentIndex() == 1)
assert(asked[1] and asked[2] and not (asked[3] or asked[4] or asked[5] or asked[6]), "only the steps in view")

-- Accept, on the event (the classic client sends the log index first).
log[1] = {}
objectives[1] = { { 0, 2 }, { 0, 3 }, { 0, 1 } }
fire("QUEST_ACCEPTED", 5, 1)
assert(S:Status(1) == "done" and S:CurrentIndex() == 2)

-- Each row follows its own objective.
objectives[1][2][1] = 2
fire("QUEST_LOG_UPDATE")
assert(S:Progress(2) == 0 and S:Progress(3) == 2 and S:CurrentIndex() == 2, "the second objective moved")
objectives[1][1][1] = 2
fire("QUEST_LOG_UPDATE")
assert(S:Status(2) == "done" and S:Status(3) == "pending" and S:CurrentIndex() == 3, "kill")
objectives[1][2][1] = 3
fire("QUEST_LOG_UPDATE")
assert(S:Status(3) == "done" and S:CurrentIndex() == 4, "loot")

-- Go: reached inside the radius, and it stays reached after walking on.
tick(1)
assert(S:Status(4) == "pending", "far away")
T.px, T.py = 0.6005, 0.6
tick(1)
assert(S:Status(4) == "done" and S:CurrentIndex() == 5, "go")
T.px, T.py = 0.492, 0.463
fire("QUEST_LOG_UPDATE")
tick(1)
assert(S:Status(4) == "done")

-- Turn in, on the event: the completed flag comes later, and until then the event's word
-- stands, for the grace period only.
log[1] = nil
fire("QUEST_REMOVED", 1)
fire("QUEST_TURNED_IN", 1)
assert(S:Status(5) == "done" and S:Status(1) == "done" and S:CurrentIndex() == 6, "turnin")
T.now = T.now + 10
fire("QUEST_TURNED_IN", 99)
assert(S:Status(5) == "pending", "after the grace period the game's word alone counts")
completed[1] = true
fire("QUEST_TURNED_IN", 99)
assert(S:Status(5) == "done" and S:Status(2) == "done" and S:CurrentIndex() == 6)

-- The same for an accept the quest log does not show yet.
fire("QUEST_ACCEPTED", 2)
assert(S:Status(6) == "done" and S:CurrentIndex() == 7, "accepted on the event's word")
T.now = T.now + 10
fire("QUEST_REMOVED", 99)
assert(S:Status(6) == "pending")
log[2] = {}
fire("QUEST_ACCEPTED", 2)
assert(S:CurrentIndex() == 7)

-- Three rows: steps 5 to 7 are in view, a turn-in and an accept. A quest log update is not one
-- of their events, so nothing is read on it.
T.cmd("rows 3")
asked = {}
fire("QUEST_LOG_UPDATE")
assert(next(asked) == nil, "no step in view listens to QUEST_LOG_UPDATE")

-- Handing in quest 2 reads the steps in view, then the ones that come into view: quest 3 is
-- in the log and quest 4 is handed in, so their steps are done the moment they are shown.
log[2] = nil
completed[2] = true
fire("QUEST_TURNED_IN", 2)
assert(S:Status(8) == "done" and S:Status(9) == "done" and S:CurrentIndex() == 10, "already done")
assert(asked[5] and not asked[6], "the steps of quest 6 are not in view")

-- A step without an objective index follows the quest's only objective.
log[5] = {}
objectives[5] = { { 0, 1 } }
fire("QUEST_ACCEPTED", 5)
assert(S:CurrentIndex() == 11)
objectives[5][1][1] = 1
fire("QUEST_LOG_UPDATE")
assert(S:Status(11) == "done" and S:CurrentIndex() == 12)

-- A planner's list. A go step whose objective the quest log calls finished is done from the
-- log; one whose quest is not in the log is not done by standing there.
log[7] = {}
objectives[7] = { { 0, 1 } }
S:SetPlan({ step("go", 7, 1, nil, 49.2, 46.3), step("go", 8, 1, nil, 49.2, 46.3) })
local n = S:Count()
tick(1)
assert(S:Status(n - 1) == "done" and S:Status(n) == "pending" and S:CurrentIndex() == n)
log[8] = {}
objectives[8] = { { 1, 1 } }
T.px, T.py = 0.3, 0.3
fire("QUEST_LOG_UPDATE")
assert(S:CurrentIndex() == nil, "finished in the quest log")

-- The planner suggests a reached point again while its objective is open: not listed twice.
S:SetPlan({ step("go", 7, 1, nil, 49.2, 46.3), step("accept", 9) })
assert(S:Count() == n + 1 and S:Current().questID == 9)
-- An abandoned quest takes its reached point with it.
log[7] = nil
S:SetPlan({ step("accept", 7) })
log[7] = {}
S:SetPlan({ step("go", 7, 1, nil, 49.2, 46.3) })
assert(S:Current().kind == "go")
print("ALL OK")
