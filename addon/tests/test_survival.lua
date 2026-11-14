-- The drowning alarm: when it sounds, once per dive, pause, surfacing, and /lvl drown.
-- From the repository root: lua5.1 addon/tests/test_survival.lua
local T = dofile("addon/tests/stub.lua")
local fire, cmd = T.fire, T.cmd

-- The game API only this feature calls. The timer keeps its delay, so that a test can let
-- time pass: wait(seconds) runs what has come due.
local sounds, waiting, breath = 0, {}, 0
function PlaySound(kit, channel)
    assert(kit == 8959 and channel == "Master")
    sounds = sounds + 1
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
print("ALL OK")
