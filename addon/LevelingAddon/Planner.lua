-- The planner: suggests the next steps from the character's state, whatever that state is.
--
-- Nothing is remembered between passes except what the game itself says: completed quests
-- (read once, then kept current from QUEST_TURNED_IN), the quest log and its objectives, level,
-- class, race, faction, zone and position. A fresh character, one that has played for weeks
-- and one that wandered off all go through the same pass.
--
-- A pass looks only at the current zone, the zones whose maps overlap it, and the level band
-- the character is in; the collector prepared those sets (ns.Data.plannerZones, plannerQuests;
-- see PlannerIndex.cs for the layout). It plays the next few actions forward on a copy of the
-- state, always taking the best-ranked action, and hands the result to ns.Steps.
--
-- Passes run on events, folded into one by Planner.Request; never per frame.
local _, ns = ...

local Planner = {}
ns.Planner = Planner

-- Quests carrying one of these marks are left out unless the mark is allowed here:
-- "dungeon", "raid", "group", "pvp". The preferences (#20) will set them.
Planner.allow = {}

local MAX_STEPS = 12 -- steps planned ahead
local STOP_YARDS = 40 -- actions this close to where the character stands are done before leaving
local NEAR_YARDS = 200 -- "close by", for counting the other candidates around an action
local BAND_WIDTH = 5 -- levels per band, as in the collector
local ELSEWHERE = 3 -- zones tried, one by one, when nothing here or next door suits the character
local LEVELS_BELOW = 7 -- a quest this many levels under the character is no longer offered
local NEARLY_FULL = 2 -- free places in the quest log at which hand-ins come before everything else
local SIDE_YARDS = 200 -- a kill or collect this close to the way to the current step is a side task

-- Ranking weights. First guesses, to be tuned in the game: one point is worth YARDS_PER_POINT
-- of travel.
local YARDS_PER_POINT = 150
local WEIGHT_XP = 1 -- the quest's XP, as a share of the best XP among the candidates
local WEIGHT_LEVEL = 1 -- how well the quest's level fits the character's
local WEIGHT_ZONE = 1 -- how well the zone's level range fits the character's
local WEIGHT_NEAR = 0.1 -- per other candidate close by, up to MAX_NEAR
local MAX_NEAR = 5
local BONUS = { turnin = 0.5, objective = 0.25, accept = 0 } -- finish what is started

-- The game's objective types, as the step kinds the window draws.
local KIND = { monster = "kill", item = "loot", object = "loot", event = "go" }

-- Completed quests -------------------------------------------------------------------------

local completed -- [quest id] = true or false; nil until read
local completedInBulk = false

-- Read once. Clients differ in how they list completed quests; where neither call exists,
-- quests are asked about one by one, the first time each matters.
local function readCompleted()
    local start = ns.Clock()
    completed = {}
    if C_QuestLog.GetAllCompletedQuestIDs then
        for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs()) do
            completed[id] = true
        end
        completedInBulk = true
    elseif GetQuestsCompleted then
        for id in pairs(GetQuestsCompleted()) do
            completed[id] = true
        end
        completedInBulk = true
    end
    ns.Report("completed quests read", ns.Clock() - start)
end

local function isCompleted(id)
    local known = completed[id]
    if known == nil and not completedInBulk then
        known = C_QuestLog.IsQuestFlaggedCompleted(id) or false
        completed[id] = known
    end
    return known
end

-- The character --------------------------------------------------------------------------

local levelSeen = 0 -- from PLAYER_LEVEL_UP, which can arrive before UnitLevel changes

local function readCharacter()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    return {
        level = math.max(UnitLevel("player") or 1, levelSeen),
        class = class,
        race = race and string.upper(race),
        side = faction and string.lower(faction),
    }
end

-- The quest ids in the log, whether the client could list them, and how many of them take a
-- place in the log (the modern log also lists quests that do not).
local function readLog()
    local log, count = {}, 0
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID then
                log[info.questID] = true
                if not (info.isHidden or info.isTask or info.isBounty) then
                    count = count + 1
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not isHeader and questID then
                log[questID] = true
                count = count + 1
            end
        end
    else
        return log, false, count
    end
    return log, true, count
