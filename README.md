# levelingaddon

A leveling addon for World of Warcraft: Forever, and the collector that gathers its quest data.

## Status

| Step | State |
| --- | --- |
| Investigation of sources, robots.txt | Done (see "Sources") |
| QuestieDB → normalized JSON | Done: 5,914 quests, 0 parse failures |
| Validation report | Done: [`reports/validation.md`](reports/validation.md) |
| Polite, resumable Wowhead fetcher with raw cache | Built and tested against a local test server; not yet run against Wowhead |
| Wowhead list / quest page parsers | Not built: need a few real sample pages first |
| Class spells per level, with training cost (#17) | Fetch prepared, not yet run: see "Fetching class spells". No parser yet |
| Flight points and flight times (#16) | Done: 65 points, 286 flights, converted by `collector parse` from a second pinned source (see "Sources") |
| JSON → Lua export | Done: `collector export`, with reduced spawn lists and a per-table memory report; checked by loading the files back |

## Addon

`addon/LevelingAddon/` is a guide window and an arrow that show the next steps, not yet run in
the game. The steps are planned from what the character has done, never from a saved place in
a list (see "The planner" below). Step progress is read from the game's quest log: accepting a
quest, objective counts and handing a quest in move the list by themselves. The design of the
window and the reasons behind it are in [`docs/ui-concepts.md`](docs/ui-concepts.md).

### Building the quest data

The addon reads quest data that is built, not committed. From `tools/collector`:

```sh
dotnet run --project src/Collector -- export --out ../../addon/LevelingAddon/Data
```

That writes the Lua tables and `data.xml` into `addon/LevelingAddon/Data/` (gitignored); the
TOC loads them through its one `Data\data.xml` line. Without them the addon loads and says in
chat that it has no quest data. Then copy `addon/LevelingAddon` into the game's
`Interface/AddOns` folder. What to check in the game is listed in
[`docs/ingame-checks/`](docs/ingame-checks/).

| Command | Does |
| --- | --- |
| `/lvl` | Hide or show the window and arrow |
| `/lvl settings` | Open the addon's page in the game's settings panel |
| `/lvl set`, `/lvl set key value` | List the settings, or change one (`/lvl set opacity 0.4`, `/lvl set combatDim off`) |
| `/lvl rows N`, `/lvl scale N` | Steps in view (3 to 16), window scale (0.6 to 2) |
| `/lvl arrow` | Turn our arrow on or off |
| `/lvl lock` | Lock the window in place, or unlock it |
| `/lvl skipped` | List the quests skipped on this character |
| `/lvl unskip NUMBER`, `/lvl unskip all` | Bring one skipped quest back (by the number in the list), or all of them |
| `/lvl reset` | Put the window back where it starts |
| `/lvl debug` | Print the addon's memory use and timings (see "Writing a feature") |
| `/lvl help` | List every command, including those that features add |

In the window: drag to move, mouse wheel to scroll through the steps, the cross on a pending
step skips its quest, the arrow on a skipped step brings the quest back. A skipped quest stays
out of the suggestions, on that character only, until it is brought back.
In a dungeon the window shrinks to a pause mark.

The settings page holds every setting: scale, background opacity, steps in view, arrow, map
pin, combat dimming, lock and reset position, and after them what each feature adds (the
drowning alarm, junk selling, the four party settings, verbose output, the item hint,
automation, the dungeon and group quest switches, reward marks, the item button). Every change applies at once, with no reload and
no loss of progress (#24), and a feature's own slash command changes the same setting the same
way. A changed preference about which quests to suggest is one debounced planner pass; a pass
keeps finished steps, skipped quests and counts.

The tests in `addon/tests/` run the addon outside the game, against a stub of the game API
with a fake quest log (`stub.lua`). Run each from the repository root, for example
`lua5.1 addon/tests/test_ui.lua`. `test_ui.lua` checks tracking, skip and restore, combat
folding, the arrow's direction and distance, and the TomTom hand-off, on a fixed route
(`northshire.lua`) with no quest data loaded; `test_arrow.lua` checks the rest of the arrow on
the same route (see "The arrow"); `test_settings.lua` checks the settings page, the
lock, the pause mark and that only changed rows are redrawn; `test_settings_apply.lua` changes
every setting on the page and checks what it is for right after, and fails for a setting that
has no check in it; `test_core.lua` checks the shared
machinery below. `test_planner.lua` checks the planner on quest data cut from a real export
(`planner_data.lua`): a fresh character, a mid-level character with a half-finished zone, a
character who skipped ahead, a full quest log, skips, and the events that ask for a pass.
`test_automation.lua` checks accepting and handing in.
`test_rewards.lua` checks the reward marks.
`test_support.lua` checks the report, the events for other addons and verbose output.
`test_flights.lua` checks the flight time on the flight map, the flight timer and what is
remembered per character.
`test_steps.lua` checks that steps complete themselves: each kind on its event, a quest with
several objectives, the grace period, steps already done, and that only the steps in view are
read. They cannot check how
anything looks, or what the game client really returns; that needs the game client.

### The planner

`Planner.lua` suggests the next steps (issue #3). It keeps no position of its own. Each pass
reads the character: completed quests (read once, then kept current from `QUEST_TURNED_IN`),
the quest log and its objectives, level, class, race, faction, zone and position.

- **Eligible quests**: not completed, not in the log, right side, race and class, required
  level met and not more than 7 levels under the character, prerequisites met (any one of
  `pre`, all of `preAll`), nothing that excludes it completed or in the log (`excl`: exclusive
  quests, the quest a breadcrumb leads to, the next quest in its chain), parent quest in the
  log where there is one, skill and reputation met, not skipped, and not marked `dungeon`,
  `raid`, `group` or `pvp` unless `ns.Planner.allow[mark]` is set ("First-run setup and quest preferences" below).
- **Actions**: pick a quest up, work on an objective of a quest in the log, hand a quest in.
- **Ranking**: travel distance, XP, how well the quest's level and the zone's level range fit
  the character, how many other candidates are close by, with a small bonus for finishing what
  is started. The weights are constants at the top of the file: first guesses, to be tuned in
  the game.
- **Steps**: the pass plays the next 12 actions forward on a copy of the state, always taking
  the best-ranked one, and whatever can be done within 40 yards of where the character stands
  is done before moving on, so actions that share a place come together. Steps further down
  are a forecast and change as the character does things.
- **Quest log limit** (issue #23): a pass asks the client how many quests the log holds and
  counts the quests in it. The plan never holds more pick-ups than there are free places; with
  two or fewer free, hand-ins come before everything else, nearest first. When the log is full
  and a pick-up would otherwise have come first, one chat line says so, naming the nearest quest
  ready to hand in if there is one, or else pointing at `/lvl abandon` when that list has rows;
  it is said once, and again only when that hand-in changes or the log has had room in between. Where the client does not tell the limit, pick-ups are
  not held back. `/lvl plan` prints the count and the limit.
- **Side tasks** (issue #8): a kill or collect objective the character already has in the log
  comes right under the current step when any of its points in the data lies within 200 yards
  (`SIDE_YARDS`) of the straight line from the character to the current step; standing at the
  step, that is 200 yards around it. Several are listed nearest that line first, and the rest
  of the plan goes on from the current step. Nothing is remembered: once the objective is
  finished, or the current step has changed and the objective is no longer near the way to the
  new one, the next pass ranks it like any other step. It is an ordinary row, found in the same
  pass, and the arrow stays on the current step.
- **Working set**: the current zone, the zones whose maps overlap its map, and the 5-level band
  the character is in. Where nothing there suits the character, the best-fitting other zones
  on the continent are tried one at a time (three at most), so a character standing somewhere
  too low or too high is still pointed at something.
- **Flights** (issue #16): those other zones are ranked by how well they fit the character's
  level, and among zones that fit equally by how soon the character can be there. That time is
  the walk to the middle of the zone at 7 yards a second (`RUN_SPEED`), or, where it is
  quicker, the walk to the nearest flight point the character knows, the flight from there to
  the known flight point nearest the zone (see "Flights"), and the walk from that one. When the
  zone the steps end up in is reached soonest by flight, one chat line says so: "nothing left
  to do around here. The next steps are in Duskwood: fly from Ironforge to Darkshire (about
  4:10)." It is said once per flight. Only flights are known: boats, zeppelins and so the other
  continent are not in the data, and there is no "take this flight" step yet.
- **When**: on quest accepted, removed or handed in, a finished objective, level up, zone
  change and entering the world, folded into one pass 0.2 seconds later. Never per frame.
  `ns.Planner.Request()` asks for a pass (after a changed preference, for example). The time
  of the last pass and of the one read of completed quests show in `/lvl debug`.

First-version limits, by the owner's decision on #3: no travel links between zones other than
flights, no list of quests not worth doing, no pinning. Quests without XP in the data rank on level fit and
distance alone. A quest with no giver in the data, or a giver without coordinates, is never
offered as a pick-up; once it is in the log its objectives and hand-in are still suggested.
Repeatable quests and world-event quests are not offered either: the first never count as
completed and the second are not always there.

"Neighbours" are worked out in the game, once per zone, from the client's own map rectangles
(`C_Map.GetWorldPosFromMapPos` on three corners of each zone map): the data has no adjacency,
only `parentZoneId`, and the same rectangles give distances across zone borders.

The steps are `ns.Steps.list`, rows of `{ kind, name, need, questID, objective, map, x, y }`
(`Steps.lua` describes each field), read through `ns.Steps:Current()`, `Count()`,
`Status(index)` and `Progress(index)`, and redrawn by `ns.Refresh()`. Finished steps and the
step a skip was made on stay above the plan as history.

### Steps that complete themselves

`Steps.lua` reads each step's state from the game (issue #7); the player never marks anything.
One table, `KINDS`, has an entry per kind of step: the game events that can finish or undo it,
and one function that reads the character's real state.

| Kind | Done when | Events |
| --- | --- | --- |
| `accept` | the quest is in the log, or handed in | `QUEST_ACCEPTED`, `QUEST_REMOVED` |
| `turnin` | the quest is flagged completed | `QUEST_TURNED_IN` |
| `kill`, `loot` | the row's own objective (`row.objective`) is finished in the quest log, which also gives the count; or the quest is handed in | `QUEST_LOG_UPDATE` |
| `go` | the row's objective is finished in the quest log, or the character has stood within `ns.Steps.ARRIVE_YARDS` (8) of the point with the quest in the log | `QUEST_LOG_UPDATE`, and the position twice a second |

- **Only the steps in view are followed**: the two rows above the current step and as many
  rows as the window has. `Steps.lua` acts only on the events of their kinds, and a check, 0.2
  seconds later, reads those steps alone. A planner pass reads its whole list once.
- **Already done**: when a step finishes, the steps that come into view are read at once, so
  whatever the character has already done is ticked the moment it is shown.
- **Grace period**: for 3 seconds after `QUEST_ACCEPTED` or `QUEST_TURNED_IN` the event is
  taken at its word, because the quest log and the completed flag follow a moment later.
  After that only the game's own state counts.
- **A reached point stays reached** while its quest is in the log. The planner asks
  (`ns.Steps:Reached(questID, index)`) and does not suggest the point again; the quest's
  hand-in waits until the quest log calls the objective finished.
- The position is looked at on the shared loop, only while a `go` step in view is open.

Not built, by the brief for #7: the kinds for reaching a level, training, buying, setting the
hearthstone and taking a flight. The planner does not suggest them yet; each will be one entry
in `KINDS`.

### The arrow

`Arrow.lua` points at the current step (issue #5), or hands the waypoint to TomTom when that is
installed.

- **Several places**: a planner step carries one point, but the thing to find often has many.
  When a step becomes current the arrow looks the step's name up among what the quest names in
  the plain tables (`quests`, then `npcs`, `objects`, `items`: the quest's givers and takers,
  its creatures and objects, and for an item whatever drops or sells it), takes their spawn
  points on the step's map, and converts them to world coordinates once, with the client's
  `C_Map.GetWorldPosFromMapPos`. It points at the nearest. With no match in the data it uses
  the step's own point.
- **Reached**: a kill or collect step with several places counts a place as reached within 30
  yards and moves on to the next nearest, round and round. Any other step is arrived at within
  8 yards (30 for a kill or collect step with one place): the arrow becomes a ring until the
  step completes.
- **Dead**: a ghost is pointed to the corpse.
- **Another continent**: the step has no direction from here, so the frame shows the name of
  its zone and of the continent under it instead, both from the client (`C_Map.GetMapInfo`),
  and grows to fit them. Decided by the owner on 2026-11-14; pointing at the flight point that
  leads there is to follow, once the flight data offers one. In an instance nothing is drawn.
- **For other features**: `ns.Arrow.Places(step)` returns the places the arrow walks for a
  step, as one flat list `{ x1, y1, x2, y2, ... }` of positions on `step.map`, each from 0 to
  1; never empty.
- **Cost**: ten updates a second on the shared loop: one `UnitPosition`, one `GetPlayerFacing`
  and arithmetic. The nearest place is looked for twice a second, the texture turns only for a
  change of about a degree, the distance text changes only with the number, and the task is
  off while there is nothing to point at.

### Flights

`Flights.lua` shows how long a flight takes and how much of it is left (issue #16). The client
reports no flight time, so the times come from the flight tables in the data (see "Sources")
and from the character's own flights.

- **On the flight map**: the tooltip of a flight point that can be flown to gets one line,
  "Flight time: about 1:18". For a flight through other points the hops the game says it will
  fly are added up; where the client does not say, the quickest way over the table through
  points the character knows is taken.
- **While flying**: the arrow has nothing to point at, so its frame shows the time left, large,
  and the destination under it, and the arrow rests until the landing. A flight with no time in
  the data counts up instead ("+0:42"). One setting, on by default: "Flight timer"
  (`/lvl set flightTimer`).
- **Another flight timer**: while the addon `EllesmereUIForeverEssentials` is loaded, ours is
  not drawn, the way the arrow steps aside for TomTom. The tooltip line and the measuring stay.
- **Measured**: every flight the character completes is timed from take-off to landing and
  kept per character (a perk makes one character's flights faster than another's). A route
  flown before shows its own time, without "about". The times of direct flights are also
  compared with the table's, and every time not yet measured is scaled by that ratio. A flight
  that ends at under half or over one and a half times what was expected is not kept.
- **Known flight points**: each time the flight map is open, the points on it that the
  character has discovered are remembered per character (`ns.char.flights.known`, by taxi node
  id). `/lvl flights` prints how many are known, how many flights are timed, and the ratio.
- **Cost**: the flight map is read once when it opens; the tooltip line is worked out when a
  point is hovered; one task, five times a second, runs only during a flight and hands the
  frame a new text once a second.

The planner uses the known flight points and these times when it has to send the character to
another zone (see "The planner", "Flights"). Boats and zeppelins are not in the data.

### Automation

`Automation.lua` removes the clicks that carry no decision (issue #9). Both halves are on by
default, each with its own setting: "Accept quests automatically" (`/lvl set autoAccept`) and
"Hand in quests automatically" (`/lvl set autoTurnIn`).

- **Only what is suggested**: a quest is accepted when a pending "accept" step names it, and
  handed in when a pending "turnin" step names it and the game says it is ready. That covers
  the quest's own windows and picking it from an NPC's list of quests. Any other quest is left
  to the player.
- **Shift** held while the window opens does the opposite of the setting for that window.
- **Never**: choosing between rewards (it stops at the reward window), and repeatable quests.
- **Any state**: if the steps change while an NPC's window is open, the window is looked at
  again.
- Not built, because the data has nothing for them: gossip options, flights (#16), inns.

### First-run setup and quest preferences

`FirstRun.lua` holds the player's two choices about which quests are suggested (issue #20),
both off by default and saved per character: "Include dungeon quests" (`/lvl dungeons`) and
"Include group quests" (`/lvl groups`). They are also on the settings page. Raid and PvP quests
are always left out; there is no switch for them.

- **At run time the choice lives in `ns.Planner.allow`** (`allow.dungeon`, `allow.group`), set
  at login and on every change. Read it there.
- **A change applies at once** (#24): it asks for one planner pass. Progress and skipped quests
  are not touched.
- **A panel asks once per character**, at its first login with the addon, whatever its level
  and history: the two tick boxes, a reminder that the window can be dragged, and "Start". The
  guide window is live behind it. `/lvl setup` shows it again.
- The settings page only knows account-wide settings, so `ns.db.dungeons` and `ns.db.groups`
  are a copy for the character that is logged in; `ns.char` holds what is saved.
- Not built, because the data cannot honour them: "fastest or safest" and professions.

### The target macro

`/lvl macro` makes one general macro, `LvlTarget`, and puts it on the cursor to drop on an
action bar (#12). Pressing it targets the current step's NPC or creatures and puts the skull on
what it targeted:

```
/cleartarget
/targetexact Kobold Vermin
/tm 8
```

- **Names**: the quest giver or taker of an accept or turn-in step; for a kill step every
  creature the quest data lists for that objective; for a loot step whatever drops or sells the
  item. A step with nothing to target (a place to reach, an object to click) leaves the macro
  empty.
- **Length**: a macro holds 255 characters. When the names do not fit, those whose spawns are
  nearest the step's point are kept; `/lvl verbose` says how many were left out.
- **Combat**: the game allows no macro changes in combat, so a step change during a fight is
  written when the fight ends.
- **Yours**: the macro is made only on `/lvl macro`, never by itself. A macro of that name that
  the addon did not make is left alone, and one the player deleted is not made again.

### Reward marks

`Rewards.lua` marks a choice of quest rewards (issue #10), with a setting, "Mark quest rewards"
(`/lvl set rewardMarks`), on by default. It never picks: the player chooses.

- **Sells for most**: the game's gold coin on the icon of the reward with the highest sell
  price times count. No coin on a tie.
- **Upgrade**: the game's green bag arrow on the reward with the biggest gain in item level
  over what is worn in its slot, among the rewards the game says the character can use. Rings,
  trinkets and one-hand weapons are held against the weaker of the two worn. This is a rough
  rule: it knows no stats. Where nothing fair can be compared (a ranged weapon, a shield beside
  a two-hander, item data not loaded) there is no arrow.
- **Cost**: everything is read from the client on `QUEST_COMPLETE` and again when item data
  arrives, only while a window with a choice is open. Two badge frames, made once.
- Not built: stat weights per class, and an automatic pick.

### Quests not worth keeping

`Abandon.lua` lists the quests in the log that are not worth keeping (issue #13) and abandons
the ones the player leaves ticked. `/lvl abandon` or the button on the settings page opens the
list; with nothing to list it says so in chat.

| Reason shown | When | Starts |
| --- | --- | --- |
| too low level | The quest is more than 7 levels under the character, and is not a prerequisite, directly or up a chain, of a quest still worth doing | ticked |
| skipped by you | The player skipped it and has not brought it back | unticked |
| dungeon quest, raid quest, group quest, PvP quest | The quest carries that mark and `ns.Planner.allow` does not allow it | unticked |

- **Never listed**: a quest ready to hand in, a quest the data does not know, and a quest for
  where it is: distance is not a reason.
- **Nothing without the click**: "Abandon N quests" abandons the ticked rows that are still in
  the log and still unfinished. A second later chat says how many left, and how many the game
  kept.
- **Worked out when opened**, not kept current. `ns.QuestsToAbandon()` returns the rows,
  `{ questID, name, reason, ticked }`, for other features (#23).

`test_abandon.lua` checks the list and the button. Whether the Forever client lets an addon
abandon a quest is not known: see [`docs/ingame-checks/abandon.md`](docs/ingame-checks/abandon.md).

### Writing a feature

The addon must stay cheap to run (issue #2). `Core.lua` holds the machinery every feature
shares, so that no feature needs a frame for events or an `OnUpdate` of its own.

- One new file per feature under `addon/LevelingAddon/`, added as one line at the end of the
  TOC. Each file starts with `local _, ns = ...`; `ns` is the table all files share.
- One test file per feature, `addon/tests/test_<feature>.lua`, starting from `stub.lua` (its
  header says how). CI runs every `test_*.lua`. Add to `stub.lua` only the game API your
  feature calls.
- One list of what to check in the game per feature, `docs/ingame-checks/<feature>.md`: no
  cloud session can run the game, so whatever only the client can confirm goes there.
- Do not edit another feature's file. `Core.lua`, the TOC header, `stub.lua` and `ci.yml` belong
  to the shared machinery (#2); `Planner.lua` to the planner (#3); `Steps.lua` to #7; `Window.lua`
  and `Settings.lua` to #4; `Arrow.lua` to #5. Commands, defaults and events are added from your own file, with
  the names below.
- Work happens on events. Nothing is recomputed per frame.
- No `OnUpdate` of your own: register a task on the shared loop, and switch it off whenever it
  has nothing to do.
- Never create frames repeatedly. Create them once and reuse them from a pool.

| Name | Does |
| --- | --- |
| `ns.On(event, handler)` | Calls `handler(event, ...)` on a game event. Any number of handlers per event, called in the order added. `ADDON_LOADED` arrives for this addon only, with the saved settings ready. Core builds the window at `PLAYER_LOGIN`, before any feature's handler for it. |
| `ns.Debounce(seconds, fn)` | Returns a function. Calling it any number of times in a burst calls `fn()` once, `seconds` after the first call. |
| `ns.Task(name, seconds, fn)` | Registers `fn()` on the shared update loop, to run every `seconds` (0: every frame) while the task is on. A task starts off. |
| `ns.SetTask(name, on)` | Switches a task on or off. The loop runs only while some task is on. A task that fails three times in a row is switched off until `/reload`, and the player is told once. |
| `ns.Job(name, fn)` | Runs `fn()` spread over frames, one job at a time, with a time limit per frame. When it finishes, its time is reported under `name`. |
| `ns.Pause()` | Inside a job, between units of work: gives the frame back if its time is used up. Not from inside `pcall`. |
| `ns.Clock()` | Milliseconds, for measuring: `local t = ns.Clock() ... ns.Clock() - t`. |
| `ns.Report(name, ms)` | Records how long the named work took the last time. `/lvl debug` prints it. |
| `ns.Stats(reset)` | The numbers `/lvl debug` prints, as a table: `memoryKB`, `timers[name]` in ms, and `loop.idle` and `loop.moving`, each `{ frames, ms, max }` for the frames the shared loop ran in. `true` starts the loop counters again. |
| `ns.commands.name = function(arg) end` | Adds `/lvl name arg`. The help line is built from the table. |
| `ns.defaults.key = value` | A default for an account-wide setting, set at file scope and read as `ns.db.key` from `ADDON_LOADED` on. A table default is copied, and filled in key by key. |
| `ns.charDefaults.key = value` | The same per character, read as `ns.char.key`. |
| `ns.AddSetting({ key = "name", label = "Text" })` | Puts a control for `ns.db.name` on the addon's settings page, and under `/lvl set name`. Call it at file scope, after setting `ns.defaults.name`: a boolean default gives a checkbox, a number a slider, which also needs `min`, `max` and `step`, a string a dropdown, which also needs `options = { "a", "b" }`. Every setting needs a check in `addon/tests/test_settings_apply.lua`. Optional: `tooltip`, and `onChange = function(value) end`, called after the value has changed; without it `ns.Refresh()` is called. Either way a change applies at once, with no reload. `ns.AddSetting({ label = "Text", func = function() end })` adds a button. |
| `ns.Set(key, value)` | Changes a setting added with `ns.AddSetting` from code and applies it the same way. A slash command that changes a setting calls this, never `ns.db` directly, so the command and the page agree. |
| `ns.say(text)` | Prints a line to chat under the addon's name. |
| `ns.Debug(text)` | The same, but only while verbose output is on (`/lvl verbose`). For anything worth seeing while chasing a bug and not otherwise. |
| `ns.errors` | The last ten errors the shared loop and the jobs caught, oldest first, as text. `/lvl report` lists them. |
| `ns.Refresh()` | Redraws the window and the arrow after a change. |

An example, `addon/LevelingAddon/Example.lua`:

```lua
local _, ns = ...

ns.charDefaults.visits = 0 -- per character
ns.defaults.greet = true -- account-wide
ns.AddSetting({ key = "greet", label = "Greet at login" }) -- a checkbox on the settings page

-- Many events, one pass a moment later, spread over frames.
local replan = ns.Debounce(0.2, function()
    ns.Job("planner", function()
        for _ = 1, 1000 do
            -- one unit of work
            ns.Pause()
        end
    end)
end)
ns.On("PLAYER_LEVEL_UP", replan)
ns.On("ZONE_CHANGED_NEW_AREA", replan)

ns.On("PLAYER_LOGIN", function()
    ns.char.visits = ns.char.visits + 1
end)

-- Something that needs frequent updates, only while it is needed.
ns.Task("example", 0.1, function()
    -- update what is on screen
end)
ns.commands.example = function(arg)
    ns.SetTask("example", arg == "on")
end
```

A new game API name goes into `read_globals` in `.luacheckrc`, one per line in its sorted
place; the list is seeded with names the planned features are expected to need. `/lvl help`
lists the commands, so the command table above does not need a row per feature. `/lvl debug` prints the addon's
memory, the last time of each reported piece of work, and the shared loop's time per frame
while standing still and while moving, counted since the previous `/lvl debug`. The targets
for these numbers are not set yet; they are measured in the game (issue #2).

### Bug reports and verbose output

`/lvl report` opens a box with text to copy into a bug report: client version, character level
and class, zone and position, the steps around the current one, the settings, the data version
(`ns.Data.manifest`, or "not loaded"), the timings of `/lvl debug`, and the last errors the
addon caught. It never asks the game for the character's name, realm, guild or account. A
feature that saves settings should keep names out of them for the same reason: the settings
are printed as they are.

`/lvl verbose`, or "Verbose output" on the settings page, switches verbose output on or off (saved account-wide). While it is on, the
addon prints what `ns.Debug` is given, including every event below as it is sent.

### Events for other addons

The addon announces three things for other addons to build on. The names and arguments are
meant to stay as they are; arguments may be added at the end.

| Event | When | Arguments |
| --- | --- | --- |
| `LevelingAddon.StepShown` | The current step has changed: at login, and whenever a step is finished or skipped, or the planner changes its mind, so that another one becomes current. Not on a redraw or a new plan with the same current step, and not when there is nothing to suggest. Also sent while the window is hidden. | `index`: the step's place in `ns.Steps.list` right now, from 1; it moves as the planner rebuilds the list, so do not keep it. `step`: the addon's own table for the step, to read and not to change: `kind` (`"accept"`, `"turnin"`, `"kill"`, `"loot"` or `"go"`), `name`, `questID`, `need`, `objective`, `map` (a `uiMapId`), `x` and `y` (map percent), as described under "The planner". |
| `LevelingAddon.QuestAccepted` | The player accepted a quest, any quest, on the route or not. | `questID` |
| `LevelingAddon.QuestTurnedIn` | The player handed a quest in, any quest. | `questID` |

Listen through the global `LevelingAddonEvents`. Make your addon load after this one
(`## OptionalDeps: LevelingAddon` in your TOC), and always pass an owner: any table or string
of yours. It comes back as the first argument, and it is the handle to stop listening.

```lua
local owner = {}
LevelingAddonEvents:RegisterCallback("LevelingAddon.StepShown", function(_, index, step)
    print("now at step", index, step.kind, step.questID)
end, owner)
LevelingAddonEvents:RegisterCallback("LevelingAddon.QuestTurnedIn", function(_, questID)
    print("handed in", questID)
end, owner)
-- later: LevelingAddonEvents:UnregisterCallback("LevelingAddon.StepShown", owner)
```

Where the client has the game's `EventRegistry`, `LevelingAddonEvents` is that same object,
so `EventRegistry:RegisterCallback(...)` works as well and needs no load order. Where the
client has none, `LevelingAddonEvents` is a small stand-in of the addon's own with the same
three methods (`RegisterCallback`, `UnregisterCallback`, `TriggerEvent`), one callback per
event and owner. An error in a listener does not stop the addon or the other listeners.

## Layout

```
collector.json          pinned sources and fetch settings
tools/collector/        the C# / .NET 10 collector (runs outside the game)
addon/LevelingAddon/    the addon's Lua: guide window, arrow, planner and the smaller features
addon/LevelingAddon/Data/  the quest data the addon loads (gitignored; "Building the quest data")
addon/tests/            tests that run outside the game, against a stub of the game API
docs/                   UI research, decisions, mockups, and what to check in the game
data/raw/               raw inputs: QuestieDB checkout, cached Wowhead responses (gitignored)
data/parsed/            normalized JSON, the source of truth (committed)
data/lua/               Lua table files generated from data/parsed (gitignored; one command to rebuild)
reports/                validation report (committed)
```

## Parsed data

All files are JSON arrays with one entity per line, sorted by id. Empty and absent values are
omitted. Re-running `parse` on the same QuestieDB commit produces identical files.

| File | Contents |
| --- | --- |
| `quests.json` | Level, required level, side and races, classes, zone or category, objective text, start and end (NPCs, objects, items), objectives, completion trigger, XP, reputation rewards, flags, skill and reputation requirements. `origin` is `era` or `forever`. |
| `quest-relations.json` | Per quest: `preQuestSingle` (any one), `preQuestGroup` (all), `nextQuestInChain`, `parentQuest` / `childQuests`, `inGroupWith`, `exclusiveTo`, `breadcrumbForQuestId` / `breadcrumbs`, and availability links. Ids keep QuestieDB's sign. |
| `npcs.json` | NPCs a quest refers to, including droppers and vendors of quest items: name, level, faction, `spawns` as `{zoneId: [[x, y], ...]}` in map percentages, patrol `waypoints`, quests started and ended. |
| `objects.json` | Game objects a quest refers to, with `spawns`. |
| `items.json` | Items a quest refers to, with their sources (`npcDrops`, `objectDrops`, `itemDrops`, `vendors`). |
| `zones.json` | Zones used by the data: QuestieDB's symbol, an English name, `uiMapId`, parent zone. Sub-zones QuestieDB has no symbol for have no name. |
| `manifest.json` | Source repository, commit and counts. |
| `taxi-nodes.json` | Flight points, from the taxi source: the game's taxi node id, name, `faction` (absent: both sides), continent (`map`: 0 or 1) and world `x`, `y` in yards. Where QuestieDB has a flight master there: `npcId`, `npcName`, and the master's place as `uiMapId`, `mapX`, `mapY` (map percent). |
| `taxi-paths.json` | Direct flights: `from`, `to`, `seconds`, and `estimated` where the source had no measured time. Sorted by `from`, then `to`. |
| `taxi-notice.txt` | Where the two files above come from, their licence, and the header of the source file with InFlight's MIT notice. Copied into the head of the exported Lua files. |

The three `taxi-` files are written by the same `parse` run but are not QuestieDB's: see
"Sources". QuestieDB marks 61 NPCs as flight masters (`npcFlags` bit 8), and `npcs.json` keeps
only the 12 a quest refers to. The others are kept here, on their flight point. A flight
master is linked by position: its spawn point is turned into world yards with its zone map's
rectangle (from `Data/Zones.lua` of the taxi source), and each flight point takes the nearest
master of its side on its continent within 100 yards. On this data 61 of the 65 points have a
master. The four without are the two in Riverglades (new in Forever) and the two on Mount
Hyjal, for which QuestieDB has no flight master. Two flight masters are linked to nothing: the
druid-only ones in Moonglade, whose flights the source leaves out.

A spawn point of `[-1, -1]` is QuestieDB's placeholder for content inside an instance.

Not in the data yet, because QuestieDB does not carry it: money and item rewards, the patch a
quest first appeared in, and Wowhead's "new / updated" notes. Faction-specific corrections that
QuestieDB applies at runtime for the logged-in character are also not included.

## Lua export

`collector export` turns `data/parsed/` into Lua files for the addon, in `data/lua/` or the
directory given with `--out`. Rows keep the JSON's field names and nothing is dropped; each
entity is on one line keyed by its id (the id is the key and is not repeated inside the row).
Two things differ from the JSON, both in the `spawns` and `waypoints` of NPCs and objects:
coordinate lists are flat, and long spawn lists are reduced. `data/parsed/` is never changed.

```lua
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.npcs = ns.Data.npcs or {}
local t = ns.Data.npcs
t[228]={name="Avette Fellwood",minLevel=24,zoneId=10,spawns={[10]={73.03,44.42}},waypoints={[10]={{73.27,44.76,73.03,44.47}}},questEnds={95161}}
```

| Output | Contents |
| --- | --- |
| `quests-N.lua`, `questRelations-N.lua`, `npcs-N.lua`, `objects-N.lua`, `items-N.lua`, `zones-N.lua` | `ns.Data.<table>[id] = row` |
| `plannerQuests-N.lua`, `plannerZones-N.lua` | The planner index: see below |
| `taxiNodes-N.lua` | `ns.Data.taxiNodes[id] = row`, as in `taxi-nodes.json` |
| `taxiPaths-N.lua` | `ns.Data.taxiPaths[from] = { to = { [to] = seconds, ... }, est = { [to] = true, ... } }`: the flights out of each point, `est` only where a time is estimated. The two taxi files carry `taxi-notice.txt` in their head. |
| `manifest.lua` | `ns.Data.manifest`: source commit and counts |
| `data.xml` | Lists every file as a `<Script>`, so the addon's TOC needs one stable line |

### The planner index

Two more tables hold what the addon's planner looks up, so that nothing is derived at login.
They are built by `PlannerIndex.cs` from the same JSON and exported like the others.

```lua
t[7]={name="Kobold Camp Cleanup",level=2,req=1,side="alliance",xp=170,pre={783},excl={15},start={{"Marshal McBride",1429,48.92,41.61}},finish={{"Marshal McBride",1429,48.92,41.61}},obj={{"monster","Kobold Vermin",1429,49.17,36.55}}}
```

| Field of `plannerQuests[id]` | Contents |
| --- | --- |
| `name`, `level`, `xp` | As in `quests` |
| `req`, `maxLevel` | Required level, and the highest level that may take the quest |
| `side`, `races`, `classes` | `side` is left out for both sides. `races` is left out when it names everyone on the side; names are the client's race tokens in upper case (`NIGHTELF`, `SCOURGE`). |
| `pre`, `preAll` | Prerequisites: any one of `pre`, all of `preAll` |
| `excl` | Not offered once any of these is completed or in the log: `exclusiveTo`, the quest this one is a breadcrumb for, and the next quest in its chain |
| `parent` | Offered only while this quest is in the log |
| `skill`, `minRep`, `maxRep` | `{skillId, value}` and `{factionId, value}` |
| `mark` | `raid`, `dungeon`, `pvp` or `group`; see below |
| `start`, `finish` | Where to pick the quest up and hand it in: a list of alternatives, each `{name, uiMapId, x, y, ...}` with one point per zone map |
| `obj` | One entry per objective that has a place: `{type, name, uiMapId, x, y, ...}`, where `type` is the game's own objective type (`monster`, `item`, `object`, `event`), in the order the data lists them per type |

A target's point in a zone is the real spawn nearest to the mean of its spawns there (for an
item, the spawns of whatever drops or sells it). Points inside instances and in zones without a
map are left out.

| Field of `plannerZones[uiMapId]` | Contents |
| --- | --- |
| `name` | The zone's name |
| `min`, `max` | The zone's level range, derived from its quests: the 10th to the 85th percentile of the levels of its ordinary quests |
| `bands[n]` | The quests that can be picked up in the zone by a character in level band `n` (levels `5n-4` to `5n`), prerequisites first. A quest is in every band from its required level to 7 levels above its own level. |

The data has no quest type, so the marks are derived, and were checked against the data:

- `raid`: `questFlags` bit 64 (389 quests), or the quest's zone is one of the raid zones. The
  flag alone misses most quests of Molten Core and the Temple of Ahn'Qiraj, so the raid zones
  are listed by id in `PlannerIndex.cs`.
- `dungeon`: the quest's zone is flagged `isDungeon` and has an instance map, or one of its
  objectives exists only inside an instance. `isDungeon` also covers raids, the three
  battlegrounds and a few city and event zones; raids and battlegrounds are told apart by id,
  and the city and event zones have no map of their own and get no mark.
- `pvp`: the quest's zone is a battleground.
- `group`: an objective NPC is elite (`rank` of 1 or more), or an objective item drops only
  from elites.

On this data: 512 raid, 357 dungeon, 99 pvp and 233 group quests out of 5,768. The two tables
take 5.7 MB (plannerQuests) and 0.3 MB in the collector's interpreter, 7.7 and 0.4 MB in stock
Lua 5.1. The planner reads only these two tables; the arrow reads `quests`, `npcs`, `objects`,
`items` and `zones` for a step's places, and the rest are loaded for the features to come.

### Spawns and waypoints

`npc.spawns[zoneId]` and `object.spawns[zoneId]` are one flat array of numbers,
`{x1, y1, x2, y2, ...}`, in percent of the zone map. Zone ids are numeric keys.

```lua
local points = ns.Data.npcs[id].spawns[zoneId]
for i = 1, #points, 2 do
  local x, y = points[i], points[i + 1]
  if x == -1 and y == -1 then
    -- inside an instance: no map position
  end
end
-- number of points: #points / 2
```

`npc.waypoints[zoneId]` is a list of patrol paths, each path one flat array of the same form:
`waypoints[zoneId][pathIndex] = {x1, y1, x2, y2, ...}`. Waypoints are never reduced.

Spawn lists are reduced per entity and zone, by two settings under `export` in `collector.json`:

- A list with at most `spawnMergeAbove` points (10) is exported exactly as it is in the JSON, so
  a quest giver or a named mob keeps its precise position.
- In a longer list, going through the points in order, a point within `spawnMergeDistance` (2,
  in percent of the zone map) of a point already kept is dropped; the kept point stands for it.

So every exported point is a real spawn point, in its original order; in a reduced list the
points are more than the merge distance apart, and every spawn that was dropped has an exported
point within the merge distance. `-1, -1` placeholders are always kept, and they do not count
towards `spawnMergeAbove`. Both values are first guesses to be tuned in game once the arrow
exists. With them, 49,511 of 107,654 spawn points are exported.

Not changed: a quest's `triggerEnd.locations[zoneId]` is still a list of `{x, y}` pairs (144
quests; flattening it would save under 0.2 MB). One NPC (12126) has a third number on a spawn
point in the JSON, a repeat of the zone's `uiMapId`; only x and y are exported.

### Memory

After writing, `collector export` loads the files table by table and prints what each adds to
the interpreter's memory after a full garbage collection. The collector's interpreter is Lua
5.4; the game runs Lua 5.1, whose tables are larger, so the same files were also measured once
in stock Lua 5.1 on a 64-bit machine. QuestieDB commit `3f10ca0751`, in MB:

| Table | Before, 5.4 | After, 5.4 | Before, 5.1 | After, 5.1 |
| --- | ---: | ---: | ---: | ---: |
| `quests` | 8.23 | 8.23 | 11.05 | 11.05 |
| `questRelations` | 0.73 | 0.73 | 0.93 | 0.93 |
| `npcs` | 13.35 | 5.49 | 15.78 | 7.19 |
| `objects` | 3.23 | 1.02 | 3.63 | 1.20 |
| `items` | 1.87 | 1.87 | 2.35 | 2.35 |
| `zones` | 0.03 | 0.03 | 0.05 | 0.05 |
| Total | 27.43 | 17.36 | 33.79 | 22.78 |

The "about 47 MB" this section used to give matches Lua 5.1 right after loading, before a
garbage collection (46.3 MB on this data); 33.79 MB is the same data once collected.

Where the 11 MB went, in Lua 5.1: spawns took 12.9 MB as `{x, y}` pairs. Flat arrays alone
bring that to 4.75 MB, and merging to 2.9 MB. Flat waypoints go from 1.5 to 0.5 MB. What is
left in `spawns` is mostly the two small tables every entity and zone needs, not points, so
stricter settings gain little: merging above 5 points within 3 percent ends at 22.4 MB.

Measured and not done: writing rows as positional arrays (`{"Avette Fellwood",24,...}` with an
index table per data table) would save a further 5.4 MB in Lua 5.1 (22.8 to 17.4 MB), because
the named rows themselves cost about 10 MB. The owner decided to keep named rows for now;
dropping unused fields later shrinks the same cost.

Memory in the game client has not been measured yet.

### Things to know when designing the addon

- `end` is a Lua keyword, so a quest's turn-in is `quest["end"]`, not `quest.end`.
- `requiredRaces` can exceed 32 bits (the Skyborne races); the game's `bit` library works on 32
  bits, so use `side` and `races` instead of masking it.
- Lua 5.1 refuses a file with more than 262,143 distinct literals. A table is split into
  numbered files before it gets close; the files can load in any order.
- Zone 1 (Dun Morogh) in `waypoints` is at index 1 like any other zone id; there is nothing
  special to do in Lua.

### Verification

`collector export` loads every file in the sandboxed interpreter, the way the game calls an
addon file, and checks every value read back. Spawn lists are checked against the reduction
rule above (short lists identical; reduced lists made of original points in order, far enough
apart, with every dropped point covered and every placeholder kept); waypoints must hold every
point; everything else must equal the JSON. It exits non-zero on any difference. `data.xml` and
loading inside the actual game client have not been tried.

## Sources

**QuestieDB (primary).** `github.com/Questie/QuestieDB`, pinned by commit in `collector.json`.
Its Forever data is a base table plus about twenty correction files that its own Lua code merges
in a fixed order. The collector runs that code unchanged, so the merge is QuestieDB's and not a
reimplementation. It runs in an embedded reference Lua interpreter with only the basic, string,
table and math libraries: no `os`, `io`, `package` or `debug`, text chunks only, and file reads
confined to the checkout. 2,601 of QuestieDB's own correction checks pass in that interpreter;
the remainder of its test suite needs temp files or subprocesses and cannot run there.

**shortest-path-forever (flight points and flight times).** `github.com/cjber/shortest-path-forever`,
pinned by commit under `taxi` in `collector.json`, licensed GPL-3.0-or-later. `collector parse`
reads two of its files: `Data/Taxi.lua` (65 flight points with world coordinates, name and
faction, and 286 direct flights with their seconds) and `Data/Zones.lua` (the zone maps'
rectangles in world yards, used only to link flight masters to flight points). Both are data
in Lua syntax, generated by that project from the client's tables (via wago.tools), CMaNGOS
classic-db (GPL-3.0) and the InFlight addon's recorded flight times (MIT; 266 of the 286 times
are InFlight's, the other 20 are that project's estimates from the path's length at 32 yards a
second). They are loaded in the same sandboxed interpreter as QuestieDB's code and only their
tables are read; the path points are not kept. InFlight's MIT notice travels with the data: in
`data/parsed/taxi-notice.txt` and in the head of the exported `taxiNodes` and `taxiPaths`
files. To move to a newer commit, change `revision` and run `parse`; the nightly update moves
only QuestieDB's pin.

**Wowhead (secondary).** For what QuestieDB lacks, and the total to reconcile against (6,138 on
2026-11-14). Findings from that date:

- `robots.txt` disallows the whole site for named AI and scraper agents. For every other client
  it disallows only `/account`, `/list` (user lists), `/random`, `/search` and
  `/site-achievement`; the quest listing and quest pages are not disallowed.
- Site pages sit behind a browser check (HTTP 202 with `x-amzn-waf-action: challenge`), so they
  need a real browser. The tooltip endpoint on `nether.wowhead.com` serves JSON to plain clients.
- The terms of use could not be read from the collection environment. Read them before running
  any bulk fetch.

Wowhead is fetched only by you, on your own machine, never from a cloud agent session.

## Using the collector

```sh
cd tools/collector
dotnet build
dotnet test

dotnet run --project src/Collector -- parse       # sync QuestieDB, merge, write data/parsed and reports
dotnet run --project src/Collector -- export      # data/parsed -> Lua files in data/lua
dotnet run --project src/Collector -- status

dotnet run --project src/Collector -- fetch quest --ids 2,5,6 --limit 3
dotnet run --project src/Collector -- fetch npc-tooltip --ids-file ids.txt
dotnet run --project src/Collector -- fetch list --urls-file slices.txt
```

`parse` needs `git` on the path and takes a few seconds once QuestieDB and the taxi source are
checked out (`data/raw/questiedb`, `data/raw/taxi`). To move to a newer QuestieDB, change the
commit in `collector.json` and run it again.

`fetch` makes one request at a time, waits `delaySeconds` plus jitter between requests, honours
`robots.txt` (including a crawl-delay), and writes every response under
`data/raw/wowhead/<kind>/` with a `.meta.json` beside it. Anything already cached is skipped
without a network request, so re-running a command resumes it. A page that does not exist is
recorded once and not asked for again. A refusal or bot challenge is never cached: the run backs
off, retries, and stops after `maxConsecutiveFailures` in a row.

Browser kinds (`quest`, `list`, `class-spells`) open a visible window of the browser named by
`browserChannel`. Nothing about the browser is disguised; if Wowhead still refuses, the run stops.

On every browser page the expressions under `browserCaptures` in `collector.json` are evaluated,
and each one that finds something is stored beside the page as `<key>.<capture>.json`. A kind
may name one of them as its `requiredCapture`: a page on which that capture finds nothing stops
the run at once, with no retry, and is not cached. The page is kept as `<key>.rejected.html` to
look at, and is asked for again on the next run.

### Fetching class spells

The trainer suggestions (#17) need the spells each class learns at each level and what they
cost to train. QuestieDB has neither, so they come from Wowhead's ability listing of each
class. This is prepared and has not been run: like every Wowhead fetch, you run it on your own
machine, never from a cloud agent session. **Read Wowhead's terms of use first**; nobody has
yet (see "Sources").

```sh
cd tools/collector
dotnet build
dotnet run --project src/Collector -- fetch class-spells --urls-file class-spells.txt --limit 1   # a one-page trial
dotnet run --project src/Collector -- fetch class-spells --urls-file class-spells.txt             # the rest
```

- **Requests**: ten in all. One page per class, nine classes, listed in
  `tools/collector/class-spells.txt`, plus `robots.txt` once, each `delaySeconds` plus jitter
  apart: about a minute. The second command skips what the trial already fetched.
- **Where it lands**: `data/raw/wowhead/class-spells/` (gitignored). Per class, the page
  (`forever_spells_abilities_<class>-<hash>.html`), its `.meta.json`, and the rows of the spell
  list as `forever_spells_abilities_<class>-<hash>.spells.json`.
- **What to send back**: two or three classes' `.spells.json` and `.html` files, so that the
  parser can be written against real pages. Either attach them to #17, or commit them to a
  branch that is not meant to be merged (`git add -f`, since `data/raw/` is ignored).

Three things here are assumptions, because the site cannot be opened from where this was
written:

| Assumption | Where to correct it |
| --- | --- |
| The pages are at `https://www.wowhead.com/forever/spells/abilities/<class>` | `tools/collector/class-spells.txt` |
| The page keeps the rows of its spell list in `g_listviews.spells.data`, as the quest listing does in `g_listviews.quests.data` | `browserCaptures.spells` in `collector.json` |
| One page holds all of a class's abilities, with level and training cost in the rows | Not checked by the collector: look at the row count in a `.spells.json` |

That is what the one-page trial is for. With a wrong address it reports the page as
"recorded as missing", or the site sends the browser somewhere else and the run ends as below.
With a wrong list name the run ends with "the browser capture 'spells' found nothing", stops at
that page and leaves a `.rejected.html`. Then open the address in your browser, type
`Object.keys(g_listviews)` in the developer console to see what the list is called, and correct
the expression; or send the `.rejected.html` back instead of the samples.

## Checks

`.github/workflows/ci.yml` runs on every pull request and on every push to `main`. Each job
runs only when something it checks has changed, and is skipped otherwise:

| Job | Runs | When these change |
| --- | --- | --- |
| `collector` | `dotnet build`, `dotnet test` and `dotnet format --verify-no-changes` in `tools/collector` | `tools/collector/`, `collector.json`, `.editorconfig` |
| `lua` | `luacheck .` and `stylua --check .` from the repository root, then every `addon/tests/test_*.lua` | any `.lua` file, `.luacheckrc`, `stylua.toml`, `.styluaignore` |

A change to `ci.yml` itself runs both.

`main` is protected: changes reach it only through a pull request, and both jobs must pass
before it can merge.

The same commands work locally. `dotnet format` without the flag fixes what it reports, and so
does `stylua .`. Code style for the collector is in `.editorconfig`.

The Lua settings are for the addon's source. `data/` is excluded from all three tools: it holds
QuestieDB's checkout and the generated tables.

| File | Tool |
| --- | --- |
| `.luacheckrc` | [Luacheck](https://github.com/lunarmodules/luacheck), the linter: Lua 5.1 plus a list of the game's globals, to extend as the addon uses more of the API |
| `stylua.toml`, `.styluaignore` | [StyLua](https://github.com/JohnnyMorganz/StyLua), the formatter: Lua 5.1 syntax, 4 spaces, 120 columns |
| `.luarc.json` | [lua-language-server](https://github.com/LuaLS/lua-language-server), for type checking in the editor. Not run in CI. |
| `.vscode/extensions.json` | Suggests the Lua, StyLua and [WoW API](https://github.com/Ketho/vscode-wow-api) extensions; the last one supplies the game's API annotations once the folder has a `.toc` file |

## Nightly data update

`.github/workflows/update-data.yml` runs every night at 03:23 UTC, and on demand from the
Actions tab. If QuestieDB's newest commit is not the one pinned in `collector.json`, it moves
the pin, runs `collector parse`, and opens a pull request with the new `data/parsed/` and
`reports/`. The pull request merges itself once `collector` and `lua` pass; nobody reads it
first. If it is still open the next night, it is updated in place.

Nothing is proposed, and the run fails, if any row fails to parse or the result no longer
exports to Lua. The run that executes QuestieDB's code has a read-only token; a second job,
which only receives the resulting files, commits them.

It needs two repository settings: "Allow GitHub Actions to create and approve pull requests"
(Settings, Actions, General) and "Allow auto-merge" (Settings, General).

## Licence

The data in `data/parsed/` is derived from QuestieDB, which its maintainers publish under the
GNU General Public License v3. This repository is therefore licensed under GPL-3.0; see
[`LICENSE.md`](LICENSE.md). The flight points and flight times are derived from
shortest-path-forever (GPL-3.0-or-later), which includes flight times recorded by the InFlight
addon under the MIT licence; that notice is kept in
[`data/parsed/taxi-notice.txt`](data/parsed/taxi-notice.txt). Quest, NPC and item names are
Blizzard Entertainment's.
