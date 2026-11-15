using System.Text.Json;
using Collector.QuestieDb;

namespace Collector.Parse;

/// <summary>
/// A flight point: the game's taxi node id, its name as the flight map shows it, the faction
/// that may use it (absent: both), and its place in world yards on a continent
/// (<c>Map</c> 0 the Eastern Kingdoms, 1 Kalimdor). The <c>Npc</c> fields are the flight master
/// QuestieDB has there, with the zone map and map percent the planner and the arrow work in.
/// </summary>
public sealed record TaxiNode
{
    public required int Id { get; init; }
    public required string Name { get; init; }
    public string? Faction { get; init; }
    public required int Map { get; init; }
    public required double X { get; init; }
    public required double Y { get; init; }
    public int? NpcId { get; init; }
    public string? NpcName { get; init; }
    public int? UiMapId { get; init; }
    public double? MapX { get; init; }
    public double? MapY { get; init; }
}

/// <summary>One direct flight. <c>Estimated</c>: the source had no measured time and computed one from the path's length.</summary>
public sealed record TaxiPath(int From, int To, double Seconds, bool? Estimated);

/// <summary>A zone map's rectangle in world yards, as the taxi source's <c>Data/Zones.lua</c> gives it.</summary>
public sealed record MapRectangle(int Map, double MinX, double MinY, double MaxX, double MaxY);

/// <summary>A QuestieDB NPC with the flight-master flag and one of its spawn points, in percent of a zone map.</summary>
public sealed record FlightMaster(int Id, string Name, string? FriendlyTo, int UiMapId, double MapX, double MapY);

/// <param name="Notice">Where the tables come from and under which licences, with the source file's own header.</param>
/// <param name="UnlinkedMasters">Flight masters with no flight point within <see cref="Taxi.LinkYards"/>.</param>
public sealed record TaxiTables(List<TaxiNode> Nodes, List<TaxiPath> Paths, string Notice, List<FlightMaster> UnlinkedMasters);

/// <summary>
/// Flight points and flight times (issue #16), converted from <c>Data/Taxi.lua</c> of the
/// repository pinned under <c>taxi</c> in collector.json. The file is data in Lua syntax; it is
/// loaded in the same sandbox as QuestieDB's code and only its tables are read.
/// </summary>
public static class Taxi
{
    public const string NodesFile = "taxi-nodes.json", PathsFile = "taxi-paths.json", NoticeFile = "taxi-notice.txt";

    /// <summary>NPCs with this bit in <c>npcFlags</c> are flight masters.</summary>
    public const long FlightMasterFlag = 8;

    /// <summary>A flight master belongs to the nearest flight point it may serve within this distance.</summary>
    public const double LinkYards = 100;

    public static TaxiTables Build(string checkout, TaxiConfig config, MergedDatabase questieDb)
    {
        using var sandbox = new LuaSandbox(checkout);
        var json = sandbox.Run(QuestieDbMerge.JsonEncoder + """
            local ns = {}
            assert(loadfile("Data/Taxi.lua"))("Taxi", ns)
            assert(loadfile("Data/Zones.lua"))("Taxi", ns)
            local nodes, paths = {}, {}
            for id, node in pairs(ns.TaxiNodes) do
              nodes[#nodes + 1] = { id = id, name = node.name, faction = node.faction, map = node.map, x = node.x, y = node.y }
            end
            for i, path in ipairs(ns.TaxiPaths) do
              paths[i] = { from = path.from, to = path.to, seconds = path.seconds, estimated = path.estimated }
            end
            return toJson(nodes), toJson(paths), toJson(ns.Zones)
            """, "=collector-taxi", 3);

        var nodes = JsonSerializer.Deserialize<List<TaxiNode>>(json[0], DataWriter.Json)!.OrderBy(n => n.Id).ToList();
        var paths = JsonSerializer.Deserialize<List<TaxiPath>>(json[1], DataWriter.Json)!.OrderBy(p => p.From).ThenBy(p => p.To).ToList();
        var rectangles = JsonSerializer.Deserialize<Dictionary<int, MapRectangle>>(json[2], DataWriter.Json)!;

        var (linked, unlinked) = Link(nodes, rectangles, FlightMasters(questieDb));
        return new TaxiTables(linked, paths, Notice(config, File.ReadAllLines(Path.Combine(checkout, "Data", "Taxi.lua"))), unlinked);
    }

