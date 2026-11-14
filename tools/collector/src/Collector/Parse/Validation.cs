using System.Text;
using System.Text.RegularExpressions;

namespace Collector.Parse;

public sealed record Finding(string Key, string Title, string Meaning, List<string> Examples, List<int> QuestIds);

public sealed record ValidationReport(
    Dictionary<string, int> Totals,
    int? WowheadReportedQuests,
    List<Finding> Findings,
    List<ParseFailure> ParseFailures);

/// <summary>Checks the normalized data against what a leveling addon needs from each quest.</summary>
public static partial class Validation
{
    public static ValidationReport Run(DataSet data, int? wowheadReportedQuests)
    {
        var npcs = data.Npcs.ToDictionary(n => n.Id);
        var objects = data.Objects.ToDictionary(o => o.Id);
        var items = data.Items.ToDictionary(i => i.Id);
        var questIds = data.Quests.Select(q => q.Id).ToHashSet();

        bool NpcLocated(int id) => npcs.TryGetValue(id, out var npc) && npc.Spawns is { Count: > 0 };
        bool ObjectLocated(int id) => objects.TryGetValue(id, out var obj) && obj.Spawns is { Count: > 0 };
        bool ItemLocated(int id, int depth = 0) =>
            items.TryGetValue(id, out var item) && depth < 3 &&
            ((item.NpcDrops ?? []).Concat(item.Vendors ?? []).Any(NpcLocated) ||
             (item.ObjectDrops ?? []).Any(ObjectLocated) ||
             (item.ItemDrops ?? []).Any(container => ItemLocated(container, depth + 1)));
        bool Located(QuestEndpoints e) =>
            (e.Npcs ?? []).Any(NpcLocated) || (e.Objects ?? []).Any(ObjectLocated) || (e.Items ?? []).Any(id => ItemLocated(id));

        // Instance content is marked with the placeholder point (-1, -1) rather than a map position.
        bool OnlyInstanceMarkers(QuestEndpoints e)
        {
            var points = (e.Npcs ?? []).Select(id => npcs.GetValueOrDefault(id)?.Spawns)
                .Concat((e.Objects ?? []).Select(id => objects.GetValueOrDefault(id)?.Spawns))
                .Where(s => s is not null).SelectMany(s => s!.Values).SelectMany(p => p).ToList();
            return points.Count > 0 && points.All(p => p.Length >= 2 && p[0] < 0 && p[1] < 0);
        }

        IEnumerable<string> Dangling(Quest q)
        {
            foreach (var endpoints in new[] { q.Start, q.End })
            {
                foreach (var id in endpoints?.Npcs ?? []) if (!npcs.ContainsKey(id)) yield return $"npc {id}";
                foreach (var id in endpoints?.Objects ?? []) if (!objects.ContainsKey(id)) yield return $"object {id}";
                foreach (var id in endpoints?.Items ?? []) if (!items.ContainsKey(id)) yield return $"item {id}";
            }
            foreach (var t in q.Objectives?.Npcs ?? []) if (!npcs.ContainsKey(t.Id)) yield return $"npc {t.Id}";
            foreach (var t in q.Objectives?.Objects ?? []) if (!objects.ContainsKey(t.Id)) yield return $"object {t.Id}";
            foreach (var t in q.Objectives?.Items ?? []) if (!items.ContainsKey(t.Id)) yield return $"item {t.Id}";
        }

        var relations = data.Relations.ToDictionary(r => r.QuestId);
        IEnumerable<int> RelationTargets(QuestRelations r) =>
            new[] { r.PreQuestSingle, r.PreQuestGroup, r.ChildQuests, r.InGroupWith, r.ExclusiveTo, r.Breadcrumbs }
                .SelectMany(list => list ?? [])
                .Concat(new[] { r.NextQuestInChain, r.ParentQuest, r.BreadcrumbForQuestId, r.AvailableUntilCompleted, r.AvailableStartingWith, r.DisabledByQuest }.OfType<int>());

        var findings = new List<Finding>();
        void Check(string key, string title, string meaning, Func<Quest, string?> problem)
        {
            var hits = data.Quests.Select(q => (Quest: q, Detail: problem(q))).Where(h => h.Detail is not null).ToList();
            findings.Add(new Finding(key, title, meaning,
                hits.Take(12).Select(h => $"{h.Quest.Id} {h.Quest.Name}{(h.Detail!.Length > 0 ? $" ({h.Detail})" : "")}").ToList(),
                hits.Select(h => h.Quest.Id).ToList()));
        }

        Check("missing-giver", "No quest giver", "No NPC, object or item starts the quest.",
            q => q.Start is null ? "" : null);
        Check("missing-turn-in", "No turn-in", "No NPC or object ends the quest.",
            q => q.End is null ? "" : null);
        Check("giver-without-coordinates", "Quest giver has no coordinates",
            "A giver is named, but neither it nor (for item starts) any source of the item has a spawn point.",
            q => q.Start is { } s && !Located(s) ? "" : null);
        Check("turn-in-without-coordinates", "Turn-in has no coordinates",
            "A turn-in is named, but it has no spawn point.",
            q => q.End is { } e && !Located(e) ? "" : null);
        Check("giver-instance-only", "Quest giver located only by an instance marker",
            "Every spawn point of the giver is the (-1, -1) placeholder used for dungeons and raids, so there is no map position.",
            q => q.Start is { } s && OnlyInstanceMarkers(s) ? "" : null);
        Check("dangling-reference", "Refers to an NPC, object or item that is not in the database",
            "A start, end or objective id has no row in QuestieDB.",
            q => Dangling(q).Distinct().ToList() is { Count: > 0 } missing ? string.Join(", ", missing.Take(4)) : null);
        Check("unknown-related-quest", "Relation points at a quest that is not in the database",
            "A prerequisite, chain, group or breadcrumb id has no quest row.",
            q => relations.TryGetValue(q.Id, out var r) && RelationTargets(r).Where(id => !questIds.Contains(Math.Abs(id))).Distinct().ToList() is { Count: > 0 } unknown
                ? "-> " + string.Join(", ", unknown.Take(5)) : null);
        Check("missing-xp", "No XP value", "QuestieDB's XP table has no entry for the quest.",
            q => q.Xp is null ? "" : null);
        Check("missing-level", "No quest level or required level", "Neither level is set, so the quest cannot be placed in a level range.",
            q => q.Level is null or 0 && q.RequiredLevel is null or 0 ? "" : null);
        Check("missing-name", "No name", "The quest row has no name.",
            q => q.Name is null ? "" : null);
        Check("looks-unused", "Name suggests a test or retired quest",
            "The name carries a marker such as <UNUSED>, [DEPRECATED], zzOLD or TEST. Kept in the data; listed so they can be excluded later.",
            q => q.Name is { } name && UnusedMarker().IsMatch(name) ? "" : null);

        var totals = new Dictionary<string, int>
        {
            ["quests"] = data.Quests.Count,
            ["questsFromEraBaseline"] = data.Quests.Count(q => q.Origin == "era"),
            ["questsAddedForForever"] = data.Quests.Count(q => q.Origin == "forever"),
            ["questsAllianceOnly"] = data.Quests.Count(q => q.Side == "alliance"),
            ["questsHordeOnly"] = data.Quests.Count(q => q.Side == "horde"),
            ["questsBothSides"] = data.Quests.Count(q => q.Side == "both"),
            ["questsWithRelations"] = data.Relations.Count,
            ["npcs"] = data.Npcs.Count,
            ["npcsInSource"] = data.SourceCounts["npcs"],
            ["objects"] = data.Objects.Count,
            ["objectsInSource"] = data.SourceCounts["objects"],
            ["items"] = data.Items.Count,
            ["itemsInSource"] = data.SourceCounts["items"],
            ["zones"] = data.Zones.Count,
        };
        return new ValidationReport(totals, wowheadReportedQuests, findings, data.Failures);
    }

