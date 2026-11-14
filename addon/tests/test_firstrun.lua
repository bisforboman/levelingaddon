-- First-run setup (issue #20): the panel is shown once per character, the two switches reach
-- the planner and ask for a pass, raid and PvP quests stay out, and a change keeps the skipped
-- quests and the progress (issue #24).
-- From the repository root: lua5.1 addon/tests/test_firstrun.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd

function UnitClass()
    return "Warrior", "WARRIOR"
end
function UnitRace()
    return "Human", "Human"
end

-- Tick boxes that remember their state.
local createFrame = CreateFrame
function CreateFrame(kind, ...)
    local frame = createFrame(kind, ...)
    if kind == "CheckButton" then
        rawset(frame, "SetChecked", function(self, checked)
            self.checked = checked
        end)
        rawset(frame, "GetChecked", function(self)
            return self.checked
        end)
    end
    return frame
end

-- A level 20 character; the stub puts every zone on the same spot, so all of them count as
-- next door. Quest 169 is a group quest; one quest of each other mark is added beside it.
T.level = 20
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", ns)
local quests, band = ns.Data.plannerQuests, ns.Data.plannerZones[1433].bands[4]
assert(quests[169].mark == "group")
for id, mark in pairs({ [900001] = "dungeon", [900002] = "raid", [900003] = "pvp" }) do
    local quest = {}
    for k, v in pairs(quests[169]) do
        quest[k] = v
    end
    quest.mark = mark
    quests[id] = quest
    band[#band + 1] = id
end

T.load()
local passes = 0
local run = ns.Planner.Run
function ns.Planner.Run(...)
    passes = passes + 1
    return run(...)
end

local function panel()
    for _, frame in ipairs(T.frames) do
        if frame.name == "LevelingAddonFirstRun" then
            return frame
        end
    end
end
-- The panel's widgets of one kind, in the order they were made.
local function parts(kind)
    local found = {}
    for _, frame in ipairs(T.frames) do
        if frame.kind == kind and frame.parent == panel() then
            found[#found + 1] = frame
        end
    end
    return found
end
local function click(widget)
    widget.scripts.OnClick(widget)
end
-- Quest ids the plan offers to pick up, as a set.
local function offered()
    local set = {}
    for _, step in ipairs(ns.Steps.list) do
        if step.kind == "accept" then
            set[step.questID] = true
        end
    end
    return set
end
local function said(text)
    for _, line in ipairs(T.chat) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

-- A hidden window comes back for the panel: it is what the player is asked to place.
LevelingAddonDB = { shown = false }

-- Not created before it is shown.
fire("ADDON_LOADED", "LevelingAddon")
assert(not panel(), "the panel is created only when shown")
fire("PLAYER_LOGIN")

-- First login of the character: the panel is up, both switches off, and the plan behind it
-- is already made, without dungeon, group, raid or PvP quests.
assert(panel() and panel().shown, "shown at the first login")
assert(not said("is on. Drag"), "the panel replaces the line in chat")
assert(ns.db.shown == true and ns.Window.frame.shown, "the window is visible beside the panel")
local checks, start = parts("CheckButton"), parts("Button")[1]
assert(#checks == 2 and not checks[1].checked and not checks[2].checked)
assert(ns.char.dungeons == false and ns.char.groups == false)
assert(passes == 1 and ns.Steps:Count() > 0, "one pass at login")
local now = offered()
assert(not (now[169] or now[900001] or now[900002] or now[900003]))

-- Something to keep: a skipped quest and a finished step.
local first = ns.Steps.list[1]
assert(first.kind == "accept")
T.log[first.questID] = {}
fire("QUEST_ACCEPTED", first.questID)
assert(ns.Steps.list[1] == first and ns.Steps:Status(1) == "done")
local skipIndex = ns.Steps:CurrentIndex()
local skipID = ns.Steps.list[skipIndex].questID
ns.Steps:Skip(skipIndex)
fire()
local function kept()
    return ns.Steps.list[1] == first and ns.Steps:Status(1) == "done" and ns.char.skipped[skipID] == true
end
assert(kept())

-- Ticking a box applies at once: saved for the character, read by the planner, one pass.
passes = 0
checks[2].checked = true
click(checks[2])
assert(ns.char.groups == true and ns.Planner.allow.group == true and not ns.Planner.allow.dungeon)
assert(passes == 0, "the pass is asked for, not run on the spot")
fire()
assert(passes == 1)
now = offered()
assert(now[169] and not (now[900001] or now[900002] or now[900003]), "group quests only")
assert(kept(), "a change keeps the progress and the skipped quests")

checks[1].checked = true
click(checks[1])
fire()
now = offered()
assert(ns.char.dungeons == true and ns.Planner.allow.dungeon == true)
assert(now[900001] and not (now[900002] or now[900003]), "raid and PvP quests stay out")
assert(not ns.Planner.allow.raid and not ns.Planner.allow.pvp)
assert(kept())

-- Start closes the panel for good.
assert(ns.char.setupDone == false)
click(start)
assert(not panel().shown and ns.char.setupDone == true)

-- The commands flip a switch or take on or off, and say what it is now.
cmd("dungeons")
assert(ns.char.dungeons == false and ns.Planner.allow.dungeon == false and said("dungeon quests off."))
cmd("groups on")
assert(ns.char.groups == true)
cmd("groups off")
assert(ns.char.groups == false and ns.Planner.allow.group == false and said("group quests off."))
fire()
now = offered()
assert(not (now[169] or now[900001]))
-- The switches on the settings page are the same two, by way of /lvl set.
cmd("set groups on")
assert(ns.char.groups == true and ns.Planner.allow.group == true)
assert(kept())

-- /lvl setup shows the same panel again, with the boxes as the settings are now.
local frames = #T.frames
cmd("setup")
assert(panel().shown and #T.frames == frames, "the panel is reused")
assert(checks[1].checked == false and checks[2].checked == true)
click(start)

-- The next login of this character: no panel, and the choice is back in the planner. The
-- account-wide copy is only what the settings page shows; the character's own value wins.
ns.Planner.allow.group = nil
ns.db.groups, ns.db.dungeons = false, true
T.login()
assert(not panel().shown, "not shown again")
assert(ns.Planner.allow.group == true and ns.Planner.allow.dungeon == false)
assert(ns.db.groups == true and ns.db.dungeons == false)

-- Another character on the same account: asked again, with both switches off.
LevelingAddonCharDB = nil
T.login()
assert(panel().shown, "once per character")
assert(ns.char.groups == false and ns.Planner.allow.group == false and ns.db.groups == false)
assert(checks[2].checked == false)
print("ALL OK")
