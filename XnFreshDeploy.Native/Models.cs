using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace XnFreshDeploy;

public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        return true;
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class ProfileCommand
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("value")]
    public string Value { get; set; } = "";

    public ProfileCommand Clone() => new() { Name = Name, Value = Value };
}

public sealed class ServerProfile : ObservableObject
{
    private string _name = "";
    private string _connect = "";
    private string _soundpack = "None";
    private string _reshade = "Keep current";
    private DateTimeOffset? _lastPlayed;
    private bool _favorite;
    private string _folder = "";
    private string _readiness = "Checking server...";
    private string _readinessColor = "#8FA4FF";

    [JsonPropertyName("name")]
    public string Name { get => _name; set => SetField(ref _name, value); }

    [JsonPropertyName("connect")]
    public string Connect { get => _connect; set => SetField(ref _connect, value); }

    [JsonPropertyName("soundpack")]
    public string Soundpack { get => _soundpack; set => SetField(ref _soundpack, value); }

    [JsonPropertyName("reshade")]
    public string Reshade { get => _reshade; set => SetField(ref _reshade, value); }

    [JsonPropertyName("commands")]
    public List<ProfileCommand> Commands { get; set; } = [];

    [JsonPropertyName("lastPlayed")]
    public DateTimeOffset? LastPlayed { get => _lastPlayed; set { if (SetField(ref _lastPlayed, value)) OnPropertyChanged(nameof(LastPlayedText)); } }

    [JsonPropertyName("favorite")]
    public bool Favorite { get => _favorite; set { if (SetField(ref _favorite, value)) OnPropertyChanged(nameof(FavoriteGlyph)); } }

    [JsonPropertyName("folder")]
    public string Folder { get => _folder; set { if (SetField(ref _folder, value)) OnPropertyChanged(nameof(FolderLabel)); } }

    [JsonPropertyName("tags")]
    public List<string> Tags { get; set; } = [];

    [JsonIgnore]
    public string FolderLabel => string.IsNullOrWhiteSpace(Folder) ? "" : Folder.Trim();

    [JsonIgnore]
    public string TagsLabel => Tags.Count == 0 ? "" : string.Join(", ", Tags);

    [JsonIgnore]
    public string FavoriteGlyph => Favorite ? "★" : "☆";

    [JsonIgnore]
    public string LastPlayedText => LastPlayed is null ? "Never played from Fresh Deploy" : $"Last played {LastPlayed.Value.ToLocalTime():g}";

    [JsonIgnore]
    public string CommandCountText => Commands.Count == 0 ? "No server commands" : $"{Commands.Count} server command{(Commands.Count == 1 ? "" : "s")}";

    [JsonIgnore]
    public string Readiness { get => _readiness; set => SetField(ref _readiness, value); }

    [JsonIgnore]
    public string ReadinessColor { get => _readinessColor; set => SetField(ref _readinessColor, value); }

    public ServerProfile Clone(string name) => new()
    {
        Name = name,
        Connect = Connect,
        Soundpack = Soundpack,
        Reshade = Reshade,
        Commands = Commands.Select(x => x.Clone()).ToList(),
        Favorite = false,
        Folder = Folder,
        Tags = Tags.Select(x => x).ToList()
    };
}

public sealed class ServerStore
{
    [JsonPropertyName("servers")]
    public List<ServerProfile> Servers { get; set; } = [];
}

public sealed class ProfileBundle
{
    [JsonPropertyName("format")]
    public string Format { get; set; } = "XnFreshDeployProfiles";

    [JsonPropertyName("version")]
    public int Version { get; set; } = 2;

    [JsonPropertyName("exportedAt")]
    public DateTimeOffset ExportedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("servers")]
    public List<ServerProfile> Servers { get; set; } = [];
}

public sealed class AppDefinition
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("desc")]
    public string Description { get; set; } = "";

    [JsonPropertyName("wingetId")]
    public string WingetId { get; set; } = "";

    [JsonPropertyName("selectedByDefault")]
    public bool SelectedByDefault { get; set; }

    [JsonPropertyName("launchAfter")]
    public bool LaunchAfter { get; set; }

    [JsonPropertyName("launchPaths")]
    public List<string> LaunchPaths { get; set; } = [];
}

public sealed class AppConfig
{
    [JsonPropertyName("apps")]
    public List<AppDefinition> Apps { get; set; } = [];

    [JsonPropertyName("fivem")]
    public FiveMConfig FiveM { get; set; } = new();
}

