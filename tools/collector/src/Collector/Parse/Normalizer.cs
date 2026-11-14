using System.Globalization;
using System.Text.Json;
using Collector.QuestieDb;

namespace Collector.Parse;

/// <summary>
/// Turns QuestieDB's merged rows into the normalized data set. It only reshapes: positional
/// tuples get names, zero "no value" markers become absent, and NPCs, objects and items are
/// narrowed to those a quest refers to. A row that does not have the expected shape is recorded
/// as a failure and left out, never guessed at.
/// </summary>
public sealed class Normalizer
{
    private readonly MergedDatabase _source;
    private readonly List<ParseFailure> _failures = [];
    private readonly Dictionary<string, long> _raceBits = [];
    private readonly Dictionary<string, long> _classBits = [];
    private readonly Dictionary<int, string> _categories = [];
    private readonly HashSet<int> _eraQuestIds;
    private long _allianceMask, _hordeMask;

    public Normalizer(MergedDatabase source)
    {
        _source = source;
        var reference = source.Reference.RootElement;

        foreach (var property in Properties(reference, "raceKeys"))
        {
            var (name, bits) = (property.Name, property.Value.GetInt64());
            if (name == "ALL_ALLIANCE") _allianceMask = bits;
            else if (name == "ALL_HORDE") _hordeMask = bits;
            else if (bits != 0) _raceBits[name] = bits;
        }
        foreach (var property in Properties(reference, "classKeys"))
            if (property.Value.GetInt64() is var bits and not 0 && !property.Name.StartsWith("ALL", StringComparison.Ordinal))
                _classBits[property.Name] = bits;
        foreach (var property in Properties(reference, "sortKeys"))
            _categories[property.Value.GetInt32()] = property.Name;
        _eraQuestIds = reference.TryGetProperty("baseQuestIds", out var ids) ? [.. Lua.Ints(ids) ?? []] : [];
    }

    public DataSet Run()
    {
        var quests = Rows(_source.Quests, "quest", ToQuest);
        var relations = Rows(_source.Quests, "quest relations", ToRelations).Where(r => !r.IsEmpty).ToList();

        // Everything a quest points at, then whatever those items come from.
        var npcIds = new SortedSet<int>();
        var objectIds = new SortedSet<int>();
        var itemIds = new SortedSet<int>();
        foreach (var quest in quests) CollectReferences(quest, npcIds, objectIds, itemIds);

        var allItems = _source.Items.RootElement;
        var pending = new Queue<int>(itemIds);
        while (pending.TryDequeue(out var itemId))
        {
            if (!allItems.TryGetProperty(Key(itemId), out var row)) continue;
            npcIds.UnionWith(Lua.Ints(row, "npcDrops") ?? []);
            npcIds.UnionWith(Lua.Ints(row, "vendors") ?? []);
            objectIds.UnionWith(Lua.Ints(row, "objectDrops") ?? []);
            foreach (var container in Lua.Ints(row, "itemDrops") ?? [])
                if (itemIds.Add(container)) pending.Enqueue(container);
        }

        var npcs = Rows(_source.Npcs, "npc", ToNpc, npcIds);
        var objects = Rows(_source.Objects, "object", ToObject, objectIds);
        var items = Rows(_source.Items, "item", ToItem, itemIds);

        return new DataSet(quests, relations, npcs, objects, items, BuildZones(quests, npcs, objects), _failures)
        {
            SourceCounts = new Dictionary<string, int>
            {
                ["quests"] = _source.Quests.RootElement.EnumerateObject().Count(),
                ["npcs"] = _source.Npcs.RootElement.EnumerateObject().Count(),
                ["objects"] = _source.Objects.RootElement.EnumerateObject().Count(),
                ["items"] = _source.Items.RootElement.EnumerateObject().Count(),
            },
        };
    }

    private List<T> Rows<T>(JsonDocument document, string type, Func<int, JsonElement, T> convert, IReadOnlySet<int>? only = null)
    {
        var result = new List<T>();
        foreach (var (id, property) in document.RootElement.EnumerateObject()
                     .Select(p => (Id: int.Parse(p.Name, CultureInfo.InvariantCulture), Property: p)).OrderBy(p => p.Id))
        {
            if (only is not null && !only.Contains(id)) continue;
            try { result.Add(convert(id, property.Value)); }
            catch (Exception ex) when (ex is InvalidOperationException or FormatException or KeyNotFoundException or OverflowException)
            {
                _failures.Add(new ParseFailure(type, property.Name, ex.Message));
            }
        }
        return result;
    }

