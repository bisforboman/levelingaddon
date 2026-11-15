-- A fixed route for tests: the first stretch of Northshire (human start), quest ids 783, 7, 33,
-- 15, 18, 21, with positions from data/parsed. It was the addon's sample route before the
-- planner; a test puts it in ns.Steps.list and loads no quest data, so no pass replaces it.
local ELWYNN = 1429

local function step(kind, name, need, questID, x, y)
    return { kind = kind, name = name, need = need, questID = questID, map = ELWYNN, x = x, y = y }
end

return {
    step("accept", "Deputy Willem", nil, 783, 48.2, 42.9),
    step("turnin", "Marshal McBride", nil, 783, 48.9, 41.6),
    step("accept", "Marshal McBride", nil, 7, 48.9, 41.6),
    step("accept", "Eagan Peltskinner", nil, 33, 48.9, 40.2),
    step("loot", "Tough Wolf Meat", 8, 33, 46.2, 46.5),
    step("kill", "Kobold Vermin", 10, 7, 49.2, 36.3),
    step("turnin", "Marshal McBride", nil, 7, 48.9, 41.6),
    step("accept", "Marshal McBride", nil, 15, 48.9, 41.6),
    step("turnin", "Eagan Peltskinner", nil, 33, 48.9, 40.2),
    step("accept", "Deputy Willem", nil, 18, 48.2, 42.9),
    step("kill", "Kobold Worker", 10, 15, 48.9, 34.6),
    step("loot", "Red Burlap Bandana", 12, 18, 54.2, 47.3),
    step("turnin", "Deputy Willem", nil, 18, 48.2, 42.9),
    step("turnin", "Marshal McBride", nil, 15, 48.9, 41.6),
    step("accept", "Marshal McBride", nil, 21, 48.9, 41.6),
    step("kill", "Kobold Laborer", 12, 21, 48.9, 28.3),
    step("turnin", "Marshal McBride", nil, 21, 48.9, 41.6),
}
