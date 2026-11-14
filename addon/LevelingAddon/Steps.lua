-- The route and each step's state. The route is still a fixed sample: the first stretch of
-- Northshire (human start), taken from data/parsed: quest ids 783, 7, 33, 15, 18, 21 and NPC
-- spawn averages. Later the list is computed from the quest data.
--
-- State is read from the game's quest log, never set by hand: a step is done when the game says
-- so. The one thing the player decides is which pending steps to skip.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

local ELWYNN = 1429
local ABBEY, MINE, VALLEY, VINEYARDS =
    "Northshire Abbey", "Echo Ridge Mine", "Northshire Valley", "Northshire Vineyards"

local function newStep(kind, name, need, questID, place, x, y)
    return { kind = kind, name = name, need = need, questID = questID, place = place, map = ELWYNN, x = x, y = y }
end

-- kind: "accept" (pick a quest up), "turnin" (hand it in), "kill", "loot".
-- need: how many, for kill and loot steps; each of these quests has a single objective.
-- x, y: map percent, as in the parsed data.
Steps.list = {
    newStep("accept", "Deputy Willem", nil, 783, ABBEY, 48.2, 42.9),
    newStep("turnin", "Marshal McBride", nil, 783, ABBEY, 48.9, 41.6),
    newStep("accept", "Marshal McBride", nil, 7, ABBEY, 48.9, 41.6),
    newStep("accept", "Eagan Peltskinner", nil, 33, ABBEY, 48.9, 40.2),
    newStep("loot", "Tough Wolf Meat", 8, 33, VALLEY, 46.2, 46.5),
    newStep("kill", "Kobold Vermin", 10, 7, MINE, 49.2, 36.3),
    newStep("turnin", "Marshal McBride", nil, 7, ABBEY, 48.9, 41.6),
    newStep("accept", "Marshal McBride", nil, 15, ABBEY, 48.9, 41.6),
    newStep("turnin", "Eagan Peltskinner", nil, 33, ABBEY, 48.9, 40.2),
    newStep("accept", "Deputy Willem", nil, 18, ABBEY, 48.2, 42.9),
    newStep("kill", "Kobold Worker", 10, 15, MINE, 48.9, 34.6),
    newStep("loot", "Red Burlap Bandana", 12, 18, VINEYARDS, 54.2, 47.3),
    newStep("turnin", "Deputy Willem", nil, 18, ABBEY, 48.2, 42.9),
    newStep("turnin", "Marshal McBride", nil, 15, ABBEY, 48.9, 41.6),
    newStep("accept", "Marshal McBride", nil, 21, ABBEY, 48.9, 41.6),
    newStep("kill", "Kobold Laborer", 12, 21, MINE, 48.9, 28.3),
    newStep("turnin", "Marshal McBride", nil, 21, ABBEY, 48.9, 41.6),
}

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
    -- Kill and loot steps: the quest's first objective. No objectives while the quest is not
    -- in the log.
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    local objective = objectives and objectives[1]
    if not objective then
        return false, 0
    end
    return objective.finished, objective.numFulfilled or 0
end

-- Read every step's state from the quest log. Returns true if anything changed.
function Steps:Sync()
    local changed = false
    for index, step in ipairs(self.list) do
        local done, count = readStep(step)
        local status = done and "done" or ns.db.skipped[index] and "skipped" or "pending"
        local state = self.state[index]
        if not state then
            state = {}
            self.state[index] = state
        end
        if state.status ~= status or state.count ~= count then
            state.status, state.count = status, count
            changed = true
        end
    end
    return changed
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
-- nil when the route is finished.
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

-- The player's own choices. Only a pending step can be skipped and only a skipped step can be
-- brought back; a finished step is never changed by hand.
function Steps:Skip(index)
    if self.list[index] and self:Status(index) == "pending" then
        ns.db.skipped[index] = true
        self:Sync()
    end
end

function Steps:Restore(index)
    if ns.db.skipped[index] then
        ns.db.skipped[index] = nil
        self:Sync()
    end
end
