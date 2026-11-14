using System.Text.Json;
using System.Text.Json.Nodes;
using Collector.Parse;

namespace Collector.Export;

/// <summary>
/// What the addon's planner looks up, prepared here so that nothing is derived at login. Two
/// tables, exported like the others:
/// <list type="bullet">
/// <item><c>plannerQuests[id]</c>: <c>name</c>, what eligibility needs (<c>req</c>, <c>maxLevel</c>,
/// <c>side</c>, <c>races</c>, <c>classes</c>, <c>pre</c> = any one of, <c>preAll</c> = all of,
/// <c>excl</c> = unavailable once any of these is completed or in the log, <c>parent</c>,
/// <c>skill</c>, <c>minRep</c>, <c>maxRep</c>), what ranking needs (<c>level</c>, <c>xp</c>,
/// <c>mark</c>), and where each action happens: <c>start</c> and <c>finish</c> (alternatives),
/// each <c>{name, uiMapId, x, y, ...}</c> with one point per zone map, and <c>obj</c> (each
/// needed), the same with the game's objective type in front.</item>
/// <item><c>plannerZones[uiMapId]</c>: name, the level range of the zone's quests
/// (<c>min</c>, <c>max</c>), and <c>bands[n]</c>: the quests that can be picked up in the zone
/// by a character whose level is in band n, prerequisites first.</item>
/// </list>
/// </summary>
public static class PlannerIndex
{
    /// <summary>Levels per band: band n holds levels (n-1)*BandWidth+1 to n*BandWidth.</summary>
    public const int BandWidth = 5;

    /// <summary>A quest stays a candidate until the character is this many levels above it.</summary>
    public const int LevelsBelow = 7;

    // The data has no quest type. These zone ids say what the isDungeon flag does not: it also
    // covers raids, battlegrounds and a few city and event zones (which have no map of their own).
    private static readonly HashSet<int> RaidZones = [1977, 2159, 2677, 2717, 3428, 3429, 3456, 16236];
    private static readonly HashSet<int> Battlegrounds = [2597, 3277, 3358];
    private const long RaidFlag = 64;

    // Categories of quests that exist only while a world event runs.
    private static readonly HashSet<string> EventCategories = ["SEASONAL", "LUNAR_FESTIVAL", "DARKMOON_FAIRE", "MIDSUMMER", "AHN_QIRAJ_WAR", "INVASION"];

    public sealed record Tables(JsonElement Quests, JsonElement Zones);

    public static Tables Build(string parsedDirectory)
    {
        List<T> Read<T>(string file) => JsonSerializer.Deserialize<List<T>>(File.ReadAllBytes(Path.Combine(parsedDirectory, file)), DataWriter.Json)!;
        return Build(Read<Quest>("quests.json"), Read<QuestRelations>("quest-relations.json"), Read<Npc>("npcs.json"),
            Read<GameObject>("objects.json"), Read<Item>("items.json"), Read<Zone>("zones.json"));
    }

