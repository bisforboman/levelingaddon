-- One arrow pointing at the current step, with the distance in yards: at the nearest of the
-- places the step can be done at, and at the corpse while the player is a ghost. On arrival it
-- becomes a ring. If TomTom is installed it gets the waypoint instead and we draw nothing, so
-- there are never two arrows.
local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local ARRIVE_YARDS = ns.Steps.ARRIVE_YARDS -- one place: an NPC, an object, the corpse
local AREA_YARDS = 30 -- one of the places of a kill or collect step
local MIN_TURN = 0.02 -- radians (about one degree); smaller changes do not redraw the arrow
local RESELECT = 5 -- updates between two looks for the nearest place
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow" -- points up when not rotated
-- Ours: a ring around a dot, white, drawn as in docs/mockups/ui-directions.html ("Arrived").
local RING_TEXTURE = "Interface\\AddOns\\LevelingAddon\\ring.tga"

-- World position and continent of a map point (x and y from 0 to 1), or nil where the game
-- has none (for example in instances).
local function worldPosition(mapID, x, y)
    local continent, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    return position, continent
end

-- A target the update loop can use without asking the map again: the places of `flat`
-- ({x1, y1, x2, y2, ...} on the map, 0 to 1) as a list of world points, the continent, and the
-- map's east and south as unit vectors in world space, so nothing depends on which way the
-- world axes run. `area` is true for kill and collect steps, whose places are visited in turn.
local function newTarget(mapID, flat, area)
    local centre, continent = worldPosition(mapID, 0.5, 0.5)
    local east, south = worldPosition(mapID, 0.51, 0.5), worldPosition(mapID, 0.5, 0.51)
    if not (centre and east and south) then
        return nil
    end
    local ex, ey = east.x - centre.x, east.y - centre.y
    local sx, sy = south.x - centre.x, south.y - centre.y
    local e, s = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
    local target = { continent = continent, area = area, ex = ex / e, ey = ey / e, sx = sx / s, sy = sy / s }
    for i = 1, #flat, 2 do
        local position = worldPosition(mapID, flat[i], flat[i + 1])
        if position then
            target[#target + 1] = { x = position.x, y = position.y }
        end
    end
    target.left = #target -- places not visited yet
    return target[1] and target
end

-- The map a zone of the data is drawn on: its own, or that of the zone it is part of. Nil for
-- a dungeon.
local function mapOf(zoneId)
    for _ = 1, 8 do
        local zone = ns.Data.zones[zoneId]
        if not zone or zone.isDungeon then
            return nil
        end
        if zone.uiMapId then
            return zone.uiMapId
        end
        zoneId = zone.parentZoneId
    end
end

-- Every place the step can be done at, on the step's map: the spawn points of whatever the
-- quest data names like the step (the quest's givers and takers, its creatures and objects,
-- and for an item whatever drops or sells it). The step's own point when the data has none.
local function placesOf(step)
    local flat = {}
    local data = ns.Data
    local quest = data and data.quests and data.quests[step.questID]
    if quest and data.npcs and data.objects and data.items and data.zones then
        local npcs, objects = data.npcs, data.objects
        local seen = {}
        local function add(row, name)
            local spawns = row and row.spawns
            if not spawns or seen[spawns] or (name or row.name) ~= step.name then
                return
            end
            seen[spawns] = true
            for zoneId, points in pairs(spawns) do
                if mapOf(zoneId) == step.map then
                    for i = 1, #points, 2 do
                        if points[i] ~= -1 then -- -1, -1 is a place inside an instance
                            flat[#flat + 1] = points[i] / 100
                            flat[#flat + 1] = points[i + 1] / 100
                        end
                    end
                end
            end
        end
        for _, ends in ipairs({ quest.start or {}, quest["end"] or {} }) do
            for _, id in ipairs(ends.npcs or {}) do
                add(npcs[id])
            end
            for _, id in ipairs(ends.objects or {}) do
                add(objects[id])
            end
        end
        local objectives = quest.objectives or {}
        for _, wanted in ipairs(objectives.npcs or {}) do
            add(npcs[wanted.id], wanted.text)
        end
        for _, wanted in ipairs(objectives.objects or {}) do
            add(objects[wanted.id], wanted.text)
        end
        for _, credit in ipairs(objectives.killCredits or {}) do
            local first = npcs[credit.npcIds[1]]
            for _, id in ipairs(credit.npcIds) do
                add(npcs[id], credit.text or first and first.name)
            end
        end
        for _, wanted in ipairs(objectives.items or {}) do
            local item = data.items[wanted.id] or {}
            local name = wanted.text or item.name
            for _, id in ipairs(item.npcDrops or {}) do
                add(npcs[id], name)
            end
            for _, id in ipairs(item.vendors or {}) do
                add(npcs[id], name)
            end
            for _, id in ipairs(item.objectDrops or {}) do
                add(objects[id], name)
            end
        end
    end
    if not flat[1] then
        flat = { step.x / 100, step.y / 100 }
    end
    return flat
end

-- The corpse, looked for on the player's map and then on the maps it is part of.
local function corpseTarget()
    local find = C_DeathInfo and C_DeathInfo.GetCorpseMapPosition
    local mapID = find and C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if not mapID then
            return nil
        end
        local position = find(mapID)
        if position then
            return newTarget(mapID, { position:GetXY() })
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
end

-- The place nearest to the player that has not been visited, and the square of its distance.
local function nearest(target, px, py)
    local best, bestSquare
    for i = 1, #target do
        local point = target[i]
        if not point.visited then
            local dx, dy = point.x - px, point.y - py
            local square = dx * dx + dy * dy
            if not bestSquare or square < bestSquare then
                best, bestSquare = point, square
            end
        end
    end
    return best, bestSquare
end

function Arrow:Create()
    local frame = CreateFrame("Frame", "LevelingAddonArrow", UIParent)
    self.frame = frame
    frame:SetSize(56, 60)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -110)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.055, 0.06, 0.66)

    self.texture = frame:CreateTexture(nil, "ARTWORK")
    self.texture:SetSize(36, 36)
    self.texture:SetPoint("TOP", 0, -4)
    self.texture:SetTexture(ARROW_TEXTURE)
    self.texture:SetVertexColor(0.95, 0.76, 0.19)

    self.ring = frame:CreateTexture(nil, "ARTWORK")
    self.ring:SetSize(36, 36)
    self.ring:SetPoint("TOP", 0, -4)
    self.ring:SetTexture(RING_TEXTURE)
    self.ring:SetVertexColor(0.95, 0.76, 0.19)
    self.ring:Hide()

    self.distance = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.distance:SetPoint("BOTTOM", 0, 5)

    -- In flight (see SetFlight): the time left, large, and the destination under it.
    self.flightTime = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    self.flightTime:SetPoint("TOP", 0, -12)
    self.flightTime:SetTextColor(0.95, 0.76, 0.19)
    self.flightName = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.flightName:SetPoint("BOTTOM", 0, 5)

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.combat = InCombatLockdown()
    frame:SetScript("OnEvent", function(_, event)
        self.combat = event == "PLAYER_REGEN_DISABLED"
        self:Fade()
    end)
end

-- Invisible where there is nothing to point at; dimmed in combat if the player wants that.
function Arrow:Fade()
    self.frame:SetAlpha(self.away and not self.flight and 0 or self.combat and ns.db.combatDim and 0.4 or 1)
end

-- In flight the arrow has nothing to point at, so Flights.lua (#16) borrows its frame: `time`
-- is the text shown large and `name` the destination under it. SetFlight(nil) gives the frame
-- back to the arrow. The frame grows sideways to fit the name.
function Arrow:SetFlight(time, name)
    if not self.frame then
        return
    end
    local changed = (time ~= nil) ~= (self.flight ~= nil)
    self.flight = time
    self.flightTime:SetText(time or "")
    if changed then
        self.flightName:SetText(name or "")
        self.frame:SetWidth(time and math.max(56, self.flightName:GetStringWidth() + 12) or 56)
        self:StepChanged()
    end
end

ns.Task("arrow", 0.1, function()
    Arrow:Update()
end)

-- Hand the waypoint to TomTom when it is there. Returns true if TomTom now has it.
function Arrow:UpdateTomTom(step)
    local tomtom = TomTom
    if not (tomtom and tomtom.AddWaypoint and tomtom.RemoveWaypoint) then
        return false
    end
    if self.waypointStep ~= step then
        if self.waypoint then
            tomtom:RemoveWaypoint(self.waypoint)
            self.waypoint = nil
        end
        self.waypointStep = step
        if step and ns.db.shown then
            self.waypoint = tomtom:AddWaypoint(step.map, step.x / 100, step.y / 100, {
                title = step.name,
                from = "Leveling Addon",
                persistent = false,
            })
        end
    end
    return true
end

local function sameStep(a, b)
    return a.questID == b.questID
        and a.kind == b.kind
        and a.name == b.name
        and a.map == b.map
        and a.x == b.x
        and a.y == b.y
end

-- Called when the current step, a setting, or where the player is may have changed. The
-- step's places are turned into world coordinates here, once, and never in the update loop.
function Arrow:StepChanged()
    if not self.frame then
        return
    end
    local step = ns.db.shown and ns.Steps:Current() or nil
    self.tomtom = self:UpdateTomTom(step)
    -- A ghost is shown the way to the corpse, whatever the step is.
    local wanted = ns.db.shown and UnitIsGhost and UnitIsGhost("player") and "corpse" or step
    local old = self.wanted
    local same = wanted == old or (wanted and old and wanted ~= "corpse" and old ~= "corpse" and sameStep(wanted, old))
    if not same or (wanted and not self.target) then
        self.target = wanted == "corpse" and corpseTarget()
            or wanted and wanted.map and wanted.x and wanted.y and newTarget(
                wanted.map,
                placesOf(wanted),
                wanted.kind == "kill" or wanted.kind == "loot"
            )
            or nil
        self.point, self.wait = nil, 0
    end
    self.wanted = wanted
    -- The frame stays shown while there is a target, and its task runs; Update hides the frame
    -- and stops the task where there is nothing to point at (an instance, another continent).
    local shown = self.target ~= nil and ns.db.arrow and not self.tomtom
    local flying = self.flight ~= nil and ns.db.shown
    self.frame:SetShown(shown or flying)
    ns.SetTask("arrow", shown and not flying)
    if flying then
        self.texture:Hide()
        self.ring:Hide()
        self.distance:SetText("")
        self.turn, self.yards = nil, nil -- so that the arrow draws itself again after landing
    end
    self:Fade()
end

-- Dying, coming back, and arriving somewhere else: the target, or whether it can be pointed at
-- from here, may have changed.
for _, event in ipairs({
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
}) do
    ns.On(event, function()
        Arrow:StepChanged()
    end)
end

function Arrow:Update()
    local target = self.target
    local px, py, _, continent = UnitPosition("player")
    if not px or continent ~= target.continent then
        -- No position here (an instance), or the target is on another continent: show nothing
        -- rather than an arrow in a meaningless direction. Neither changes without one of the
        -- events above, so the task rests until then.
        if not self.away then
            self.away = true
            self:Fade()
        end
        if px or IsInInstance() then
            ns.SetTask("arrow", false)
        end
        return
    end
    if self.away then
        self.away = false
        self:Fade()
    end

    self.wait = self.wait - 1
    if self.wait <= 0 then
        self.wait = RESELECT
        local point, square = nearest(target, px, py)
        if target.area and target[2] and square < AREA_YARDS * AREA_YARDS then
            -- Reached: on to the next nearest place, and after the last one round again.
            point.visited = true
            target.left = target.left - 1
            if target.left == 0 then
                for i = 1, #target do
                    target[i].visited = target[i] == point or nil
                end
                target.left = #target - 1
            end
            point = nearest(target, px, py)
        end
        self.point = point
    end

    local dx, dy = self.point.x - px, self.point.y - py
    local yards = math.floor(math.sqrt(dx * dx + dy * dy))
    -- A step with one place is arrived at; the places of an area are passed through instead.
    local arrived = not (target.area and target[2]) and yards < (target.area and AREA_YARDS or ARRIVE_YARDS)
    local facing = GetPlayerFacing() -- 0 is north, growing counter-clockwise; nil in instances
    -- The bearing in the same convention as facing; the turn is counter-clockwise from "ahead".
    local eastward, southward = dx * target.ex + dy * target.ey, dx * target.sx + dy * target.sy
    local turn = facing and (math.atan2(-eastward, -southward) - facing)
    self.ring:SetShown(arrived)
    self.texture:SetShown(turn ~= nil and not arrived)
    if turn and not arrived and math.abs(turn - (self.turn or math.huge)) >= MIN_TURN then
        self.turn = turn
        self.texture:SetRotation(turn)
    end
    local text = arrived and "" or yards
    if text ~= self.yards then
        self.yards = text
        self.distance:SetText(arrived and "" or yards .. " yd")
    end
end
