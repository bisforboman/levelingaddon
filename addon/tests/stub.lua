-- A stub of the game API for tests that run outside the game, shared by every test file.
-- Every widget method exists and returns something harmless. A test starts with
--     local T = dofile("addon/tests/stub.lua")
--     T.load()   -- runs the addon's files in TOC order; T.ns is their shared table
--     T.login()  -- ADDON_LOADED and PLAYER_LOGIN
-- and then drives the game through T: T.fire(event, ...), T.tick(seconds), T.cmd("rows 5"),
-- the fake quest log (T.log, T.completed), the fields below, and T.chat for what was printed.
-- Run tests from the repository root: lua5.1 addon/tests/test_core.lua
local T = {
    now = 0, -- GetTime, seconds
    clockMs = 0, -- debugprofilestop, milliseconds
    speed = 0, -- GetUnitSpeed
    combat = false,
    facing = 0,
    px = 0.492, -- the player's map position
    py = 0.463,
    log = {}, -- [quest id] = { need = n, have = n } for quests in the log
    completed = {}, -- [quest id] = true for quests handed in
    timers = {}, -- functions waiting in C_Timer.After
    chat = {}, -- lines printed
    frames = {},
    level = 1, -- UnitLevel
    xp = 0, -- UnitXP
    xpMax = 400, -- UnitXPMax
    zone = "Elwynn Forest", -- GetRealZoneText
    ns = {},
    mapID = 1429, -- the map the world map shows
    canvasScale = 1,
    zoom = 0, -- minimap zoom level
    indoors = false,
    cvars = {}, -- GetCVar
}
local function widget()
    local w = { scripts = {}, shown = true, h = 20, alpha = 1 }
    return setmetatable(w, {
        __index = function(t, k)
            if k == "SetScript" then
                return function(self, n, f)
                    self.scripts[n] = f
                end
            end
            if k == "SetHeight" then
                return function(self, v)
                    self.h = v
                end
            end
            if k == "GetHeight" then
                return function(self)
                    return self.h
                end
            end
            if k == "SetShown" then
                return function(self, v)
                    self.shown = v and true or false
                end
            end
            if k == "Show" then
                return function(self)
                    self.shown = true
                end
            end
            if k == "Hide" then
                return function(self)
                    self.shown = false
                end
            end
            if k == "IsShown" then
                return function(self)
                    return self.shown
                end
            end
            if k == "SetAlpha" then
                return function(self, v)
                    self.alpha = v
                end
            end
            if k == "GetAlpha" then
                return function(self)
                    return self.alpha
                end
            end
            if k == "SetText" then
                return function(self, v)
                    self.text = v
                end
            end
            if k == "IsMouseOver" then
                return function(self)
                    return self.over or false
                end
            end
            if k == "GetStringWidth" then
                return function()
                    return 80
                end
            end
            if k == "SetPoint" then
                return function(self, ...)
                    self.point = { ... }
                end
            end
            if k == "GetFrameLevel" or k == "GetScale" then
                return function()
                    return 1
                end
            end
            if k == "GetPoint" then
                return function()
                    return "TOPRIGHT", nil, "TOPRIGHT", -10, -20
                end
            end
            if k == "CreateTexture" or k == "CreateFontString" then
                return function()
                    return widget()
                end
            end
            if k == "IsOwned" then
                return function()
                    return false
                end
            end
            if type(k) == "string" and k:match("^%u") then
                return function() end
            end
        end,
    })
