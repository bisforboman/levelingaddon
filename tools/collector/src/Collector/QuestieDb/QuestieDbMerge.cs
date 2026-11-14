using System.Text.Json;

namespace Collector.QuestieDb;

/// <summary>QuestieDB's Forever data after its own merge, as JSON documents.</summary>
public sealed record MergedDatabase(
    JsonDocument Quests, JsonDocument Npcs, JsonDocument Objects, JsonDocument Items, JsonDocument Reference, string LuaOutput) : IDisposable
{
    public void Dispose()
    {
        foreach (var document in new[] { Quests, Npcs, Objects, Items, Reference }) document.Dispose();
    }
}

/// <summary>
/// Produces QuestieDB's Forever data exactly as its generator bakes it: base tables, then every
/// Static Correction in manifest order, then its Derived Passes. All of that is QuestieDB's own
/// code, run in <see cref="LuaSandbox"/>; the driver below only asks for the result as JSON.
/// </summary>
public static class QuestieDbMerge
{
    public static MergedDatabase Run(string checkout)
    {
        using var sandbox = new LuaSandbox(checkout);
        var json = sandbox.Run(Driver, "=collector-driver", 5);
        return new MergedDatabase(JsonDocument.Parse(json[0]), JsonDocument.Parse(json[1]), JsonDocument.Parse(json[2]),
            JsonDocument.Parse(json[3]), JsonDocument.Parse(json[4]), sandbox.Output);
    }

    /// <summary>Runs a Lua snippet of ours against the checkout; a debugging aid.</summary>
    public static string RunSnippet(string checkout, string code)
    {
        using var sandbox = new LuaSandbox(checkout);
        return sandbox.Run(JsonEncoder + code, "=collector-snippet", 1)[0] + "\n" + sandbox.Output;
    }

    // Dense 1..n tables become arrays; anything else an object keyed by the stringified key.
    private const string JsonEncoder = """
        local function jsonString(s)
          return '"' .. s:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == '\\' then return '\\\\'
            elseif c == '\n' then return '\\n' elseif c == '\r' then return '\\r' elseif c == '\t' then return '\\t'
            else return string.format('\\u%04x', c:byte()) end
          end) .. '"'
        end
        local function jsonNumber(n)
          if n ~= n or n == math.huge or n == -math.huge then return 'null' end
          if n == math.floor(n) and n > -9e15 and n < 9e15 then return string.format('%d', n) end
          return string.format('%.14g', n)
        end
        local encode
        local function jsonKey(k)
          return type(k) == 'number' and '"' .. jsonNumber(k) .. '"' or jsonString(tostring(k))
        end
        encode = function(v, out)
          local t = type(v)
          if t == 'table' then
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            local dense = true
            for i = 1, count do if v[i] == nil then dense = false break end end
            if dense then
              out[#out + 1] = '['
              for i = 1, count do
                if i > 1 then out[#out + 1] = ',' end
                encode(v[i], out)
              end
              out[#out + 1] = ']'
            else
              local keys = {}
              for k in pairs(v) do keys[#keys + 1] = k end
              table.sort(keys, function(a, b)
                if type(a) == type(b) then return a < b end
                return type(a) == 'number'
              end)
              out[#out + 1] = '{'
              for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = ',' end
                out[#out + 1] = jsonKey(k)
                out[#out + 1] = ':'
                encode(v[k], out)
              end
              out[#out + 1] = '}'
            end
          elseif t == 'string' then out[#out + 1] = jsonString(v)
          elseif t == 'number' then out[#out + 1] = jsonNumber(v)
          elseif t == 'boolean' then out[#out + 1] = v and 'true' or 'false'
          else out[#out + 1] = 'null' end
        end
        local function toJson(v)
          local out = {}
          encode(v, out)
          return table.concat(out)
        end

        """;

    // Mirrors what generate.lua does for one flavor (generator/flavor.lua), and loads the support
    // tables the way src/support/data.lua does. Rows come back keyed by field name.
    private const string Driver = JsonEncoder + """
        local config = dofile("src/config.lua")
        local flavor = config.flavorByName.Forever
        local loaded, stats = dofile("generator/flavor.lua").load(flavor, nil, true)
        local runtime = dofile("generator/runtime.lua")
        local db = dofile("generator/corrections.lua").prepare(flavor).lib

        local function entityJson(name)
          local entry = loaded[name]
          local names = entry.meta.names
          local out, first = { '{' }, true
          local ids = {}
          for id in pairs(entry.entities) do ids[#ids + 1] = id end
          table.sort(ids)
          for _, id in ipairs(ids) do
            local row, named = entry.entities[id], {}
            for index, value in pairs(row) do named[names[index] or tostring(index)] = value end
            if not first then out[#out + 1] = ',' end
            first = false
            out[#out + 1] = '"' .. string.format('%d', id) .. '":'
            encode(named, out)
          end
          out[#out + 1] = '}'
          return table.concat(out)
        end

        -- Support data: quest XP and zone tables. Files that need more of the game client than
        -- the shim provides are reported, not guessed at.
        runtime.execute("src/support/data.lua", "QuestieDB", db)
        UnitFactionGroup = UnitFactionGroup or function() return "Alliance" end
        db.Support.Install(flavor)
        local skipped = {}
        for _, path in ipairs(config.supportData.perFlavor.Forever) do
          if path:find("/QuestXP/") or path:find("/Zones/") then
            local ok, err = pcall(runtime.execute, path, "QuestieDB", db)
            if not ok then skipped[#skipped + 1] = path .. ": " .. tostring(err) end
          end
        end
        local modules = db.Support.GetAll()
        db.Support.Remove()

        local zone = (modules.ZoneDB or {}).private or {}
        -- Zone tables arrive as a base payload plus an override payload; the override wins.
        local function zoneTable(name)
          local merged = {}
          for _, field in ipairs({ name, name .. "Override" }) do
            local value = zone[field]
            if type(value) == "string" then value = loadstring(value)() end
            if type(value) == "table" then for k, v in pairs(value) do merged[k] = v end end
          end
          return merged
        end
        -- Ids present before any correction: the Era baseline, as opposed to Forever additions.
        local baseQuestIds = {}
        for id in pairs(dofile("generator/flavor.lua").load(flavor, { Quest = true }, false).Quest.entities) do
          baseQuestIds[#baseQuestIds + 1] = id
        end
        table.sort(baseQuestIds)
        local shapes = {}
        for name, entry in pairs(loaded) do shapes[name] = { names = entry.meta.names, structures = entry.meta.structures } end

        -- Forever defines its own race masks and takes the rest from the rule set it builds on.
        local function enumFor(name)
          local byExpansion = db.Enum.byExpansion or {}
          return (byExpansion[flavor.expansion] or {})[name] or (byExpansion[flavor.rules or ""] or {})[name]
        end

        local reference = {
          zoneIDs = db.Enum.zoneIDs,
          raceKeys = enumFor("raceKeys"),
          classKeys = enumFor("classKeys"),
          sortKeys = db.Enum.sortKeys,
          questXp = (modules.QuestXP or {}).db,
          areaIdToUiMapId = zoneTable("areaIdToUiMapId"),
          subZoneToParentZone = zoneTable("subZoneToParentZone"),
          dungeons = zone.dungeons,
          baseQuestIds = baseQuestIds,
          shapes = shapes,
          skippedSupportFiles = skipped,
          correctionStats = stats,
        }
        return entityJson("Quest"), entityJson("Npc"), entityJson("Object"), entityJson("Item"), toJson(reference)
        """;
}
