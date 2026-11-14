using System.Text.Json;
using System.Text.Json.Serialization;

namespace Collector.Parse;

// The normalized data set. Property names become the JSON keys; null and empty values are omitted.

/// <summary>Zone id to the list of [x, y] points (map percentages) in that zone.</summary>
public sealed class Locations : SortedDictionary<int, List<double[]>>;

public sealed record QuestEndpoints(List<int>? Npcs, List<int>? Objects, List<int>? Items)
{
    [JsonIgnore]
    public bool IsEmpty => Npcs is null && Objects is null && Items is null;
}

public sealed record ObjectiveTarget(int Id, string? Text);
public sealed record KillCredit(List<int> NpcIds, int? BaseNpcId, string? Text);
public sealed record SpellObjective(int SpellId, string? Text, int? ItemId);
public sealed record FactionValue(int FactionId, double Value);
public sealed record SkillValue(int SkillId, int Value);
public sealed record EntityRef(string Type, int Id);
public sealed record ExtraObjective(string? Text, int? ObjectiveIndex, Locations? Locations, List<EntityRef>? Refs);
public sealed record Trigger(string? Text, Locations? Locations);

public sealed record QuestObjectives(
    List<ObjectiveTarget>? Npcs,
    List<ObjectiveTarget>? Objects,
    List<ObjectiveTarget>? Items,
    FactionValue? Reputation,
    List<KillCredit>? KillCredits,
    List<SpellObjective>? Spells);

public sealed record Quest
{
    public required int Id { get; init; }
    public string? Name { get; init; }
    /// <summary>"era" when the quest id exists in the Classic Era baseline, "forever" when it was added for Forever.</summary>
    public required string Origin { get; init; }
    public int? Level { get; init; }
    public int? RequiredLevel { get; init; }
    public int? RequiredMaxLevel { get; init; }
    /// <summary>"alliance", "horde" or "both", from the race mask.</summary>
    public required string Side { get; init; }
    public long? RequiredRaces { get; init; }
    public List<string>? Races { get; init; }
    public long? RequiredClasses { get; init; }
    public List<string>? Classes { get; init; }
    public int? ZoneId { get; init; }
    /// <summary>Set instead of a zone for class, profession, event and similar quests.</summary>
    public string? Category { get; init; }
    public int? CategoryId { get; init; }
    public List<string>? ObjectivesText { get; init; }
    public QuestEndpoints? Start { get; init; }
    public QuestEndpoints? End { get; init; }
    public QuestObjectives? Objectives { get; init; }
    public Trigger? TriggerEnd { get; init; }
    public List<ExtraObjective>? ExtraObjectives { get; init; }
    public int? SourceItemId { get; init; }
    public List<int>? RequiredSourceItems { get; init; }
    public int? Xp { get; init; }
    public int? XpLevel { get; init; }
    public List<FactionValue>? ReputationRewards { get; init; }
    public long? QuestFlags { get; init; }
    public long? SpecialFlags { get; init; }
    public bool? Repeatable { get; init; }
    public SkillValue? RequiredSkill { get; init; }
    public List<SkillValue>? RequiredRanks { get; init; }
    public FactionValue? RequiredMinRep { get; init; }
    public FactionValue? RequiredMaxRep { get; init; }
    public int? RequiredSpell { get; init; }
    public int? RequiredSpecialization { get; init; }
}

/// <summary>How one quest depends on, leads to, or excludes others. Only quests with a relation appear.</summary>
public sealed record QuestRelations
{
    public required int QuestId { get; init; }
    /// <summary>Any one of these must be completed first.</summary>
    public List<int>? PreQuestSingle { get; init; }
    /// <summary>All of these must be completed first. QuestieDB's sign is kept: a negative id is its own convention.</summary>
    public List<int>? PreQuestGroup { get; init; }
    public int? NextQuestInChain { get; init; }
    public int? ParentQuest { get; init; }
    public List<int>? ChildQuests { get; init; }
    public List<int>? InGroupWith { get; init; }
    public List<int>? ExclusiveTo { get; init; }
    /// <summary>This quest is an optional lead-in to the named quest.</summary>
    public int? BreadcrumbForQuestId { get; init; }
    public List<int>? Breadcrumbs { get; init; }
    public int? AvailableUntilCompleted { get; init; }
    public int? AvailableStartingWith { get; init; }
    public int? DisabledByQuest { get; init; }

    [JsonIgnore]
    public bool IsEmpty => this == new QuestRelations { QuestId = QuestId };
}

public sealed record Npc
{
    public required int Id { get; init; }
    public string? Name { get; init; }
    public string? SubName { get; init; }
    public int? MinLevel { get; init; }
    public int? MaxLevel { get; init; }
    public int? Rank { get; init; }
    public int? ZoneId { get; init; }
    public int? FactionId { get; init; }
    /// <summary>"A", "H" or "AH": the factions this NPC is friendly to.</summary>
    public string? FriendlyTo { get; init; }
    public long? NpcFlags { get; init; }
    public Locations? Spawns { get; init; }
    public JsonElement? Waypoints { get; init; }
    public List<int>? QuestStarts { get; init; }
    public List<int>? QuestEnds { get; init; }
}

public sealed record GameObject
{
    public required int Id { get; init; }
    public string? Name { get; init; }
    public int? ZoneId { get; init; }
    public int? FactionId { get; init; }
    public Locations? Spawns { get; init; }
    public List<int>? QuestStarts { get; init; }
    public List<int>? QuestEnds { get; init; }
}

public sealed record Item
{
    public required int Id { get; init; }
    public string? Name { get; init; }
    public int? Class { get; init; }
    public int? SubClass { get; init; }
    public int? ItemLevel { get; init; }
    public int? RequiredLevel { get; init; }
    public long? Flags { get; init; }
    public int? StartQuest { get; init; }
    public List<int>? NpcDrops { get; init; }
    public List<int>? ObjectDrops { get; init; }
    public List<int>? ItemDrops { get; init; }
    public List<int>? Vendors { get; init; }
    public List<int>? RelatedQuests { get; init; }
    public List<int>? QuestRewards { get; init; }
}

public sealed record Zone
{
    public required int Id { get; init; }
    /// <summary>QuestieDB's symbol for the zone, e.g. STORMWIND_CITY.</summary>
    public string? Key { get; init; }
    /// <summary>English name: the dungeon table's where there is one, otherwise derived from the symbol.</summary>
    public string? Name { get; init; }
    public int? UiMapId { get; init; }
    public int? ParentZoneId { get; init; }
    public bool? IsDungeon { get; init; }
}

public sealed record ParseFailure(string Type, string Id, string Error);

public sealed record DataSet(
    List<Quest> Quests,
    List<QuestRelations> Relations,
    List<Npc> Npcs,
    List<GameObject> Objects,
    List<Item> Items,
    List<Zone> Zones,
    List<ParseFailure> Failures)
{
    /// <summary>Counts in the source before narrowing to what quests refer to.</summary>
    public required IReadOnlyDictionary<string, int> SourceCounts { get; init; }
}
