-- The quest item button: shown for a step whose quest has a usable item in the bags, hidden
-- without one, and never touched in combat; what changed in combat is applied when it ends.
-- From the repository root: lua5.1 addon/tests/test_itembutton.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, cmd = T.ns, T.fire, T.cmd

-- The bags and the items' use effects, as the client would report them (stub.lua).
local bags = T.bags
T.itemSpells[11], T.itemSpells[12] = "Read", "Blow"
local special = {} -- [quest id] = item id: the quest log's own item for the quest
local cooldownStart = 0
C_Container = {
    GetItemCooldown = function()
        return cooldownStart, 30, 1
    end,
}
function C_QuestLog.GetLogIndexForQuestID(questID)
    return T.log[questID] and questID + 1000
end
function GetQuestLogSpecialItemInfo(index)
    local id = special[index - 1000]
    return id and "|cffffffff|Hitem:" .. id .. "::::::::20:::::|h[Thing]|h|r"
end

-- The game refuses these on a secure frame in combat, so the test does too, and counts them.
local PROTECTED = { "Show", "Hide", "SetPoint", "ClearAllPoints", "SetAttribute", "StartMoving", "SetSize" }
local button, cooldown
local calls, attributes, cooldowns = 0, {}, 0
local createFrame = CreateFrame
function CreateFrame(kind, name, parent, template)
    local f = createFrame(kind, name, parent)
    if name == "LevelingAddonItemButton" then
        assert(not button, "the button is made once")
        assert(not T.combat, "created in combat")
        assert(template == "SecureActionButtonTemplate" and parent == UIParent)
        button = f
        for _, method in ipairs(PROTECTED) do
            local original = f[method]
            rawset(f, method, function(self, ...)
                assert(not T.combat, method .. " in combat")
                calls = calls + 1
                if method == "SetAttribute" then
                    attributes[...] = select(2, ...)
                end
                return original(self, ...)
            end)
        end
    elseif button and parent == button then
        cooldown = f
        rawset(f, "SetCooldown", function(_, start, duration)
            cooldowns = cooldowns + 1
            f.start, f.duration = start, duration
        end)
    end
    return f
end
local tooltipItem
rawset(GameTooltip, "SetItemByID", function(_, id)
    tooltipItem = id
end)

-- Quest 7 hands out item 11 to use; quest 33 wants item 750, which has no use effect, and
-- item 12, which must be held and used; quest 15 has nothing.
ns.Data = {
    quests = {
        [7] = { sourceItemId = 11 },
        [33] = { requiredSourceItems = { 12 }, objectives = { items = { { id = 750 } } } },
    },
}
T.load()
local ELWYNN = 1429
ns.Steps.list = {
    { kind = "kill", name = "Kobold Vermin", need = 10, questID = 7, map = ELWYNN, x = 49.2, y = 36.3 },
    { kind = "loot", name = "Tough Wolf Meat", need = 8, questID = 33, map = ELWYNN, x = 46.2, y = 46.5 },
    { kind = "turnin", name = "Eagan Peltskinner", questID = 33, map = ELWYNN, x = 48.9, y = 40.2 },
    { kind = "kill", name = "Kobold Worker", need = 10, questID = 15, map = ELWYNN, x = 48.9, y = 34.6 },
}
T.log[7] = { need = 10, have = 0 }
T.log[33] = { need = 8, have = 0 }
T.log[15] = { need = 10, have = 0 }
T.login()

-- On by default. The item is not in the bags yet: the button exists, beside the window's
-- starting place, and is hidden. It is its own frame, anchored to the screen.
assert(ns.db.itemButton == true)
assert(button and not button.shown)
assert(button.point[1] == "TOPRIGHT" and button.point[2] == UIParent and button.point[4] == -478)
assert(attributes.type == "item")

-- The item arrives: one look a moment after the burst of bag events, and the button shows it.
bags[11] = 1
fire("BAG_UPDATE", 0)
assert(button.shown and attributes.item == "item:11")
assert(cooldown.start == 0 and cooldown.duration == 30)

