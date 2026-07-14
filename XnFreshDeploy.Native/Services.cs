using Microsoft.Win32;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Management;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace XnFreshDeploy;

public static class AppPaths
{
    public static string BaseDirectory { get; } = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
    public static string ServersFile => Path.Combine(BaseDirectory, "servers.json");
    public static string ConfigFile => Path.Combine(BaseDirectory, "config.json");
    public static string LibraryDirectory => Path.Combine(BaseDirectory, "Library");
    public static string SoundpacksDirectory => Path.Combine(LibraryDirectory, "Soundpacks");
    public static string ReShadeDirectory => Path.Combine(LibraryDirectory, "ReShade");
    public static string DriversDirectory => Path.Combine(BaseDirectory, "Drivers");
    public static string BackupDirectory => Path.Combine(BaseDirectory, "Backup");

    public static void EnsurePortableLayout()
    {
        foreach (var directory in new[] { LibraryDirectory, SoundpacksDirectory, ReShadeDirectory, DriversDirectory })
            Directory.CreateDirectory(directory);

        var probe = Path.Combine(BaseDirectory, $".xn-write-{Guid.NewGuid():N}");
        try { File.WriteAllText(probe, "ok"); }
        catch (Exception ex) { throw new InvalidOperationException("Move Xn Fresh Deploy to a writable folder such as Documents, Desktop, another drive, or a USB stick.", ex); }
        finally { try { File.Delete(probe); } catch { } }
    }
}

public sealed class DataService
{
    private readonly JsonSerializerOptions _json = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    public AppConfig LoadConfig()
    {
        if (!File.Exists(AppPaths.ConfigFile)) SaveAtomic(AppPaths.ConfigFile, DefaultConfig());
        var config = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(AppPaths.ConfigFile), _json) ?? DefaultConfig();
        ValidateConfig(config);
        return config;
    }

    public List<ServerProfile> LoadProfiles()
    {
        if (!File.Exists(AppPaths.ServersFile)) SaveProfiles([]);
        try
        {
            var store = JsonSerializer.Deserialize<ServerStore>(File.ReadAllText(AppPaths.ServersFile), _json) ?? new ServerStore();
            foreach (var profile in store.Servers)
            {
                profile.Commands ??= [];
                profile.Tags ??= [];
                profile.Soundpack = string.IsNullOrWhiteSpace(profile.Soundpack) ? "None" : profile.Soundpack;
                profile.Reshade = string.IsNullOrWhiteSpace(profile.Reshade) ? "Keep current" : profile.Reshade;
            }
            return store.Servers;
        }
        catch (Exception ex) { throw new InvalidDataException("servers.json is damaged or contains unsupported data.", ex); }
    }

    public void SaveProfiles(IEnumerable<ServerProfile> profiles) =>
        SaveAtomic(AppPaths.ServersFile, new ServerStore { Servers = profiles.ToList() });

    public void ExportProfiles(string path, IEnumerable<ServerProfile> profiles) =>
        SaveAtomic(path, new ProfileBundle { Servers = profiles.Select(CloneForStorage).ToList() });

    public List<ServerProfile> ImportProfiles(string path)
    {
        var bundle = JsonSerializer.Deserialize<ProfileBundle>(File.ReadAllText(path), _json)
                     ?? throw new InvalidDataException("The profile backup is empty.");
        if (bundle.Format != "XnFreshDeployProfiles" || bundle.Version is < 1 or > 2)
            throw new InvalidDataException("That file is not a supported Xn Fresh Deploy profile backup.");
        if (bundle.Servers.Count > 500) throw new InvalidDataException("The backup contains too many profiles.");
        return bundle.Servers;
    }

    private void SaveAtomic<T>(string path, T value)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
        var temporary = path + $".new-{Guid.NewGuid():N}";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(value, _json));
            _ = JsonDocument.Parse(File.ReadAllText(temporary));
            File.Move(temporary, path, true);
        }
        finally { try { File.Delete(temporary); } catch { } }
    }

    private static void ValidateConfig(AppConfig config)
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var app in config.Apps)
        {
            if (string.IsNullOrWhiteSpace(app.Name) || !Regex.IsMatch(app.WingetId, "^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$"))
                throw new InvalidDataException("Every configured app needs a valid name and exact winget ID.");
            if (!names.Add(app.Name)) throw new InvalidDataException($"The app name '{app.Name}' is listed more than once.");
        }
    }

    private static ServerProfile CloneForStorage(ServerProfile source) => new()
    {
        Name = source.Name,
        Connect = source.Connect,
        Soundpack = source.Soundpack,
        Reshade = source.Reshade,
        Commands = source.Commands.Select(x => x.Clone()).ToList(),
        LastPlayed = source.LastPlayed,
        Favorite = source.Favorite,
        Folder = source.Folder,
        Tags = source.Tags.Select(x => x).ToList()
    };

    private static AppConfig DefaultConfig() => new()
    {
        Apps =
        [
            new() { Name = "7-Zip", Description = "Archive utility used by setup and driver packages", WingetId = "7zip.7zip", SelectedByDefault = true },
            new() { Name = "Brave Browser", Description = "Privacy-focused web browser", WingetId = "Brave.Brave", LaunchAfter = true },
            new() { Name = "Steam", Description = "Game launcher", WingetId = "Valve.Steam", LaunchAfter = true },
            new() { Name = "Discord", Description = "Voice and community chat", WingetId = "Discord.Discord", LaunchAfter = true },
            new() { Name = "OBS Studio", Description = "Recording and streaming", WingetId = "OBSProject.OBSStudio" },
            new() { Name = "Git", Description = "Version control tools", WingetId = "Git.Git" },
            new() { Name = "Node.js LTS", Description = "JavaScript development runtime", WingetId = "OpenJS.NodeJS.LTS" }
        ]
    };
}

public static class CommandCatalog
{
    public static List<CommandOption> Create() =>
    [
        Option("fps_counter", "FPS counter  |  cl_drawfps 1  |  Small counter in the top-left", "cl_drawfps", "1"),
        Option("crosshair_off", "Crosshair off  |  profile_reticulesize -10", "profile_reticulesize", "-10", group: "reticule"),
        Option("crosshair_on", "Crosshair on  |  profile_reticulesize 0", "profile_reticulesize", "0", group: "reticule"),
        Option("gamma", "Brightness 35  |  profile_gamma 35", "profile_gamma", "35"),
        Option("aim_accel", "Aim acceleration off  |  profile_aimAcceleration 0", "profile_aimAcceleration", "0"),
        Option("mouse_accel", "Mouse acceleration off  |  profile_mouseAcceleration 0", "profile_mouseAcceleration", "0"),
        Option("mouse_foot_zero", "On-foot mouse scale 0  |  profile_mouseOnFootScale 0", "profile_mouseOnFootScale", "0"),
        Option("mouse_accel_lower", "Mouse acceleration off (lowercase)  |  profile_mouseacceleration 0", "profile_mouseacceleration", "0"),
        Option("mouse_foot_custom", "Custom on-foot mouse scale  |  profile_mouseonfootscale [value]", "profile_mouseonfootscale", valueKey: "MouseScale"),
        Option("first_person_fov", "First-person field of view  |  profile_fpsFieldOfView [value]", "profile_fpsFieldOfView", valueKey: "Fov"),
        Option("sync_audio", "Synchronous audio  |  game_useSynchronousAudio true", "game_useSynchronousAudio", "true"),
        Option("download_backoff", "Faster server downloads  |  cl_rcdFailureBackoff 0", "cl_rcdFailureBackoff", "0")
    ];

    public static void Validate(ProfileCommand command)
    {
        command.Name = command.Name.Trim();
        if (!Regex.IsMatch(command.Name, "^[A-Za-z_][A-Za-z0-9_.-]{0,63}$"))
            throw new InvalidDataException("Command names may contain letters, numbers, underscores, dots, and dashes.");
        if (command.Value.Length > 256 || command.Value.Any(char.IsControl) || command.Value.Contains('"'))
            throw new InvalidDataException($"The value for '{command.Name}' contains unsupported characters or is too long.");
    }

    public static List<ProfileCommand> ToCommands(IEnumerable<CommandOption> options)
    {
        var commands = new List<ProfileCommand>();
        var groups = new HashSet<string>(StringComparer.Ordinal);
        foreach (var option in options.Where(x => x.IsSelected))
        {
            if (option.Group.Length > 0 && !groups.Add(option.Group))
                throw new InvalidDataException("Choose either Crosshair off or Crosshair on, not both.");
            var value = option.EffectiveValue;
            if (option.NeedsValue && !Regex.IsMatch(value, "^[+-]?(?:\\d+(?:\\.\\d+)?|\\.\\d+)$"))
                throw new InvalidDataException($"Enter a number for {option.Label.Split('|')[0].Trim()}.");
            var command = new ProfileCommand { Name = option.Name, Value = value };
            Validate(command);
            commands.Add(command);
        }
        if (commands.Count > 20) throw new InvalidDataException("Each profile can contain up to 20 server commands.");
        return commands;
    }

