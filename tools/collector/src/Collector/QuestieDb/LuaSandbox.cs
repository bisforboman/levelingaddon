using System.Text;
using KeraLua;

namespace Collector.QuestieDb;

/// <summary>
/// Runs QuestieDB's own Lua sources so that its merge order and correction semantics are theirs,
/// not a reimplementation. The interpreter is reference Lua with only the basic, string, table
/// and math libraries opened: there is no os, io, package or debug library, chunks load as text
/// only, and the one way to reach a file is a read confined to the QuestieDB checkout.
/// </summary>
public sealed class LuaSandbox : IDisposable
{
    private readonly Lua _lua;
    private readonly string _root;
    private readonly StringBuilder _output = new();

    // Held in fields so the delegates outlive the native references to them.
    private readonly LuaFunction _read;
    private readonly LuaFunction _print;

    /// <summary>Everything the Lua side printed, for diagnostics.</summary>
    public string Output => _output.ToString();

    public LuaSandbox(string rootDirectory)
    {
        _root = Path.GetFullPath(rootDirectory);
        if (!Directory.Exists(_root))
            throw new DirectoryNotFoundException($"QuestieDB checkout not found: {_root}");

        _lua = new Lua(openLibs: false) { Encoding = Encoding.UTF8 };
        _lua.OpenBasicLibrary();
        _lua.SetTop(0);
        OpenAs("string", lua => lua.OpenStringLibrary());
        OpenAs("table", lua => lua.OpenTableLibrary());
        OpenAs("math", lua => lua.OpenMathLibrary());

        _read = ReadFile;
        _print = Print;
        _lua.Register("__collector_read", _read);
        _lua.Register("__collector_print", _print);
        Run(Prelude, "=collector-prelude", 0);
    }

    /// <summary>Runs a chunk of ours and returns the strings it returned.</summary>
    public string[] Run(string code, string chunkName, int results)
    {
        _lua.SetTop(0);
        var failed = _lua.LoadBuffer(Encoding.UTF8.GetBytes(code), chunkName, "t") != LuaStatus.OK
                     || _lua.PCall(0, results, 0) != LuaStatus.OK;
        if (failed)
        {
            var message = _lua.ToString(-1);
            _lua.SetTop(0);
            throw new InvalidOperationException($"Lua error: {message}\n{Output}".TrimEnd());
        }

        var values = new string[results];
        for (var i = 0; i < results; i++)
            values[i] = Encoding.UTF8.GetString(_lua.ToBuffer(i + 1) ?? []);
        _lua.SetTop(0);
        return values;
    }

    /// <summary>Resolves a path the Lua side asked for; null for anything outside the checkout.</summary>
    internal static string? ResolveInside(string root, string requested)
    {
        var full = Path.GetFullPath(Path.Combine(root, requested.Replace('\\', '/')));
        var prefix = root.EndsWith(Path.DirectorySeparatorChar) ? root : root + Path.DirectorySeparatorChar;
        return full.StartsWith(prefix, StringComparison.Ordinal) ? full : null;
    }

    private void OpenAs(string name, Action<Lua> open)
    {
        // Depending on the binding version the library table is left on the stack or already
        // published as a global; handle both, then insist that it is there.
        _lua.SetTop(0);
        open(_lua);
        if (_lua.GetTop() > 0 && _lua.IsTable(-1)) _lua.SetGlobal(name);
        _lua.SetTop(0);
        if (_lua.GetGlobal(name) != LuaType.Table)
            throw new InvalidOperationException($"Lua library '{name}' did not load.");
        _lua.SetTop(0);
    }

    // Lua: __collector_read(path) -> file contents, or nil when missing or outside the checkout.
    private int ReadFile(IntPtr state)
    {
        var lua = Lua.FromIntPtr(state);
        try
        {
            var path = lua.ToString(1);
            var full = path is null ? null : ResolveInside(_root, path);
            if (full is null || !File.Exists(full))
            {
                lua.PushNil();
                return 1;
            }
            var bytes = File.ReadAllBytes(full);
            var hasBom = bytes is [0xEF, 0xBB, 0xBF, ..];
            lua.PushBuffer(hasBom ? bytes[3..] : bytes);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            lua.PushNil();
        }
        return 1;
    }

    private int Print(IntPtr state)
    {
        _output.AppendLine(Lua.FromIntPtr(state).ToString(1));
        return 0;
    }

    public void Dispose() => _lua.Dispose();

    /// <summary>
    /// File access and the Lua 5.1 names QuestieDB's tooling expects, built on the single
    /// read function above. Nothing here can write, delete, or start a process.
    /// </summary>
    private const string Prelude = """
        local read, emit, rawload = __collector_read, __collector_print, load
        __collector_read, __collector_print = nil, nil

        load = function(chunk, name, _, env)
          if env ~= nil then return rawload(chunk, name, "t", env) end
          return rawload(chunk, name, "t")
        end
        loadstring = function(text, name) return rawload(text, name or "=(loadstring)", "t") end
        loadfile = function(path)
          local text = read(path)
          if not text then return nil, "cannot open " .. tostring(path) end
          -- As the stock loadfile does, ignore a leading "#!" line.
          if text:sub(1, 1) == "#" then text = "--" .. text end
          return rawload(text, "@" .. path, "t")
        end
        dofile = function(path)
          local chunk, err = loadfile(path)
          if not chunk then error(err, 2) end
          return chunk()
        end

        io = {
          open = function(path, mode)
            if mode and mode:find("[wa+]") then return nil, "sandbox: read-only" end
            local text = read(path)
            if not text then return nil, tostring(path) .. ": No such file or directory" end
            local consumed = false
            return {
              read = function()
                if consumed then return nil end
                consumed = true
                return text
              end,
              lines = function() return text:gmatch("([^\n]*)\n?") end,
              close = function() return true end,
            }
          end,
        }

        print = function(...)
          local parts = {}
          for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
          emit(table.concat(parts, "\t"))
        end

        -- Lua 5.1 spellings. QuestieDB's tooling refuses anything that does not report 5.1; the
        -- merge path uses only what is provided here, and setfenv fails loudly if ever reached.
        unpack = table.unpack
        table.getn = function(t) return #t end
        math.pow = function(a, b) return a ^ b end
        math.mod = math.fmod
        string.gfind = string.gmatch
        setfenv = function() error("sandbox: setfenv is not available", 2) end
        getfenv = setfenv
        arg = {}
        _VERSION = "Lua 5.1"
        -- Read once by generator/lib.lua to tell path separators apart; no loader behind it.
        package = { config = "/\n;\n?\n!\n-\n" }
        """;
}
