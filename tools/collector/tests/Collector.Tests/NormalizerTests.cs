using System.Text.Json;
using Collector.Parse;
using Collector.QuestieDb;

namespace Collector.Tests;

public sealed class NormalizerTests
{
    // Shaped like the merge output: tuples with gaps arrive as objects keyed by index.
    private const string Quests = """
        {
          "2": {"name":"Sharptalon's Claw","startedBy":{"3":[16305]},"finishedBy":[[12696]],"requiredLevel":20,"questLevel":30,
                "requiredRaces":178,"zoneOrSort":331,"preQuestSingle":[6383],"inGroupWith":[23,24],"sourceItemId":16305,
                "reputationReward":[[81,100]],"nextQuestInChain":0,"requiredSkill":[],"objectivesText":["Bring the claw."]},
          "25": {"name":"Stonetalon Standstill","startedBy":[[12737]],"finishedBy":[[12737]],"questLevel":25,"requiredRaces":0,
                 "objectives":{"1":[[3917]],"3":[[5646,"A phial"]],"5":[[[11,12],11,"Slain"]]},"specialFlags":1,
                 "triggerEnd":["Scout the gazebo",{"331":[[48.92,69.56]]}],"zoneOrSort":-263},
          "900": {"name":"New Arrival","requiredRaces":77,"zoneOrSort":1,"breadcrumbForQuestId":25}
        }
        """;
    private const string Npcs = """
        {
          "12696": {"name":"Senani Thunderheart","spawns":{"331":[[73.78,61.46]]},"zoneID":331,"friendlyToFaction":"H","minLevel":40,"maxLevel":40},
          "12737": {"name":"Mastok Wrilehiss","spawns":[[[1,2]]],"zoneID":1},
          "12676": {"name":"Sharptalon","spawns":{"331":[[74,70],[75,71]]}},
          "3917": {"name":"Befouled Water Elemental"},
          "11": {"name":"Credit A"}, "12": {"name":"Credit B"},
          "555": {"name":"Unrelated Bystander","spawns":{"331":[[1,1]]}}
        }
        """;
    private const string Objects = """{ "77": {"name":"Unrelated Crate"} }""";
    private const string Items = """
        {
          "16305": {"name":"Sharptalon's Claw","npcDrops":[12676],"startQuest":2,"class":12},
          "5646": {"name":"Phial"},
          "1": {"name":"Unrelated Sword"}
        }
        """;
    private const string Reference = """
        {
          "raceKeys": {"ALL_ALLIANCE":77,"ALL_HORDE":178,"HUMAN":1,"ORC":2,"DWARF":4,"NIGHT_ELF":8,"UNDEAD":16,"TAUREN":32,"GNOME":64,"TROLL":128,"NONE":0},
          "classKeys": {"DRUID":1024,"NONE":0},
          "sortKeys": {"DRUID":-263},
          "zoneIDs": {"ASHENVALE":331,"DUN_MOROGH":1},
          "questXp": {"2":[30,2450]},
          "areaIdToUiMapId": {"331":1440},
          "subZoneToParentZone": {},
          "baseQuestIds": [2,25]
        }
        """;

    private static DataSet Normalize() => new Normalizer(new MergedDatabase(
        JsonDocument.Parse(Quests), JsonDocument.Parse(Npcs), JsonDocument.Parse(Objects), JsonDocument.Parse(Items), JsonDocument.Parse(Reference), "")).Run();

    [Fact]
    public void A_quest_keeps_its_endpoints_levels_side_and_rewards()
    {
        var quest = Normalize().Quests.Single(q => q.Id == 2);

        Assert.Equal([16305], quest.Start!.Items);
        Assert.Null(quest.Start.Npcs);
        Assert.Equal([12696], quest.End!.Npcs);
        Assert.Equal((30, 20, 331), (quest.Level, quest.RequiredLevel, quest.ZoneId));
        Assert.Equal("horde", quest.Side);
        Assert.Equal(["ORC", "TAUREN", "TROLL", "UNDEAD"], quest.Races);
        Assert.Equal((2450, 30), (quest.Xp, quest.XpLevel));
        Assert.Equal(new FactionValue(81, 100), Assert.Single(quest.ReputationRewards!));
        Assert.Equal("era", quest.Origin);
        Assert.Null(quest.RequiredSkill); // cleared by an empty table
    }