    public static List<CommandOption> FromCommands(IEnumerable<ProfileCommand> commands)
    {
        var options = Create();
        foreach (var command in commands)
        {
            Validate(command);
            var match = options.FirstOrDefault(x => x.Name == command.Name && (x.NeedsValue || x.Value == command.Value));
            if (match is null)
            {
                match = Option($"custom_{Guid.NewGuid():N}", $"Custom  |  {command.Name} {command.Value}", command.Name, command.Value, custom: true);
                options.Add(match);
            }
            match.IsSelected = true;
            if (match.NeedsValue) match.InputValue = command.Value;
        }
        return options;
    }

    public static CommandOption AddCustom(IList<CommandOption> options, string name, string value)
    {
        var command = new ProfileCommand { Name = name, Value = value };
        Validate(command);
        foreach (var existing in options.Where(x => x.Name == command.Name).ToList())
        {
            existing.IsSelected = false;
            if (existing.IsCustom) options.Remove(existing);
        }
        var builtIn = options.FirstOrDefault(x => !x.NeedsValue && x.Name == command.Name && x.Value == command.Value);
        if (builtIn is not null) { builtIn.IsSelected = true; return builtIn; }
        var custom = Option($"custom_{Guid.NewGuid():N}", $"Custom  |  {command.Name} {command.Value}", command.Name, command.Value, custom: true);
        custom.IsSelected = true;
        options.Add(custom);
        return custom;
    }

    private static CommandOption Option(string id, string label, string name, string value = "", string valueKey = "", string group = "", bool custom = false) =>
        new() { Id = id, Label = label, Name = name, Value = value, ValueKey = valueKey, Group = group, IsCustom = custom };
}

public sealed class ServerApi
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(7) };

    public async Task<ServerTestResult> TestAsync(string connect, CancellationToken cancellationToken = default)
    {
        var target = FiveMService.NormalizeConnectTarget(connect);
        if (target.Length == 0) return new() { Detail = "Enter a connect code or IP first." };
        try
        {
            if (Regex.IsMatch(target, "^[A-Za-z0-9]{4,12}$"))
            {
                using var document = JsonDocument.Parse(await _http.GetStringAsync($"https://servers-frontend.fivem.net/api/servers/single/{target}", cancellationToken));
                var data = document.RootElement.GetProperty("Data");
                var name = ReadServerName(data);
                var players = data.TryGetProperty("clients", out var clients) && data.TryGetProperty("svMaxclients", out var max)
                    ? $"{clients.GetInt32()}/{max.GetInt32()} players" : "";
                return new() { Online = true, Name = name, Players = players, Detail = "Connect code verified by Cfx.re." };
            }

            var endpoint = target;
            if (!Regex.IsMatch(endpoint, @":\d+$") && !endpoint.Contains('/')) endpoint += ":30120";
            var baseUri = endpoint.StartsWith("http", StringComparison.OrdinalIgnoreCase) ? endpoint.TrimEnd('/') : "http://" + endpoint.TrimEnd('/');
            using var info = JsonDocument.Parse(await _http.GetStringAsync(baseUri + "/info.json", cancellationToken));
            return new() { Online = true, Name = ReadServerName(info.RootElement), Detail = "FiveM info.json responded." };
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) { return new() { Detail = "Server is offline or could not be verified: " + ex.Message }; }
    }

    private static string ReadServerName(JsonElement element)
    {
        if (element.TryGetProperty("vars", out var vars))
        {
            if (vars.TryGetProperty("sv_projectName", out var project)) return project.GetString() ?? "";
            if (vars.TryGetProperty("sv_hostname", out var host)) return host.GetString() ?? "";
        }
        return element.TryGetProperty("hostname", out var hostname) ? hostname.GetString() ?? "" : "";
    }
}

public sealed class ServerDetectionService
{
    private static readonly Regex JoinCodePattern = new(@"(?i)cfx\.re/join/([a-z0-9]{4,12})", RegexOptions.Compiled);
    private static readonly Regex EndpointPattern = new(@"(?i)(?:connect(?:ing|ed)?(?:\s+to)?|server\s+endpoint|resolved\s+endpoint).*?((?:\d{1,3}\.){3}\d{1,3}:\d{2,5})", RegexOptions.Compiled);
    private readonly ServerApi _serverApi;

    public ServerDetectionService(ServerApi serverApi) => _serverApi = serverApi;

    public async Task<ServerHint?> DetectAsync(CancellationToken cancellationToken = default)
    {
        var logsDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FiveM", "FiveM.app", "logs");
        if (!Directory.Exists(logsDirectory)) return null;
        var logs = Directory.EnumerateFiles(logsDirectory, "CitizenFX_log_*.log")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .Take(3);
        string? endpoint = null;
        foreach (var log in logs)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var text = await ReadTailAsync(log, 1_000_000, cancellationToken);
            var codeMatches = JoinCodePattern.Matches(text);
            if (codeMatches.Count > 0)
            {
                var code = codeMatches[^1].Groups[1].Value;
                var test = await _serverApi.TestAsync(code, cancellationToken);
                return new ServerHint { Connect = code, Name = test.Name, Source = "recent FiveM connect code" };
            }
            var endpointMatches = EndpointPattern.Matches(text);
            if (endpointMatches.Count > 0) endpoint ??= endpointMatches[^1].Groups[1].Value;
        }
        if (endpoint is null) return null;
        var result = await _serverApi.TestAsync(endpoint, cancellationToken);
        return new ServerHint { Connect = endpoint, Name = result.Name, Source = "recent FiveM server endpoint" };
    }

    private static async Task<string> ReadTailAsync(string path, int maximumBytes, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 4096, true);
        if (stream.Length > maximumBytes) stream.Seek(-maximumBytes, SeekOrigin.End);
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync(cancellationToken);
    }
}

public static class ShortcutService
{
    public static string PathFor(string profileName)
    {
        var safeName = string.Concat(profileName.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), safeName + ".lnk");
    }

    public static void Create(ServerProfile profile)
    {
        var shellType = Type.GetTypeFromProgID("WScript.Shell") ?? throw new InvalidOperationException("Windows shortcut support is unavailable.");
        dynamic shell = Activator.CreateInstance(shellType)!;
        dynamic shortcut = shell.CreateShortcut(PathFor(profile.Name));
        shortcut.TargetPath = Environment.ProcessPath;
        shortcut.Arguments = $"--play \"{profile.Name.Replace("\"", "")}\"";
        shortcut.WorkingDirectory = AppPaths.BaseDirectory;
        shortcut.Description = $"Play {profile.Name} through Xn Fresh Deploy";
        shortcut.Save();
    }

    public static void UpdateIfPresent(string previousName, ServerProfile profile)
    {
        var previous = PathFor(previousName);
        if (!File.Exists(previous)) return;
        if (!previous.Equals(PathFor(profile.Name), StringComparison.OrdinalIgnoreCase)) File.Delete(previous);
        Create(profile);
    }

    public static void DeleteIfPresent(string profileName)
    {
        var path = PathFor(profileName);
        if (File.Exists(path)) File.Delete(path);
    }
}

public sealed class PackService
{
    private readonly string _appDirectory;
    private string SoundJournalPath => Path.Combine(_appDirectory, ".xn-sound-switch.json");
    private string ReShadeJournalPath => Path.Combine(_appDirectory, ".xn-reshade-switch.json");
    private string PreviousModsPath => Path.Combine(_appDirectory, ".xn-previous-mods");
    private string PreviousReShadePath => Path.Combine(_appDirectory, ".xn-previous-reshade");

    public PackService(string? appDirectory = null) =>
        _appDirectory = appDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FiveM", "FiveM.app");

    public void RecoverInterruptedSwitches()
    {
        if (!Directory.Exists(_appDirectory)) return;
        var mods = Path.Combine(_appDirectory, "mods");
        if (File.Exists(SoundJournalPath))
        {
            var journal = ReadJournal<SoundSwitchJournal>(SoundJournalPath);
            var rollback = SafeChildPath(_appDirectory, journal.RollbackFolder);
            var stage = SafeChildPath(_appDirectory, journal.StageFolder);
            if (Directory.Exists(mods)) SafeDeleteDirectory(mods);
            if (journal.HadPreviousMods && Directory.Exists(rollback)) Directory.Move(rollback, mods);
            SafeDeleteDirectory(stage);
            File.Delete(SoundJournalPath);
        }
        else
        {
            var rollbacks = Directory.GetDirectories(_appDirectory, ".xn-mods-rollback-*").OrderByDescending(Directory.GetLastWriteTimeUtc).ToList();
            if (!Directory.Exists(mods) && rollbacks.Count > 0)
            {
                Directory.Move(rollbacks[0], mods);
                rollbacks.RemoveAt(0);
            }
            else if (Directory.Exists(mods) && rollbacks.Count > 0)
            {
                SafeDeleteDirectory(PreviousModsPath);
                Directory.Move(rollbacks[0], PreviousModsPath);
                rollbacks.RemoveAt(0);
            }
            foreach (var folder in rollbacks) SafeDeleteDirectory(folder);
        }
        foreach (var folder in Directory.GetDirectories(_appDirectory, ".xn-mods-stage-*")) SafeDeleteDirectory(folder);

        if (File.Exists(ReShadeJournalPath)) RecoverReShadeJournal();
        foreach (var folder in Directory.GetDirectories(_appDirectory, ".xn-reshade-stage-*")) SafeDeleteDirectory(folder);
        foreach (var folder in Directory.GetDirectories(_appDirectory, ".xn-reshade-rollback-*")) SafeDeleteDirectory(folder);
    }

