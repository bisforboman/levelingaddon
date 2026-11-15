using System.Text.Json;
using System.Text.RegularExpressions;
using Collector.Fetch;

namespace Collector.Parse;

/// <summary>
/// A spell a class trainer teaches: <c>Class</c> is the client's class token ("MAGE"),
/// <c>Level</c> the level to learn it at, <c>Cost</c> in copper before any discount. <c>Rank</c>
/// only for "Rank N" spells; <c>Races</c> (the client's race ids) only for a spell some races get.
/// </summary>
public sealed record ClassSpell(string Class, int Id, string Name, int? Rank, int Level, int Cost, IReadOnlyList<int>? Races);

/// <param name="TalentRanks">Names left out of a class, "MAGE Pyroblast": see <see cref="ClassSpells.Parse"/>.</param>
public sealed record ClassSpellTables(List<ClassSpell> Spells, List<string> TalentRanks);

/// <summary>
/// The spells each class learns from its trainer (issue #17), from the rows of Wowhead's ability
/// listing of each class as the fetch kept them (README, "Fetching class spells").
/// </summary>
public static partial class ClassSpells
{
    public const string SpellsFile = "class-spells.json", Kind = "class-spells", Capture = "spells";

    public static readonly IReadOnlyList<string> Classes = ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"];

    /// <summary>The skill line of the hunter's pet skills (Great Stamina, Natural Armor), which pet trainers sell.</summary>
    public const int BeastTrainingSkill = 261;

    [GeneratedRegex(@"^Rank (\d+)$")]
    private static partial Regex RankText();

    /// <summary>
    /// The trainer-taught rows of one class's listing. A row is trainer-taught when it has a
    /// training cost; the listing also holds starting spells, talents, books and quest rewards,
    /// which have none.
    /// <para>
    /// Left out: the trained ranks of a spell whose lowest rank on the page is above 1. Rank 1
    /// of those comes from a talent (Pyroblast, Mortal Strike) or belongs to a pet (Growl), and
    /// nothing on the page says which character can buy the rest. An inference, not a field.
    /// </para>
    /// <para>
    /// Also left out: rows of <see cref="BeastTrainingSkill"/>, which the class trainer does not sell.
    /// </para>
    /// </summary>
    public static (List<ClassSpell> Spells, List<string> TalentRanks) Parse(string classToken, JsonElement rows)
    {
        var lowestRank = new Dictionary<string, int>();
        foreach (var row in rows.EnumerateArray())
            if (Rank(row) is { } rank && row.GetProperty("name").GetString() is { } name)
                lowestRank[name] = Math.Min(rank, lowestRank.GetValueOrDefault(name, rank));

        var spells = new List<ClassSpell>();
        var talentRanks = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var row in rows.EnumerateArray())
        {
            if (!row.TryGetProperty("trainingcost", out var cost)) continue;
            if (row.TryGetProperty("skill", out var skills) && skills.EnumerateArray().Any(s => s.GetInt32() == BeastTrainingSkill)) continue;
            var name = row.GetProperty("name").GetString() ?? throw new InvalidDataException($"{classToken}: a spell row has no name: {row.GetRawText()}");
            var rank = Rank(row);
            if (rank is not null && lowestRank[name] > 1)
            {
                talentRanks.Add(name);
                continue;
            }
            var races = row.TryGetProperty("races", out var list) ? list.EnumerateArray().Select(r => r.GetInt32()).ToList() : null;
            spells.Add(new ClassSpell(classToken, row.GetProperty("id").GetInt32(), name, rank, row.GetProperty("level").GetInt32(), cost.GetInt32(), races));
        }
        return (spells.OrderBy(s => s.Level).ThenBy(s => s.Id).ToList(), talentRanks.ToList());
    }

    /// <summary>Every class page in the raw cache. The class is the last part of the page's address.</summary>
    public static ClassSpellTables Build(string cacheDirectory)
    {
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var tables = new ClassSpellTables([], []);
        foreach (var metaPath in Directory.GetFiles(cacheDirectory, "*.meta.json").Order(StringComparer.Ordinal))
        {
            var entry = JsonSerializer.Deserialize<CacheEntry>(File.ReadAllText(metaPath), json)!;
            var classToken = new Uri(entry.Url).Segments[^1].Trim('/').ToUpperInvariant();
            if (!Classes.Contains(classToken)) throw new InvalidDataException($"{entry.Url} is not the ability listing of a class.");
            if (tables.Spells.Any(s => s.Class == classToken)) throw new InvalidDataException($"Two cached pages for {classToken} in {cacheDirectory}.");
            if (entry.CaptureFiles?.GetValueOrDefault(Capture) is not { } capture)
                throw new InvalidDataException($"{entry.Url} was cached without its spell list; fetch it again.");

            using var rows = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(cacheDirectory, capture)));
            var (spells, talentRanks) = Parse(classToken, rows.RootElement);
            if (spells.Count == 0) throw new InvalidDataException($"{entry.Url}: no row has a training cost.");
            tables.Spells.AddRange(spells);
            tables.TalentRanks.AddRange(talentRanks.Select(name => $"{classToken} {name}"));
        }
        // The result replaces the committed file, so a trial fetch of one page must not get that far.
        var missing = Classes.Except(tables.Spells.Select(s => s.Class)).ToList();
        if (missing.Count > 0) throw new InvalidDataException($"No cached page for {string.Join(", ", missing)} in {cacheDirectory}; finish the fetch first.");
        return tables;
    }

    public static void Write(ClassSpellTables tables, string directory) =>
        DataWriter.WriteLines(Path.Combine(directory, SpellsFile), tables.Spells);

    private static int? Rank(JsonElement row) =>
        row.TryGetProperty("rank", out var text) && RankText().Match(text.GetString() ?? "") is { Success: true } match ? int.Parse(match.Groups[1].Value) : null;
}