    [Fact]
    public void Objectives_with_gaps_triggers_and_categories_are_read_by_position()
    {
        var quest = Normalize().Quests.Single(q => q.Id == 25);

        Assert.Equal(new ObjectiveTarget(3917, null), Assert.Single(quest.Objectives!.Npcs!));
        Assert.Equal(new ObjectiveTarget(5646, "A phial"), Assert.Single(quest.Objectives.Items!));
        var credit = Assert.Single(quest.Objectives.KillCredits!);
        Assert.Equal([11, 12], credit.NpcIds);
        Assert.Equal((11, "Slain"), (credit.BaseNpcId, credit.Text));
        Assert.Null(quest.Objectives.Objects);
        Assert.Equal([48.92, 69.56], Assert.Single(quest.TriggerEnd!.Locations![331]));
        Assert.Equal(("DRUID", -263, null), (quest.Category, quest.CategoryId, quest.ZoneId));
        Assert.Equal(("both", true), (quest.Side, quest.Repeatable));
    }

    [Fact]
    public void Relations_are_separate_and_zero_means_none()
    {
        var data = Normalize();

        var relations = data.Relations.Single(r => r.QuestId == 2);
        Assert.Equal([6383], relations.PreQuestSingle);
        Assert.Equal([23, 24], relations.InGroupWith);
        Assert.Null(relations.NextQuestInChain);
        Assert.Equal(25, data.Relations.Single(r => r.QuestId == 900).BreadcrumbForQuestId);
        Assert.DoesNotContain(data.Relations, r => r.QuestId == 25);
    }

    [Fact]
    public void Only_entities_a_quest_refers_to_are_kept_including_item_sources()
    {
        var data = Normalize();

        Assert.Equal([11, 12, 3917, 12676, 12696, 12737], data.Npcs.Select(n => n.Id));
        Assert.Equal([5646, 16305], data.Items.Select(i => i.Id));
        Assert.Empty(data.Objects);
        Assert.Equal(7, data.SourceCounts["npcs"]);
        // A spawn map whose only zone is 1 arrives as an array and must still read as zone 1.
        Assert.Equal([1.0, 2.0], Assert.Single(data.Npcs.Single(n => n.Id == 12737).Spawns![1]));
    }

    [Fact]
    public void Zones_cover_what_the_data_uses()
    {
        var zones = Normalize().Zones;

        Assert.Equal([1, 331], zones.Select(z => z.Id));
        Assert.Equal(("ASHENVALE", "Ashenvale", 1440), (zones[1].Key, zones[1].Name, zones[1].UiMapId));
    }

    [Fact]
    public void Validation_reports_missing_givers_turn_ins_coordinates_and_unknown_relations()
    {
        var report = Validation.Run(Normalize(), wowheadReportedQuests: 5);
        List<int> Ids(string key) => report.Findings.Single(f => f.Key == key).QuestIds;

        Assert.Equal([900], Ids("missing-giver"));
        Assert.Equal([900], Ids("missing-turn-in"));
        Assert.Empty(Ids("giver-without-coordinates")); // quest 2 is located through the item's dropper
        Assert.Equal([2], Ids("unknown-related-quest"));
        Assert.Equal([25, 900], Ids("missing-xp"));
        Assert.Equal((3, 1, 2), (report.Totals["quests"], report.Totals["questsAddedForForever"], report.Totals["questsFromEraBaseline"]));
        Assert.Contains("| Difference | 2 |", Validation.ToMarkdown(report, "test"));
    }
}
