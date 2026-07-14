using System.IO;
using System.Text.Json;

namespace XnFreshDeploy;

public sealed class LegacyMigrationPreview
{
    public string SourceDirectory { get; init; } = "";
    public int ProfileCount { get; init; }
    public int SoundpackCount { get; init; }
    public int ReShadeCount { get; init; }
}

public sealed class LegacyMigrationResult
{
    public int Profiles { get; init; }
    public int Soundpacks { get; init; }
    public int ReShadeLooks { get; init; }
}

public static class LegacyMigrationService
{
    public static IReadOnlyList<LegacyMigrationPreview> FindCandidates()
    {
        var results = new List<LegacyMigrationPreview>();
        foreach (var root in CandidateRoots().Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var preview = Preview(root);
            if (preview is not null) results.Add(preview);
        }
        return results;
    }

    public static LegacyMigrationResult Migrate(string sourceDirectory, IList<ServerProfile> targetProfiles, DataService data)
    {
        var importedProfiles = 0;
        foreach (var profile in LoadProfiles(sourceDirectory))
        {
            if (targetProfiles.Any(x => x.Name.Equals(profile.Name, StringComparison.OrdinalIgnoreCase))) continue;
            targetProfiles.Add(profile);
            importedProfiles++;
        }
        data.SaveProfiles(targetProfiles);

        return new LegacyMigrationResult
        {
            Profiles = importedProfiles,
            Soundpacks = CopyLibraryFolders(Path.Combine(sourceDirectory, "Library", "Soundpacks"), AppPaths.SoundpacksDirectory),
            ReShadeLooks = CopyLibraryFolders(Path.Combine(sourceDirectory, "Library", "ReShade"), AppPaths.ReShadeDirectory)
        };
    }

    private static LegacyMigrationPreview? Preview(string root)
    {
        if (!Directory.Exists(root)) return null;
        if (string.Equals(Path.GetFullPath(root).TrimEnd('\\'), Path.GetFullPath(AppPaths.BaseDirectory).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
            return null;

        var isLegacy = File.Exists(Path.Combine(root, "Xn-Setup.ps1")) || File.Exists(Path.Combine(root, "Xn-Setup.bat"));
        var profiles = LoadProfiles(root);
        var soundpacks = CountPackFolders(Path.Combine(root, "Library", "Soundpacks"));
        var looks = CountPackFolders(Path.Combine(root, "Library", "ReShade"));
        if (!isLegacy && profiles.Count == 0 && soundpacks == 0 && looks == 0) return null;

        return new LegacyMigrationPreview
        {
            SourceDirectory = root,
            ProfileCount = profiles.Count,
            SoundpackCount = soundpacks,
            ReShadeCount = looks
        };
    }

    private static IEnumerable<string> CandidateRoots()
    {
        var parent = Directory.GetParent(AppPaths.BaseDirectory)?.FullName;
        if (parent is null) yield break;

        yield return Path.Combine(parent, "XnFreshDeploy");
        foreach (var sibling in Directory.EnumerateDirectories(parent))
            yield return sibling;
    }

    private static List<ServerProfile> LoadProfiles(string root)
    {
        var file = Path.Combine(root, "servers.json");
        if (!File.Exists(file)) return [];
        try
        {
            var store = JsonSerializer.Deserialize<ServerStore>(File.ReadAllText(file)) ?? new ServerStore();
            foreach (var profile in store.Servers)
            {
                profile.Commands ??= [];
                profile.Tags ??= [];
            }
            return store.Servers;
        }
        catch { return []; }
    }

    private static int CountPackFolders(string root)
    {
        if (!Directory.Exists(root)) return 0;
        return Directory.EnumerateDirectories(root).Count(IsPackFolder);
    }

    private static int CopyLibraryFolders(string sourceRoot, string destinationRoot)
    {
        if (!Directory.Exists(sourceRoot)) return 0;
        Directory.CreateDirectory(destinationRoot);
        var copied = 0;
        foreach (var folder in Directory.EnumerateDirectories(sourceRoot).Where(IsPackFolder))
        {
            var name = Path.GetFileName(folder);
            var target = Path.Combine(destinationRoot, name);
            if (Directory.Exists(target)) continue;
            CopyDirectory(folder, target);
            copied++;
        }
        return copied;
    }

    private static bool IsPackFolder(string path)
    {
        var name = Path.GetFileName(path);
        return !name.StartsWith('.') && !name.Contains("DROP", StringComparison.OrdinalIgnoreCase);
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, file);
            var target = Path.Combine(destination, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, true);
        }
    }
}
