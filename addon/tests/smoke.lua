-- Smoke test for the addon outside the game: lua5.1 addon/tests/smoke.lua addon/LevelingAddon
-- It loads the addon files against a stub of the game API and walks the sample route:
-- quest-log tracking, skip, scroll back, restore, combat folding, arrow maths, TomTom hand-off.
-- Stub of the game API: every widget method exists and returns something harmless.
local now = 0
local function widget()
    local w = { scripts = {}, shown = true, h = 20, alpha = 1 }
    return setmetatable(w, {
        __index = function(t, k)
            if k == "SetScript" then
                return function(self, n, f)
                    self.scripts[n] = f
                end
            end
            if k == "SetHeight" then
                return function(self, v)
                    self.h = v
                end
            end
            if k == "GetHeight" then
                return function(self)
                    return self.h
                end
            end
            if k == "SetShown" then
                return function(self, v)
                    self.shown = v and true or false
                end
            end
            if k == "Show" then
                return function(self)
                    self.shown = true
                end
            end
            if k == "Hide" then
                return function(self)
                    self.shown = false
                end
            end
            if k == "IsShown" then
                return function(self)
                    return self.shown
                end
            end
            if k == "SetAlpha" then
                return function(self, v)
                    self.alpha = v
                end
            end
            if k == "GetAlpha" then
                return function(self)
                    return self.alpha
                end
            end
            if k == "SetText" then
                return function(self, v)
                    self.text = v
                end
            end
            if k == "IsMouseOver" then
                return function(self)
                    return self.over or false
                end
            end
            if k == "GetStringWidth" then
                return function()
                    return 80
                end
            end
            if k == "GetPoint" then
                return function()
                    return "TOPRIGHT", nil, "TOPRIGHT", -10, -20
                end
            end
            if k == "CreateTexture" or k == "CreateFontString" then
                return function()
                    return widget()
                end
            end
            if k == "IsOwned" then
                return function()
                    return false
                end
            end
            if type(k) == "string" and k:match("^%u") then
                return function() end
            end
        end,
    })
