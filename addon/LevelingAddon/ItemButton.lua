-- One button for the usable item the current step needs (issue #11), shown while that item is
-- in the bags or equipped and hidden otherwise. Clicking it, or pressing the key bound to it
-- (Bindings.xml), uses the item.
--
-- The button is a secure frame: the game blocks showing, hiding, moving and re-pointing it in
-- combat. Every such change is made in update(), which does nothing in combat and runs again
-- when combat ends. It is its own frame, never anchored to the guide window, so the window
-- stays free to fold and fade in combat.
local _, ns = ...

ns.defaults.itemButton = true
ns.AddSetting({
    key = "itemButton",
    label = "Quest item button",
    tooltip = "A button for the usable item the current step needs.",
})

-- The texts the game's key bindings screen shows for the binding in Bindings.xml.
BINDING_HEADER_LEVELINGADDON = "Leveling Addon"
_G["BINDING_NAME_CLICK LevelingAddonItemButton:LeftButton"] = "Use the step's quest item"

local SIZE = 36

local button, icon, cooldown
local item -- the item id the button uses; nil while it is hidden
local placed = false -- the button is where the saved settings say
local moving = false

local function usable(itemID)
    return itemID and C_Item.GetItemSpell(itemID) and C_Item.GetItemCount(itemID) > 0
end

-- The item to use for the step, or nil. The quest log's own "special item" for the step's quest
-- comes first; otherwise the first of the quest's items in the data that the client says has a
-- use effect. Either way the character must have it. Not for a hand-in: nothing is left to use.
local function stepItem(step)
    local questID = step and step.kind ~= "turnin" and step.questID
    if not questID then
        return nil
    end
    local index = GetQuestLogSpecialItemInfo and C_QuestLog.GetLogIndexForQuestID(questID)
    local link = index and GetQuestLogSpecialItemInfo(index)
    local special = link and tonumber(link:match("item:(%d+)"))
    if special and C_Item.GetItemCount(special) > 0 then
        return special
    end
    local quest = ns.Data and ns.Data.quests and ns.Data.quests[questID]
    if not quest then
        return nil
    end
    if usable(quest.sourceItemId) then
        return quest.sourceItemId
    end
    for _, itemID in ipairs(quest.requiredSourceItems or {}) do
        if usable(itemID) then
            return itemID
        end
    end
    for _, objective in ipairs(quest.objectives and quest.objectives.items or {}) do
        if usable(objective.id) then
            return objective.id
        end
    end
    return nil
end

-- The cooldown is drawn by a plain child frame, which may change in combat.
local function showCooldown()
    if item then
        local start, duration = C_Container.GetItemCooldown(item)
        cooldown:SetCooldown(start, duration)
    end
end

-- The position is kept in our own saved settings, like the window's.
local function stopMoving()
    if moving then
        moving = false
        button:StopMovingOrSizing()
        button:SetUserPlaced(false)
        local point, _, relativePoint, x, y = button:GetPoint(1)
        ns.db.itemButtonPoint = { point, relativePoint, x, y }
    end
end

local function create()
    button = CreateFrame("Button", "LevelingAddonItemButton", UIParent, "SecureActionButtonTemplate")
    button:Hide()
    button:SetSize(SIZE, SIZE)
    button:SetAttribute("type", "item")
    -- Left click only, on press and on release: the game acts on the one its "cast on key
    -- down" setting names. The right button is left free for dragging.
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("RightButton")
    button:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            moving = true
            self:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", stopMoving)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(item)
        GameTooltip:AddLine("Drag with the right mouse button to move.", 0.72, 0.71, 0.67)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
end

-- Beside the guide window's own starting place (Window.lua), to its left.
local function place()
    placed = true
    local saved = ns.db.itemButtonPoint
    button:ClearAllPoints()
    if saved then
        button:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -478, -190)
    end
end

-- The one place the button is created, placed, pointed at an item, shown or hidden. In combat
-- it does nothing: whatever changed is still true, or not, when combat ends and this runs again.
local function update()
    if InCombatLockdown() then
        return
    end
    if not button then
        create()
    end
    if not placed then
        place()
    end
    local now = ns.db.shown and ns.db.itemButton and stepItem(ns.Steps:Current()) or nil
    if now == item then
        return
    end
    item = now
    if item then
        button:SetAttribute("item", "item:" .. item)
        icon:SetTexture(C_Item.GetItemIconByID(item))
        showCooldown()
        button:Show()
    else
        button:Hide()
    end
end

-- ns.Refresh runs after every change to the current step or the settings.
local refresh = ns.Refresh
function ns.Refresh()
    refresh()
    update()
end

-- /lvl reset and the settings page's "Reset position" put the button back as well.
local reset = ns.commands.reset
function ns.commands.reset()
    reset()
    ns.db.itemButtonPoint = nil
    placed = false
    update()
end

-- Core's own handler for PLAYER_LOGIN ends in ns.Refresh, so the button exists by now.
ns.On("PLAYER_LOGIN", function()
    ns.On("BAG_UPDATE", ns.Debounce(0.2, update))
    ns.On("BAG_UPDATE_COOLDOWN", showCooldown)
    ns.On("PLAYER_REGEN_ENABLED", update)
    -- A drag still going when combat starts ends here, while the button may still be touched.
    ns.On("PLAYER_REGEN_DISABLED", stopMoving)
end)
