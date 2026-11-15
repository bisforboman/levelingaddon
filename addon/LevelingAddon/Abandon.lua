-- Abandon: lists the quests in the log that are not worth keeping (issue #13), each with its
-- reason, and abandons the ticked ones when the player presses the button. Nothing is abandoned
-- without that click. The list is worked out when it is opened (/lvl abandon, or the button on
-- the settings page), never in the background.
--
-- A quest is listed for one of three reasons: it is too low for the character, the player
-- skipped it, or it is of a kind the player opted out of (ns.Planner.allow). Never for where it
-- is, never when it is ready to hand in, and never when the quest data does not know it.
local _, ns = ...

local Abandon = {}
ns.Abandon = Abandon

local LEVELS_BELOW = 7 -- as in Planner.lua: a quest this far under the character is not offered
local TOO_LOW = "too low level"
local SKIPPED = "skipped by you"
local KIND = { dungeon = "dungeon quest", raid = "raid quest", group = "group quest", pvp = "PvP quest" }
local REPORT_AFTER = 1 -- seconds until the log is read again to see what the game abandoned

-- The list ---------------------------------------------------------------------------------

-- The ids of the quests that take a place in the log, on either form of the quest log API.
local function questsInLog()
    local ids = {}
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID and not (info.isHidden or info.isTask or info.isBounty) then
                ids[#ids + 1] = info.questID
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not isHeader and questID then
                ids[#ids + 1] = questID
            end
        end
    end
    return ids
end

-- Waiting to be handed in: the client's word where it gives one, or every objective finished.
local function readyToHandIn(id)
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or IsQuestComplete and IsQuestComplete(id) then
        return true
    end
    local objectives = C_QuestLog.GetQuestObjectives(id) or {}
    for _, objective in ipairs(objectives) do
        if not objective.finished then
            return false
        end
    end
    return objectives[1] ~= nil
end

ns.ReadyToHandIn = readyToHandIn -- also for the quest giver's tooltip (Hints.lua)

local function tooLow(quest, level)
    return quest.level ~= nil and quest.level > 0 and quest.level + LEVELS_BELOW < level
end

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

-- [quest id] = the quests that name it as a prerequisite. Built the first time the list is
-- asked for.
local followers

local function buildFollowers()
    local start = ns.Clock()
    followers = {}
    for id, quest in pairs(ns.Data.plannerQuests) do
        for _, key in ipairs({ "pre", "preAll" }) do
            for _, before in ipairs(quest[key] or {}) do
                followers[before] = followers[before] or {}
                table.insert(followers[before], id)
            end
        end
    end
    ns.Report("abandon index", ns.Clock() - start)
end

-- Is the quest a prerequisite, directly or further up a chain, of a quest still worth doing:
-- one for this character, not handed in, not skipped, of an allowed kind and not too low?
local function leadsSomewhere(id, me, seen)
    local quests = ns.Data.plannerQuests
    for _, follower in ipairs(followers[id] or {}) do
        if not seen[follower] then
            seen[follower] = true
            local quest = quests[follower]
            if
                not C_QuestLog.IsQuestFlaggedCompleted(follower)
                and not ns.char.skipped[follower]
                and (not quest.mark or ns.Planner.allow[quest.mark])
                and (not quest.side or quest.side == me.side)
                and (not quest.races or contains(quest.races, me.race))
                and (not quest.classes or contains(quest.classes, me.class))
                and (not tooLow(quest, me.level) or leadsSomewhere(follower, me, seen))
            then
                return true
            end
        end
    end
    return false
end

-- The quests in the log that are not worth keeping, as rows of
-- { questID, name, reason, ticked }: `reason` is the text shown, `ticked` whether the row
-- starts ticked. Too-low quests come first, then by name. Issue #23 uses this list too.
function ns.QuestsToAbandon()
    local rows = {}
    local quests = ns.Data and ns.Data.plannerQuests
    if not quests then
        return rows
    end
    if not followers then
        buildFollowers()
    end
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local me = {
        level = UnitLevel("player") or 1,
        class = class,
        race = race and string.upper(race),
        side = faction and string.lower(faction),
    }
    for _, id in ipairs(questsInLog()) do
        local quest = quests[id]
        if quest and not readyToHandIn(id) then
            local reason
            if tooLow(quest, me.level) and not leadsSomewhere(id, me, { [id] = true }) then
                reason = TOO_LOW
            elseif ns.char.skipped[id] then
                reason = SKIPPED
            elseif quest.mark and not ns.Planner.allow[quest.mark] then
                reason = KIND[quest.mark] or quest.mark .. " quest"
            end
            if reason then
                rows[#rows + 1] = { questID = id, name = quest.name, reason = reason, ticked = reason == TOO_LOW }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.ticked ~= b.ticked then
            return a.ticked
        elseif a.name ~= b.name then
            return a.name < b.name
        end
        return a.questID < b.questID
    end)
    return rows
end

-- Abandoning --------------------------------------------------------------------------------

-- Ask the game to abandon one quest, on either form of the API. False where the client has
-- neither.
local function abandon(id)
    if C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
        C_QuestLog.SetSelectedQuest(id)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
        return true
    end
    local index = GetQuestLogIndexByID and SelectQuestLogEntry and SetAbandonQuest and AbandonQuest
    index = index and GetQuestLogIndexByID(id)
    if index and index > 0 then
        SelectQuestLogEntry(index)
        SetAbandonQuest()
        AbandonQuest()
        return true
    end
    return false
end

-- The button: abandon the ticked quests that are still in the log and still not ready to hand
-- in, then say what the game did with them.
local function abandonTicked()
    local wanted = {}
    for _, entry in ipairs(Abandon.list) do
        local id = entry.questID
        if entry.ticked and C_QuestLog.IsOnQuest(id) and not readyToHandIn(id) then
            wanted[#wanted + 1] = id
            abandon(id)
        end
    end
    Abandon.frame:Hide()
    C_Timer.After(REPORT_AFTER, function()
        local kept = 0
        for _, id in ipairs(wanted) do
            kept = kept + (C_QuestLog.IsOnQuest(id) and 1 or 0)
        end
        local gone = #wanted - kept
        if gone > 0 then
            ns.say(string.format("abandoned %d quest%s.", gone, gone == 1 and "" or "s"))
        end
        if kept > 0 then
            ns.say(kept .. " still in the quest log: the game did not let the addon abandon them. Use the quest log.")
        end
    end)
end

-- The window --------------------------------------------------------------------------------

local WIDTH = 320
local ROW_HEIGHT = 20
local TITLE_HEIGHT = 30
local BUTTON_HEIGHT = 24
local YELLOW = { 0.95, 0.76, 0.19 }
local BRIGHT = { 0.96, 0.95, 0.90 }
local DIM = { 0.72, 0.71, 0.67 }

local function draw()
    local ticked = 0
    for _, row in ipairs(Abandon.rows) do
        local entry = row.entry
        if entry then
            row.name:SetText(entry.name)
            row.reason:SetText(entry.reason)
            row.tick:SetShown(entry.ticked)
            ticked = ticked + (entry.ticked and 1 or 0)
        end
    end
    local button = Abandon.button
    local color = ticked > 0 and YELLOW or DIM
    button.count = ticked
    button.text:SetText(string.format("Abandon %d quest%s", ticked, ticked == 1 and "" or "s"))
    button.text:SetTextColor(color[1], color[2], color[3])
end

-- A row is one button: clicking anywhere on it ticks or unticks its quest.
local function createRow(parent, slot)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT - (slot - 1) * ROW_HEIGHT)
    row.box = row:CreateTexture(nil, "BACKGROUND")
    row.box:SetSize(14, 14)
    row.box:SetPoint("LEFT", 10, 0)
    row.box:SetColorTexture(1, 1, 1, 0.12)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetAllPoints(row.box)
    row.tick:SetAtlas("common-icon-checkmark")
    row.reason = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.reason:SetPoint("RIGHT", -10, 0)
    row.reason:SetTextColor(DIM[1], DIM[2], DIM[3])
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", 32, 0)
    row.name:SetPoint("RIGHT", row.reason, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetTextColor(BRIGHT[1], BRIGHT[2], BRIGHT[3])
    row:SetScript("OnClick", function()
        row.entry.ticked = not row.entry.ticked
        draw()
    end)
    return row
end

-- Created once, the first time there is something to list.
local function create()
    local frame = CreateFrame("Frame", "LevelingAddonAbandon", UIParent)
    Abandon.frame = frame
    Abandon.rows = {}
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "LevelingAddonAbandon") -- Escape closes it
    end

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.055, 0.06, 0.9)
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Quests not worth keeping")
    title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -8, -7)
    close:SetNormalAtlas("common-icon-redx")
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local button = CreateFrame("Button", nil, frame)
    Abandon.button = button
    button:SetHeight(BUTTON_HEIGHT)
    button:SetPoint("BOTTOMLEFT", 10, 10)
    button:SetPoint("BOTTOMRIGHT", -10, 10)
    local plate = button:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetColorTexture(YELLOW[1], YELLOW[2], YELLOW[3], 0.16)
    button.text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    button.text:SetPoint("CENTER")
    button:SetScript("OnClick", function()
        if button.count > 0 then
            abandonTicked()
        end
    end)
end

-- Open the list, worked out now. With nothing to list, one chat line and no window.
function ns.commands.abandon()
    local list = ns.QuestsToAbandon()
    if not list[1] then
        if Abandon.frame then
            Abandon.frame:Hide()
        end
        ns.say("no quest in the log needs abandoning.")
        return
    end
    if not Abandon.frame then
        create()
    end
    Abandon.list = list
    local rows = Abandon.rows
    for slot = 1, math.max(#list, #rows) do
        rows[slot] = rows[slot] or createRow(Abandon.frame, slot)
        rows[slot].entry = list[slot]
        rows[slot]:SetShown(list[slot] ~= nil)
    end
    draw()
    Abandon.frame:SetHeight(TITLE_HEIGHT + #list * ROW_HEIGHT + BUTTON_HEIGHT + 20)
    Abandon.frame:Show()
end

ns.AddSetting({
    label = "Quests not worth keeping",
    tooltip = "List the quests in the log that could be abandoned. Nothing is abandoned until you confirm.",
    func = function()
        ns.commands.abandon()
    end,
})
