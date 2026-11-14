-- The steps the window and the arrow show, and each step's state.
--
-- The list is the planner's: ns.Planner computes the next steps from the character's state and
-- hands them over with Steps:SetPlan. Steps that were finished or skipped while they were on
-- the list stay above the plan as history, so the window can scroll back to them.
--
-- A step is { kind, name, need, questID, objective, map, x, y }:
--   kind       "accept" (pick a quest up), "turnin" (hand it in), "kill", "loot", or "go"
--              (be somewhere: an escort, an exploration)
--   name       the NPC, creature, item or place to find
--   need       how many, for a kill or loot step whose quest is in the log
--   objective  which of the quest's objectives in the log a kill, loot or go step is about;
--              nil while the quest is not in the log yet
--   map, x, y  the zone map (uiMapId) and the position on it in percent
--
-- State is read from the game, never set by hand: a step is done when the game says so. The one
-- thing the player decides is which quests to skip, and that is kept per character.
--
-- Only the steps in view are followed: of the events handled here, only those of their kinds
-- lead to a check, and a check reads those steps alone. A step that comes into view is read at
-- once, so what the player already did is done the moment it is shown.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

local HISTORY = 20 -- finished and skipped steps kept above the plan
local BEFORE = 2 -- rows the window keeps above the current step
local GRACE = 3 -- seconds an accept or a turn-in is taken on the event's word; the log lags
local POLL = 0.5 -- seconds between looks at the character's position, for the kinds that ask
Steps.ARRIVE_YARDS = 8 -- a point counts as reached inside this radius; the arrow's as well

ns.charDefaults.skipped = {} -- [quest id] = true for quests the player chose to skip

Steps.list = {}
Steps.state = {} -- [index] = { done = boolean, count = number }, for the steps read so far

-- What an event said that the quest log may not show yet, each with the time it stands until:
-- a quest accepted or handed in, for GRACE seconds; a point reached, for as long as its quest
-- stays in the log.
local noted = { accept = {}, turnin = {}, go = {} }

local function note(kind, key, seconds)
    noted[kind][key] = GetTime() + (seconds or GRACE)
end

local function isNoted(kind, key)
    return (noted[kind][key] or 0) > GetTime()
end

local function handedIn(questID)
    return isNoted("turnin", questID) or C_QuestLog.IsQuestFlaggedCompleted(questID)
end

