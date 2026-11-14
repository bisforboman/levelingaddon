using System.Text.Json;
using Collector.Export;
using Collector.Parse;

namespace Collector.Tests;

public sealed class DangerIndexTests
{
    // Elwynn (zone 12, map 1429) with the sub-zone Northshire (9), Westfall (40, map 1436) and
    // the Deadmines (1581, an instance under Westfall).
    private static readonly List<Zone> Zones =
    [
        new() { Id = 9, UiMapId = 1429, ParentZoneId = 12 },
        new() { Id = 12, Name = "Elwynn Forest", UiMapId = 1429 },
        new() { Id = 40, Name = "Westfall", UiMapId = 1436 },
        new() { Id = 1581, Name = "The Deadmines", UiMapId = 291, ParentZoneId = 40, IsDungeon = true },
    ];

    private static Locations At(int zone, params double[] xy)
    {
        var points = new List<double[]>();
        for (var i = 0; i < xy.Length; i += 2) points.Add([xy[i], xy[i + 1]]);
        return new Locations { [zone] = points };
    }

    private static readonly JsonElement Path = JsonSerializer.SerializeToElement(new Dictionary<string, double[][][]> { ["12"] = [[[25, 92], [26, 93]]] });

    private static Dictionary<int, string> Build(List<Npc> npcs, List<Quest>? quests = null, List<Item>? items = null, ExportConfig? config = null) =>
        DangerIndex.Build(quests ?? [], npcs, items ?? [], Zones, config ?? new ExportConfig()).EnumerateArray()
            .ToDictionary(row => row.GetProperty("id").GetInt32(), row => row.GetProperty("mobs").GetRawText());

    [Fact]
    public void An_elite_is_listed_under_the_map_of_each_zone_it_spawns_in()
    {
        var zones = Build(
        [
            new() { Id = 448, Name = "Hogger", MinLevel = 11, MaxLevel = 11, Rank = 1, Spawns = At(12, 25.02, 92.9), Waypoints = Path },
            new() { Id = 2, Name = "Roamer", MinLevel = 8, MaxLevel = 10, Rank = 2, Spawns = new Locations { [9] = [[50, 50]], [12] = [[51, 51]], [40] = [[30, 30]] } },
        ]);

        Assert.Equal([1429, 1436], zones.Keys);
        Assert.Equal("""[{"id":2,"name":"Roamer","level":10,"at":[50,50,51,51]},{"id":448,"name":"Hogger","level":11,"patrols":true,"at":[25.02,92.9]}]""", zones[1429]);
        Assert.Equal("""[{"id":2,"name":"Roamer","level":10,"at":[30,30]}]""", zones[1436]);
    }

    [Fact]
    public void Only_elites_that_can_be_hostile_in_the_open_world_are_listed()
    {
        var zones = Build(
        [
            new() { Id = 1, Name = "Normal", Rank = 0, Spawns = At(12, 10, 10) },
            new() { Id = 2, Name = "No rank", Spawns = At(12, 10, 10) },
            new() { Id = 3, Name = "Rare", Rank = 4, Spawns = At(12, 10, 10) },
            new() { Id = 4, Name = "Guard", Rank = 1, FriendlyTo = "AH", Spawns = At(12, 10, 10) },
            new() { Id = 5, Name = "Dungeon Boss", Rank = 1, Spawns = At(1581, -1, -1) },
            new() { Id = 6, Name = "Placeholder", Rank = 1, Spawns = At(40, -1, -1) },
            new() { Id = 7, Name = "No Spawns", Rank = 1 },
            new() { Id = 8, Rank = 1, Spawns = At(12, 10, 10) },
            new() { Id = 9, Name = "City Boss", MinLevel = 63, MaxLevel = 9999, Rank = 3, FriendlyTo = "A", Spawns = At(12, 10, 10, -1, -1) },
        ]);

        Assert.Equal("""[{"id":9,"name":"City Boss","side":"A","at":[10,10]}]""", Assert.Single(zones).Value);
    }

    [Fact]
    public void A_mob_carries_the_quests_it_is_an_objective_of()
    {
        List<Quest> quests =
        [
            new() { Id = 176, Origin = "era", Side = "both", Objectives = new QuestObjectives([new ObjectiveTarget(448, null)], null, null, null, null, null) },
            new() { Id = 20, Origin = "era", Side = "both", Objectives = new QuestObjectives(null, null, null, null, [new KillCredit([7, 448], null, null)], null) },
            new() { Id = 30, Origin = "era", Side = "both", Objectives = new QuestObjectives(null, null, [new ObjectiveTarget(100, null)], null, null, null) },
            new() { Id = 40, Origin = "era", Side = "both", Start = new QuestEndpoints([448], null, null) },
        ];
        List<Item> items = [new() { Id = 100, Name = "Claw", NpcDrops = [448] }];

        var zones = Build([new() { Id = 448, Name = "Hogger", MinLevel = 11, Rank = 1, Spawns = At(12, 25.02, 92.9) }], quests, items);

        Assert.Equal("""[{"id":448,"name":"Hogger","level":11,"quests":[20,30,176],"at":[25.02,92.9]}]""", zones[1429]);
    }

    [Fact]
    public void Many_points_are_reduced_by_the_spawn_rule()
    {
        var zones = Build([new() { Id = 1, Name = "Pack", Rank = 1, Spawns = At(12, 10, 10, 10.5, 10, 11, 10, 40, 40) }],
            config: new ExportConfig(SpawnMergeAbove: 3, SpawnMergeDistance: 2));

        Assert.Equal("""[{"id":1,"name":"Pack","at":[10,10,40,40]}]""", zones[1429]);
    }
}