    public bool CanRestorePrevious => Directory.Exists(PreviousModsPath) || File.Exists(Path.Combine(PreviousReShadePath, "state.json"));

    public async Task ApplyAsync(ServerProfile profile, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(_appDirectory)) throw new DirectoryNotFoundException("Open FiveM once before applying a profile.");
        if (!string.Equals(profile.Soundpack, "None", StringComparison.OrdinalIgnoreCase))
        {
            progress?.Report("Verifying soundpack...");
            await ApplySoundpackAsync(profile.Soundpack, cancellationToken);
        }
        if (!string.Equals(profile.Reshade, "Keep current", StringComparison.OrdinalIgnoreCase))
        {
            progress?.Report("Applying ReShade look...");
            await ApplyReShadeAsync(profile.Reshade, cancellationToken);
        }
    }

    private async Task ApplySoundpackAsync(string name, CancellationToken cancellationToken)
    {
        var source = SafeLibraryPath(AppPaths.SoundpacksDirectory, name);
        if (!Directory.Exists(source)) throw new DirectoryNotFoundException($"Soundpack '{name}' is missing from the library.");
        var stage = Path.Combine(_appDirectory, $".xn-mods-stage-{Guid.NewGuid():N}");
        var rollback = Path.Combine(_appDirectory, $".xn-mods-rollback-{Guid.NewGuid():N}");
        var mods = Path.Combine(_appDirectory, "mods");
        try
        {
            await CopyTreeVerifiedAsync(source, stage, cancellationToken);
            WriteJournal(SoundJournalPath, new SoundSwitchJournal
            {
                StageFolder = Path.GetFileName(stage),
                RollbackFolder = Path.GetFileName(rollback),
                HadPreviousMods = Directory.Exists(mods)
            });
            if (Directory.Exists(mods)) Directory.Move(mods, rollback);
            Directory.Move(stage, mods);
            File.WriteAllText(Path.Combine(mods, ".xn-current"), name);
            File.Delete(SoundJournalPath);
            SafeDeleteDirectory(PreviousModsPath);
            if (Directory.Exists(rollback)) Directory.Move(rollback, PreviousModsPath);
        }
        catch
        {
            if (File.Exists(SoundJournalPath))
            {
                if (Directory.Exists(mods)) SafeDeleteDirectory(mods);
                if (Directory.Exists(rollback)) Directory.Move(rollback, mods);
                File.Delete(SoundJournalPath);
            }
            throw;
        }
        finally { SafeDeleteDirectory(stage); SafeDeleteDirectory(rollback); }
    }

    private async Task ApplyReShadeAsync(string name, CancellationToken cancellationToken)
    {
        var source = SafeLibraryPath(AppPaths.ReShadeDirectory, name);
        if (!Directory.Exists(source)) throw new DirectoryNotFoundException($"ReShade look '{name}' is missing from the library.");
        var plugins = Path.Combine(_appDirectory, "plugins");
        Directory.CreateDirectory(plugins);
        var stage = Path.Combine(_appDirectory, $".xn-reshade-stage-{Guid.NewGuid():N}");
        var rollback = Path.Combine(_appDirectory, $".xn-reshade-rollback-{Guid.NewGuid():N}");
        var manifestPath = Path.Combine(plugins, ".xn-reshade-managed.json");
        var markerPath = Path.Combine(plugins, ".xn-reshade");
        var newFiles = new List<string>();
        var oldFiles = new List<string>();
        string? oldManifest = null;
        string? oldMarker = null;
        try
        {
            await CopyTreeVerifiedAsync(source, stage, cancellationToken);
            newFiles = RelativeFiles(stage).ToList();
            oldManifest = File.Exists(manifestPath) ? File.ReadAllText(manifestPath) : null;
            oldMarker = File.Exists(markerPath) ? File.ReadAllText(markerPath) : null;
            oldFiles = oldManifest is null ? [] : JsonSerializer.Deserialize<List<string>>(oldManifest) ?? [];
            SaveCurrentReShadeSnapshot(plugins, oldFiles, oldManifest, oldMarker);
            Directory.CreateDirectory(rollback);
            foreach (var relative in oldFiles.Concat(newFiles).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                var target = SafeChildPath(plugins, relative);
                if (!File.Exists(target)) continue;
                var backup = SafeChildPath(rollback, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(backup)!);
                File.Copy(target, backup, true);
            }
            WriteJournal(ReShadeJournalPath, new ReShadeSwitchJournal
            {
                StageFolder = Path.GetFileName(stage),
                RollbackFolder = Path.GetFileName(rollback),
                NewFiles = newFiles,
                OldManifest = oldManifest,
                OldMarker = oldMarker
            });
            foreach (var relative in oldFiles)
            {
                var target = SafeChildPath(plugins, relative);
                if (File.Exists(target)) File.Delete(target);
            }
            foreach (var relative in newFiles)
            {
                var from = SafeChildPath(stage, relative);
                var to = SafeChildPath(plugins, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(to)!);
                File.Copy(from, to, true);
            }
            File.WriteAllText(manifestPath, JsonSerializer.Serialize(newFiles));
            File.WriteAllText(markerPath, name);
            File.Delete(ReShadeJournalPath);
        }
        catch
        {
            RestoreReShadeFiles(plugins, rollback, newFiles, oldManifest, oldMarker);
            try { File.Delete(ReShadeJournalPath); } catch { }
            throw;
        }
        finally { SafeDeleteDirectory(stage); SafeDeleteDirectory(rollback); }
    }

    public async Task RestorePreviousAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (!CanRestorePrevious) throw new InvalidOperationException("There is no previous soundpack or ReShade setup to restore.");
        var mods = Path.Combine(_appDirectory, "mods");
        if (Directory.Exists(PreviousModsPath))
        {
            progress?.Report("Restoring the previous soundpack...");
            var current = Path.Combine(_appDirectory, $".xn-mods-current-{Guid.NewGuid():N}");
            try
            {
                if (Directory.Exists(mods)) Directory.Move(mods, current);
                Directory.Move(PreviousModsPath, mods);
                if (Directory.Exists(current)) Directory.Move(current, PreviousModsPath);
            }
            catch
            {
                if (!Directory.Exists(mods) && Directory.Exists(current)) Directory.Move(current, mods);
                throw;
            }
            finally { SafeDeleteDirectory(current); }
        }

        var previousStatePath = Path.Combine(PreviousReShadePath, "state.json");
        if (File.Exists(previousStatePath))
        {
            progress?.Report("Restoring the previous ReShade look...");
            var plugins = Path.Combine(_appDirectory, "plugins");
            Directory.CreateDirectory(plugins);
            var currentSnapshot = Path.Combine(_appDirectory, $".xn-reshade-current-{Guid.NewGuid():N}");
            SaveReShadeSnapshot(plugins, currentSnapshot);
            try
            {
                RestoreReShadeSnapshot(plugins, PreviousReShadePath, cancellationToken);
                SafeDeleteDirectory(PreviousReShadePath);
                Directory.Move(currentSnapshot, PreviousReShadePath);
            }
            catch
            {
                try { RestoreReShadeSnapshot(plugins, currentSnapshot, CancellationToken.None); } catch { }
                SafeDeleteDirectory(currentSnapshot);
                throw;
            }
        }
        await Task.CompletedTask;
    }

    private void RecoverReShadeJournal()
    {
        var journal = ReadJournal<ReShadeSwitchJournal>(ReShadeJournalPath);
        var plugins = Path.Combine(_appDirectory, "plugins");
        var rollback = SafeChildPath(_appDirectory, journal.RollbackFolder);
        var stage = SafeChildPath(_appDirectory, journal.StageFolder);
        RestoreReShadeFiles(plugins, rollback, journal.NewFiles, journal.OldManifest, journal.OldMarker);
        SafeDeleteDirectory(stage);
        SafeDeleteDirectory(rollback);
        File.Delete(ReShadeJournalPath);
    }

    private void SaveCurrentReShadeSnapshot(string plugins, List<string> oldFiles, string? oldManifest, string? oldMarker)
    {
        var stage = Path.Combine(_appDirectory, $".xn-previous-reshade-stage-{Guid.NewGuid():N}");
        try
        {
            var filesRoot = Path.Combine(stage, "files");
            foreach (var relative in oldFiles)
            {
                var source = SafeChildPath(plugins, relative);
                if (!File.Exists(source)) continue;
                var target = SafeChildPath(filesRoot, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                File.Copy(source, target, true);
            }
            Directory.CreateDirectory(stage);
            WriteJournal(Path.Combine(stage, "state.json"), new ReShadeSnapshot { Files = oldFiles.Where(x => File.Exists(SafeChildPath(plugins, x))).ToList(), Manifest = oldManifest, Marker = oldMarker });
            SafeDeleteDirectory(PreviousReShadePath);
            Directory.Move(stage, PreviousReShadePath);
        }
        finally { SafeDeleteDirectory(stage); }
    }

    private static void SaveReShadeSnapshot(string plugins, string destination)
    {
        var manifestPath = Path.Combine(plugins, ".xn-reshade-managed.json");
        var manifest = File.Exists(manifestPath) ? File.ReadAllText(manifestPath) : null;
        var markerPath = Path.Combine(plugins, ".xn-reshade");
        var marker = File.Exists(markerPath) ? File.ReadAllText(markerPath) : null;
        var files = manifest is null ? [] : JsonSerializer.Deserialize<List<string>>(manifest) ?? [];
        var copied = new List<string>();
        foreach (var relative in files)
        {
            var source = SafeChildPath(plugins, relative);
            if (!File.Exists(source)) continue;
            var target = SafeChildPath(Path.Combine(destination, "files"), relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(source, target, true);
            copied.Add(relative);
        }
        Directory.CreateDirectory(destination);
        WriteJournal(Path.Combine(destination, "state.json"), new ReShadeSnapshot { Files = copied, Manifest = manifest, Marker = marker });
    }

    private static void RestoreReShadeSnapshot(string plugins, string snapshot, CancellationToken cancellationToken)
    {
        var state = ReadJournal<ReShadeSnapshot>(Path.Combine(snapshot, "state.json"));
        var currentManifestPath = Path.Combine(plugins, ".xn-reshade-managed.json");
        var currentFiles = File.Exists(currentManifestPath)
            ? JsonSerializer.Deserialize<List<string>>(File.ReadAllText(currentManifestPath)) ?? [] : [];
        foreach (var relative in currentFiles)
        {
            var target = SafeChildPath(plugins, relative);
            if (File.Exists(target)) File.Delete(target);
        }
        foreach (var relative in state.Files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var from = SafeChildPath(Path.Combine(snapshot, "files"), relative);
            var to = SafeChildPath(plugins, relative);
            if (!File.Exists(from)) throw new IOException("The previous ReShade snapshot is incomplete.");
            Directory.CreateDirectory(Path.GetDirectoryName(to)!);
            File.Copy(from, to, true);
        }
        RestoreTextFile(currentManifestPath, state.Manifest);
        RestoreTextFile(Path.Combine(plugins, ".xn-reshade"), state.Marker);
    }

    private static void RestoreReShadeFiles(string plugins, string rollback, IEnumerable<string> newFiles, string? oldManifest, string? oldMarker)
    {
        Directory.CreateDirectory(plugins);
        foreach (var relative in newFiles)
        {
            var target = SafeChildPath(plugins, relative);
            if (File.Exists(target)) File.Delete(target);
        }
        if (Directory.Exists(rollback))
        {
            foreach (var relative in RelativeFiles(rollback))
            {
                var from = SafeChildPath(rollback, relative);
                var to = SafeChildPath(plugins, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(to)!);
                File.Copy(from, to, true);
            }
        }
        RestoreTextFile(Path.Combine(plugins, ".xn-reshade-managed.json"), oldManifest);
        RestoreTextFile(Path.Combine(plugins, ".xn-reshade"), oldMarker);
    }

    private static void RestoreTextFile(string path, string? content)
    {
        if (content is null) { if (File.Exists(path)) File.Delete(path); }
        else File.WriteAllText(path, content);
    }

    private static async Task CopyTreeVerifiedAsync(string source, string destination, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories).Where(x => !Path.GetFileName(x).Equals(".xn-hash-cache.json", StringComparison.OrdinalIgnoreCase)))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var relative = Path.GetRelativePath(source, file);
            var target = SafeChildPath(destination, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            await using var input = File.OpenRead(file);
            await using var output = File.Create(target);
            await input.CopyToAsync(output, cancellationToken);
        }
        var sourceHashes = await HashTreeAsync(source, useCache: true, cancellationToken);
        var destinationHashes = await HashTreeAsync(destination, useCache: false, cancellationToken);
        if (sourceHashes.Count != destinationHashes.Count || sourceHashes.Any(x => !destinationHashes.TryGetValue(x.Key, out var hash) || hash != x.Value))
            throw new IOException("Pack verification failed after copying to the temporary folder.");
    }

    private static async Task<Dictionary<string, string>> HashTreeAsync(string root, bool useCache, CancellationToken cancellationToken)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var cachePath = Path.Combine(root, ".xn-hash-cache.json");
        var cache = useCache && File.Exists(cachePath)
            ? TryReadHashCache(cachePath) : new Dictionary<string, HashCacheEntry>(StringComparer.OrdinalIgnoreCase);
        var updated = new Dictionary<string, HashCacheEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).Where(x => !x.Equals(cachePath, StringComparison.OrdinalIgnoreCase)).Order())
        {
            cancellationToken.ThrowIfCancellationRequested();
            var relative = Path.GetRelativePath(root, file);
            var info = new FileInfo(file);
            string hash;
            if (useCache && cache.TryGetValue(relative, out var existing) && existing.Length == info.Length && existing.LastWriteUtcTicks == info.LastWriteTimeUtc.Ticks)
                hash = existing.Sha256;
            else
            {
                await using var stream = File.OpenRead(file);
                hash = Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken));
            }
            result[relative] = hash;
            if (useCache) updated[relative] = new HashCacheEntry { Length = info.Length, LastWriteUtcTicks = info.LastWriteTimeUtc.Ticks, Sha256 = hash };
        }
        if (useCache) WriteJournal(cachePath, updated);
        return result;
    }

    private static Dictionary<string, HashCacheEntry> TryReadHashCache(string path)
    {
        try { return JsonSerializer.Deserialize<Dictionary<string, HashCacheEntry>>(File.ReadAllText(path)) ?? new(StringComparer.OrdinalIgnoreCase); }
        catch { return new(StringComparer.OrdinalIgnoreCase); }
    }

    private static IEnumerable<string> RelativeFiles(string root) =>
        Directory.Exists(root) ? Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).Select(x => Path.GetRelativePath(root, x)) : [];

    private static string SafeLibraryPath(string root, string name)
    {
        if (!Regex.IsMatch(name, @"^[\w .-]{1,30}$") || name.StartsWith('.') || name.StartsWith('_')) throw new InvalidDataException("Unsafe library name.");
        return SafeChildPath(root, name);
    }

    private static string SafeChildPath(string root, string relative)
    {
        if (Path.IsPathRooted(relative)) throw new InvalidDataException("Unsafe rooted path.");
        var rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var target = Path.GetFullPath(Path.Combine(root, relative));
        if (!target.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("A file escaped its expected folder.");
        return target;
    }

    private static void SafeDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, true); } catch { }
    }

    private static void WriteJournal<T>(string path, T value)
    {
        var temporary = path + $".new-{Guid.NewGuid():N}";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(value));
            _ = JsonDocument.Parse(File.ReadAllText(temporary));
            File.Move(temporary, path, true);
        }
        finally { try { File.Delete(temporary); } catch { } }
    }

    private static T ReadJournal<T>(string path) where T : new() =>
        JsonSerializer.Deserialize<T>(File.ReadAllText(path)) ?? throw new InvalidDataException("A recovery journal is damaged.");

    private sealed class SoundSwitchJournal
    {
        public string StageFolder { get; set; } = "";
        public string RollbackFolder { get; set; } = "";
        public bool HadPreviousMods { get; set; }
    }

    private sealed class ReShadeSwitchJournal
    {
        public string StageFolder { get; set; } = "";
        public string RollbackFolder { get; set; } = "";
        public List<string> NewFiles { get; set; } = [];
        public string? OldManifest { get; set; }
        public string? OldMarker { get; set; }
    }

    private sealed class ReShadeSnapshot
    {
        public List<string> Files { get; set; } = [];
        public string? Manifest { get; set; }
        public string? Marker { get; set; }
    }

    private sealed class HashCacheEntry
    {
        public long Length { get; set; }
        public long LastWriteUtcTicks { get; set; }
        public string Sha256 { get; set; } = "";
    }
}

