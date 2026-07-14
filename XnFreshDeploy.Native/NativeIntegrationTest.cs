using System.IO;

namespace XnFreshDeploy;

internal static class NativeIntegrationTest
{
    public static async Task RunAsync()
    {
        AppPaths.EnsurePortableLayout();
        var data = new DataService();
        var config = data.LoadConfig();
        var sound = Path.Combine(AppPaths.SoundpacksDirectory, "Integration Sound");
        var look = Path.Combine(AppPaths.ReShadeDirectory, "Integration Look");
        Directory.CreateDirectory(sound);
        Directory.CreateDirectory(look);
        await File.WriteAllTextAsync(Path.Combine(sound, "audio.rpf"), "sound-test");
        await File.WriteAllTextAsync(Path.Combine(look, "preset.ini"), "look-test");
        var profiles = new List<ServerProfile>
        {
            new() { Name = "Integration", Connect = "abc123", Soundpack = "Integration Sound", Reshade = "Integration Look", Commands = [new() { Name = "cl_drawfps", Value = "1" }] }
        };

        var library = new LibraryService();
        var preview = await library.PreviewAsync(sound);
        if (preview.FileCount != 1 || preview.RiskyFiles.Count != 0) throw new InvalidOperationException("Library preview test failed.");

        var fiveM = Path.Combine(AppPaths.BaseDirectory, "IntegrationFiveM");
        var mods = Path.Combine(fiveM, "mods");
        var plugins = Path.Combine(fiveM, "plugins");
        Directory.CreateDirectory(mods);
        Directory.CreateDirectory(plugins);
        await File.WriteAllTextAsync(Path.Combine(mods, "previous.rpf"), "previous-sound");
        await File.WriteAllTextAsync(Path.Combine(plugins, "previous.ini"), "previous-look");
        await File.WriteAllTextAsync(Path.Combine(plugins, ".xn-reshade-managed.json"), "[\"previous.ini\"]");
        await File.WriteAllTextAsync(Path.Combine(plugins, ".xn-reshade"), "Previous Look");
        var packs = new PackService(fiveM);
        await packs.ApplyAsync(profiles[0]);
        if (!File.Exists(Path.Combine(mods, "audio.rpf")) || !File.Exists(Path.Combine(plugins, "preset.ini"))) throw new InvalidOperationException("Safe pack switch test failed.");
        if (!File.Exists(Path.Combine(sound, ".xn-hash-cache.json")) || !packs.CanRestorePrevious) throw new InvalidOperationException("Pack cache or rollback snapshot test failed.");
        await packs.RestorePreviousAsync();
        if (!File.Exists(Path.Combine(mods, "previous.rpf")) || !File.Exists(Path.Combine(plugins, "previous.ini")) || File.Exists(Path.Combine(plugins, "preset.ini")))
            throw new InvalidOperationException("Previous setup restore test failed.");

        var portable = new PortableBackupService();
        var backup = Path.Combine(AppPaths.BaseDirectory, "integration.xnportable.zip");
        await portable.ExportAsync(backup, profiles, config);
        var review = await portable.PreviewAsync(backup);
        if (review.Profiles != 1 || review.Soundpacks != 1 || review.ReShade != 1) throw new InvalidOperationException("Portable preview test failed.");
        Directory.Delete(sound, true);
        Directory.Delete(look, true);
        var imported = await portable.ImportAsync(backup);
        if (imported.Profiles.Count != 1 || imported.SoundpackCount != 1 || imported.ReShadeCount != 1) throw new InvalidOperationException("Portable import test failed.");
        if (!Directory.Exists(Path.Combine(AppPaths.SoundpacksDirectory, imported.Profiles[0].Soundpack))) throw new InvalidOperationException("Imported soundpack is missing.");
        if (!Directory.Exists(Path.Combine(AppPaths.ReShadeDirectory, imported.Profiles[0].Reshade))) throw new InvalidOperationException("Imported ReShade look is missing.");
    }
}
