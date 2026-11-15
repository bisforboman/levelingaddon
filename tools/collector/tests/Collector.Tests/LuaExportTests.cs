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
            {"id":2,"name":"Sharptalon's Claw","level":30,"start":{"items":[16305]},"end":{"npcs":[12696]},"requiredRaces":8589934770,"repeatable":true,"origin":"era","side":"horde"},
            {"id":25,"name":"Say \"hi\"\\ twice\nthen leave","triggerEnd":{"text":"Scout","locations":{"331":[[48.92,69.56]],"1":[[-1,-1]]}},"objectivesText":["a","","b"],"origin":"era","side":"both"},
            {"id":900,"name":"Entrée à Zephras","ratio":0.5,"empty":[],"nested":{"007":"bond","-3":"minus","a-b":1},"origin":"forever","side":"both"}
            ]
            """);
        File.WriteAllText(Path.Combine(Parsed, "quest-relations.json"), """[{"questId":2,"preQuestSingle":[6383],"nextQuestInChain":25}]""");
        File.WriteAllText(Path.Combine(Parsed, "npcs.json"), """
            [
            {"id":6,"name":"Kobold Vermin","spawns":{"12":[[48.89,36.44],[49.55,36.06],[-1,-1],[47.58,35.94],[60,20],[49.27,37.05]],"1":[[-1,-1]]},"waypoints":{"12":[[[48.89,36.44],[49,36.5]],[[60,20],[61,21],[60,20]]]}},
            {"id":12696,"name":"Senani Thunderheart","spawns":{"331":[[73.78,61.46]]}}
            ]
            """);
        File.WriteAllText(Path.Combine(Parsed, "objects.json"), "[]");
        File.WriteAllText(Path.Combine(Parsed, "items.json"), """[{"id":16305,"name":"Sharptalon's Claw","npcDrops":[12676]}]""");
        File.WriteAllText(Path.Combine(Parsed, "zones.json"), """[{"id":331,"key":"ASHENVALE","name":"Ashenvale"}]""");
        File.WriteAllText(Path.Combine(Parsed, "taxi-nodes.json"), """
            [
            {"id":2,"name":"Stormwind, Elwynn","faction":"Alliance","map":0,"x":-8832.77,"y":478.623,"npcId":352,"npcName":"Dungar Longdrink","uiMapId":1453,"mapX":71.29,"mapY":72.23},
            {"id":80,"name":"Ratchet, The Barrens","map":1,"x":-894.59,"y":-3773.01}
            ]
            """);
        File.WriteAllText(Path.Combine(Parsed, "taxi-paths.json"), """[{"from":2,"to":4,"seconds":78},{"from":2,"to":80,"seconds":123.8,"estimated":true},{"from":4,"to":2,"seconds":86}]""");
        File.WriteAllText(Path.Combine(Parsed, "taxi-notice.txt"), "From elsewhere, GPL-3.0-or-later.\n\nMIT License\n");
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    // These tests are about how JSON becomes Lua, so they keep every field; trimming to what the
    // addon reads has tests of its own.
    private static readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, string[]?>> Everything =
        new Dictionary<string, IReadOnlyDictionary<string, string[]?>>();

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
        new LuaExporter(new ExportConfig(), Everything).Run(Parsed, Output);

        var lines = File.ReadAllLines(Path.Combine(Output, "quests-1.lua"));
        Assert.StartsWith(LuaExporter.GeneratedMarker, lines[0]);
        Assert.Contains("local _, ns = ...", lines);
        Assert.Contains("ns.Data.quests=ns.Data.quests or {}", lines);
        Assert.Contains("""t[2]={name="Sharptalon's Claw",level=30,start={items={16305}},["end"]={npcs={12696}},requiredRaces=8589934770,repeatable=true,origin="era",side="horde"}""", lines);
        Assert.False(File.Exists(Path.Combine(Output, "questRelations-1.lua")), "quest relations are not exported");
    }

    [Fact]
    public void Rows_keep_only_what_the_addon_reads_and_still_verify()
    {
        var exporter = new LuaExporter(new ExportConfig());
        var export = exporter.Run(Parsed, Output);

        var quests = File.ReadAllLines(Path.Combine(Output, "quests-1.lua"));
        var quest = quests.Single(l => l.StartsWith("t[2]="));
        Assert.Contains("name=\"Sharptalon's Claw\"", quest);
        Assert.Contains("repeatable=true", quest);
        Assert.Contains("side=\"horde\"", quest);
        Assert.Contains("start={items={16305}}", quest);
        Assert.DoesNotContain("level=", quest);
        Assert.DoesNotContain("origin=", quest);
        Assert.DoesNotContain("requiredRaces=", quest);
        Assert.DoesNotContain("triggerEnd", quests.Single(l => l.StartsWith("t[25]=")));
        Assert.DoesNotContain("nested", quests.Single(l => l.StartsWith("t[900]=")));

        var npc = File.ReadAllLines(Path.Combine(Output, "npcs-1.lua")).Single(l => l.StartsWith("t[6]="));
        Assert.Contains("spawns=", npc);
        Assert.DoesNotContain("waypoints", npc);
        var node = File.ReadAllLines(Path.Combine(Output, "taxiNodes-1.lua")).Single(l => l.StartsWith("t[2]="));
        Assert.DoesNotContain("npcId", node);
        Assert.DoesNotContain("npcName", node);
        Assert.Contains("t[331]={}", File.ReadAllLines(Path.Combine(Output, "zones-1.lua")));

        Assert.DoesNotContain("questRelations", export.Tables.Select(t => t.Name));
        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);
    }

    [Fact]
    public void Trimming_keeps_the_listed_properties_of_a_nested_object_and_drops_one_left_empty()
    {
        using var rows = JsonDocument.Parse("""[{"id":7,"name":"A","level":2,"objectives":{"npcs":[{"id":6}],"reputation":[{"factionId":1}]}},{"id":8,"objectives":{"spells":[1]}}]""");
        var trimmed = LuaExporter.Trim(LuaExporter.Fields, "quests", "id", rows.RootElement);
        Assert.Equal("""[{"id":7,"name":"A","objectives":{"npcs":[{"id":6}]}},{"id":8}]""", trimmed.GetRawText());
    }

    [Fact]
    public void Flight_points_and_flights_are_exported_under_their_own_notice()
    {
        new LuaExporter(new ExportConfig(), Everything).Run(Parsed, Output);

        var nodes = File.ReadAllLines(Path.Combine(Output, "taxiNodes-1.lua"));
        Assert.Equal(["-- From elsewhere, GPL-3.0-or-later.", "--", "-- MIT License"], nodes[1..4]);
        Assert.DoesNotContain(nodes, line => line.Contains("Derived from QuestieDB"));
        Assert.Contains("""t[2]={name="Stormwind, Elwynn",faction="Alliance",map=0,x=-8832.77,y=478.623,npcId=352,npcName="Dungar Longdrink",uiMapId=1453,mapX=71.29,mapY=72.23}""", nodes);
        Assert.Contains("""t[80]={name="Ratchet, The Barrens",map=1,x=-894.59,y=-3773.01}""", nodes);

        var paths = File.ReadAllLines(Path.Combine(Output, "taxiPaths-1.lua"));
        Assert.Contains("-- MIT License", paths);
        Assert.Contains("t[2]={to={[4]=78,[80]=123.8},est={[80]=true}}", paths);
        Assert.Contains("t[4]={to={[2]=86}}", paths);
    }

    [Fact]
    public void Class_spells_are_lists_by_class_token_and_the_export_verifies_with_and_without_them()
    {
        var exporter = new LuaExporter(new ExportConfig(), Everything);
        var without = exporter.Run(Parsed, Output);
        Assert.DoesNotContain("classSpells-1.lua", without.Files);
        Assert.Empty(exporter.Verify(Parsed, Output, without).Differences);

        File.WriteAllText(Path.Combine(Parsed, "class-spells.json"), """
            [
            {"class":"MAGE","id":143,"name":"Fireball","rank":2,"level":6,"cost":100},
            {"class":"MAGE","id":3565,"name":"Teleport: Darnassus","level":30,"cost":8000,"races":[1,3,4,7]},
            {"class":"WARRIOR","id":100,"name":"Charge","rank":1,"level":4,"cost":100}
            ]
            """);
        var export = exporter.Run(Parsed, Output);

        var lines = File.ReadAllLines(Path.Combine(Output, "classSpells-1.lua"));
        Assert.Contains("Wowhead", lines[0]);
        Assert.DoesNotContain(lines, line => line.Contains("QuestieDB"));
        Assert.Equal(["t.MAGE={", """{id=143,name="Fireball",rank=2,level=6,cost=100},""", """{id=3565,name="Teleport: Darnassus",level=30,cost=8000,races={1,3,4,7}},""", "}", "t.WARRIOR={"], lines[5..10]);
        Assert.Contains("\t<Script file=\"classSpells-1.lua\"/>", File.ReadAllLines(Path.Combine(Output, "data.xml")));
        Assert.Equal(3, export.Tables.Single(t => t.Name == "classSpells").Rows);
        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);

        // A value that differs from the JSON is found.
        File.WriteAllText(Path.Combine(Output, "classSpells-1.lua"), File.ReadAllText(Path.Combine(Output, "classSpells-1.lua")).Replace("cost=8000", "cost=8001"));
        Assert.Contains("classSpells.MAGE.2.cost", Assert.Single(exporter.Verify(Parsed, Output, export).Differences));
    }

    [Fact]
    public void A_key_spell_is_marked_on_its_first_purchase_only_and_a_name_that_marks_nothing_stops_the_export()
    {
        File.WriteAllText(Path.Combine(Parsed, "class-spells.json"), """
            [
            {"class":"MAGE","id":116,"name":"Frostbolt","rank":1,"level":4,"cost":100},
            {"class":"MAGE","id":143,"name":"Fireball","rank":2,"level":6,"cost":100},
            {"class":"MAGE","id":205,"name":"Frostbolt","rank":2,"level":8,"cost":200},
            {"class":"MAGE","id":1953,"name":"Blink","level":20,"cost":2000},
            {"class":"WARRIOR","id":100,"name":"Charge","rank":1,"level":4,"cost":100}
            ]
            """);
        ExportConfig Keys(params string[] mage) => new(ClassSpellKeys: new() { ["MAGE"] = mage });

        var exporter = new LuaExporter(Keys("Frostbolt", "Blink"));
        var export = exporter.Run(Parsed, Output);

        Assert.Equal(
        [
            """{id=116,name="Frostbolt",rank=1,level=4,cost=100,key=true},""",
            """{id=143,name="Fireball",rank=2,level=6,cost=100},""",
            """{id=205,name="Frostbolt",rank=2,level=8,cost=200},""",
            """{id=1953,name="Blink",level=20,cost=2000,key=true},""",
        ], File.ReadAllLines(Path.Combine(Output, "classSpells-1.lua"))[6..10]);
        Assert.Equal(2, export.KeySpells);
        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);

        // Rank 1 of Fireball is a starting spell, not in the data; Charge is another class's; Blnk is a typo.
        foreach (var name in new[] { "Fireball", "Charge", "Blnk" })
            Assert.Contains($"MAGE \"{name}\" names 0", Assert.Throws<InvalidDataException>(() => new LuaExporter(Keys(name)).Run(Parsed, Output)).Message);
    }

    [Fact]
    public void Coordinate_lists_are_flat_and_few_spawns_are_kept_exactly()
    {
        new LuaExporter(new ExportConfig(), Everything).Run(Parsed, Output);

        var lines = File.ReadAllLines(Path.Combine(Output, "npcs-1.lua"));
        Assert.Contains("""t[6]={name="Kobold Vermin",spawns={[12]={48.89,36.44,49.55,36.06,-1,-1,47.58,35.94,60,20,49.27,37.05},[1]={-1,-1}},waypoints={[12]={{48.89,36.44,49,36.5},{60,20,61,21,60,20}}}}""", lines);
        Assert.Contains("""t[12696]={name="Senani Thunderheart",spawns={[331]={73.78,61.46}}}""", lines);
        // Other coordinates are a plain translation.
        Assert.Contains("locations={[331]={{48.92,69.56}},[1]={{-1,-1}}}", File.ReadAllText(Path.Combine(Output, "quests-1.lua")));
    }

    [Fact]
    public void Many_spawns_in_a_zone_are_merged_and_the_export_still_verifies()
    {
        var exporter = new LuaExporter(new ExportConfig(SpawnMergeAbove: 3, SpawnMergeDistance: 2), Everything);

        var export = exporter.Run(Parsed, Output);

        Assert.Contains("spawns={[12]={48.89,36.44,-1,-1,60,20},[1]={-1,-1}},waypoints={[12]={{48.89,36.44,49,36.5},{60,20,61,21,60,20}}}", File.ReadAllText(Path.Combine(Output, "npcs-1.lua")));
        Assert.Equal((8, 5), (export.SpawnPoints, export.SpawnPointsKept));
        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);
    }

    [Theory]
    [InlineData("48.89,36.44,-1,-1,60,20}", "48.89,36.44,60,20}", "placeholder")]
    [InlineData("48.89,36.44,-1,-1,60,20}", "48.89,36.44,-1,-1}", "(60, 20) was dropped")]
    [InlineData("48.89,36.44,-1,-1,60,20}", "48.9,36.44,-1,-1,60,20}", "not the next point")]
    [InlineData("{[331]={73.78,61.46}}", "{[331]={73.78,61.47}}", "kept exactly")]
    [InlineData("{60,20,61,21,60,20}", "{60,20,61,21}", "npcs[6].waypoints.12.2")]
    [InlineData("{[331]={73.78,61.46}}", "{[331]={{73.78,61.46}}}", "flat")]
    public void Verification_reports_spawns_that_break_the_reduction_rule(string exported, string tampered, string expectedMessage)
    {
        var exporter = new LuaExporter(new ExportConfig(SpawnMergeAbove: 3, SpawnMergeDistance: 2), Everything);
        var export = exporter.Run(Parsed, Output);
        var path = Path.Combine(Output, "npcs-1.lua");
        Assert.Contains(exported, File.ReadAllText(path));
        File.WriteAllText(path, File.ReadAllText(path).Replace(exported, tampered));

        Assert.Contains(expectedMessage, Assert.Single(exporter.Verify(Parsed, Output, export).Differences));
    }

    [Fact]
    public void Verification_measures_what_each_table_holds_in_memory()
    {
        var exporter = new LuaExporter(new ExportConfig(), Everything);

        var memory = exporter.Verify(Parsed, Output, exporter.Run(Parsed, Output)).Memory;

        Assert.Equal(["manifest", "quests", "npcs", "objects", "items", "zones", "taxiNodes", "plannerQuests", "plannerZones", "dangers", "taxiPaths"], memory.Select(m => m.Table));
        Assert.All(memory, m => Assert.InRange(m.Megabytes, 0.00001, 1));
        Assert.Equal(0, memory.Single(m => m.Table == "objects").Megabytes, 3);
    }

    [Fact]
    public void The_export_loads_and_reads_back_identical_to_the_json()
    {
        var exporter = new LuaExporter(new ExportConfig(), Everything);

        var export = exporter.Run(Parsed, Output);

        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);
        Assert.Equal(["manifest.lua", "quests-1.lua", "npcs-1.lua", "objects-1.lua", "items-1.lua", "zones-1.lua", "taxiNodes-1.lua", "plannerQuests-1.lua", "plannerZones-1.lua", "dangers-1.lua", "taxiPaths-1.lua"], export.Files);
        var xml = File.ReadAllText(Path.Combine(Output, "data.xml"));
        Assert.All(export.Files, file => Assert.Contains($"<Script file=\"{file}\"/>", xml));
    }

    [Fact]
    public void A_table_is_split_when_one_file_would_hold_too_many_distinct_literals()
    {
        var exporter = new LuaExporter(new ExportConfig(MaxConstantsPerFile: 20), Everything);

        var export = exporter.Run(Parsed, Output);

        var quests = export.Tables.Single(t => t.Name == "quests");
        Assert.Equal(["quests-1.lua", "quests-2.lua", "quests-3.lua"], quests.Files);
        Assert.Contains("Part 2 of 3.", File.ReadAllText(Path.Combine(Output, "quests-2.lua")));
        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);
    }

    [Fact]
    public void A_custom_table_name_is_used_throughout()
    {
        var exporter = new LuaExporter(new ExportConfig(Table: "QuestData"));

        var export = exporter.Run(Parsed, Output);

        Assert.Contains("ns.QuestData.zones=ns.QuestData.zones or {}", File.ReadAllText(Path.Combine(Output, "zones-1.lua")));
        Assert.Empty(exporter.Verify(Parsed, Output, export).Differences);
    }

    [Fact]
    public void Re_exporting_removes_stale_generated_files_and_leaves_other_files_alone()
    {
        new LuaExporter(new ExportConfig(MaxConstantsPerFile: 20)).Run(Parsed, Output);
        File.WriteAllText(Path.Combine(Output, "handwritten.lua"), "-- mine\nreturn 1\n");

        new LuaExporter(new ExportConfig(), Everything).Run(Parsed, Output);

        Assert.False(File.Exists(Path.Combine(Output, "quests-2.lua")));
        Assert.True(File.Exists(Path.Combine(Output, "quests-1.lua")));
        Assert.True(File.Exists(Path.Combine(Output, "handwritten.lua")));
    }

    [Fact]
    public void Verification_reports_a_value_that_differs_from_the_json()
    {
        var exporter = new LuaExporter(new ExportConfig(), Everything);
        var export = exporter.Run(Parsed, Output);
        var path = Path.Combine(Output, "quests-1.lua");
        File.WriteAllText(path, File.ReadAllText(path).Replace("level=30", "level=31"));

        var differences = exporter.Verify(Parsed, Output, export).Differences;

        Assert.Contains("quests[2].level", Assert.Single(differences));
    }
}