    public static string ToMarkdown(ValidationReport report, string sourceDescription)
    {
        var text = new StringBuilder();
        var quests = report.Totals["quests"];
        text.AppendLine("# Validation report").AppendLine();
        text.AppendLine($"Source: {sourceDescription}").AppendLine();
        text.AppendLine("Generated by `collector parse`. Full id lists are in `validation.json`.").AppendLine();

        text.AppendLine("## Totals").AppendLine();
        text.AppendLine("| | Count |").AppendLine("| --- | ---: |");
        text.AppendLine($"| Quests | {quests} |");
        if (report.WowheadReportedQuests is { } reported)
            text.AppendLine($"| Quests Wowhead reports | {reported} |").AppendLine($"| Difference | {reported - quests} |");
        text.AppendLine($"| From the Classic Era baseline | {report.Totals["questsFromEraBaseline"]} |");
        text.AppendLine($"| Added for Forever | {report.Totals["questsAddedForForever"]} |");
        text.AppendLine($"| Alliance only / Horde only / both | {report.Totals["questsAllianceOnly"]} / {report.Totals["questsHordeOnly"]} / {report.Totals["questsBothSides"]} |");
        text.AppendLine($"| Quests with at least one relation | {report.Totals["questsWithRelations"]} |");
        text.AppendLine($"| NPCs referenced by quests (of {report.Totals["npcsInSource"]} in source) | {report.Totals["npcs"]} |");
        text.AppendLine($"| Objects referenced by quests (of {report.Totals["objectsInSource"]} in source) | {report.Totals["objects"]} |");
        text.AppendLine($"| Items referenced by quests (of {report.Totals["itemsInSource"]} in source) | {report.Totals["items"]} |");
        text.AppendLine($"| Zones | {report.Totals["zones"]} |").AppendLine();
        if (report.WowheadReportedQuests is not null)
            text.AppendLine("The difference from Wowhead cannot be broken down by quest until the Wowhead list pages have been fetched; only the totals can be compared.").AppendLine();

        text.AppendLine("## Findings").AppendLine();
        text.AppendLine("| Finding | Quests | Share |").AppendLine("| --- | ---: | ---: |");
        foreach (var finding in report.Findings)
            text.AppendLine($"| {finding.Title} | {finding.QuestIds.Count} | {100.0 * finding.QuestIds.Count / Math.Max(1, quests):0.0}% |");
        text.AppendLine($"| Rows that could not be parsed | {report.ParseFailures.Count} | |").AppendLine();

        foreach (var finding in report.Findings.Where(f => f.QuestIds.Count > 0))
        {
            text.AppendLine($"### {finding.Title} ({finding.QuestIds.Count})").AppendLine();
            text.AppendLine(finding.Meaning).AppendLine();
            foreach (var example in finding.Examples) text.AppendLine($"- {example}");
            if (finding.QuestIds.Count > finding.Examples.Count) text.AppendLine($"- ... and {finding.QuestIds.Count - finding.Examples.Count} more");
            text.AppendLine();
        }

        text.AppendLine($"## Parse failures ({report.ParseFailures.Count})").AppendLine();
        if (report.ParseFailures.Count == 0) text.AppendLine("None.");
        foreach (var failure in report.ParseFailures.Take(50)) text.AppendLine($"- {failure.Type} {failure.Id}: {failure.Error}");
        return text.ToString();
    }

    [GeneratedRegex(@"<(UNUSED|NYI|TXT|TEST|DEPRECATED)>|\[(DEPRECATED|PH|UNUSED|OLD|NYI)\]|\b(DEPRECATED|REUSE|UNUSED|zzOLD|TEST)\b|^(zz|ZZ)", RegexOptions.CultureInvariant)]
    private static partial Regex UnusedMarker();
}
