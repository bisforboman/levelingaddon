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
| JSON → Lua export | Done: `collector export`, checked by loading the files back and in Lua 5.1 |

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

In the window: drag to move, mouse wheel to scroll through the route, the cross on a pending
step skips it, the arrow on a skipped step brings it back.

`lua5.1 addon/tests/smoke.lua addon/LevelingAddon` runs the addon against a stub of the game
API with a fake quest log, and checks tracking, skip and restore, combat folding, the arrow's
direction and distance, and the TomTom hand-off. It cannot check how anything looks; that
needs the game client.

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
directory given with `--out`. It is a plain translation: same field names, nothing dropped, each
entity on one line keyed by its id (the id is the key and is not repeated inside the row).

```lua
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.quests = ns.Data.quests or {}
local t = ns.Data.quests
t[2]={name="Sharptalon's Claw",level=30,side="horde",start={items={16305}},["end"]={npcs={12696}},xp=2450}
```

| Output | Contents |
| --- | --- |
| `quests-N.lua`, `questRelations-N.lua`, `npcs-N.lua`, `objects-N.lua`, `items-N.lua`, `zones-N.lua` | `ns.Data.<table>[id] = row` |
| `manifest.lua` | `ns.Data.manifest`: source commit and counts |
| `data.xml` | Lists every file as a `<Script>`, so the addon's TOC needs one stable line |

Things to know when designing the addon:

- Zone-keyed maps use numeric keys: `npc.spawns[331][1]` is `{x, y}`.
- `end` is a Lua keyword, so a quest's turn-in is `quest["end"]`, not `quest.end`.
- `requiredRaces` can exceed 32 bits (the Skyborne races); the game's `bit` library works on 32
  bits, so use `side` and `races` instead of masking it.
- Lua 5.1 refuses a file with more than 262,143 distinct literals. A table is split into
  numbered files before it gets close; the files can load in any order.
- Loaded in full, the tables take about 47 MB in stock Lua 5.1. The addon will probably want to
  load less or load lazily; that is a design decision this step does not make.

After writing, the command loads every file in the sandboxed interpreter, the way the game
calls an addon file, and compares each value with the JSON. It exits non-zero on any difference.
`data.xml` and loading inside the actual game client have not been tried.

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
| `lua` | `luacheck .` and `stylua --check .` from the repository root | any `.lua` file, `.luacheckrc`, `stylua.toml`, `.styluaignore` |

A change to `ci.yml` itself runs both.

`main` is protected: changes reach it only through a pull request, and both jobs must pass
before it can merge.

The same commands work locally. `dotnet format` without the flag fixes what it reports, and so
does `stylua .`. Code style for the collector is in `.editorconfig`.

The Lua settings are for the addon's source, which does not exist yet, so the `lua` job has no
files to check for now. `data/` is excluded from all three tools: it holds QuestieDB's checkout
and the generated tables.

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
