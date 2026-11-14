-- Reward marks: the choice that sells for most and the best upgrade by item level get a badge,
-- and nothing is marked that cannot be judged.
-- From the repository root: lua5.1 addon/tests/test_rewards.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd

-- The game API this feature calls: the reward window's choices, item facts and worn gear.
local items = {} -- [link] = { level, equipLoc, price }; an absent link has not loaded yet
local choices = {} -- { link, count, usable } per choice
local gear = {} -- [slot] = link
local buttons = {}
function GetNumQuestChoices()
    return #choices
end
function GetQuestItemLink(_, i)
    return choices[i][1]
end
function GetQuestItemInfo(_, i)
    return "name", "texture", choices[i][2], 1, choices[i][3]
end
function GetItemInfo(link)
    local item = items[link]
    if item then
        return link, link, 1, item[1], 1, "", "", 1, item[2], "", item[3]
    end
end
function GetInventoryItemLink(_, slot)
    return gear[slot]
end
-- Automation.lua listens to the same window; it has no step for this quest and leaves it alone.
function IsShiftKeyDown()
    return false
end
function GetQuestID()
    return 1
end
QuestInfoRewardsFrame = { RewardButtons = buttons }
for i = 1, 4 do
    buttons[i] = CreateFrame("Button")
    buttons[i].type = "choice"
    buttons[i].Icon = {}
    rawset(buttons[i], "GetID", function()
        return i
    end)
end
T.frames = {} -- so that Core's frame is the first again

T.load()
T.login()
local made = #T.frames

-- Open the reward window with these choices; returns the choice each badge sits on.
local function at(frame)
    for i, button in ipairs(buttons) do
        if frame and frame.shown and frame.point[2] == button.Icon then
            return i
        end
    end
end
local function marks()
    local sell, upgrade
    for i = made + 1, #T.frames do
        local frame = T.frames[i]
        if frame.point and frame.point[1] == "TOPRIGHT" then
            sell = frame
        elseif frame.point then
            upgrade = frame
        end
    end
    return at(sell), at(upgrade)
end
local function window(list)
    fire("QUEST_FINISHED")
    choices = list
    fire("QUEST_COMPLETE")
    return marks()
end
-- The expected marks first: only a call in last place hands on both of its values.
local function same(wantSell, wantUpgrade, sell, upgrade)
    assert(sell == wantSell, "sell badge on " .. tostring(sell))
    assert(upgrade == wantUpgrade, "upgrade badge on " .. tostring(upgrade))
end

items.helm = { 10, "INVTYPE_HEAD", 100 }
items.oldHelm = { 8, "INVTYPE_HEAD", 50 }
items.ring = { 12, "INVTYPE_FINGER", 300 }
items.ring9 = { 9, "INVTYPE_FINGER", 10 }
items.ring14 = { 14, "INVTYPE_FINGER", 10 }
items.potion = { 5, "", 40 }
items.sword = { 10, "INVTYPE_WEAPON", 20 }
items.sword15 = { 15, "INVTYPE_WEAPON", 20 }
items.staff = { 12, "INVTYPE_2HWEAPON", 20 }
items.shield = { 20, "INVTYPE_SHIELD", 20 }
items.shield5 = { 5, "INVTYPE_SHIELD", 20 }
items.bow = { 30, "INVTYPE_RANGED", 20 }

