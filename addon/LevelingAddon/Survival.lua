-- Survival: the drowning alarm. A warning sound when the breath timer is down to its last
-- LOW seconds, once per dive. The game's mirror timer events say when the breath timer starts,
-- pauses and stops; the moment it runs low is worked out from its value and rate and waited
-- for with one timer. Nothing is polled.
local _, ns = ...

ns.defaults.drownAlarm = true -- a warning, not automation: on unless switched off
ns.AddSetting({
    key = "drownAlarm",
    label = "Drowning alarm",
    tooltip = "Sound a warning when the breath is about to run out.",
    onChange = function() end, -- read when the alarm is due; nothing to redraw
})

local LOW = 15 -- seconds of breath left when the alarm sounds
local rate -- the breath timer's seconds per second: negative under water, positive refilling
local warned = false -- the alarm has had its turn on this dive
local wanted = 0 -- changes whenever a waiting alarm is no longer wanted

-- Wait for the alarm from `value` milliseconds of breath, or drop the one waiting.
local function schedule(value)
    wanted = wanted + 1
    if type(value) ~= "number" or type(rate) ~= "number" or rate >= 0 then
        return
    end
    local left = value / 1000 / -rate
    if left > LOW then
        warned = false -- breath has recovered: the next low is a new one
    elseif warned then
        return
    end
    local mine = wanted
    C_Timer.After(math.max(left - LOW, 0), function()
        if mine ~= wanted then
            return
        end
        warned = true
        if ns.db.drownAlarm then
            PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
        end
    end)
end

ns.On("MIRROR_TIMER_START", function(_, timer, value, _, scale, paused)
    if timer == "BREATH" then
        rate = scale
        schedule(not (paused and paused ~= 0) and value)
    end
end)

ns.On("MIRROR_TIMER_PAUSE", function(_, timer, paused)
    if timer == "BREATH" then
        schedule(not (paused and paused ~= 0) and GetMirrorTimerProgress and GetMirrorTimerProgress(timer))
    end
end)

ns.On("MIRROR_TIMER_STOP", function(_, timer)
    if timer == "BREATH" then
        schedule()
    end
end)

function ns.commands.drown()
    ns.Set("drownAlarm", not ns.db.drownAlarm)
    ns.say("drowning alarm " .. (ns.db.drownAlarm and "on" or "off") .. ".")
end
