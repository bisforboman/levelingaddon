# levelingaddon

Data collection for a World of Warcraft: Forever leveling addon. This phase only gathers quest
data; the addon itself (Lua) comes later.

## Status

| Step | State |
| --- | --- |
| Investigation of sources, robots.txt | Done (see "Sources") |
| Polite, resumable fetcher with raw cache | Built and tested against a local test server; not yet run against Wowhead |
| QuestieDB checkout at a pinned commit | Built and tested |
| QuestieDB → normalized JSON | **Not built yet**: waiting on a decision about how to read QuestieDB's Lua files |
| Wowhead list / quest page parsers | Not built: need a few real sample pages first |
| Validation report, JSON → Lua export | Not built |

## Layout

```
collector.json          pinned sources and fetch settings
tools/collector/        the C# / .NET 10 collector (runs outside the game)
data/raw/               raw inputs: QuestieDB checkout, cached Wowhead responses (gitignored)
data/parsed/            normalized JSON, the source of truth (committed; nothing here yet)
```

## Sources

**QuestieDB (primary).** `github.com/Questie/QuestieDB`, pinned by commit in `collector.json`.
It has a Forever dataset with quest givers, turn-ins, NPC and object coordinates per zone,
objectives, prerequisites, chains and breadcrumbs. Its licence intent is GPLv3, so data derived
from it, and an addon shipping that data, must be GPLv3 with attribution to QuestieDB.

**Wowhead (secondary).** For what QuestieDB lacks: money, item rewards, patch and change notes,
and the total quest count to reconcile against. Findings from 2026-11-14:

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

dotnet run --project src/Collector -- questiedb sync
dotnet run --project src/Collector -- fetch quest --ids 2,5,6 --limit 3
dotnet run --project src/Collector -- fetch npc-tooltip --ids-file ids.txt
dotnet run --project src/Collector -- fetch list --urls-file slices.txt
dotnet run --project src/Collector -- status
```

`fetch` makes one request at a time, waits `delaySeconds` plus jitter between requests, honours
`robots.txt` (including a crawl-delay), and writes every response under
`data/raw/wowhead/<kind>/` with a `.meta.json` beside it. Anything already cached is skipped
without a network request, so re-running a command resumes it. A page that does not exist is
recorded once and not asked for again. A refusal or bot challenge is never cached: the run backs
off, retries, and stops after `maxConsecutiveFailures` in a row.

Browser kinds (`quest`, `list`) open a visible window of the browser named by `browserChannel`.
Nothing about the browser is disguised; if Wowhead still refuses, the run stops.