    /// <summary>
    /// Gives each flight point the nearest flight master that may serve it. A spawn point is
    /// turned into world yards with its zone map's rectangle: map x runs along world -y and map y
    /// along world -x. A master further than <see cref="LinkYards"/> from every point it may
    /// serve stays unlinked, and so does a point with no master that near.
    /// </summary>
    public static (List<TaxiNode> Nodes, List<FlightMaster> Unlinked) Link(
        IReadOnlyList<TaxiNode> nodes, IReadOnlyDictionary<int, MapRectangle> rectangles, IReadOnlyList<FlightMaster> masters)
    {
        var used = new HashSet<int>();
        var linked = nodes.Select(node =>
        {
            var best = masters
                .Where(m => node.Faction is null || m.FriendlyTo is null || m.FriendlyTo.Contains(node.Faction[0]))
                .Where(m => rectangles.TryGetValue(m.UiMapId, out var r) && r.Map == node.Map)
                .Select(m =>
                {
                    var r = rectangles[m.UiMapId];
                    var x = r.MaxX - m.MapY / 100 * (r.MaxX - r.MinX);
                    var y = r.MaxY - m.MapX / 100 * (r.MaxY - r.MinY);
                    return (Master: m, Yards: Math.Sqrt((x - node.X) * (x - node.X) + (y - node.Y) * (y - node.Y)));
                })
                .Where(c => c.Yards <= LinkYards)
                .OrderBy(c => c.Yards).ThenBy(c => c.Master.Id)
                .Select(c => c.Master).FirstOrDefault();
            if (best is null) return node;
            used.Add(best.Id);
            return node with { NpcId = best.Id, NpcName = best.Name, UiMapId = best.UiMapId, MapX = best.MapX, MapY = best.MapY };
        }).ToList();
        return (linked, masters.Where(m => !used.Contains(m.Id)).DistinctBy(m => m.Id).ToList());
    }

    /// <summary>Every spawn point of every NPC with the flight-master flag, in a zone that has a map.</summary>
    public static List<FlightMaster> FlightMasters(MergedDatabase questieDb)
    {
        var uiMaps = questieDb.Reference.RootElement.GetProperty("areaIdToUiMapId");
        var masters = new List<FlightMaster>();
        foreach (var property in questieDb.Npcs.RootElement.EnumerateObject())
        {
            var row = property.Value;
            if (((Lua.Long(row, "npcFlags") ?? 0) & FlightMasterFlag) == 0 || Lua.String(row, "name") is not { } name) continue;
            var spawns = row.TryGetProperty("spawns", out var value) ? Lua.Locations(value) : null;
            foreach (var (zone, points) in spawns ?? [])
                if (Lua.At(uiMaps, zone)?.GetInt32() is { } uiMap and not 0)
                    masters.AddRange(points.Where(p => p[0] >= 0).Select(p => new FlightMaster(int.Parse(property.Name), name, Lua.String(row, "friendlyToFaction"), uiMap, p[0], p[1])));
        }
        return masters.OrderBy(m => m.Id).ToList();
    }

    public static void Write(TaxiTables tables, string directory)
    {
        DataWriter.WriteLines(Path.Combine(directory, NodesFile), tables.Nodes);
        DataWriter.WriteLines(Path.Combine(directory, PathsFile), tables.Paths);
        File.WriteAllText(Path.Combine(directory, NoticeFile), tables.Notice);
    }

    /// <summary>The source, its licence, and the comment lines that head the source file (they carry InFlight's MIT notice).</summary>
    public static string Notice(TaxiConfig config, IEnumerable<string> sourceLines)
    {
        var header = sourceLines.TakeWhile(line => !line.StartsWith("ns.", StringComparison.Ordinal))
            .Where(line => line.StartsWith("--", StringComparison.Ordinal) && !line.StartsWith("---@", StringComparison.Ordinal) && !line.StartsWith("-- stylua", StringComparison.Ordinal))
            .Select(line => line[2..].TrimStart(' '));
        return $"""
            Flight points and flight times ({NodesFile}, {PathsFile}) are converted from Data/Taxi.lua of
            {config.Source} at commit {config.Revision},
            which is licensed GPL-3.0-or-later. The flight masters and their map positions are QuestieDB's (GPL-3.0),
            linked to the flight points with the zone rectangles in Data/Zones.lua of the same commit.
            The header of Data/Taxi.lua follows as it stands there.

            {string.Join("\n", header)}

            """;
    }
}
