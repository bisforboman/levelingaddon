using System.Text.Json;
using System.Text.Json.Nodes;
using Collector.Parse;

namespace Collector.Export;

/// <summary>
/// The elite mobs of each zone map, so that the addon can say "an elite is near this step" by
/// reading one zone's short list instead of every NPC's spawns. One table, exported like the
/// others: <c>dangers[uiMapId].mobs</c> is a list of
/// <c>{id, name, level, side, patrols, quests, at}</c>:
/// <list type="bullet">
/// <item><c>level</c>: the mob's highest level; absent for a boss without one.</item>
/// <item><c>side</c>: "A" or "H" when the mob is friendly to that side and so only a danger to
/// the other. Mobs friendly to both are left out.</item>
/// <item><c>patrols</c>: true when the data has a patrol path for it.</item>
/// <item><c>quests</c>: the quests the mob is an objective of (to kill, or to loot an objective
/// item from): a step of such a quest needs no warning about it.</item>
/// <item><c>at</c>: its spawn points on this map, flat <c>{x1, y1, x2, y2, ...}</c> in percent,
/// reduced by the same rule as <c>spawns</c>.</item>
/// </list>
/// Only NPCs a quest refers to are in the data, so a zone's list is never all of its elites.
/// </summary>
public static class DangerIndex
{
    /// <summary>QuestieDB's ranks: 1 elite, 2 rare elite, 3 boss. 0 is normal and 4 is rare, not elite.</summary>
    public static bool IsElite(int? rank) => rank is >= 1 and <= 3;

    // A boss without a level is given this one or more.
    private const int NoLevel = 9999;

    public static JsonElement Build(string parsedDirectory, ExportConfig config)
    {
        List<T> Read<T>(string file) => JsonSerializer.Deserialize<List<T>>(File.ReadAllBytes(Path.Combine(parsedDirectory, file)), DataWriter.Json)!;
        return Build(Read<Quest>("quests.json"), Read<Npc>("npcs.json"), Read<Item>("items.json"), Read<Zone>("zones.json"), config);
    }

    public static JsonElement Build(List<Quest> quests, List<Npc> npcs, List<Item> itemRows, List<Zone> zoneRows, ExportConfig config)
    {
        var zones = zoneRows.ToDictionary(z => z.Id);
        var items = itemRows.ToDictionary(i => i.Id);

        // The map an open-world zone is drawn on: its own or its parent's. None for an instance.
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

        // npc -> the quests it is an objective of.
        var questsOf = new Dictionary<int, SortedSet<int>>();
        foreach (var quest in quests)
        {
            var objectives = quest.Objectives;
            var targets = (objectives?.Npcs ?? []).Select(t => t.Id)
                .Concat((objectives?.KillCredits ?? []).SelectMany(c => c.NpcIds))
                .Concat((objectives?.Items ?? []).SelectMany(t => items.GetValueOrDefault(t.Id)?.NpcDrops ?? []));
            foreach (var npcId in targets)
                (questsOf.TryGetValue(npcId, out var set) ? set : questsOf[npcId] = []).Add(quest.Id);
        }

        var byMap = new SortedDictionary<int, JsonArray>();
        foreach (var npc in npcs.Where(n => IsElite(n.Rank) && n.Name is not null && n.FriendlyTo != "AH" && n.Spawns is not null).OrderBy(n => n.Id))
        {
            var points = new SortedDictionary<int, List<Point>>();
            foreach (var (zoneId, list) in npc.Spawns!)
            {
                if (MapOf(zoneId) is not { } map) continue;
                (points.TryGetValue(map, out var onMap) ? onMap : points[map] = []).AddRange(list.Select(p => new Point(p[0], p[1])).Where(p => !p.IsPlaceholder));
            }
            foreach (var (map, onMap) in points.Where(p => p.Value.Count > 0))
            {
                var mob = new JsonObject { ["id"] = npc.Id, ["name"] = npc.Name };
                if ((npc.MaxLevel ?? npc.MinLevel) is { } level and > 0 and < NoLevel) mob["level"] = level;
                if (npc.FriendlyTo is { } side) mob["side"] = side;
                if (npc.Waypoints is not null) mob["patrols"] = true;
                if (questsOf.TryGetValue(npc.Id, out var own)) mob["quests"] = new JsonArray(own.Select(id => (JsonNode)id).ToArray());
                mob["at"] = new JsonArray(Spawns.Reduce(onMap, config).SelectMany(p => new JsonNode[] { p.X, p.Y }).ToArray());
                (byMap.TryGetValue(map, out var mobs) ? mobs : byMap[map] = []).Add(mob);
            }
        }
        return JsonSerializer.SerializeToElement(byMap.Select(pair => new JsonObject { ["id"] = pair.Key, ["mobs"] = pair.Value }));
    }
}
