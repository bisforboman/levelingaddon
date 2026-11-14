-- The route and each step's state. For now the route is a fixed sample: the first stretch of
-- Northshire, taken from data/parsed (quest ids 783, 7, 33, 15, 18, 21; NPC spawn averages).
-- Later this list is computed from the quest data and the state is read from the quest log.
local _, ns = ...

local Steps = {}
ns.Steps = Steps

local ELWYNN = 1429
local ABBEY, MINE, VALLEY, VINEYARDS =
    "Northshire Abbey", "Echo Ridge Mine", "Northshire Valley", "Northshire Vineyards"

local function step(kind, name, need, quest, place, x, y)
    return { kind = kind, name = name, need = need, quest = quest, place = place, map = ELWYNN, x = x, y = y }
end

-- kind: "accept" (pick a quest up), "turnin" (hand it in), "kill", "loot".
-- need: how many, for kill and loot steps. x, y: map percent, as in the parsed data.
Steps.list = {
    step("accept", "Deputy Willem", nil, "A Threat Within", ABBEY, 48.2, 42.9),
    step("turnin", "Marshal McBride", nil, "A Threat Within", ABBEY, 48.9, 41.6),
    step("accept", "Marshal McBride", nil, "Kobold Camp Cleanup", ABBEY, 48.9, 41.6),
    step("accept", "Eagan Peltskinner", nil, "Wolves Across the Border", ABBEY, 48.9, 40.2),
    step("loot", "Tough Wolf Meat", 8, "Wolves Across the Border", VALLEY, 46.2, 46.5),
    step("kill", "Kobold Vermin", 10, "Kobold Camp Cleanup", MINE, 49.2, 36.3),
    step("turnin", "Marshal McBride", nil, "Kobold Camp Cleanup", ABBEY, 48.9, 41.6),
    step("accept", "Marshal McBride", nil, "Investigate Echo Ridge", ABBEY, 48.9, 41.6),
    step("turnin", "Eagan Peltskinner", nil, "Wolves Across the Border", ABBEY, 48.9, 40.2),
    step("accept", "Deputy Willem", nil, "Brotherhood of Thieves", ABBEY, 48.2, 42.9),
    step("kill", "Kobold Worker", 10, "Investigate Echo Ridge", MINE, 48.9, 34.6),
    step("loot", "Red Burlap Bandana", 12, "Brotherhood of Thieves", VINEYARDS, 54.2, 47.3),
    step("turnin", "Deputy Willem", nil, "Brotherhood of Thieves", ABBEY, 48.2, 42.9),
    step("turnin", "Marshal McBride", nil, "Investigate Echo Ridge", ABBEY, 48.9, 41.6),
    step("accept", "Marshal McBride", nil, "Skirmish at Echo Ridge", ABBEY, 48.9, 41.6),
    step("kill", "Kobold Laborer", 12, "Skirmish at Echo Ridge", MINE, 48.9, 28.3),
    step("turnin", "Marshal McBride", nil, "Skirmish at Echo Ridge", ABBEY, 48.9, 41.6),
}

function Steps:Count()
    return #self.list
end

-- "done", "skipped" or "pending".
function Steps:Status(index)
    return ns.db.status[index] or "pending"
end

function Steps:Progress(index)
    return ns.db.progress[index] or 0
end

-- The current step is the first one that is neither done nor skipped. Returns its index, or
-- nil when the route is finished.
function Steps:CurrentIndex()
    for index = 1, #self.list do
        if not ns.db.status[index] then
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
    if self.list[index] and not ns.db.status[index] then
        ns.db.status[index] = "skipped"
    end
end

function Steps:Restore(index)
    if ns.db.status[index] == "skipped" then
        ns.db.status[index] = nil
    end
end

-- Stand-in for the game reporting progress on the current step (see /lvl next).
function Steps:Advance()
    local current, index = self:Current()
    if not current then
        return
    end
    if current.need then
        local count = self:Progress(index) + 1
        ns.db.progress[index] = count
        if count < current.need then
            return
        end
    end
    ns.db.status[index] = "done"
end
