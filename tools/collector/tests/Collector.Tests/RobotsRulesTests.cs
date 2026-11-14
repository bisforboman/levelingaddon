using Collector.Fetch;

namespace Collector.Tests;

public sealed class RobotsRulesTests
{
    // The shape of Wowhead's file on 2026-11-14, reduced to the rules that matter here.
    private const string WowheadLike = """
        User-agent: anthropic-ai
        User-agent: ClaudeBot
        User-agent: Scrapy
        Disallow: /

        User-agent: Claude-SearchBot
        Crawl-delay: 1
        Disallow: /search

        User-Agent: *
        Disallow: /forever/account
        Disallow: /forever/list
        Disallow: /forever/list=*
        Disallow: /forever/search
        Disallow: /forever/site-achievement/*
        """;

    private static Uri Url(string path) => new("https://www.wowhead.com" + path);

    [Theory]
    [InlineData("/forever/quests", true)]
    [InlineData("/forever/quest=2", true)]
    [InlineData("/forever/quests/kalimdor/durotar", true)]
    [InlineData("/forever/list=42", false)]
    [InlineData("/forever/search?q=claw", false)]
    [InlineData("/forever/site-achievement/1", false)]
    public void An_unnamed_client_falls_under_the_star_group(string path, bool allowed)
    {
        var rules = RobotsRules.Parse(WowheadLike, "quest-data-collector/0.1");

        Assert.Equal("*", rules.MatchedGroup);
        Assert.Equal(allowed, rules.IsAllowed(Url(path)));
        Assert.Null(rules.CrawlDelay);
    }

    [Fact]
    public void A_named_client_gets_its_own_group_and_nothing_from_the_star_group()
    {
        var rules = RobotsRules.Parse(WowheadLike, "Scrapy/2.11");

        Assert.False(rules.IsAllowed(Url("/forever/quest=2")));
    }

    [Fact]
    public void Crawl_delay_is_read_from_the_matching_group()
    {
        var rules = RobotsRules.Parse(WowheadLike, "Claude-SearchBot/1.0");

        Assert.Equal(TimeSpan.FromSeconds(1), rules.CrawlDelay);
        Assert.True(rules.IsAllowed(Url("/forever/quest=2")));
    }

    [Fact]
    public void The_longest_rule_wins_and_allow_wins_a_tie()
    {
        var rules = RobotsRules.Parse("User-agent: *\nDisallow: /a\nAllow: /a/b\nDisallow: /c$\nAllow: /d\nDisallow: /d\n", "x");

        Assert.False(rules.IsAllowed(Url("/a/x")));
        Assert.True(rules.IsAllowed(Url("/a/b/c")));
        Assert.False(rules.IsAllowed(Url("/c")));
        Assert.True(rules.IsAllowed(Url("/c/more")));
        Assert.True(rules.IsAllowed(Url("/d")));
    }
}
