using System.Text.RegularExpressions;

namespace Collector.Fetch;

/// <summary>
/// The robots.txt group that applies to one user agent: the group naming its product token if
/// there is one, otherwise the <c>*</c> group. Longest matching rule wins; Allow wins a tie.
/// </summary>
public sealed class RobotsRules
{
    private readonly List<(bool Allow, string Pattern, Regex Regex)> _rules = [];

    public TimeSpan? CrawlDelay { get; private set; }

    /// <summary>The user-agent line of the group in effect, or null when no group applies.</summary>
    public string? MatchedGroup { get; private set; }

    public static RobotsRules AllowAll { get; } = new();

    public static RobotsRules Parse(string robotsTxt, string userAgent)
    {
        var token = ProductToken(userAgent);
        var groups = new List<(List<string> Agents, List<(string Field, string Value)> Lines)>();
        (List<string> Agents, List<(string, string)> Lines)? current = null;
        var lastWasAgent = false;

        foreach (var raw in robotsTxt.Split('\n'))
        {
            var line = raw.Split('#')[0].Trim();
            var colon = line.IndexOf(':');
            if (colon <= 0) continue;
            var field = line[..colon].Trim().ToLowerInvariant();
            var value = line[(colon + 1)..].Trim();

            if (field == "user-agent")
            {
                // Consecutive user-agent lines share one group.
                if (!lastWasAgent || current is null)
                {
                    current = ([], []);
                    groups.Add(current.Value);
                }
                current.Value.Agents.Add(value.ToLowerInvariant());
                lastWasAgent = true;
            }
            else
            {
                current?.Lines.Add((field, value));
                lastWasAgent = false;
            }
        }

        var chosen = groups.Where(g => g.Agents.Any(a => a != "*" && token.Contains(a, StringComparison.Ordinal))).ToList();
        if (chosen.Count == 0) chosen = groups.Where(g => g.Agents.Contains("*")).ToList();

        var rules = new RobotsRules();
        foreach (var group in chosen)
        {
            rules.MatchedGroup ??= string.Join(", ", group.Agents);
            foreach (var (field, value) in group.Lines)
            {
                if (field is "allow" or "disallow" && value.Length > 0)
                    rules._rules.Add((field == "allow", value, ToRegex(value)));
                else if (field == "crawl-delay" && double.TryParse(value, System.Globalization.CultureInfo.InvariantCulture, out var seconds))
                    rules.CrawlDelay = TimeSpan.FromSeconds(seconds);
            }
        }
        return rules;
    }

    public bool IsAllowed(Uri url)
    {
        var path = url.PathAndQuery;
        var best = _rules.Where(r => r.Regex.IsMatch(path))
            .OrderByDescending(r => r.Pattern.Length).ThenByDescending(r => r.Allow)
            .FirstOrDefault();
        return best.Pattern is null || best.Allow;
    }

    private static string ProductToken(string userAgent) =>
        userAgent.Split(' ', '/')[0].ToLowerInvariant();

    private static Regex ToRegex(string pattern)
    {
        var anchored = pattern.EndsWith('$');
        var body = string.Join(".*", (anchored ? pattern[..^1] : pattern).Split('*').Select(Regex.Escape));
        return new Regex("^" + body + (anchored ? "$" : ""), RegexOptions.CultureInvariant);
    }
}
