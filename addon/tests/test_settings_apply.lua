-- Every setting applies at once (#24): each control on the settings page is changed, through
-- the page's own setter, and what the setting is for is checked right after, with no reload
-- and with the steps' progress untouched. A setting that has no check here fails the test, so
-- a feature that adds a setting adds its check to `effects` below (or to `PREFERENCES`).
-- From the repository root: lua5.1 addon/tests/test_settings_apply.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick, cmd = T.ns, T.fire, T.tick, T.cmd

-- The settings page: every control's key and the setter the game would call.
local registered
local dropdown = {} -- what the one dropdown offers, as "value=Label"
Settings = {
    RegisterVerticalLayoutCategory = function()
        return {}, { AddInitializer = function() end }
    end,
    RegisterProxySetting = function(_, variable, _, _, _, _, set)
        registered[variable:match("^LevelingAddon_(.+)$")] = set
        return {}
    end,
    CreateSliderOptions = function()
        return { SetLabelFormatter = function() end }
    end,
    CreateSlider = function() end,
    CreateCheckbox = function() end,
    CreateDropdown = function(_, _, options)
        dropdown = options()
    end,
    CreateControlTextContainer = function()
        local data = {}
        return {
            Add = function(_, value, label)
                data[#data + 1] = value .. "=" .. label
            end,
            GetData = function()
                return data
            end,
        }
    end,
    RegisterAddOnCategory = function() end,
}
function CreateSettingsButtonInitializer() end

-- Run the timers that are waiting, and those they start.
local function flush(t)
    t = t or T
    while t.timers[1] do
        table.remove(t.timers, 1)()
    end
end

-- The game API the features call, each as small as its check needs. ------------------------

local did = {} -- what the addon called, in order
local function call(name)
    return function(arg)
        did[#did + 1] = name .. (arg ~= nil and " " .. tostring(arg) or "")
    end
end
local function done()
    local text = table.concat(did, ", ")
    did = {}
    return text
end

PlaySound = call("sound")

-- Items: 1 is a grey that sells, 3 is needed for quest 100, 50 is quest 7's usable item.
function GetItemInfo(item)
    return "Item", item, 0, 10, 1, "", "", 1, "INVTYPE_HEAD", "", item == "cheap" and 50 or 100, 15
end
local bag = {}
C_Container = {
    GetContainerNumSlots = function(index)
        return index == 0 and #bag or 0
    end,
    GetContainerItemInfo = function(_, slot)
        return bag[slot] and { itemID = bag[slot], stackCount = 1, quality = 0 }
    end,
    UseContainerItem = function(_, slot)
        did[#did + 1] = "sold " .. bag[slot]
        bag[slot] = nil
    end,
    GetItemCooldown = function()
        return 0, 0
    end,
}
T.bags[50], T.itemSpells[50] = 1, "Use"

-- A party of two, and a friend whose messages arrive.
C_AddOns = {
    GetAddOnMetadata = function()
        return "1.2.3"
    end,
}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(_, text)
        did[#did + 1] = "sent " .. text
    end,
    SendChatMessage = function(text, channel)
        did[#did + 1] = channel .. " " .. text
    end,
}
function IsInGroup()
    return true
end
function IsInGuild()
    return false
end
function GetNumGroupMembers()
    return 2
end
function UnitName(unit)
    return unit == "party1" and "Friend" or nil
end
QuestLogPushQuest = call("shared")

-- A flight map with one flight on it, and a character who is in the air once it is taken.
function TakeTaxiNode() end
function NumTaxiNodes()
    return 2
end
function TaxiNodeName(slot)
    return slot == 1 and "Here, Zone" or "There, Zone"
end
function TaxiNodeGetType(slot)
    return slot == 1 and "CURRENT" or "REACHABLE"
end
function UnitOnTaxi()
    return true
end

-- The quest windows.
local quest, choices = 0, 0
function IsShiftKeyDown()
    return false
end
function GetQuestID()
    return quest
end
function GetNumQuestChoices()
    return choices
end
function GetQuestItemLink(_, i)
    return i == 1 and "dear" or "cheap"
end
function GetQuestItemInfo()
    return "name", "texture", 1, 1, true
end
function GetInventoryItemLink() end
AcceptQuest = call("accept")
GetQuestReward = call("reward")
local buttons = {}
for i = 1, 2 do
    buttons[i] = CreateFrame("Button")
    buttons[i].type = "choice"
    rawset(buttons[i], "GetID", function()
        return i
    end)
end
QuestInfoRewardsFrame = { RewardButtons = buttons }
T.frames = {} -- so that Core's frame is the first again

-- An item tooltip.
local tooltipLines, showTooltip = 0, nil
GameTooltip = {
    AddLine = function()
        tooltipLines = tooltipLines + 1
    end,
}
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(_, fn)
        showTooltip = fn
    end,
}

-- The fixed route and the plain quest data; no planner data, so no pass replaces the route.
T.load()
C_QuestLog.IsPushableQuest = function()
    return true
end
C_QuestLog.GetSelectedQuest = function() end
C_QuestLog.SetSelectedQuest = function() end
ns.Steps.list = dofile("addon/tests/northshire.lua")
ns.Data = {
    quests = { [7] = { sourceItemId = 50 }, [100] = { name = "Wolves", objectives = { items = { { id = 3 } } } } },
    items = { [3] = {} },
}
registered = {}
T.login()
flush()
local W, Arrow, Steps = ns.Window, ns.Arrow, ns.Steps

-- Some progress to lose: two steps done, a quest skipped, a count on the current step (the
-- sixth: kill Kobold Vermin, 4 of 10).
T.completed[783] = true
fire("QUEST_TURNED_IN", 783)
Steps:Skip(4)
T.log[7] = { need = 10, have = 4 }
fire("QUEST_ACCEPTED", 7)
flush()
local function progress(steps)
    local out = {}
    for index, step in ipairs(steps.list) do
        out[index] = step.kind .. step.questID .. steps:Status(index) .. steps:Progress(index)
    end
    return table.concat(out, " ")
end
local before = progress(Steps)
assert(before:find("accept783done0 turnin783done0 accept7done0 accept33skipped0 loot33skipped0 kill7pending4", 1, true))
done()

local function frameNamed(name)
    for _, frame in ipairs(T.frames) do
        if frame.name == name then
            return frame
        end
    end
end
local function rowsShown()
    local n = 0
    for _, row in ipairs(W.rows) do
        n = n + (row.shown and 1 or 0)
    end
    return n
end
local function combat(on)
    local event = on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"
    W.frame.scripts.OnEvent(nil, event)
    Arrow.frame.scripts.OnEvent(nil, event)
end

-- [key] = function(set): change the setting with set(value) and check what it is for. --------
local effects = {}

function effects.scale(set)
    local scale
    W.frame.SetScale = function(_, value)
        scale = value
    end
    set(1.5)
    assert(scale == 1.5)
end

function effects.opacity(set)
    local alpha
    W.background.SetColorTexture = function(_, _, _, _, a)
        alpha = a
    end
    set(0.2)
    assert(math.abs(alpha - 0.2) < 1e-9)
end

function effects.rows(set)
    set(4)
    assert(rowsShown() == 4)
    set(12)
    assert(rowsShown() == 12)
end

function effects.arrow(set)
    assert(Arrow.frame.shown)
    set(false)
    assert(not Arrow.frame.shown)
    set(true)
    assert(Arrow.frame.shown)
end

function effects.pin(set)
    local pin
    for _, frame in ipairs(T.frames) do
        pin = pin or frame.parent == Minimap and frame
    end
    assert(pin.shown)
    set(false)
    assert(not pin.shown)
    set(true)
    assert(pin.shown)
end

function effects.combatDim(set)
    combat(true)
    assert(rowsShown() == 1 and W.frame.alpha == 0.4 and Arrow.frame.alpha == 0.4)
    set(false)
    assert(rowsShown() == ns.db.rows and W.frame.alpha == 1 and Arrow.frame.alpha == 1, "in the middle of a fight")
    set(true)
    assert(rowsShown() == 1 and W.frame.alpha == 0.4 and Arrow.frame.alpha == 0.4)
    combat(false)
end

function effects.locked(set)
    local moves = 0
    W.frame.StartMoving = function()
        moves = moves + 1
    end
    local function drag()
        W.header.scripts.OnDragStart()
        W.header.scripts.OnDragStop()
    end
    set(true)
    drag()
    assert(moves == 0)
    set(false)
    drag()
    assert(moves == 1)
    ns.db.point = nil
end

-- A dive, and the wait for the last seconds of breath (the stub's timers do not wait).
function effects.drownAlarm(set)
    local function dive()
        fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0)
        fire("MIRROR_TIMER_STOP", "BREATH")
        return done()
    end
    set(false)
    assert(dive() == "")
    set(true)
    assert(dive() == "sound 8959")
end

-- A step that starts beside an elite the data lists. The step is only shown to the warning;
-- the plan is not touched.
function effects.eliteNotice(set)
    ns.Data = ns.Data or {}
    local data, current = ns.Data, ns.Steps.Current
    local dangers = data.dangers
    local function start(questID, name)
        data.dangers = { [1] = { mobs = { { id = questID, name = name, at = { 50, 50 } } } } }
        ns.Steps.Current = function(self)
            local _, index = current(self)
            return { kind = "go", name = "Somewhere", questID = questID, map = 1, x = 50, y = 50 }, index or 1
        end
        T.chat = {}
        ns.Refresh()
        return done() .. (T.chat[1] and T.chat[1]:match(" Elite.*") or "")
    end
    set(false)
    assert(start(-1, "Brute") == "")
    set(true)
    assert(start(-2, "Ogre") == "sound 3175 Elite nearby: Ogre.")
    data.dangers, ns.Steps.Current = dangers, current
    ns.Refresh()
end

-- At an open vendor the change counts at once, both ways.
function effects.junkSell(set)
    local function sell()
        for _ = 1, 5 do
            if T.looping() then
                tick(0.1)
            end
        end
        return done()
    end
    cmd("hide") -- so that only the selling keeps the update loop running
    bag = { 1, 1 }
    fire("MERCHANT_SHOW")
    assert(sell() == "", "off: nothing is sold")
    set(true)
    tick(0.1)
    assert(done() == "sold 1", "on: sold without leaving the vendor")
    set(false)
    assert(sell() == "" and bag[1] == 1, "off: the rest is kept")
    fire("MERCHANT_CLOSED")
    cmd("show")
    done()
end

function effects.partyVersion(set)
    local function hear()
        local lines = #T.chat
        fire("CHAT_MSG_ADDON", "LevelingAddon", "V 9.9.9", "PARTY", "Friend")
        return #T.chat - lines
    end
    set(false)
    flush()
    assert(done() == "" and hear() == 0, "off: nothing is sent or reported")
    set(true)
    flush()
    assert(done() == "sent V 1.2.3", "on: the party is told now, not at the next join")
    assert(hear() == 1)
end

-- The tracker's line at a level-up.
function effects.levelLine(set)
    local function line()
        T.chat = {}
        fire("PLAYER_LEVEL_UP", ns.char.tracker.level + 1)
        return table.concat(T.chat, "\n"):find("took") ~= nil
    end
    assert(line())
    set(false)
    assert(not line())
    set(true)
    assert(line())
end

function effects.partyAnnounce(set)
    local function levelUp()
        fire("PLAYER_LEVEL_UP", 2)
        return done()
    end
    assert(levelUp() == "")
    set("party")
    assert(levelUp():find("^PARTY Level 2!"))
    set("guild")
    assert(levelUp() == "", "not in a guild")
    set("off")
    assert(levelUp() == "")
end

function effects.partyShare(set)
    local function accept()
        fire("QUEST_ACCEPTED", 999) -- not a quest of the route
        return done()
    end
    assert(accept() == "")
    set(true)
    assert(accept() == "shared")
    set(false)
    assert(accept() == "")
end

function effects.verbose(set)
    local function debug()
        local lines = #T.chat
        ns.Debug("ping")
        return #T.chat - lines
    end
    assert(debug() == 0)
    set(true)
    assert(debug() == 1)
    set(false)
    assert(debug() == 0)
end

function effects.itemHint(set)
    local function lines()
        tooltipLines = 0
        showTooltip(GameTooltip, { id = 3 })
        return tooltipLines
    end
    assert(lines() == 1)
    set(false)
    assert(lines() == 0)
    set(true)
    assert(lines() == 1)
end

-- Quest 15 has a pending pick-up on the route, quest 7 a pending hand-in. A window that is
-- open when the setting changes is looked at again.
function effects.autoAccept(set)
    set(false)
    quest = 15
    fire("QUEST_DETAIL")
    assert(done() == "")
    set(true)
    assert(done() == "accept", "the open window is accepted")
    fire("QUEST_FINISHED")
end

function effects.autoTurnIn(set)
    set(false)
    quest = 7
    fire("QUEST_COMPLETE")
    assert(done() == "")
    set(true)
    assert(done() == "reward 0", "the open window is handed in")
    fire("QUEST_FINISHED")
end

-- The current step, kill Kobold Vermin with 4 of 10, goes to the party, and is taken back.
function effects.partyStep(set)
    ns.Data.plannerQuests = { [7] = { obj = { { "monster", "Kobold Vermin" } } } }
    flush()
    assert(done() == "", "off: nothing is sent")
    set(true)
    flush()
    assert(done() == "sent S 7 k 1 4 10", "on: the party is told now, not at the next step")
    set(false)
    flush()
    assert(done() == "sent S 0", "off: the party no longer has a step of ours")
    ns.Data.plannerQuests = nil
end

-- A choice of two rewards: the badges are on the game's buttons, or hidden.
function effects.rewardMarks(set)
    local made = #T.frames
    quest, choices = 1, 2
    fire("QUEST_COMPLETE")
    local coin, arrow = T.frames[made + 1], T.frames[made + 2]
    assert(coin.shown and arrow.shown and #T.frames == made + 2)
    set(false)
    assert(not coin.shown and not arrow.shown, "the open window loses its marks")
    set(true)
    assert(coin.shown and arrow.shown)
    fire("QUEST_FINISHED")
    choices = 0
end

function effects.itemButton(set)
    local button = frameNamed("LevelingAddonItemButton")
    assert(button.shown)
    set(false)
    assert(not button.shown)
    set(true)
    assert(button.shown)
end

-- In flight: the timer is in the arrow's frame, or the frame is the arrow's again.
function effects.flightTimer(set)
    ns.Data = ns.Data or {}
    ns.Data.taxiNodes = { [1] = { name = "Here, Zone" }, [2] = { name = "There, Zone" } }
    ns.Data.taxiPaths = { [1] = { to = { [2] = 90 } } }
    fire("TAXIMAP_OPENED")
    TakeTaxiNode(2)
    fire("PLAYER_CONTROL_LOST")
    tick(0.2)
    assert(ns.Arrow.flightTime.text == "1:30" and ns.Arrow.flightName.text == "There")
    set(false)
    assert(ns.Arrow.flightTime.text == "", "the timer goes in the middle of a flight")
    set(true)
    assert(ns.Arrow.flightTime.text == "1:30")
    fire("PLAYER_CONTROL_GAINED")
    assert(ns.Arrow.flightTime.text == "")
    ns.Data.taxiNodes, ns.Data.taxiPaths = nil, nil
end

-- The preferences: settings that change what the planner suggests. They are checked further
-- down, on planner data. [key] = the planner's mark for the quests the setting lets in.
local PREFERENCES = { dungeons = "dungeon", groups = "group" }

local keys = {}
for key in pairs(registered) do
    keys[#keys + 1] = key
end
table.sort(keys)
assert(#keys >= 19, "the page was built")
assert(table.concat(dropdown, " ") == "off=Off party=Party guild=Guild")
for _, key in ipairs(keys) do
    assert(effects[key] or PREFERENCES[key], "setting '" .. key .. "' has no check in test_settings_apply.lua")
    if effects[key] then
        local default = ns.db[key]
        assert(default == ns.defaults[key], key .. " is at its default until it is changed")
        effects[key](registered[key])
        registered[key](default)
        flush()
        done()
    end
end
assert(progress(Steps) == before, "no step lost its state:\n" .. before .. "\n" .. progress(Steps))

-- A feature's own slash command changes its setting the way the page does: through ns.Set.
local set, viaSet = ns.Set, nil
ns.Set = function(key, value)
    viaSet = key
    set(key, value)
end
for command, key in pairs({
    ["arrow"] = "arrow",
    ["rows 8"] = "rows",
    ["scale 1"] = "scale",
    ["lock"] = "locked",
    ["pin"] = "pin",
    ["drown"] = "drownAlarm",
    ["junk"] = "junkSell",
    ["verbose"] = "verbose",
    ["party version"] = "partyVersion",
    ["party share"] = "partyShare",
    ["party step"] = "partyStep",
    ["party announce guild"] = "partyAnnounce",
    ["set itemHint"] = "itemHint",
}) do
    viaSet = nil
    local value = ns.db[key]
    cmd(command)
    assert(viaSet == key, "/lvl " .. command)
    assert(ns.db[key] ~= value or command:find("%d"), "/lvl " .. command .. " changes " .. key)
end
cmd("set partyAnnounce loudly")
assert(ns.db.partyAnnounce == "guild" and T.chat[#T.chat]:find("one of: off, party, guild"))
cmd("set partyAnnounce party")
assert(ns.db.partyAnnounce == "party")

-- Preferences, on planner data: a level 17 character with one quest in the log, 2 of 5. -----
-- A changed preference is one debounced planner pass, and a pass keeps the finished steps
-- above the plan, the skipped quests and the counts.
LevelingAddonDB, LevelingAddonCharDB = nil, nil
local P = dofile("addon/tests/stub.lua")
local pns = P.ns
-- The planner reads the quest log as a list.
local function logged()
    local ids = {}
    for id in pairs(P.log) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end
C_QuestLog.GetNumQuestLogEntries = function()
    return #logged()
end
C_QuestLog.GetInfo = function(index)
    return { questID = logged()[index] }
end
function UnitClass()
    return "Warrior", "WARRIOR"
end
function UnitRace()
    return "Human", "Human"
end
P.level = 17
P.log[174] = { need = 5, have = 2 }
P.load()
assert(loadfile("addon/tests/planner_data.lua"))("LevelingAddon", pns)
registered = {}
P.login()
P.fire("PLAYER_ENTERING_WORLD")
flush(P)

local function find(kind, questID)
    for index, step in ipairs(pns.Steps.list) do
        if step.kind == kind and step.questID == questID then
            return index
        end
    end
end
P.log[163] = {}
P.fire("QUEST_ACCEPTED", 163)
flush(P)
pns.Steps:Skip(find("accept", 164))
local function kept()
    local done163, skipped164, loot = find("accept", 163), find("accept", 164), find("loot", 174)
    return done163 == 1
        and pns.Steps:Status(done163) == "done"
        and pns.Steps:Status(skipped164) == "skipped"
        and pns.char.skipped[164]
        and pns.Steps:Progress(loot) == 2
        and pns.Steps.list[loot].need == 5
end
assert(kept())

local passes = 0
local run = pns.Planner.Run
pns.Planner.Run = function(...)
    passes = passes + 1
    return run(...)
end
-- Through the setting where a feature has registered one (#20), else straight to the planner.
local function prefer(key, value)
    local mark = PREFERENCES[key]
    if registered[key] then
        registered[key](value)
        assert(pns.Planner.allow[mark] == value, key .. " reaches the planner")
    else
        pns.Planner.allow[mark] = value
        pns.Planner.Request()
    end
end
for key in pairs(PREFERENCES) do
    passes = 0
    prefer(key, true)
    prefer(key, false)
    prefer(key, true)
    assert(passes == 0, "not at once: debounced")
    flush(P)
    assert(passes == 1, key .. ": one pass for a burst of changes, not " .. passes)
    assert(kept(), key .. " on: history, skips and counts are kept")
    -- Quest 169 is the one group quest this character could do.
    assert((find("accept", 169) ~= nil) == (key == "groups"), "the suggestions follow " .. key)
    prefer(key, false)
    flush(P)
    assert(passes == 2 and kept() and not find("accept", 169), key .. " off")
end
print("ALL OK")