-- A single reward, or none: nothing happens, and no frame is made.
same(nil, nil, window({ { "helm", 1, true } }))
same(nil, nil, window({}))
assert(#T.frames == made)

-- The highest sell value is price times count: ten potions beat one ring.
gear = { [1] = "oldHelm", [11] = "ring14", [12] = "ring14" }
same(3, 1, window({ { "helm", 1, true }, { "ring", 1, true }, { "potion", 10, true } }))
assert(#T.frames == made + 2, "two badges, made once")

-- A tie for the highest value marks none; all worthless marks none.
same(nil, nil, window({ { "ring9", 1, true }, { "ring14", 1, true } }))
items.free = { 1, "", 0 }
same(nil, nil, window({ { "free", 1, true }, { "free", 1, true } }))

-- A ring is held against the weaker of the two worn: level 12 beats the 9, not the 14.
gear = { [1] = "helm", [11] = "ring14", [12] = "ring9" }
same(2, 2, window({ { "helm", 1, true }, { "ring", 1, true } }))
gear[12] = "ring14"
same(2, nil, window({ { "helm", 1, true }, { "ring", 1, true } }))
-- An empty slot is the weakest there is.
gear[12] = nil
same(2, 2, window({ { "helm", 1, true }, { "ring", 1, true } }))

-- The biggest gain wins: +4 on the head against +3 on the finger.
gear = { [1] = "oldHelm", [11] = "ring9", [12] = "ring9" }
items.helm[1] = 12
same(1, 2, window({ { "ring", 1, true }, { "helm", 1, true } }))
items.helm[1] = 10

-- An item the class cannot use gets no arrow, however good.
gear = { [1] = "oldHelm" }
same(1, nil, window({ { "helm", 1, false }, { "potion", 1, true } }))

-- A kind with no slot we can be sure of (a bow) gets none either.
same(2, nil, window({ { "bow", 1, true }, { "potion", 1, true } }))

-- One-hand weapons: against the main hand alone beside a shield or an empty hand, against the
-- weaker when two weapons are held.
gear = { [16] = "sword15", [17] = "shield5" }
same(2, nil, window({ { "sword", 1, true }, { "potion", 1, true } }))
gear = { [16] = "sword15" }
same(2, nil, window({ { "sword", 1, true }, { "potion", 1, true } }))
items.dagger = { 4, "INVTYPE_WEAPON", 1 }
gear = { [16] = "sword15", [17] = "dagger" }
same(2, 1, window({ { "sword", 1, true }, { "potion", 1, true } }))
-- A shield with a two-hander worn cannot be compared; with a free off hand it is an upgrade.
gear = { [16] = "staff" }
same(2, nil, window({ { "shield", 1, true }, { "potion", 1, true } }))
gear = { [16] = "sword" }
same(2, 1, window({ { "shield", 1, true }, { "potion", 1, true } }))

-- Data that has not arrived: no mark at all, then the marks when it comes. Nothing is polled.
gear = { [1] = "oldHelm" }
same(nil, nil, window({ { "helm", 1, true }, { "late", 1, true } }))
assert(#T.timers == 0)
items.late = { 20, "INVTYPE_HEAD", 500 }
fire("GET_ITEM_INFO_RECEIVED", 1, true)
same(2, 2, marks())
-- Worn gear whose data is missing: the coin still, no arrow.
gear = { [1] = "unknown" }
same(1, nil, window({ { "helm", 1, true }, { "potion", 1, true } }))
-- A choice that is not an item (no link): nothing.
same(nil, nil, window({ { "helm", 1, true }, { nil, 1, true } }))

-- The setting: off removes the marks at once, on brings them back; off, a window does nothing.
gear = { [1] = "oldHelm" }
same(1, 1, window({ { "helm", 1, true }, { "potion", 1, true } }))
assert(ns.db.rewardMarks == true)
cmd("set rewardMarks off")
same(nil, nil, marks())
cmd("set rewardMarks on")
same(1, 1, marks())
cmd("set rewardMarks off")
same(nil, nil, window({ { "helm", 1, true }, { "potion", 1, true } }))
cmd("set rewardMarks on")

-- Closing the window hides the marks, and events after that do nothing.
same(1, 1, window({ { "helm", 1, true }, { "potion", 1, true } }))
fire("QUEST_FINISHED")
same(nil, nil, marks())
choices = {}
GetNumQuestChoices = function()
    error("asked with no reward window open")
end
fire("GET_ITEM_INFO_RECEIVED", 1, true)
fire("PLAYER_EQUIPMENT_CHANGED", 1)
fire("QUEST_FINISHED")
assert(#T.timers == 0 and #T.frames == made + 2)
print("ALL OK")
