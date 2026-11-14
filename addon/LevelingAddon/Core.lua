-- Start-up, saved settings, the slash command, and the machinery every feature shares: one
-- event frame, debouncing, one throttled update loop, time-sliced jobs and timings. The
-- conventions are in the README under "Writing a feature". The window and the arrow only draw
-- what ns.Steps says; nothing in the step logic depends on a frame being shown.
local addonName, ns = ...

-- Defaults for the saved settings. A feature adds its own at file scope
-- (ns.defaults.key = value); they are applied at ADDON_LOADED, after every file has run.
ns.charDefaults = {} -- per character, saved as ns.char
ns.defaults = { -- account-wide, saved as ns.db
    shown = true, -- the window and arrow are visible
    arrow = true, -- draw our own arrow (ignored when TomTom takes the waypoint)
    rows = 8, -- steps in view
    scale = 1,
    skipped = {}, -- [step index] = true for steps the player chose to skip
}

local function say(text)
    print("|cfff2c230Leveling|r " .. text)
end
ns.say = say

local frame = CreateFrame("Frame")

-- Events ---------------------------------------------------------------------------------

local handlers = {} -- [event] = { handler, ... }

-- Call handler(event, ...) on a game event. Any number of handlers per event, called in the
-- order they were added. ADDON_LOADED arrives for this addon only, with ns.db and ns.char
-- ready.
function ns.On(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

-- Returns a function that folds a burst of calls into one call of fn, `seconds` after the
-- first of them.
function ns.Debounce(seconds, fn)
    local pending = false
    local function run()
        pending = false
        fn()
    end
    return function()
        if not pending then
            pending = true
            C_Timer.After(seconds, run)
        end
    end
end

-- Timings --------------------------------------------------------------------------------

local clock = debugprofilestop -- milliseconds, finer than a frame; nil if the client lacks it
local timers = {} -- [name] = milliseconds of the last report
local function newLoopStats()
    return { idle = { frames = 0, ms = 0, max = 0 }, moving = { frames = 0, ms = 0, max = 0 } }
end
local loopStats = newLoopStats()

-- Milliseconds, for measuring a stretch of work: local t = ns.Clock() ... ns.Clock() - t.
function ns.Clock()
    return clock and clock() or GetTime() * 1000
end

-- Record how long the named piece of work took the last time it ran.
function ns.Report(name, ms)
    timers[name] = ms
end

-- The numbers /lvl debug prints:
--   memoryKB  the addon's memory, nil if the client does not say
--   timers    [name] = milliseconds of the last ns.Report (and of each finished ns.Job)
--   loop      idle and moving, each { frames, ms, max }: frames the shared loop ran in, their
--             total and their longest, since the last ns.Stats(true)
-- Pass true to start the loop counters again.
function ns.Stats(reset)
    local memoryKB
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        memoryKB = GetAddOnMemoryUsage(addonName)
    end
    local stats = { memoryKB = memoryKB, timers = timers, loop = loopStats }
    if reset then
        loopStats = newLoopStats()
    end
    return stats
end

-- The shared update loop -----------------------------------------------------------------

local MAX_ERRORS = 3 -- failures in a row before a task is stopped for the session
local tasks = {} -- by name, and as a list
local running = 0 -- tasks switched on; the frame has an OnUpdate only while this is not 0

local function onUpdate(_, elapsed)
    local start = clock and clock()
    for i = 1, #tasks do
        local task = tasks[i]
        if task.on then
            task.wait = task.wait - elapsed
            if task.wait <= 0 then
                task.wait = task.seconds
                local ok, err = pcall(task.fn)
                if ok then
                    task.errors = 0
                else
                    task.errors = task.errors + 1
                    if task.errors >= MAX_ERRORS then
                        task.broken = true
                        ns.SetTask(task.name, false)
                        say("stopped '" .. task.name .. "' after repeated errors: " .. tostring(err))
                        say("the rest keeps working. /reload starts it again.")
                    end
                end
            end
        end
    end
    if start then
        local ms = clock() - start
        local moving = GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0
        local bucket = moving and loopStats.moving or loopStats.idle
        bucket.frames = bucket.frames + 1
        bucket.ms = bucket.ms + ms
        if ms > bucket.max then
            bucket.max = ms
        end
    end
end

-- Register fn to be called every `seconds` (0: every frame) while the task is switched on.
-- A task starts switched off.
function ns.Task(name, seconds, fn)
    local task = { name = name, seconds = seconds, fn = fn, on = false, wait = 0, errors = 0 }
    tasks[name] = task
    table.insert(tasks, task)
end

-- Switch a task on or off. The loop runs only while some task is on, so switch a task off
-- whenever it has nothing to do. A task stopped for its errors stays off.
function ns.SetTask(name, on)
    local task = tasks[name]
    on = on and not task.broken or false
    if task.on == on then
        return
    end
    task.on = on
    task.wait = 0
    running = running + (on and 1 or -1)
    frame:SetScript("OnUpdate", running > 0 and onUpdate or nil)
end

-- Time-sliced jobs -----------------------------------------------------------------------

local SLICE_MS = 2 -- time for jobs in one frame. A first guess: to be set from measurements.
local jobs = {} -- queue of { name, co, ms }
local sliceEnd = 0

-- Inside a job: give the frame back if this frame's time is used up. Call it between units
-- of work, never from inside pcall.
function ns.Pause()
    if not clock or clock() >= sliceEnd then
        coroutine.yield()
    end
end

-- Run fn() across frames, one job at a time in the order given. fn calls ns.Pause() between
-- units of work. When it finishes, the time it took is reported under `name`.
function ns.Job(name, fn)
    table.insert(jobs, { name = name, co = coroutine.create(fn), ms = 0 })
    ns.SetTask("jobs", true)
end

ns.Task("jobs", 0, function()
    local start = ns.Clock()
    sliceEnd = start + SLICE_MS
    repeat
        local job = jobs[1]
        local began = ns.Clock()
        local ok, err = coroutine.resume(job.co)
        job.ms = job.ms + ns.Clock() - began
        if not ok then
            table.remove(jobs, 1)
            say("'" .. job.name .. "' failed: " .. tostring(err))
        elseif coroutine.status(job.co) == "dead" then
            table.remove(jobs, 1)
            ns.Report(job.name, job.ms)
        end
    until not jobs[1] or not clock or clock() >= sliceEnd
    if not jobs[1] then
        ns.SetTask("jobs", false)
    end
end)

-- Redraw everything that shows steps. Called after any change to the route or settings.
function ns.Refresh()
    if ns.Window then
        ns.Window:Refresh()
    end
    if ns.Arrow then
        ns.Arrow:StepChanged()
    end
end

function ns.SetShown(shown)
    ns.db.shown = shown
    ns.Refresh()
    if not shown then
        say("hidden. /lvl brings it back.")
    end
end

-- Slash commands: /lvl name arg calls ns.commands.name(arg). A feature adds its own at file
-- scope; the help line is built from this table.
local commands = {}
ns.commands = commands

function commands.show()
    ns.SetShown(true)
end

function commands.hide()
    ns.SetShown(false)
end

function commands.arrow()
    ns.db.arrow = not ns.db.arrow
    ns.Refresh()
    say("arrow " .. (ns.db.arrow and "on" or "off") .. ".")
end

function commands.rows(arg)
    local n = tonumber(arg)
    if not n or n < 3 or n > 16 then
        say("rows takes a number from 3 to 16.")
        return
    end
    ns.db.rows = math.floor(n)
    ns.Refresh()
end

function commands.scale(arg)
    local n = tonumber(arg)
    if not n or n < 0.6 or n > 2 then
        say("scale takes a number from 0.6 to 2.")
        return
    end
    ns.db.scale = n
    ns.Refresh()
end

-- Put the window back where it starts.
function commands.reset()
    ns.db.point = nil
    ns.Window:RestorePosition()
end

-- Bring every skipped step back.
function commands.unskip()
    wipe(ns.db.skipped)
    ns.Steps:Sync()
    ns.Refresh()
end

-- Memory and timings, to hold the addon against its performance budget. The loop numbers
-- cover the time since the last /lvl debug: stand still, run it, move, run it again.
function commands.debug()
    local stats = ns.Stats(true)
    say(stats.memoryKB and string.format("memory %.0f KB", stats.memoryKB) or "memory: not available")
    local names = {}
    for name in pairs(stats.timers) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        say(string.format("%s: %.2f ms last time", name, stats.timers[name]))
    end
    for _, state in ipairs({ "idle", "moving" }) do
        local loop = stats.loop[state]
        if loop.frames == 0 then
            say("loop while " .. state .. ": did not run")
        else
            local text = "loop while %s: %.3f ms a frame, longest %.3f, over %d frames"
            say(string.format(text, state, loop.ms / loop.frames, loop.max, loop.frames))
        end
    end
end

SLASH_LEVELINGADDON1 = "/lvl"
SlashCmdList.LEVELINGADDON = function(message)
    local command, arg = strsplit(" ", strtrim(message or ""), 2)
    command = string.lower(command or "")
    if command == "" then
        ns.SetShown(not ns.db.shown)
    elseif commands[command] then
        commands[command](arg)
    else
        local names = {}
        for name in pairs(commands) do
            table.insert(names, name)
        end
        table.sort(names)
        say("/lvl, then one of: " .. table.concat(names, ", "))
    end
end

-- The addon list by the minimap calls this by name (see the TOC).
function LevelingAddon_OnCompartmentClick()
    ns.SetShown(not ns.db.shown)
end

-- Fill in whatever the saved table lacks. A default that is a table is copied, and filled in
-- key by key if it was saved before.
local function applyDefaults(saved, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(saved[key]) ~= "table" then
                saved[key] = {}
            end
            applyDefaults(saved[key], value)
        elseif saved[key] == nil then
            saved[key] = value
        end
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then
            return
        end
        LevelingAddonDB = LevelingAddonDB or {}
        LevelingAddonCharDB = LevelingAddonCharDB or {}
        ns.db = LevelingAddonDB
        ns.char = LevelingAddonCharDB
        ns.firstRun = ns.db.shown == nil
        applyDefaults(ns.db, ns.defaults)
        applyDefaults(ns.char, ns.charDefaults)
    end
    local list = handlers[event]
    for i = 1, list and #list or 0 do
        list[i](event, ...)
    end
end)

-- Quest events arrive in bursts (QUEST_LOG_UPDATE especially), so they only mark the state as
-- stale; one read of the quest log follows a moment later.
local syncSoon = ns.Debounce(0.2, function()
    if ns.Steps:Sync() then
        ns.Refresh()
    end
end)

ns.On("PLAYER_LOGIN", function()
    for _, name in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE" }) do
        ns.On(name, syncSoon)
    end
    ns.On("QUEST_TURNED_IN", function(_, questID)
        ns.Steps:NoteTurnedIn(questID)
        syncSoon()
    end)
    ns.Steps:Sync()
    ns.Window:Create()
    ns.Arrow:Create()
    ns.Refresh()
    if ns.firstRun then
        say("is on. Drag the window to move it. /lvl hides or shows it.")
    end
end)