public sealed class FiveMConfig
{
    [JsonPropertyName("downloadUrl")]
    public string DownloadUrl { get; set; } = "https://runtime.fivem.net/client/FiveM.exe";
}

public sealed class CommandOption : ObservableObject
{
    private bool _isSelected;
    private string _inputValue = "";

    public string Id { get; init; } = "";
    public string Label { get; init; } = "";
    public string Name { get; init; } = "";
    public string Value { get; init; } = "";
    public string ValueKey { get; init; } = "";
    public string Group { get; init; } = "";
    public bool IsCustom { get; init; }
    public bool NeedsValue => ValueKey.Length > 0;
    public bool IsSelected { get => _isSelected; set => SetField(ref _isSelected, value); }
    public string InputValue { get => _inputValue; set => SetField(ref _inputValue, value); }
    public string EffectiveValue => NeedsValue ? InputValue.Trim() : Value;
}

public sealed class SetupOption : ObservableObject
{
    private bool _isSelected;
    private string _status = "Optional";

    public string Name { get; init; } = "";
    public string Description { get; init; } = "";
    public string Kind { get; init; } = "App";
    public string Id { get; init; } = "";
    public bool DefaultSelected { get; init; }
    public bool IsSelected { get => _isSelected; set => SetField(ref _isSelected, value); }
    public string Status { get => _status; set => SetField(ref _status, value); }
}

public sealed class SetupSelection
{
    public List<string> Apps { get; set; } = [];
    public bool Drivers { get; set; }
    public bool Mouse { get; set; }
    public bool FiveM { get; set; }
    public bool ReShade { get; set; }
    public bool Restore { get; set; }
    public bool Launch { get; set; }
}

public sealed class SetupWorkerEvent
{
    public string Type { get; set; } = "";
    public string Id { get; set; } = "";
    public string State { get; set; } = "";
    public string Message { get; set; } = "";
}

public sealed class HardwareInfo
{
    public string Cpu { get; set; } = "Unknown CPU";
    public string Gpu { get; set; } = "Unknown GPU";
    public string Windows { get; set; } = Environment.OSVersion.VersionString;
}

public sealed class ServerTestResult
{
    public bool Online { get; init; }
    public string Name { get; init; } = "";
    public string Players { get; init; } = "";
    public string Detail { get; init; } = "";
}

public sealed class ServerHint
{
    public string Connect { get; init; } = "";
    public string Name { get; init; } = "";
    public string Source { get; init; } = "";
}

public enum LibraryKind
{
    Soundpack,
    ReShade
}

public sealed class LibraryEntry
{
    public string Name { get; init; } = "";
    public LibraryKind Kind { get; init; }
    public int FileCount { get; init; }
    public string Usage { get; init; } = "Not used by a profile";
    public string Detail => $"{FileCount:N0} file{(FileCount == 1 ? "" : "s")} · {Usage}";
}

public sealed class ImportPreview
{
    public int FileCount { get; init; }
    public long TotalBytes { get; init; }
    public IReadOnlyList<string> FileTypes { get; init; } = [];
    public IReadOnlyList<string> RiskyFiles { get; init; } = [];
    public string Summary => $"{FileCount:N0} files, {FormatBytes(TotalBytes)}\nTypes: {(FileTypes.Count == 0 ? "No extensions" : string.Join(", ", FileTypes))}";
    public string Warning => RiskyFiles.Count == 0 ? "No executable, script, or DLL files detected." : $"Warning: {RiskyFiles.Count} executable, script, or DLL file(s) detected:\n{string.Join("\n", RiskyFiles.Take(12))}";

    private static string FormatBytes(long bytes) => bytes switch
    {
        >= 1_073_741_824 => $"{bytes / 1_073_741_824d:0.##} GB",
        >= 1_048_576 => $"{bytes / 1_048_576d:0.##} MB",
        >= 1024 => $"{bytes / 1024d:0.##} KB",
        _ => $"{bytes} bytes"
    };
}

public sealed class PortableImportResult
{
    public List<ServerProfile> Profiles { get; init; } = [];
    public int SoundpackCount { get; init; }
    public int ReShadeCount { get; init; }
}

public sealed class SetupProgressItem : ObservableObject
{
    private string _state = "Waiting";
    private string _detail = "Waiting to start.";
    private string _color = "#66758C";

    public string Id { get; init; } = "";
    public string Label { get; init; } = "";
    public string State { get => _state; set => SetField(ref _state, value); }
    public string Detail { get => _detail; set => SetField(ref _detail, value); }
    public string Color { get => _color; set => SetField(ref _color, value); }
}
