using System.Text;
using System.Text.Json;
using Collector.Export;

namespace Collector.Tests;

public sealed class LuaExportTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("collector-export-").FullName;
    private string Parsed => Path.Combine(_directory, "parsed");
    private string Output => Path.Combine(_directory, "lua");

    public LuaExportTests()
    {
        Directory.CreateDirectory(Parsed);
        File.WriteAllText(Path.Combine(Parsed, "manifest.json"), """{"schemaVersion":1,"source":{"commit":"0123456789abcdef"},"counts":{"quests":3}}""");
        File.WriteAllText(Path.Combine(Parsed, "quests.json"), """
            [
            {"id":2,"name":"Sharptalon's Claw","level":30,"start":{"items":[16305]},"end":{"npcs":[12696]},"requiredRaces":8589934770,"repeatable":true},
            {"id":25,"name":"Say \"hi\"\\ twice\nthen leave","triggerEnd":{"text":"Scout","locations":{"331":[[48.92,69.56]],"1":[[-1,-1]]}},"objectivesText":["a","","b"]},
            {"id":900,"name":"Entrée à Zephras","xp":0.5,"empty":[],"nested":{"007":"bond","-3":"minus","a-b":1}}
            ]
            """);
        File.WriteAllText(Path.Combine(Parsed, "quest-relations.json"), """[{"questId":2,"preQuestSingle":[6383],"nextQuestInChain":25}]""");
        File.WriteAllText(Path.Combine(Parsed, "npcs.json"), """[{"id":12696,"name":"Senani Thunderheart","spawns":{"331":[[73.78,61.46]]}}]""");
        File.WriteAllText(Path.Combine(Parsed, "objects.json"), "[]");
        File.WriteAllText(Path.Combine(Parsed, "items.json"), """[{"id":16305,"name":"Sharptalon's Claw","npcDrops":[12676]}]""");
        File.WriteAllText(Path.Combine(Parsed, "zones.json"), """[{"id":331,"key":"ASHENVALE","name":"Ashenvale"}]""");
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    private static string Lua(string json)
    {
        var lua = new StringBuilder();
        LuaWriter.Write(lua, JsonDocument.Parse(json).RootElement, new LuaConstants());
        return lua.ToString();
    }

    [Theory]
    [InlineData("""{"name":"x","level":30}""", """{name="x",level=30}""")]
    [InlineData("""{"end":{"npcs":[1,2]},"local":true}""", """{["end"]={npcs={1,2}},["local"]=true}""")]
    [InlineData("""{"331":[[48.92,69.56]],"-3":0,"007":1,"a-b":2}""", """{[331]={{48.92,69.56}},[-3]=0,["007"]=1,["a-b"]=2}""")]
    [InlineData("""["a\"b\\c\nd\u0001e", "Entrée"]""", """{"a\"b\\c\nd\001e","Entrée"}""")]
    [InlineData("""[8589934770, -1, 0.5, 1e-7, [], {}, null, false]""", """{8589934770,-1,0.5,1E-07,{},{},nil,false}""")]
    public void Json_becomes_the_equivalent_lua_literal(string json, string lua) => Assert.Equal(lua, Lua(json));

    [Fact]
    public void Each_entity_is_one_line_keyed_by_id_without_repeating_the_id()
    {
        new LuaExporter(new ExportConfig()).Run(Parsed, Output);

        var lines = File.ReadAllLines(Path.Combine(Output, "quests-1.lua"));
        Assert.StartsWith(LuaExporter.GeneratedMarker, lines[0]);
        Assert.Contains("local _, ns = ...", lines);
        Assert.Contains("ns.Data.quests=ns.Data.quests or {}", lines);
        Assert.Contains("""t[2]={name="Sharptalon's Claw",level=30,start={items={16305}},["end"]={npcs={12696}},requiredRaces=8589934770,repeatable=true}""", lines);
        Assert.Contains("t[2]={preQuestSingle={6383},nextQuestInChain=25}", File.ReadAllLines(Path.Combine(Output, "questRelations-1.lua")));
    }

    [Fact]
    public void The_export_loads_and_reads_back_identical_to_the_json()
    {
        var exporter = new LuaExporter(new ExportConfig());

        var export = exporter.Run(Parsed, Output);

        Assert.Empty(exporter.Verify(Parsed, Output, export));
        Assert.Equal(["manifest.lua", "quests-1.lua", "questRelations-1.lua", "npcs-1.lua", "objects-1.lua", "items-1.lua", "zones-1.lua"], export.Files);
        var xml = File.ReadAllText(Path.Combine(Output, "data.xml"));
        Assert.All(export.Files, file => Assert.Contains($"<Script file=\"{file}\"/>", xml));
    }

    [Fact]
    public void A_table_is_split_when_one_file_would_hold_too_many_distinct_literals()
    {
        var exporter = new LuaExporter(new ExportConfig(MaxConstantsPerFile: 20));

        var export = exporter.Run(Parsed, Output);

        var quests = export.Tables.Single(t => t.Name == "quests");
        Assert.Equal(["quests-1.lua", "quests-2.lua", "quests-3.lua"], quests.Files);
        Assert.Contains("Part 2 of 3.", File.ReadAllText(Path.Combine(Output, "quests-2.lua")));
        Assert.Empty(exporter.Verify(Parsed, Output, export));
    }

    [Fact]
    public void A_custom_table_name_is_used_throughout()
    {
        var exporter = new LuaExporter(new ExportConfig(Table: "QuestData"));

        var export = exporter.Run(Parsed, Output);

        Assert.Contains("ns.QuestData.zones=ns.QuestData.zones or {}", File.ReadAllText(Path.Combine(Output, "zones-1.lua")));
        Assert.Empty(exporter.Verify(Parsed, Output, export));
    }

    [Fact]
    public void Re_exporting_removes_stale_generated_files_and_leaves_other_files_alone()
    {
        new LuaExporter(new ExportConfig(MaxConstantsPerFile: 20)).Run(Parsed, Output);
        File.WriteAllText(Path.Combine(Output, "handwritten.lua"), "-- mine\nreturn 1\n");

        new LuaExporter(new ExportConfig()).Run(Parsed, Output);

        Assert.False(File.Exists(Path.Combine(Output, "quests-2.lua")));
        Assert.True(File.Exists(Path.Combine(Output, "quests-1.lua")));
        Assert.True(File.Exists(Path.Combine(Output, "handwritten.lua")));
    }

    [Fact]
    public void Verification_reports_a_value_that_differs_from_the_json()
    {
        var exporter = new LuaExporter(new ExportConfig());
        var export = exporter.Run(Parsed, Output);
        var path = Path.Combine(Output, "quests-1.lua");
        File.WriteAllText(path, File.ReadAllText(path).Replace("level=30", "level=31"));

        var differences = exporter.Verify(Parsed, Output, export);

        Assert.Contains("quests[2].level", Assert.Single(differences));
    }
}