end

-- How many quests the log holds, asked of the client; nil where it cannot say, and then the
-- planner does not hold pick-ups back.
local function logLimit()
    local limit = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or MAX_QUESTS
    return type(limit) == "number" and limit > 0 and limit or nil
end

-- Profession skill by skill line id; nil where the client cannot say.
local function skillRank(skillID)
    if not (GetProfessions and GetProfessionInfo) then
        return nil
    end
    for slot = 1, 5 do
        local index = select(slot, GetProfessions())
        if index then
            local _, _, rank, _, _, _, line = GetProfessionInfo(index)
            if line == skillID then
                return rank
            end
        end
    end
    return 0
end

-- Reputation with a faction; a faction the character has not met, or a client that cannot
-- say, counts as neutral.
local function standing(factionID)
    local value
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        value = data and data.currentStanding
    elseif GetFactionInfoByID then
        value = select(6, GetFactionInfoByID(factionID))
    end
    return value or 0
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

-- What cannot change during a pass: is this quest for this character at all?
local function suits(id, quest, me)
    local level = quest.level
    return not ns.char.skipped[id]
        and (not quest.mark or Planner.allow[quest.mark])
        and (not quest.side or quest.side == me.side)
        and (not quest.races or contains(quest.races, me.race))
        and (not quest.classes or contains(quest.classes, me.class))
        and (quest.req or 1) <= me.level
        and (not quest.maxLevel or me.level <= quest.maxLevel)
        and (not level or level <= 0 or level + LEVELS_BELOW >= me.level)
        and (not quest.skill or (skillRank(quest.skill[1]) or -1) >= quest.skill[2])
        and (not quest.minRep or standing(quest.minRep[1]) >= quest.minRep[2])
        and (not quest.maxRep or standing(quest.maxRep[1]) < quest.maxRep[2])
end

-- Maps --------------------------------------------------------------------------------------

-- Each zone map as a frame in world yards: an origin and the vectors along its two edges,
-- measured once per map. Distances across neighbouring zones and the zones' neighbours both
-- come from these; false where the client has no world position for the map.
local frames = {}

local function frameOf(map)
    local frame = frames[map]
    if frame == nil then
        frame = false
        local ok, continent, origin = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
        local _, _, east = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 0))
        local _, _, south = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 1))
        if ok and origin and east and south then
            local ex, ey, sx, sy = east.x - origin.x, east.y - origin.y, south.x - origin.x, south.y - origin.y
            frame = { continent = continent, ox = origin.x, oy = origin.y, ex = ex, ey = ey, sx = sx, sy = sy }
            -- The map's bounding box in the world, for the neighbour test.
            local x2, x3, x4 = origin.x + ex, origin.x + sx, origin.x + ex + sx
            local y2, y3, y4 = origin.y + ey, origin.y + sy, origin.y + ey + sy
            frame.minX, frame.maxX = math.min(origin.x, x2, x3, x4), math.max(origin.x, x2, x3, x4)
            frame.minY, frame.maxY = math.min(origin.y, y2, y3, y4), math.max(origin.y, y2, y3, y4)
        end
        frames[map] = frame
    end
    return frame
end

-- World position of a point given in percent of a zone map.
local function worldPosition(map, x, y)
    local frame = frameOf(map)
    if not frame then
        return nil
    end
    x, y = x / 100, y / 100
    return frame.ox + x * frame.ex + y * frame.sx, frame.oy + x * frame.ey + y * frame.sy
end

