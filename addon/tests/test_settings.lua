-- The settings page and its registration point, the lock, the dungeon pause mark, and the
-- window redrawing only the rows that changed.
-- From the repository root: lua5.1 addon/tests/test_settings.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick, cmd = T.ns, T.fire, T.tick, T.cmd

-- A fake of the game's Settings API that records what the addon puts on its page.
local page = { controls = {} }
local function control(kind, setting, extra)
    local c = { kind = kind, setting = setting, options = extra }
    page.controls[#page.controls + 1] = c
    return c
end
Settings = {
    RegisterVerticalLayoutCategory = function(name)
        page.name = name
        local category = {
            GetID = function()
                return 7
            end,
        }
        local layout = {
            AddInitializer = function(_, button)
                page.controls[#page.controls + 1] = button
            end,
        }
        return category, layout
    end,
    RegisterProxySetting = function(_, variable, varType, name, default, get, set)
        return { variable = variable, varType = varType, name = name, default = default, get = get, set = set }
    end,
    CreateSliderOptions = function(min, max, step)
        return { min = min, max = max, step = step, SetLabelFormatter = function() end }
    end,
    CreateSlider = function(_, setting, options)
        return control("slider", setting, options)
    end,
    CreateCheckbox = function(_, setting)
        return control("checkbox", setting)
    end,
    RegisterAddOnCategory = function()
        page.registered = true
    end,
    OpenToCategory = function(id)
        page.opened = id
    end,
}
function CreateSettingsButtonInitializer(_, text, func)
    return { kind = "button", text = text, func = func }
end
local inInstance = false
function IsInInstance()
    return inInstance
end

T.load()

-- A feature adds a switch and a slider from its own file, at file scope.
local greeted
ns.defaults.greet = true
ns.defaults.volume = 5
ns.AddSetting({
    key = "greet",
    label = "Greet at login",
    onChange = function(value)
        greeted = value
    end,
})
ns.AddSetting({ key = "volume", label = "Volume", min = 0, max = 10, step = 1 })

ns.Steps.list = dofile("addon/tests/northshire.lua") -- a fixed route; no quest data, no planner
T.login()
local W = ns.Window
local refreshes = 0
local refresh = ns.Refresh
ns.Refresh = function()
    refreshes = refreshes + 1
    refresh()
end

local function find(name)
    for _, c in ipairs(page.controls) do
        if (c.setting and c.setting.name or c.text) == name then
            return c
        end
    end
end

-- The page holds the owner's list with the game's controls, then what features added.
assert(page.registered and page.name == "Leveling Addon")
for name, kind in pairs({
    ["Scale"] = "slider",
    ["Background opacity"] = "slider",
    ["Steps in view"] = "slider",
    ["Arrow"] = "checkbox",
    ["Map pin"] = "checkbox",
    ["Dim in combat"] = "checkbox",
    ["Lock position"] = "checkbox",
    ["Reset position"] = "button",
    ["Greet at login"] = "checkbox",
    ["Volume"] = "slider",
}) do
    assert(find(name) and find(name).kind == kind, name)
end
assert(page.controls[#page.controls].setting.name == "Volume", "features come after, in the order added")
assert(find("Steps in view").options.min == 3 and find("Steps in view").options.max == 16)
assert(find("Map pin").setting.get() == true and ns.db.pin == true)

-- A control changes the saved value and applies it at once: through ns.Refresh, or through
-- the feature's own callback.
local function rowsShown()
    local n = 0
    for _, r in ipairs(W.rows) do
        n = n + (r.shown and 1 or 0)
    end
    return n
end
assert(rowsShown() == 8)
find("Steps in view").setting.set(5)
assert(ns.db.rows == 5 and rowsShown() == 5 and refreshes == 1)
find("Greet at login").setting.set(false)
assert(ns.db.greet == false and greeted == false and refreshes == 1, "onChange replaces ns.Refresh")
local opacity
W.background.SetColorTexture = function(_, _, _, _, a)
    opacity = a
end
find("Background opacity").setting.set(0.3)
assert(math.abs(opacity - 0.3) < 1e-9)
find("Arrow").setting.set(false)
assert(not ns.Arrow.frame.shown)
find("Arrow").setting.set(true)
assert(ns.Arrow.frame.shown)

-- The page reads the saved value, so a slash command shows up on it.
cmd("scale 1.5")
assert(find("Scale").setting.get() == 1.5)

-- /lvl set: the same settings without the page.
cmd("set volume 99")
assert(ns.db.volume == 10, "kept within the range")
cmd("set rows 6.4")
assert(ns.db.rows == 6, "kept on the slider's steps")
cmd("set volume loud")
assert(ns.db.volume == 10)
cmd("set greet on")
assert(ns.db.greet == true and greeted == true)
cmd("set greet")
assert(ns.db.greet == false)
cmd("set")
assert(T.chat[#T.chat]:match("volume 10") and T.chat[#T.chat]:match("locked false"))

cmd("settings")
assert(page.opened == 7)

-- Lock: a locked window does not start moving, from the setting or from /lvl lock.
local moves, saved = 0, 0
W.frame.StartMoving = function()
    moves = moves + 1
end
W.frame.StopMovingOrSizing = function()
    saved = saved + 1
end
local function drag()
    W.header.scripts.OnDragStart()
    W.header.scripts.OnDragStop()
end
assert(not W.rows[3].scripts.OnDragStart, "a row is not a handle")
W.frame.scripts.OnDragStart()
W.frame.scripts.OnDragStop()
assert(moves == 0, "nor is the list itself, outside a dungeon")
drag()
assert(moves == 1 and saved == 1 and ns.db.point, "unlocked: dragging moves the window and saves the place")
cmd("lock")
assert(ns.db.locked == true and find("Lock position").setting.get() == true)
drag()
assert(moves == 1 and saved == 1, "locked: no move")
find("Lock position").setting.set(false)
drag()
assert(moves == 2 and saved == 2)

-- Reset position: the button does what /lvl reset does, for the window and the arrow (#76).
ns.db.arrowPoint = { 300, 450 }
find("Reset position").func()
assert(ns.db.point == nil and ns.db.arrowPoint == nil)

-- Combat dimming can be switched off: the window then stays as it is in combat.
cmd("set rows 8")
W.frame.scripts.OnEvent(nil, "PLAYER_REGEN_DISABLED")
assert(rowsShown() == 1 and W.frame.alpha == 0.4)
find("Dim in combat").setting.set(false)
assert(rowsShown() == 8 and W.frame.alpha == 1, "applies at once, in combat")
W.frame.scripts.OnEvent(nil, "PLAYER_REGEN_ENABLED")
find("Dim in combat").setting.set(true)

-- Only rows whose content changed are redrawn, and row frames are reused.
local draws = {}
for slot, r in ipairs(W.rows) do
    r.name.SetText = function(self, text)
        draws[#draws + 1] = slot
        self.text = text
    end
end
local frames = #T.frames
ns.Refresh()
assert(#draws == 0, "nothing changed: nothing redrawn")
T.log[783] = {}
fire("QUEST_ACCEPTED", 783) -- step 1 done: the list slides up, and the top row stays empty
assert(#draws == 7)
T.completed[783] = true
T.log[7] = { need = 10, have = 0 }
T.log[33] = { need = 8, have = 0 }
fire("QUEST_LOG_UPDATE") -- current step is now 5, in the third row
draws = {}
T.log[7].have = 4
fire("QUEST_LOG_UPDATE") -- step 6, in the fourth row, gains a count
assert(#draws == 1 and draws[1] == 4 and W.rows[4].count.text == "4/10", table.concat(draws, " "))
draws = {}
W.frame.scripts.OnMouseWheel(nil, -1)
W.frame.scripts.OnMouseWheel(nil, 1)
cmd("set rows 4")
cmd("set rows 8")
assert(#T.frames == frames, "scrolling and resizing create no frames")

-- A dungeon: the window shrinks to the pause mark and says so once; outside it comes back.
inInstance = true
local lines = #T.chat
fire("PLAYER_ENTERING_WORLD")
assert(W.pause.shown and rowsShown() == 0 and W.frame.shown and #T.chat == lines + 1)
fire("PLAYER_ENTERING_WORLD")
assert(#T.chat == lines + 1)
assert(not T.looping() or (tick() or true), "the pointer check has nothing to do while paused")
inInstance = false
fire("PLAYER_ENTERING_WORLD")
assert(not W.pause.shown and rowsShown() == 8)

-- Without the game's Settings API there is no page, and the commands still work.
Settings = nil
local T2 = dofile("addon/tests/stub.lua")
T2.load()
T2.login()
T2.cmd("settings")
assert(T2.chat[#T2.chat]:match("/lvl set"))
T2.cmd("set locked on")
assert(T2.ns.db.locked == true)

-- An API that differs from the one built against leaves the addon working, without a page.
Settings = {
    RegisterVerticalLayoutCategory = function()
        error("different client")
    end,
    RegisterProxySetting = function() end,
}
local T3 = dofile("addon/tests/stub.lua")
T3.load()
T3.login()
T3.cmd("settings")
assert(T3.chat[#T3.chat]:match("/lvl set") and T3.ns.Window.frame.shown)
print("ALL OK")
