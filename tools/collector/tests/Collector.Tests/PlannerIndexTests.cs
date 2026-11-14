using System.Text.Json;
using Collector.Export;
using Collector.Parse;

namespace Collector.Tests;

public sealed class PlannerIndexTests
{
    // A small world: Elwynn (zone 12, map 1429) with the sub-zone Northshire (9), Westfall (40,
    // map 1436), the Deadmines (1581, an instance under Westfall), Molten Core (2717, a raid),
    // Warsong Gulch (3277, a battleground) and a city zone flagged isDungeon that has no map.
    private static readonly List<Zone> Zones =
    [
        new() { Id = 9, UiMapId = 1429, ParentZoneId = 12 },
        new() { Id = 12, Name = "Elwynn Forest", UiMapId = 1429 },
        new() { Id = 40, Name = "Westfall", UiMapId = 1436 },
        new() { Id = 1581, Name = "The Deadmines", UiMapId = 291, ParentZoneId = 40, IsDungeon = true },
        new() { Id = 2717, Name = "Molten Core", UiMapId = 232, IsDungeon = true },
        new() { Id = 3277, Name = "Warsong Gulch", UiMapId = 1460, IsDungeon = true },
        new() { Id = 16544, Name = "City of Dalaran", ParentZoneId = 12, IsDungeon = true },
    ];

    private static Locations At(int zone, params double[] xy)
    {
        var points = new List<double[]>();
        for (var i = 0; i < xy.Length; i += 2) points.Add([xy[i], xy[i + 1]]);
        return new Locations { [zone] = points };
    }

    private static readonly List<Npc> Npcs =
    [
        new() { Id = 1, Name = "Giver", Spawns = At(12, 48.2, 42.9) },
        new() { Id = 2, Name = "Taker", Spawns = new Locations { [12] = [[10, 10]], [40] = [[56.3, 47.5]] } },
        // Five spawns: the mean is (30, 30), and (31, 30) is the spawn nearest to it.
        new() { Id = 3, Name = "Kobold", Rank = 0, Spawns = At(12, 20, 20, 40, 40, 31, 30, 20, 40, 39, 20, -1, -1) },
        new() { Id = 4, Name = "Elite", Rank = 1, Spawns = At(12, 60, 60) },
        new() { Id = 5, Name = "Boss", Rank = 1, Spawns = At(1581, -1, -1) },
        new() { Id = 6, Name = "Sub-zone Giver", Spawns = At(9, 50, 50) },
    ];

    private static readonly List<GameObject> Objects = [new() { Id = 7, Name = "Crate", Spawns = At(40, 30, 30) }];

    private static readonly List<Item> Items =
    [
        new() { Id = 10, Name = "Kobold Ear", NpcDrops = [3], ObjectDrops = [7] },
        new() { Id = 11, Name = "Elite Fang", NpcDrops = [4] },
        new() { Id = 12, Name = "Boss Head", NpcDrops = [5] },
    ];

    private static Quest Quest(int id, int level = 5, int requiredLevel = 1, string side = "alliance") => new()
    {
        Id = id,
        Name = "Quest " + id,
        Origin = "era",
        Level = level,
        RequiredLevel = requiredLevel,
        Side = side,
        ZoneId = 12,
        Start = new QuestEndpoints([1], null, null),
        End = new QuestEndpoints([2], null, null),
    };

    private static (Dictionary<int, JsonElement> Quests, Dictionary<int, JsonElement> Zones) Build(List<Quest> quests, List<QuestRelations>? relations = null)
    {
        var tables = PlannerIndex.Build(quests, relations ?? [], Npcs, Objects, Items, Zones);
        Dictionary<int, JsonElement> ById(JsonElement rows) => rows.EnumerateArray().ToDictionary(r => r.GetProperty("id").GetInt32());
        return (ById(tables.Quests), ById(tables.Zones));
    }

    private static string Json(JsonElement row, string property) => row.TryGetProperty(property, out var value) ? value.GetRawText() : "(none)";