-- The zone the character is in: the nearest map at or above the game's "best map" that the
-- data knows, with the position on it in percent.
local function currentZone()
    local zones = ns.Data.plannerZones
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 5 do
        if not map or zones[map] then
            break
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    local position = map and zones[map] and C_Map.GetPlayerMapPosition(map, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    return map, x * 100, y * 100
end

-- A zone's neighbours are the zones on the same continent whose maps overlap its map. The data
-- has no adjacency, and a zone map is drawn with a margin that reaches into the zones around
-- it, so this needs nothing authored. Worked out once per zone.
local neighbours = {}

local function workingSet(map)
    local set = neighbours[map]
    if not set then
        set = { [map] = true }
        local here = frameOf(map)
        for other in pairs(here and ns.Data.plannerZones or {}) do
            local there = frameOf(other)
            if
                there
                and there.continent == here.continent
                and there.minX < here.maxX
                and here.minX < there.maxX
                and there.minY < here.maxY
                and here.minY < there.maxY
            then
                set[other] = true
            end
        end
        neighbours[map] = set
    end
    return set
end

-- How well a level sits in a range: 1 inside it, falling to 0 over `fade` levels outside.
local function fit(level, low, high, fade)
    local gap = math.max(low - level, level - high, 0)
    return math.max(0, 1 - gap / fade)
end

-- Where nothing here suits the character: the other zones on this continent, those whose level
-- range fits best first, and the nearest of those first.
local function otherZones(map, me, px, py)
    local here = frameOf(map)
    local list = {}
    for other, zone in pairs(here and ns.Data.plannerZones or {}) do
        local there = frameOf(other)
        if other ~= map and zone.min and there and there.continent == here.continent then
            local dx, dy = (there.minX + there.maxX) / 2 - px, (there.minY + there.maxY) / 2 - py
            list[#list + 1] =
                { map = other, fit = fit(me.level, zone.min, zone.max, BAND_WIDTH), yards = dx * dx + dy * dy }
        end
    end
    table.sort(list, function(a, b)
        if a.fit ~= b.fit then
            return a.fit > b.fit
        elseif a.yards ~= b.yards then
            return a.yards < b.yards
        end
        return a.map < b.map
    end)
    return list
end

-- One pass ---------------------------------------------------------------------------------

-- The n-th objective of a type in the data, which is how the quest log's objectives are
-- matched: the game does not say which NPC or item an objective is about.
local function objectiveOfType(quest, kind, n)
    for _, objective in ipairs(quest.obj or {}) do
        if objective[1] == kind then
            n = n - 1
            if n == 0 then
                return objective
            end
        end
    end
end

local UNREAD_TRIES = 5
local unread = {} -- [quest id] = passes that found fewer objectives in the log than the data has

-- Plan from the given state, looking only at the zones in `working`. `free` is the number of
-- free places in the quest log: the plan never holds more pick-ups than that. Returns the rows
-- and, where the log is full and the best next thing would otherwise be a pick-up, that quest.
local function plan(working, me, log, logListed, px, py, free)
    local quests, zones = ns.Data.plannerQuests, ns.Data.plannerZones
    local band = math.floor((me.level - 1) / BAND_WIDTH) + 1

    -- Quests that could be picked up: in a working zone, in the band, and right for the
    -- character.
    local pool, pooled, bestXP = {}, {}, 1
    for map in pairs(working) do
        for _, id in ipairs(zones[map] and zones[map].bands[band] or {}) do
            if not pooled[id] then
                pooled[id] = true
                if suits(id, quests[id], me) then
                    pool[#pool + 1] = id
                    bestXP = math.max(bestXP, quests[id].xp or 0)
                end
            end
        end
    end
    table.sort(pool) -- the order must not depend on the order of `pairs`

    -- The state the plan is played forward on.
    local done, inLog = {}, {}
    local open = {} -- [quest id] = objectives still to do: { target, index in the log, need }
    local stuck = {} -- [quest id] = true: an open objective the data cannot place
    local logged = {}
    for id in pairs(log) do
        local quest = quests[id]
        inLog[id] = true
        if quest and not ns.char.skipped[id] then
            logged[#logged + 1] = id
            open[id] = {}
            local listed = C_QuestLog.GetQuestObjectives(id) or {}
            -- Just after a quest is accepted the log may not hold its objectives yet. Such a
            -- quest is left alone, and the next quest log update asks for another pass (a few
            -- times at most, in case the data counts objectives the game does not have).
            local expected = 0
            for _, objective in ipairs(quest.obj or {}) do
                expected = expected + (objective[1] ~= "event" and 1 or 0)
            end
            if #listed < expected then
                stuck[id] = true
                unread[id] = (unread[id] or 0) + 1
                Planner.waiting = Planner.waiting or unread[id] <= UNREAD_TRIES
            end
            local seen = {}
            for index, objective in ipairs(listed) do
                local kind = objective.type
                local target
                if kind then
                    seen[kind] = (seen[kind] or 0) + 1
                    target = objectiveOfType(quest, kind, seen[kind])
                else
                    target = quest.obj and quest.obj[index]
                end
                if not objective.finished then
                    if target and target[3] then
                        table.insert(open[id], { target = target, index = index, need = objective.numRequired })
                    else
                        stuck[id] = true
                    end
                end
            end
        end
    end
    table.sort(logged)

    local function isDone(id)
        return done[id] or isCompleted(id)
    end
    local function isOn(id)
        return inLog[id] or (not logListed and C_QuestLog.IsOnQuest(id))
    end
    local function available(id, quest)
        if isDone(id) or isOn(id) then
            return false
        end
        if quest.pre then
            local any = false
            for _, other in ipairs(quest.pre) do
                any = any or isDone(other)
            end
            if not any then
                return false
            end
        end
        for _, other in ipairs(quest.preAll or {}) do
            if not isDone(other) then
                return false
            end
        end
        for _, other in ipairs(quest.excl or {}) do
            if isDone(other) or isOn(other) then
                return false
            end
        end
        return not quest.parent or isOn(quest.parent)
    end

    -- A target's points in the working zones, in world yards. `first` is where its points
    -- start: 2 in a start or finish {name, map, x, y, ...}, 3 in an objective.
    local placed = {}
    local function pointsOf(target, first)
        local points = placed[target]
        if not points then
            points = {}
            for i = first, #target, 3 do
                local map = target[i]
                local wx, wy
                if working[map] then
                    wx, wy = worldPosition(map, target[i + 1], target[i + 2])
                end
                if wx then
                    points[#points + 1] = { map = map, x = target[i + 1], y = target[i + 2], wx = wx, wy = wy }
                end
            end
            placed[target] = points
        end
        return points
    end

    -- Every action open in the current state is offered to `consider`; pick-ups only while
    -- `slots` is above zero.
    local function eachAction(consider, slots)
        for _, id in ipairs(logged) do
            if inLog[id] then
                local quest = quests[id]
                if open[id][1] then
                    for _, objective in ipairs(open[id]) do
                        consider("objective", id, quest, objective.target, 3, objective)
                    end
                elseif not stuck[id] then
                    for _, target in ipairs(quest.finish or {}) do
                        consider("turnin", id, quest, target, 2)
                    end
                end
            end
        end
        for _, id in ipairs(slots > 0 and pool or {}) do
            local quest = quests[id]
            if available(id, quest) then
                for _, target in ipairs(quest.start) do
                    consider("accept", id, quest, target, 2)
                end
            end
        end
    end

    -- How many candidates sit in each NEAR_YARDS cell, counted once on the opening state.
    local crowd = {}
    local function cell(point)
        return math.floor(point.wx / NEAR_YARDS) * 100003 + math.floor(point.wy / NEAR_YARDS)
    end
    eachAction(function(_, _, _, target, first)
        for _, point in ipairs(pointsOf(target, first)) do
            crowd[cell(point)] = (crowd[cell(point)] or 0) + 1
        end
    end, free)

    -- The best action overall, and the best within STOP_YARDS: whatever can be done on the spot
    -- is done before moving on, which groups the actions that share a place. With `turninsOnly`
    -- only hand-ins are looked at, and the nearest is the best.
    local function pick(slots, turninsOnly)
        local best, here
        eachAction(function(action, id, quest, target, first, objective)
            for _, point in ipairs(turninsOnly and action ~= "turnin" and {} or pointsOf(target, first)) do
                local dx, dy = point.wx - px, point.wy - py
                local yards = math.sqrt(dx * dx + dy * dy)
                local level = quest.level and quest.level > 0 and quest.level or me.level
                local zone = zones[point.map]
                local score = turninsOnly and -yards
                    or BONUS[action]
                        + WEIGHT_XP * (quest.xp or 0) / bestXP
                        + WEIGHT_LEVEL * fit(me.level, level - 2, level + 3, LEVELS_BELOW - 3)
                        + WEIGHT_ZONE * (zone and zone.min and fit(me.level, zone.min, zone.max, BAND_WIDTH) or 0.5)
                        + WEIGHT_NEAR * math.min((crowd[cell(point)] or 1) - 1, MAX_NEAR)
                        - yards / YARDS_PER_POINT
                local near = yards <= STOP_YARDS
                local current = near and here or not near and best
                if not current or score > current.score or (score == current.score and id < current.id) then
                    current = current or {}
                    current.score, current.action, current.id, current.quest = score, action, id, quest
                    current.target, current.first, current.point, current.objective = target, first, point, objective
                    if near then
                        here = current
                    else
                        best = current
                    end
                end
            end
        end, slots)
        return here or best
    end

    -- Side tasks (#8): a kill or collect objective the character already has in the log, with
    -- a point within SIDE_YARDS of the straight line from where the character stands (ax, ay)
    -- to the current step (px, py). The one nearest that line, shaped like a pick.
    local function sideTask(ax, ay)
        local dx, dy = px - ax, py - ay
        local length = dx * dx + dy * dy
        local side = { score = -SIDE_YARDS, action = "objective", first = 3 }
        for _, id in ipairs(logged) do
            for _, objective in ipairs(inLog[id] and open[id] or {}) do
                local target = objective.target
                -- An index means the game's log has the objective; a planned pick-up has none.
                for _, point in ipairs(objective.index and target[1] ~= "event" and pointsOf(target, 3) or {}) do
                    local along = length > 0 and ((point.wx - ax) * dx + (point.wy - ay) * dy) / length or 0
                    along = math.max(0, math.min(1, along))
                    local ox, oy = point.wx - ax - along * dx, point.wy - ay - along * dy
                    local score = -math.sqrt(ox * ox + oy * oy)
                    if score > side.score or (score == side.score and not side.id) then
                        side.score, side.id, side.quest = score, id, quests[id]
                        side.target, side.point, side.objective = target, point, objective
                    end
                end
            end
        end
        return side.id and side
    end

    local rows, blocked = {}, nil
    local ax, ay = px, py -- where the character stands
    -- A full log: what would come first if it were not?
    local wish = free == 0 and pick(1)
    if wish and wish.action == "accept" then
        blocked = wish.id
    end
    for _ = 1, MAX_STEPS do
        -- With the log full or nearly full, hand-ins come first, nearest first.
        -- Side tasks come right under the current step, which is the first row.
        local side = rows[1] and sideTask(ax, ay)
        local chosen = side or free <= NEARLY_FULL and pick(0, true) or pick(free)
        if not chosen then
            break
        end

        local id, point, objective = chosen.id, chosen.point, chosen.objective
        local row = { questID = id, name = chosen.target[chosen.first - 1], map = point.map, x = point.x, y = point.y }
        if chosen.action == "accept" then
            row.kind = "accept"
            free = free - 1
            inLog[id] = true
            logged[#logged + 1] = id
            open[id] = {}
            for _, target in ipairs(chosen.quest.obj or {}) do
                if target[3] then
                    table.insert(open[id], { target = target })
                end
            end
        elseif chosen.action == "turnin" then
            row.kind = "turnin"
            inLog[id] = nil
            done[id] = true
        else
            row.kind = KIND[objective.target[1]] or "go"
            row.objective, row.need = objective.index, objective.need
            for i, other in ipairs(open[id]) do
                if other == objective then
                    table.remove(open[id], i)
                    break
                end
            end
        end
        rows[#rows + 1] = row
        -- A side task is done along the way: the plan goes on from the current step.
        if not side then
            px, py = point.wx, point.wy
        end
    end
    return rows, blocked
end

local warned = false
local last -- what the last pass looked at, for /lvl plan
local noticed -- the hand-in named (or 0 for none) in the full-log line already said, nil when not full

-- One pass, now. Feature code asks for one with Planner.Request instead.
function Planner:Run()
    local rows, blocked
    self.waiting = false
    if not (ns.Data and ns.Data.plannerQuests and ns.Data.plannerZones) then
        if not warned then
            warned = true
            ns.say("has no quest data, so it cannot suggest steps. The README says how to build it.")
        end
    else
        if not completed then
            readCompleted()
        end
        local start = ns.Clock()
        -- No zone or no position (an instance, a loading screen): the steps stay as they are.
        local map, x, y = currentZone()
        local px, py
        if map then
            px, py = worldPosition(map, x, y)
        end
        if px then
            local me = readCharacter()
            local log, logListed, count = readLog()
            local limit = logListed and logLimit()
            local free = limit and math.max(limit - count, 0) or math.huge
            last = { map = map, me = me, logListed = logListed, count = count, limit = limit }
            rows, blocked = plan(workingSet(map), me, log, logListed, px, py, free)
            -- Nothing to do here or next door: look into the best few zones elsewhere, one at
            -- a time.
            local elsewhere = not rows[1] and otherZones(map, me, px, py)
            for i = 1, elsewhere and math.min(#elsewhere, ELSEWHERE) or 0 do
                rows = plan({ [elsewhere[i].map] = true }, me, log, logListed, px, py, free)
                if rows[1] then
                    break
                end
            end
        end
        ns.Report("planner pass", ns.Clock() - start)
    end
    -- The log is full and a pick-up would have come first: said once, and again only when the
    -- hand-in to name changes.
    if blocked then
        local quests, first = ns.Data.plannerQuests, rows[1]
        local turnin = first and first.kind == "turnin" and first.questID or 0
        if noticed ~= turnin then
            noticed = turnin
            ns.say(
                "the quest log is full, so "
                    .. quests[blocked].name
                    .. " cannot be picked up"
                    .. (turnin ~= 0 and ": hand in " .. quests[turnin].name .. " at " .. first.name .. " first." or ".")
            )
        end
    elseif rows then
        noticed = nil
    end
    if rows then
        ns.Steps:SetPlan(rows)
    else
        ns.Steps:Sync()
    end
    ns.Refresh()
end

-- What the last pass saw, to check the planner against the game: the character as it was
-- read, the zone, and the zones taken as its neighbours.
function ns.commands.plan()
    if not last then
        ns.say("no pass has run with a known zone and position yet.")
        return
    end
    local zones, me = ns.Data.plannerZones, last.me
    local names = {}
    for map in pairs(workingSet(last.map)) do
        if map ~= last.map then
            names[#names + 1] = zones[map].name or tostring(map)
        end
    end
    table.sort(names)
    ns.say(string.format("level %d %s %s, %s.", me.level, tostring(me.race), tostring(me.class), tostring(me.side)))
    ns.say((zones[last.map].name or last.map) .. " (map " .. last.map .. "), next to: " .. table.concat(names, ", "))
    local text = "completed quests %s, quest log %s, %d steps."
    ns.say(
        string.format(
            text,
            completedInBulk and "read in one call" or "asked one by one",
            last.logListed and "listed" or "not listable",
            ns.Steps:Count()
        )
    )
    ns.say(
        string.format("%d quests in the log, which holds %s.", last.count, tostring(last.limit or "an unknown number"))
    )
end

-- The one way to ask for a pass: after an event, a changed preference, a skip. A burst of
-- requests becomes one pass.
Planner.Request = ns.Debounce(0.2, function()
    Planner:Run()
end)

ns.On("QUEST_TURNED_IN", function(_, questID)
    if completed and questID then
        completed[questID] = true
    end
    Planner.Request()
end)
ns.On("PLAYER_LEVEL_UP", function(_, level)
    levelSeen = tonumber(level) or levelSeen
    Planner.Request()
end)
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, Planner.Request)
end
