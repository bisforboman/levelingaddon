-- The leveling tracker: time per level, XP split by source, deaths, unknown and partial levels,
-- and /lvl stats. From the repository root: lua5.1 addon/tests/test_tracker.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd
local asked = 0
function RequestTimePlayed()
    asked = asked + 1
end
T.load()

-- The addon is installed on a character half-way through level 5.
T.level, T.xp, T.xpMax = 5, 1000, 2800
T.login()
local t = ns.char.tracker
assert(asked == 1 and t.played == nil, "the game is asked for the time played once")
assert(t.levels[5].partial and t.levels[4] == nil, "the level in progress is partial, earlier ones unknown")
assert(ns.Tracker.LevelTime(4) == nil, "an unknown level has no time, not zero")

-- /played answers: from then on the total counts along.
fire("TIME_PLAYED_MSG", 36000, 1200)
T.now = 600
fire("PLAYER_DEAD")

-- A quest worth 1900 takes the character to level 6, 100 XP into it.
T.xp, T.xpMax = 100, 3600
fire("QUEST_TURNED_IN", 783, 1900, 0)
fire("PLAYER_XP_UPDATE", "player")
fire("PLAYER_LEVEL_UP", 6)
local five = t.levels[5]
assert(five.time == 600 and five.xp == 1900 and five.quest == 1900 and five.kill == 0, "level 5 is closed")
assert(five.deaths == 1 and t.level == 6 and t.played == 36600)
local seconds, partial = ns.Tracker.LevelTime(5)
assert(seconds == 600 and partial == true)

-- Level 6, all of it seen: a kill (announced before the XP arrives), a quest, an exploration.
T.now = 700
T.xp = 400
fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 300 experience.")
fire("PLAYER_XP_UPDATE", "player")
T.xp = 1400
fire("QUEST_TURNED_IN", 54, 1000, 0)
fire("PLAYER_XP_UPDATE", "player")
T.xp = 1500
fire("PLAYER_XP_UPDATE", "player")
local six = t.levels[6]
assert(six.xp == 1400 and six.quest == 1000 and six.kill == 300, "quest and kill XP are split; the rest is neither")

-- A new zone gets its own row; the old one keeps what happened in it.
T.now = 1000
T.zone = "Westfall"
fire("ZONE_CHANGED_NEW_AREA")
fire("PLAYER_DEAD")
local elwynn, westfall = t.zones["Elwynn Forest"], t.zones["Westfall"]
assert(elwynn.time == 1000 and elwynn.xp == 3300 and elwynn.quest == 2900 and elwynn.deaths == 1)
assert(westfall.deaths == 1 and six.deaths == 1)

-- The level-up announcement may ask before this file's own handler has run: same answer.
T.now = 2400
T.xp, T.xpMax = 50, 4500
seconds, partial = ns.Tracker.LevelTime(6)
assert(seconds == 1800 and partial == false, "a level finished after install has a time")
fire("CHAT_MSG_COMBAT_XP_GAIN", "Riverpaw Gnoll dies, you gain 2150 experience.")
fire("PLAYER_LEVEL_UP", 7)
assert(six.time == 1800 and six.xp == 3550 and six.kill == 2450 and not six.partial)
assert(ns.Tracker.LevelTime(6) == 1800 and t.played == 38400)

-- The summary: this level, the last three, the totals. Level 4 is unknown, never zero.
T.now = 2460
T.chat = {}
cmd("stats")
local out = table.concat(T.chat, "\n")
assert(out:find("level 7 so far: 1m 00s, 0 deaths"), out)
assert(out:find("level 6: 30m 00s, 7100 XP an hour, 28%% from quests, 69%% from kills, 1 death"), out)
assert(out:find("level 5: 10m 00s, .*100%% from quests, 0%% from kills, 1 death, partial"), out)
assert(out:find("level 4: unknown") and not out:find("level 3"), out)
assert(out:find("recorded in all: 41m 00s, .*2 deaths") and out:find("time played: 10h 41m"), out)
T.chat = {}
cmd("stats zones")
assert(#T.chat == 2 and T.chat[1]:find("Elwynn Forest: 16m 40s") and T.chat[2]:find("Westfall: 24m 20s"), T.chat[1])

-- Logging out saves the time; the next session goes on where this one stopped.
T.now = 2500
fire("PLAYER_LOGOUT")
assert(t.levels[7].time == 100)
T.now = 0
T.level = 7
T.login()
assert(asked == 1 and not t.levels[7].partial, "nothing was missed: not partial, and /played is not asked again")
T.now = 50
assert(ns.Tracker.LevelTime(7) == 150)

-- The character gained a level with the addon switched off: both levels are partial.
fire("PLAYER_LOGOUT")
T.level, T.xp = 8, 10
T.login()
assert(t.levels[7].partial and t.levels[8].partial and t.level == 8)
print("ALL OK")
