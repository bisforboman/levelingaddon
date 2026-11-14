-- Support tools (#22): /lvl report, a copyable report for bug reports with no name, realm,
-- guild or account in it; named events other addons can listen to; and a verbose mode.
local _, ns = ...

-- Verbose mode ---------------------------------------------------------------------------

ns.defaults.verbose = false
ns.AddSetting({
    key = "verbose",
    label = "Verbose output",
    tooltip = "Print what the addon does, for chasing a bug.",
    onChange = function() end, -- read at every line; nothing to redraw
})

-- Prints only while /lvl verbose is on. For any feature to call.
function ns.Debug(text)
    if ns.db and ns.db.verbose then
        ns.say("|cff999999" .. text .. "|r")
    end
end

ns.commands.verbose = function()
    ns.Set("verbose", not ns.db.verbose)
    ns.say("verbose output " .. (ns.db.verbose and "on" or "off") .. ".")
end

-- Events for other addons ----------------------------------------------------------------
--
-- The names and arguments are in the README ("Events for other addons"); other people build
-- on them, so do not change them. They go through the game's EventRegistry where it exists,
-- and through a small stand-in with the same two methods where it does not. Either way it is
-- the global LevelingAddonEvents.

local registry = EventRegistry
if not registry then
    local callbacks = {} -- [event] = { [owner] = func }
    registry = {}
    function registry:RegisterCallback(event, func, owner)
        callbacks[event] = callbacks[event] or {}
        callbacks[event][owner] = func
    end
    function registry:UnregisterCallback(event, owner)
        if callbacks[event] then
            callbacks[event][owner] = nil
        end
    end
    function registry:TriggerEvent(event, ...)
        for owner, func in pairs(callbacks[event] or {}) do
            local ok, err = pcall(func, owner, ...)
            if not ok then
                ns.Debug(event .. " listener failed: " .. tostring(err))
            end
        end
    end
end
LevelingAddonEvents = registry

local function fire(event, ...)
    if ns.db and ns.db.verbose then
        local text = event
        for i = 1, select("#", ...) do
            text = text .. " " .. tostring((select(i, ...)))
        end
        ns.Debug(text)
    end
    local ok, err = pcall(registry.TriggerEvent, registry, event, ...)
    if not ok then
        ns.Debug(event .. " failed: " .. tostring(err))
    end
end

-- Every change to what is shown ends in ns.Refresh, so that is where the current step is
-- compared with the one last announced.
local refresh, lastStep = ns.Refresh, nil
function ns.Refresh()
    refresh()
    local step, index = ns.Steps:Current()
    -- Not the index or the table: the planner rebuilds the list on every pass.
    local key = step and table.concat({ step.kind, step.questID, step.objective or 0, tostring(step.name) }, ":")
    if key ~= lastStep then
        lastStep = key
        if step then
            fire("LevelingAddon.StepShown", index, step)
        end
    end
end

-- QUEST_ACCEPTED carries the quest id alone in the modern client and after the quest log
-- index in the classic one.
ns.On("QUEST_ACCEPTED", function(_, a, b)
    fire("LevelingAddon.QuestAccepted", b or a)
end)
ns.On("QUEST_TURNED_IN", function(_, questID)
    fire("LevelingAddon.QuestTurnedIn", questID)
end)

-- The report ------------------------------------------------------------------------------

local STEPS_BEFORE, STEPS_AFTER = 1, 4 -- steps listed around the current one

-- One value on one line; tables as { key=value, ... } with sorted keys.
local function show(value, depth)
    if type(value) ~= "table" then
        return tostring(value)
    elseif depth >= 3 then
        return "{...}"
    end
    local keys, parts = {}, {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
        table.insert(parts, tostring(key) .. "=" .. show(value[key], depth + 1))
    end
    return #parts == 0 and "{}" or "{ " .. table.concat(parts, ", ") .. " }"
end

local function addTable(lines, title, t)
    table.insert(lines, title .. ":")
    local keys = {}
    for key in pairs(t) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
        table.insert(lines, "  " .. tostring(key) .. " = " .. show(t[key], 1))
    end
    if #keys == 0 then
        table.insert(lines, "  none")
    end
end

-- The text of the report. Nothing here asks the game for the character's name, realm, guild
-- or account.
function ns.ReportText()
    local lines = {}
    local function add(text, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(text, ...) or text)
    end

    add("Leveling Addon report")
    if GetBuildInfo then
        local version, build, _, interface = GetBuildInfo()
        add("client: %s build %s, interface %s", tostring(version), tostring(build), tostring(interface))
    end
    local _, class = UnitClass("player")
    add("character: level %s %s", tostring(UnitLevel("player")), tostring(class))
    local zone, subZone = GetZoneText() or "?", GetSubZoneText() or ""
    add("zone: %s", subZone ~= "" and subZone ~= zone and zone .. ", " .. subZone or zone)
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position then
        local x, y = position:GetXY()
        add("position: map %d at %.1f, %.1f", mapID, x * 100, y * 100)
    else
        add("position: map %s, no position", tostring(mapID))
    end

    local Steps = ns.Steps
    local _, current = Steps:Current()
    local count = #Steps.list
    add("steps: %s of %d", current and tostring(current) or "finished", count)
    local at = current or count
    for index = math.max(1, at - STEPS_BEFORE), math.min(count, at + STEPS_AFTER) do
        add("  %s%d %s", index == current and ">" or " ", index, show(Steps.list[index], 2))
    end

    addTable(lines, "settings", ns.db)
    addTable(lines, "character settings", ns.char)

    local manifest = ns.Data and ns.Data.manifest
    add("data: %s", manifest and show(manifest, 1) or "not loaded")

    local stats = ns.Stats()
    add("timings:")
    add("  memory = %s", stats.memoryKB and string.format("%.0f KB", stats.memoryKB) or "not available")
    local names = {}
    for name in pairs(stats.timers) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        add("  %s = %.2f ms last time", name, stats.timers[name])
    end
    for _, state in ipairs({ "idle", "moving" }) do
        local loop = stats.loop[state]
        add("  loop while %s = %.3f ms over %d frames, longest %.3f", state, loop.ms, loop.frames, loop.max)
    end

    add("recent errors:")
    for _, text in ipairs(ns.errors) do
        add("  %s", text)
    end
    if #ns.errors == 0 then
        add("  none")
    end
    return table.concat(lines, "\n")
end

-- The window: a title, a text box to copy from, a close button. Made on first use.
local window, box

local function createWindow()
    window = CreateFrame("Frame", "LevelingAddonReport", UIParent)
    window:SetSize(520, 420)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)

    local background = window:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.055, 0.06, 0.95)

    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Leveling Addon report: Ctrl+C copies it")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local scroll = CreateFrame("ScrollFrame", "LevelingAddonReportScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(470)
    box:SetScript("OnEscapePressed", function()
        window:Hide()
    end)
    scroll:SetScrollChild(box)
end

ns.commands.report = function()
    if not window then
        createWindow()
    end
    box:SetText(ns.ReportText())
    window:Show()
    box:SetFocus()
    box:HighlightText()
end
