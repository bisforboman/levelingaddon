-- Start-up, saved settings and the slash command. The window and the arrow only draw what
-- ns.Steps says; nothing in the step logic depends on a frame being shown.
local addonName, ns = ...

ns.defaults = {
    shown = true, -- the window and arrow are visible
    arrow = true, -- draw our own arrow (ignored when TomTom takes the waypoint)
    rows = 8, -- steps in view
    scale = 1,
    skipped = {}, -- [step index] = true for steps the player chose to skip
}

local function say(text)
    print("|cfff2c230Leveling|r " .. text)
end
ns.say = say

-- Redraw everything that shows steps. Called after any change to the route or settings.
function ns.Refresh()
    if ns.Window then
        ns.Window:Refresh()
    end
    if ns.Arrow then
        ns.Arrow:StepChanged()
    end
end

function ns.SetShown(shown)
    ns.db.shown = shown
    ns.Refresh()
    if not shown then
        say("hidden. /lvl brings it back.")
    end
end

local commands = {}

function commands.show()
    ns.SetShown(true)
end

function commands.hide()
    ns.SetShown(false)
end

function commands.arrow()
    ns.db.arrow = not ns.db.arrow
    ns.Refresh()
    say("arrow " .. (ns.db.arrow and "on" or "off") .. ".")
end

function commands.rows(arg)
    local n = tonumber(arg)
    if not n or n < 3 or n > 16 then
        say("rows takes a number from 3 to 16.")
        return
    end
    ns.db.rows = math.floor(n)
    ns.Refresh()
end

function commands.scale(arg)
    local n = tonumber(arg)
    if not n or n < 0.6 or n > 2 then
        say("scale takes a number from 0.6 to 2.")
        return
    end
    ns.db.scale = n
    ns.Refresh()
end

-- Put the window back where it starts.
function commands.reset()
    ns.db.point = nil
    ns.Window:RestorePosition()
end

-- Bring every skipped step back.
function commands.unskip()
    wipe(ns.db.skipped)
    ns.Steps:Sync()
    ns.Refresh()
end

SLASH_LEVELINGADDON1 = "/lvl"
SlashCmdList.LEVELINGADDON = function(message)
    local command, arg = strsplit(" ", strtrim(message or ""), 2)
    command = string.lower(command or "")
    if command == "" then
        ns.SetShown(not ns.db.shown)
    elseif commands[command] then
        commands[command](arg)
    else
        say("/lvl, /lvl show, hide, arrow, rows N, scale N, reset, unskip")
    end
end

-- The addon list by the minimap calls this by name (see the TOC).
function LevelingAddon_OnCompartmentClick()
    ns.SetShown(not ns.db.shown)
end

-- Quest events arrive in bursts (QUEST_LOG_UPDATE especially), so they only mark the state as
-- stale; one read of the quest log follows a moment later.
local syncPending = false
local function syncSoon()
    if syncPending then
        return
    end
    syncPending = true
    C_Timer.After(0.2, function()
        syncPending = false
        if ns.Steps:Sync() then
            ns.Refresh()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= addonName then
            return
        end
        LevelingAddonDB = LevelingAddonDB or {}
        ns.db = LevelingAddonDB
        ns.firstRun = ns.db.shown == nil
        for key, value in pairs(ns.defaults) do
            if ns.db[key] == nil then
                ns.db[key] = type(value) == "table" and {} or value
            end
        end
    elseif event == "PLAYER_LOGIN" then
        for _, name in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do
            self:RegisterEvent(name)
        end
        ns.Steps:Sync()
        ns.Window:Create()
        ns.Arrow:Create()
        ns.Refresh()
        if ns.firstRun then
            say("is on. Drag the window to move it. /lvl hides or shows it.")
        end
    else
        if event == "QUEST_TURNED_IN" then
            ns.Steps:NoteTurnedIn(arg)
        end
        syncSoon()
    end
end)
