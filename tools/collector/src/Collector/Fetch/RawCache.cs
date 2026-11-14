using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Collector.Fetch;

/// <summary>What was stored for one request. The sidecar file doubles as the "this is cached" marker.</summary>
public sealed record CacheEntry(
    string Url,
    int Status,
    string? ContentType,
    DateTimeOffset FetchedAtUtc,
    string Source,
    long Bytes,
    string? Sha256,
    string? BodyFile,
    IReadOnlyDictionary<string, string>? CaptureFiles = null);

/// <summary>
/// Raw responses on disk, one body file plus one <c>.meta.json</c> per request. An entry exists
/// only once its meta file does, and the meta file is written last, so an interrupted run leaves
/// either a complete entry or nothing that counts as one.
/// </summary>
public sealed class RawCache(string rootDirectory)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    public string Root { get; } = Path.GetFullPath(rootDirectory);

    private string MetaPath(FetchRequest request) => Path.Combine(Root, request.Kind, request.Key + ".meta.json");

    public bool Has(FetchRequest request) => File.Exists(MetaPath(request));

    public CacheEntry? Read(FetchRequest request)
    {
        var path = MetaPath(request);
        return File.Exists(path) ? JsonSerializer.Deserialize<CacheEntry>(File.ReadAllText(path), Json) : null;
    }

    public byte[]? ReadBody(FetchRequest request)
    {
        var entry = Read(request);
        return entry?.BodyFile is null ? null : File.ReadAllBytes(Path.Combine(Root, request.Kind, entry.BodyFile));
    }

    /// <summary>Stores a response. A null body records the status only (used for 404s).</summary>
    public CacheEntry Write(FetchRequest request, FetchResult result, DateTimeOffset now, bool keepBody)
    {
        var directory = Path.Combine(Root, request.Kind);
        Directory.CreateDirectory(directory);

        string? bodyFile = null;
        string? sha = null;
        if (keepBody)
        {
            bodyFile = request.Key + ExtensionFor(result.ContentType);
            WriteAtomically(Path.Combine(directory, bodyFile), result.Body);
            sha = Convert.ToHexStringLower(SHA256.HashData(result.Body));
        }

        // Values a browser evaluated on the page (e.g. the list data) go in files of their own.
        Dictionary<string, string>? captureFiles = null;
        if (keepBody && result.Captures is { Count: > 0 })
        {
            captureFiles = [];
            foreach (var (name, content) in result.Captures)
            {
                var file = $"{request.Key}.{name}.json";
                WriteAtomically(Path.Combine(directory, file), Encoding.UTF8.GetBytes(content));
                captureFiles[name] = file;
            }
        }

        var entry = new CacheEntry(request.Url.ToString(), result.Status, result.ContentType, now, result.Source,
            keepBody ? result.Body.LongLength : 0, sha, bodyFile, captureFiles);
        WriteAtomically(MetaPath(request), JsonSerializer.SerializeToUtf8Bytes(entry, Json));
        return entry;
    }

    public int Count(string kind)
    {
        var directory = Path.Combine(Root, kind);
        return Directory.Exists(directory) ? Directory.GetFiles(directory, "*.meta.json").Length : 0;
    }

    public IEnumerable<string> Kinds() =>
        Directory.Exists(Root) ? Directory.GetDirectories(Root).Select(Path.GetFileName).OfType<string>().Order() : [];

    private static void WriteAtomically(string path, byte[] content)
    {
        var temp = path + ".tmp";
        File.WriteAllBytes(temp, content);
        File.Move(temp, path, overwrite: true);
    }

    private static string ExtensionFor(string? contentType) => contentType?.Split(';')[0].Trim().ToLowerInvariant() switch
    {
        "application/json" => ".json",
        "text/html" => ".html",
        "text/plain" => ".txt",
        _ => ".bin",
    };
}
