using System.Text.Json;
using Collector.Export;
using Collector.Parse;

namespace Collector.Tests;

public sealed class ClassSpellsTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("collector-class-spells-").FullName;

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    // Rows as the listing has them, cut down to the fields that matter and a few that do not.
    private const string MageRows = """
        [
        {"id":133,"name":"Fireball","rank":"Rank 1","level":1,"cat":7},
        {"id":143,"name":"Fireball","rank":"Rank 2","level":6,"source":[6],"trainingcost":100},
        {"id":400618,"name":"Fireball","rank":"Rank 2","level":6},
        {"id":25306,"name":"Fireball","rank":"Rank 12","level":60,"source":[2]},
        {"id":12505,"name":"Pyroblast","rank":"Rank 2","level":24,"source":[6],"trainingcost":200},
        {"id":12522,"name":"Pyroblast","rank":"Rank 3","level":30,"source":[6],"trainingcost":400},
        {"id":3565,"name":"Teleport: Darnassus","level":30,"races":[1,3,4,7],"reqrace":4294967373,"source":[6],"trainingcost":8000},
        {"id":768,"name":"Cat Form","rank":"Shapeshift","level":20,"source":[6],"trainingcost":2000},
        {"id":118,"name":"Polymorph","rank":"Rank 1","level":8,"source":[6],"trainingcost":200}
        ]
        """;

    [Fact]
    public void A_row_with_a_training_cost_is_a_trainer_spell_in_level_order()
    {
        var (spells, _) = ClassSpells.Parse("MAGE", JsonDocument.Parse(MageRows).RootElement);

        Assert.Equal([143, 118, 768, 3565], spells.Select(s => s.Id));
        Assert.Equal(new ClassSpell("MAGE", 143, "Fireball", 2, 6, 100, null), spells[0]);
    }

    [Fact]
    public void Only_a_numbered_rank_is_a_rank_and_races_are_kept()
    {
        var (spells, _) = ClassSpells.Parse("MAGE", JsonDocument.Parse(MageRows).RootElement);

        Assert.Null(spells.Single(s => s.Name == "Cat Form").Rank);
        Assert.Equal(1, spells.Single(s => s.Name == "Polymorph").Rank);
        Assert.Equal([1, 3, 4, 7], spells.Single(s => s.Id == 3565).Races);
    }

    [Fact]
    public void Trained_ranks_of_a_spell_without_rank_one_on_the_page_are_left_out_and_named()
    {
        var (spells, talentRanks) = ClassSpells.Parse("MAGE", JsonDocument.Parse(MageRows).RootElement);

        Assert.DoesNotContain(spells, s => s.Name == "Pyroblast");
        Assert.Equal(["Pyroblast"], talentRanks);
    }

    private void Cache(string key, string url, string? rows)
    {
        var captures = rows is null ? "" : $$""","captureFiles":{"spells":"{{key}}.spells.json"}""";
        File.WriteAllText(Path.Combine(_directory, key + ".meta.json"), $$"""{"url":"{{url}}","status":200,"bodyFile":"{{key}}.html"{{captures}}}""");
        if (rows is not null) File.WriteAllText(Path.Combine(_directory, key + ".spells.json"), rows);
    }

    [Fact]
    public void The_class_comes_from_the_address_of_each_cached_page()
    {
        Cache("b-1", "https://example.test/forever/spells/abilities/warrior", """[{"id":100,"name":"Charge","rank":"Rank 1","level":4,"trainingcost":100}]""");
        Cache("a-2", "https://example.test/forever/spells/abilities/mage", MageRows);

        var tables = ClassSpells.Build(_directory);
        ClassSpells.Write(tables, _directory);

        Assert.Equal(["MAGE", "MAGE", "MAGE", "MAGE", "WARRIOR"], tables.Spells.Select(s => s.Class));
        Assert.Equal(["MAGE Pyroblast"], tables.TalentRanks);
        var lines = File.ReadAllLines(Path.Combine(_directory, ClassSpells.SpellsFile));
        Assert.Equal("""{"class":"MAGE","id":143,"name":"Fireball","rank":2,"level":6,"cost":100},""", lines[1]);
        Assert.Equal("""{"class":"WARRIOR","id":100,"name":"Charge","rank":1,"level":4,"cost":100}""", lines[5]);
    }

    [Theory]
    [InlineData("https://example.test/forever/spells/abilities/monk", "[]", "not the ability listing of a class")]
    [InlineData("https://example.test/forever/spells/abilities/mage", null, "without its spell list")]
    [InlineData("https://example.test/forever/spells/abilities/mage", """[{"id":133,"name":"Fireball","level":1}]""", "no row has a training cost")]
    public void A_page_that_cannot_be_a_class_listing_stops_the_parse(string url, string? rows, string message)
    {
        Cache("page", url, rows);

        Assert.Contains(message, Assert.Throws<InvalidDataException>(() => ClassSpells.Build(_directory)).Message);
    }
}