public sealed class FiveMService
{
    private readonly PackService _packs;
    private readonly string _appDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FiveM", "FiveM.app");

    public FiveMService(PackService packs) => _packs = packs;

    public bool IsRunning => Process.GetProcesses().Any(x => x.ProcessName.StartsWith("FiveM", StringComparison.OrdinalIgnoreCase));
    public bool IsInstalled => ResolveExecutable() is not null;

    public void EnsureCanary(bool requireInstalled = true)
    {
        if (!Directory.Exists(_appDirectory))
        {
            if (requireInstalled) throw new DirectoryNotFoundException("FiveM is not installed for this Windows account.");
            return;
        }
        var path = Path.Combine(_appDirectory, "CitizenFX.ini");
        var original = File.Exists(path) ? File.ReadAllText(path) : "";
        if (Regex.IsMatch(original, @"(?im)^\s*UpdateChannel\s*=\s*canary\s*$")) return;
        string updated;
        if (Regex.IsMatch(original, @"(?im)^\s*UpdateChannel\s*=.*$"))
            updated = Regex.Replace(original, @"(?im)^\s*UpdateChannel\s*=.*$", "UpdateChannel=canary");
        else if (Regex.IsMatch(original, @"(?im)^\s*\[Game\]\s*$"))
            updated = new Regex(@"^\s*\[Game\]\s*$", RegexOptions.IgnoreCase | RegexOptions.Multiline).Replace(original, "$0\r\nUpdateChannel=canary", 1);
        else updated = "[Game]\r\nUpdateChannel=canary\r\n\r\n" + original;
        if (File.Exists(path) && !File.Exists(path + ".xn-before-canary")) File.Copy(path, path + ".xn-before-canary");
        var temporary = path + $".xn-new-{Guid.NewGuid():N}";
        File.WriteAllText(temporary, updated);
        if (!Regex.IsMatch(File.ReadAllText(temporary), @"(?im)^\s*UpdateChannel\s*=\s*canary\s*$")) throw new IOException("FiveM channel verification failed.");
        File.Move(temporary, path, true);
    }

