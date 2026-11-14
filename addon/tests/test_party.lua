-- Party features: the version check and its throttle, the level-up announcement, quest sharing
-- and /lvl party. The game API they call is stubbed here, on top of stub.lua.
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
local party = ns.db.party
assert(party.version == true and party.announce == "off" and party.share == false, "only the version check is on")
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
party.version = false
wait(60)
assert(#sent == 2, "the check is off: nothing sent")
party.version = true

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
party.version = false
hear("V 9.9.9")
assert(#T.chat == lines, "the check is off: nothing reported")
party.version = true

-- A newer version is reported once in a session.
hear("V 1.10.0")
assert(#T.chat == lines + 1 and T.chat[#T.chat]:find("Friend-Realm runs version 1.10.0. Yours is 1.2.3.", 1, true))
hear("V 2.0.0", "PARTY", "Other-Realm")
assert(#T.chat == lines + 1, "once")

-- Level-up announcement: off by default, then to the party or the guild, with the level's
-- time when the tracker (#19) is there.
fire("PLAYER_LEVEL_UP", 10)
assert(#chat == 0, "off: nothing announced")
cmd("party announce party")
fire("PLAYER_LEVEL_UP", 11)
assert(chat[1] == "PARTY: Level 11!", chat[1])
ns.LevelTime = function(level)
    return ({ [12] = 5025, [13] = 1500, [14] = 42 })[level]
end
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
fire("PLAYER_LEVEL_UP", 15)
assert(#chat == 4)

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
assert(party.share == false and party.version == false)
cmd("party version")
cmd("party announce loudly")
assert(party.version == true and party.announce == "off")
cmd("party")
assert(T.chat[#T.chat]:find("version check on, level-up announcement off, quest sharing off", 1, true))
cmd("help")
assert(T.chat[#T.chat]:find("party", 1, true))

print("test_party: ok")
