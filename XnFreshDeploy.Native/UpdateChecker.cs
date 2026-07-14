using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace XnFreshDeploy;

public sealed class UpdateInfo
{
    public string Version { get; init; } = "";
    public string Url { get; init; } = "";
    public string Notes { get; init; } = "";
}

public static class UpdateChecker
{
    public const string GitHubRepo = "WHOMEANSWHO/xn-fresh-deploy";

    private static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromSeconds(12),
        DefaultRequestHeaders = { { "User-Agent", "XnFreshDeploy" } }
    };

    public static string CurrentVersion
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version is null ? "4.1.0" : $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }

    public static async Task<UpdateInfo?> CheckAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var json = await Http.GetStringAsync($"https://api.github.com/repos/{GitHubRepo}/releases/latest", cancellationToken);
            var release = JsonSerializer.Deserialize<GitHubRelease>(json);
            if (release is null || release.TagName.Length == 0) return null;

            var latest = release.TagName.TrimStart('v', 'V');
            if (!IsNewer(latest, CurrentVersion)) return null;

            return new UpdateInfo
            {
                Version = latest,
                Url = release.HtmlUrl,
                Notes = release.Body?.Trim() ?? ""
            };
        }
        catch { return null; }
    }

    public static bool IsNewer(string latest, string current)
    {
        static int[] Parts(string value) => value.Split('.', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => int.TryParse(new string(part.TakeWhile(char.IsDigit).ToArray()), out var n) ? n : 0)
            .ToArray();

        var left = Parts(latest);
        var right = Parts(current);
        var count = Math.Max(left.Length, right.Length);
        for (var i = 0; i < count; i++)
        {
            var a = i < left.Length ? left[i] : 0;
            var b = i < right.Length ? right[i] : 0;
            if (a != b) return a > b;
        }
        return false;
    }

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; set; } = "";

        [JsonPropertyName("html_url")]
        public string HtmlUrl { get; set; } = "";

        [JsonPropertyName("body")]
        public string? Body { get; set; }
    }
}
