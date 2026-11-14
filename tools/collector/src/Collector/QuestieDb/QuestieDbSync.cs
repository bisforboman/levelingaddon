using System.Diagnostics;

namespace Collector.QuestieDb;

/// <summary>
/// Keeps a checkout of QuestieDB at the pinned commit under the raw data folder. It only moves
/// files with git; nothing from the checkout is executed.
/// </summary>
public static class QuestieDbSync
{
    public static async Task<string> EnsureAsync(QuestieDbConfig config, string directory, Action<string> log)
    {
        if (Directory.Exists(Path.Combine(directory, ".git")) &&
            (await GitAsync(directory, "rev-parse", "HEAD")).Output.Trim() == config.Commit)
        {
            log($"QuestieDB already at {config.Commit[..10]} in {directory}; nothing fetched.");
            return directory;
        }

        Directory.CreateDirectory(directory);
        if (!Directory.Exists(Path.Combine(directory, ".git")))
        {
            await GitOrThrowAsync(directory, "init", "--quiet");
            await GitOrThrowAsync(directory, "remote", "add", "origin", config.Repository);
        }
        log($"Fetching QuestieDB {config.Commit[..10]} from {config.Repository} ...");
        await GitOrThrowAsync(directory, "fetch", "--quiet", "--depth", "1", "origin", config.Commit);
        await GitOrThrowAsync(directory, "-c", "advice.detachedHead=false", "checkout", "--quiet", "--force", config.Commit);
        log($"QuestieDB checked out at {config.Commit[..10]}.");
        return directory;
    }

    private static async Task GitOrThrowAsync(string directory, params string[] arguments)
    {
        var (exitCode, output) = await GitAsync(directory, arguments);
        if (exitCode != 0) throw new InvalidOperationException($"git {string.Join(' ', arguments)} failed ({exitCode}): {output.Trim()}");
    }

    private static async Task<(int ExitCode, string Output)> GitAsync(string directory, params string[] arguments)
    {
        var start = new ProcessStartInfo("git") { WorkingDirectory = directory, RedirectStandardOutput = true, RedirectStandardError = true };
        // LFS objects are not needed and are not served to anonymous clones.
        start.Environment["GIT_LFS_SKIP_SMUDGE"] = "1";
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start git.");
        var output = await process.StandardOutput.ReadToEndAsync() + await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return (process.ExitCode, output);
    }
}
