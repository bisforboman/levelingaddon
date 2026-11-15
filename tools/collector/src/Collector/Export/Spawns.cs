using System.Text.Json;

namespace Collector.Export;

/// <summary>A map position in percent of the zone map. (-1, -1) is QuestieDB's placeholder for "inside an instance".</summary>
public readonly record struct Point(double X, double Y)
{
    public bool IsPlaceholder => X == -1 && Y == -1;

    public bool Within(double distance, Point other)
    {
        var (dx, dy) = (X - other.X, Y - other.Y);
        return dx * dx + dy * dy <= distance * distance;
    }
}

/// <summary>
/// The spawn reduction rule. A zone's list with at most <see cref="ExportConfig.SpawnMergeAbove"/>
/// real points is kept exactly. In a longer list a point is dropped when a point kept before it
/// lies within <see cref="ExportConfig.SpawnMergeDistance"/>; the kept point stands for it. So
/// every point that remains is a real spawn, in the original order, the kept points are more than
/// the distance apart, and every dropped point has a kept one within the distance. Placeholders
/// are never counted, merged or dropped.
/// </summary>
public static class Spawns
{
    /// <summary>
    /// True for a non-empty JSON array of [x, y] points. A point may carry more numbers (one NPC
    /// repeats the zone's uiMapId as a third); only x and y are read.
    /// </summary>
    public static bool IsPointList(JsonElement value) =>
        value.ValueKind == JsonValueKind.Array && value.GetArrayLength() > 0 && value.EnumerateArray().All(p =>
            p.ValueKind == JsonValueKind.Array && p.GetArrayLength() >= 2 && p.EnumerateArray().All(n => n.ValueKind == JsonValueKind.Number));

    public static List<Point> Read(JsonElement pointList) =>
        pointList.EnumerateArray().Select(p => new Point(p[0].GetDouble(), p[1].GetDouble())).ToList();

    public static List<Point> Reduce(IReadOnlyList<Point> points, ExportConfig config)
    {
        if (points.Count(p => !p.IsPlaceholder) <= config.SpawnMergeAbove) return [.. points];

        var result = new List<Point>();
        foreach (var point in points)
            if (point.IsPlaceholder || !result.Any(kept => !kept.IsPlaceholder && kept.Within(config.SpawnMergeDistance, point)))
                result.Add(point);
        return result;
    }

    /// <summary>
    /// Checks an exported list against the rule without repeating <see cref="Reduce"/>: null
    /// when <paramref name="exported"/> is a valid reduction of <paramref name="original"/>.
    /// </summary>
    public static string? Violation(IReadOnlyList<Point> original, IReadOnlyList<Point> exported, ExportConfig config)
    {
        if (original.Count(p => !p.IsPlaceholder) <= config.SpawnMergeAbove)
            return original.Count == exported.Count && original.Zip(exported).All(pair => Same(pair.First, pair.Second))
                ? null
                : $"{original.Count} points are few enough to be kept exactly, but {exported.Count} different ones were loaded";

        // The exported points must be original points in their original order.
        var kept = new List<Point>();
        foreach (var point in original)
            if (kept.Count < exported.Count && Same(point, exported[kept.Count]))
                kept.Add(point);
        if (kept.Count != exported.Count)
            return $"loaded point {kept.Count + 1} ({exported[kept.Count].X}, {exported[kept.Count].Y}) is not the next point of the JSON";
        if (kept.Count(p => p.IsPlaceholder) != original.Count(p => p.IsPlaceholder)) return "an instance placeholder was dropped";

        var real = kept.Where(p => !p.IsPlaceholder).ToList();
        for (var i = 0; i < real.Count; i++)
            for (var j = i + 1; j < real.Count; j++)
                if (real[i].Within(config.SpawnMergeDistance, real[j]))
                    return $"({real[i].X}, {real[i].Y}) and ({real[j].X}, {real[j].Y}) are within the merge distance and both kept";

        foreach (var point in original)
            if (!point.IsPlaceholder && !real.Any(k => k.Within(config.SpawnMergeDistance, point)))
                return $"({point.X}, {point.Y}) was dropped with no kept point within the merge distance";
        return null;
    }

    // Coordinates come back from Lua printed with 14 significant digits.
    private static bool Same(Point a, Point b) => Math.Abs(a.X - b.X) <= 1e-9 && Math.Abs(a.Y - b.Y) <= 1e-9;
}
