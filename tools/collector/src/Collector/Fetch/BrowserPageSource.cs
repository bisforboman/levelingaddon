using Microsoft.Playwright;

namespace Collector.Fetch;

public sealed record BrowserOptions(
    string? Channel = "chrome",
    string? ExecutablePath = null,
    bool Headless = false,
    TimeSpan? ChallengeTimeout = null,
    IReadOnlyDictionary<string, string>? CaptureExpressions = null);

/// <summary>
/// Loads pages in one tab of an ordinary browser, one navigation at a time. Nothing about the
/// browser is altered or hidden; if the site still refuses, the result says so and the runner
/// stops. Images, media and fonts are not requested, since only the document is kept.
/// </summary>
public sealed class BrowserPageSource : IPageSource
{
    private readonly IPlaywright _playwright;
    private readonly IBrowser _browser;
    private readonly IPage _page;
    private readonly BrowserOptions _options;
    private IResponse? _lastDocument;

    private BrowserPageSource(IPlaywright playwright, IBrowser browser, IPage page, BrowserOptions options)
    {
        (_playwright, _browser, _page, _options) = (playwright, browser, page, options);
        _page.Response += (_, response) =>
        {
            if (response.Request.IsNavigationRequest && response.Frame == _page.MainFrame) _lastDocument = response;
        };
    }

    public static async Task<BrowserPageSource> LaunchAsync(BrowserOptions options)
    {
        var playwright = await Playwright.CreateAsync();
        var browser = await playwright.Chromium.LaunchAsync(new BrowserTypeLaunchOptions
        {
            Channel = options.ExecutablePath is null ? options.Channel : null,
            ExecutablePath = options.ExecutablePath,
            Headless = options.Headless,
        });
        var context = await browser.NewContextAsync();
        await context.RouteAsync("**/*", route =>
            route.Request.ResourceType is "image" or "media" or "font" ? route.AbortAsync() : route.ContinueAsync());
        return new BrowserPageSource(playwright, browser, await context.NewPageAsync(), options);
    }

    public async Task<FetchResult> GetAsync(Uri url, CancellationToken cancellationToken)
    {
        _lastDocument = null;
        try
        {
            await _page.GotoAsync(url.ToString(), new PageGotoOptions { WaitUntil = WaitUntilState.DOMContentLoaded, Timeout = 60_000 });

            // A bot check replaces the document and reloads the page once the browser has passed
            // it. Wait for that reload; if it never comes, report the challenge as the outcome.
            var deadline = DateTime.UtcNow + (_options.ChallengeTimeout ?? TimeSpan.FromSeconds(30));
            while (IsChallenge(_lastDocument) && DateTime.UtcNow < deadline)
                await Task.Delay(500, cancellationToken);

            var document = _lastDocument ?? throw new HttpRequestException($"No document response for {url}");
            if (!IsChallenge(document))
                await _page.WaitForLoadStateAsync(LoadState.DOMContentLoaded, new PageWaitForLoadStateOptions { Timeout = 60_000 });

            var body = await document.BodyAsync();
            document.Headers.TryGetValue("content-type", out var contentType);
            return new FetchResult(document.Status, body, contentType, "browser",
                BotChallenge: IsChallenge(document),
                Captures: document.Status == 200 && !IsChallenge(document) ? await CaptureAsync() : null);
        }
        catch (PlaywrightException ex)
        {
            throw new HttpRequestException($"Browser could not load {url}: {ex.Message}", ex);
        }
    }

    private static bool IsChallenge(IResponse? response) =>
        response is not null && response.Headers.ContainsKey("x-amzn-waf-action");

    private async Task<IReadOnlyDictionary<string, string>?> CaptureAsync()
    {
        if (_options.CaptureExpressions is not { Count: > 0 } expressions) return null;
        var captures = new Dictionary<string, string>();
        foreach (var (name, expression) in expressions)
        {
            // Each expression returns a JSON string, or null when the page has nothing to offer.
            var value = await _page.EvaluateAsync<string?>(expression);
            if (!string.IsNullOrEmpty(value) && value != "null") captures[name] = value;
        }
        return captures;
    }

    public async ValueTask DisposeAsync()
    {
        await _browser.DisposeAsync();
        _playwright.Dispose();
    }
}
