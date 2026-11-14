-- Quest automation: a suggested quest is accepted and handed in, from the quest windows and
-- from an NPC's list; anything else is left alone, Shift inverts, a choice of rewards stops it,
-- a repeatable is never touched, and each setting switches its half off.
-- From the repository root: lua5.1 addon/tests/test_automation.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd, log = T.ns, T.fire, T.cmd, T.log

-- The quest windows of the game: which quest the open window is about, and what was called.
local quest, completable, choices, shiftDown = 0, true, 0, false
local calls = {}
local function call(name)
    return function(arg)
        calls[#calls + 1] = name .. (arg and " " .. arg or "")
    end
end
-- What the addon did since the last look.
local function did()
    local text = table.concat(calls, ", ")
    calls = {}
    return text
end
function IsShiftKeyDown()
    return shiftDown
end
function GetQuestID()
    return quest
end
function IsQuestCompletable()
    return completable
end
function GetNumQuestChoices()
    return choices
end
AcceptQuest = call("accept")
CompleteQuest = call("complete")
GetQuestReward = call("reward")

-- An NPC's list of quests, both as gossip and as the plain greeting.
local active, available = {}, {}
C_GossipInfo = {
    GetActiveQuests = function()
        return active
    end,
    GetAvailableQuests = function()
        return available
    end,
    SelectActiveQuest = call("gossip active"),
    SelectAvailableQuest = call("gossip available"),
}
function GetNumActiveQuests()
    return #active
end
function GetNumAvailableQuests()
    return #available
end
function GetActiveTitle(i)
    return active[i].title, active[i].isComplete
end
function GetActiveQuestID(i)
    return active[i].questID
end
function GetAvailableQuestInfo(i)
    return false, 0, available[i].repeatable, false, available[i].questID
end
SelectActiveQuest = call("greeting active")
SelectAvailableQuest = call("greeting available")

-- The Northshire route, plus a step for a quest the data marks repeatable (the planner never
-- suggests one; the automation must not rely on that).
T.load()
ns.Steps.list = dofile("addon/tests/northshire.lua")
table.insert(ns.Steps.list, { kind = "accept", name = "Somebody", questID = 900, map = 1429, x = 50, y = 50 })
table.insert(ns.Steps.list, { kind = "turnin", name = "Somebody", questID = 900, map = 1429, x = 50, y = 50 })
ns.Data = { quests = { [900] = { name = "Again and Again", repeatable = true } } }
T.login()
assert(ns.db.autoAccept == true and ns.db.autoTurnIn == true, "on by default")

local function show(event, questID)
    quest = questID
    fire(event)
    return did()
end

-- A suggested quest is accepted; one the addon does not suggest is not.
assert(show("QUEST_DETAIL", 783) == "accept")
assert(show("QUEST_DETAIL", 5) == "")
fire("QUEST_FINISHED")

-- Handing in: through the progress window when the quest is ready, then the reward window.
log[783] = {}
fire("QUEST_ACCEPTED", 783)
completable = false
assert(show("QUEST_PROGRESS", 783) == "", "not ready: left alone")
completable = true
assert(show("QUEST_PROGRESS", 783) == "complete")
assert(show("QUEST_COMPLETE", 783) == "reward 0")
assert(show("QUEST_COMPLETE", 5) == "" and show("QUEST_PROGRESS", 5) == "", "not suggested: left alone")
assert(show("QUEST_DETAIL", 783) == "", "its pick-up is a finished step, no longer a suggestion")

-- One reward is taken, a choice of rewards stops at the reward window.
choices = 1
assert(show("QUEST_COMPLETE", 783) == "reward 1")
choices = 2
assert(show("QUEST_COMPLETE", 783) == "", "the player chooses")
choices = 0

-- Shift does the opposite of the setting, for that window.
shiftDown = true
assert(show("QUEST_DETAIL", 7) == "" and show("QUEST_COMPLETE", 783) == "")
fire("QUEST_FINISHED")
cmd("set autoAccept off")
cmd("set autoTurnIn off")
assert(show("QUEST_DETAIL", 7) == "accept" and show("QUEST_COMPLETE", 783) == "reward 0")
assert(show("QUEST_DETAIL", 5) == "", "Shift never reaches a quest that is not suggested")
shiftDown = false

-- Each setting switches its own half off.
assert(show("QUEST_DETAIL", 7) == "" and show("QUEST_COMPLETE", 783) == "")
cmd("set autoAccept on")
assert(show("QUEST_DETAIL", 7) == "accept" and show("QUEST_COMPLETE", 783) == "")
cmd("set autoAccept off")
cmd("set autoTurnIn on")
assert(did() == "reward 0", "a changed setting looks at the open window again, at once")
assert(show("QUEST_DETAIL", 7) == "" and show("QUEST_COMPLETE", 783) == "reward 0")
cmd("set autoAccept on")
fire("QUEST_FINISHED")
did()

-- A repeatable quest is never touched, by the data's word or by the game's.
assert(show("QUEST_DETAIL", 900) == "" and show("QUEST_PROGRESS", 900) == "" and show("QUEST_COMPLETE", 900) == "")
ns.Data = nil
active = {}
available = { { questID = 7, repeatable = true } }
assert(show("GOSSIP_SHOW") == "" and show("QUEST_GREETING") == "")

-- An NPC's list: the suggested hand-in that is ready comes first, then a suggested pick-up.
active =
    { { questID = 5, isComplete = true }, { questID = 7, isComplete = false }, { questID = 783, isComplete = true } }
available = { { questID = 5 }, { questID = 7 } }
assert(show("GOSSIP_SHOW") == "gossip active 783")
assert(show("QUEST_GREETING") == "greeting active 3")
active[3].isComplete = false
assert(show("GOSSIP_SHOW") == "gossip available 7")
assert(show("QUEST_GREETING") == "greeting available 2")
shiftDown = true
assert(show("GOSSIP_SHOW") == "" and show("QUEST_GREETING") == "")
shiftDown = false
-- A greeting that cannot tell the quests' ids picks nothing.
GetActiveQuestID, GetAvailableQuestInfo = nil, nil
active[3].isComplete = true
assert(show("QUEST_GREETING") == "")
fire("QUEST_FINISHED")
fire("GOSSIP_CLOSED")

-- A window that is open when the suggestion changes is handled then. Quest 5 is on offer and
-- not suggested; then the steps change and suggest it.
assert(show("QUEST_DETAIL", 5) == "")
table.insert(ns.Steps.list, { kind = "accept", name = "Somebody", questID = 5, map = 1429, x = 50, y = 50 })
ns.Refresh()
assert(did() == "accept")
-- Shift counts as it was when the window opened, not as it is when the steps change.
shiftDown = true
assert(show("QUEST_DETAIL", 5) == "")
shiftDown = false
ns.Refresh()
assert(did() == "")
-- Once the window has closed, a change of steps does nothing.
assert(show("QUEST_DETAIL", 5) == "accept")
fire("QUEST_FINISHED")
ns.Refresh()
assert(did() == "")
-- The gossip window closing does not end a quest window opened from it, and the other way round.
assert(show("GOSSIP_SHOW") == "gossip active 783")
quest = 5
fire("QUEST_FINISHED")
ns.Refresh()
assert(did() == "gossip active 783")
fire("QUEST_DETAIL")
fire("GOSSIP_CLOSED")
did()
ns.Refresh()
assert(did() == "accept")
print("ALL OK")
