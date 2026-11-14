# levelingaddon

Data collection for a World of Warcraft: Forever leveling addon. This phase only gathers quest
data; the addon itself (Lua) comes later.

## Status

| Step | State |
| --- | --- |
| Investigation of sources, robots.txt | Done (see "Sources") |
| QuestieDB → normalized JSON | Done: 5,914 quests, 0 parse failures |
| Validation report | Done: [`reports/validation.md`](reports/validation.md) |
| Polite, resumable Wowhead fetcher with raw cache | Built and tested against a local test server; not yet run against Wowhead |
| Wowhead list / quest page parsers | Not built: need a few real sample pages first |
| JSON → Lua export | Done: `collector export`, with reduced spawn lists and a per-table memory report; checked by loading the files back |

## Addon (UI shell)

`addon/LevelingAddon/` is a first shell of the interface, not yet run in the game: a guide
window and an arrow for a fixed sample route (the first stretch of Northshire, the human
start, with quest ids, names and coordinates taken from `data/parsed`). Step progress is read
from the game's quest log: accepting a quest, objective counts and handing a quest in move the
list by themselves. The route is not yet computed from the quest data. The design and the
reasons behind it are in [`docs/ui-concepts.md`](docs/ui-concepts.md).

To try it, copy `addon/LevelingAddon` into the game's `Interface/AddOns` folder and start a
human character.

| Command | Does |
| --- | --- |
| `/lvl` | Hide or show the window and arrow |
| `/lvl rows N`, `/lvl scale N` | Steps in view (3 to 16), window scale (0.6 to 2) |
| `/lvl arrow` | Turn our arrow on or off |
| `/lvl unskip` | Bring every skipped step back |
| `/lvl reset` | Put the window back where it starts |
| `/lvl debug` | Print the addon's memory use and timings (see "Writing a feature") |

In the window: drag to move, mouse wheel to scroll through the route, the cross on a pending
step skips it, the arrow on a skipped step brings it back.

`lua5.1 addon/tests/smoke.lua addon/LevelingAddon` runs the addon against a stub of the game
API with a fake quest log, and checks tracking, skip and restore, combat folding, the arrow's
direction and distance, the TomTom hand-off, and the shared machinery below. It cannot check
how anything looks; that needs the game client.

### Writing a feature

The addon must stay cheap to run (issue #2). `Core.lua` holds the machinery every feature
shares, so that no feature needs a frame for events or an `OnUpdate` of its own.

- One file per feature under `addon/LevelingAddon/`, added as one line at the end of the TOC.
  Each file starts with `local _, ns = ...`; `ns` is the table all files share.
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
| `ns.say(text)` | Prints a line to chat under the addon's name. |
| `ns.Refresh()` | Redraws the window and the arrow after a change. |

An example, `addon/LevelingAddon/Example.lua`:

```lua
local _, ns = ...

ns.charDefaults.visits = 0 -- per character
ns.defaults.greet = true -- account-wide

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

A new game API name goes into `read_globals` in `.luacheckrc`. `/lvl debug` prints the addon's
memory, the last time of each reported piece of work, and the shared loop's time per frame
while standing still and while moving, counted since the previous `/lvl debug`. The targets
for these numbers are not set yet; they are measured in the game (issue #2).

## Layout

```
collector.json          pinned sources and fetch settings
tools/collector/        the C# / .NET 10 collector (runs outside the game)
addon/LevelingAddon/    the addon's Lua: UI shell with a sample route
addon/tests/            smoke test that runs outside the game
docs/                   UI research, decisions and mockups
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
| `manifest.lua` | `ns.Data.manifest`: source commit and counts |
| `data.xml` | Lists every file as a `<Script>`, so the addon's TOC needs one stable line |

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

`parse` needs `git` on the path and takes a few seconds once QuestieDB is checked out. To move to
a newer QuestieDB, change the commit in `collector.json` and run it again.

`fetch` makes one request at a time, waits `delaySeconds` plus jitter between requests, honours
`robots.txt` (including a crawl-delay), and writes every response under
`data/raw/wowhead/<kind>/` with a `.meta.json` beside it. Anything already cached is skipped
without a network request, so re-running a command resumes it. A page that does not exist is
recorded once and not asked for again. A refusal or bot challenge is never cached: the run backs
off, retries, and stops after `maxConsecutiveFailures` in a row.

Browser kinds (`quest`, `list`) open a visible window of the browser named by `browserChannel`.
Nothing about the browser is disguised; if Wowhead still refuses, the run stops.

## Checks

`.github/workflows/ci.yml` runs on every pull request and on every push to `main`. Each job
runs only when something it checks has changed, and is skipped otherwise:

| Job | Runs | When these change |
| --- | --- | --- |
| `collector` | `dotnet build`, `dotnet test` and `dotnet format --verify-no-changes` in `tools/collector` | `tools/collector/`, `collector.json`, `.editorconfig` |
| `lua` | `luacheck .` and `stylua --check .` from the repository root, then the addon's smoke test | any `.lua` file, `.luacheckrc`, `stylua.toml`, `.styluaignore` |

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
[`LICENSE.md`](LICENSE.md). Quest, NPC and item names are Blizzard Entertainment's.
