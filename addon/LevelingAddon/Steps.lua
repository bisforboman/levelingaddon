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
-- State is read from the game's quest log, never set by hand: a step is done when the game says
-- so. The one thing the player decides is which quests to skip, and that is kept per character.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

local HISTORY = 20 -- finished and skipped steps kept above the plan

ns.charDefaults.skipped = {} -- [quest id] = true for quests the player chose to skip
ns.defaults.skipped = nil -- skips used to be kept per step index, for the whole account

Steps.list = {}
Steps.state = {} -- [index] = { status = "done" | "skipped" | "pending", count = number }
local turnedIn = {} -- quests handed in this session; the completed flag can lag the event

function Steps:NoteTurnedIn(questID)
    turnedIn[questID] = true
end

local function questCompleted(questID)
    return turnedIn[questID] or C_QuestLog.IsQuestFlaggedCompleted(questID)
end

-- What the game says about one step: is it done, and how far along is its count.
local function readStep(step)
    local questID = step.questID
    if questCompleted(questID) then
        return true, step.need or 0
    end
    if step.kind == "accept" then
        return C_QuestLog.IsOnQuest(questID), 0
    elseif step.kind == "turnin" then
        return false, 0
    end
    -- Kill, loot and go steps: one objective of the quest. No objectives while the quest is
    -- not in the log.
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    local objective = objectives and objectives[step.objective or 1]
    if not objective then
        return false, 0
    end
    return objective.finished, objective.numFulfilled or 0
end

-- Read every step's state from the quest log. Returns whether anything changed, and whether a
-- step's status did (and not just a count).
local function read(self)
    local changed, moved = false, false
    for index, step in ipairs(self.list) do
        local done, count = readStep(step)
        local status = done and "done" or ns.char.skipped[step.questID] and "skipped" or "pending"
        local state = self.state[index]
        if not state then
            state = {}
            self.state[index] = state
        end
        if state.status ~= status or state.count ~= count then
            moved = moved or state.status ~= status
            state.status, state.count = status, count
            changed = true
        end
    end
    return changed, moved
end

-- Called after quest events. A step that finished (or came back) means the plan is stale, so a
-- pass is asked for as well.
function Steps:Sync()
    local changed, moved = read(self)
    if moved then
        ns.Planner.Request()
    end
    return changed
end

-- The planner's new steps. What was finished stays as history, and so does the step a skip
-- was made on; everything else of the old list is replaced.
function Steps:SetPlan(rows)
    read(self)
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
    read(self)
end

function Steps:Count()
    return #self.list
end

-- "done", "skipped" or "pending".
function Steps:Status(index)
    local state = self.state[index]
    return state and state.status or "pending"
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
