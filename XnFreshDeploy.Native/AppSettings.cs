using System.IO;
using System.Text.Json;

namespace XnFreshDeploy;

public sealed class UserSettings
{
    public bool HasSeenFirstRun { get; set; }
    public bool WindowMaximized { get; set; }
    public double WindowLeft { get; set; } = double.NaN;
    public double WindowTop { get; set; } = double.NaN;
    public double WindowWidth { get; set; } = 1160;
    public double WindowHeight { get; set; } = 820;
    public string TagFilter { get; set; } = "";
    public string? SkippedUpdateVersion { get; set; }
}

public static class AppSettings
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    private static string Path => System.IO.Path.Combine(AppPaths.BaseDirectory, "settings.json");

    public static UserSettings Load()
    {
        try
        {
            if (!File.Exists(Path)) return new UserSettings();
            return JsonSerializer.Deserialize<UserSettings>(File.ReadAllText(Path), Json) ?? new UserSettings();
        }
        catch { return new UserSettings(); }
    }

    public static void Save(UserSettings settings)
    {
        try
        {
            var temp = Path + $".new-{Guid.NewGuid():N}";
            File.WriteAllText(temp, JsonSerializer.Serialize(settings, Json));
            File.Move(temp, Path, true);
        }
        catch { }
    }
}
