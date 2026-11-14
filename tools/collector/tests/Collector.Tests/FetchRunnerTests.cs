using System.Text;
using Collector.Fetch;

namespace Collector.Tests;

public sealed class FetchRunnerTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("collector-tests-").FullName;
    private readonly FakeClock _clock = new();
    private readonly List<TimeSpan> _waits = [];

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    private const string Robots = """
        User-agent: Scrapy
        Disallow: /

        User-agent: *
        Disallow: /forever/list
        Disallow: /forever/search
        """;

    private (FetchRunner Runner, RawCache Cache, FakeSource Pages, PoliteGate Gate) Build(Func<Uri, FetchResult> respond, string robots = Robots)
    {
        var cache = new RawCache(_directory);
        var pages = new FakeSource(respond);
        var robotsSource = new FakeSource(_ => Ok(robots, "text/plain"));
        var gate = new PoliteGate(TimeSpan.FromSeconds(5), TimeSpan.Zero, _clock, (wait, _) =>
        {
            _waits.Add(wait);
            _clock.Advance(wait);
            return Task.CompletedTask;
        });
        return (new FetchRunner(pages, robotsSource, cache, gate, "quest-data-collector/0.1", clock: _clock), cache, pages, gate);
    }

    private static FetchResult Ok(string body, string contentType = "text/html") =>
        new(200, Encoding.UTF8.GetBytes(body), contentType, "fake");

    private static List<FetchRequest> Quests(params int[] ids) =>
        ids.Select(id => new FetchRequest("quest", id.ToString(), new Uri($"https://example.test/forever/quest={id}"))).ToList();

    [Fact]
    public async Task Cached_pages_are_never_fetched_again()
    {
        var (runner, cache, pages, _) = Build(url => Ok("page " + url));

        var first = await runner.RunAsync(Quests(1, 2, 3), new FetchOptions(), default);
        var second = await runner.RunAsync(Quests(1, 2, 3, 4), new FetchOptions(), default);

        Assert.Equal(3, first.Fetched);
        Assert.Equal((3, 1), (second.AlreadyCached, second.Fetched));
        Assert.Equal(4, pages.Requests.Count);
        Assert.Equal("page https://example.test/forever/quest=2", Encoding.UTF8.GetString(cache.ReadBody(Quests(2)[0])!));
    }

    [Fact]
    public async Task Requests_are_spaced_by_the_minimum_delay()
    {
        var (runner, _, pages, _) = Build(_ => Ok("x"));

        await runner.RunAsync(Quests(1, 2, 3), new FetchOptions(), default);

        // robots.txt first, then three pages: every gap is the full delay.
        Assert.Equal(3, pages.Requests.Count);
        Assert.Equal([TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5)], _waits);
    }

    [Fact]
    public async Task Limit_counts_network_requests_and_leaves_the_rest_for_later()
    {
        var (runner, _, pages, _) = Build(_ => Ok("x"));

        var summary = await runner.RunAsync(Quests(1, 2, 3, 4, 5), new FetchOptions(Limit: 2), default);

        Assert.Equal((2, 3), (summary.Fetched, summary.Remaining));
        Assert.Equal(2, pages.Requests.Count);
    }

    [Fact]
    public async Task Missing_pages_are_remembered_without_a_body()
    {
        var (runner, cache, pages, _) = Build(_ => new FetchResult(404, [], "text/html", "fake"));

        await runner.RunAsync(Quests(7), new FetchOptions(), default);
        var again = await runner.RunAsync(Quests(7), new FetchOptions(), default);

        Assert.Single(pages.Requests);
        Assert.Equal(1, again.AlreadyCached);
        Assert.Equal(404, cache.Read(Quests(7)[0])!.Status);
        Assert.Null(cache.ReadBody(Quests(7)[0]));
    }

    [Fact]
    public async Task A_bot_challenge_is_not_cached_and_stops_the_run_after_repeated_refusals()
    {
        var (runner, cache, pages, _) = Build(_ => new FetchResult(202, [], "text/html", "fake", BotChallenge: true));

        var summary = await runner.RunAsync(Quests(1, 2), new FetchOptions(MaxConsecutiveFailures: 3), default);

        Assert.True(summary.Aborted);
        Assert.Contains("bot challenge", summary.AbortReason);
        Assert.Equal(3, pages.Requests.Count);
        Assert.All(pages.Requests, url => Assert.EndsWith("quest=1", url.ToString()));
        Assert.False(cache.Has(Quests(1)[0]));
        // Back-off grows between attempts: 5s x 4, then 5s x 16.
        Assert.Contains(TimeSpan.FromSeconds(20), _waits);
        Assert.Contains(TimeSpan.FromSeconds(80), _waits);
    }

    [Fact]
    public async Task A_transient_error_is_retried_and_honours_retry_after()
    {
        var attempts = 0;
        var (runner, cache, _, _) = Build(_ => ++attempts == 1
            ? new FetchResult(429, [], null, "fake", RetryAfter: TimeSpan.FromSeconds(42))
            : Ok("fine"));

        var summary = await runner.RunAsync(Quests(1), new FetchOptions(), default);

        Assert.Equal((1, 1, false), (summary.Fetched, summary.Failed, summary.Aborted));
        Assert.Contains(TimeSpan.FromSeconds(42), _waits);
        Assert.True(cache.Has(Quests(1)[0]));
    }

    [Fact]
    public async Task Paths_disallowed_by_robots_are_not_requested()
    {
        var (runner, _, pages, _) = Build(_ => Ok("x"));
        var plan = new List<FetchRequest>
        {
            new("list", "a", new Uri("https://example.test/forever/list=123")),
            new("list", "b", new Uri("https://example.test/forever/quests")),
        };

        var summary = await runner.RunAsync(plan, new FetchOptions(), default);

        Assert.Equal((1, 1), (summary.RefusedByRobots, summary.Fetched));
        Assert.Equal("/forever/quests", Assert.Single(pages.Requests).AbsolutePath);
    }

    [Fact]
    public async Task Crawl_delay_from_robots_raises_the_gap()
    {
        var (runner, _, _, gate) = Build(_ => Ok("x"), "User-agent: *\nCrawl-delay: 30\n");

        await runner.RunAsync(Quests(1, 2), new FetchOptions(), default);

        Assert.Equal(TimeSpan.FromSeconds(30), gate.MinimumDelay);
        Assert.Equal(TimeSpan.FromSeconds(30), _waits.Last());
    }

    [Fact]
    public async Task Browser_captures_are_stored_beside_the_page()
    {
        var (runner, cache, _, _) = Build(_ => Ok("<html>") with { Captures = new Dictionary<string, string> { ["listview"] = "[{\"id\":2}]" } });
        var request = new FetchRequest("list", "all", new Uri("https://example.test/forever/quests"));

        await runner.RunAsync([request], new FetchOptions(), default);

        var entry = cache.Read(request)!;
        Assert.Equal("all.listview.json", entry.CaptureFiles!["listview"]);
        Assert.Equal("[{\"id\":2}]", File.ReadAllText(Path.Combine(cache.Root, "list", "all.listview.json")));
    }

    [Fact]
    public async Task A_page_without_the_required_capture_stops_the_run_and_is_not_cached()
    {
        // The first class page has the spell list; the second loads but has no such list.
        var (runner, cache, pages, _) = Build(url => url.AbsolutePath.EndsWith("warrior")
            ? Ok("<html>") with { Captures = new Dictionary<string, string> { ["spells"] = "[{\"id\":78,\"level\":1}]" } }
            : Ok("<html>no list</html>") with { Captures = new Dictionary<string, string> { ["listview"] = "[]" } });
        var plan = new[] { "warrior", "mage", "priest" }
            .Select(name => new FetchRequest("class-spells", name, new Uri($"https://example.test/forever/spells/abilities/{name}"))).ToList();

        var summary = await runner.RunAsync(plan, new FetchOptions(RequiredCapture: "spells"), default);

        Assert.True(summary.Aborted);
        Assert.Contains("capture 'spells' found nothing", summary.AbortReason);
        Assert.Contains("/forever/spells/abilities/mage", summary.AbortReason);
        Assert.Equal((1, 1, 2), (summary.Fetched, summary.Failed, summary.Remaining));
        Assert.Equal(2, pages.Requests.Count); // no retry, and the third page is not asked for
        Assert.Equal("[{\"id\":78,\"level\":1}]", File.ReadAllText(Path.Combine(cache.Root, "class-spells", "warrior.spells.json")));
        Assert.False(cache.Has(plan[1]));
        Assert.Equal(1, cache.Count("class-spells"));
        Assert.Equal("<html>no list</html>", File.ReadAllText(Path.Combine(cache.Root, "class-spells", "mage.rejected.html")));
    }

    [Fact]
    public void Collector_json_defines_the_class_spell_fetch()
    {
        var root = CollectorConfig.FindRepositoryRoot(AppContext.BaseDirectory);
        var wowhead = CollectorConfig.Load(root).Wowhead;

        var kind = wowhead.Kinds["class-spells"];
        Assert.Equal("browser", kind.Source);
        Assert.Contains(kind.RequiredCapture!, wowhead.BrowserCaptures!.Keys);

        var urls = File.ReadAllLines(Path.Combine(root, "tools", "collector", "class-spells.txt"))
            .Where(line => line.Length > 0 && !line.StartsWith('#')).Select(line => new Uri(line)).ToList();
        Assert.Equal(9, urls.Distinct().Count());
        Assert.All(urls, url => Assert.StartsWith("/forever/", url.AbsolutePath));
    }

    private sealed class FakeSource(Func<Uri, FetchResult> respond) : IPageSource
    {
        public List<Uri> Requests { get; } = [];

        public Task<FetchResult> GetAsync(Uri url, CancellationToken cancellationToken)
        {
            Requests.Add(url);
            return Task.FromResult(respond(url));
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class FakeClock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 11, 14, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan by) => _now += by;
    }
}