    public async Task LaunchAsync(ServerProfile profile, IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        foreach (var command in profile.Commands) CommandCatalog.Validate(command);
        EnsureCanary();
        if (IsRunning && profile.Commands.Count > 0) throw new InvalidOperationException("Close FiveM before launching a profile with server commands.");
        if (!IsRunning) await _packs.ApplyAsync(profile, progress, cancellationToken);

        var target = NormalizeConnectTarget(profile.Connect);
        if (Regex.IsMatch(target, "^[A-Za-z0-9]{4,12}$")) target = "cfx.re/join/" + target;
        var executable = ResolveExecutable();
        if (executable is not null)
        {
            var start = new ProcessStartInfo(executable) { UseShellExecute = true };
            foreach (var command in profile.Commands)
            {
                start.ArgumentList.Add("+set");
                start.ArgumentList.Add(command.Name);
                start.ArgumentList.Add(command.Value);
            }
            start.ArgumentList.Add("+connect");
            start.ArgumentList.Add(target);
            Process.Start(start);
        }
        else
        {
            Process.Start(new ProcessStartInfo("fivem://connect/" + target) { UseShellExecute = true });
        }
    }

    public string Readiness(ServerProfile profile)
    {
        if (!IsInstalled) return "FiveM missing";
        if (IsRunning && profile.Commands.Count > 0) return "Close FiveM for commands";
        if (profile.Soundpack != "None" && !Directory.Exists(Path.Combine(AppPaths.SoundpacksDirectory, profile.Soundpack))) return "Soundpack missing";
        if (profile.Reshade != "Keep current" && !Directory.Exists(Path.Combine(AppPaths.ReShadeDirectory, profile.Reshade))) return "ReShade look missing";
        return "Ready";
    }

    public string? ResolveExecutable()
    {
        foreach (var path in new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FiveM", "FiveM.exe"),
            Path.Combine(_appDirectory, "FiveM.exe")
        }) if (File.Exists(path)) return path;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Classes\fivem\shell\open\command");
            var command = Environment.ExpandEnvironmentVariables(key?.GetValue(null)?.ToString() ?? "");
            var match = Regex.Match(command, "^\\s*\\\"([^\\\"]+FiveM\\.exe)\\\"|^\\s*([^\\s]+FiveM\\.exe)", RegexOptions.IgnoreCase);
            if (match.Success)
            {
                var path = match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value;
                if (File.Exists(path)) return path;
            }
        }
        catch { }
        return null;
    }

    public static string NormalizeConnectTarget(string connect)
    {
        var value = (connect ?? "").Trim().Trim('"', '\'').Replace("fivem://connect/", "", StringComparison.OrdinalIgnoreCase).TrimEnd('/');
        var match = Regex.Match(value, @"^(?:https?://)?(?:www\.)?cfx\.re/join/([A-Za-z0-9]{4,12})$", RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value : value;
    }
}

public sealed class LibraryService
{
    private static readonly HashSet<string> RiskyExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".exe", ".msi", ".dll", ".bat", ".cmd", ".ps1", ".vbs", ".js", ".jse", ".wsf", ".scr", ".com"
    };

    public List<LibraryEntry> GetEntries(LibraryKind kind, IEnumerable<ServerProfile> profiles)
    {
        var root = Root(kind);
        Directory.CreateDirectory(root);
        return Directory.EnumerateDirectories(root)
            .Where(x => !Path.GetFileName(x).StartsWith(".xn-", StringComparison.OrdinalIgnoreCase))
            .Select(path =>
            {
                var name = Path.GetFileName(path);
                var used = profiles.Where(x => (kind == LibraryKind.Soundpack ? x.Soundpack : x.Reshade).Equals(name, StringComparison.OrdinalIgnoreCase)).Select(x => x.Name).ToList();
                return new LibraryEntry
                {
                    Name = name,
                    Kind = kind,
                    FileCount = EnumerateSafeFiles(path).Count(),
                    Usage = used.Count == 0 ? "Not used by a profile" : "Used by " + string.Join(", ", used)
                };
            })
            .OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public async Task<ImportPreview> PreviewAsync(string source, CancellationToken cancellationToken = default)
    {
        if (Directory.Exists(source))
        {
            var files = EnumerateSafeFiles(source).ToList();
            return BuildPreview(files.Select(x => (Path.GetRelativePath(source, x), new FileInfo(x).Length)));
        }
        if (!File.Exists(source) || !Path.GetExtension(source).Equals(".zip", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Choose a folder or a .zip pack.");
        using var archive = ZipFile.OpenRead(source);
        ValidateArchive(archive);
        await Task.CompletedTask;
        return BuildPreview(archive.Entries.Where(x => !string.IsNullOrEmpty(x.Name)).Select(x => (x.FullName, x.Length)));
    }

    public async Task<string> ImportAsync(string source, LibraryKind kind, string? requestedName = null, CancellationToken cancellationToken = default)
    {
        requestedName ??= Directory.Exists(source) ? new DirectoryInfo(source).Name : Path.GetFileNameWithoutExtension(source);
        var name = UniqueName(Root(kind), CleanLibraryName(requestedName));
        var stage = Path.Combine(Root(kind), $".xn-import-stage-{Guid.NewGuid():N}");
        var unpack = Path.Combine(Path.GetTempPath(), $"XnFreshDeploy-import-{Guid.NewGuid():N}");
        try
        {
            if (Directory.Exists(source)) await CopyDirectoryAsync(source, stage, cancellationToken);
            else
            {
                Directory.CreateDirectory(unpack);
                using var archive = ZipFile.OpenRead(source);
                ValidateArchive(archive);
                foreach (var entry in archive.Entries.Where(x => !string.IsNullOrEmpty(x.Name)))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var target = SafeChildPath(unpack, entry.FullName.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    await using var input = entry.Open();
                    await using var output = File.Create(target);
                    await input.CopyToAsync(output, cancellationToken);
                }
                var directories = Directory.EnumerateDirectories(unpack).ToList();
                var files = Directory.EnumerateFiles(unpack).ToList();
                var contentRoot = directories.Count == 1 && files.Count == 0 ? directories[0] : unpack;
                await CopyDirectoryAsync(contentRoot, stage, cancellationToken);
            }
            if (!EnumerateSafeFiles(stage).Any()) throw new InvalidDataException("The selected pack contains no files.");
            Directory.Move(stage, Path.Combine(Root(kind), name));
            return name;
        }
        finally
        {
            SafeDelete(stage);
            SafeDelete(unpack);
        }
    }

    public string Rename(LibraryKind kind, string currentName, string requestedName, IEnumerable<ServerProfile> profiles)
    {
        var root = Root(kind);
        var current = SafeLibraryPath(root, currentName);
        if (!Directory.Exists(current)) throw new DirectoryNotFoundException("That library item no longer exists.");
        var clean = CleanLibraryName(requestedName);
        var destination = SafeLibraryPath(root, clean);
        if (Directory.Exists(destination)) throw new InvalidOperationException("A library item already uses that name.");
        Directory.Move(current, destination);
        foreach (var profile in profiles)
        {
            if (kind == LibraryKind.Soundpack && profile.Soundpack.Equals(currentName, StringComparison.OrdinalIgnoreCase)) profile.Soundpack = clean;
            if (kind == LibraryKind.ReShade && profile.Reshade.Equals(currentName, StringComparison.OrdinalIgnoreCase)) profile.Reshade = clean;
        }
        return clean;
    }

    public void Delete(LibraryKind kind, string name)
    {
        var path = SafeLibraryPath(Root(kind), name);
        if (Directory.Exists(path)) Directory.Delete(path, true);
    }

    internal static string CleanLibraryName(string value)
    {
        var clean = Regex.Replace(value.Trim(), @"[^\w .-]", " ");
        clean = Regex.Replace(clean, @"\s+", " ").Trim(' ', '.');
        if (clean.Length > 30) clean = clean[..30].Trim();
        if (!Regex.IsMatch(clean, @"^[\w][\w .-]{0,29}$") || clean.StartsWith('_')) throw new InvalidDataException("Use a short library name containing letters, numbers, spaces, dots, or dashes.");
        return clean;
    }

    internal static IEnumerable<string> EnumerateSafeFiles(string root) =>
        Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Where(x => !new FileInfo(x).Attributes.HasFlag(FileAttributes.ReparsePoint) && !Path.GetFileName(x).Equals(".xn-hash-cache.json", StringComparison.OrdinalIgnoreCase));

    internal static void ValidateArchive(ZipArchive archive)
    {
        if (archive.Entries.Count > 50_000) throw new InvalidDataException("The archive contains too many files.");
        if (archive.Entries.Sum(x => x.Length) > 20L * 1024 * 1024 * 1024) throw new InvalidDataException("The archive expands beyond the 20 GB safety limit.");
        foreach (var entry in archive.Entries)
        {
            var value = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            if (Path.IsPathRooted(value) || value.Split(Path.DirectorySeparatorChar).Any(x => x == ".."))
                throw new InvalidDataException("The archive contains an unsafe path.");
        }
    }

    internal static string SafeChildPath(string root, string relative)
    {
        var rootFull = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var target = Path.GetFullPath(Path.Combine(root, relative));
        if (!target.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("A file escaped its expected folder.");
        return target;
    }

    private static ImportPreview BuildPreview(IEnumerable<(string Name, long Length)> files)
    {
        var list = files.ToList();
        var types = list.Select(x => Path.GetExtension(x.Name).ToLowerInvariant()).Where(x => x.Length > 0).GroupBy(x => x).OrderByDescending(x => x.Count()).Take(18).Select(x => $"{x.Key} ({x.Count()})").ToList();
        var risky = list.Where(x => RiskyExtensions.Contains(Path.GetExtension(x.Name))).Select(x => x.Name).Take(100).ToList();
        return new ImportPreview { FileCount = list.Count, TotalBytes = list.Sum(x => x.Length), FileTypes = types, RiskyFiles = risky };
    }

    private static string Root(LibraryKind kind) => kind == LibraryKind.Soundpack ? AppPaths.SoundpacksDirectory : AppPaths.ReShadeDirectory;

    private static string SafeLibraryPath(string root, string name) => SafeChildPath(root, CleanLibraryName(name));

    private static string UniqueName(string root, string stem)
    {
        var name = stem;
        var number = 2;
        while (Directory.Exists(Path.Combine(root, name))) name = $"{stem} {number++}";
        return name;
    }

    private static async Task CopyDirectoryAsync(string source, string destination, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in EnumerateSafeFiles(source))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var target = SafeChildPath(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            await using var input = File.OpenRead(file);
            await using var output = File.Create(target);
            await input.CopyToAsync(output, cancellationToken);
            if (new FileInfo(file).Length != new FileInfo(target).Length) throw new IOException("A library file did not copy completely.");
        }
    }

    private static void SafeDelete(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, true); } catch { }
    }
}

