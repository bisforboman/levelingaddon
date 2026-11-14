-- Luacheck settings for the addon's Lua. The game runs Lua 5.1.
std = "lua51"
max_line_length = 120

-- Not addon source: QuestieDB's checkout (data/raw) and the generated tables (data/lua).
exclude_files = { "data/" }

-- Methods and event handlers often leave `self` unused.
ignore = { "212/self" }

-- Names the game client provides. Add each API the addon starts to use, so that a misspelt
-- name is still reported as an undefined global.
read_globals = {
    "CreateFrame",
    "UIParent",
    "C_Timer",
    "C_Map",
    "C_QuestLog",
    "GetLocale",
    "UnitLevel",
    "UnitFactionGroup",
    "UnitRace",
    "UnitClass",
    "format",
    "strsplit",
    "tinsert",
    "wipe",
    "bit",
}
