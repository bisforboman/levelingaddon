using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Collector;
using Collector.Export;
using Collector.Fetch;
using Collector.Parse;
using Collector.QuestieDb;

const string Usage = """
    collector <command> [options]        (run from anywhere inside the repository)

      status
          Count what the raw cache holds.

      questiedb sync
          Check out QuestieDB at the commit pinned in collector.json into data/raw/questiedb.

      parse
          Merge QuestieDB (its own code, run in a sandboxed Lua interpreter), write the normalized
          JSON to data/parsed/ and the validation report to reports/.

      export [--out DIRECTORY]
          Write data/parsed/ as Lua table files for the addon (default: data/lua/), then load them
          back in the sandboxed interpreter and check every value against the JSON.

      fetch <kind> (--ids 1,2,3 | --ids-file FILE | --urls-file FILE) [--limit N] [--delay SECONDS]
          Fetch pages of a kind defined in collector.json into data/raw/wowhead/<kind>/.
          One request at a time, spaced out, robots.txt honoured. Cached pages are never fetched
          again, so re-running the same command resumes an interrupted run.
          --limit counts network requests, so `--limit 5` is a five-page trial.
          Browser kinds open a visible browser window; --browser-path overrides the channel.
    """;

if (args.Length == 0 || args[0] is "-h" or "--help")
{
    Console.WriteLine(Usage);
    return 0;
}

var root = CollectorConfig.FindRepositoryRoot(Directory.GetCurrentDirectory());
var config = CollectorConfig.Load(root);
var rawRoot = Path.Combine(root, "data", "raw");
var cache = new RawCache(Path.Combine(rawRoot, "wowhead"));

try
{
    switch (args[0])
    {
        case "status":
            foreach (var kind in cache.Kinds()) Console.WriteLine($"{kind,-16} {cache.Count(kind),6} cached");
            var questieDb = Path.Combine(rawRoot, "questiedb");
            Console.WriteLine($"questiedb        {(Directory.Exists(questieDb) ? "checked out" : "not synced")} (pinned {config.QuestieDb.Commit[..10]})");
            return 0;

        case "questiedb" when args.ElementAtOrDefault(1) == "sync":
            await QuestieDbSync.EnsureAsync(config.QuestieDb, Path.Combine(rawRoot, "questiedb"), Console.WriteLine);
            return 0;

        case "questiedb" when args.ElementAtOrDefault(1) == "lua":
            // Debug aid: run a Lua snippet of ours inside the sandbox, against the checkout.
            Console.WriteLine(QuestieDbMerge.RunSnippet(Path.Combine(rawRoot, "questiedb"), File.ReadAllText(args[2])));
            return 0;

        case "questiedb" when args.ElementAtOrDefault(1) == "inspect":
        {
            // Debug aid: counts, reference data, and the rows named on the command line.
            var merged = QuestieDbMerge.Run(Path.Combine(rawRoot, "questiedb"));
            foreach (var (name, document) in new[] { ("Quest", merged.Quests), ("Npc", merged.Npcs), ("Object", merged.Objects), ("Item", merged.Items) })
            {
                Console.WriteLine($"== {name}: {document.RootElement.EnumerateObject().Count()} rows");
                foreach (var id in args.Skip(2))
                    if (document.RootElement.TryGetProperty(id, out var row)) Console.WriteLine($"   [{id}] {row.GetRawText()}");
            }
            foreach (var property in merged.Reference.RootElement.EnumerateObject())
            {
                var text = property.Value.GetRawText();
                Console.WriteLine($"-- {property.Name}: {(text.Length > 700 ? text[..700] + " ..." : text)}");
            }
            Console.WriteLine(merged.LuaOutput);
            return 0;
        }

        case "parse":
        {
            var checkout = await QuestieDbSync.EnsureAsync(config.QuestieDb, Path.Combine(rawRoot, "questiedb"), Console.WriteLine);
            using var merged = QuestieDbMerge.Run(checkout);
            var data = new Normalizer(merged).Run();
            var source = $"{config.QuestieDb.Repository} at commit {config.QuestieDb.Commit}";
            DataWriter.Write(data, Path.Combine(root, "data", "parsed"), new
            {
                schemaVersion = 1,
                source = new { config.QuestieDb.Repository, config.QuestieDb.Commit, flavor = "Forever", license = "GPL-3.0" },
                counts = new { quests = data.Quests.Count, questRelations = data.Relations.Count, npcs = data.Npcs.Count, objects = data.Objects.Count, items = data.Items.Count, zones = data.Zones.Count },
            });

            var report = Validation.Run(data, config.Wowhead.ReportedQuestCount);
            var reports = Path.Combine(root, "reports");
            Directory.CreateDirectory(reports);
            File.WriteAllText(Path.Combine(reports, "validation.md"), Validation.ToMarkdown(report, source));
            File.WriteAllText(Path.Combine(reports, "validation.json"),
                System.Text.Json.JsonSerializer.Serialize(report, new System.Text.Json.JsonSerializerOptions(DataWriter.Json) { WriteIndented = true }) + "\n");

            Console.WriteLine($"Wrote {data.Quests.Count} quests, {data.Relations.Count} relation rows, {data.Npcs.Count} NPCs, {data.Objects.Count} objects, " +
                              $"{data.Items.Count} items, {data.Zones.Count} zones to data/parsed; {data.Failures.Count} parse failure(s). Report: reports/validation.md");
            return 0;
        }

        case "export":
        {
            var parsed = Path.Combine(root, "data", "parsed");
            var output = Path.GetFullPath(Option(args, "--out") ?? Path.Combine(root, "data", "lua"));
            var exporter = new LuaExporter(config.Export ?? new ExportConfig());
            var export = exporter.Run(parsed, output);
            foreach (var table in export.Tables)
                Console.WriteLine($"{table.Name,-16} {table.Rows,6} rows in {table.Files.Count} file(s), up to {table.LargestLiteralCount} distinct literals per file");
            Console.WriteLine($"Wrote {export.Files.Count} Lua files and data.xml to {output} ({export.Bytes / 1024.0 / 1024.0:0.0} MB).");

            var differences = exporter.Verify(parsed, output, export);
            if (differences.Count == 0)
            {
                Console.WriteLine("Verified: the Lua files load and every value matches data/parsed.");
                return 0;
            }
            Console.Error.WriteLine("Export does not match data/parsed:");
            foreach (var difference in differences) Console.Error.WriteLine("  " + difference);
            return 1;
        }

        case "fetch" when args.Length >= 2:
            return await FetchAsync(args[1], args[2..]);

        default:
            Console.Error.WriteLine(Usage);
            return 2;
    }
}
catch (Exception ex) when (ex is InvalidOperationException or InvalidDataException or FileNotFoundException or ArgumentException)
{
    Console.Error.WriteLine("error: " + ex.Message);
    return 1;
}

