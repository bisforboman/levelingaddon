-- The machinery in Core that every feature shares: events, saved-setting defaults, debouncing,
-- the update loop and its error stop, jobs, timings, /lvl debug and the command table.
-- From the repository root: lua5.1 addon/tests/test_core.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick, cmd = T.ns, T.fire, T.tick, T.cmd
LevelingAddonDB = { nested = { kept = 1 } } -- saved by an earlier session
T.load()

-- What a feature file does at file scope, after Core has run.
local seen = {}
ns.defaults.nested = { kept = 0, added = { 1, 2 } }
ns.charDefaults.route = { at = 1 }
ns.On("ADDON_LOADED", function(_, name)
    seen[#seen + 1] = name .. (ns.db and ns.char and " ready" or "")
end)
ns.On("PLAYER_LOGIN", function()
    seen[#seen + 1] = ns.Window.frame and "login after Core" or "login"
end)
ns.On("PLAYER_LOGIN", function()
    seen[#seen + 1] = "second"
end)
T.login()
assert(ns.db == LevelingAddonDB and ns.char == LevelingAddonCharDB)
assert(ns.db.nested.kept == 1 and ns.db.nested.added[2] == 2, "table defaults fill in what is missing")
assert(ns.db.nested.added ~= ns.defaults.nested.added and ns.char.route.at == 1, "defaults are copied")
assert(table.concat(seen, ", ") == "LevelingAddon ready, login after Core, second", table.concat(seen, ", "))

-- Nothing needs updating while the window is hidden.
cmd("hide")
assert(not T.looping(), "no task is on: no OnUpdate")

-- Debounce: a burst is one call, and the next burst is one more.
local calls = 0
local soon = ns.Debounce(0.2, function()
    calls = calls + 1
end)
soon()
soon()
soon()
assert(calls == 0 and #T.timers == 1)
fire("QUEST_LOG_UPDATE")
assert(calls == 1)
soon()
fire("QUEST_LOG_UPDATE")
assert(calls == 2)

-- A task runs at its interval while it is on.
ns.Stats(true)
local runs = 0
ns.Task("test", 0.5, function()
    runs = runs + 1
    T.clockMs = T.clockMs + 2
end)
ns.SetTask("test", true)
tick(0.1)
assert(runs == 1, "a task runs on the first frame after it is switched on")
tick(0.2)
tick(0.2)
assert(runs == 1)
T.speed = 7
tick(0.2)
assert(runs == 2)
T.speed = 0
ns.SetTask("test", false)
assert(not T.looping())
local stats = ns.Stats(true)
assert(stats.memoryKB == 123.4)
assert(stats.loop.idle.frames == 3 and stats.loop.idle.ms == 2 and stats.loop.idle.max == 2)
assert(stats.loop.moving.frames == 1 and stats.loop.moving.ms == 2)
assert(ns.Stats().loop.idle.frames == 0, "Stats(true) starts the counters again")

-- A task that keeps failing is stopped, the player is told once, and the rest goes on.
local attempts = 0
ns.Task("broken", 0, function()
    attempts = attempts + 1
    error("boom")
end)
ns.SetTask("broken", true)
ns.SetTask("test", true)
T.chat = {}
for _ = 1, 10 do
    tick(1)
end
assert(attempts == 3, "stopped after three failures in a row")
assert(#T.chat == 2 and T.chat[1]:find("stopped 'broken'") and T.chat[1]:find("boom"), T.chat[1])
assert(runs == 12, "the other task kept running")
ns.SetTask("broken", true)
tick(1)
assert(attempts == 3, "a stopped task stays off")
ns.SetTask("test", false)
assert(not T.looping())

-- A job is spread over frames: each unit of work takes 1 ms here, and a frame allows a few.
local units, frames = 0, 0
ns.Job("planner", function()
    for _ = 1, 10 do
        units = units + 1
        T.clockMs = T.clockMs + 1
        ns.Pause()
    end
end)
ns.Job("bad", function()
    error("oops")
end)
T.chat = {}
while T.looping() do
    tick(0.01)
    frames = frames + 1
    assert(frames <= 10, "the jobs never finish")
end
assert(units == 10 and frames > 1 and frames <= 10)
assert(ns.Stats().timers.planner == 10, "a finished job reports its time")
assert(#T.chat == 1 and T.chat[1]:find("'bad' failed") and T.chat[1]:find("oops"))

-- Timings a feature reports itself, and the debug command.
local t = ns.Clock()
T.clockMs = T.clockMs + 1.5
ns.Report("sync", ns.Clock() - t)
T.chat = {}
cmd("debug")
local out = table.concat(T.chat, "\n")
assert(out:find("memory 123 KB") and out:find("planner: 10.00 ms") and out:find("sync: 1.50 ms"), out)
assert(out:find("loop while idle: [%d.]+ ms a frame") and out:find("loop while moving: did not run"), out)

-- A feature's own command, and the help line built from the table.
local got
ns.commands.mine = function(a)
    got = a
end
cmd("mine 42")
assert(got == "42")
T.chat = {}
cmd("nonsense")
local help = ", mine, " -- features add commands of their own, so the whole list is not fixed here
assert(T.chat[1]:find(help), T.chat[1])
T.chat = {}
cmd("help")
assert(T.chat[1]:find(help))
print("ALL OK")
