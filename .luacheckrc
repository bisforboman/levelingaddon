-- Luacheck settings for the addon's Lua. The game runs Lua 5.1.
std = "lua51"
max_line_length = 120

-- Not addon source: QuestieDB's checkout (data/raw), the generated tables (data/lua), and the
-- test that stubs the game API (addon/tests).
exclude_files = { "data/", "addon/tests/" }

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
    "strtrim",
    "GetTime",
    "InCombatLockdown",
    "GetPlayerFacing",
    "CreateVector2D",
    "GameTooltip",
    "TomTom",
    "debugprofilestop",
    "UpdateAddOnMemoryUsage",
    "GetAddOnMemoryUsage",
    "GetUnitSpeed",
}

-- Names the addon defines for the game to find: saved settings, the slash command, and the
-- function the TOC names for the addon list by the minimap.
globals = {
    "SlashCmdList",
    "LevelingAddonDB",
    "LevelingAddonCharDB",
    "SLASH_LEVELINGADDON1",
    "LevelingAddon_OnCompartmentClick",
}