end
local frames = {}
function CreateFrame(kind, name)
    local f = widget()
    f.kind = kind
    f.name = name
    frames[#frames + 1] = f
    return f
end
UIParent = widget()
GameTooltip = widget()
SlashCmdList = {}
function print(...)
    io.write("  chat: ", table.concat({ ... }, " "), "\n")
end
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
function strtrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
function strsplit(sep, s, n)
    local a, b = s:match("^([^" .. sep .. "]*)" .. sep .. "?(.*)$")
    return a, b ~= "" and b or nil
end
function GetTime()
    return now
end
local combat = false
function InCombatLockdown()
    return combat
end
local facing = 0
function GetPlayerFacing()
    return facing
end
function CreateVector2D(x, y)
    return {
        x = x,
        y = y,
        GetXY = function(s)
            return s.x, s.y
        end,
    }
end
-- A 1000 x 1000 yard map; world x runs north, world y runs west, as in the game.
local px, py = 0.492, 0.463
C_Map = {
    GetBestMapForUnit = function()
        return 1429
    end,
    GetPlayerMapPosition = function()
        return CreateVector2D(px, py)
    end,
    GetWorldPosFromMapPos = function(_, v)
        return 0, { x = -v.y * 1000, y = -v.x * 1000 }
    end,
}
-- A fake quest log the test drives: quests in the log with their objective count, and quests
-- already handed in.
local log, completed = {}, {}
C_QuestLog = {
    IsOnQuest = function(q)
        return log[q] ~= nil
    end,
    IsQuestFlaggedCompleted = function(q)
        return completed[q] == true
    end,
    GetQuestObjectives = function(q)
        local o = log[q]
        if not o or not o.need then
            return o and {} or nil
        end
        return { { finished = o.have >= o.need, numFulfilled = o.have, numRequired = o.need } }
    end,
}
local timers = {}
C_Timer = {
    After = function(_, f)
        timers[#timers + 1] = f
    end,
}

local ns = {}
for _, f in ipairs({ "Core", "Steps", "Window", "Arrow" }) do
    assert(loadfile(arg[1] .. "/" .. f .. ".lua"))("LevelingAddon", ns)
end
local events
for _, f in ipairs(frames) do
    if f.scripts.OnEvent then
        events = f
        break
    end
end
local function fire(event, a)
    events.scripts.OnEvent(events, event, a)
    local run = timers
    timers = {}
    for _, f in ipairs(run) do
        f()
    end
end
fire("ADDON_LOADED", "Other")
fire("ADDON_LOADED", "LevelingAddon")
fire("PLAYER_LOGIN")
local W, S, A = ns.Window, ns.Steps, ns.Arrow
local function view()
    local out = {}
    for _, r in ipairs(W.rows) do
        if r.shown then
            local mark = r.status == "done" and "v" or r.status == "skipped" and "x" or ""
            out[#out + 1] = r.step and (r.index .. mark .. (r.band.shown and "*" or "")) or "-"
        end
    end
    return table.concat(out, " ")
end
local function cmd(c)
    SlashCmdList.LEVELINGADDON(c)
end
-- What the game would do.
local function accept(q, need)
    log[q] = { need = need, have = 0 }
    fire("QUEST_ACCEPTED", q)
end
local function progress(q, n)
    log[q].have = log[q].have + n
    fire("QUEST_LOG_UPDATE")
end
local function turnIn(q)
    log[q] = nil
    fire("QUEST_REMOVED", q)
    fire("QUEST_TURNED_IN", q) -- the completed flag is not set yet: the addon must not wait for it
    completed[q] = true
end
local function rowFor(index)
    for _, r in ipairs(W.rows) do
        if r.index == index then
            return r
        end
    end
end

print("start        ", view())
assert(view() == "- - 1* 2 3 4 5 6", view())

-- Accepting and handing in quests moves the list by itself.
accept(783)
assert(S:CurrentIndex() == 2, "accepting A Threat Within finishes step 1")
turnIn(783)
accept(7, 10)
accept(33, 8)
print("three quests ", view())
assert(S:CurrentIndex() == 5 and view() == "3v 4v 5* 6 7 8 9 10", view())

-- Counts come from the quest log.
progress(33, 3)
assert(S:Progress(5) == 3 and rowFor(5).count.text == "3/8")

-- The player skips the wolves: the step stays, crossed out, and the kobolds become current.
local wolf = rowFor(5)
W.frame.over = true
wolf.over = true
W.frame.scripts.OnUpdate(nil, 0.1)
assert(wolf.skip.shown and not wolf.restore.shown, "a pending row offers skip")
wolf.skip.scripts.OnClick()
print("skip wolves  ", view())
assert(view() == "4v 5x 6* 7 8 9 10 11", view())
W.frame.over = false
wolf.over = false

progress(7, 9)
assert(S:CurrentIndex() == 6 and S:Progress(6) == 9)
progress(7, 1)
print("kobolds done ", view())
assert(S:Status(6) == "done" and view() == "5x 6v 7* 8 9 10 11 12", view())

-- Finishing a skipped step in the game anyway marks it done: the game's word wins.
progress(33, 5)
assert(S:Status(5) == "done")
log[33].have = 3
fire("QUEST_LOG_UPDATE")
assert(S:Status(5) == "skipped")

-- Scroll back and bring the skipped step back.
for _ = 1, 6 do
    W.frame.scripts.OnMouseWheel(nil, 1)
end
print("scrolled back", view())
assert(view():match("^1v 2v"), view())
wolf = rowFor(5)
W.frame.over = true
wolf.over = true
W.frame.scripts.OnUpdate(nil, 0.1)
assert(wolf.restore.shown and not wolf.skip.shown, "a skipped row offers restore")
wolf.restore.scripts.OnClick()
print("restored     ", view())
assert(S:CurrentIndex() == 5 and view() == "3v 4v 5* 6v 7 8 9 10", view())
for _, r in ipairs(W.rows) do
    r.over = false
end
W.frame.over = false

-- A scrolled list returns by itself.
W.frame.scripts.OnMouseWheel(nil, -1)
assert(W.scroll == 1)
now = now + 6
W.frame.scripts.OnUpdate(nil, 0.1)
assert(W.scroll == 0)

-- Combat folds the window to the current row.
W.frame.scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
print("combat       ", view())
assert(view() == "5*")
W.frame.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
assert(view() == "3v 4v 5* 6v 7 8 9 10")

-- Arrow: step 5 is the wolves at 46.2, 46.5; the player stands at 49.2, 46.3 facing north, so
-- the target is 30 yards due west: a quarter turn counter-clockwise.
local turnSet
A.texture.SetRotation = function(_, v)
    turnSet = v
end
A:Update()
print("arrow        ", A.distance.text, string.format("turn %.2f rad", turnSet))
assert(A.distance.text == "30 yd" and math.abs(turnSet - math.pi / 2) < 0.08)
facing = math.pi / 2
A:Update()
assert(math.abs(turnSet) < 0.08, "facing west: straight ahead")
px, py = 0.462, 0.465
A:Update()
assert(A.distance.text == "" and not A.texture.shown, "arrived")
local position = C_Map.GetPlayerMapPosition
C_Map.GetPlayerMapPosition = function()
    return nil
end
A:Update()
assert(A.frame.alpha == 0, "no position: nothing drawn")
C_Map.GetPlayerMapPosition = position

-- Settings.
cmd("rows 5")
assert(#view():gsub("[^ ]", "") == 4)
cmd("hide")
assert(not W.frame.shown and not A.frame.shown)
cmd("")
assert(W.frame.shown)
S:Skip(5)
cmd("unskip")
assert(S:Status(5) == "pending")

-- TomTom takes the waypoint and follows the current step.
local added, removed = 0, 0
TomTom = {
    AddWaypoint = function(_, m, x, _, o)
        added = added + 1
        assert(m == 1429 and x < 1 and o.title)
        return added
    end,
    RemoveWaypoint = function()
        removed = removed + 1
    end,
}
ns.Refresh()
assert(added == 1 and not A.frame.shown)
progress(33, 5)
assert(added == 2 and removed == 1 and S:CurrentIndex() == 7)

-- Hand everything in: the route ends and nothing points anywhere.
for _, q in ipairs({ 7, 33, 15, 18, 21 }) do
    completed[q] = true
end
fire("QUEST_LOG_UPDATE")
print("route done   ", view())
assert(S:CurrentIndex() == nil)
print("ALL OK")
