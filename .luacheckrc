-- Luacheck settings for the addon's Lua. The game runs Lua 5.1.
std = "lua51"
max_line_length = 120

-- Not addon source: QuestieDB's checkout (data/raw), the generated tables (data/lua), and the
-- tests that stub the game API (addon/tests).
exclude_files = { "data/", "addon/tests/", "addon/LevelingAddon/Data/" }

-- Methods and event handlers often leave `self` unused.
ignore = { "212/self" }

-- Names the game client provides, one per line in alphabetical order. The list is seeded with
-- what the planned features are expected to need; add any other API the addon starts to use in
-- its sorted place, so that a misspelt name is still reported as an undefined global.
read_globals = {
    "bit",
    "C_AddOns",
    "C_ChatInfo",
    "C_Container",
    "C_GossipInfo",
    "C_Item",
    "C_Map",
    "C_QuestLog",
    "C_Reputation",
    "C_TaxiMap",
    "C_Timer",
    "ChatFontNormal",
    "CreateFrame",
    "CreateSettingsButtonInitializer",
    "CreateVector2D",
    "debugprofilestop",
    "EventRegistry",
    "format",
    "GameTooltip",
    "GetAddOnMemoryUsage",
    "GetBindLocation",
    "GetBuildInfo",
    "GetCVar",
    "GetFactionInfoByID",
    "GetItemInfo",
    "GetLocale",
    "GetMinimapShape",
    "GetMirrorTimerProgress",
    "GetMoney",
    "GetNumGroupMembers",
    "GetNumQuestLogEntries",
    "GetPlayerFacing",
    "GetProfessionInfo",
    "GetProfessions",
    "GetQuestLogPushable",
    "GetQuestLogSelection",
    "GetQuestLogTitle",
    "GetQuestsCompleted",
    "GetRealZoneText",
    "GetSubZoneText",
    "GetTime",
    "GetUnitSpeed",
    "GetZoneText",
    "hooksecurefunc",
    "InCombatLockdown",
    "IsIndoors",
    "IsInGroup",
    "IsInGuild",
    "IsInInstance",
    "MAX_QUESTS",
    "MinimalSliderWithSteppersMixin",
    "Minimap",
    "PlaySound",
    "QuestLogPushQuest",
    "RequestTimePlayed",
    "SelectQuestLogEntry",
    "SendChatMessage",
    "Settings",
    "SOUNDKIT",
    "strsplit",
    "strtrim",
    "tinsert",
    "TomTom",
    "UIParent",
    "UnitClass",
    "UnitFactionGroup",
    "UnitLevel",
    "UnitOnTaxi",
    "UnitPosition",
    "UnitRace",
    "UnitXP",
    "UnitXPMax",
    "UpdateAddOnMemoryUsage",
    "wipe",
    "WorldMapFrame",
}

-- Names the addon defines for the game to find: saved settings, the slash command, and the
-- function the TOC names for the addon list by the minimap.
globals = {
    "SlashCmdList",
    "LevelingAddonDB",
    "LevelingAddonCharDB",
    "SLASH_LEVELINGADDON1",
    "LevelingAddon_OnCompartmentClick",
    "LevelingAddonEvents",
}
