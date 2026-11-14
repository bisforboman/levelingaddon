-- The item tooltip hint: one line naming a quest that still needs the item, on both ways a
-- client offers to hook an item tooltip, and nothing for finished quests or with it off.
-- From the repository root: lua5.1 addon/tests/test_hints.lua
local T = dofile("addon/tests/stub.lua")
local ns, cmd = T.ns, T.cmd

function GetItemInfo(id)
    return "Item " .. id, nil, 1, 1, 1, "", "", 20, "", 1, 0, id == 9 and 12 or 15, 0
end

-- A tooltip that records the lines added to it.
local function tooltip()
    local t = { lines = {}, hooks = {} }
    function t:AddLine(text)
        self.lines[#self.lines + 1] = text
    end
    function t:HasScript(name)
        return name == "OnTooltipSetItem"
    end
    function t:HookScript(name, fn)
        self.hooks[name] = fn
    end
    function t:GetItem()
        return "Item", self.link
    end
    return t
end
GameTooltip = tooltip()
ItemRefTooltip = tooltip()
local shopping = tooltip() -- a comparison tooltip

-- The newer way: one callback for every tooltip that shows an item.
local postCall
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        assert(kind == 0)
        postCall = fn
    end,
}

-- The quest data as the Lua export lays it out. Item 3 is linked to quest 100 twice.
ns.Data = {
    quests = {
        [100] = { name = "Wolves at the Gate", side = "alliance", objectives = { items = { { id = 3 } } } },
        [101] = { name = "A Letter Home", side = "both", requiredSourceItems = { 3 } },
        [102] = { name = "Pelts for the Warchief", side = "horde", objectives = { items = { { id = 3 }, { id = 4 } } } },
        [103] = { name = "More Pelts", side = "alliance", sourceItemId = 3 },
    },
    items = { [3] = { relatedQuests = { 100 } }, [4] = {}, [9] = {} },
}
T.load()
T.login()
assert(postCall and not GameTooltip.hooks.OnTooltipSetItem, "the newer way is used when the client has it")

local function show(itemID, tip)
    tip = tip or GameTooltip
    tip.lines = {}
    postCall(tip, { id = itemID })
    return table.concat(tip.lines, "|")
end

-- On by default. The lowest quest id is named and the rest counted; the other faction's quest
-- is not among them.
assert(ns.db.itemHint == true)
assert(show(3) == "Needed for: Wolves at the Gate and 2 more", show(3))
assert(show(3, ItemRefTooltip) == "Needed for: Wolves at the Gate and 2 more")
assert(show(3, shopping) == "", "comparison tooltips are left alone")

-- A quest in the log is named before one that is not.
T.log[103] = {}
assert(show(3) == "Needed for: More Pelts and 2 more", show(3))
T.log[103] = nil

-- Finished quests are not named, and with all of them finished there is no line.
T.completed[100] = true
assert(show(3) == "Needed for: A Letter Home and 1 more", show(3))
T.completed[101] = true
assert(show(3) == "Needed for: More Pelts", show(3))
T.completed[103] = true
assert(show(3) == "")

-- Nothing for an item only the other faction's quest needs, an item no quest needs, an item
-- the data does not know, a quest item the data cannot name a quest for, or a tooltip
-- without an item id.
assert(show(4) == "" and show(5) == "" and show(9) == "" and show(nil) == "")
assert(not ns.QuestNeedsItem(4) and ns.QuestNeedsItem(9), "junk selling: the client's word still counts")
postCall(GameTooltip, nil)

-- Off and on again, with /lvl set.
T.completed[103] = nil
cmd("set itemHint off")
assert(ns.db.itemHint == false and show(3) == "")
cmd("set itemHint")
assert(ns.db.itemHint == true and show(3) == "Needed for: More Pelts")

-- The older way: a script on each of the two tooltips, which reads the item from its link.
TooltipDataProcessor = nil
assert(loadfile("addon/LevelingAddon/Hints.lua"))("LevelingAddon", ns)
for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    tip.lines = {}
    tip.link = "|cffffffff|Hitem:3::::::::20:::::|h[Wolf Pelt]|h|r"
    tip.hooks.OnTooltipSetItem(tip)
    assert(tip.lines[1] == "Needed for: More Pelts" and #tip.lines == 1, tip.lines[1])
    tip.lines, tip.link = {}, nil -- a tooltip that does not know its item
    tip.hooks.OnTooltipSetItem(tip)
    assert(#tip.lines == 0)
end

-- A tooltip without the script (a newer client that lost the callbacks too) is not hooked.
GameTooltip = tooltip()
function GameTooltip:HasScript()
    return false
end
assert(loadfile("addon/LevelingAddon/Hints.lua"))("LevelingAddon", ns)
assert(not GameTooltip.hooks.OnTooltipSetItem)
print("ALL OK")
