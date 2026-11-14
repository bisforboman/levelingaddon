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
| JSON → Lua export | Not built (planned as a separate `export` step reading `data/parsed/`) |

## Layout

```
collector.json          pinned sources and fetch settings
tools/collector/        the C# / .NET 10 collector (runs outside the game)
data/raw/               raw inputs: QuestieDB checkout, cached Wowhead responses (gitignored)
data/parsed/            normalized JSON, the source of truth (committed)
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

## Licence

The data in `data/parsed/` is derived from QuestieDB, which its maintainers publish under the
GNU General Public License v3. This repository is therefore licensed under GPL-3.0; see
[`LICENSE.md`](LICENSE.md). Quest, NPC and item names are Blizzard Entertainment's.
