using Collector.QuestieDb;

namespace Collector.Tests;

public sealed class LuaSandboxTests : IDisposable
{
    private readonly string _outside = Directory.CreateTempSubdirectory("collector-sandbox-").FullName;
    private readonly string _root;

    public LuaSandboxTests()
    {
        _root = Directory.CreateDirectory(Path.Combine(_outside, "checkout")).FullName;
        File.WriteAllText(Path.Combine(_root, "inside.lua"), "return 'inside'");
        File.WriteAllText(Path.Combine(_root, "script.lua"), "#!/usr/bin/env lua\nreturn 41 + 1");
        File.WriteAllText(Path.Combine(_outside, "secret.lua"), "return 'secret'");
    }

    public void Dispose() => Directory.Delete(_outside, recursive: true);

    private string Eval(string code)
    {
        using var sandbox = new LuaSandbox(_root);
        return sandbox.Run(code, "=test", 1)[0];
    }

    [Fact]
    public void There_is_no_operating_system_access() =>
        Assert.Equal("nil nil nil nil nil",
            Eval("return table.concat({ tostring(os), tostring(require), tostring(debug), tostring(io.popen), tostring(io.write) }, ' ')"));

    [Fact]
    public void Files_inside_the_checkout_can_be_read_and_run()
    {
        Assert.Equal("inside", Eval("return dofile('inside.lua')"));
        Assert.Equal("42", Eval("return tostring(dofile('script.lua'))"));
        Assert.Equal("return 'inside'", Eval("local f = io.open('inside.lua', 'r'); local text = f:read('*a'); f:close(); return text"));
    }

    [Theory]
    [InlineData("../secret.lua")]
    [InlineData("sub/../../secret.lua")]
    public void Files_outside_the_checkout_cannot_be_reached(string path)
    {
        Assert.Equal("nil", Eval($"return tostring(io.open('{path}', 'r'))"));
        Assert.Equal("nil", Eval($"return tostring((loadfile('{path}')))"));
        Assert.Equal("false", Eval($"return tostring((pcall(dofile, '{path}')))"));
    }

    [Fact]
    public void An_absolute_path_outside_the_checkout_cannot_be_reached() =>
        Assert.Equal("nil", Eval($"return tostring(io.open([[{Path.Combine(_outside, "secret.lua")}]], 'r'))"));

    [Fact]
    public void Nothing_can_be_opened_for_writing()
    {
        Assert.Equal("nil", Eval("return tostring((io.open('new.txt', 'w')))"));
        Assert.False(File.Exists(Path.Combine(_root, "new.txt")));
    }

    [Fact]
    public void Precompiled_chunks_are_refused() =>
        Assert.Equal("nil", Eval("return tostring((load(string.dump(function() return 1 end))))"));

    [Fact]
    public void A_lua_error_surfaces_with_its_message()
    {
        var error = Assert.Throws<InvalidOperationException>(() => Eval("error('boom')"));
        Assert.Contains("boom", error.Message);
    }
}
