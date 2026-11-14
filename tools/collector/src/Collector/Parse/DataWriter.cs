using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Collector.Parse;

/// <summary>
/// Writes the normalized data set as JSON arrays with one entity per line, sorted by id, so the
/// files are stable between runs and a change to one quest is a one-line diff.
/// </summary>
public static class DataWriter
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static void Write(DataSet data, string directory, object manifest)
    {
        Directory.CreateDirectory(directory);
        WriteLines(Path.Combine(directory, "quests.json"), data.Quests);
        WriteLines(Path.Combine(directory, "quest-relations.json"), data.Relations);
        WriteLines(Path.Combine(directory, "npcs.json"), data.Npcs);
        WriteLines(Path.Combine(directory, "objects.json"), data.Objects);
        WriteLines(Path.Combine(directory, "items.json"), data.Items);
        WriteLines(Path.Combine(directory, "zones.json"), data.Zones);
        File.WriteAllText(Path.Combine(directory, "manifest.json"),
            JsonSerializer.Serialize(manifest, new JsonSerializerOptions(Json) { WriteIndented = true }) + "\n");
    }

    public static void WriteLines<T>(string path, IReadOnlyList<T> rows)
    {
        var text = new StringBuilder("[\n");
        for (var i = 0; i < rows.Count; i++)
            text.Append(JsonSerializer.Serialize(rows[i], Json)).Append(i < rows.Count - 1 ? ",\n" : "\n");
        File.WriteAllText(path, text.Append("]\n").ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }
}
