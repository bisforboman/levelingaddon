-- For players who level together and both run the addon (issue #21): a version check over
-- addon messages, a level-up announcement, and automatic quest sharing. Only the version
-- check is on by default. /lvl party switches them.
local addonName, ns = ...

ns.defaults.party = {
    version = true, -- say once when a party member runs a newer version
    announce = "off", -- level-ups go to "party", "guild" or "off"
    share = false, -- share a quest with the party when it is accepted
}

-- Version check --------------------------------------------------------------------------

-- An addon message is "<type> <payload>". "V 0.1.0" is the only type so far; a type this
-- version does not know is ignored, so later versions can add their own.
local PREFIX = "LevelingAddon"
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

if own and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    local told = false -- once per session
    ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
        if told or prefix ~= PREFIX or channel ~= "PARTY" or not ns.db.party.version then
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
        if ns.db.party.version and IsInGroup() then
            lastSent = GetTime()
            C_ChatInfo.SendAddonMessage(PREFIX, "V " .. ownText, "PARTY")
        end
    end
    local function groupChanged()
        local count = GetNumGroupMembers()
        if count > members and not waiting then
            waiting = true
            C_Timer.After(math.max(1, lastSent + INTERVAL - GetTime()), send)
        end
        members = count
    end
    ns.On("GROUP_ROSTER_UPDATE", groupChanged)
    ns.On("PLAYER_LOGIN", groupChanged) -- already in a group after /reload
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
    local to = ns.db.party.announce
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
    if not ns.db.party.share or not IsInGroup() then
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

-- /lvl party, /lvl party version, /lvl party announce party, /lvl party share ---------------

function ns.commands.party(arg)
    local party = ns.db.party
    local what, value = strsplit(" ", string.lower(arg or ""), 2)
    if what == "version" or what == "share" then
        party[what] = not party[what]
    elseif what == "announce" and (value == "party" or value == "guild" or value == "off") then
        party.announce = value
    elseif what ~= "" then
        ns.say("/lvl party and one of: version, share, announce party, announce guild, announce off.")
        return
    end
    local announce = party.announce == "off" and "off" or "to " .. party.announce
    ns.say(
        "party: version check "
            .. (party.version and "on" or "off")
            .. ", level-up announcement "
            .. announce
            .. ", quest sharing "
            .. (party.share and "on" or "off")
            .. "."
    )
end
