-- One pin on the world map and one on the minimap for the current step, and on the world map
-- a smaller, fainter, numbered pin for each of the next few places after it. Steps close
-- together share a pin, and a pin's tooltip names what is there. When TomTom has taken the
-- waypoint it draws its own icons, so we draw none. The frames are made once; they are placed
-- again only when the steps they show or the shown map change, and the minimap pin follows the
-- player on the shared loop.
local _, ns = ...

ns.defaults.pin = true

local TEXTURE = "Interface\\COMMON\\Indicator-Yellow"
-- Yards across the minimap at each of its zoom levels.
local OUTDOOR = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local LATER = 3 -- numbered pins for the places after the current step: a first number, to tune
local MERGE = 2 -- steps within this many percent of their zone map share a pin

local canvas -- the world map's scrolling child, which the world-map pins sit on
local mapPins = {} -- [0] for the current step's place, [1] to [LATER] for the places after it
local miniPin
-- What the pins show, by the same numbers: { map, x, y, names, continent, world }, with x and y
-- in percent and the world position nil where the game has none. `key` is the steps behind it.
local spots, key = {}, ""
local lastX, lastY -- where the minimap pin was put last

-- A pin for spot `n`. A later place's pin is fainter and carries its number.
local function newPin(parent, size, level, n)
    local pin = CreateFrame("Frame", nil, parent)
    pin.n = n
    pin:SetSize(size, size)
    pin:SetFrameLevel(parent:GetFrameLevel() + level)
    local texture = pin:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(TEXTURE)
    if n > 0 then
        pin:SetAlpha(0.7)
        local number = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        number:SetPoint("CENTER")
        number:SetTextColor(0, 0, 0)
        number:SetText(n)
    end
    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then
        pin:SetMouseClickEnabled(false) -- tooltip only: clicks go through to the map
    end
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local names = spots[self.n].names
        GameTooltip:SetText(names[1])
        for i = 2, #names do
            GameTooltip:AddLine(names[i])
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    pin:Hide()
    return pin
end

-- Put each world-map pin where its place is on the map being shown: the place's own map, or
-- any map that contains it (its continent, for example). A pin keeps its size on screen at any
-- map zoom.
local function placeOnMap()
    local mapID = mapPins[0] and WorldMapFrame:GetMapID()
    for n = 0, mapPins[0] and LATER or -1 do
        local pin, spot = mapPins[n], spots[n]
        local x, y
        if spot and mapID == spot.map then
            x, y = spot.x / 100, spot.y / 100
        elseif spot and mapID and spot.world then
            local _, position = C_Map.GetMapPosFromWorldPos(spot.continent, spot.world, mapID)
            if position then
                x, y = position:GetXY()
            end
        end
        if not x or x < 0 or x > 1 or y < 0 or y > 1 then
            pin:Hide()
        else
            local scale = canvas:GetScale()
            pin:SetScale(1 / scale)
            pin:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth() * scale, -y * canvas:GetHeight() * scale)
            pin:Show()
        end
    end
end

-- Put the minimap pin in the step's direction, at its distance; on the rim when it is further
-- away than the minimap shows. World x runs north and world y runs west.
local function placeOnMinimap()
    local spot = spots[0]
    local world = spot.world
    local px, py, _, instance = UnitPosition("player")
    if not px or instance ~= spot.continent then
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

-- The places to pin: the current step's, then those of the pending steps after it until
-- LATER more places are found. A step near a place already found joins it. Also returns a key
-- that is the same for as long as the steps found are.
local function gather()
    local found, parts = {}, {}
    local current, index
    if ns.db.shown and ns.db.pin and not (ns.Arrow and ns.Arrow.tomtom) then
        current, index = ns.Steps:Current()
    end
    if not (current and current.map and current.x and current.y) then
        return found, ""
    end
    for i = index, ns.Steps:Count() do
        local row = ns.Steps.list[i]
        if (i == index or ns.Steps:Status(i) == "pending") and row.map and row.x and row.y then
            local spot
            for n = 0, #found do
                local near = found[n]
                if near and near.map == row.map then
                    local dx, dy = near.x - row.x, near.y - row.y
                    if dx * dx + dy * dy <= MERGE * MERGE then
                        spot = near
                        break
                    end
                end
            end
            if not spot then
                local n = found[0] and #found + 1 or 0
                if n > LATER then
                    break
                end
                spot = { map = row.map, x = row.x, y = row.y, names = {} }
                found[n] = spot
            end
            local name, listed = tostring(row.name), false
            for _, other in ipairs(spot.names) do
                listed = listed or other == name
            end
            if not listed then
                table.insert(spot.names, name)
            end
            table.insert(parts, row.map .. ":" .. row.x .. ":" .. row.y .. ":" .. name)
        end
    end
    return found, table.concat(parts, "|")
end

-- After anything that may have changed the steps or a setting.
local function update()
    if not miniPin then
        return
    end
    local found, newKey = gather()
    if newKey == key then
        return
    end
    spots, key = found, newKey
    for n = 0, #spots do
        local spot = spots[n]
        if spot then
            local point = CreateVector2D(spot.x / 100, spot.y / 100)
            spot.continent, spot.world = C_Map.GetWorldPosFromMapPos(spot.map, point)
        end
    end
    lastX = nil
    local follow = spots[0] ~= nil and spots[0].world ~= nil
    ns.SetTask("pins", follow)
    if follow then
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
    miniPin = newPin(Minimap, 14, 5, 0)
    canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if canvas then
        mapPins[0] = newPin(canvas, 22, 3000, 0)
        for n = 1, LATER do
            mapPins[n] = newPin(canvas, 18, 3000 - n, n)
        end
        -- Hooks run after the game's own code and never change which map is shown.
        for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged" }) do
            if WorldMapFrame[method] then
                hooksecurefunc(WorldMapFrame, method, placeOnMap)
            end
        end
    end
    update()
end)
