-- Hints: one line on an item's tooltip, "Needed for: <quest>", when a quest the character has
-- or can still do needs the item, so that it is not sold or deleted. The lookup is the one junk
-- selling uses (ns.QuestNeedsItem in Junk.lua): by item id, with nothing scanned when a
-- tooltip opens. Also the quest giver's tooltip and the quest log marks (#80), further down.
local _, ns = ...

ns.defaults.itemHint = true
ns.AddSetting({
    key = "itemHint",
    label = "Quest item hint",
    tooltip = "Say on an item's tooltip which quest needs it.",
    onChange = function() end, -- read when the next tooltip opens; nothing to redraw
})

local function hint(tooltip, itemID)
    -- Only the two tooltips that show an item on its own, not the comparison tooltips.
    if not itemID or not ns.db.itemHint or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
        return
    end
    local _, questID, count = ns.QuestNeedsItem(itemID)
    local quest = questID and ns.Data.quests and ns.Data.quests[questID]
    if quest and quest.name then
        tooltip:AddLine("Needed for: " .. quest.name .. (count > 1 and " and " .. count - 1 .. " more" or ""))
    end
end

-- Newer clients hand every tooltip's data to callbacks; older ones run a script on the tooltip
-- when it is given an item. Both only add a line, after the game has filled the tooltip.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        hint(tooltip, data and data.id)
    end)
else
    for _, tooltip in pairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip.HasScript and tooltip:HasScript("OnTooltipSetItem") then
            tooltip:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                hint(self, link and tonumber(link:match("item:(%d+)")))
            end)
        end
    end
end

-- Quest givers and the quest log (#80) -------------------------------------------------------
-- On a quest giver's tooltip, one line per quest the character can pick up there now or hand
-- in there now: "! <quest>" and "? <quest>", those the steps suggest first, at most three and
-- then "and N more". In the quest log, a small mark on the quests in the guide's current steps.
-- Both are lookups by id when the tooltip or the log is drawn; nothing runs in the background.

local MAX_LINES = 3
local YELLOW = { 0.95, 0.76, 0.19 }
local MARK_TEXTURE = "Interface\\AddOns\\LevelingAddon\\ring.tga" -- the arrow's "arrived" ring

local markLog -- below

ns.defaults.npcHint = true
ns.defaults.questLogMark = true
ns.AddSetting({
    key = "npcHint",
    label = "Quest giver hint",
    tooltip = "On a quest giver's tooltip, list the quests you can pick up or hand in there.",
    onChange = function() end, -- read when the next tooltip opens; nothing to redraw
})
ns.AddSetting({
    key = "questLogMark",
    label = "Mark the trail in the quest log",
    tooltip = "Mark the quests in the guide's current steps in the quest log.",
    onChange = function()
        markLog()
    end,
})

-- Where the client keeps a unit's identity from addons (in combat or in instances, on some).
local function secret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- The NPC id in a creature's GUID: "Creature-0-<server>-<instance>-<zone>-<npc id>-<spawn>".
local function npcOf(unit)
    local guid = unit and UnitGUID(unit)
    if not guid or secret(guid) then
        return nil
    end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

-- Where the pending steps suggest a pick-up or hand-in: [kind .. quest id] = place in the list.
local function suggested()
    local places = {}
    for index, step in ipairs(ns.Steps.list) do
        local kind = step.kind
        if step.questID and (kind == "accept" or kind == "turnin") and ns.Steps:Status(index) == "pending" then
            local key = step.kind .. step.questID
            places[key] = places[key] or index
        end
    end
    return places
end

-- The tooltip lines for an NPC, by its id: what can be handed in or picked up there now, the
-- quests the steps suggest first in the steps' order, then hand-ins, then pick-ups.
function ns.QuestGiverLines(npcID)
    local data = ns.Data
    local npc = data and data.npcs and data.npcs[npcID]
    if not npc then
        return {}
    end
    local places, rows = suggested(), {}
    local function add(kind, id, glyph, order)
        local quest = data.quests and data.quests[id] or data.plannerQuests and data.plannerQuests[id]
        if quest and quest.name then
            local place = places[kind .. id] or math.huge
            rows[#rows + 1] = { text = glyph .. " " .. quest.name, place = place, order = order, id = id }
        end
    end
    for _, id in ipairs(npc.questEnds or {}) do
        if C_QuestLog.IsOnQuest(id) and ns.ReadyToHandIn and ns.ReadyToHandIn(id) then
            add("turnin", id, "?", 1)
        end
    end
    for _, id in ipairs(npc.questStarts or {}) do
        if ns.Planner.CanTake(id) then
            add("accept", id, "!", 2)
        end
    end
    table.sort(rows, function(a, b)
        if a.place ~= b.place then
            return a.place < b.place
        end
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
    local lines = {}
    for i = 1, math.min(#rows, MAX_LINES) do
        lines[i] = rows[i].text
    end
    if #rows > MAX_LINES then
        lines[#lines + 1] = "  and " .. (#rows - MAX_LINES) .. " more"
    end
    return lines
end

local function npcHint(tooltip)
    if tooltip ~= GameTooltip or not ns.db.npcHint or not tooltip.GetUnit then
        return
    end
    local _, unit = tooltip:GetUnit()
    if secret(unit) then
        return
    end
    local id = npcOf(unit)
    for _, line in ipairs(id and ns.QuestGiverLines(id) or {}) do
        tooltip:AddLine(line, YELLOW[1], YELLOW[2], YELLOW[3])
    end
end

local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and unitType then
    TooltipDataProcessor.AddTooltipPostCall(unitType, npcHint)
elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", npcHint)
end

-- The quest log: the classic window, whose rows are the buttons QuestLogTitle1 to
-- QuestLogTitle<QUESTS_DISPLAYED>, each with the log index it shows as its id. The marks are
-- set after the game has drawn the rows, and again when the steps change while it is open.
local marks = {} -- [row] = the mark's texture, made the first time that row needs one

local function logQuestID(index)
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        return info and not info.isHeader and info.questID or nil
    elseif GetQuestLogTitle then
        local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
        return not isHeader and questID or nil
    end
end

function markLog()
    local trail = {}
    for index, step in ipairs(ns.db.questLogMark and ns.Steps.list or {}) do
        if step.questID and ns.Steps:Status(index) == "pending" then
            trail[step.questID] = true
        end
    end
    for row = 1, QUESTS_DISPLAYED or 0 do
        local button = _G["QuestLogTitle" .. row]
        if not button then
            break
        end
        local id = button:IsShown() and logQuestID(button:GetID())
        local mark = marks[row]
        if id and trail[id] then
            if not mark then
                mark = button:CreateTexture(nil, "OVERLAY")
                mark:SetTexture(MARK_TEXTURE)
                mark:SetSize(10, 10)
                mark:SetPoint("RIGHT", button, "RIGHT", -2, 0)
                mark:SetVertexColor(YELLOW[1], YELLOW[2], YELLOW[3])
                marks[row] = mark
            end
            mark:Show()
        elseif mark then
            mark:Hide()
        end
    end
end

ns.On("PLAYER_LOGIN", function()
    if QuestLog_Update then
        hooksecurefunc("QuestLog_Update", markLog)
    end
end)

local refresh = ns.Refresh
function ns.Refresh()
    refresh()
    if QuestLogFrame and QuestLogFrame:IsShown() then
        markLog()
    end
end
