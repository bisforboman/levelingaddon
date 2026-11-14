using System.Text.Json;

namespace Collector;

public sealed record QuestieDbConfig(string Repository, string Commit);

/// <summary>A fetchable kind of page: where it lives and whether it needs a real browser.</summary>
public sealed record KindConfig(string? Url, string Source);

public sealed record WowheadConfig(
    string UserAgent,
    double DelaySeconds,
    double JitterSeconds,
    int MaxConsecutiveFailures,
    string BrowserChannel,
    Dictionary<string, KindConfig> Kinds,
    Dictionary<string, string>? BrowserCaptures,
    int? ReportedQuestCount = null);

/// <summary>How the Lua export names its table and how large one file may grow.</summary>
public sealed record ExportConfig(string Table = "Data", int MaxConstantsPerFile = 200_000);

public sealed record CollectorConfig(QuestieDbConfig QuestieDb, WowheadConfig Wowhead, ExportConfig? Export = null)
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