    [Fact]
    public void A_quest_row_carries_what_eligibility_and_ranking_need()
    {
        var quest = Quest(100, level: 12, requiredLevel: 9) with
        {
            RequiredMaxLevel = 20,
            Races = ["HUMAN", "NIGHT_ELF", "UNDEAD"],
            Classes = ["PALADIN", "WARRIOR"],
            Xp = 840,
            RequiredSkill = new SkillValue(185, 50),
            RequiredMinRep = new FactionValue(72, 3000),
            RequiredMaxRep = new FactionValue(21, -6000),
        };
        var relations = new QuestRelations { QuestId = 100, PreQuestSingle = [1, 2], PreQuestGroup = [-3, 4], ExclusiveTo = [5], BreadcrumbForQuestId = 6, NextQuestInChain = 7, ParentQuest = 8 };

        // A second quest, so that the first one's races are not everyone on its side.
        var row = Build([quest, Quest(101) with { Races = ["DWARF", "HUMAN", "NIGHT_ELF", "UNDEAD"] }], [relations]).Quests[100];

        Assert.Equal(
            """{"id":100,"name":"Quest 100","level":12,"req":9,"maxLevel":20,"side":"alliance","races":["HUMAN","NIGHTELF","SCOURGE"],"classes":["PALADIN","WARRIOR"],"xp":840""" +
            ""","pre":[1,2],"preAll":[3,4],"excl":[5,6,7],"parent":8,"skill":[185,50],"minRep":[72,3000],"maxRep":[21,-6000]""" +
            ""","start":[["Giver",1429,48.2,42.9]],"finish":[["Taker",1429,10,10,1436,56.3,47.5]]}""",
            row.GetRawText());
    }

    [Fact]
    public void A_race_list_that_names_everyone_on_the_side_is_dropped_and_both_sides_have_no_side()
    {
        var (quests, _) = Build(
        [
            Quest(1) with { Races = ["DWARF", "HUMAN"] },
            Quest(2) with { Races = ["HUMAN"] },
            Quest(3, side: "both") with { Races = ["HUMAN", "ORC"] },
        ]);

        Assert.Equal("(none)", Json(quests[1], "races"));
        Assert.Equal("""["HUMAN"]""", Json(quests[2], "races"));
        Assert.Equal("""["HUMAN","ORC"]""", Json(quests[3], "races"));
        Assert.Equal("(none)", Json(quests[3], "side"));
    }

    [Fact]
    public void An_objective_is_its_game_type_its_name_and_one_real_spawn_per_map()
    {
        var quest = Quest(1) with
        {
            Objectives = new QuestObjectives([new ObjectiveTarget(3, null)], [new ObjectiveTarget(7, "Open the crate")], [new ObjectiveTarget(10, null), new ObjectiveTarget(999, null)], new FactionValue(72, 1), null, null),
            TriggerEnd = new Trigger("Scout the camp", At(12, 70, 70)),
        };

        var row = Build([quest]).Quests[1];

        // The kobold's point is the spawn nearest the mean, not the mean and not the placeholder.
        // The item drops from the kobold (Elwynn) and from a crate (Westfall): a point in each.
        // An item the data does not know keeps its place, so the n-th item is still the n-th.
        Assert.Equal(
            """[["monster","Kobold",1429,31,30],["object","Open the crate",1436,30,30],["item","Kobold Ear",1429,31,30,1436,30,30],["item",""],["event","Scout the camp",1429,70,70]]""",
            Json(row, "obj"));
    }

    [Fact]
    public void A_sub_zone_uses_its_parents_map_and_an_endpoint_without_a_point_is_left_out()
    {
        var (quests, zones) = Build(
        [
            Quest(1) with { ZoneId = 9, Start = new QuestEndpoints([6], null, null), End = new QuestEndpoints([5], null, null) },
            Quest(2) with { Start = new QuestEndpoints(null, null, [10]) },
        ]);

        Assert.Equal("""[["Sub-zone Giver",1429,50,50]]""", Json(quests[1], "start"));
        Assert.Equal("(none)", Json(quests[1], "finish")); // the boss stands inside an instance
        Assert.Equal("(none)", Json(quests[2], "start")); // started by an item: no giver
        // Only a quest with a giver is a pick-up.
        Assert.Equal("""{"1":[1]}""", Json(zones[1429], "bands"));
    }

    [Theory]
    [InlineData(1, "(none)")] // an ordinary kill quest
    [InlineData(2, "\"raid\"")] // the raid flag
    [InlineData(3, "\"raid\"")] // a raid zone without the flag
    [InlineData(4, "\"dungeon\"")] // an instance zone
    [InlineData(5, "\"dungeon\"")] // an outdoor quest whose objective exists only inside an instance
    [InlineData(6, "\"pvp\"")] // a battleground
    [InlineData(7, "\"group\"")] // an elite to kill
    [InlineData(8, "\"group\"")] // an item only an elite drops
    [InlineData(9, "(none)")] // a zone flagged isDungeon that is neither: a city without a map
    [InlineData(10, "(none)")] // an item that also comes from a crate
    public void Quests_are_marked_raid_dungeon_pvp_or_group(int id, string mark)
    {
        QuestObjectives Kill(int npc) => new([new ObjectiveTarget(npc, null)], null, null, null, null, null);
        QuestObjectives Collect(int item) => new(null, null, [new ObjectiveTarget(item, null)], null, null, null);
        var (quests, _) = Build(
        [
            Quest(1) with { Objectives = Kill(3), QuestFlags = 8 },
            Quest(2) with { QuestFlags = 72 },
            Quest(3) with { ZoneId = 2717 },
            Quest(4) with { ZoneId = 1581 },
            Quest(5) with { ZoneId = 40, Objectives = Collect(12) },
            Quest(6) with { ZoneId = 3277 },
            Quest(7) with { Objectives = Kill(4) },
            Quest(8) with { Objectives = Collect(11) },
            Quest(9) with { ZoneId = 16544 },
            Quest(10) with { Objectives = Collect(10) },
        ]);

        Assert.Equal(mark, Json(quests[id], "mark"));
    }