public sealed class PortableBackupService
{
    private readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true, WriteIndented = true };

    public async Task ExportAsync(string path, IEnumerable<ServerProfile> profiles, AppConfig config, CancellationToken cancellationToken = default)
    {
        var temporary = path + $".new-{Guid.NewGuid():N}";
        var profileList = profiles.ToList();
        var manifest = new PortableManifest { Profiles = profileList };
        try
        {
            await using (var file = File.Create(temporary))
            using (var archive = new ZipArchive(file, ZipArchiveMode.Create, leaveOpen: false))
            {
                foreach (var profile in profileList)
                {
                    if (!profile.Soundpack.Equals("None", StringComparison.OrdinalIgnoreCase))
                        await AddPackAsync(archive, LibraryKind.Soundpack, profile.Soundpack, manifest, cancellationToken);
                    if (!profile.Reshade.Equals("Keep current", StringComparison.OrdinalIgnoreCase))
                        await AddPackAsync(archive, LibraryKind.ReShade, profile.Reshade, manifest, cancellationToken);
                }
                var configEntry = archive.CreateEntry("config.json", CompressionLevel.Optimal);
                await using (var output = configEntry.Open()) await JsonSerializer.SerializeAsync(output, config, _json, cancellationToken);
                var manifestEntry = archive.CreateEntry("manifest.json", CompressionLevel.Optimal);
                await using (var output = manifestEntry.Open()) await JsonSerializer.SerializeAsync(output, manifest, _json, cancellationToken);
            }
            File.Move(temporary, path, true);
        }
        finally { try { File.Delete(temporary); } catch { } }
    }

    public async Task<(ImportPreview Preview, int Profiles, int Soundpacks, int ReShade)> PreviewAsync(string path, CancellationToken cancellationToken = default)
    {
        using var archive = ZipFile.OpenRead(path);
        LibraryService.ValidateArchive(archive);
        var manifest = await ReadManifestAsync(archive, cancellationToken);
        var preview = await new LibraryService().PreviewAsync(path, cancellationToken);
        return (preview, manifest.Profiles.Count, manifest.Soundpacks.Count, manifest.ReShade.Count);
    }

    public async Task<PortableImportResult> ImportAsync(string path, CancellationToken cancellationToken = default)
    {
        var temporary = Path.Combine(Path.GetTempPath(), $"XnFreshDeploy-portable-{Guid.NewGuid():N}");
        try
        {
            using var archive = ZipFile.OpenRead(path);
            LibraryService.ValidateArchive(archive);
            var manifest = await ReadManifestAsync(archive, cancellationToken);
            Directory.CreateDirectory(temporary);
            foreach (var entry in archive.Entries.Where(x => !string.IsNullOrEmpty(x.Name) && x.FullName.StartsWith("Library/", StringComparison.OrdinalIgnoreCase)))
            {
                cancellationToken.ThrowIfCancellationRequested();
                var relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                var target = LibraryService.SafeChildPath(temporary, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                await using (var input = entry.Open())
                await using (var output = File.Create(target))
                    await input.CopyToAsync(output, cancellationToken);
                await using var verify = File.OpenRead(target);
                var hash = Convert.ToHexString(await SHA256.HashDataAsync(verify, cancellationToken));
                if (!manifest.Hashes.TryGetValue(entry.FullName, out var expected) || !hash.Equals(expected, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Portable backup verification failed for " + entry.FullName);
            }

            var installed = new List<string>();
            try
            {
                var soundMap = ImportPackFolders(Path.Combine(temporary, "Library", "Soundpacks"), AppPaths.SoundpacksDirectory, manifest.Soundpacks, installed);
                var reshadeMap = ImportPackFolders(Path.Combine(temporary, "Library", "ReShade"), AppPaths.ReShadeDirectory, manifest.ReShade, installed);
                foreach (var profile in manifest.Profiles)
                {
                    if (soundMap.TryGetValue(profile.Soundpack, out var sound)) profile.Soundpack = sound;
                    if (reshadeMap.TryGetValue(profile.Reshade, out var look)) profile.Reshade = look;
                }
                return new PortableImportResult { Profiles = manifest.Profiles, SoundpackCount = soundMap.Count, ReShadeCount = reshadeMap.Count };
            }
            catch
            {
                foreach (var directory in installed) try { if (Directory.Exists(directory)) Directory.Delete(directory, true); } catch { }
                throw;
            }
        }
        finally { try { if (Directory.Exists(temporary)) Directory.Delete(temporary, true); } catch { } }
    }

    private async Task AddPackAsync(ZipArchive archive, LibraryKind kind, string name, PortableManifest manifest, CancellationToken cancellationToken)
    {
        name = LibraryService.CleanLibraryName(name);
        var names = kind == LibraryKind.Soundpack ? manifest.Soundpacks : manifest.ReShade;
        if (!names.Add(name)) return;
        var root = kind == LibraryKind.Soundpack ? AppPaths.SoundpacksDirectory : AppPaths.ReShadeDirectory;
        var source = LibraryService.SafeChildPath(root, name);
        if (!Directory.Exists(source)) throw new DirectoryNotFoundException($"Referenced library item '{name}' is missing.");
        var category = kind == LibraryKind.Soundpack ? "Soundpacks" : "ReShade";
        foreach (var file in LibraryService.EnumerateSafeFiles(source))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var entryName = $"Library/{category}/{name}/{Path.GetRelativePath(source, file).Replace('\\', '/')}";
            var entry = archive.CreateEntry(entryName, CompressionLevel.Optimal);
            await using var input = File.OpenRead(file);
            manifest.Hashes[entryName] = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken));
            input.Position = 0;
            await using var output = entry.Open();
            await input.CopyToAsync(output, cancellationToken);
        }
    }

    private async Task<PortableManifest> ReadManifestAsync(ZipArchive archive, CancellationToken cancellationToken)
    {
        var entry = archive.GetEntry("manifest.json") ?? throw new InvalidDataException("This is not an Xn Fresh Deploy portable backup.");
        if (entry.Length > 10 * 1024 * 1024) throw new InvalidDataException("The portable manifest is unexpectedly large.");
        await using var input = entry.Open();
        var manifest = await JsonSerializer.DeserializeAsync<PortableManifest>(input, _json, cancellationToken) ?? throw new InvalidDataException("The portable manifest is empty.");
        if (manifest.Format != "XnFreshDeployPortable" || manifest.Version != 1) throw new InvalidDataException("This portable backup version is not supported.");
        return manifest;
    }

    private static Dictionary<string, string> ImportPackFolders(string sourceRoot, string destinationRoot, IEnumerable<string> names, List<string> installed)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        Directory.CreateDirectory(destinationRoot);
        foreach (var original in names)
        {
            var source = LibraryService.SafeChildPath(sourceRoot, original);
            if (!Directory.Exists(source)) throw new InvalidDataException($"The portable backup is missing '{original}'.");
            var name = original;
            var number = 2;
            while (Directory.Exists(Path.Combine(destinationRoot, name))) name = $"{original} Imported {number++}";
            var destination = Path.Combine(destinationRoot, name);
            var stage = Path.Combine(destinationRoot, $".xn-portable-stage-{Guid.NewGuid():N}");
            try
            {
                Directory.CreateDirectory(stage);
                foreach (var file in LibraryService.EnumerateSafeFiles(source))
                {
                    var target = LibraryService.SafeChildPath(stage, Path.GetRelativePath(source, file));
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    File.Copy(file, target, true);
                    if (new FileInfo(file).Length != new FileInfo(target).Length) throw new IOException("A portable library file did not copy completely.");
                }
                Directory.Move(stage, destination);
                installed.Add(destination);
            }
            finally { try { if (Directory.Exists(stage)) Directory.Delete(stage, true); } catch { } }
            map[original] = name;
        }
        return map;
    }

    private sealed class PortableManifest
    {
        public string Format { get; set; } = "XnFreshDeployPortable";
        public int Version { get; set; } = 1;
        public DateTimeOffset ExportedAt { get; set; } = DateTimeOffset.UtcNow;
        public List<ServerProfile> Profiles { get; set; } = [];
        public HashSet<string> Soundpacks { get; set; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> ReShade { get; set; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, string> Hashes { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }
}

public static class HardwareService
{
    public static HardwareInfo Detect()
    {
        var info = new HardwareInfo();
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_Processor");
            info.Cpu = searcher.Get().Cast<ManagementObject>().FirstOrDefault()?["Name"]?.ToString()?.Trim() ?? info.Cpu;
        }
        catch { }
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name, VideoProcessor, AdapterRAM, PNPDeviceID, CurrentHorizontalResolution FROM Win32_VideoController");
            var adapters = searcher.Get().Cast<ManagementObject>()
                .Select(adapter => new
                {
                    Name = adapter["Name"]?.ToString()?.Trim() ?? "",
                    PnpId = adapter["PNPDeviceID"]?.ToString() ?? "",
                    Memory = TryReadUInt64(adapter["AdapterRAM"]),
                    IsDrivingDisplay = adapter["CurrentHorizontalResolution"] is not null
                })
                .Where(adapter => adapter.Name.Length > 0 && !adapter.Name.Contains("Basic Display", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(adapter => ScoreGraphicsAdapter(adapter.Name, adapter.PnpId, adapter.Memory, adapter.IsDrivingDisplay))
                .ToList();
            info.Gpu = adapters.FirstOrDefault()?.Name ?? info.Gpu;
        }
        catch { }
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Caption FROM Win32_OperatingSystem");
            info.Windows = searcher.Get().Cast<ManagementObject>().FirstOrDefault()?["Caption"]?.ToString()?.Trim() ?? info.Windows;
        }
        catch { }
        return info;
    }

    private static int ScoreGraphicsAdapter(string name, string pnpId, ulong memory, bool isDrivingDisplay)
    {
        var score = 0;
        if (pnpId.Contains("VEN_10DE", StringComparison.OrdinalIgnoreCase) || name.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) || name.Contains("GeForce", StringComparison.OrdinalIgnoreCase)) score += 10_000;
        if (name.Contains("Radeon RX", StringComparison.OrdinalIgnoreCase) || name.Contains("Intel Arc", StringComparison.OrdinalIgnoreCase)) score += 8_000;
        if (isDrivingDisplay) score += 2_000;
        if (memory >= 2UL * 1024 * 1024 * 1024) score += 1_000;
        if (name.Contains("Radeon(TM) Graphics", StringComparison.OrdinalIgnoreCase) || name.Contains("UHD Graphics", StringComparison.OrdinalIgnoreCase) || name.Contains("Iris", StringComparison.OrdinalIgnoreCase)) score -= 3_000;
        return score;
    }

    private static ulong TryReadUInt64(object? value)
    {
        try { return value is null ? 0 : Convert.ToUInt64(value); }
        catch { return 0; }
    }
}