-- One objective of the step's quest: finished, and its count. A step without an objective
-- index (its quest was not in the log when it was planned) follows the quest's only objective,
-- and nothing if the quest has several. No objectives while the quest is not in the log.
local function objective(step)
    local list = C_QuestLog.GetQuestObjectives(step.questID)
    local one = list and list[step.objective or (#list == 1 and 1)]
    if not one then
        return false, 0
    end
    return one.finished, one.numFulfilled or 0
end

local function goKey(step)
    return step.questID * 100 + (step.objective or 0)
end

-- Whether the character has stood at the point of this objective of a quest in the log. The
-- planner asks, so that it does not suggest the point again.
function Steps:Reached(questID, index)
    return isNoted("go", questID * 100 + index)
end

-- Whether the character stands within ARRIVE_YARDS of the step's point. World x runs north
-- and world y runs west; the point's world position is kept on the step.
local function near(step)
    if step.world == nil then
        local continent, world
        if step.map and step.x and step.y then
            continent, world = C_Map.GetWorldPosFromMapPos(step.map, CreateVector2D(step.x / 100, step.y / 100))
        end
        step.continent, step.world = continent, world or false
    end
    local px, py, _, instance = UnitPosition("player")
    if not (step.world and px) or instance ~= step.continent then
        return false
    end
    local dx, dy = step.world.x - px, step.world.y - py
    return dx * dx + dy * dy <= Steps.ARRIVE_YARDS ^ 2
end

local function readObjective(step)
    if handedIn(step.questID) then
        return true, step.need or 0
    end
    return objective(step)
end

-- The kinds of step. Adding a kind is one entry here:
--   events  the game events that can finish a step of this kind, or undo it
--   read    function(step): whether the game says the step is done, and its count if it has one
--   poll    optional function(step), cheap: asked every POLL seconds while a step of this kind
--           is in view and not done; when it holds, the step is read
local KINDS = {
    accept = {
        events = { "QUEST_ACCEPTED", "QUEST_REMOVED" },
        read = function(step)
            local questID = step.questID
            return isNoted("accept", questID) or C_QuestLog.IsOnQuest(questID) or handedIn(questID)
        end,
    },
    turnin = {
        events = { "QUEST_TURNED_IN" },
        read = function(step)
            return handedIn(step.questID)
        end,
    },
    kill = { events = { "QUEST_LOG_UPDATE" }, read = readObjective },
    loot = { events = { "QUEST_LOG_UPDATE" }, read = readObjective },
    -- Be somewhere: done when the quest's objective says so, or once the character has stood
    -- at the point with the quest in the log.
    go = {
        events = { "QUEST_LOG_UPDATE" },
        poll = near,
        read = function(step)
            local questID, key = step.questID, goKey(step)
            if handedIn(questID) then
                return true, step.need or 0
            elseif not C_QuestLog.IsOnQuest(questID) then
                noted.go[key] = nil
                return false, 0
            end
            local done, count = objective(step)
            if not done and (isNoted("go", key) or near(step)) then
                note("go", key, math.huge)
                done = true
            end
            return done, count
        end,
    },
}

-- Read the steps from `first` to `last` from the game; with `polled`, only those whose kind's
-- poll holds. Returns whether anything changed, and whether a step finished or came back (and
-- not just a count).
local function read(self, polled, first, last)
    local changed, moved = false, false
    for index = first, last do
        local step = self.list[index]
        local kind = KINDS[step.kind]
        local state = self.state[index]
        if not state then
            state = { done = false, count = 0 }
            self.state[index] = state
        end
        if not polled or (kind.poll and not state.done and kind.poll(step)) then
            local done, count = kind.read(step)
            done, count = done and true or false, count or 0
            if state.done ~= done or state.count ~= count then
                moved = moved or state.done ~= done
                state.done, state.count = done, count
                changed = true
            end
        end
    end
    return changed, moved
end

-- The steps in view: the rows the window shows at rest, around the current step.
local rowsSeen -- the number of rows the view was last worked out for
local function inView(self)
    rowsSeen = ns.db.rows
    local top = (self:CurrentIndex() or #self.list + 1) - BEFORE
    return math.max(1, top), math.min(#self.list, top + rowsSeen - 1)
end

local watched = {} -- [event] = true for the events of the steps in view
local hooked = {} -- [event] = true once our handler is on it

local checkSoon = ns.Debounce(0.2, function()
    if Steps:Sync() then
        ns.Refresh()
    end
end)

-- QUEST_ACCEPTED carries the quest id alone in the modern client, and the quest log index
-- before it in the classic one.
local function onEvent(event, a, b)
    if not watched[event] then
        return
    end
    if event == "QUEST_ACCEPTED" then
        note("accept", b or a)
    elseif event == "QUEST_TURNED_IN" then
        note("turnin", a)
    end
    checkSoon()
end

-- Follow the events of the steps in view and no others, and look at the position only while
-- a step in view asks for it. An event is registered with the game the first time a step
-- needs it.
local function watch(self)
    local function want(event)
        watched[event] = true
        if not hooked[event] then
            hooked[event] = true
            ns.On(event, onEvent)
        end
    end
    wipe(watched)
    local polling = false
    local first, last = inView(self)
    for index = first, last do
        local kind = KINDS[self.list[index].kind]
        for _, event in ipairs(kind.events) do
            want(event)
        end
        polling = polling or (kind.poll ~= nil and not self.state[index].done)
    end
    -- A planner waiting for the quest log to fill in is asked again on its next update.
    if ns.Planner.waiting then
        want("QUEST_LOG_UPDATE")
    end
    ns.SetTask("steps", polling)
end

-- Check the steps in view; a finished step brings others into view, and those are read as
-- well. A step that finished (or came back) means the
-- plan is stale, so a pass is asked for; and so does a planner that is waiting for the log.
-- Returns whether anything changed. With `polled`, the check starts from the steps whose
-- kind's poll holds.
function Steps:Sync(polled)
    local changed, moved = false, false
    repeat
        local stepChanged, stepMoved = read(self, polled, inView(self))
        if polled and not stepChanged then
            return false -- the usual answer of the position check: nobody arrived
        end
        polled = false
        changed, moved = changed or stepChanged, moved or stepMoved
    until not stepMoved
    watch(self)
    if moved or ns.Planner.waiting then
        ns.Planner.Request()
    end
    return changed
end

-- A changed number of rows brings other steps into view.
local refresh = ns.Refresh
function ns.Refresh()
    if rowsSeen ~= ns.db.rows then
        Steps:Sync()
    end
    refresh()
end

ns.Task("steps", POLL, function()
    if Steps:Sync(true) then
        ns.Refresh()
    end
end)

-- The planner's new steps. What was finished stays as history, and so does the step a skip
-- was made on; everything else of the old list is replaced.
function Steps:SetPlan(rows)
    read(self, false, 1, #self.list)
    local list = {}
    for index, step in ipairs(self.list) do
        local status = self:Status(index)
        if status == "done" or (status == "skipped" and step.kept) then
            list[#list + 1] = step
        end
    end
    while #list > HISTORY do
        table.remove(list, 1)
    end
    for _, step in ipairs(rows) do
        list[#list + 1] = step
    end
    self.list = list
    wipe(self.state)
    read(self, false, 1, #list)
    watch(self)
end

function Steps:Count()
    return #self.list
end

-- "done", "skipped" or "pending". The game's word wins: a skipped step that is done is done.
function Steps:Status(index)
    local state, step = self.state[index], self.list[index]
    if state and state.done then
        return "done"
    end
    return step and ns.char.skipped[step.questID] and "skipped" or "pending"
end

function Steps:Progress(index)
    local state = self.state[index]
    return state and state.count or 0
end

-- The current step is the first one that is neither done nor skipped. Returns its index, or
-- nil when there is nothing left to suggest.
function Steps:CurrentIndex()
    for index = 1, #self.list do
        if self:Status(index) == "pending" then
            return index
        end
    end
    return nil
end

function Steps:Current()
    local index = self:CurrentIndex()
    return index and self.list[index], index
end

-- The player's own choices. Skipping a step skips its quest: nothing of that quest is
-- suggested again until the player restores it. Only a pending step can be skipped; a finished
-- step is never changed by hand.
function Steps:Skip(index)
    local step = self.list[index]
    if step and self:Status(index) == "pending" then
        ns.char.skipped[step.questID] = true
        step.kept = true -- this step stays in view, crossed out, to restore from
        ns.Planner:Run()
    end
end

function Steps:Restore(index)
    local step = self.list[index]
    if step then
        self:RestoreQuest(step.questID)
    end
end

function Steps:RestoreQuest(questID)
    if ns.char.skipped[questID] then
        ns.char.skipped[questID] = nil
        ns.Planner:Run()
    end
end

-- The skipped quests, to restore from.
function ns.commands.skipped()
    local ids = {}
    for questID in pairs(ns.char.skipped) do
        ids[#ids + 1] = questID
    end
    table.sort(ids)
    if not ids[1] then
        ns.say("no skipped quests.")
        return
    end
    local quests = ns.Data and ns.Data.plannerQuests or {}
    for _, questID in ipairs(ids) do
        ns.say(questID .. " " .. (quests[questID] and quests[questID].name or "?"))
    end
    ns.say("/lvl unskip NUMBER brings one back, /lvl unskip all brings back every one.")
end

function ns.commands.unskip(arg)
    local questID = tonumber(arg)
    if arg == "all" then
        wipe(ns.char.skipped)
        ns.Planner:Run()
    elseif questID and ns.char.skipped[questID] then
        Steps:RestoreQuest(questID)
    else
        ns.commands.skipped()
    end
end