-- Nothing is touched when nothing changed.
local before = calls
fire("BAG_UPDATE", 0)
ns.Refresh()
assert(calls == before)

-- The tooltip is the item's own.
button.scripts.OnEnter(button)
assert(tooltipItem == 11 and GameTooltip.shown)
button.scripts.OnLeave(button)
assert(not GameTooltip.shown)

-- The cooldown follows the game's event, in combat as well: it is a plain child frame.
cooldownStart = 100
T.combat = true
fire("BAG_UPDATE_COOLDOWN")
assert(cooldown.start == 100)
T.combat = false

-- Used up: hidden.
bags[11] = nil
fire("BAG_UPDATE", 0)
assert(not button.shown)

-- In combat nothing about the button is changed (a call would fail the assert above): not when
-- the item comes back, not when the step changes, not for the setting or a reset. When combat
-- ends, the button is brought to what is true by then.
T.combat = true
fire("PLAYER_REGEN_DISABLED")
before = calls
bags[11] = 1
fire("BAG_UPDATE", 0)
ns.Refresh()
cmd("set itemButton off")
cmd("set itemButton on")
cmd("reset")
button.scripts.OnDragStart(button)
button.scripts.OnDragStop(button)
assert(calls == before and not button.shown and ns.db.itemButtonPoint == nil)
T.combat = false
fire("PLAYER_REGEN_ENABLED")
assert(button.shown and attributes.item == "item:11")

-- The step changes in combat: the button keeps the old item until combat ends. The next step's
-- quest has an item to hold and use.
bags[12] = 1
bags[750] = 3
T.combat = true
T.log[7].have = 10
fire("QUEST_LOG_UPDATE")
assert(ns.Steps:Current().questID == 33)
assert(button.shown and attributes.item == "item:11")
T.combat = false
fire("PLAYER_REGEN_ENABLED")
assert(button.shown and attributes.item == "item:12", attributes.item)

-- The quest log's own item for the quest comes first, with or without a use effect the client
-- admits to, as long as the character has it.
special[33] = 750
ns.Refresh()
assert(attributes.item == "item:750")
bags[750] = nil
fire("BAG_UPDATE", 0)
assert(attributes.item == "item:12")
special[33] = nil

-- An item without a use effect is not offered.
bags[12] = nil
bags[750] = 3
fire("BAG_UPDATE", 0)
assert(not button.shown)
bags[12] = 1
fire("BAG_UPDATE", 0)
assert(button.shown)

-- The setting, and hiding the addon, hide the button; both bring it back.
cmd("set itemButton off")
assert(not button.shown)
cmd("set itemButton on")
assert(button.shown)
cmd("hide")
assert(not button.shown)
cmd("show")
assert(button.shown)

-- Dragged with the right button, the place is saved; /lvl reset puts it back.
button.scripts.OnDragStart(button)
button.scripts.OnDragStop(button)
assert(ns.db.itemButtonPoint[1] == "TOPRIGHT" and ns.db.itemButtonPoint[3] == -10)
cmd("reset")
assert(ns.db.itemButtonPoint == nil and button.point[4] == -478)

-- A drag still going when combat starts is ended and saved before the game locks the button.
button.scripts.OnDragStart(button)
fire("PLAYER_REGEN_DISABLED")
T.combat = true
assert(ns.db.itemButtonPoint[3] == -10)
button.scripts.OnDragStop(button)
T.combat = false
fire("PLAYER_REGEN_ENABLED")
cmd("reset")

-- A hand-in has nothing left to use, and a quest without items never had.
T.log[33].have = 8
fire("QUEST_LOG_UPDATE")
assert(ns.Steps:Current().kind == "turnin" and not button.shown)
T.completed[33], T.log[33] = true, nil
fire("QUEST_TURNED_IN", 33)
assert(ns.Steps:Current().questID == 15 and not button.shown)
print("ALL OK")
