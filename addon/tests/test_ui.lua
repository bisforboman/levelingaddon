-- The guide window and the arrow on a fixed route (northshire.lua, with no quest data loaded, so
-- the planner leaves the list alone): quest-log tracking, skip, scroll back,
-- restore, combat folding, arrow maths, TomTom hand-off.
-- From the repository root: lua5.1 addon/tests/test_ui.lua
local T = dofile("addon/tests/stub.lua")
local ns, fire, tick, cmd = T.ns, T.fire, T.tick, T.cmd
local log, completed = T.log, T.completed
T.load()
ns.Steps.list = dofile("addon/tests/northshire.lua")
T.login()
local W, S, A = ns.Window, ns.Steps, ns.Arrow
local function view()
    local out = {}
    for _, r in ipairs(W.rows) do
        if r.shown then
            local mark = r.status == "done" and "v" or r.status == "skipped" and "x" or ""
            out[#out + 1] = r.step and (r.index .. mark .. (r.bar.shown and "*" or "")) or "-"
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
-- A skip is for the whole quest, so its turn-in (step 9) is crossed out as well.
local wolf = rowFor(5)
-- The header: up while the pointer is on the list or on the header itself, never when locked.
assert(not W.header.shown, "no header while playing")
W.frame.over = true
tick()
assert(W.header.shown, "the pointer on the list brings the header")
W.frame.over = false
W.header.over = true
tick()
assert(W.header.shown, "it stays under the pointer")
W.header.over = false
tick()
assert(not W.header.shown, "and goes when the pointer leaves")
ns.db.locked = true
W.frame.over = true
tick()
assert(not W.header.shown, "a locked window has no header")
ns.db.locked = false
W.frame.over = false
tick()

W.frame.over = true
wolf.over = true
tick()
assert(wolf.skip.shown and not wolf.restore.shown, "a pending row offers skip")
-- With the pointer on the skip button itself, the skip is previewed: the step and its quest's
-- turn-in are crossed out already. Moving off the button takes the preview away.
assert(not wolf.strike.shown and not wolf.preview)
wolf.skip.over = true
tick()
assert(wolf.strike.shown and wolf.alpha == 0.8, "the hovered skip is previewed")
assert(rowFor(9).strike.shown and not rowFor(6).strike.shown, "the preview covers the whole quest, and only it")
assert(S:Status(5) == "pending", "a preview skips nothing")
wolf.skip.over = false
tick()
assert(not wolf.strike.shown and not rowFor(9).strike.shown and wolf.alpha == 1, "the preview goes with the pointer")
wolf.skip.over = true
tick()
wolf.skip.scripts.OnClick()
print("skip wolves  ", view())
wolf.skip.over = false
tick()
assert(W.previewQuest == nil and rowFor(5).strike.shown, "after the click the line is the skip's own")
assert(view() == "4v 5x 6* 7 8 9x 10 11", view())
assert(ns.char.skipped[33] and ns.db.skipped == nil, "skips are kept per quest and per character")
W.frame.over = false
wolf.over = false

progress(7, 9)
assert(S:CurrentIndex() == 6 and S:Progress(6) == 9)
progress(7, 1)
print("kobolds done ", view())
assert(S:Status(6) == "done" and view() == "5x 6v 7* 8 9x 10 11 12", view())

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
tick()
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
T.now = T.now + 6
tick()
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
A.turn = nil -- the loop has drawn this angle already; draw it again for the test
A:Update()
print("arrow        ", A.distance.text, string.format("turn %.2f rad", turnSet))
assert(A.distance.text == "30 yd" and math.abs(turnSet - math.pi / 2) < 0.08)
T.facing = math.pi / 2
A:Update()
assert(math.abs(turnSet) < 0.08, "facing west: straight ahead")
turnSet = nil
T.facing = T.facing + 0.005
A:Update()
assert(turnSet == nil, "a turn too small to see does not redraw the arrow")
T.px, T.py = 0.462, 0.465
A:Update()
assert(A.distance.text == "" and not A.texture.shown, "arrived")
local position = UnitPosition
function UnitPosition() end
A:Update()
assert(A.frame.alpha == 0, "no position: nothing drawn")
UnitPosition = position

-- Settings.
cmd("rows 5")
assert(#view():gsub("[^ ]", "") == 4)
cmd("hide")
assert(not W.frame.shown and not A.frame.shown)
cmd("")
assert(W.frame.shown)
S:Skip(5)
cmd("unskip 33")
assert(S:Status(5) == "pending" and S:Status(9) == "pending")
S:Skip(5)
S:Skip(8)
assert(S:Status(8) == "skipped" and S:Status(11) == "skipped")
cmd("unskip all")
assert(S:Status(5) == "pending" and S:Status(8) == "pending")

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
