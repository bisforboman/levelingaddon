-- Automation (issue #9): accept and hand in the quests the addon suggests, without the clicks.
-- Only a quest with a pending "accept" or "turnin" step in ns.Steps is touched; a repeatable
-- quest never is, and a choice of rewards is left to the player. Holding Shift while the
-- window opens does the opposite of the setting for that window. Everything happens on the
-- game's quest and gossip events, and once more when the steps change under an open window.
local _, ns = ...

ns.defaults.autoAccept = true
ns.defaults.autoTurnIn = true
-- No onChange: ns.Refresh, below, looks at an open window again.
ns.AddSetting({
    key = "autoAccept",
    label = "Accept quests automatically",
    tooltip = "Accept the quests the addon suggests. Hold Shift for the opposite.",
})
ns.AddSetting({
    key = "autoTurnIn",
    label = "Hand in quests automatically",
    tooltip = "Hand in the quests the addon suggests, unless there is a reward to choose. Hold Shift for the opposite.",
})

local open -- the event of the NPC window that is open, nil when none is
local shift -- whether Shift was down when it opened

-- Is this kind of automation wanted for the open window, and does a pending step of that kind
-- suggest the quest?
local function suggested(kind, questID)
    local setting = kind == "accept" and ns.db.autoAccept or kind == "turnin" and ns.db.autoTurnIn
    local quest = ns.Data and ns.Data.quests and ns.Data.quests[questID]
    if not questID or setting == shift or (quest and quest.repeatable) then
        return false
    end
    for index, step in ipairs(ns.Steps.list) do
        if step.kind == kind and step.questID == questID and ns.Steps:Status(index) == "pending" then
            return true
        end
    end
    return false
end

-- A window that lists an NPC's quests: pick one the addon suggests, a hand-in before a pick-up.
-- Gossip entries are tables with the quest's id; the plain greeting is asked row by row.
local function gossip()
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
        if quest.isComplete and suggested("turnin", quest.questID) then
            return C_GossipInfo.SelectActiveQuest(quest.questID)
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
        if not quest.repeatable and suggested("accept", quest.questID) then
            return C_GossipInfo.SelectAvailableQuest(quest.questID)
        end
    end
end

local function greeting()
    for i = 1, GetActiveQuestID and GetNumActiveQuests() or 0 do
        local _, isComplete = GetActiveTitle(i)
        if isComplete and suggested("turnin", GetActiveQuestID(i)) then
            return SelectActiveQuest(i)
        end
    end
    for i = 1, GetAvailableQuestInfo and GetNumAvailableQuests() or 0 do
        local _, _, isRepeatable, _, questID = GetAvailableQuestInfo(i)
        if not isRepeatable and suggested("accept", questID) then
            return SelectAvailableQuest(i)
        end
    end
end

local windows = {
    GOSSIP_SHOW = gossip,
    QUEST_GREETING = greeting,
    QUEST_DETAIL = function()
        if suggested("accept", GetQuestID()) then
            AcceptQuest()
        end
    end,
    -- "Have you got them?": on to the reward window, if the quest is ready.
    QUEST_PROGRESS = function()
        if IsQuestCompletable() and suggested("turnin", GetQuestID()) then
            CompleteQuest()
        end
    end,
    -- The reward window. One reward or none is taken; a choice stops here.
    QUEST_COMPLETE = function()
        local choices = GetNumQuestChoices()
        if choices <= 1 and suggested("turnin", GetQuestID()) then
            GetQuestReward(choices)
        end
    end,
}

for event in pairs(windows) do
    ns.On(event, function()
        open, shift = event, IsShiftKeyDown() and true or false
        windows[event]()
    end)
end
ns.On("GOSSIP_CLOSED", function()
    if open == "GOSSIP_SHOW" then
        open = nil
    end
end)
ns.On("QUEST_FINISHED", function()
    if open ~= "GOSSIP_SHOW" then
        open = nil
    end
end)

-- Every change to the steps ends in ns.Refresh: a window that is still open is looked at again,
-- with Shift as it was when the window opened.
local refresh = ns.Refresh
function ns.Refresh()
    refresh()
    if open then
        windows[open]()
    end
end
