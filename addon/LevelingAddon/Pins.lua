-- One pin on the world map and one on the minimap for the current step, each with a tooltip
-- naming the step. When TomTom has taken the waypoint it draws its own icons on both, so we
-- draw neither. The two frames are made once; they are placed again only when the step or the
-- shown map changes, and the minimap pin follows the player on the shared loop.
local _, ns = ...

ns.defaults.pin = true

local TEXTURE = "Interface\\COMMON\\Indicator-Yellow"
-- Yards across the minimap at each of its zoom levels.
local OUTDOOR = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local canvas -- the world map's scrolling child, which the world-map pin sits on
local worldPin, miniPin
local step -- the step the pins show; nil when they show nothing
local continent, world -- its world position; nil where the game has none
local lastX, lastY -- where the minimap pin was put last

local function newPin(parent, size, level)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin:SetFrameLevel(parent:GetFrameLevel() + level)
    local texture = pin:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(TEXTURE)
    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then
        pin:SetMouseClickEnabled(false) -- tooltip only: clicks go through to the map
    end
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(step.name)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    pin:Hide()
    return pin
end

-- Put the world-map pin where the step is on the map being shown: the step's own map, or any
-- map that contains the spot (its continent, for example). The pin keeps its size on screen
-- at any map zoom.
local function placeOnMap()
    if not worldPin then
        return
    end
    local mapID = step and WorldMapFrame:GetMapID()
    local x, y
    if mapID and mapID == step.map then
        x, y = step.x / 100, step.y / 100
    elseif mapID and world then
        local _, position = C_Map.GetMapPosFromWorldPos(continent, world, mapID)
        if position then
            x, y = position:GetXY()
        end
    end
    if not x or x < 0 or x > 1 or y < 0 or y > 1 then
        worldPin:Hide()
        return
    end
    local scale = canvas:GetScale()
    worldPin:SetScale(1 / scale)
    worldPin:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() * scale, -y * canvas:GetHeight() * scale)
    worldPin:Show()
end

-- Put the minimap pin in the step's direction, at its distance; on the rim when it is further
-- away than the minimap shows. World x runs north and world y runs west.
local function placeOnMinimap()
    local px, py, _, instance = UnitPosition("player")
    if not px or instance ~= continent then
        lastX = nil
        miniPin:Hide()
        return
    end
    local radius = (IsIndoors() and INDOOR or OUTDOOR)[Minimap:GetZoom()] / 2
    local east, north = (py - world.y) / radius, (world.x - px) / radius
    local facing = GetCVar("rotateMinimap") == "1" and GetPlayerFacing()
    if facing then
        local sin, cos = math.sin(facing), math.cos(facing)
        east, north = east * cos + north * sin, north * cos - east * sin
    end
    -- GetMinimapShape is defined by addons that reshape the minimap. Shapes other than a full
    -- square are treated as round, which keeps the pin inside every one of them.
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local reach = square and math.max(math.abs(east), math.abs(north)) or math.sqrt(east * east + north * north)
    if reach > 1 then
        east, north = east / reach, north / reach
    end
    if east ~= lastX or north ~= lastY then
        lastX, lastY = east, north
        miniPin:SetPoint("CENTER", Minimap, "CENTER", east * Minimap:GetWidth() / 2, north * Minimap:GetHeight() / 2)
        miniPin:Show()
    end
end

ns.Task("pins", 0.05, placeOnMinimap)

-- After anything that may have changed the current step or a setting.
local function update()
    if not miniPin then
        return
    end
    local tomtom = ns.Arrow and ns.Arrow.tomtom
    local now = ns.db.shown and ns.db.pin and not tomtom and ns.Steps:Current() or nil
    if now and not (now.map and now.x and now.y) then
        now = nil
    end
    if now == step then
        return
    end
    step = now
    continent, world = nil, nil
    if step then
        continent, world = C_Map.GetWorldPosFromMapPos(step.map, CreateVector2D(step.x / 100, step.y / 100))
    end
    lastX = nil
    ns.SetTask("pins", world ~= nil)
    if world then
        placeOnMinimap()
    else
        miniPin:Hide()
    end
    placeOnMap()
end

-- ns.Refresh runs after every change to the route or the settings; the pins follow it, after
-- the arrow has settled whether TomTom has the waypoint.
local refresh = ns.Refresh
function ns.Refresh()
    refresh()
    update()
end

function ns.commands.pin()
    ns.Set("pin", not ns.db.pin)
    ns.say("map pins " .. (ns.db.pin and "on" or "off") .. ".")
end

ns.On("PLAYER_LOGIN", function()
    miniPin = newPin(Minimap, 14, 5)
    canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if canvas then
        worldPin = newPin(canvas, 22, 3000)
        -- Hooks run after the game's own code and never change which map is shown.
        for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged" }) do
            if WorldMapFrame[method] then
                hooksecurefunc(WorldMapFrame, method, placeOnMap)
            end
        end
    end
    update()
end)
