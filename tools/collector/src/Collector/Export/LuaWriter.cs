using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Collector.Export;

/// <summary>The distinct string and number literals in a piece of Lua, which is what Lua 5.1 limits per file.</summary>
public sealed class LuaConstants
{
    private readonly HashSet<string> _strings = new(StringComparer.Ordinal);
    private readonly HashSet<double> _numbers = [];

    public int Count => _strings.Count + _numbers.Count;

    public void Add(string value) => _strings.Add(value);

    public void Add(double value)
    {
        // A negative literal may be stored as its magnitude, the folded negative, or both.
        _numbers.Add(value);
        _numbers.Add(Math.Abs(value));
    }

    public int CountNotIn(LuaConstants other) =>
        _strings.Count(s => !other._strings.Contains(s)) + _numbers.Count(n => !other._numbers.Contains(n));

    public void UnionWith(LuaConstants other)
    {
        _strings.UnionWith(other._strings);
        _numbers.UnionWith(other._numbers);
    }
}

/// <summary>
/// Writes a JSON value as a Lua 5.1 table constructor. Arrays become sequences; objects become
/// tables whose keys are numbers when the JSON key is an integer (zone ids, for instance) and
/// strings otherwise. Nothing is renamed or dropped.
/// </summary>
public static class LuaWriter
{
    private static readonly HashSet<string> Reserved = new(StringComparer.Ordinal)
    {
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
        "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
    };

    /// <param name="skipProperty">A top-level property to leave out, used for the id that becomes the table key.</param>
    public static void Write(StringBuilder lua, JsonElement value, LuaConstants constants, string? skipProperty = null)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                lua.Append('{');
                var first = true;
                foreach (var property in value.EnumerateObject())
                {
                    if (property.Name == skipProperty) continue;
                    if (!first) lua.Append(',');
                    first = false;
                    WriteKey(lua, property.Name, constants);
                    lua.Append('=');
                    Write(lua, property.Value, constants);
                }
                lua.Append('}');
                break;

            case JsonValueKind.Array:
                lua.Append('{');
                var index = 0;
                foreach (var element in value.EnumerateArray())
                {
                    if (index++ > 0) lua.Append(',');
                    Write(lua, element, constants);
                }
                lua.Append('}');
                break;

            case JsonValueKind.String:
                WriteString(lua, value.GetString()!, constants);
                break;

            case JsonValueKind.Number:
                WriteNumber(lua, value, constants);
                break;

            case JsonValueKind.True: lua.Append("true"); break;
            case JsonValueKind.False: lua.Append("false"); break;
            default: lua.Append("nil"); break;
        }
    }

    public static void WriteKey(StringBuilder lua, string key, LuaConstants constants)
    {
        if (IsInteger(key))
        {
            lua.Append('[').Append(key).Append(']');
            constants.Add(double.Parse(key, CultureInfo.InvariantCulture));
        }
        else if (IsIdentifier(key))
        {
            lua.Append(key);
            constants.Add(key);
        }
        else
        {
            lua.Append('[');
            WriteString(lua, key, constants);
            lua.Append(']');
        }
    }

    public static void WriteNumber(StringBuilder lua, JsonElement value, LuaConstants constants)
    {
        if (value.TryGetInt64(out var integer))
        {
            lua.Append(integer.ToString(CultureInfo.InvariantCulture));
            constants.Add(integer);
            return;
        }
        var number = value.GetDouble();
        lua.Append(number.ToString("R", CultureInfo.InvariantCulture));
        constants.Add(number);
    }

    public static void WriteString(StringBuilder lua, string text, LuaConstants constants)
    {
        constants.Add(text);
        lua.Append('"');
        foreach (var c in text)
        {
            switch (c)
            {
                case '"': lua.Append("\\\""); break;
                case '\\': lua.Append("\\\\"); break;
                case '\n': lua.Append("\\n"); break;
                case '\r': lua.Append("\\r"); break;
                case '\t': lua.Append("\\t"); break;
                // Three digits, so a following digit cannot be read as part of the escape.
                case < ' ' or '\u007f': lua.Append('\\').Append(((int)c).ToString("D3", CultureInfo.InvariantCulture)); break;
                default: lua.Append(c); break;
            }
        }
        lua.Append('"');
    }

    private static bool IsInteger(string key) =>
        key.Length is > 0 and <= 15 && (key == "0" || (key[0] is >= '1' and <= '9' || (key[0] == '-' && key.Length > 1 && key[1] is >= '1' and <= '9')))
        && key.AsSpan(1).IndexOfAnyExceptInRange('0', '9') < 0;

    private static bool IsIdentifier(string key) =>
        key.Length > 0 && !Reserved.Contains(key) && (char.IsAsciiLetter(key[0]) || key[0] == '_') &&
        key.All(c => char.IsAsciiLetterOrDigit(c) || c == '_');
}