end
function CreateFrame(kind, name, parent)
    local f = widget()
    f.kind = kind
    f.name = name
    f.parent = parent
    T.frames[#T.frames + 1] = f
    return f
end
UIParent = widget()
GameTooltip = widget()
SlashCmdList = {}
function print(...)
    T.chat[#T.chat + 1] = table.concat({ ... }, " ")
    io.write("  chat: ", T.chat[#T.chat], "\n")
end
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
function strtrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
function strsplit(sep, s, n)
    local a, b = s:match("^([^" .. sep .. "]*)" .. sep .. "?(.*)$")
    return a, b ~= "" and b or nil
end
function GetTime()
    return T.now
end
function debugprofilestop()
    return T.clockMs
end
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage()
    return 123.4
end
function GetUnitSpeed()
    return T.speed
end
function UnitLevel()
    return T.level
end
function UnitXP()
    return T.xp
end
function UnitXPMax()
    return T.xpMax
end
function GetRealZoneText()
    return T.zone
end
function InCombatLockdown()
    return T.combat
end
function GetPlayerFacing()
    return T.facing
end
function CreateVector2D(x, y)
    return {
        x = x,
        y = y,
        GetXY = function(s)
            return s.x, s.y
        end,
    }
end
-- A 1000 x 1000 yard map; world x runs north, world y runs west, as in the game.
C_Map = {
    GetBestMapForUnit = function()
        return 1429
    end,
    GetPlayerMapPosition = function()
        return CreateVector2D(T.px, T.py)
    end,
    GetWorldPosFromMapPos = function(_, v)
        return 0, { x = -v.y * 1000, y = -v.x * 1000 }
    end,
    -- Map 13 is the continent: twice as wide and high, with map 1429 in its middle. No other
    -- map contains the spot.
    GetMapPosFromWorldPos = function(_, p, mapID)
        if mapID == 13 then
            return mapID, CreateVector2D(0.25 - p.y / 2000, 0.25 - p.x / 2000)
        end
    end,
}
-- The player's world position, from the same map position as above; instance 0.
function UnitPosition()
    return -T.py * 1000, -T.px * 1000, 0, 0
end
function IsIndoors()
    return T.indoors
end
function GetCVar(name)
    return T.cvars[name]
end
function hooksecurefunc(t, name, hook)
    local original = t[name]
    rawset(t, name, function(...)
        original(...)
        hook(...)
    end)
end
-- A 140 x 140 minimap, and a world map with a 1000 x 600 canvas.
Minimap = widget()
rawset(Minimap, "GetZoom", function()
    return T.zoom
end)
rawset(Minimap, "GetWidth", function()
    return 140
end)
rawset(Minimap, "GetHeight", function()
    return 140
end)
T.canvas = widget()
rawset(T.canvas, "GetWidth", function()
    return 1000
end)
rawset(T.canvas, "GetHeight", function()
    return 600
end)
rawset(T.canvas, "GetScale", function()
    return T.canvasScale
end)
WorldMapFrame = widget()
rawset(WorldMapFrame, "GetCanvas", function()
    return T.canvas
end)
rawset(WorldMapFrame, "GetMapID", function()
    return T.mapID
end)
function WorldMapFrame.OnMapChanged() end
function WorldMapFrame.OnCanvasScaleChanged() end
-- A fake quest log the test drives: quests in the log with their objective count, and quests
-- already handed in.
local log, completed = T.log, T.completed
C_QuestLog = {
    IsOnQuest = function(q)
        return log[q] ~= nil
    end,
    IsQuestFlaggedCompleted = function(q)
        return completed[q] == true
    end,
    GetQuestObjectives = function(q)
        local o = log[q]
        if not o or not o.need then
            return o and {} or nil
        end
        return { { finished = o.have >= o.need, numFulfilled = o.have, numRequired = o.need } }
    end,
}
C_Timer = {
    After = function(_, f)
        T.timers[#T.timers + 1] = f
    end,
}

-- Run the addon's files in the order the TOC lists them.
function T.load()
    local dir = "addon/LevelingAddon/"
    for line in io.lines(dir .. "LevelingAddon.toc") do
        if line:match("%.lua$") then
            assert(loadfile(dir .. line))("LevelingAddon", T.ns)
        end
    end
end

-- The frame Core listens and updates on: the first one the addon creates.
local function core()
    return T.frames[1]
end

-- Send a game event, then run the timers it started.
function T.fire(event, ...)
    core().scripts.OnEvent(core(), event, ...)
    local run = T.timers
    T.timers = {}
    for _, f in ipairs(run) do
        f()
    end
end

function T.login()
    T.fire("ADDON_LOADED", "Other")
    T.fire("ADDON_LOADED", "LevelingAddon")
    T.fire("PLAYER_LOGIN")
end

-- True while the shared update loop is running.
function T.looping()
    return core().scripts.OnUpdate ~= nil
end

-- One frame of the shared update loop.
function T.tick(seconds)
    core().scripts.OnUpdate(core(), seconds or 0.1)
end

function T.cmd(text)
    SlashCmdList.LEVELINGADDON(text)
end

return T
