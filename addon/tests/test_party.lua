-- Party features: the version check and its throttle, the level-up announcement, quest
-- sharing, party members' steps and /lvl party. The game API they call is stubbed here, on
-- top of stub.lua.
-- From the repository root: lua5.1 addon/tests/test_party.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd

local group = 0 -- players in the group, the player included
local guild = false
local sent, chat, pushed, selected = {}, {}, {}, 0
local timers = {} -- { at, fn }: here timers wait for their time, unlike stub.lua's
C_Timer.After = function(seconds, fn)
    timers[#timers + 1] = { at = T.now + seconds, fn = fn }
end
local function wait(seconds)
    T.now = T.now + seconds
    local due = timers
    timers = {}
    for _, t in ipairs(due) do
        if t.at <= T.now then
            t.fn()
        else
            timers[#timers + 1] = t
        end
    end
end
C_AddOns = {
    GetAddOnMetadata = function(_, field)
        return field == "Version" and "1.2.3" or nil
    end,
}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        T.prefix = prefix
    end,
    SendAddonMessage = function(prefix, text, channel)
        sent[#sent + 1] = prefix .. "|" .. text .. "|" .. channel
    end,
}
function IsInGroup()
    return group > 0
end
function GetNumGroupMembers()
    return group
end
function IsInGuild()
    return guild
end
local party = { "Friend" } -- the other members' names, as party1 to party4
function UnitName(unit)
    return unit == "mouseover" and T.over or party[tonumber(unit:match("^party(%d)$"))]
end
function UnitInParty(unit)
    return unit == "mouseover" and T.overInParty
end
-- The unit tooltip: what the game calls when it has filled one, and the lines added to it.
-- Every unit callback is kept: the quest giver hint (Hints.lua) adds one too.
local unitCalls, tooltipLines = {}, {}
local function unitTooltip(...)
    for _, fn in ipairs(unitCalls) do
        fn(...)
    end
end
Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        if kind == Enum.TooltipDataType.Unit then
            unitCalls[#unitCalls + 1] = fn
        end
    end,
}
rawset(GameTooltip, "GetUnit", function()
    return T.over, T.over and "mouseover"
end)
rawset(GameTooltip, "AddLine", function(_, text)
    tooltipLines[#tooltipLines + 1] = text
end)
-- Point at a unit; returns the lines the addon put on its tooltip.
local function hover(name, inParty)
    T.over, T.overInParty, tooltipLines = name, inParty ~= false, {}
    unitTooltip(GameTooltip, {})
    return table.concat(tooltipLines, "; ")
end
function SendChatMessage(text, channel)
    chat[#chat + 1] = channel .. ": " .. text
end
function QuestLogPushQuest()
    pushed[#pushed + 1] = selected
end
local pushable = { [7] = true }
C_QuestLog.IsPushableQuest = function(q)
    return pushable[q] == true
end
C_QuestLog.GetSelectedQuest = function()
    return selected
end
C_QuestLog.SetSelectedQuest = function(q)
    selected = q
end
local function setGroup(n)
    group = n
    fire("GROUP_ROSTER_UPDATE")
end
local function hear(text, channel, sender)
    fire("CHAT_MSG_ADDON", "LevelingAddon", text, channel or "PARTY", sender or "Friend-Realm")
end

T.load()
T.login()
assert(
    ns.db.partyVersion == true and ns.db.partyAnnounce == "off" and ns.db.partyShare == false,
    "only the version check is on"
)
assert(T.prefix == "LevelingAddon" and #T.prefix <= 16)

-- Messages: nothing alone, one a moment after somebody joins, none when somebody leaves.
wait(60)
assert(#sent == 0, "not in a group: nothing sent")
setGroup(2)
setGroup(2) -- the game repeats the event
assert(#sent == 0, "not at once")
wait(1)
assert(#sent == 1 and sent[1] == "LevelingAddon|V 1.2.3|PARTY", sent[1])
setGroup(3)
wait(1)
assert(#sent == 1, "throttled: the second message waits")
setGroup(4)
wait(8)
assert(#sent == 1, "still inside the interval")
wait(1)
assert(#sent == 2, "one message for both joins, when the interval is over")
setGroup(3)
wait(60)
assert(#sent == 2, "somebody left: nothing to say")
setGroup(0)
setGroup(2)
ns.db.partyVersion = false
wait(60)
assert(#sent == 2, "the check is off: nothing sent")
ns.db.partyVersion = true

-- What arrives: older, equal and malformed versions are ignored, and so is another channel.
local lines = #T.chat
for _, text in ipairs({
    "V 1.2.3",
    "V 1.2.2",
    "V 0.9.9",
    "V 2",
    "V 2.0",
    "V 2.0.0.1",
    "V 1234.0.0",
    "V 9.9.9 ",
    "V -2.0.0",
    "V |cffff0000 9.9.9",
    "v 9.9.9",
    "9.9.9",
    "S 12", -- a type from a later version
    "",
    string.rep("9", 255),
}) do
    hear(text)
end
fire("CHAT_MSG_ADDON", "LevelingAddon", nil, "PARTY", "Friend-Realm")
fire("CHAT_MSG_ADDON", "Other", "V 9.9.9", "PARTY", "Friend-Realm")
hear("V 9.9.9", "WHISPER", "Stranger-Realm")
assert(#T.chat == lines, "nothing reported")
ns.db.partyVersion = false
hear("V 9.9.9")
assert(#T.chat == lines, "the check is off: nothing reported")
ns.db.partyVersion = true

-- A newer version is reported once in a session.
hear("V 1.10.0")
assert(#T.chat == lines + 1 and T.chat[#T.chat]:find("Friend-Realm runs version 1.10.0. Yours is 1.2.3.", 1, true))
hear("V 2.0.0", "PARTY", "Other-Realm")
assert(#T.chat == lines + 1, "once")

-- Level-up announcement: off by default, then to the party or the guild, with the level's
-- time when the tracker (#19) is there.
ns.Tracker = nil
fire("PLAYER_LEVEL_UP", 10)
assert(#chat == 0, "off: nothing announced")
cmd("party announce party")
fire("PLAYER_LEVEL_UP", 11)
assert(chat[1] == "PARTY: Level 11!", chat[1])
-- The tracker is asked for the level just finished; a level it saw only part of has no time.
ns.Tracker = {
    LevelTime = function(level)
        return ({ [11] = 5025, [12] = 1500, [13] = 42, [14] = 600 })[level], level == 14
    end,
}
fire("PLAYER_LEVEL_UP", 12)
assert(chat[2] == "PARTY: Level 12! It took 1 h 23 min.", chat[2])
group = 0
fire("PLAYER_LEVEL_UP", 13)
assert(#chat == 2, "no party: nothing announced")
cmd("party announce guild")
fire("PLAYER_LEVEL_UP", 13)
assert(#chat == 2, "no guild: nothing announced")
guild = true
fire("PLAYER_LEVEL_UP", 13)
fire("PLAYER_LEVEL_UP", 14)
assert(chat[3] == "GUILD: Level 13! It took 25 min." and chat[4] == "GUILD: Level 14! It took 42 s.", chat[4])
cmd("party announce off")
cmd("party announce guild")
fire("PLAYER_LEVEL_UP", 15)
assert(chat[5] == "GUILD: Level 15!", chat[5])
cmd("party announce off")
fire("PLAYER_LEVEL_UP", 16)
assert(#chat == 5)

-- Quest sharing: off by default, then only in a group and only what can be shared, and the
-- quest log's selection is left as it was.
group = 2
selected = 3
fire("QUEST_ACCEPTED", 7)
assert(#pushed == 0, "off: nothing shared")
cmd("party share")
fire("QUEST_ACCEPTED", 7)
assert(#pushed == 1 and pushed[1] == 7 and selected == 3)
fire("QUEST_ACCEPTED", 8)
assert(#pushed == 1, "cannot be shared")
group = 0
fire("QUEST_ACCEPTED", 7)
assert(#pushed == 1, "alone")
group = 2
fire("QUEST_ACCEPTED", 5, 7) -- the classic client's arguments: quest log index, quest id
assert(#pushed == 2 and pushed[2] == 7)

-- The classic client's quest log, which works by index.
C_QuestLog.IsPushableQuest = nil
function GetQuestLogSelection()
    return selected
end
function SelectQuestLogEntry(index)
    selected = index
end
function GetQuestLogPushable()
    return selected == 5
end
fire("QUEST_ACCEPTED", 5, 7)
fire("QUEST_ACCEPTED", 6, 8)
assert(#pushed == 3 and pushed[3] == 5 and selected == 3)

-- /lvl party
cmd("party share")
cmd("party version")
assert(ns.db.partyShare == false and ns.db.partyVersion == false)
cmd("party version")
cmd("party announce loudly")
assert(ns.db.partyVersion == true and ns.db.partyAnnounce == "off")
cmd("party")
local status = "version check on, level-up announcement off, quest sharing off, sharing my step off"
assert(T.chat[#T.chat]:find(status, 1, true))
cmd("help")
assert(T.chat[#T.chat]:find("party", 1, true))

-- Our own step: sent to the party when it changes, as ids, never as text. ------------------

-- The character's current step and its count, as the planner and the quest log would have
-- them; the planner hands over a new table on every pass.
local current, have = nil, 0
ns.Steps.Current = function()
    return current and { kind = current[1], questID = current[2], name = current[3], need = current[4] }, 1
end
ns.Steps.Progress = function()
    return have
end
ns.Data = {
    plannerQuests = {
        [7] = {
            start = { { "Marshal McBride", 1429, 48.92, 41.61 } },
            finish = { { "Somebody Else", 1429, 1, 1 }, { "Marshal McBride", 1429, 48.92, 41.61 } },
            obj = { { "monster", "Kobold Vermin", 1429, 49.17, 36.55 }, { "item", "Candle", 1429, 49, 36 } },
        },
        [54] = { obj = { { "event", "Goldshire", 1429, 42, 65 } } },
    },
}
group = 0
setGroup(2)
wait(60)
sent = {}
local function step(kind, questID, name, need, count)
    current, have = kind and { kind, questID, name, need }, count or 0
    ns.Refresh()
end
step("kill", 7, "Kobold Vermin", 10, 6)
wait(60)
assert(#sent == 0, "off: nothing sent")
cmd("party step")
assert(ns.db.partyStep == true and #sent == 0, "not at once")
wait(1)
assert(sent[1] == "LevelingAddon|S 7 k 1 6 10|PARTY", sent[1])
ns.Refresh()
ns.Refresh() -- a planner pass, the same step in a new table
wait(60)
assert(#sent == 1, "the step did not change: nothing sent")
step("kill", 7, "Kobold Vermin", 10, 7)
wait(1)
assert(#sent == 2 and sent[2] == "LevelingAddon|S 7 k 1 7 10|PARTY", "a count is a change")
step("kill", 7, "Kobold Vermin", 10, 8)
wait(1)
assert(#sent == 2, "throttled")
step("loot", 7, "Candle", 4, 0)
wait(3)
assert(#sent == 2, "still inside the interval")
wait(1)
assert(#sent == 3 and sent[3] == "LevelingAddon|S 7 l 2 0 4|PARTY", "one message, with the latest step")
step("kill", 7, "Kobold Vermin", 10, 9)
step("loot", 7, "Candle", 4, 0)
wait(60)
assert(#sent == 3, "changed and changed back inside the interval: nothing to say")
step("accept", 7, "Marshal McBride")
wait(60)
step("turnin", 7, "Marshal McBride")
wait(60)
step("go", 54, "Goldshire")
wait(60)
assert(sent[4]:find("|S 7 a 1 0 0|", 1, true) and sent[5]:find("|S 7 t 2 0 0|", 1, true), sent[5])
assert(sent[6]:find("|S 54 g 1 0 0|", 1, true), sent[6])
step("kill", 999, "Not In The Data", 5, 1)
wait(60)
assert(sent[7] == "LevelingAddon|S 0|PARTY", "a step the data does not have is no step")
step()
wait(60)
assert(#sent == 7, "no step is no step still")
-- Somebody joins and has nothing of us yet; somebody leaves and nothing is said.
step("kill", 7, "Kobold Vermin", 10, 9)
wait(60)
sent = {}
setGroup(3)
wait(60)
assert(sent[1]:find("|V ", 1, true) and sent[2]:find("|S 7 k 1 9 10|", 1, true) and #sent == 2)
setGroup(2)
wait(60)
assert(#sent == 2)
-- Alone, nothing is sent; switched off in a party, the party is told once that there is no step.
setGroup(0)
step("kill", 7, "Kobold Vermin", 10, 10)
wait(60)
assert(#sent == 2, "alone")
setGroup(2)
wait(60)
sent = {}
cmd("party step")
wait(60)
assert(#sent == 1 and sent[1]:find("|S 0|", 1, true) and ns.db.partyStep == false)
setGroup(3)
step("loot", 7, "Candle", 4, 1)
wait(60)
assert(#sent == 2 and sent[2]:find("|V ", 1, true), "off: no step is sent, to newcomers either")

-- A party member's step: on their tooltip and in /lvl party, from our own data. ---------------

assert(hover("Friend") == "", "nothing known: nothing shown")
hear("S 7 k 1 6 10")
assert(hover("Friend") == "Leveling: Kobold Vermin 6/10", hover("Friend"))
assert(hover("Friend", false) == "", "somebody of the same name who is not in the party")
assert(hover("Stranger") == "" and hover(nil) == "")
lines = #T.chat
cmd("party")
assert(#T.chat == lines + 2 and T.chat[#T.chat]:find("Friend: Kobold Vermin 6/10", 1, true))
hear("S 7 a 1 0 0")
assert(hover("Friend") == "Leveling: ! Marshal McBride")
hear("S 7 t 2 0 0")
assert(hover("Friend") == "Leveling: ? Marshal McBride")
hear("S 54 g 1 0 0", "PARTY", "Friend") -- a sender without a realm
assert(hover("Friend") == "Leveling: Goldshire")
-- What our data cannot resolve is not shown: an unknown quest, an objective it does not have.
hear("S 999 k 1 1 5")
assert(hover("Friend") == "")
hear("S 7 k 3 1 5")
assert(hover("Friend") == "")
-- Everything else is dropped, and what was known stays.
hear("S 7 l 2 3 4")
for _, text in ipairs({
    "S 7 x 1 6 10",
    "S 7 k 1 6",
    "S 7 k 1 6 10 1",
    "S 7 k 0 6 10",
    "S 7 k 51 6 10",
    "S 7 k 1 10000 10",
    "S 7 k 1 6 10000",
    "S 10000000 k 1 6 10",
    "S -7 k 1 6 10",
    "S 7 k 1.5 6 10",
    "S 7 k 1 6 10 ",
    "S 7 k 1 6 |cffff0000",
    "S Kobold Vermin 6/10",
    "S",
    "S 7 k 1 6 " .. string.rep("9", 40),
}) do
    hear(text)
    assert(hover("Friend") == "Leveling: Candle 3/4", text)
end
hear("S 7 k 1 6 10", "WHISPER")
hear("S 7 k 1 6 10", "PARTY", "Stranger-Realm") -- not in our party
fire("CHAT_MSG_ADDON", "LevelingAddon", "S 7 k 1 6 10", "PARTY", nil)
assert(hover("Friend") == "Leveling: Candle 3/4" and hover("Stranger") == "")
-- A client that keeps a unit's identity from addons: nothing is shown.
function issecretvalue(value)
    return value == "mouseover"
end
assert(hover("Friend") == "")
issecretvalue = nil
-- No step any more, and a member who leaves is forgotten.
hear("S 0")
assert(hover("Friend") == "")
hear("S 7 l 2 3 4")
party = {}
setGroup(0)
party = { "Friend" }
assert(hover("Friend") == "", "left and came back: nothing known until they say so")

print("test_party: ok")
