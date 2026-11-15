-- For players who level together and both run the addon (issue #21): a version check over
-- addon messages, a level-up announcement, automatic quest sharing, and each party member's
-- current step on their tooltip. Only the version check is on by default. The settings page
-- and /lvl party switch them.
local addonName, ns = ...

ns.defaults.partyVersion = true -- say once when a party member runs a newer version
ns.defaults.partyAnnounce = "off" -- level-ups go to "party", "guild" or "off"
ns.defaults.partyShare = false -- share a quest with the party when it is accepted
ns.defaults.partyStep = false -- tell the party which step this character is on

local sendSoon = function() end -- our version to the party, a moment from now
local stepSoon = function() end -- our step to the party, if it is not the one they have

ns.AddSetting({
    key = "partyVersion",
    label = "Party version check",
    tooltip = "Say once when a party member runs a newer version of the addon.",
    onChange = function()
        sendSoon()
    end,
})
ns.AddSetting({
    key = "partyAnnounce",
    label = "Announce level-ups",
    tooltip = "Say each new level in party or guild chat.",
    options = { "off", "party", "guild" },
    onChange = function() end, -- read at the next level; nothing to redraw
})
ns.AddSetting({
    key = "partyShare",
    label = "Share quests",
    tooltip = "Share a quest with the party when it is accepted.",
    onChange = function() end, -- read at the next quest; nothing to redraw
})
ns.AddSetting({
    key = "partyStep",
    label = "Share my step",
    tooltip = "Show party members who run the addon the step you are on, on your tooltip.",
    onChange = function()
        stepSoon()
    end,
})

-- Version check --------------------------------------------------------------------------

-- An addon message is "<type> <payload>": "V 0.1.0" is a version, "S ..." a step (further
-- down). A type this version does not know is ignored, so later versions can add their own.
local PREFIX = "LevelingAddon"
local canSend = C_ChatInfo and C_ChatInfo.SendAddonMessage
if canSend then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end
local INTERVAL = 10 -- seconds between two of our messages, at least

-- "1.2.3" as a number that orders versions, and as text. Nil for anything else: what arrives
-- was written by another player's client. Three digits a part keeps the number exact.
local function version(text)
    local a, b, c = string.match(type(text) == "string" and text or "", "^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
    if a then
        return a * 1e6 + b * 1e3 + c, text
    end
end

local own, ownText = version(C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version"))

if own and canSend then
    local told = false -- once per session
    ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
        if told or prefix ~= PREFIX or channel ~= "PARTY" or not ns.db.partyVersion then
            return
        end
        local theirs, theirText = version(type(text) == "string" and text:match("^V (.+)$"))
        if theirs and theirs > own then
            told = true
            ns.say(tostring(sender) .. " runs version " .. theirText .. ". Yours is " .. ownText .. ".")
        end
    end)

    -- Our version goes out when somebody joins the group, not when somebody leaves, and at
    -- most once per INTERVAL: a join inside the interval waits for its end.
    local members, lastSent, waiting = 0, -INTERVAL, false
    local function send()
        waiting = false
        if ns.db.partyVersion and IsInGroup() then
            lastSent = GetTime()
            C_ChatInfo.SendAddonMessage(PREFIX, "V " .. ownText, "PARTY")
        end
    end
    sendSoon = function()
        if not waiting then
            waiting = true
            C_Timer.After(math.max(1, lastSent + INTERVAL - GetTime()), send)
        end
    end
    local function groupChanged()
        local count = GetNumGroupMembers()
        if count > members then
            sendSoon()
        end
        members = count
    end
    ns.On("GROUP_ROSTER_UPDATE", groupChanged)
    ns.On("PLAYER_LOGIN", groupChanged) -- already in a group after /reload
end

-- Party members' steps -------------------------------------------------------------------
--
-- A step travels as numbers, never as text: "S <quest id> <kind> <index> <count> <need>",
-- where the kind is one letter and the index says which of the quest's givers (a), receivers
-- (t) or objectives (k, l, g) in the quest data the step names. The receiver takes the name
-- from its own data, in its own language, and shows nothing for what it cannot find. "S 0" is
-- no step. Messages go to the party only, when the step really changed and at most once per
-- STEP_INTERVAL; with the setting off, nothing is sent.

local STEP_INTERVAL = 5 -- seconds between two step messages, at least
local CODE = { accept = "a", turnin = "t", kill = "k", loot = "l", go = "g" }
local steps = {} -- [party member's name] = { questID, kind, index, count, need }, as received

-- The list in a quest's data that a step of this kind names an entry of, and where an entry
-- keeps its name.
local function targets(questID, code)
    local quest = ns.Data and ns.Data.plannerQuests and ns.Data.plannerQuests[questID]
    if not quest then
        return nil
    elseif code == "a" then
        return quest.start, 1
    elseif code == "t" then
        return quest.finish, 1
    end
    return quest.obj, 2
end

-- A party member's step as the window would show it: the game's mark for a quest to pick up
-- or hand in, a name, a count. Nil when nothing is known or our data does not have it.
local function stepLine(name)
    local step = steps[name]
    local list, field = targets(step and step.questID, step and step.kind)
    local text = list and list[step.index] and list[step.index][field]
    if type(text) ~= "string" then
        return nil
    elseif step.kind == "a" then
        return "! " .. text
    elseif step.kind == "t" then
        return "? " .. text
    elseif step.need > 0 and step.kind ~= "g" then
        return text .. " " .. step.count .. "/" .. step.need
    end
    return text
end

local function inParty(name)
    for i = 1, 4 do
        if UnitName("party" .. i) == name then
            return true
        end
    end
    return false
end

if canSend then
    -- What arrives was written by another player's client: only the exact form, from a member
    -- of our party, with every number in range, is kept. A name is kept without its realm.
    ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
        if prefix ~= PREFIX or channel ~= "PARTY" or type(text) ~= "string" or #text > 40 then
            return
        end
        local name = type(sender) == "string" and sender:match("^[^-]+")
        if not name or not inParty(name) then
            return
        elseif text == "S 0" then
            steps[name] = nil
            return
        end
        local questID, kind, index, count, need = text:match("^S (%d+) ([atklg]) (%d+) (%d+) (%d+)$")
        questID, index, count, need = tonumber(questID), tonumber(index), tonumber(count), tonumber(need)
        if questID and questID >= 1 and questID < 1e7 and index >= 1 and index <= 50 and count < 1e4 and need < 1e4 then
            steps[name] = { questID = questID, kind = kind, index = index, count = count, need = need }
        end
    end)

    -- The current step as a message. The planner makes the step list anew on every pass, so
    -- the message itself is what is compared: kind, quest, objective and count.
    local function stepMessage()
        local step, index = ns.Steps:Current()
        local code = step and ns.db.partyStep and CODE[step.kind]
        local list, field = targets(step and step.questID, code)
        for at, target in ipairs(code and list or {}) do
            if target[field] == step.name then
                local count, need = ns.Steps:Progress(index), step.need or 0
                return string.format("S %d %s %d %d %d", step.questID, code, at, count, need)
            end
        end
        return "S 0"
    end

    local sent, lastSent, waiting = "S 0", -STEP_INTERVAL, false -- sent: what the party has of us
    local function send()
        waiting = false
        local text = stepMessage()
        if text ~= sent and IsInGroup() then
            sent, lastSent = text, GetTime()
            C_ChatInfo.SendAddonMessage(PREFIX, text, "PARTY")
        end
    end
    stepSoon = function()
        if not waiting and IsInGroup() and stepMessage() ~= sent then
            waiting = true
            C_Timer.After(math.max(1, lastSent + STEP_INTERVAL - GetTime()), send)
        end
    end

    -- Every change to what is shown ends in ns.Refresh.
    local refresh = ns.Refresh
    function ns.Refresh()
        refresh()
        stepSoon()
    end

    -- Whoever left is forgotten, and whoever joined has nothing of us yet.
    local members = 0
    ns.On("GROUP_ROSTER_UPDATE", function()
        for name in pairs(steps) do
            if not inParty(name) then
                steps[name] = nil
            end
        end
        local count = GetNumGroupMembers()
        if count > members then
            sent = "S 0"
            stepSoon()
        end
        members = count
    end)

    -- One line on the tooltip of a party member whose step is known. Only a line is added,
    -- after the game has filled the tooltip. Where the client keeps a unit's identity from
    -- addons (in combat or in instances, on some), nothing is added.
    local function secret(value)
        return issecretvalue ~= nil and issecretvalue(value)
    end
    local function addLine(tooltip)
        if tooltip ~= GameTooltip or not next(steps) or not tooltip.GetUnit then
            return
        end
        local _, unit = tooltip:GetUnit()
        if secret(unit) or not unit or not UnitInParty(unit) then
            return
        end
        local name = UnitName(unit)
        local text = not secret(name) and stepLine(name)
        if text then
            tooltip:AddLine("Leveling: " .. text)
        end
    end
    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and unitType then
        TooltipDataProcessor.AddTooltipPostCall(unitType, addLine)
    elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", addLine)
    end
end

-- Level-up announcement ------------------------------------------------------------------

local function duration(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then
        return math.floor(seconds) .. " s"
    elseif minutes < 60 then
        return minutes .. " min"
    end
    return math.floor(minutes / 60) .. " h " .. minutes % 60 .. " min"
end

ns.On("PLAYER_LEVEL_UP", function(_, level)
    local to = ns.db.partyAnnounce
    if to == "party" and IsInGroup() or to == "guild" and IsInGuild() then
        local text = "Level " .. tostring(level) .. "!"
        -- The level tracker says how long the level took; without it, or for a level it saw
        -- only part of, no time.
        local seconds, partial
        if ns.Tracker then
            seconds, partial = ns.Tracker.LevelTime(level - 1)
        end
        if type(seconds) == "number" and not partial then
            text = text .. " It took " .. duration(seconds) .. "."
        end
        local sendChat = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        sendChat(text, string.upper(to))
    end
end)

-- Quest sharing --------------------------------------------------------------------------

-- QUEST_ACCEPTED carries the quest id alone in the modern client, and the quest log index
-- before it in the classic one. Sharing works on the selected quest, so the selection is put
-- back afterwards.
ns.On("QUEST_ACCEPTED", function(_, index, questID)
    if not ns.db.partyShare or not IsInGroup() then
        return
    end
    if C_QuestLog.IsPushableQuest then
        questID = questID or index
        if C_QuestLog.IsPushableQuest(questID) then
            local selected = C_QuestLog.GetSelectedQuest()
            C_QuestLog.SetSelectedQuest(questID)
            QuestLogPushQuest()
            C_QuestLog.SetSelectedQuest(selected)
        end
    elseif questID and SelectQuestLogEntry and GetQuestLogPushable then
        local selected = GetQuestLogSelection()
        SelectQuestLogEntry(index)
        if GetQuestLogPushable() then
            QuestLogPushQuest()
        end
        SelectQuestLogEntry(selected)
    end
end)

-- /lvl party, and /lvl party version, announce party, share, step --------------------------

function ns.commands.party(arg)
    local what, value = strsplit(" ", string.lower(arg or ""), 2)
    if what == "version" then
        ns.Set("partyVersion", not ns.db.partyVersion)
    elseif what == "share" then
        ns.Set("partyShare", not ns.db.partyShare)
    elseif what == "step" then
        ns.Set("partyStep", not ns.db.partyStep)
    elseif what == "announce" and (value == "party" or value == "guild" or value == "off") then
        ns.Set("partyAnnounce", value)
    elseif what ~= "" then
        ns.say("/lvl party and one of: version, share, step, announce party, announce guild, announce off.")
        return
    end
    local announce = ns.db.partyAnnounce == "off" and "off" or "to " .. ns.db.partyAnnounce
    ns.say(
        "party: version check "
            .. (ns.db.partyVersion and "on" or "off")
            .. ", level-up announcement "
            .. announce
            .. ", quest sharing "
            .. (ns.db.partyShare and "on" or "off")
            .. ", sharing my step "
            .. (ns.db.partyStep and "on" or "off")
            .. "."
    )
    for i = 1, 4 do
        local name = UnitName and UnitName("party" .. i)
        local text = name and stepLine(name)
        if text then
            ns.say(name .. ": " .. text)
        end
    end
end