    private Quest ToQuest(int id, JsonElement row)
    {
        var races = Lua.Long(row, "requiredRaces") is var mask and not (null or 0) ? mask : null;
        var classes = Lua.Long(row, "requiredClasses") is var classMask and not (null or 0) ? classMask : null;
        var zoneOrSort = Lua.Int(row, "zoneOrSort") ?? 0;
        var specialFlags = Lua.Long(row, "specialFlags");
        var xp = Lua.At(_source.Reference.RootElement.GetProperty("questXp"), id);

        return new Quest
        {
            Id = id,
            Name = Lua.String(row, "name"),
            Origin = _eraQuestIds.Contains(id) ? "era" : "forever",
            Level = Lua.Int(row, "questLevel"),
            RequiredLevel = Lua.Int(row, "requiredLevel"),
            RequiredMaxLevel = Lua.Id(row, "requiredMaxLevel"),
            Side = SideOf(races),
            RequiredRaces = races,
            Races = races is null ? null : Names(_raceBits, races.Value),
            RequiredClasses = classes,
            Classes = classes is null ? null : Names(_classBits, classes.Value),
            ZoneId = zoneOrSort > 0 ? zoneOrSort : null,
            CategoryId = zoneOrSort < 0 ? zoneOrSort : null,
            Category = zoneOrSort < 0 ? _categories.GetValueOrDefault(zoneOrSort) : null,
            ObjectivesText = Lua.Strings(row, "objectivesText"),
            Start = Endpoints(row, "startedBy"),
            End = Endpoints(row, "finishedBy"),
            Objectives = Objectives(row),
            TriggerEnd = row.TryGetProperty("triggerEnd", out var trigger)
                ? new Trigger(Lua.At(trigger, 1)?.GetString(), Lua.Locations(Lua.At(trigger, 2)))
                : null,
            ExtraObjectives = ExtraObjectives(row),
            SourceItemId = Lua.Id(row, "sourceItemId"),
            RequiredSourceItems = Lua.Ints(row, "requiredSourceItems"),
            XpLevel = xp is { } x1 ? Lua.At(x1, 1)?.GetInt32() : null,
            Xp = xp is { } x2 ? Lua.At(x2, 2)?.GetInt32() : null,
            ReputationRewards = Present(Lua.List(row, "reputationReward", Faction)),
            QuestFlags = Lua.Long(row, "questFlags"),
            SpecialFlags = specialFlags,
            Repeatable = specialFlags is { } flags && (flags & 1) != 0 ? true : null,
            RequiredSkill = row.TryGetProperty("requiredSkill", out var skill) ? Skill(skill) : null,
            RequiredRanks = Present(Lua.List(row, "requiredRanks", Skill)),
            RequiredMinRep = row.TryGetProperty("requiredMinRep", out var minRep) ? Faction(minRep) : null,
            RequiredMaxRep = row.TryGetProperty("requiredMaxRep", out var maxRep) ? Faction(maxRep) : null,
            RequiredSpell = Lua.Id(row, "requiredSpell"),
            RequiredSpecialization = Lua.Id(row, "requiredSpecialization"),
        };
    }

    private static QuestRelations ToRelations(int id, JsonElement row) => new()
    {
        QuestId = id,
        PreQuestSingle = Lua.Ints(row, "preQuestSingle"),
        PreQuestGroup = Lua.Ints(row, "preQuestGroup"),
        NextQuestInChain = Lua.Id(row, "nextQuestInChain"),
        ParentQuest = Lua.Id(row, "parentQuest"),
        ChildQuests = Lua.Ints(row, "childQuests"),
        InGroupWith = Lua.Ints(row, "inGroupWith"),
        ExclusiveTo = Lua.Ints(row, "exclusiveTo"),
        BreadcrumbForQuestId = Lua.Id(row, "breadcrumbForQuestId"),
        Breadcrumbs = Lua.Ints(row, "breadcrumbs"),
        AvailableUntilCompleted = Lua.Id(row, "availableUntilCompleted"),
        AvailableStartingWith = Lua.Id(row, "availableStartingWith"),
        DisabledByQuest = Lua.Id(row, "disabledByQuest"),
    };

