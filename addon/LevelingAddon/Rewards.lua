-- Rewards (issue #10): when a quest's reward window offers a choice, put a small badge on the
-- reward that sells for most at a vendor (the game's gold coin) and on the best upgrade (the
-- game's green arrow from the bags). Nothing is picked: the player chooses. Everything comes
-- from the client while the window is open, and is looked at again when item data arrives.
--
-- "Upgrade" is a rough rule, by the owner's decision: item level against what is worn in the
-- same slot, for items the game says the character can use. Where that cannot be compared
-- there is no arrow.
local _, ns = ...

ns.defaults.rewardMarks = true

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemLevel = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo

-- The game's own textures: an atlas where this client has it, else a texture file.
local COIN = { "coin-gold", "Interface\\MoneyFrame\\UI-GoldIcon" }
local ARROW = { "bags-greenarrow", "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong" }
local SIZE = 16

-- Where each kind of equipment is worn. Ranged weapons, thrown weapons and relics are left
-- out: the slot they go in differs between clients, so they get no arrow.
local MAIN_HAND, OFF_HAND = 16, 17
local SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { MAIN_HAND, OFF_HAND },
    INVTYPE_2HWEAPON = { MAIN_HAND },
    INVTYPE_WEAPONMAINHAND = { MAIN_HAND },
    INVTYPE_WEAPONOFFHAND = { OFF_HAND },
    INVTYPE_SHIELD = { OFF_HAND },
    INVTYPE_HOLDABLE = { OFF_HAND },
}

local function itemLevel(link, baseLevel)
    return GetItemLevel and GetItemLevel(link) or baseLevel
end

-- The item level worn in a slot and what kind of item it is: 0 for an empty slot, nil while
-- the client cannot say.
local function worn(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then
        return 0
    end
    local _, _, _, baseLevel, _, _, _, _, equipLoc = GetItemInfo(link)
    return itemLevel(link, baseLevel), equipLoc
end

-- The item level a reward of this kind has to beat: the weaker of the two where it can go in
-- two slots. nil when there is nothing fair to compare with.
local function toBeat(equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then
        return nil
    end
    local level = worn(slots[1])
    if slots[1] == OFF_HAND and level == 0 then
        local _, mainHand = worn(MAIN_HAND)
        if mainHand == "INVTYPE_2HWEAPON" then
            return nil -- the off hand is empty because both hands are full
        end
    end
    if slots[2] and level then
        local second, secondLoc = worn(slots[2])
        if not second then
            return nil
        end
        -- A one-hand weapon is held against the off hand only when a weapon is in it: not
        -- against a shield, and not against an empty hand.
        if equipLoc ~= "INVTYPE_WEAPON" or secondLoc == "INVTYPE_WEAPON" or secondLoc == "INVTYPE_WEAPONOFFHAND" then
            level = math.min(level, second)
        end
    end
    return level
end

-- Which choice sells for most, and which is the biggest upgrade. Each can be nil; both are
-- while any choice's data has not arrived, because that one could be the best.
local function best(choices)
    local sellAt, bestValue, upgradeAt, bestGain = nil, 0, nil, 0
    for i = 1, choices do
        local link = GetQuestItemLink("choice", i)
        if not link then
            return nil
        end
        local _, _, count, _, usable = GetQuestItemInfo("choice", i)
        local _, _, _, baseLevel, _, _, _, _, equipLoc, _, price = GetItemInfo(link)
        if not price then
            return nil
        end
        local value = price * math.max(count or 1, 1)
        if value > bestValue then
            sellAt, bestValue = i, value
        elseif value == bestValue then
            sellAt = nil -- no single reward sells for most
        end
        local level, against = itemLevel(link, baseLevel), usable and toBeat(equipLoc)
        if level and against and level - against > bestGain then
            upgradeAt, bestGain = i, level - against
        end
    end
    return sellAt, upgradeAt
end

-- The game's button for a choice. Only read, never changed.
local function button(index)
    local frame = QuestInfoRewardsFrame
    for _, candidate in ipairs(frame and frame.RewardButtons or {}) do
        if candidate.type == "choice" and candidate:GetID() == index and candidate:IsShown() then
            return candidate
        end
    end
end

local badges -- { sell = frame, upgrade = frame }: ours, made at the first reward window

local function badge(look)
    local frame = CreateFrame("Frame")
    frame:SetSize(SIZE, SIZE)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(look[1]) then
        texture:SetAtlas(look[1])
    else
        texture:SetTexture(look[2])
    end
    return frame
end

-- Our badge becomes a child of the game's button, so that it scrolls and hides with it.
local function place(frame, corner, index)
    local target = index and button(index)
    if not target then
        frame:Hide()
        return
    end
    frame:SetParent(target)
    frame:SetFrameLevel(target:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint(corner, target.Icon or target, corner)
    frame:Show()
end

local open = false -- a reward window with a choice is open

local function mark()
    local sellAt, upgradeAt
    if open and ns.db.rewardMarks then
        sellAt, upgradeAt = best(GetNumQuestChoices())
    end
    if not badges then
        if not (sellAt or upgradeAt) then
            return
        end
        badges = { sell = badge(COIN), upgrade = badge(ARROW) }
    end
    place(badges.sell, "TOPRIGHT", sellAt)
    place(badges.upgrade, "TOPLEFT", upgradeAt)
end

-- A moment after the event, so that the game has laid its buttons out first.
local update = ns.Debounce(0.05, mark)

ns.On("QUEST_COMPLETE", function()
    -- GetQuestItemLink stands for the reward calls: on a client without them, nothing is done.
    open = GetQuestItemLink ~= nil and GetNumQuestChoices() > 1
    if open then
        update()
    end
end)
ns.On("QUEST_FINISHED", function()
    if open then
        open = false
        mark()
    end
end)
-- Item data that was not there yet, or other gear put on, while the window is open.
for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "QUEST_ITEM_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
    ns.On(event, function()
        if open then
            update()
        end
    end)
end

ns.AddSetting({
    key = "rewardMarks",
    label = "Mark quest rewards",
    tooltip = "On a choice of quest rewards, mark the one that sells for most and the best upgrade by item level.",
    onChange = mark,
})
