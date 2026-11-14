using System.Text;

namespace Collector.Fetch;

public sealed record FetchOptions(int? Limit = null, int MaxConsecutiveFailures = 3, TimeSpan? MaxBackOff = null);

public sealed record FetchSummary(int Planned, int AlreadyCached, int Fetched, int NotFound, int RefusedByRobots, int Failed, bool Aborted, string? AbortReason)
{
    public int Remaining => Planned - AlreadyCached - Fetched - NotFound - RefusedByRobots;
}

/// <summary>
/// Works through a list of requests one at a time. Anything already in the raw cache is skipped
/// without touching the network, so an interrupted run resumes where it stopped. Refusals are
/// never cached and never hammered: the runner backs off, retries the same request, and gives up
/// on the whole run after a few in a row.
/// </summary>
public sealed class FetchRunner(
    IPageSource pages,
    IPageSource robotsSource,
    RawCache cache,
    PoliteGate gate,
    string userAgent,
    Action<string>? log = null,
    TimeProvider? clock = null)
{
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private readonly Dictionary<string, RobotsRules> _robots = [];
    private readonly Action<string> _log = log ?? (_ => { });

    public async Task<FetchSummary> RunAsync(IReadOnlyList<FetchRequest> plan, FetchOptions options, CancellationToken cancellationToken)
    {
        int cached = 0, fetched = 0, notFound = 0, refused = 0, failed = 0, consecutive = 0, networkRequests = 0;
        var maxBackOff = options.MaxBackOff ?? TimeSpan.FromMinutes(5);

        FetchSummary Summary(string? abortReason = null) =>
            new(plan.Count, cached, fetched, notFound, refused, failed, abortReason is not null, abortReason);

        for (var index = 0; index < plan.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var request = plan[index];

            if (cache.Has(request))
            {
                cached++;
                continue;
            }

            if (options.Limit is { } limit && networkRequests >= limit)
            {
                _log($"Limit of {limit} network requests reached; {plan.Count - index} request(s) not attempted.");
                break;
            }

            var robots = await RobotsForAsync(request.Url, cancellationToken);
            if (robots is null)
                return Summary($"could not read robots.txt for {request.Url.Host}");
            if (!robots.IsAllowed(request.Url))
            {
                refused++;
                _log($"robots.txt disallows {request.Url.PathAndQuery}; skipped.");
                continue;
            }

            await gate.WaitForTurnAsync(cancellationToken);
            FetchResult? result = null;
            string? error = null;
            try { result = await pages.GetAsync(request.Url, cancellationToken); }
            catch (Exception ex) when (ex is HttpRequestException or TimeoutException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
            {
                error = ex.Message;
            }
            finally { gate.MarkFinished(); }
            networkRequests++;

            if (result is { BotChallenge: false, Status: 200 })
            {
                cache.Write(request, result, _clock.GetUtcNow(), keepBody: true);
                fetched++;
                consecutive = 0;
                _log($"[{index + 1}/{plan.Count}] {request.Kind}/{request.Key}: {result.Body.Length} bytes");
                continue;
            }

            if (result is { BotChallenge: false, Status: 404 or 410 })
            {
                // Remembered, so a missing page is asked for once and never again.
                cache.Write(request, result, _clock.GetUtcNow(), keepBody: false);
                notFound++;
                consecutive = 0;
                _log($"[{index + 1}/{plan.Count}] {request.Kind}/{request.Key}: {result.Status}, recorded as missing");
                continue;
            }

            failed++;
            consecutive++;
            var reason = error ?? (result!.BotChallenge ? $"bot challenge (HTTP {result.Status})" : $"HTTP {result.Status}");
            if (consecutive >= options.MaxConsecutiveFailures)
                return Summary($"{consecutive} consecutive failures, last: {reason} for {request.Url}");

            var backOff = result?.RetryAfter ?? gate.MinimumDelay * Math.Pow(4, consecutive);
            if (backOff > maxBackOff) backOff = maxBackOff;
            _log($"{request.Kind}/{request.Key}: {reason}; nothing cached, backing off {backOff.TotalSeconds:0}s before retrying.");
            await gate.BackOffAsync(backOff, cancellationToken);
            index--; // same request again
        }

        return Summary();
    }

    /// <summary>robots.txt per host, itself read through the cache so it is fetched once.</summary>
    private async Task<RobotsRules?> RobotsForAsync(Uri url, CancellationToken cancellationToken)
    {
        if (_robots.TryGetValue(url.Host, out var known)) return known;

        var request = new FetchRequest("robots", url.Host, new Uri(url, "/robots.txt"));
        if (!cache.Has(request))
        {
            await gate.WaitForTurnAsync(cancellationToken);
            FetchResult result;
            try { result = await robotsSource.GetAsync(request.Url, cancellationToken); }
            catch (HttpRequestException) { return null; }
            finally { gate.MarkFinished(); }

            if (result.BotChallenge || result.Status is not (200 or 404)) return null;
            cache.Write(request, result, _clock.GetUtcNow(), keepBody: result.Status == 200);
        }

        var body = cache.ReadBody(request);
        var rules = body is null ? RobotsRules.AllowAll : RobotsRules.Parse(Encoding.UTF8.GetString(body), userAgent);
        if (rules.CrawlDelay is { } crawlDelay) gate.RequireAtLeast(crawlDelay);
        _log($"robots.txt for {url.Host}: group '{rules.MatchedGroup ?? "none"}'" +
             (rules.CrawlDelay is { } d ? $", crawl-delay {d.TotalSeconds:0}s" : ""));
        return _robots[url.Host] = rules;
    }
}
