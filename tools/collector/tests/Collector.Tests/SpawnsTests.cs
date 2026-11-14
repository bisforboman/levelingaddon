using Collector.Export;

namespace Collector.Tests;

public sealed class SpawnsTests
{
    private static readonly ExportConfig Config = new(SpawnMergeAbove: 3, SpawnMergeDistance: 1);
    private static readonly Point Placeholder = new(-1, -1);

    // Two clumps around (10, 10) and (50, 50), and a point on its own.
    private static readonly Point[] Dense =
    [
        new(10, 10), new(10.5, 10.2), new(50, 50), new(9.6, 10.3), new(50.4, 49.5), new(80, 20), new(10.9, 10),
    ];

    [Fact]
    public void A_list_with_few_points_is_kept_exactly()
    {
        Point[] few = [new(10, 10), new(10.01, 10), new(10, 10.01)];

        Assert.Equal(few, Spawns.Reduce(few, Config));
        Assert.Null(Spawns.Violation(few, few, Config));
    }

    [Fact]
    public void In_a_long_list_points_near_a_kept_point_merge_into_it()
    {
        var reduced = Spawns.Reduce(Dense, Config);

        Assert.Equal([new(10, 10), new(50, 50), new(80, 20)], reduced);
        Assert.Null(Spawns.Violation(Dense, reduced, Config));
    }

    [Fact]
    public void Placeholders_are_kept_and_neither_count_nor_merge()
    {
        Point[] onlyFewReal = [new(10, 10), Placeholder, new(10.1, 10), Placeholder, new(10.2, 10)];
        Assert.Equal(onlyFewReal, Spawns.Reduce(onlyFewReal, Config));

        Point[] dense = [Placeholder, .. Dense, Placeholder];
        var reduced = Spawns.Reduce(dense, Config);
        Assert.Equal([Placeholder, new(10, 10), new(50, 50), new(80, 20), Placeholder], reduced);
        Assert.Null(Spawns.Violation(dense, reduced, Config));
    }

    [Fact]
    public void The_same_input_always_gives_the_same_output()
    {
        var points = Enumerable.Range(0, 500).Select(i => new Point(i * 37 % 101 / 4.0, i * 53 % 97 / 4.0)).ToArray();

        var first = Spawns.Reduce(points, Config);

        Assert.InRange(first.Count, 2, points.Length - 1);
        Assert.Equal(first, Spawns.Reduce(points, Config));
        Assert.Null(Spawns.Violation(points, first, Config));
    }

    [Fact]
    public void The_check_rejects_lists_that_break_the_rule()
    {
        Point[] few = [new(10, 10), new(10.01, 10)];
        Assert.NotNull(Spawns.Violation(few, [new(10, 10)], Config));

        Point[] dense = [.. Dense, Placeholder];
        Assert.NotNull(Spawns.Violation(dense, [new(10, 10), new(50, 50), new(80, 20)], Config)); // placeholder dropped
        Assert.NotNull(Spawns.Violation(dense, [new(10, 10), new(50, 50), Placeholder], Config)); // (80, 20) left uncovered
        Assert.NotNull(Spawns.Violation(dense, [new(10, 10), new(10.5, 10.2), new(50, 50), new(80, 20), Placeholder], Config)); // not merged
        Assert.NotNull(Spawns.Violation(dense, [new(50, 50), new(10, 10), new(80, 20), Placeholder], Config)); // reordered
        Assert.NotNull(Spawns.Violation(dense, [new(10.2, 10.1), new(50, 50), new(80, 20), Placeholder], Config)); // not a spawn point
    }
}
