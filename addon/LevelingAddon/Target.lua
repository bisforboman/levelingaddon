-- One macro that targets the current step's NPC or mobs and puts a raid marker on what it
-- targeted (#12). The player asks for it once with /lvl macro and drops it on an action bar;
-- from then on its text follows the current step. The game lets macros be created and edited
-- only out of combat, so a change made in combat waits for the end of it. The macro is never
-- made unasked, and a macro of the same name that the addon did not make is left alone.
local _, ns = ...

local NAME = "LvlTarget"
local ICON = "INV_MISC_QUESTIONMARK" -- the game then shows the icon of what the macro does
local LIMIT = 255 -- characters in a macro
local MARKER = 8 -- the skull
local ACCOUNT_SLOTS = 120

ns.defaults.targetMacro = false -- true once /lvl macro has made the macro

-- The map a zone of the data is drawn on: its own, or that of the zone it is part of.
local function mapOf(zones, zoneId)
    for _ = 1, 8 do
        local zone = zones and zones[zoneId]
        if not zone or zone.isDungeon then
            return nil
        end
        if zone.uiMapId then
            return zone.uiMapId
        end
        zoneId = zone.parentZoneId
    end
end

-- The names to target for a step, nearest the step's point first. A quest giver or taker is
-- the step's own name. A kill or loot step takes every creature the quest data lists under the
-- step's name: the objective's creatures, and for an item whatever drops or sells it.
local function namesOf(step)
    if step.kind == "accept" or step.kind == "turnin" then
        return { step.name }
    elseif step.kind ~= "kill" and step.kind ~= "loot" then
        return {}
    end
    local data = ns.Data or {}
    local quest, npcs, items = data.quests and data.quests[step.questID], data.npcs, data.items or {}
    local names, distance = {}, {}
    local function add(id, label)
        local npc = npcs[id]
        if not npc or (label or npc.name) ~= step.name then
            return
        end
        local best = distance[npc.name]
        if not best then
            best = math.huge
            names[#names + 1] = npc.name
        end
        for zoneId, points in pairs(npc.spawns or {}) do
            if step.x and mapOf(data.zones, zoneId) == step.map then
                for i = 1, #points, 2 do
                    local dx, dy = points[i] - step.x, points[i + 1] - step.y
                    best = math.min(best, dx * dx + dy * dy)
                end
            end
        end
        distance[npc.name] = best
    end
    local objectives = quest and npcs and quest.objectives or {}
    for _, wanted in ipairs(objectives.npcs or {}) do
        add(wanted.id, wanted.text)
    end
    for _, credit in ipairs(objectives.killCredits or {}) do
        local first = npcs[credit.npcIds[1]]
        for _, id in ipairs(credit.npcIds) do
            add(id, credit.text or first and first.name)
        end
    end
    for _, wanted in ipairs(objectives.items or {}) do
        local item = items[wanted.id] or {}
        local label = wanted.text or item.name
        for _, id in ipairs(item.npcDrops or {}) do
            add(id, label)
        end
        for _, id in ipairs(item.vendors or {}) do
            add(id, label)
        end
    end
    if not names[1] and step.kind == "kill" then
        return { step.name } -- no quest data loaded: the step is named after its creature
    end
    table.sort(names, function(a, b)
        if distance[a] ~= distance[b] then
            return distance[a] < distance[b]
        end
        return a < b
    end)
    return names
end

-- The macro's text for a step: as many of its names as fit, then the marker. Empty, a macro
-- that does nothing, when there is no name to target. Returns the number of names left out.
local function textFor(step)
    local names = step and namesOf(step) or {}
    local lines, tail = { "/cleartarget" }, "/tm " .. MARKER
    local length = #lines[1] + 1 + #tail
    for i, name in ipairs(names) do
        local line = "/targetexact " .. name
        if length + #line + 1 > LIMIT then
            return table.concat(lines, "\n") .. "\n" .. tail, #names - i + 1
        end
        length = length + #line + 1
        lines[#lines + 1] = line
    end
    if not lines[2] then
        return "", 0
    end
    return table.concat(lines, "\n") .. "\n" .. tail, 0
end

local shown -- the step the macro was last written for, as a key
local pending -- text waiting to be written, while in combat

local function write()
    if not pending or InCombatLockdown() then
        return
    end
    if GetMacroIndexByName(NAME) == 0 then
        ns.db.targetMacro = false -- the player deleted it; it is made again only on request
    elseif GetMacroBody(NAME) ~= pending then
        EditMacro(NAME, nil, nil, pending)
    end
    pending = nil
end

local function update()
    if not ns.db.targetMacro then
        return
    end
    local step = ns.Steps:Current()
    -- Not the table: the planner rebuilds the list on every pass.
    local key = step and table.concat({ step.kind, step.questID, tostring(step.name), step.map or 0 }, ":")
    if key == shown then
        return
    end
    shown = key
    local text, cut = textFor(step)
    if cut > 0 then
        ns.Debug("target macro: " .. cut .. " names did not fit.")
    end
    pending = text
    write()
end

local refresh = ns.Refresh
function ns.Refresh()
    refresh()
    update()
end

ns.On("PLAYER_REGEN_ENABLED", write)

function ns.commands.macro()
    if InCombatLockdown() then
        ns.say("macros cannot be made or changed in combat. Try again after the fight.")
        return
    end
    local text = textFor(ns.Steps:Current())
    if GetMacroIndexByName(NAME) == 0 then
        if GetNumMacros() >= (MAX_ACCOUNT_MACROS or ACCOUNT_SLOTS) then
            ns.say("no free slot for a general macro. Delete one and try again.")
            return
        end
        CreateMacro(NAME, ICON, text)
        ns.db.targetMacro = true
    elseif not ns.db.targetMacro then
        ns.say('there is already a macro named "' .. NAME .. '" that this addon did not make. Rename or delete it.')
        return
    end
    shown = nil
    update()
    PickupMacro(NAME)
    ns.say('macro "' .. NAME .. '" is on the cursor: drop it on an action bar. It targets and marks the current step.')
end
