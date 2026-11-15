-- Survival: warnings that keep the character alive.
--
-- The drowning alarm: a warning sound when the breath timer is down to its last LOW seconds,
-- once per dive. The game's mirror timer events say when the breath timer starts, pauses and
-- stops; the moment it runs low is worked out from its value and rate and waited for with one
-- timer. Nothing is polled.
--
-- The elite warning: one line in chat and a short sound when a step starts near an elite mob.
-- The collector lists the elites of each zone map (ns.Data.dangers, README "Lua export"), so
-- a new step reads the list of its own zone and nothing else. The data only knows mobs that a
-- quest refers to: no warning never means there is no elite.
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

-- The elite warning ----------------------------------------------------------------------

ns.defaults.eliteNotice = true -- a warning, not automation: on unless switched off
ns.AddSetting({
    key = "eliteNotice",
    label = "Elite warning",
    tooltip = "Say in chat when a step starts near an elite mob that the quest data knows. "
        .. "It does not know every elite.",
    onChange = function() end, -- read when the next step starts; nothing to redraw
})

local NEAR = 4 -- how close to the step's point a spawn counts, in percent of the zone map
local BELOW = 5 -- an elite more than this many levels under the character is left out
local told = {} -- [npc id] = true for the elites named or counted this session
local last -- the step last looked at, as a key

local function contains(list, value)
    for i = 1, list and #list or 0 do
        if list[i] == value then
            return true
        end
    end
    return false
end

-- The square of the distance from the step's point to the mob's nearest spawn.
local function distance(mob, step)
    local best = math.huge
    for i = 1, #mob.at, 2 do
        local dx, dy = mob.at[i] - step.x, mob.at[i + 1] - step.y
        best = math.min(best, dx * dx + dy * dy)
    end
    return best
end

local function warn()
    local step = ns.Steps:Current()
    -- Not the table: the planner rebuilds the list on every pass.
    local key = step and table.concat({ step.kind, step.questID, tostring(step.name), step.map or 0 }, ":")
    if key == last then
        return
    end
    last = key
    local zone = step and step.x and ns.db.eliteNotice and ns.Data and ns.Data.dangers and ns.Data.dangers[step.map]
    if not zone then
        return
    end
    -- Hostile to this character, not far below its level, and not what the step's own quest
    -- sends the player to: the nearest is named, the rest are counted.
    local side = string.sub(UnitFactionGroup("player") or "", 1, 1)
    local level = UnitLevel("player") - BELOW
    local nearest, best, others = nil, math.huge, -1
    for _, mob in ipairs(zone.mobs) do
        if
            not told[mob.id]
            and mob.side ~= side
            and (mob.level or math.huge) >= level
            and not contains(mob.quests, step.questID)
        then
            local d = distance(mob, step)
            if d <= NEAR * NEAR then
                told[mob.id] = true
                others = others + 1
                if d < best then
                    nearest, best = mob, d
                end
            end
        end
    end
    if nearest then
        ns.say(
            "Elite nearby: "
                .. nearest.name
                .. (nearest.level and " (level " .. nearest.level .. ")." or ".")
                .. (nearest.patrols and " Patrols the area." or "")
                .. (others > 0 and " " .. others .. " more near this step." or "")
        )
        PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "Master")
    end
end

local refresh = ns.Refresh
function ns.Refresh()
    refresh()
    warn()
end
