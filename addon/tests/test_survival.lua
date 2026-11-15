-- The drowning alarm: when it sounds, once per dive, pause, surfacing, and /lvl drown.
-- The elite warning: which elites a step warns of, once each, and its setting.
-- From the repository root: lua5.1 addon/tests/test_survival.lua
local T = dofile("addon/tests/stub.lua")
local fire, cmd = T.fire, T.cmd

-- The game API only this feature calls. The timer keeps its delay, so that a test can let
-- time pass: wait(seconds) runs what has come due.
local sounds, waiting, breath = 0, {}, 0
local pings = 0
function PlaySound(kit, channel)
    assert((kit == 8959 or kit == 3175) and channel == "Master")
    if kit == 3175 then
        pings = pings + 1
    else
        sounds = sounds + 1
    end
end
function GetMirrorTimerProgress(timer)
    assert(timer == "BREATH")
    return breath
end
C_Timer.After = function(seconds, fn)
    waiting[#waiting + 1] = { at = T.now + seconds, fn = fn }
end
local function wait(seconds)
    T.now = T.now + seconds
    local due = waiting
    waiting = {}
    for _, timer in ipairs(due) do
        if timer.at <= T.now then
            timer.fn()
        else
            waiting[#waiting + 1] = timer
        end
    end
end

T.load()
T.login()
cmd("hide") -- nothing of the window's needs the update loop now
waiting = {} -- what start-up scheduled is not ours
assert(T.ns.db.drownAlarm == true, "on by default")

-- A dive with 60 seconds of breath: the alarm sounds once, with 15 seconds left.
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
assert(#waiting == 1 and not T.looping(), "one timer, no polling")
wait(44)
assert(sounds == 0)
wait(1)
assert(sounds == 1, "sounds with 15 seconds left")
wait(60)
assert(sounds == 1 and #waiting == 0)

-- Up for a breath and straight down again while still low: the same dive, no second alarm.
fire("MIRROR_TIMER_START", "BREATH", 10000, 60000, 10, 0, "Breath")
fire("MIRROR_TIMER_START", "BREATH", 12000, 60000, -1, 0, "Breath")
wait(60)
assert(sounds == 1 and #waiting == 0, "once per dive")

-- Breath recovered, then a new dive that ends early: nothing sounds after surfacing.
fire("MIRROR_TIMER_START", "BREATH", 12000, 60000, 10, 0, "Breath")
fire("MIRROR_TIMER_STOP", "BREATH")
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
wait(30)
fire("MIRROR_TIMER_START", "BREATH", 30000, 60000, 10, 0, "Breath")
wait(60)
fire("MIRROR_TIMER_STOP", "BREATH")
wait(60)
assert(sounds == 1, "surfacing drops the waiting alarm")

-- A faster drain is counted in real seconds, and another timer is not breath.
fire("MIRROR_TIMER_START", "EXHAUSTION", 1000, 60000, -1, 0, "Fatigue")
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -2, 0, "Breath")
wait(14)
assert(sounds == 1)
wait(1)
assert(sounds == 2, "30 seconds of bar at double speed is 15 seconds")
fire("MIRROR_TIMER_STOP", "BREATH")

-- Paused: the alarm waits, and is worked out again from what is left when the timer goes on.
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
wait(20)
fire("MIRROR_TIMER_PAUSE", "BREATH", 1)
wait(100)
assert(sounds == 2, "nothing sounds while paused")
breath = 40000
fire("MIRROR_TIMER_PAUSE", "BREATH", 0)
wait(24)
assert(sounds == 2)
wait(1)
assert(sounds == 3)
fire("MIRROR_TIMER_STOP", "BREATH")

-- A dive that starts already low sounds at once.
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, 10, 0, "Breath")
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
fire("MIRROR_TIMER_START", "BREATH", 9000, 60000, -1, 0, "Breath")
wait(0)
assert(sounds == 4)
fire("MIRROR_TIMER_STOP", "BREATH")

-- Switched off: silent. Switched on again: sounds on the next dive.
T.chat = {}
cmd("drown")
assert(T.ns.db.drownAlarm == false and T.chat[1]:find("drowning alarm off"), T.chat[1])
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
wait(60)
assert(sounds == 4, "silent while off")
fire("MIRROR_TIMER_STOP", "BREATH")
cmd("drown")
assert(T.ns.db.drownAlarm == true and T.chat[2]:find("drowning alarm on"))
fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
wait(45)
assert(sounds == 5)

-- Arguments the client should never send do not raise an error.
fire("MIRROR_TIMER_START", "BREATH")
fire("MIRROR_TIMER_PAUSE", "BREATH")
fire("MIRROR_TIMER_STOP")
assert(#waiting == 0)

-- The elite warning --------------------------------------------------------------------------
-- A level 10 Alliance character in Elwynn (map 1429). The list is what the collector exports.
local ns = T.ns
T.level = 10
ns.Data = {
    dangers = {
        [1429] = {
            mobs = {
                { id = 448, name = "Hogger", level = 11, patrols = true, quests = { 176 }, at = { 25, 92 } },
                { id = 2, name = "Far Away", level = 12, at = { 60, 60, 25, 86 } },
                { id = 3, name = "Old Foe", level = 4, at = { 25, 92 } },
                { id = 4, name = "Marshal", level = 20, side = "A", at = { 25, 92 } },
                { id = 5, name = "Warlord", level = 20, side = "H", at = { 26, 91 } },
                { id = 6, name = "Nameless Horror", at = { 30, 96 } },
            },
        },
    },
}
local function start(step)
    T.chat = {}
    ns.Steps:SetPlan({ step })
    ns.Refresh()
    return T.chat[1]
end
local function at(questID, x, y, map)
    return { kind = "kill", name = "Riverpaw Gnoll", questID = questID, map = map or 1429, x = x, y = y }
end

-- Nothing near, another zone, a zone without a list, a step without a point: silence.
assert(not start(at(1, 50, 50)) and not start(at(1, 25, 92, 1436)) and not start({ kind = "go", questID = 1 }))
assert(pings == 0)

-- The step's own quest target is not news; a step of another quest at the same place is.
assert(not start(at(176, 22, 92)), "no warning about the quest's own mob")
local line = start(at(1, 25.1, 92.1))
assert(line:find("Elite nearby: Hogger (level 11). Patrols the area. 1 more near this step.", 1, true), line)
assert(pings == 1 and #T.chat == 1, "one line and one sound")
-- Left out: far away (its near spawn is 6 away), far below the character, friendly to its side.
-- "Warlord" was the one counted.

-- Once per mob per session: the same place again says nothing, by a new step or a new pass.
ns.Refresh()
assert(not start(at(2, 25.1, 92.1)) and pings == 1)

-- An elite without a level, and no patrol: a shorter line.
line = start(at(3, 30, 96.5))
assert(
    line:find("Elite nearby: Nameless Horror.", 1, true) and not line:find("Patrols") and not line:find("more"),
    line
)

-- Switched off: silent, and the elite is still new when it is switched on again.
ns.Data.dangers[1429].mobs[7] = { id = 7, name = "Late Comer", level = 30, at = { 80, 80 } }
cmd("set eliteNotice off")
assert(ns.db.eliteNotice == false and not start(at(4, 80, 80)))
cmd("set eliteNotice on")
line = start(at(5, 80, 80))
assert(line and line:find("Late Comer (level 30).", 1, true) and pings == 3, line)

-- A level 40 character is not warned of a level 30 elite; a Horde one is warned of the Marshal.
ns.Data.dangers[1429].mobs[8] = { id = 8, name = "Small Fry", level = 30, at = { 10, 10 } }
T.level = 40
assert(not start(at(6, 10, 10)))
function UnitFactionGroup()
    return "Horde"
end
T.level = 10
line = start(at(7, 25, 92))
assert(line and line:find("Marshal (level 20).", 1, true), line)
print("ALL OK")