    private static Npc ToNpc(int id, JsonElement row) => new()
    {
        Id = id,
        Name = Lua.String(row, "name"),
        SubName = Lua.String(row, "subName"),
        MinLevel = Lua.Int(row, "minLevel"),
        MaxLevel = Lua.Int(row, "maxLevel"),
        Rank = Lua.Int(row, "rank"),
        ZoneId = Lua.Id(row, "zoneID"),
        FactionId = Lua.Id(row, "factionID"),
        FriendlyTo = Lua.String(row, "friendlyToFaction"),
        NpcFlags = Lua.Long(row, "npcFlags") is var flags and not (null or 0) ? flags : null,
        Spawns = row.TryGetProperty("spawns", out var spawns) ? Lua.Locations(spawns) : null,
        Waypoints = row.TryGetProperty("waypoints", out var waypoints) ? waypoints.Clone() : null,
        QuestStarts = Lua.Ints(row, "questStarts"),
        QuestEnds = Lua.Ints(row, "questEnds"),
    };

    private static GameObject ToObject(int id, JsonElement row) => new()
    {
        Id = id,
        Name = Lua.String(row, "name"),
        ZoneId = Lua.Id(row, "zoneID"),
        FactionId = Lua.Id(row, "factionID"),
        Spawns = row.TryGetProperty("spawns", out var spawns) ? Lua.Locations(spawns) : null,
        QuestStarts = Lua.Ints(row, "questStarts"),
        QuestEnds = Lua.Ints(row, "questEnds"),
    };

    private static Item ToItem(int id, JsonElement row) => new()
    {
        Id = id,
        Name = Lua.String(row, "name"),
        Class = Lua.Int(row, "class"),
        SubClass = Lua.Int(row, "subClass"),
        ItemLevel = Lua.Int(row, "itemLevel"),
        RequiredLevel = Lua.Int(row, "requiredLevel"),
        Flags = Lua.Long(row, "flags") is var flags and not (null or 0) ? flags : null,
        StartQuest = Lua.Id(row, "startQuest"),
        NpcDrops = Lua.Ints(row, "npcDrops"),
        ObjectDrops = Lua.Ints(row, "objectDrops"),
        ItemDrops = Lua.Ints(row, "itemDrops"),
        Vendors = Lua.Ints(row, "vendors"),
        RelatedQuests = Lua.Ints(row, "relatedQuests"),
        QuestRewards = Lua.Ints(row, "questRewards"),
    };

    // {npcIds?, objectIds?, itemIds?}
    private static QuestEndpoints? Endpoints(JsonElement row, string field)
    {
        if (!row.TryGetProperty(field, out var value)) return null;
        var endpoints = new QuestEndpoints(Lua.Ints(Lua.At(value, 1)), Lua.Ints(Lua.At(value, 2)), Lua.Ints(Lua.At(value, 3)));
        return endpoints.IsEmpty ? null : endpoints;
    }

    // Six positional groups: creature, object, item, reputation, kill credit, spell.
    private static QuestObjectives? Objectives(JsonElement row)
    {
        if (!row.TryGetProperty("objectives", out var value)) return null;

        static List<ObjectiveTarget>? Targets(JsonElement? group) =>
            Lua.List(group, e => new ObjectiveTarget(Lua.At(e, 1)!.Value.GetInt32(), Lua.At(e, 2)?.GetString()));

        var reputation = Lua.At(value, 4);
        var objectives = new QuestObjectives(
            Targets(Lua.At(value, 1)), Targets(Lua.At(value, 2)), Targets(Lua.At(value, 3)),
            reputation is { } rep ? Faction(rep) : null,
            Lua.List(Lua.At(value, 5), e => new KillCredit(Lua.Ints(Lua.At(e, 1)) ?? [], Lua.At(e, 2)?.GetInt32(), Lua.At(e, 3)?.GetString())),
            Lua.List(Lua.At(value, 6), e => new SpellObjective(Lua.At(e, 1)!.Value.GetInt32(), Lua.At(e, 2)?.GetString(), Lua.At(e, 3)?.GetInt32())));
        return objectives == new QuestObjectives(null, null, null, null, null, null) ? null : objectives;
    }

    // {{spawnlist, iconFile, text, objectiveIndex?, {{kind, id}, ...}?}, ...}
    private static List<ExtraObjective>? ExtraObjectives(JsonElement row) =>
        Lua.List(row, "extraObjectives", e => new ExtraObjective(
            Lua.At(e, 3)?.GetString(),
            Lua.At(e, 4)?.GetInt32(),
            Lua.Locations(Lua.At(e, 1)),
            Lua.List(Lua.At(e, 5), r => new EntityRef(Lua.At(r, 1)!.Value.GetString()!, Lua.At(r, 2)!.Value.GetInt32()))));