    [Fact]
    public void A_zone_has_the_level_range_of_its_ordinary_quests()
    {
        // Twenty quests at levels 1 to 20, a riding quest at 40, and quests that do not count:
        // a marked one, a repeatable one, an event one and one that scales with the character.
        var quests = Enumerable.Range(1, 20).Select(level => Quest(level, level)).ToList();
        quests.Add(Quest(21, 40));
        quests.Add(Quest(22, 60) with { QuestFlags = 64 });
        quests.Add(Quest(23, 60) with { Repeatable = true });
        quests.Add(Quest(24, 60) with { Category = "SEASONAL" });
        quests.Add(Quest(25, -1));

        var zone = Build(quests).Zones[1429];

        Assert.Equal("Elwynn Forest", zone.GetProperty("name").GetString());
        Assert.Equal(3, zone.GetProperty("min").GetInt32()); // the 10th percentile of 21 levels
        Assert.Equal(18, zone.GetProperty("max").GetInt32()); // the 85th: the 40 does not stretch it
    }

    [Fact]
    public void A_band_holds_the_pick_ups_for_its_levels_prerequisites_first()
    {
        var relations = new List<QuestRelations>
        {
            new() { QuestId = 1, PreQuestSingle = [3] },
            new() { QuestId = 3, PreQuestGroup = [2] },
        };
        var (_, zones) = Build(
        [
            Quest(1, level: 4), // needs 3, which needs 2
            Quest(2, level: 4),
            Quest(3, level: 4),
            Quest(4, level: 12, requiredLevel: 8), // levels 8 to 12, the top level in this data: bands 2 and 3
            Quest(5, level: -1, requiredLevel: 10), // scales with the character: from 10 to the top level
            Quest(6, level: 3) with { Repeatable = true },
            Quest(7, level: 3) with { Category = "DARKMOON_FAIRE" },
            Quest(8, level: 3) with { QuestFlags = 64 }, // marked quests stay in: a preference may allow them
        ], relations);

        // Levels 1 to 5 are band 1. A level 4 quest is offered up to level 11, so bands 1 to 3.
        // Within a band: what needs nothing first, by required level; then what needs those.
        Assert.Equal("""{"1":[2,8,3,1],"2":[2,8,4,5,3,1],"3":[2,4,5,3,1]}""", Json(zones[1429], "bands"));
        // The giver stands only in Elwynn; Westfall holds a turn-in but no pick-up, so no zone row.
        Assert.False(zones.ContainsKey(1436));
        Assert.Equal(1, PlannerIndex.Band(5));
        Assert.Equal(2, PlannerIndex.Band(6));
    }

    [Fact]
    public void The_real_data_builds_and_every_band_quest_has_a_giver_in_its_zone()
    {
        var parsed = Path.Combine(CollectorConfig.FindRepositoryRoot(AppContext.BaseDirectory), "data", "parsed");

        var tables = PlannerIndex.Build(parsed);

        var quests = tables.Quests.EnumerateArray().ToDictionary(r => r.GetProperty("id").GetInt32());
        Assert.True(quests.Count > 5000);
        foreach (var zone in tables.Zones.EnumerateArray())
        {
            var map = zone.GetProperty("id").GetInt32();
            foreach (var id in zone.GetProperty("bands").EnumerateObject().SelectMany(b => b.Value.EnumerateArray()).Select(q => q.GetInt32()).Distinct())
                Assert.Contains(quests[id].GetProperty("start").EnumerateArray(), giver => giver.EnumerateArray().Skip(1).Where((_, i) => i % 3 == 0).Any(m => m.GetInt32() == map));
        }
        // Northshire's first quest: human start, Deputy Willem to Marshal McBride.
        Assert.Equal("""[["Deputy Willem",1429,48.17,42.94]]""", Json(quests[783], "start"));
        Assert.Equal("""[["monster","Kobold Vermin",1429,49.17,36.55]]""", Json(quests[7], "obj"));
    }
}
