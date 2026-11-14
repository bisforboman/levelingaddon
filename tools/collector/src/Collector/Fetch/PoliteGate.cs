namespace Collector.Fetch;

/// <summary>
/// Spaces requests out: each one starts no sooner than the minimum delay (plus random jitter)
/// after the previous one finished. The delay function is injectable so tests do not sleep.
/// </summary>
public sealed class PoliteGate(
    TimeSpan minimumDelay,
    TimeSpan jitter,
    TimeProvider? clock = null,
    Func<TimeSpan, CancellationToken, Task>? delay = null,
    Random? random = null)
{
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay = delay ?? Task.Delay;
    private readonly Random _random = random ?? Random.Shared;
    private DateTimeOffset? _lastFinished;

    public TimeSpan MinimumDelay { get; private set; } = minimumDelay;

    /// <summary>Raises the delay, e.g. to honour a Crawl-delay; never lowers it.</summary>
    public void RequireAtLeast(TimeSpan value)
    {
        if (value > MinimumDelay) MinimumDelay = value;
    }

    public async Task WaitForTurnAsync(CancellationToken cancellationToken)
    {
        if (_lastFinished is not { } last) return;
        var wait = last + MinimumDelay + jitter * _random.NextDouble() - _clock.GetUtcNow();
        if (wait > TimeSpan.Zero) await _delay(wait, cancellationToken);
    }

    /// <summary>An extra pause after a refusal or error.</summary>
    public Task BackOffAsync(TimeSpan duration, CancellationToken cancellationToken) => _delay(duration, cancellationToken);

    public void MarkFinished() => _lastFinished = _clock.GetUtcNow();
}