async Task<int> FetchAsync(string kindName, string[] options)
{
    if (!config.Wowhead.Kinds.TryGetValue(kindName, out var kind))
        throw new ArgumentException($"Unknown kind '{kindName}'. Known: {string.Join(", ", config.Wowhead.Kinds.Keys)}");

    var plan = BuildPlan(kindName, kind, options);
    var delay = TimeSpan.FromSeconds(double.Parse(Option(options, "--delay") ?? config.Wowhead.DelaySeconds.ToString()));
    var gate = new PoliteGate(delay, TimeSpan.FromSeconds(config.Wowhead.JitterSeconds));
    gate.MarkFinished(); // a previous run may have ended a moment ago, so the first request waits too

    await using var http = new HttpPageSource(config.Wowhead.UserAgent);
    await using IPageSource pages = kind.Source == "browser"
        ? await BrowserPageSource.LaunchAsync(new BrowserOptions(
            Channel: config.Wowhead.BrowserChannel,
            ExecutablePath: Option(options, "--browser-path"),
            Headless: options.Contains("--headless"),
            CaptureExpressions: config.Wowhead.BrowserCaptures))
        : new HttpPageSource(config.Wowhead.UserAgent);

    using var cancel = new CancellationTokenSource();
    Console.CancelKeyPress += (_, e) => { e.Cancel = true; cancel.Cancel(); };

    var runner = new FetchRunner(pages, http, cache, gate, config.Wowhead.UserAgent, Console.WriteLine);
    var limit = Option(options, "--limit") is { } text ? int.Parse(text) : (int?)null;
    FetchSummary summary;
    try
    {
        summary = await runner.RunAsync(plan, new FetchOptions(limit, config.Wowhead.MaxConsecutiveFailures), cancel.Token);
    }
    catch (OperationCanceledException)
    {
        Console.WriteLine("Interrupted. Everything fetched so far is cached; run the same command to resume.");
        return 130;
    }

    Console.WriteLine($"{kindName}: planned {summary.Planned}, already cached {summary.AlreadyCached}, fetched {summary.Fetched}, " +
                      $"missing {summary.NotFound}, disallowed by robots.txt {summary.RefusedByRobots}, failed attempts {summary.Failed}, " +
                      $"still to do {summary.Remaining}.");
    if (!summary.Aborted) return 0;
    Console.Error.WriteLine($"Stopped early: {summary.AbortReason}. Nothing was cached for the failed request.");
    return 1;
}

List<FetchRequest> BuildPlan(string kindName, KindConfig kind, string[] options)
{
    if (Option(options, "--urls-file") is { } urlsFile)
        return ReadLines(urlsFile).Select(line => new Uri(line)).Select(url => new FetchRequest(kindName, KeyForUrl(url), url)).ToList();

    var ids = Option(options, "--ids")?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
              ?? (Option(options, "--ids-file") is { } idsFile ? ReadLines(idsFile) : null)
              ?? throw new ArgumentException("Give --ids, --ids-file or --urls-file.");
    if (kind.Url is null) throw new ArgumentException($"Kind '{kindName}' has no URL template; use --urls-file.");

    return ids.Select(id => long.Parse(id))
        .Distinct()
        .Select(id => new FetchRequest(kindName, id.ToString(), new Uri(kind.Url.Replace("{id}", id.ToString()))))
        .ToList();
}

static string[] ReadLines(string path) =>
    File.ReadAllLines(path).Select(line => line.Trim()).Where(line => line.Length > 0 && !line.StartsWith('#')).ToArray();

// A readable, collision-free file name for an arbitrary URL.
static string KeyForUrl(Uri url)
{
    var slug = Regex.Replace(url.PathAndQuery.Trim('/'), "[^A-Za-z0-9]+", "_");
    if (slug.Length > 80) slug = slug[..80];
    return $"{slug}-{Convert.ToHexStringLower(SHA1.HashData(Encoding.UTF8.GetBytes(url.ToString())))[..8]}";
}

static string? Option(string[] options, string name)
{
    var index = Array.IndexOf(options, name);
    return index >= 0 && index + 1 < options.Length ? options[index + 1] : null;
}
