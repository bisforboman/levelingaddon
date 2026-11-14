-- How the leveling is going: time, XP by source and deaths, per level and per zone, saved per
-- character. A few counters move on XP, level-up, zone and death events; nothing runs per
-- frame. A level the addon never saw has no row: it is unknown, not zero. A level it saw only
-- part of is marked partial. /lvl stats prints a summary.
local _, ns = ...

-- levels[level] and zones[zone name] are rows of { time, xp, quest, kill, deaths, partial }:
-- seconds, XP gained, the part of it from quests and from kills (the rest is exploration and
-- the like), and partial = true where the addon missed some of it. Beside them: level, xp and
-- xpMax as last seen, and played, the game's total time played once it has told us.
ns.charDefaults.tracker = { levels = {}, zones = {} }

local Tracker = {}
ns.Tracker = Tracker

local RECENT = 3 -- finished levels /lvl stats lists
local t -- ns.char.tracker
local zone -- the zone the player is in
local mark -- GetTime() up to which time has been counted
local gained, questXP, killed = 0, 0, false -- XP not yet split by source

local function row(list, key)
    if not list[key] then
        list[key] = { time = 0, xp = 0, quest = 0, kill = 0, deaths = 0 }
    end
    return list[key]
end

-- Count n on the current level and on the current zone.
local function add(key, n)
    local level, here = row(t.levels, t.level), row(t.zones, zone)
    level[key] = level[key] + n
    here[key] = here[key] + n
end

-- Whole seconds, so that the saved numbers stay short.
local function countTime()
    local now = math.floor(GetTime())
    add("time", now - mark)
    if t.played then
        t.played = t.played + now - mark
    end
    mark = now
end

-- XP arrives as a change of UnitXP. What it was for arrives in other events, in an order we do
-- not rely on: a quest's reward with QUEST_TURNED_IN, a kill as a line of combat chat. So the
-- pieces are collected and split a moment later: up to the quest's reward is the quest's, and
-- the rest is from kills if a kill was announced.
local function split()
    if gained == 0 then
        return
    end
    local quest = math.min(questXP, gained)
    add("xp", gained)
    add("quest", quest)
    if killed then
        add("kill", gained - quest)
    end
    gained, questXP, killed = 0, 0, false
    countTime() -- so that a crash loses little time
end
local splitSoon = ns.Debounce(0.3, split)

local function readXP()
    local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local delta = xp - t.xp
    if max ~= t.xpMax then
        delta = delta + t.xpMax -- a new level: the rest of the old one, and what is over
    end
    gained = gained + math.max(delta, 0)
    t.xp, t.xpMax = xp, max
    splitSoon()
end

local function where()
    local name = GetRealZoneText and GetRealZoneText()
    return name and name ~= "" and name or "?"
end

-- Seconds spent on `level`, and true if the addon saw only part of the level. Nothing if the
-- level is unknown. In a PLAYER_LEVEL_UP handler, the level just finished is the new one - 1;
-- the answer is right whether or not this file's handler has run yet.
function Tracker.LevelTime(level)
    if not t then
        return
    end
    countTime()
    local r = t.levels[level]
    if r then
        return r.time, r.partial or false
    end
end

ns.On("PLAYER_LOGIN", function()
    t = ns.char.tracker
    mark = math.floor(GetTime())
    zone = where()
    local level, xp = UnitLevel("player"), UnitXP("player") or 0
    if t.level ~= level or t.xp ~= xp then
        -- The first login with the addon, or the character moved on without it.
        if t.level then
            row(t.levels, t.level).partial = true
        end
        t.level = level
        if level > 1 or xp > 0 then
            row(t.levels, level).partial = true
        end
    end
    t.xp, t.xpMax = xp, UnitXPMax("player") or 0

    ns.On("PLAYER_XP_UPDATE", readXP)
    ns.On("QUEST_TURNED_IN", function(_, _, xpReward)
        questXP = questXP + (tonumber(xpReward) or 0)
        splitSoon()
    end)
    ns.On("CHAT_MSG_COMBAT_XP_GAIN", function()
        killed = true
        splitSoon()
    end)
    ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
        readXP()
        split()
        countTime()
        t.level = newLevel
    end)
    ns.On("ZONE_CHANGED_NEW_AREA", function()
        split()
        countTime()
        zone = where()
    end)
    ns.On("PLAYER_DEAD", function()
        add("deaths", 1)
    end)
    ns.On("PLAYER_LOGOUT", function()
        split()
        countTime()
    end)
    -- The game's own total, whenever it says it (/played); from then on we count along.
    ns.On("TIME_PLAYED_MSG", function(_, total)
        countTime()
        t.played = tonumber(total)
    end)
    if not t.played and RequestTimePlayed then
        RequestTimePlayed() -- once per character; the game prints its two lines to chat
    end
end)

local function clock(seconds)
    if seconds < 3600 then
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    end
    return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function describe(r)
    local parts = { clock(r.time) }
    if r.xp > 0 then
        if r.time > 0 then
            table.insert(parts, math.floor(r.xp * 3600 / r.time + 0.5) .. " XP an hour")
        end
        local quest, kill = math.floor(100 * r.quest / r.xp + 0.5), math.floor(100 * r.kill / r.xp + 0.5)
        table.insert(parts, quest .. "% from quests, " .. kill .. "% from kills")
    end
    table.insert(parts, r.deaths .. (r.deaths == 1 and " death" or " deaths"))
    if r.partial then
        table.insert(parts, "partial: not all of it was recorded")
    end
    return table.concat(parts, ", ")
end

-- /lvl stats: this level so far, the last few finished levels, and everything recorded.
-- /lvl stats zones: the same numbers per zone, most XP first.
ns.commands.stats = function(arg)
    split()
    countTime()
    if arg == "zones" then
        local names = {}
        for name in pairs(t.zones) do
            table.insert(names, name)
        end
        table.sort(names, function(a, b)
            return t.zones[a].xp > t.zones[b].xp
        end)
        for _, name in ipairs(names) do
            ns.say(name .. ": " .. describe(t.zones[name]))
        end
        return
    end
    ns.say("level " .. t.level .. " so far: " .. describe(row(t.levels, t.level)))
    for level = t.level - 1, math.max(t.level - RECENT, 1), -1 do
        local r = t.levels[level]
        ns.say("level " .. level .. ": " .. (r and describe(r) or "unknown, not recorded"))
    end
    local total = { time = 0, xp = 0, quest = 0, kill = 0, deaths = 0 }
    for _, r in pairs(t.levels) do
        for key in pairs(total) do
            total[key] = total[key] + r[key]
        end
    end
    ns.say("recorded in all: " .. describe(total))
    ns.say("time played: " .. (t.played and clock(t.played) or "unknown until the game says (/played)"))
end