public sealed class BackupService
{
    public void CreateBackup()
    {
        Directory.CreateDirectory(AppPaths.BackupDirectory);
        foreach (var item in BrowserBookmarkPaths())
            if (File.Exists(item.Source)) { Directory.CreateDirectory(Path.GetDirectoryName(item.Destination)!); File.Copy(item.Source, item.Destination, true); }
        var citizen = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CitizenFX");
        if (Directory.Exists(citizen)) CopyDirectory(citizen, Path.Combine(AppPaths.BackupDirectory, "CitizenFX"));
    }

    public bool HasBackup => Directory.Exists(AppPaths.BackupDirectory) && Directory.EnumerateFileSystemEntries(AppPaths.BackupDirectory).Any();

    public void RestoreBackup()
    {
        if (!HasBackup) throw new DirectoryNotFoundException("No backup is available beside the app.");
        var citizen = Path.Combine(AppPaths.BackupDirectory, "CitizenFX");
        if (Directory.Exists(citizen)) CopyDirectory(citizen, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CitizenFX"));
        foreach (var item in BrowserBookmarkPaths())
            if (File.Exists(item.Destination)) { Directory.CreateDirectory(Path.GetDirectoryName(item.Source)!); File.Copy(item.Destination, item.Source, true); }
    }

    private static IEnumerable<(string Source, string Destination)> BrowserBookmarkPaths()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        foreach (var browser in new[] { ("Brave", @"BraveSoftware\Brave-Browser\User Data\Default\Bookmarks"), ("Chrome", @"Google\Chrome\User Data\Default\Bookmarks"), ("Edge", @"Microsoft\Edge\User Data\Default\Bookmarks") })
            yield return (Path.Combine(local, browser.Item2), Path.Combine(AppPaths.BackupDirectory, browser.Item1, "Bookmarks"));
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var directory in Directory.EnumerateDirectories(source, "*", SearchOption.AllDirectories)) Directory.CreateDirectory(Path.Combine(destination, Path.GetRelativePath(source, directory)));
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            var target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, true);
        }
    }
}

