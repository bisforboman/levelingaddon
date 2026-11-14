-- One arrow pointing at the current step, with the distance in yards. If TomTom is installed
-- it gets the waypoint instead and we draw nothing, so there are never two arrows.
local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local ARRIVE_YARDS = 8
local MIN_TURN = 0.02 -- radians (about one degree); smaller changes do not redraw the arrow
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow" -- points up when not rotated

-- World position of a map point, or nil where the game has none (for example in instances).
local function worldPosition(mapID, x, y)
    local _, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    return position
end

-- Direction and distance from the player to a step.
--
-- The map's own east and south directions are measured in world space first, so nothing here
-- depends on which way the world axes run. Returns yards and the angle to turn the arrow by
-- (counter-clockwise from "straight ahead"); the angle is nil when facing is unknown.
local function vectorTo(step)
    local mapID = C_Map.GetBestMapForUnit("player")
    local mapPosition = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not mapPosition then
        return nil
    end
    local px, py = mapPosition:GetXY()
    local player = worldPosition(mapID, px, py)
    local east = worldPosition(mapID, px + 0.01, py)
    local south = worldPosition(mapID, px, py + 0.01)
    local target = worldPosition(step.map, step.x / 100, step.y / 100)
    if not (player and east and south and target) then
        return nil
    end

    local dx, dy = target.x - player.x, target.y - player.y
    local ex, ey = east.x - player.x, east.y - player.y
    local sx, sy = south.x - player.x, south.y - player.y
    local eastward = (dx * ex + dy * ey) / math.sqrt(ex * ex + ey * ey)
    local southward = (dx * sx + dy * sy) / math.sqrt(sx * sx + sy * sy)
    local yards = math.sqrt(dx * dx + dy * dy)

    local facing = GetPlayerFacing() -- 0 is north, growing counter-clockwise; nil in instances
    local bearing = math.atan2(-eastward, -southward) -- same convention as facing
    return yards, facing and (bearing - facing)
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

    self.distance = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.distance:SetPoint("BOTTOM", 0, 5)

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        frame:SetAlpha(event == "PLAYER_REGEN_DISABLED" and 0.4 or 1)
    end)
end

ns.Task("arrow", 0.05, function()
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

-- Called when the current step or a setting may have changed.
function Arrow:StepChanged()
    if not self.frame then
        return
    end
    local step = ns.db.shown and ns.Steps:Current() or nil
    self.step = step
    self.tomtom = self:UpdateTomTom(step)
    -- The frame stays shown while there is a step, and its task keeps running; Update hides
    -- the pieces instead when there is nothing to point at.
    local shown = step ~= nil and ns.db.arrow and not self.tomtom
    self.frame:SetShown(shown)
    ns.SetTask("arrow", shown)
end

function Arrow:Update()
    local yards, turn = vectorTo(self.step)
    local frame = self.frame
    if not yards then
        -- No position here (an instance, or a map with no coordinates): show nothing rather
        -- than an arrow frozen in its last direction.
        frame:SetAlpha(0)
        return
    end
    if frame:GetAlpha() == 0 then
        frame:SetAlpha(InCombatLockdown() and 0.4 or 1)
    end
    local arrived = yards < ARRIVE_YARDS
    self.texture:SetShown(turn ~= nil and not arrived)
    if turn and not arrived and math.abs(turn - (self.turn or math.huge)) >= MIN_TURN then
        self.turn = turn
        self.texture:SetRotation(turn)
    end
    self.distance:SetText(arrived and "" or string.format("%d yd", yards))
end
