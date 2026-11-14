using System.Net;

namespace Collector.Fetch;

/// <summary>One thing to fetch. Kind and key decide where it lands in the raw cache.</summary>
public sealed record FetchRequest(string Kind, string Key, Uri Url);

public sealed record FetchResult(
    int Status,
    byte[] Body,
    string? ContentType,
    string Source,
    TimeSpan? RetryAfter = null,
    bool BotChallenge = false,
    IReadOnlyDictionary<string, string>? Captures = null);

public interface IPageSource : IAsyncDisposable
{
    /// <summary>Fetches one URL. Never called concurrently.</summary>
    Task<FetchResult> GetAsync(Uri url, CancellationToken cancellationToken);
}

/// <summary>
/// Plain HTTP over a single connection, identifying itself with the configured user agent.
/// Suits robots.txt and the tooltip JSON endpoint; site pages answer it with a bot challenge.
/// </summary>
public sealed class HttpPageSource : IPageSource
{
    private readonly HttpClient _client;

    public HttpPageSource(string userAgent, HttpMessageHandler? handler = null)
    {
        _client = new HttpClient(handler ?? new SocketsHttpHandler
        {
            MaxConnectionsPerServer = 1,
            AutomaticDecompression = DecompressionMethods.All,
            AllowAutoRedirect = false,
        })
        { Timeout = TimeSpan.FromSeconds(60) };
        _client.DefaultRequestHeaders.UserAgent.ParseAdd(userAgent);
    }

    public async Task<FetchResult> GetAsync(Uri url, CancellationToken cancellationToken)
    {
        using var response = await _client.GetAsync(url, cancellationToken);
        var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        var retryAfter = response.Headers.RetryAfter?.Delta
            ?? (response.Headers.RetryAfter?.Date is { } date ? date - DateTimeOffset.UtcNow : null);
        var challenge = response.Headers.TryGetValues("x-amzn-waf-action", out var actions) && actions.Any();
        return new FetchResult((int)response.StatusCode, body, response.Content.Headers.ContentType?.ToString(),
            "http", retryAfter, challenge);
    }

    public ValueTask DisposeAsync()
    {
        _client.Dispose();
        return ValueTask.CompletedTask;
    }
}
