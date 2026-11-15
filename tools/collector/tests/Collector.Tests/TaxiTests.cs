using Collector.Parse;
using Collector.QuestieDb;

namespace Collector.Tests;

public sealed class TaxiTests : IDisposable
{
    private readonly string _checkout = Directory.CreateTempSubdirectory("collector-taxi-").FullName;

    // Elwynn's zone map covers world x -10200..-8000 and y -2000..1000 here; the city map is a part of it.
    private static readonly Dictionary<int, MapRectangle> Rectangles = new()
    {
        [1429] = new(0, -10200, -2000, -8000, 1000),
        [1453] = new(0, -9200, 0, -8000, 1800),
        [1413] = new(1, -5000, -7500, 1600, 2600),
    };

    public TaxiTests()
    {
        Directory.CreateDirectory(Path.Combine(_checkout, "Data"));
        File.WriteAllText(Path.Combine(_checkout, "Data", "Taxi.lua"), """
            -- Generated elsewhere.
            ---@type string, table
            local _, ns = ...

            -- InFlight duration data license:
            -- MIT License
            --
            -- Copyright (c) someone

            -- stylua: ignore
            ns.TaxiNodes = {
            	[80] = { map = 1, x = -894.59, y = -3773.01, z = 11.48, name = "Ratchet, The Barrens" },
            	[2] = { map = 0, x = -8840, y = 480, z = 109.6, name = "Stormwind, Elwynn", faction = "Alliance" },
            	[4] = { map = 0, x = -10628.89, y = 1036.68, z = 34.06, name = "Sentinel Hill, Westfall", faction = "Alliance" },
            }
            -- not part of the header
            ns.TaxiPaths = {
            	{ from = 4, to = 2, seconds = 86, points = { 0, -10628.5, 1040.1, 0, -8834.9, 476.4 } },
            	{ from = 2, to = 80, seconds = 123.8, estimated = true, points = { 0, 1, 2 } },
            	{ from = 2, to = 4, seconds = 78, points = { 0, -8842, 491.2 } },
            }
            """);
        File.WriteAllText(Path.Combine(_checkout, "Data", "Zones.lua"), """
            local _, ns = ...
            ns.Zones = {
            	[1453] = { city = "Alliance", zone = 1429, map = 0, minX = -9200, minY = 0, maxX = -8000, maxY = 1800 },
            	[1413] = { low = 10, high = 25, map = 1, minX = -5000, minY = -7500, maxX = 1600, maxY = 2600 },
            }
            """);
    }

    public void Dispose() => Directory.Delete(_checkout, recursive: true);

    private static MergedDatabase QuestieDb(string npcs) => new(
        System.Text.Json.JsonDocument.Parse("{}"), System.Text.Json.JsonDocument.Parse(npcs), System.Text.Json.JsonDocument.Parse("{}"),
        System.Text.Json.JsonDocument.Parse("{}"), System.Text.Json.JsonDocument.Parse("""{"areaIdToUiMapId":{"1519":1453,"17":1413,"9999":0}}"""), "");

    [Fact]
    public void The_source_file_becomes_nodes_and_paths_sorted_by_id()
    {
        using var questieDb = QuestieDb("""
            {
            "352":{"name":"Dungar Longdrink","npcFlags":11,"friendlyToFaction":"A","spawns":{"1519":[[73.33,70]]}},
            "16227":{"name":"Bragok","npcFlags":8,"friendlyToFaction":"AH","spawns":{"17":[[63.09,37.16]],"9999":[[1,1]]}},
            "6":{"name":"Kobold Vermin","npcFlags":0,"spawns":{"17":[[63.1,37.2]]}}
            }
            """);

        var tables = Taxi.Build(_checkout, new TaxiConfig("https://example.org/taxi", "abc123"), questieDb);

        Assert.Equal([2, 4, 80], tables.Nodes.Select(n => n.Id));
        Assert.Equal(
            new TaxiNode { Id = 2, Name = "Stormwind, Elwynn", Faction = "Alliance", Map = 0, X = -8840, Y = 480, NpcId = 352, NpcName = "Dungar Longdrink", UiMapId = 1453, MapX = 73.33, MapY = 70 },
            tables.Nodes[0]);
        Assert.Equal(new TaxiNode { Id = 4, Name = "Sentinel Hill, Westfall", Faction = "Alliance", Map = 0, X = -10628.89, Y = 1036.68 }, tables.Nodes[1]);
        Assert.Equal((null, 16227), (tables.Nodes[2].Faction, tables.Nodes[2].NpcId));
        Assert.Equal([new(2, 4, 78, null), new(2, 80, 123.8, true), new(4, 2, 86, null)], tables.Paths);
        Assert.Empty(tables.UnlinkedMasters);
    }

    [Fact]
    public void The_notice_names_the_pinned_source_and_keeps_the_header_of_the_file()
    {
        using var questieDb = QuestieDb("{}");

        var notice = Taxi.Build(_checkout, new TaxiConfig("https://example.org/taxi", "abc123"), questieDb).Notice;

        Assert.Contains("https://example.org/taxi at commit abc123", notice);
        Assert.Contains("GPL-3.0-or-later", notice);
        Assert.Contains("Generated elsewhere.\nInFlight duration data license:\nMIT License\n\nCopyright (c) someone\n", notice);
        Assert.DoesNotContain("@type", notice);
        Assert.DoesNotContain("stylua", notice);
        Assert.DoesNotContain("not part of the header", notice);
    }

    [Fact]
    public void A_flight_master_is_linked_to_the_nearest_point_it_may_serve()
    {
        TaxiNode[] nodes =
        [
            new() { Id = 18, Name = "Booty Bay, Stranglethorn", Faction = "Horde", Map = 0, X = -9000, Y = 500 },
            new() { Id = 19, Name = "Booty Bay, Stranglethorn", Faction = "Alliance", Map = 0, X = -9030, Y = 460 },
            new() { Id = 80, Name = "Ratchet, The Barrens", Map = 1, X = -9000, Y = 500 },
        ];
        // (50, 50) on the zone map is world (-9100, -500); these two stand at about (-9001, 500) and (-9028, 461).
        FlightMaster[] masters =
        [
            new(2858, "Gringer", "H", 1429, 16.67, 45.5),
            new(2859, "Gyll", "A", 1429, 17.97, 46.73),
            new(11798, "Bunthen Plainswind", "AH", 1429, 50, 50),
        ];

        var (linked, unlinked) = Taxi.Link(nodes, Rectangles, masters);

        Assert.Equal([2858, 2859, null], linked.Select(n => n.NpcId));
        Assert.Equal((1429, 17.97, 46.73, "Gyll"), (linked[1].UiMapId, linked[1].MapX, linked[1].MapY, linked[1].NpcName));
        Assert.Equal([11798], unlinked.Select(m => m.Id));
    }

    [Fact]
    public void A_flight_master_too_far_away_or_on_a_map_without_a_rectangle_is_not_linked()
    {
        TaxiNode[] nodes = [new() { Id = 2, Name = "Stormwind, Elwynn", Faction = "Alliance", Map = 0, X = -9100, Y = -500 }];
        // 5 percent of the map's width is 150 yards.
        FlightMaster[] masters = [new(1, "Far", "A", 1429, 55, 50), new(2, "Unmapped", "A", 77, 50, 50)];

        var (linked, unlinked) = Taxi.Link(nodes, Rectangles, masters);

        Assert.Null(linked[0].NpcId);
        Assert.Equal([1, 2], unlinked.Select(m => m.Id));
    }
}
