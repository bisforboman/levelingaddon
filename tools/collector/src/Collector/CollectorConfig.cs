using System.Text.Json;

namespace Collector;

public sealed record QuestieDbConfig(string Repository, string Commit);

/// <summary>
/// The repository whose <c>Data/Taxi.lua</c> gives flight points and flight times, pinned by
/// commit. The keys are not "repository" and "commit": the nightly update finds QuestieDB's pin
/// in collector.json by those two names.
/// </summary>
public sealed record TaxiConfig(string Source, string Revision);

/// <summary>
/// A fetchable kind of page: where it lives, whether it needs a real browser, and the browser
/// capture a page of this kind must yield to be worth keeping.
/// </summary>
public sealed record KindConfig(string? Url, string Source, string? RequiredCapture = null);

public sealed record WowheadConfig(
    string UserAgent,
    double DelaySeconds,
    double JitterSeconds,
    int MaxConsecutiveFailures,
    string BrowserChannel,
    Dictionary<string, KindConfig> Kinds,
    Dictionary<string, string>? BrowserCaptures,
    int? ReportedQuestCount = null);

/// <summary>
/// How the Lua export names its table, how large one file may grow, and how spawn lists are
/// reduced: a zone's list with more than <paramref name="SpawnMergeAbove"/> points has points
/// within <paramref name="SpawnMergeDistance"/> (map percent) of a kept point merged into it.
/// <paramref name="ClassSpellKeys"/> names, per class token, the spells whose first purchase is
/// exported with <c>key = true</c>.
/// </summary>
public sealed record ExportConfig(string Table = "Data", int MaxConstantsPerFile = 200_000, int SpawnMergeAbove = 10, double SpawnMergeDistance = 2,
    Dictionary<string, string[]>? ClassSpellKeys = null);

public sealed record CollectorConfig(QuestieDbConfig QuestieDb, WowheadConfig Wowhead, ExportConfig? Export = null, TaxiConfig? Taxi = null)
{
    public const string FileName = "collector.json";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public static CollectorConfig Load(string repositoryRoot) =>
        JsonSerializer.Deserialize<CollectorConfig>(File.ReadAllText(Path.Combine(repositoryRoot, FileName)), Json)
        ?? throw new InvalidDataException($"{FileName} is empty");

    /// <summary>The nearest directory at or above <paramref name="start"/> that holds collector.json.</summary>
    public static string FindRepositoryRoot(string start)
    {
        for (var directory = new DirectoryInfo(start); directory is not null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, FileName))) return directory.FullName;
        throw new FileNotFoundException($"No {FileName} found in {start} or any parent directory.");
    }
}