    // A correction clears a pair by replacing it with an empty table; that reads as "no value".
    private static FactionValue? Faction(JsonElement pair) =>
        Lua.At(pair, 1) is { } faction ? new FactionValue(faction.GetInt32(), Lua.At(pair, 2)?.GetDouble() ?? 0) : null;

    private static SkillValue? Skill(JsonElement pair) =>
        Lua.At(pair, 1) is { } skill ? new SkillValue(skill.GetInt32(), Lua.At(pair, 2)?.GetInt32() ?? 0) : null;

    private static List<T>? Present<T>(List<T?>? values) where T : class =>
        values?.OfType<T>().ToList() is { Count: > 0 } present ? present : null;

    private string SideOf(long? races)
    {
        if (races is null) return "both";
        var alliance = (races.Value & _allianceMask) != 0;
        var horde = (races.Value & _hordeMask) != 0;
        return alliance == horde ? "both" : alliance ? "alliance" : "horde";
    }

    private static List<string>? Names(Dictionary<string, long> bits, long mask)
    {
        var names = bits.Where(b => (mask & b.Value) == b.Value).Select(b => b.Key).Order(StringComparer.Ordinal).ToList();
        return names.Count == 0 ? null : names;
    }

    private static void CollectReferences(Quest quest, ISet<int> npcs, ISet<int> objects, ISet<int> items)
    {
        foreach (var endpoints in new[] { quest.Start, quest.End })
        {
            npcs.UnionWith(endpoints?.Npcs ?? []);
            objects.UnionWith(endpoints?.Objects ?? []);
            items.UnionWith(endpoints?.Items ?? []);
        }
        if (quest.Objectives is { } o)
        {
            npcs.UnionWith(o.Npcs?.Select(t => t.Id) ?? []);
            objects.UnionWith(o.Objects?.Select(t => t.Id) ?? []);
            items.UnionWith(o.Items?.Select(t => t.Id) ?? []);
            foreach (var credit in o.KillCredits ?? [])
            {
                npcs.UnionWith(credit.NpcIds);
                if (credit.BaseNpcId is { } baseId) npcs.Add(baseId);
            }
            items.UnionWith(o.Spells?.Select(s => s.ItemId).OfType<int>() ?? []);
        }
        foreach (var reference in quest.ExtraObjectives?.SelectMany(e => e.Refs ?? []) ?? [])
            (reference.Type switch { "monster" => npcs, "object" => objects, _ => items }).Add(reference.Id);
        if (quest.SourceItemId is { } source) items.Add(source);
        items.UnionWith(quest.RequiredSourceItems ?? []);
    }

    private List<Zone> BuildZones(List<Quest> quests, List<Npc> npcs, List<GameObject> objects)
    {
        var reference = _source.Reference.RootElement;
        var keys = Properties(reference, "zoneIDs").GroupBy(p => p.Value.GetInt32()).ToDictionary(g => g.Key, g => g.Select(p => p.Name).Order(StringComparer.Ordinal).First());
        var uiMaps = reference.GetProperty("areaIdToUiMapId");
        var parents = reference.GetProperty("subZoneToParentZone");
        var dungeons = reference.TryGetProperty("dungeons", out var d) ? d : default;

        var used = new SortedSet<int>();
        used.UnionWith(quests.Select(q => q.ZoneId).OfType<int>());
        used.UnionWith(quests.SelectMany(q => (q.TriggerEnd?.Locations?.Keys ?? Enumerable.Empty<int>()).Concat(q.ExtraObjectives?.SelectMany(e => e.Locations?.Keys ?? Enumerable.Empty<int>()) ?? [])));
        used.UnionWith(npcs.SelectMany(n => (n.Spawns?.Keys ?? Enumerable.Empty<int>()).Append(n.ZoneId ?? 0)));
        used.UnionWith(objects.SelectMany(o => (o.Spawns?.Keys ?? Enumerable.Empty<int>()).Append(o.ZoneId ?? 0)));
        used.Remove(0);

        // Parents of used zones belong in the table too.
        foreach (var id in used.ToList())
            if (ParentOf(id) is { } parent and not 0) used.Add(parent);

        return used.Select(id =>
        {
            var dungeon = dungeons.ValueKind is JsonValueKind.Object or JsonValueKind.Array ? Lua.At(dungeons, id) : null;
            keys.TryGetValue(id, out var key);
            return new Zone
            {
                Id = id,
                Key = key,
                Name = (dungeon is { } entry ? Lua.At(entry, 1)?.GetString() : null) ?? (key is null ? null : TitleCase(key)),
                UiMapId = Lua.At(uiMaps, id)?.GetInt32() is var ui and not (null or 0) ? ui : null,
                ParentZoneId = ParentOf(id),
                IsDungeon = dungeon is not null ? true : null,
            };
        }).ToList();

        int? ParentOf(int id) =>
            Lua.At(parents, id)?.GetInt32() is var parent and not (null or 0) && parent != id ? parent
            : dungeons.ValueKind is JsonValueKind.Object or JsonValueKind.Array && Lua.At(dungeons, id) is { } entry ? Lua.At(entry, 3)?.GetInt32()
            : null;
    }