public sealed class SetupService
{
    private readonly AppConfig _config;
    private readonly BackupService _backup;
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromMinutes(5) };

    public SetupService(AppConfig config, BackupService backup) { _config = config; _backup = backup; }

    public static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    public List<SetupProgressItem> BuildTasks(SetupSelection selection)
    {
        var tasks = new List<SetupProgressItem>();
        if (selection.Apps.Count > 0) tasks.Add(NewProgressTask("apps", "Install selected apps"));
        if (selection.Drivers) tasks.Add(NewProgressTask("drivers", "Run local driver packages"));
        if (selection.Mouse) tasks.Add(NewProgressTask("mouse", "Disable Windows mouse acceleration"));
        if (selection.FiveM) tasks.Add(NewProgressTask("fivem", "Download FiveM"));
        if (selection.ReShade) tasks.Add(NewProgressTask("reshade", "Prepare ReShade installer"));
        if (selection.Restore) tasks.Add(NewProgressTask("restore", "Restore portable backup"));
        if (selection.Launch) tasks.Add(NewProgressTask("launch", "Open installed apps"));
        return tasks;
    }

    public async Task RunAsync(SetupSelection selection, Action<string, string, string> stage, Action<string> log, CancellationToken cancellationToken)
    {
        if (selection.Apps.Count > 0) await RunTask("apps", "Installing selected apps...", async () =>
        {
            var failures = 0;
            foreach (var name in selection.Apps)
            {
                var app = _config.Apps.First(x => x.Name == name);
                log($"Installing {app.Name} through winget...");
                var exit = await RunProcessAsync("winget.exe", ["install", "--id", app.WingetId, "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements"], log, cancellationToken);
                if (exit != 0) failures++;
            }
            if (failures > 0) throw new InvalidOperationException($"{failures} app installation(s) need attention.");
        }, stage, log);

        if (selection.Drivers) await RunTask("drivers", "Running local driver packages...", async () =>
        {
            var files = Directory.EnumerateFiles(AppPaths.DriversDirectory).Where(x => Path.GetExtension(x).Equals(".exe", StringComparison.OrdinalIgnoreCase) || Path.GetExtension(x).Equals(".msi", StringComparison.OrdinalIgnoreCase)).ToList();
            if (files.Count == 0) throw new InvalidOperationException("No .exe or .msi driver packages were found.");
            foreach (var file in files)
            {
                log("Starting " + Path.GetFileName(file));
                var start = Path.GetExtension(file).Equals(".msi", StringComparison.OrdinalIgnoreCase)
                    ? new ProcessStartInfo("msiexec.exe") { UseShellExecute = true }
                    : new ProcessStartInfo(file) { UseShellExecute = true };
                if (start.FileName == "msiexec.exe") { start.ArgumentList.Add("/i"); start.ArgumentList.Add(file); }
                using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start " + file);
                await process.WaitForExitAsync(cancellationToken);
            }
        }, stage, log);

        if (selection.Mouse) await RunTask("mouse", "Applying consistent mouse input...", () =>
        {
            using var key = Registry.CurrentUser.CreateSubKey(@"Control Panel\Mouse");
            key.SetValue("MouseSpeed", "0"); key.SetValue("MouseThreshold1", "0"); key.SetValue("MouseThreshold2", "0");
            return Task.CompletedTask;
        }, stage, log);

        if (selection.FiveM) await RunTask("fivem", "Downloading and verifying FiveM...", async () =>
        {
            var uri = new Uri(_config.FiveM.DownloadUrl);
            if (uri.Scheme != "https" || !uri.Host.Equals("runtime.fivem.net", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("The FiveM URL is not trusted.");
            var target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "FiveM.exe");
            await DownloadAsync(uri, target, cancellationToken);
            NativeTrust.AssertTrustedSignedFile(target, ["Rockstar Games", "CitizenFX", "Cfx"]);
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }, stage, log);

        if (selection.ReShade) await RunTask("reshade", "Downloading and verifying ReShade...", async () =>
        {
            var page = await _http.GetStringAsync("https://reshade.me/", cancellationToken);
            var match = Regex.Match(page, @"ReShade_Setup_([0-9.]+)\.exe", RegexOptions.IgnoreCase);
            var thumbprintMatch = Regex.Match(page, @"X\.509 Digital Signature Thumbprint:.{0,250}?([A-Fa-f0-9]{40})", RegexOptions.IgnoreCase | RegexOptions.Singleline);
            if (!match.Success || !thumbprintMatch.Success) throw new InvalidOperationException("The current ReShade installer or its published signature could not be identified safely.");
            var fileName = match.Value;
            var uri = new Uri("https://reshade.me/downloads/" + fileName);
            var target = Path.Combine(Path.GetTempPath(), fileName);
            await DownloadAsync(uri, target, cancellationToken);
            NativeTrust.AssertTrustedSignedFile(target, thumbprintMatch.Groups[1].Value);
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
            log("Choose FiveM in the verified ReShade installer. FiveM must have been opened once first.");
        }, stage, log);

        if (selection.Restore) await RunTask("restore", "Restoring backup...", () => { _backup.RestoreBackup(); return Task.CompletedTask; }, stage, log);

        if (selection.Launch) await RunTask("launch", "Opening selected apps...", () =>
        {
            foreach (var app in _config.Apps.Where(x => selection.Apps.Contains(x.Name) && x.LaunchAfter))
            {
                var path = app.LaunchPaths.Select(Environment.ExpandEnvironmentVariables).FirstOrDefault(File.Exists);
                if (path is not null) Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            }
            return Task.CompletedTask;
        }, stage, log);
    }

    private async Task DownloadAsync(Uri uri, string target, CancellationToken cancellationToken)
    {
        await using var input = await _http.GetStreamAsync(uri, cancellationToken);
        await using var output = File.Create(target);
        await input.CopyToAsync(output, cancellationToken);
        if (new FileInfo(target).Length < 1024) throw new InvalidDataException("The downloaded installer is unexpectedly small.");
    }

    private static async Task RunTask(string id, string detail, Func<Task> action, Action<string, string, string> stage, Action<string> log)
    {
        stage(id, "Running", detail);
        try { await action(); stage(id, "Complete", "Completed successfully."); }
        catch (Exception ex) { log(ex.Message); stage(id, "Warning", ex.Message); }
    }

    private static SetupProgressItem NewProgressTask(string id, string label) => new() { Id = id, Label = label };

    private static async Task<int> RunProcessAsync(string fileName, IEnumerable<string> arguments, Action<string> log, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(fileName) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start " + fileName);
        var stdout = Task.Run(async () => { while (await process.StandardOutput.ReadLineAsync(cancellationToken) is { } line) log(line); }, cancellationToken);
        var stderr = Task.Run(async () => { while (await process.StandardError.ReadLineAsync(cancellationToken) is { } line) log(line); }, cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        await Task.WhenAll(stdout, stderr);
        return process.ExitCode;
    }
}

public static class SetupWorkerCoordinator
{
    public static async Task<int> RunWorkerAsync(string selectionPath, string eventsPath, CancellationToken cancellationToken = default)
    {
        selectionPath = ValidateTempArtifact(selectionPath, "XnFreshDeploy-setup-", ".json");
        eventsPath = ValidateTempArtifact(eventsPath, "XnFreshDeploy-events-", ".jsonl");
        using var writer = new SetupEventWriter(eventsPath);
        try
        {
            if (!SetupService.IsAdministrator()) throw new InvalidOperationException("The PC Setup worker did not receive administrator permission.");
            AppPaths.EnsurePortableLayout();
            var selection = JsonSerializer.Deserialize<SetupSelection>(await File.ReadAllTextAsync(selectionPath, cancellationToken)) ?? throw new InvalidDataException("The PC Setup selection is empty.");
            var backup = new BackupService();
            var setup = new SetupService(new DataService().LoadConfig(), backup);
            var hasWarnings = false;
            writer.Send(new SetupWorkerEvent { Type = "log", Message = "Administrator permission granted. Setup is continuing in the original app window." });
            await setup.RunAsync(selection,
                (id, state, detail) =>
                {
                    if (state == "Warning") hasWarnings = true;
                    writer.Send(new SetupWorkerEvent { Type = "stage", Id = id, State = state, Message = detail });
                },
                message => writer.Send(new SetupWorkerEvent { Type = "log", Message = message }),
                cancellationToken);
            writer.Send(new SetupWorkerEvent { Type = "done", State = hasWarnings ? "Review" : "Complete" });
            return 0;
        }
        catch (Exception ex)
        {
            writer.Send(new SetupWorkerEvent { Type = "fatal", State = "Stopped", Message = ex.Message });
            return 1;
        }
        finally { try { File.Delete(selectionPath); } catch { } }
    }

    private static string ValidateTempArtifact(string path, string prefix, string extension)
    {
        var fullPath = Path.GetFullPath(path);
        var tempRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var name = Path.GetFileName(fullPath);
        if (!fullPath.StartsWith(tempRoot, StringComparison.OrdinalIgnoreCase) || !name.StartsWith(prefix, StringComparison.Ordinal) || !name.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The PC Setup handoff path is unsafe.");
        return fullPath;
    }

    private sealed class SetupEventWriter : IDisposable
    {
        private readonly object _sync = new();
        private readonly StreamWriter _writer;

        public SetupEventWriter(string path)
        {
            var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.Read | FileShare.Delete);
            _writer = new StreamWriter(stream) { AutoFlush = true };
        }

        public void Send(SetupWorkerEvent message)
        {
            lock (_sync) _writer.WriteLine(JsonSerializer.Serialize(message));
        }

        public void Dispose() => _writer.Dispose();
    }
}

internal static class NativeTrust
{
    private static readonly Guid ActionGenericVerifyV2 = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

    public static void AssertTrustedSignedFile(string path, IEnumerable<string> allowedSubjects)
    {
        using var certificate = ReadTrustedCertificate(path);
        if (!allowedSubjects.Any(x => certificate.Subject.Contains(x, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("The installer was signed by an unexpected publisher: " + certificate.Subject);
    }

    public static void AssertTrustedSignedFile(string path, string expectedThumbprint)
    {
        using var certificate = ReadTrustedCertificate(path);
        var actual = certificate.Thumbprint.Replace(" ", "", StringComparison.Ordinal).ToUpperInvariant();
        var expected = expectedThumbprint.Replace(" ", "", StringComparison.Ordinal).ToUpperInvariant();
        if (!actual.Equals(expected, StringComparison.Ordinal))
            throw new InvalidDataException("The installer signature does not match the thumbprint published by its official website.");
    }

    private static X509Certificate2 ReadTrustedCertificate(string path)
    {
        var fileInfo = new WinTrustFileInfo(path);
        var data = new WinTrustData(fileInfo);
        try
        {
            var action = ActionGenericVerifyV2;
            var result = WinVerifyTrust(IntPtr.Zero, ref action, ref data);
            if (result != 0) throw new InvalidDataException($"Windows rejected the digital signature on {Path.GetFileName(path)} (0x{result:X8}).");
            return new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
        }
        finally { data.Dispose(); fileInfo.Dispose(); }
    }

    [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = true)]
    private static extern uint WinVerifyTrust(IntPtr hwnd, [MarshalAs(UnmanagedType.LPStruct)] ref Guid actionId, ref WinTrustData data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WinTrustFileInfo : IDisposable
    {
        public uint StructSize;
        public IntPtr FilePath;
        public IntPtr FileHandle;
        public IntPtr KnownSubject;

        public WinTrustFileInfo(string path)
        {
            StructSize = (uint)Marshal.SizeOf<WinTrustFileInfo>();
            FilePath = Marshal.StringToCoTaskMemUni(path);
            FileHandle = IntPtr.Zero;
            KnownSubject = IntPtr.Zero;
        }
        public void Dispose() { if (FilePath != IntPtr.Zero) Marshal.FreeCoTaskMem(FilePath); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WinTrustData : IDisposable
    {
        public uint StructSize;
        public IntPtr PolicyCallbackData;
        public IntPtr SIPClientData;
        public uint UIChoice;
        public uint RevocationChecks;
        public uint UnionChoice;
        public IntPtr FileInfoPtr;
        public uint StateAction;
        public IntPtr StateData;
        public string? URLReference;
        public uint ProviderFlags;
        public uint UIContext;

        public WinTrustData(WinTrustFileInfo fileInfo)
        {
            StructSize = (uint)Marshal.SizeOf<WinTrustData>();
            PolicyCallbackData = IntPtr.Zero;
            SIPClientData = IntPtr.Zero;
            UIChoice = 2;
            RevocationChecks = 0;
            UnionChoice = 1;
            FileInfoPtr = Marshal.AllocCoTaskMem(Marshal.SizeOf<WinTrustFileInfo>());
            Marshal.StructureToPtr(fileInfo, FileInfoPtr, false);
            StateAction = 0;
            StateData = IntPtr.Zero;
            URLReference = null;
            ProviderFlags = 0x00000010;
            UIContext = 0;
        }
        public void Dispose() { if (FileInfoPtr != IntPtr.Zero) Marshal.FreeCoTaskMem(FileInfoPtr); }
    }
}
