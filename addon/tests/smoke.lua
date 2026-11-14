-- Smoke test for the addon outside the game: lua5.1 addon/tests/smoke.lua addon/LevelingAddon
-- It loads the addon files against a stub of the game API and walks the sample route:
-- skip, scroll back, restore, combat folding, arrow maths, TomTom hand-off.
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
local ns = {}
for _, f in ipairs({ "Core", "Steps", "Window", "Arrow" }) do
    assert(loadfile(arg[1] .. "/" .. f .. ".lua"))("LevelingAddon", ns)
end
local ev = frames[1].scripts.OnEvent
ev(nil, "ADDON_LOADED", "Other")
ev(nil, "ADDON_LOADED", "LevelingAddon")
ev(nil, "PLAYER_LOGIN")
local W, S, A = ns.Window, ns.Steps, ns.Arrow
local function view()
    local out = {}
    for _, r in ipairs(W.rows) do
        if r.shown then
            out[#out + 1] = (
                r.step
                    and (r.index .. (r.status == "done" and "v" or r.status == "skipped" and "x" or "") .. (r.band.shown and "*" or ""))
                or "-"
            )
        end
    end
    return table.concat(out, " ")
end
local function cmd(c)
    SlashCmdList.LEVELINGADDON(c)
end
print("start        ", view())
assert(view() == "- - 1* 2 3 4 5 6", view())
for _ = 1, 4 do
    cmd("next")
end
print("after 4 next ", view())
assert(S:CurrentIndex() == 5)
S:Skip(5)
ns.Refresh()
print("skip wolf    ", view())
assert(view() == "4v 5x 6* 7 8 9 10 11", view())
for _ = 1, 9 do
    cmd("next")
end
assert(S:Progress(6) == 9 and S:CurrentIndex() == 6)
cmd("next")
assert(S:Status(6) == "done" and S:CurrentIndex() == 7)
print("kobolds done ", view())
-- scroll back to the top, restore the skipped step
W.frame.scripts.OnMouseWheel(nil, 1)
W.frame.scripts.OnMouseWheel(nil, 1)
W.frame.scripts.OnMouseWheel(nil, 1)
W.frame.scripts.OnMouseWheel(nil, 1)
W.frame.scripts.OnMouseWheel(nil, 1)
W.frame.scripts.OnMouseWheel(nil, 1)
print("scrolled back", view())
assert(view():match("^1v 2v"), view())
local wolf
for _, r in ipairs(W.rows) do
    if r.index == 5 then
        wolf = r
    end
end
W.frame.over = true
wolf.over = true
W.frame.scripts.OnUpdate(nil, 0.1)
assert(wolf.restore.shown and not wolf.skip.shown, "restore shows on a skipped row")
wolf.restore.scripts.OnClick()
print("restored     ", view())
assert(S:CurrentIndex() == 5 and view() == "3v 4v 5* 6v 7 8 9 10", view())
-- pointer on a pending row offers skip, not restore
local r7
for _, r in ipairs(W.rows) do
    r.over = false
    if r.index == 7 then
        r7 = r
    end
end
r7.over = true
W.frame.scripts.OnUpdate(nil, 0.1)
assert(r7.skip.shown and not r7.restore.shown)
-- scroll returns by itself
W.frame.over = false
r7.over = false
W.frame.scripts.OnMouseWheel(nil, -1)
assert(W.scroll == 1)
now = now + 6
W.frame.scripts.OnUpdate(nil, 0.1)
assert(W.scroll == 0)
-- combat folds to the current row
W.frame.scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
print("combat       ", view())
assert(view() == "5*")
W.frame.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
assert(view() == "3v 4v 5* 6v 7 8 9 10")
-- arrow: step 5 is the wolves at 46.2, 46.5; the player stands at 49.2, 46.3 facing north,
-- so the target is 30 yards due west: a quarter turn counter-clockwise.
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
C_Map.GetPlayerMapPosition = function()
    return nil
end
A:Update()
assert(A.frame.alpha == 0, "no position: nothing drawn")
-- finish the route, hide, rows setting
cmd("restart")
for _ = 1, 200 do
    cmd("next")
end
assert(S:CurrentIndex() == nil)
print("route done   ", view())
assert(not A.frame.shown)
cmd("rows 5")
assert(#view():gsub("[^ ]", "") == 4)
cmd("hide")
assert(not W.frame.shown and not A.frame.shown)
cmd("")
assert(W.frame.shown)
-- TomTom takes the waypoint
cmd("restart")
local added, removed = 0, 0
TomTom = {
    AddWaypoint = function(_, m, x, y, o)
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
cmd("next")
assert(added == 2 and removed == 1)
print("ALL OK")