    private static string TitleCase(string symbol) =>
        CultureInfo.InvariantCulture.TextInfo.ToTitleCase(symbol.Replace('_', ' ').ToLowerInvariant());

    private static IEnumerable<JsonProperty> Properties(JsonElement parent, string name) =>
        parent.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Object ? value.EnumerateObject() : [];

    private static string Key(int id) => id.ToString(CultureInfo.InvariantCulture);
}

/// <summary>
/// Reading Lua values out of their JSON form. A Lua tuple or map arrives as a JSON array when its
/// keys run 1..n without gaps and as an object keyed by index otherwise, so every positional
/// read goes through <see cref="At"/> and every map read through <see cref="Entries"/>.
/// </summary>
internal static class Lua
{
    public static JsonElement? At(JsonElement value, int index)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Array:
                return index >= 1 && index <= value.GetArrayLength() && value[index - 1].ValueKind != JsonValueKind.Null ? value[index - 1] : null;
            case JsonValueKind.Object:
                return value.TryGetProperty(index.ToString(CultureInfo.InvariantCulture), out var found) && found.ValueKind != JsonValueKind.Null ? found : null;
            default:
                return null;
        }
    }

    public static IEnumerable<(int Key, JsonElement Value)> Entries(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Array => value.EnumerateArray().Select((element, index) => (index + 1, element)),
        JsonValueKind.Object => value.EnumerateObject().Select(p => (int.Parse(p.Name, CultureInfo.InvariantCulture), p.Value)),
        _ => throw new InvalidOperationException($"expected a table, found {value.ValueKind}"),
    };

    public static string? String(JsonElement row, string field) =>
        row.TryGetProperty(field, out var value) && value.ValueKind == JsonValueKind.String && value.GetString() is { Length: > 0 } text ? text : null;

    public static int? Int(JsonElement row, string field) => row.TryGetProperty(field, out var value) ? value.GetInt32() : null;

    public static long? Long(JsonElement row, string field) => row.TryGetProperty(field, out var value) ? value.GetInt64() : null;

    /// <summary>An id-like field, where QuestieDB stores 0 for "none".</summary>
    public static int? Id(JsonElement row, string field) => Int(row, field) is var value and not (null or 0) ? value : null;

    public static List<int>? Ints(JsonElement row, string field) => row.TryGetProperty(field, out var value) ? Ints(value) : null;

    public static List<int>? Ints(JsonElement? value)
    {
        if (value is not { } list) return null;
        var result = Entries(list).Select(e => e.Value.GetInt32()).ToList();
        return result.Count == 0 ? null : result;
    }

    public static List<string>? Strings(JsonElement row, string field)
    {
        if (!row.TryGetProperty(field, out var value)) return null;
        var result = Entries(value).Select(e => e.Value.GetString() ?? "").ToList();
        return result.Count == 0 ? null : result;
    }

    public static List<T>? List<T>(JsonElement row, string field, Func<JsonElement, T> convert) =>
        row.TryGetProperty(field, out var value) ? List(value, convert) : null;

    public static List<T>? List<T>(JsonElement? value, Func<JsonElement, T> convert)
    {
        if (value is not { } list) return null;
        var result = Entries(list).Select(e => convert(e.Value)).ToList();
        return result.Count == 0 ? null : result;
    }

    /// <summary>{[zoneId] = {{x, y, phase?}, ...}}</summary>
    public static Locations? Locations(JsonElement? value)
    {
        if (value is not { } map) return null;
        var result = new Locations();
        foreach (var (zone, points) in Entries(map))
            result[zone] = Entries(points).Select(p => Entries(p.Value).Select(n => n.Value.GetDouble()).ToArray()).ToList();
        return result.Count == 0 ? null : result;
    }
}