    public static Tables Build(List<Quest> quests, List<QuestRelations> relationRows, List<Npc> npcRows, List<GameObject> objectRows, List<Item> itemRows, List<Zone> zoneRows)
    {
        var relations = relationRows.ToDictionary(r => r.QuestId);
        var npcs = npcRows.ToDictionary(n => n.Id);
        var objects = objectRows.ToDictionary(o => o.Id);
        var items = itemRows.ToDictionary(i => i.Id);
        var zones = zoneRows.ToDictionary(z => z.Id);

        // A zone the planner can point into: an outdoor zone or city with a map. Sub-zones use
        // their parent's map.
        int? MapOf(int zoneId)
        {
            for (var hops = 0; zones.TryGetValue(zoneId, out var zone) && hops < 8; hops++)
            {
                if (zone.IsDungeon == true) return null;
                if (zone.UiMapId is { } map) return map;
                if (zone.ParentZoneId is not { } parent) return null;
                zoneId = parent;
            }
            return null;
        }
        bool IsInstance(int zoneId) => zones.TryGetValue(zoneId, out var zone) && zone.IsDungeon == true && zone.UiMapId is not null && !Battlegrounds.Contains(zoneId);

        // The one place spawns are read. Returns the real points per map, and whether any point
        // lies inside an instance.
        (Dictionary<int, List<Point>> ByMap, bool Instanced) Points(IEnumerable<Locations?> spawns)
        {
            var byMap = new Dictionary<int, List<Point>>();
            var instanced = false;
            foreach (var (zoneId, points) in spawns.Where(s => s is not null).SelectMany(s => s!))
            {
                var map = MapOf(zoneId);
                foreach (var point in points.Select(p => new Point(p[0], p[1])))
                {
                    if (point.IsPlaceholder || map is null) instanced |= point.IsPlaceholder || IsInstance(zoneId);
                    else (byMap.TryGetValue(map.Value, out var list) ? list : byMap[map.Value] = []).Add(point);
                }
            }
            return (byMap, instanced);
        }

        // A target is {name, uiMapId, x, y, uiMapId, x, y, ...}: one point per map, the real
        // spawn nearest to the mean of that map's spawns. Null when it has no point.
        JsonArray? Target(string? name, IEnumerable<Locations?> spawns)
        {
            var at = new JsonArray(name ?? "");
            foreach (var (map, points) in Points(spawns).ByMap.OrderBy(p => p.Key))
            {
                var (meanX, meanY) = (points.Average(p => p.X), points.Average(p => p.Y));
                var nearest = points.MinBy(p => (p.X - meanX) * (p.X - meanX) + (p.Y - meanY) * (p.Y - meanY));
                at.Add(map);
                at.Add(nearest.X);
                at.Add(nearest.Y);
            }
            return at.Count == 1 ? null : at;
        }

        // A quest's start or end: each NPC or object that has a point is an alternative.
        JsonArray? Endpoints(QuestEndpoints? endpoints)
        {
            var targets = (endpoints?.Npcs ?? []).Select(id => npcs.GetValueOrDefault(id)).Where(n => n is not null).Select(n => Target(n!.Name, [n.Spawns]))
                .Concat((endpoints?.Objects ?? []).Select(id => objects.GetValueOrDefault(id)).Where(o => o is not null).Select(o => Target(o!.Name, [o.Spawns])))
                .Where(t => t is not null).ToArray();
            return targets.Length == 0 ? null : new JsonArray(targets);
        }

        IEnumerable<Locations?> ItemSources(Item item) =>
            (item.NpcDrops ?? []).Concat(item.Vendors ?? []).Select(id => npcs.GetValueOrDefault(id)?.Spawns)
            .Concat((item.ObjectDrops ?? []).Select(id => objects.GetValueOrDefault(id)?.Spawns));

        bool Elite(int npcId) => npcs.TryGetValue(npcId, out var npc) && npc.Rank >= 1;

        // Objectives in the order the game lists each type: `type` is the game's own name for
        // the objective type, so the planner can match the n-th of a type in the quest log.
        // Reputation and spell objectives have no place to point at and are left out.
        (List<(string Type, string? Name, IEnumerable<Locations?> Spawns)> Objectives, bool Group) ObjectivesOf(Quest quest)
        {
            var list = new List<(string, string?, IEnumerable<Locations?>)>();
            var group = false;
            foreach (var target in quest.Objectives?.Npcs ?? [])
            {
                var npc = npcs.GetValueOrDefault(target.Id);
                list.Add(("monster", target.Text ?? npc?.Name, [npc?.Spawns]));
                group |= Elite(target.Id);
            }
            foreach (var credit in quest.Objectives?.KillCredits ?? [])
            {
                list.Add(("monster", credit.Text ?? npcs.GetValueOrDefault(credit.NpcIds.FirstOrDefault())?.Name, credit.NpcIds.Select(id => npcs.GetValueOrDefault(id)?.Spawns)));
                group |= credit.NpcIds.Count > 0 && credit.NpcIds.All(Elite);
            }
            foreach (var target in quest.Objectives?.Objects ?? [])
                list.Add(("object", target.Text ?? objects.GetValueOrDefault(target.Id)?.Name, [objects.GetValueOrDefault(target.Id)?.Spawns]));
            foreach (var target in quest.Objectives?.Items ?? [])
            {
                var item = items.GetValueOrDefault(target.Id);
                list.Add(("item", target.Text ?? item?.Name, item is null ? [] : ItemSources(item)));
                // An item only elites drop.
                group |= item is { NpcDrops.Count: > 0, ObjectDrops: null, Vendors: null, ItemDrops: null } && item.NpcDrops.All(Elite);
            }
            if (quest.TriggerEnd is { Locations: not null } trigger) list.Add(("event", trigger.Text, [trigger.Locations]));
            return (list, group);
        }

        // Everyone on a side: a race list that names them all restricts nothing beyond the side.
        var sideRaces = quests.Where(q => q.Side != "both" && q.Races is not null).GroupBy(q => q.Side)
            .ToDictionary(g => g.Key, g => g.SelectMany(q => q.Races!).Distinct().Count());

        var questRows = new List<JsonObject>();
        var pickups = new Dictionary<int, List<Quest>>(); // map -> quests that can be picked up there
        var zoneLevels = new Dictionary<int, List<int>>(); // map -> levels of the zone's ordinary quests
        foreach (var quest in quests)
        {
            var relation = relations.GetValueOrDefault(quest.Id);
            var (objectives, group) = ObjectivesOf(quest);
            var start = Endpoints(quest.Start);

            var zoneId = quest.ZoneId ?? 0;
            var instanced = IsInstance(zoneId) || objectives.Any(o => Points(o.Spawns) is ({ Count: 0 }, true));
            var mark = ((quest.QuestFlags ?? 0) & RaidFlag) != 0 || RaidZones.Contains(zoneId) ? "raid"
                : instanced ? "dungeon"
                : Battlegrounds.Contains(zoneId) ? "pvp"
                : group ? "group"
                : null;

            var row = new JsonObject { ["id"] = quest.Id };
            void Set(string key, JsonNode? value)
            {
                if (value is not null and not JsonArray { Count: 0 }) row[key] = value;
            }
            JsonArray? Ids(IEnumerable<int>? ids) => ids is null ? null : new JsonArray(ids.Select(id => (JsonNode)Math.Abs(id)).ToArray());

            Set("name", quest.Name);
            Set("level", quest.Level);
            Set("req", quest.RequiredLevel);
            Set("maxLevel", quest.RequiredMaxLevel);
            if (quest.Side != "both") row["side"] = quest.Side;
            // Race names as the client spells them in upper case: no underscore, and "Scourge" for undead.
            if (quest.Races is { } races && races.Count != sideRaces.GetValueOrDefault(quest.Side))
                row["races"] = new JsonArray(races.Select(r => (JsonNode)(r == "UNDEAD" ? "SCOURGE" : r.Replace("_", ""))).ToArray());
            if (quest.Classes is { } classes) row["classes"] = new JsonArray(classes.Select(c => (JsonNode)c).ToArray());
            Set("xp", quest.Xp);
            Set("mark", mark);
            Set("pre", Ids(relation?.PreQuestSingle));
            Set("preAll", Ids(relation?.PreQuestGroup));
            // A breadcrumb leads to its target, and a quest to the next in its chain: once that
            // one is taken or done, this one is no longer offered.
            Set("excl", Ids((relation?.ExclusiveTo ?? []).Concat(new[] { relation?.BreadcrumbForQuestId, relation?.NextQuestInChain }.OfType<int>()).Distinct()));
            Set("parent", relation?.ParentQuest);
            if (quest.RequiredSkill is { } skill) row["skill"] = new JsonArray(skill.SkillId, skill.Value);
            if (quest.RequiredMinRep is { } minRep) row["minRep"] = new JsonArray(minRep.FactionId, minRep.Value);
            if (quest.RequiredMaxRep is { } maxRep) row["maxRep"] = new JsonArray(maxRep.FactionId, maxRep.Value);
            Set("start", start);
            Set("finish", Endpoints(quest.End));
            // An objective is its type and then its target; one without a point keeps its place.
            Set("obj", new JsonArray(objectives.Select(o =>
            {
                var objective = Target(o.Name, o.Spawns) ?? new JsonArray(o.Name ?? "");
                objective.Insert(0, o.Type);
                return (JsonNode)objective;
            }).ToArray()));
            questRows.Add(row);

            // Repeatable quests never count as completed and event quests are not always there,
            // so neither is offered as a pick-up or counted in a zone's level range.
            if (quest.Repeatable == true || EventCategories.Contains(quest.Category ?? "")) continue;
            foreach (var map in (start ?? []).SelectMany(t => t!.AsArray().Where((_, i) => i % 3 == 1)).Select(n => n!.GetValue<int>()).Distinct())
                (pickups.TryGetValue(map, out var list) ? list : pickups[map] = []).Add(quest);
            if (mark is null && quest.Level > 0 && MapOf(zoneId) is { } home)
                (zoneLevels.TryGetValue(home, out var levels) ? levels : zoneLevels[home] = []).Add(quest.Level.Value);
        }

        // Prerequisite order: a quest sorts after everything it needs.
        var depths = new Dictionary<int, int>();
        int Depth(int questId)
        {
            if (depths.TryGetValue(questId, out var known)) return known;
            depths[questId] = 0; // a cycle in the data ends here
            var needs = relations.GetValueOrDefault(questId) is { } r ? (r.PreQuestSingle ?? []).Concat(r.PreQuestGroup ?? []) : [];
            return depths[questId] = needs.Select(id => Depth(Math.Abs(id)) + 1).DefaultIfEmpty(0).Max();
        }

        var topLevel = quests.Max(q => q.Level ?? 0);
        var zoneRowList = new List<JsonObject>();
        foreach (var map in pickups.Keys.Union(zoneLevels.Keys).Order())
        {
            var row = new JsonObject { ["id"] = map };
            var named = zoneRows.Where(z => z.UiMapId == map && z.Name is not null).OrderBy(z => z.ParentZoneId is null ? 0 : 1).FirstOrDefault();
            if (named is not null) row["name"] = named.Name;
            if (zoneLevels.TryGetValue(map, out var levels))
            {
                // The 10th to the 85th percentile of the zone's quests: a few strays (riding
                // quests at 40, a late chain) must not stretch the range.
                levels.Sort();
                row["min"] = levels[(levels.Count - 1) * 10 / 100];
                row["max"] = levels[(levels.Count - 1) * 85 / 100];
            }
            var bands = new JsonObject();
            foreach (var group in (pickups.GetValueOrDefault(map) ?? [])
                .SelectMany(q => Enumerable.Range(Band(q.RequiredLevel ?? 1), Math.Max(0, Band(q.Level > 0 ? Math.Min(q.Level.Value + LevelsBelow, topLevel) : topLevel) - Band(q.RequiredLevel ?? 1) + 1)).Select(band => (band, q)))
                .GroupBy(p => p.band).OrderBy(g => g.Key))
                bands[group.Key.ToString()] = new JsonArray(group.Select(p => p.q).OrderBy(q => Depth(q.Id)).ThenBy(q => q.RequiredLevel ?? 1).ThenBy(q => q.Id).Select(q => (JsonNode)q.Id).ToArray());
            row["bands"] = bands;
            zoneRowList.Add(row);
        }

        static JsonElement Rows(IEnumerable<JsonObject> rows) => JsonSerializer.SerializeToElement(rows);
        return new Tables(Rows(questRows), Rows(zoneRowList));
    }

    /// <summary>The band a level falls in, from 1.</summary>
    public static int Band(int level) => (Math.Max(level, 1) - 1) / BandWidth + 1;
}
