-- Support tools: the report, the events for other addons, verbose output.
-- From the repository root: lua5.1 addon/tests/test_support.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd

-- The game API Support.lua calls, and the personal details it must never ask for.
local asked = {}
local function personal(name, value)
    _G[name] = function()
        asked[#asked + 1] = name
        return value
    end
end
personal("UnitName", "Secretname")
personal("UnitFullName", "Secretname")
personal("GetRealmName", "Secretrealm")
personal("GetNormalizedRealmName", "Secretrealm")
personal("GetGuildInfo", "Secretguild")
function UnitLevel()
    return 7
end
function UnitClass()
    return "Warrior", "WARRIOR"
end
function GetZoneText()
    return "Elwynn Forest"
end
function GetSubZoneText()
    return "Northshire Valley"
end
function GetBuildInfo()
    return "1.16.1", "60001", "Nov 1 2026", 16001
end

-- A listener, registered the way the README says, before the addon logs in.
local heard = {}
local function listen(registry, owner)
    for _, name in ipairs({ "StepShown", "QuestAccepted", "QuestTurnedIn" }) do
        registry:RegisterCallback("LevelingAddon." .. name, function(who, ...)
            assert(who == owner, "the owner comes first")
            heard[#heard + 1] = { name, ... }
        end, owner)
    end
end

T.load()
local me = {}
listen(LevelingAddonEvents, me)
T.login()

-- Step shown: once at login, then only when the current step changes.
assert(#heard == 1 and heard[1][1] == "StepShown", "the first step is announced at login")
assert(heard[1][2] == 1 and heard[1][3] == ns.Steps.list[1] and heard[1][3].questID == 783)
ns.Refresh()
cmd("rows 5")
fire("QUEST_LOG_UPDATE")
assert(#heard == 1, "a redraw without a new current step announces nothing")

-- Accepting a quest: the quest id, in the modern and in the classic argument order.
T.log[783] = {}
fire("QUEST_ACCEPTED", 783)
assert(#heard == 3, #heard)
assert(heard[2][1] == "QuestAccepted" and heard[2][2] == 783)
assert(heard[3][1] == "StepShown" and heard[3][2] == 2 and heard[3][3].kind == "turnin")
fire("QUEST_ACCEPTED", 4, 7)
assert(heard[4][1] == "QuestAccepted" and heard[4][2] == 7)

-- Handing one in.
T.log[783] = nil
T.completed[783] = true
fire("QUEST_TURNED_IN", 783, 40, 0)
assert(heard[5][1] == "QuestTurnedIn" and heard[5][2] == 783 and heard[5][3] == nil)
assert(heard[6][1] == "StepShown" and heard[6][2] == 3 and #heard == 6)

-- Skipping moves the current step too; a failing listener stops nothing.
LevelingAddonEvents:RegisterCallback("LevelingAddon.StepShown", function()
    error("someone else's bug")
end, {})
ns.Steps:Skip(3)
ns.Refresh()
assert(heard[7][1] == "StepShown" and heard[7][2] == 4)
LevelingAddonEvents:UnregisterCallback("LevelingAddon.StepShown", me)
cmd("unskip")
assert(#heard == 7, "an unregistered listener hears nothing")

-- Verbose output appears only while the mode is on.
T.chat = {}
ns.Debug("quiet")
assert(#T.chat == 0 and ns.db.verbose == false)
cmd("verbose")
T.chat = {}
ns.Debug("loud")
assert(#T.chat == 1 and T.chat[1]:find("loud"))
fire("QUEST_ACCEPTED", 33)
assert(table.concat(T.chat, "\n"):find("LevelingAddon.QuestAccepted 33", 1, true), "events are shown while verbose")
cmd("verbose")
T.chat = {}
ns.Debug("quiet again")
fire("QUEST_ACCEPTED", 33)
assert(#T.chat == 0)

-- The report: errors Core caught, timings, and every listed field.
ns.Job("bad", function()
    error("oops")
end)
T.tick(0.01)
ns.Report("sync", 1.5)
local frames = #T.frames
cmd("report")
local made = #T.frames - frames
assert(made > 0)
local box
for _, frame in ipairs(T.frames) do
    box = frame.kind == "EditBox" and frame or box
end
local text = box.text
assert(text == ns.ReportText())
local function has(plain)
    assert(text:find(plain, 1, true), "the report lacks: " .. plain .. "\n" .. text)
end
has("client: 1.16.1 build 60001, interface 16001")
has("character: level 7 WARRIOR")
has("zone: Elwynn Forest, Northshire Valley")
has("position: map 1429 at 49.2, 46.3")
has("steps: 3 of 17")
has(">3 { kind=accept, map=1429, name=Marshal McBride")
has("  rows = 5")
has("  skipped = {}")
has("  verbose = false")
has("character settings:")
has("data: not loaded")
has("  memory = 123 KB")
has("  sync = 1.50 ms last time")
has("  loop while idle = ")
has("recent errors:")
has("bad: ")
has("oops")
assert(#asked == 0, "the report asked for " .. tostring(asked[1]))
assert(not text:find("Secret"), "no name, realm or guild in the report")

-- The data version, once the data is loaded; and the window is made once.
ns.Data = { manifest = { commit = "3f10ca0751", counts = { quests = 5914 } } }
frames = #T.frames
cmd("report")
assert(#T.frames == frames, "the report window is created once")
assert(box.text:find("data: { commit=3f10ca0751, counts={ quests=5914 } }", 1, true), box.text)

-- Only the last ten errors are kept.
for i = 1, 12 do
    ns.Job("bad" .. i, function()
        error("oops")
    end)
end
T.tick(0.01)
assert(#ns.errors == 10 and ns.errors[10]:find("^bad12: ") and ns.errors[1]:find("^bad3: "))

-- Where the client has an EventRegistry, the events go through it.
T = dofile("addon/tests/stub.lua")
local triggered = {}
EventRegistry = {
    TriggerEvent = function(_, name, ...)
        triggered[#triggered + 1] = { name, ... }
    end,
}
T.load()
assert(LevelingAddonEvents == EventRegistry)
T.login()
assert(#triggered == 1 and triggered[1][1] == "LevelingAddon.StepShown" and triggered[1][2] == 1)
print("ALL OK")
