using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace XnFreshDeploy;

public partial class MainWindow : Window
{
    private readonly DataService _data = new();
    private readonly PackService _packs = new();
    private readonly BackupService _backup = new();
    private readonly ServerApi _serverApi = new();
    private readonly ServerDetectionService _serverDetection;
    private readonly PortableBackupService _portable = new();
    private readonly ObservableCollection<ServerProfile> _profiles = [];
    private readonly ObservableCollection<CommandOption> _commandOptions = [];
    private readonly ObservableCollection<SetupOption> _setupOptions = [];
    private readonly ObservableCollection<SetupProgressItem> _progressItems = [];
    private readonly string[] _args;
    private readonly UserSettings _settings;
    private readonly ToastHost _toasts;
    private AppConfig _config = new();
    private FiveMService _fiveM = null!;
    private SetupService _setup = null!;
    private ServerProfile? _editingProfile;
    private ServerProfile? _selectedProfile;
    private string? _editingOriginalName;
    private UpdateInfo? _pendingUpdate;
    private CancellationTokenSource? _readinessCancellation;
    private bool _loadingCommands;
    private bool _loaded;
    private bool _loadingTagFilter;
    private bool _loadingFolderFilter;

    public MainWindow(string[] args)
    {
        _settings = AppSettings.Load();
        if (!double.IsNaN(_settings.WindowLeft) && !double.IsNaN(_settings.WindowTop))
        {
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = _settings.WindowLeft;
            Top = _settings.WindowTop;
            Width = _settings.WindowWidth;
            Height = _settings.WindowHeight;
        }
        if (_settings.WindowMaximized) WindowState = WindowState.Maximized;

        InitializeComponent();
        _toasts = new ToastHost(ToastPanel);
        _args = args;
        _serverDetection = new ServerDetectionService(_serverApi);
        WindowChrome.ApplyDarkTitleBar(this);
        Loaded += MainWindow_Loaded;
        Closed += MainWindow_Closed;
    }

    private void MainWindow_Closed(object? sender, EventArgs e)
    {
        _readinessCancellation?.Cancel();
        SaveWindowState();
    }

    private void SaveWindowState()
    {
        if (WindowState == WindowState.Maximized)
        {
            _settings.WindowMaximized = true;
        }
        else
        {
            _settings.WindowMaximized = false;
            _settings.WindowLeft = Left;
            _settings.WindowTop = Top;
            _settings.WindowWidth = Width;
            _settings.WindowHeight = Height;
        }
        AppSettings.Save(_settings);
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        try
        {
            AppPaths.EnsurePortableLayout();
            _config = _data.LoadConfig();
            _fiveM = new FiveMService(_packs);
            _setup = new SetupService(_config, _backup);
            _packs.RecoverInterruptedSwitches();
            try { _fiveM.EnsureCanary(false); } catch { }

            foreach (var profile in _data.LoadProfiles()) _profiles.Add(profile);
            foreach (var app in _config.Apps)
            {
                var option = new SetupOption { Name = app.Name, Description = app.Description, Id = app.WingetId, DefaultSelected = app.SelectedByDefault, IsSelected = app.SelectedByDefault };
                option.PropertyChanged += (_, eventArgs) => { if (eventArgs.PropertyName == nameof(SetupOption.IsSelected)) UpdateSetupSummary(); };
                _setupOptions.Add(option);
            }
            SetupAppsItems.ItemsSource = _setupOptions;
            ProgressTasksItems.ItemsSource = _progressItems;
            LibrarySectionView.Initialize(_data, _profiles);
            ProfileSortBox.SelectedIndex = 0;
            RefreshLibraries();
            RestorePreviousButton.IsEnabled = _packs.CanRestorePrevious;
            ResetProfileForm();
            RefreshProfiles();
            RefreshFilters();
            UpdateBackupUi();
            UpdateDriverUi();
            UpdateSetupSummary();
            _ = LoadHardwareAsync();

            if (_args.Length >= 2 && _args[0].Equals("--play", StringComparison.OrdinalIgnoreCase))
            {
                var profile = _profiles.FirstOrDefault(x => x.Name.Equals(_args[1], StringComparison.OrdinalIgnoreCase));
                if (profile is not null) await PlayProfileAsync(profile);
            }

            VersionText.Text = AppVersion.Display;
            ShowProfiles();
            UpdateFiveMBadge();
            _ = CheckForUpdatesAsync();
            MaybeShowFirstRun();
            MaybeOfferLegacyImport();
        }
        catch (Exception ex)
        {
            CrashLogger.Write("startup", ex);
            MessageBox.Show(this, ex.Message, "Xn Fresh Deploy", MessageBoxButton.OK, MessageBoxImage.Error);
            Close();
        }
    }

    private void Notify(string message, ToastKind kind = ToastKind.Info)
    {
        if (ProfileStatusText.Visibility == Visibility.Visible) ProfileStatusText.Text = message;
        if (SetupStatusText.Visibility == Visibility.Visible) SetupStatusText.Text = message;
        _toasts.Show(message, kind);
    }

    private void MaybeShowFirstRun()
    {
        if (_settings.HasSeenFirstRun) return;
        var guide = new FirstRunWindow { Owner = this };
        if (guide.ShowDialog() == true)
        {
            _settings.HasSeenFirstRun = true;
            AppSettings.Save(_settings);
        }
    }

    private void MaybeOfferLegacyImport()
    {
        var candidates = LegacyMigrationService.FindCandidates();
        if (candidates.Count == 0 || _profiles.Count > 0) return;
        var first = candidates[0];
        if (MessageBox.Show(this,
                $"Found a previous Xn Fresh Deploy folder:\n{first.SourceDirectory}\n\nImport {first.ProfileCount} profile(s), {first.SoundpackCount} soundpack(s), and {first.ReShadeCount} ReShade look(s)?",
                "Import legacy data",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        ImportLegacyFrom(first.SourceDirectory);
    }

    private void UpdateFiveMBadge()
    {
        if (_fiveM is null) return;
        if (_fiveM.IsInstalled)
        {
            FiveMStatusText.Text = _fiveM.IsRunning ? "FiveM running" : "FiveM installed";
            FiveMStatusText.Foreground = (Brush)FindResource("GreenBrush");
        }
        else
        {
            FiveMStatusText.Text = "FiveM not found";
            FiveMStatusText.Foreground = (Brush)FindResource("AmberBrush");
        }
    }

    private Task<UpdateInfo?> QueryForUpdatesAsync() => UpdateChecker.CheckAsync();

    private async Task CheckForUpdatesAsync()
    {
        var update = await QueryForUpdatesAsync();
        if (update is null) return;
        if (string.Equals(_settings.SkippedUpdateVersion, update.Version, StringComparison.OrdinalIgnoreCase)) return;
        _pendingUpdate = update;
        UpdateBannerTitle.Text = $"Version {update.Version} is available";
        UpdateBannerDetail.Text = string.IsNullOrWhiteSpace(update.Notes)
            ? "A newer build is on GitHub."
            : (update.Notes.Length > 180 ? update.Notes[..180] + "…" : update.Notes);
        UpdateBanner.Visibility = Visibility.Visible;
    }

    private void DownloadUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingUpdate is null) return;
        Process.Start(new ProcessStartInfo(_pendingUpdate.Url) { UseShellExecute = true });
        Notify("Opened the latest release page in your browser.", ToastKind.Info);
    }

    private void DismissUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingUpdate is not null)
        {
            _settings.SkippedUpdateVersion = _pendingUpdate.Version;
            AppSettings.Save(_settings);
        }
        UpdateBanner.Visibility = Visibility.Collapsed;
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.N && Keyboard.Modifiers == ModifierKeys.Control && ProfilesScreen.Visibility == Visibility.Visible)
        {
            ResetProfileForm();
            ProfileNameBox.Focus();
            Notify("New profile form ready.", ToastKind.Info);
            e.Handled = true;
            return;
        }
        if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control && ProfilesScreen.Visibility == Visibility.Visible)
        {
            ProfileSearchBox.Focus();
            ProfileSearchBox.SelectAll();
            e.Handled = true;
            return;
        }
        if (e.Key == Key.Enter && ProfilesScreen.Visibility == Visibility.Visible && _selectedProfile is not null &&
            !ProfileNameBox.IsKeyboardFocused && !ProfileConnectBox.IsKeyboardFocused && !ProfileSearchBox.IsKeyboardFocused)
        {
            _ = PlayProfileAsync(_selectedProfile);
            e.Handled = true;
        }
    }

    private async void ProfileCard_Select(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not ServerProfile profile) return;
        _selectedProfile = profile;
        _settings.LastSelectedProfile = profile.Name;
        AppSettings.Save(_settings);
        if (e.ClickCount >= 2)
        {
            await PlayProfileAsync(profile);
            return;
        }
        Notify($"Selected {profile.Name}. Press Enter to play.", ToastKind.Info);
    }

    private void FolderFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingFolderFilter || !_loaded) return;
        _settings.FolderFilter = FolderFilterBox.SelectedItem?.ToString() ?? "";
        AppSettings.Save(_settings);
        RefreshProfiles();
    }

    private void TagFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingTagFilter || !_loaded) return;
        _settings.TagFilter = TagFilterBox.SelectedItem?.ToString() ?? "";
        AppSettings.Save(_settings);
        RefreshProfiles();
    }

    private void ImportLegacy_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Choose a legacy XnFreshDeploy folder",
            InitialDirectory = Directory.GetParent(AppPaths.BaseDirectory)?.FullName ?? AppPaths.BaseDirectory
        };
        if (dialog.ShowDialog(this) == true) ImportLegacyFrom(dialog.FolderName);
    }

    private void ImportLegacyFrom(string sourceDirectory)
    {
        try
        {
            var result = LegacyMigrationService.Migrate(sourceDirectory, _profiles, _data);
            RefreshFilters();
            RefreshProfiles();
            RefreshLibraries();
            LibrarySectionView.RefreshItems();
            Notify($"Imported {result.Profiles} profile(s), {result.Soundpacks} soundpack(s), and {result.ReShadeLooks} ReShade look(s).", ToastKind.Success);
        }
        catch (Exception ex) { Notify(ex.Message, ToastKind.Error); }
    }

    private void ProfilesNav_Click(object sender, RoutedEventArgs e) => ShowProfiles();

    private void Version_Click(object sender, MouseButtonEventArgs e)
    {
        var about = new AboutWindow(QueryForUpdatesAsync) { Owner = this };
        about.ShowDialog();
    }

    private void Help_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button) return;
        var menu = new ContextMenu { PlacementTarget = button, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        menu.Items.Add(Menu("Open app folder", () => OpenFolder(AppPaths.BaseDirectory)));
        menu.Items.Add(Menu("Open crash logs", () => OpenFolder(Path.Combine(AppPaths.BaseDirectory, "logs"))));
        menu.Items.Add(Menu("View releases", () => Process.Start(new ProcessStartInfo($"https://github.com/{UpdateChecker.GitHubRepo}/releases") { UseShellExecute = true })));
        menu.Items.Add(Menu("Report issue", () => Process.Start(new ProcessStartInfo($"https://github.com/{UpdateChecker.GitHubRepo}/issues/new/choose") { UseShellExecute = true })));
        menu.Items.Add(Menu("First-run guide", () => new FirstRunWindow { Owner = this }.ShowDialog()));
        menu.Items.Add(Menu("About", () => new AboutWindow(QueryForUpdatesAsync) { Owner = this }.ShowDialog()));
        menu.IsOpen = true;
    }

    private static MenuItem Menu(string label, Action action)
    {
        var item = new MenuItem { Header = label };
        item.Click += (_, _) => action();
        return item;
    }

    private void CopyConnect_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not ServerProfile profile) return;
        try
        {
            Clipboard.SetText(profile.Connect);
            Notify($"Copied connect target for {profile.Name}.", ToastKind.Success);
        }
        catch (Exception ex) { Notify(ex.Message, ToastKind.Error); }
    }
    private void LibraryNav_Click(object sender, RoutedEventArgs e) => ShowLibrary();
    private void SetupNav_Click(object sender, RoutedEventArgs e) => ShowSetup();

    private void ShowProfiles()
    {
        UiChrome.SetActiveNav(ProfilesNavButton, ProfilesNavButton, LibraryNavButton, SetupNavButton);
        UiChrome.ShowScreen(ProfilesScreen, SetupScreen, LibrarySectionView, ProgressScreen);
        ShowFooterStatus(ProfileStatusText);
        RefreshLibraries();
        RefreshProfiles();
    }

    private void ShowLibrary()
    {
        UiChrome.SetActiveNav(LibraryNavButton, ProfilesNavButton, LibraryNavButton, SetupNavButton);
        UiChrome.ShowScreen(LibrarySectionView, ProfilesScreen, SetupScreen, ProgressScreen);
        ShowFooterStatus(ProfileStatusText);
        LibrarySectionView.RefreshItems();
    }

    private void ShowSetup()
    {
        UiChrome.SetActiveNav(SetupNavButton, ProfilesNavButton, LibraryNavButton, SetupNavButton);
        UiChrome.ShowScreen(SetupScreen, ProfilesScreen, LibrarySectionView, ProgressScreen);
        ShowFooterStatus(SetupStatusText);
    }

    private void ShowFooterStatus(TextBlock active)
    {
        ProfileStatusText.Visibility = ReferenceEquals(active, ProfileStatusText) ? Visibility.Visible : Visibility.Collapsed;
        SetupStatusText.Visibility = ReferenceEquals(active, SetupStatusText) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshProfiles()
    {
        if (_fiveM is null) return;
        foreach (var profile in _profiles)
        {
            profile.Readiness = _fiveM.Readiness(profile);
            profile.ReadinessColor = UiChrome.ReadinessColor(profile.Readiness);
        }
        IEnumerable<ServerProfile> view = _profiles;
        var query = ProfileSearchBox.Text.Trim();
        if (query.Length > 0) view = view.Where(x => x.Name.Contains(query, StringComparison.OrdinalIgnoreCase) || x.Connect.Contains(query, StringComparison.OrdinalIgnoreCase));
        var tag = TagFilterBox.SelectedItem?.ToString();
        if (!string.IsNullOrWhiteSpace(tag) && !tag.Equals("All tags", StringComparison.OrdinalIgnoreCase))
            view = view.Where(x => x.Tags.Any(t => t.Equals(tag, StringComparison.OrdinalIgnoreCase)));
        var folder = FolderFilterBox.SelectedItem?.ToString();
        if (!string.IsNullOrWhiteSpace(folder) && !folder.Equals("All folders", StringComparison.OrdinalIgnoreCase))
            view = view.Where(x => x.Folder.Equals(folder, StringComparison.OrdinalIgnoreCase));
        var sort = (ProfileSortBox.SelectedItem as ComboBoxItem)?.Content?.ToString();
        view = sort switch
        {
            "Server name" => view.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase),
            "Favourites" => view.OrderByDescending(x => x.Favorite).ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase),
            _ => view.OrderByDescending(x => x.LastPlayed ?? DateTimeOffset.MinValue)
        };
        var displayed = view.ToList();
        EmptyProfilesPanel.Visibility = displayed.Count == 0 && query.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        ProfilesItems.ItemsSource = displayed;
        if (_selectedProfile is null && !string.IsNullOrWhiteSpace(_settings.LastSelectedProfile))
            _selectedProfile = displayed.FirstOrDefault(x => x.Name.Equals(_settings.LastSelectedProfile, StringComparison.OrdinalIgnoreCase));
        _readinessCancellation?.Cancel();
        _readinessCancellation?.Dispose();
        _readinessCancellation = new CancellationTokenSource();
        _ = RefreshServerStatusesAsync(displayed, _readinessCancellation.Token);
        UpdateFiveMBadge();
    }

    private void RefreshFilters()
    {
        _loadingTagFilter = true;
        _loadingFolderFilter = true;
        var tags = _profiles.SelectMany(x => x.Tags).Select(x => x.Trim()).Where(x => x.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
        var tagItems = new List<string> { "All tags" };
        tagItems.AddRange(tags);
        var selectedTag = string.IsNullOrWhiteSpace(_settings.TagFilter) ? "All tags" : _settings.TagFilter;
        TagFilterBox.ItemsSource = tagItems;
        TagFilterBox.SelectedItem = tagItems.FirstOrDefault(x => x.Equals(selectedTag, StringComparison.OrdinalIgnoreCase)) ?? "All tags";

        var folders = _profiles.Select(x => x.Folder).Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
        var folderItems = new List<string> { "All folders" };
        folderItems.AddRange(folders);
        var selectedFolder = string.IsNullOrWhiteSpace(_settings.FolderFilter) ? "All folders" : _settings.FolderFilter;
        FolderFilterBox.ItemsSource = folderItems;
        FolderFilterBox.SelectedItem = folderItems.FirstOrDefault(x => x.Equals(selectedFolder, StringComparison.OrdinalIgnoreCase)) ?? "All folders";
        _loadingTagFilter = false;
        _loadingFolderFilter = false;
    }

    private async Task RefreshServerStatusesAsync(IReadOnlyCollection<ServerProfile> profiles, CancellationToken cancellationToken)
    {
        using var limit = new SemaphoreSlim(4);
        var tasks = profiles.Where(x => x.Readiness == "Ready").Select(async profile =>
        {
            var acquired = false;
            try
            {
                await limit.WaitAsync(cancellationToken);
                acquired = true;
                profile.Readiness = "Checking…";
                profile.ReadinessColor = UiChrome.Muted;
                var result = await _serverApi.TestAsync(profile.Connect, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                profile.Readiness = result.Online ? (result.Players.Length > 0 ? $"Online · {result.Players}" : "Online") : "Offline";
                profile.ReadinessColor = UiChrome.ReadinessColor(profile.Readiness);
            }
            catch (OperationCanceledException) { }
            finally { if (acquired) limit.Release(); }
        });
        await Task.WhenAll(tasks);
    }

    private void RefreshLibraries()
    {
        var sound = new[] { "None" }.Concat(Directory.GetDirectories(AppPaths.SoundpacksDirectory).Select(Path.GetFileName).Where(x => x is not null)!).OrderBy(x => x == "None" ? "" : x).ToList();
        var looks = new[] { "Keep current" }.Concat(Directory.GetDirectories(AppPaths.ReShadeDirectory).Select(Path.GetFileName).Where(x => x is not null)!).OrderBy(x => x == "Keep current" ? "" : x).ToList();
        SoundpackBox.ItemsSource = sound;
        ReShadeBox.ItemsSource = looks;
    }

    private void ResetProfileForm()
    {
        _editingProfile = null;
        _editingOriginalName = null;
        ProfileFormEyebrow.Text = "New profile";
        ProfileFormTitle.Text = "Add a server";
        SaveProfileButton.Content = "Save profile";
        CancelEditButton.Visibility = Visibility.Collapsed;
        ProfileNameBox.Text = "";
        ProfileFolderBox.Text = "";
        ProfileTagsBox.Text = "";
        ProfileConnectBox.Text = "";
        SoundpackBox.SelectedItem = "None";
        ReShadeBox.SelectedItem = "Keep current";
        LoadCommandOptions(CommandCatalog.Create());
        CustomNameBox.Text = "";
        CustomValueBox.Text = "";
    }

    private void LoadProfileForm(ServerProfile profile)
    {
        _editingProfile = profile;
        _editingOriginalName = profile.Name;
        ProfileFormEyebrow.Text = "Editing";
        ProfileFormTitle.Text = profile.Name;
        SaveProfileButton.Content = "Save changes";
        CancelEditButton.Visibility = Visibility.Visible;
        ProfileNameBox.Text = profile.Name;
        ProfileFolderBox.Text = profile.Folder;
        ProfileTagsBox.Text = string.Join(", ", profile.Tags);
        ProfileConnectBox.Text = profile.Connect;
        SoundpackBox.SelectedItem = SoundpackBox.Items.Cast<string>().Contains(profile.Soundpack) ? profile.Soundpack : "None";
        ReShadeBox.SelectedItem = ReShadeBox.Items.Cast<string>().Contains(profile.Reshade) ? profile.Reshade : "Keep current";
        LoadCommandOptions(CommandCatalog.FromCommands(profile.Commands.Select(x => x.Clone())));
    }

    private void LoadCommandOptions(IEnumerable<CommandOption> options)
    {
        _loadingCommands = true;
        _commandOptions.Clear();
        foreach (var option in options)
        {
            option.PropertyChanged += (_, eventArgs) =>
            {
                if (eventArgs.PropertyName == nameof(CommandOption.IsSelected) && !_loadingCommands) UpdateCommandPanels();
            };
            _commandOptions.Add(option);
        }
        CommandList.ItemsSource = _commandOptions;
        _loadingCommands = false;
        UpdateCommandPanels();
    }

    private void UpdateCommandPanels()
    {
        if (_loadingCommands) return;
        var mouse = _commandOptions.First(x => x.ValueKey == "MouseScale");
        var fov = _commandOptions.First(x => x.ValueKey == "Fov");
        MouseScalePanel.Visibility = mouse.IsSelected ? Visibility.Visible : Visibility.Collapsed;
        FovPanel.Visibility = fov.IsSelected ? Visibility.Visible : Visibility.Collapsed;
        if (!MouseScaleBox.IsKeyboardFocused) MouseScaleBox.Text = mouse.InputValue;
        if (!FovBox.IsKeyboardFocused) FovBox.Text = fov.InputValue;
        var count = _commandOptions.Count(x => x.IsSelected);
        CommandSummaryText.Text = count switch
        {
            0 => "Click to select. Ctrl+click for multiple.",
            1 => "1 command selected.",
            _ => $"{count} commands selected."
        };
    }

    private void CommandList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingCommands) return;
        foreach (var added in e.AddedItems.OfType<CommandOption>().Where(x => x.Group.Length > 0))
            foreach (var other in _commandOptions.Where(x => x != added && x.Group == added.Group)) other.IsSelected = false;
        UpdateCommandPanels();
    }

    private void CommandValue_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_loadingCommands) return;
        var mouse = _commandOptions.FirstOrDefault(x => x.ValueKey == "MouseScale");
        var fov = _commandOptions.FirstOrDefault(x => x.ValueKey == "Fov");
        if (mouse is not null) mouse.InputValue = MouseScaleBox.Text;
        if (fov is not null) fov.InputValue = FovBox.Text;
    }

    private void AddCustomCommand_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var item = CommandCatalog.AddCustom(_commandOptions, CustomNameBox.Text, CustomValueBox.Text);
            CustomNameBox.Text = "";
            CustomValueBox.Text = "";
            CommandList.Items.Refresh();
            UpdateCommandPanels();
            ProfileStatusText.Text = $"Added and selected custom command: {item.Name} {item.Value}";
        }
        catch (Exception ex) { ProfileStatusText.Text = ex.Message; }
    }

    private void RemoveCustomCommand_Click(object sender, RoutedEventArgs e)
    {
        var selected = _commandOptions.Where(x => x.IsCustom && x.IsSelected).ToList();
        foreach (var item in selected) _commandOptions.Remove(item);
        UpdateCommandPanels();
        ProfileStatusText.Text = selected.Count == 0 ? "Select a Custom entry first." : $"Removed {selected.Count} custom command(s).";
    }

    private async void SaveProfile_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var name = ProfileNameBox.Text.Trim();
            var connect = FiveMService.NormalizeConnectTarget(ProfileConnectBox.Text);
            if (!System.Text.RegularExpressions.Regex.IsMatch(name, @"^[\w .-]{1,30}$")) throw new InvalidDataException("Use letters, numbers, spaces, dashes, or dots for the profile name (max 30).");
            if (connect.Length == 0) throw new InvalidDataException("Enter a connect code, link, or IP.");
            if (_profiles.Any(x => !ReferenceEquals(x, _editingProfile) && x.Name.Equals(name, StringComparison.OrdinalIgnoreCase))) throw new InvalidDataException("Another profile already uses that name.");
            var commands = CommandCatalog.ToCommands(_commandOptions);
            var folder = ProfileFolderBox.Text.Trim();
            var tags = ParseTags(ProfileTagsBox.Text);
            string? shortcutPreviousName = null;
            if (_editingProfile is null)
            {
                _profiles.Add(new ServerProfile
                {
                    Name = name,
                    Connect = connect,
                    Folder = folder,
                    Tags = tags,
                    Soundpack = SoundpackBox.SelectedItem?.ToString() ?? "None",
                    Reshade = ReShadeBox.SelectedItem?.ToString() ?? "Keep current",
                    Commands = commands
                });
                Notify($"Created {name}.", ToastKind.Success);
            }
            else
            {
                var previousName = _editingOriginalName ?? _editingProfile.Name;
                shortcutPreviousName = previousName;
                _editingProfile.Name = name;
                _editingProfile.Connect = connect;
                _editingProfile.Folder = folder;
                _editingProfile.Tags = tags;
                _editingProfile.Soundpack = SoundpackBox.SelectedItem?.ToString() ?? "None";
                _editingProfile.Reshade = ReShadeBox.SelectedItem?.ToString() ?? "Keep current";
                _editingProfile.Commands = commands;
                Notify($"Saved changes to {name}.", ToastKind.Success);
            }
            _data.SaveProfiles(_profiles);
            if (shortcutPreviousName is not null && _editingProfile is not null)
            {
                try { ShortcutService.UpdateIfPresent(shortcutPreviousName, _editingProfile); }
                catch (Exception ex) { Notify($"Profile saved, but shortcut update failed: {ex.Message}", ToastKind.Warning); }
            }
            ResetProfileForm();
            RefreshProfiles();
            RefreshFilters();
            await Task.CompletedTask;
        }
        catch (Exception ex) { Notify(ex.Message, ToastKind.Error); }
    }

    private static List<string> ParseTags(string value) => value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(tag => tag.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(12)
        .ToList();

    private void CancelEdit_Click(object sender, RoutedEventArgs e) => ResetProfileForm();
    private void EditProfile_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is ServerProfile profile) LoadProfileForm(profile); }

    private void FavouriteProfile_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not ServerProfile profile) return;
        profile.Favorite = !profile.Favorite;
        _data.SaveProfiles(_profiles);
        RefreshProfiles();
    }

    private void ProfileMore_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not ServerProfile profile) return;
        var menu = new ContextMenu { PlacementTarget = button, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        menu.Items.Add(CreateProfileMenuItem("Desktop shortcut", () =>
        {
            try
            {
                ShortcutService.Create(profile);
                ProfileStatusText.Text = $"Shortcut created for {profile.Name}.";
            }
            catch (Exception ex) { ProfileStatusText.Text = ex.Message; }
        }));
        menu.Items.Add(CreateProfileMenuItem("Duplicate", () =>
        {
            var stem = profile.Name.Length > 24 ? profile.Name[..24].Trim() : profile.Name;
            var name = stem + " Copy";
            var number = 2;
            while (_profiles.Any(x => x.Name.Equals(name, StringComparison.OrdinalIgnoreCase))) name = $"{stem} Copy {number++}";
            _profiles.Add(profile.Clone(name));
            _data.SaveProfiles(_profiles);
            RefreshProfiles();
            RefreshFilters();
            ProfileStatusText.Text = $"Duplicated as {name}.";
        }));
        menu.Items.Add(CreateProfileMenuItem("Remove", () =>
        {
            if (MessageBox.Show(this, $"Remove '{profile.Name}'?", "Remove profile", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            _profiles.Remove(profile);
            _data.SaveProfiles(_profiles);
            try { ShortcutService.DeleteIfPresent(profile.Name); } catch { }
            RefreshProfiles();
            RefreshFilters();
            ProfileStatusText.Text = $"Removed {profile.Name}.";
        }));
        menu.IsOpen = true;
    }

    private static MenuItem CreateProfileMenuItem(string label, Action action)
    {
        var item = new MenuItem { Header = label };
        item.Click += (_, _) => action();
        return item;
    }

    private async void PlayProfile_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is ServerProfile profile) await PlayProfileAsync(profile); }

    private async Task PlayProfileAsync(ServerProfile profile)
    {
        try
        {
            ProfileStatusText.Text = $"Preparing {profile.Name}...";
            var progress = new Progress<string>(message => ProfileStatusText.Text = message);
            await _fiveM.LaunchAsync(profile, progress);
            profile.LastPlayed = DateTimeOffset.UtcNow;
            _data.SaveProfiles(_profiles);
            RefreshProfiles();
            RefreshFilters();
            ProfileStatusText.Text = $"Connecting to {profile.Name}.";
            UiChrome.Pulse(ProfileStatusText);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Could not launch FiveM", MessageBoxButton.OK, MessageBoxImage.Warning); ProfileStatusText.Text = ex.Message; }
        finally { RestorePreviousButton.IsEnabled = _packs.CanRestorePrevious; }
    }

    private async void TestConnection_Click(object sender, RoutedEventArgs e)
    {
        TestConnectionButton.IsEnabled = false;
        ProfileStatusText.Text = "Testing the server...";
        try
        {
            var result = await _serverApi.TestAsync(ProfileConnectBox.Text);
            ProfileStatusText.Text = result.Online ? $"Online. {result.Players} {result.Detail}".Trim() : result.Detail;
            if (result.Online && ProfileNameBox.Text.Trim().Length == 0 && result.Name.Length > 0)
            {
                var clean = System.Text.RegularExpressions.Regex.Replace(result.Name, @"\^[0-9]|[^\w .-]", "").Trim();
                ProfileNameBox.Text = clean.Length > 30 ? clean[..30].Trim() : clean;
            }
        }
        finally { TestConnectionButton.IsEnabled = true; }
    }

    private async void DetectServer_Click(object sender, RoutedEventArgs e)
    {
        DetectServerButton.IsEnabled = false;
        ProfileStatusText.Text = "Checking recent FiveM connection details…";
        try
        {
            var hint = await _serverDetection.DetectAsync();
            if (hint is null)
            {
                ProfileStatusText.Text = "No recent server was found. Join it once in FiveM, then choose Detect from FiveM again.";
                return;
            }
            ProfileConnectBox.Text = hint.Connect;
            if (ProfileNameBox.Text.Trim().Length == 0 && hint.Name.Length > 0) ProfileNameBox.Text = CleanProfileName(hint.Name);
            ProfileStatusText.Text = $"Detected {hint.Connect} from the {hint.Source}. Test the connection before saving.";
        }
        catch (Exception ex) { ProfileStatusText.Text = ex.Message; }
        finally { DetectServerButton.IsEnabled = true; }
    }

    private static string CleanProfileName(string value)
    {
        var clean = System.Text.RegularExpressions.Regex.Replace(value, @"\^[0-9]|[^\w .-]", "").Trim();
        return clean.Length > 30 ? clean[..30].Trim() : clean;
    }

    private void ProfileSearch_TextChanged(object sender, TextChangedEventArgs e) { if (_loaded) RefreshProfiles(); }
    private void ProfileSort_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (_loaded) RefreshProfiles(); }

    private async void RestorePrevious_Click(object sender, RoutedEventArgs e)
    {
        if (_fiveM.IsRunning) { ProfileStatusText.Text = "Close FiveM before restoring the previous setup."; return; }
        if (MessageBox.Show(this, "Swap the active soundpack and ReShade look with the previous working setup? You can use this button again to swap back.", "Restore previous setup", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        RestorePreviousButton.IsEnabled = false;
        try
        {
            var progress = new Progress<string>(message => ProfileStatusText.Text = message);
            await _packs.RestorePreviousAsync(progress);
            ProfileStatusText.Text = "The previous soundpack and ReShade setup was restored.";
        }
        catch (Exception ex) { ProfileStatusText.Text = ex.Message; }
        finally { RestorePreviousButton.IsEnabled = _packs.CanRestorePrevious; }
    }
    private void OpenDrivers_Click(object sender, RoutedEventArgs e) => OpenFolder(AppPaths.DriversDirectory);
    private void OpenBackup_Click(object sender, RoutedEventArgs e) { Directory.CreateDirectory(AppPaths.BackupDirectory); OpenFolder(AppPaths.BackupDirectory); }
    private static void OpenFolder(string path) { Directory.CreateDirectory(path); Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true }); }

    private void ExportProfiles_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { Filter = "Xn profile backup (*.xnprofiles.json)|*.xnprofiles.json", FileName = $"Xn-Profiles-{DateTime.Now:yyyy-MM-dd}.xnprofiles.json" };
        if (dialog.ShowDialog(this) != true) return;
        _data.ExportProfiles(dialog.FileName, _profiles);
        ProfileStatusText.Text = "Profiles exported to " + dialog.FileName;
    }

    private async void PortableBackup_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog
        {
            Filter = "Xn portable backup (*.xnportable.zip)|*.xnportable.zip",
            FileName = $"Xn-Portable-{DateTime.Now:yyyy-MM-dd}.xnportable.zip"
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            ProfileStatusText.Text = "Building the full portable backup with referenced packs…";
            await _portable.ExportAsync(dialog.FileName, _profiles, _config);
            ProfileStatusText.Text = "Full portable backup created: " + dialog.FileName;
        }
        catch (Exception ex) { ProfileStatusText.Text = ex.Message; }
    }

    private async void ImportProfiles_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "Xn backups (*.xnprofiles.json;*.xnportable.zip;*.json)|*.xnprofiles.json;*.xnportable.zip;*.json|Profile backup (*.json)|*.json|Full portable backup (*.zip)|*.zip" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            if (Path.GetExtension(dialog.FileName).Equals(".zip", StringComparison.OrdinalIgnoreCase))
            {
                ProfileStatusText.Text = "Reviewing the portable backup…";
                var review = await _portable.PreviewAsync(dialog.FileName);
                var icon = review.Preview.RiskyFiles.Count == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning;
                var answer = MessageBox.Show(this,
                    $"Import this full portable backup?\n\nProfiles: {review.Profiles}\nSoundpacks: {review.Soundpacks}\nReShade looks: {review.ReShade}\n\n{review.Preview.Summary}\n\n{review.Preview.Warning}",
                    "Review portable import", MessageBoxButton.YesNo, icon);
                if (answer != MessageBoxResult.Yes) { ProfileStatusText.Text = "Import cancelled."; return; }
                var imported = await _portable.ImportAsync(dialog.FileName);
                foreach (var profile in imported.Profiles) AddImportedProfile(profile);
                _data.SaveProfiles(_profiles);
                RefreshLibraries();
                RefreshProfiles();
            RefreshFilters();
                ProfileStatusText.Text = $"Imported {imported.Profiles.Count} profiles, {imported.SoundpackCount} soundpacks, and {imported.ReShadeCount} ReShade looks.";
                return;
            }
            var added = 0;
            foreach (var incoming in _data.ImportProfiles(dialog.FileName))
            {
                AddImportedProfile(incoming);
                added++;
            }
            _data.SaveProfiles(_profiles);
            RefreshProfiles();
            RefreshFilters();
            ProfileStatusText.Text = $"Imported {added} profile(s).";
        }
        catch (Exception ex) { ProfileStatusText.Text = ex.Message; }
    }

    private void AddImportedProfile(ServerProfile incoming)
    {
        var original = incoming.Name;
        var name = original;
        var number = 2;
        while (_profiles.Any(x => x.Name.Equals(name, StringComparison.OrdinalIgnoreCase))) name = $"{original} {number++}";
        incoming.Name = name;
        _profiles.Add(incoming);
    }

    private async Task LoadHardwareAsync()
    {
        var info = await Task.Run(HardwareService.Detect);
        CpuText.Text = info.Cpu;
        GpuText.Text = info.Gpu;
        WindowsText.Text = info.Windows;
    }

    private void SetupChoice_Changed(object sender, RoutedEventArgs e) { if (_loaded) UpdateSetupSummary(); }

    private void RecommendedSetup_Click(object sender, RoutedEventArgs e)
    {
        foreach (var option in _setupOptions) option.IsSelected = option.DefaultSelected;
        DriversCheck.IsChecked = Directory.EnumerateFiles(AppPaths.DriversDirectory).Any();
        MouseCheck.IsChecked = false;
        FiveMCheck.IsChecked = true;
        ReShadeCheck.IsChecked = true;
        RestoreCheck.IsChecked = _backup.HasBackup;
        LaunchCheck.IsChecked = false;
        UpdateSetupSummary();
    }

    private void ClearSetup_Click(object sender, RoutedEventArgs e)
    {
        foreach (var option in _setupOptions) option.IsSelected = false;
        DriversCheck.IsChecked = MouseCheck.IsChecked = FiveMCheck.IsChecked = ReShadeCheck.IsChecked = RestoreCheck.IsChecked = LaunchCheck.IsChecked = false;
        UpdateSetupSummary();
    }

    private SetupSelection CurrentSetupSelection() => new()
    {
        Apps = _setupOptions.Where(x => x.IsSelected).Select(x => x.Name).ToList(),
        Drivers = DriversCheck.IsChecked == true,
        Mouse = MouseCheck.IsChecked == true,
        FiveM = FiveMCheck.IsChecked == true,
        ReShade = ReShadeCheck.IsChecked == true,
        Restore = RestoreCheck.IsChecked == true,
        Launch = LaunchCheck.IsChecked == true
    };

    private void UpdateSetupSummary()
    {
        if (!_loaded) return;
        var selection = CurrentSetupSelection();
        var lines = new List<string>();
        if (selection.Apps.Count > 0) lines.Add($"Apps\n  {string.Join(", ", selection.Apps)}");
        if (selection.Drivers) lines.Add("Drivers\n  Run local packages");
        var gaming = new List<string>(); if (selection.FiveM) gaming.Add("FiveM"); if (selection.ReShade) gaming.Add("ReShade");
        if (gaming.Count > 0) lines.Add("Gaming setup\n  " + string.Join(", ", gaming));
        if (selection.Mouse) lines.Add("Windows\n  Disable mouse acceleration");
        if (selection.Restore) lines.Add("Backup\n  Restore saved data");
        if (selection.Launch) lines.Add("Finishing\n  Open selected apps");
        SetupSummaryText.Text = lines.Count == 0 ? "Nothing selected yet." : string.Join("\n\n", lines);
        var count = _setup.BuildTasks(selection).Count;
        SetupCountText.Text = $"{count} task{(count == 1 ? "" : "s")} selected";
    }

    private void UpdateDriverUi()
    {
        var count = Directory.Exists(AppPaths.DriversDirectory)
            ? Directory.EnumerateFiles(AppPaths.DriversDirectory).Count(x => Path.GetExtension(x).Equals(".exe", StringComparison.OrdinalIgnoreCase) || Path.GetExtension(x).Equals(".msi", StringComparison.OrdinalIgnoreCase)) : 0;
        DriversDetailText.Text = count == 0 ? "No .exe or .msi packages detected." : $"{count} local driver package(s) ready.";
    }

    private void UpdateBackupUi()
    {
        BackupDetailText.Text = _backup.HasBackup ? "A portable backup is available." : "No backup available.";
        RestoreCheck.IsEnabled = _backup.HasBackup;
        if (!_backup.HasBackup) RestoreCheck.IsChecked = false;
    }

    private async void BackupNow_Click(object sender, RoutedEventArgs e)
    {
        try { await Task.Run(_backup.CreateBackup); UpdateBackupUi(); SetupStatusText.Text = "Backup completed beside the app."; }
        catch (Exception ex) { SetupStatusText.Text = ex.Message; }
    }

    private void EditConfig_Click(object sender, RoutedEventArgs e) => Process.Start(new ProcessStartInfo("notepad.exe", $"\"{AppPaths.ConfigFile}\"") { UseShellExecute = true });

    private async void StartSetup_Click(object sender, RoutedEventArgs e)
    {
        var selection = CurrentSetupSelection();
        if (_setup.BuildTasks(selection).Count == 0) { SetupStatusText.Text = "Choose at least one setup action first."; return; }
        if (!SetupService.IsAdministrator())
        {
            await RunElevatedSetupAsync(selection);
            return;
        }
        await RunSetupAsync(selection);
    }

    private async Task RunSetupAsync(SetupSelection selection)
    {
        PrepareProgressUi(selection);
        try
        {
            await _setup.RunAsync(selection, UpdateProgressStage, AppendProgressLog, CancellationToken.None);
            FinishProgressUi(stopped: false);
        }
        catch (Exception ex)
        {
            AppendProgressLog(ex.Message);
            FinishProgressUi(stopped: true);
        }
    }

    private async Task RunElevatedSetupAsync(SetupSelection selection)
    {
        var operationId = Guid.NewGuid().ToString("N");
        var handoff = Path.Combine(Path.GetTempPath(), $"XnFreshDeploy-setup-{operationId}.json");
        var eventsPath = Path.Combine(Path.GetTempPath(), $"XnFreshDeploy-events-{operationId}.jsonl");
        PrepareProgressUi(selection);
        ProgressStateText.Text = UiChrome.SetupPhaseLabel("waiting");
        ProgressCurrentText.Text = "Waiting for administrator permission…";
        try
        {
            await File.WriteAllTextAsync(handoff, JsonSerializer.Serialize(selection));
            await File.WriteAllTextAsync(eventsPath, "");
            var start = new ProcessStartInfo(Environment.ProcessPath!)
            {
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            };
            start.ArgumentList.Add("--setup-worker");
            start.ArgumentList.Add(handoff);
            start.ArgumentList.Add(eventsPath);
            using var worker = Process.Start(start) ?? throw new InvalidOperationException("The administrator setup worker could not be started.");
            ProgressStateText.Text = UiChrome.SetupPhaseLabel("active");
            ProgressCurrentText.Text = "Administrator permission granted. Starting setup…";
            AppendProgressLog("The main app will stay open while the elevated setup worker runs in the background.");

            var position = 0L;
            var receivedDone = false;
            var stopped = false;
            while (!worker.HasExited)
            {
                ReadWorkerEvents(eventsPath, ref position, ref receivedDone, ref stopped);
                await Task.Delay(180);
            }
            await worker.WaitForExitAsync();
            await Task.Delay(100);
            ReadWorkerEvents(eventsPath, ref position, ref receivedDone, ref stopped);
            if (!receivedDone && worker.ExitCode != 0) stopped = true;
            FinishProgressUi(stopped);
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            ShowSetup();
            SetupStatusText.Text = "Setup cancelled — no changes were made.";
        }
        catch (Exception ex)
        {
            AppendProgressLog(ex.Message);
            FinishProgressUi(stopped: true);
        }
        finally
        {
            try { File.Delete(handoff); } catch { }
            try { File.Delete(eventsPath); } catch { }
        }
    }

    private void PrepareProgressUi(SetupSelection selection)
    {
        UiChrome.SetActiveNav(SetupNavButton, ProfilesNavButton, LibraryNavButton, SetupNavButton);
        UiChrome.ShowScreen(ProgressScreen, ProfilesScreen, SetupScreen, LibrarySectionView);
        ShowFooterStatus(SetupStatusText);
        _progressItems.Clear();
        foreach (var task in _setup.BuildTasks(selection)) _progressItems.Add(task);
        ProgressLogBox.Text = "";
        ProgressBackButton.IsEnabled = false;
        CompletionBanner.Visibility = Visibility.Collapsed;
        ProgressTitleText.Text = "Setting up your PC";
        ProgressStateText.Text = UiChrome.SetupPhaseLabel("active");
        ProgressCurrentText.Text = "Preparing tasks…";
        OverallProgressBar.Value = 0;
        ProgressPercentText.Text = "0%";
    }

    private void UpdateProgressStage(string id, string state, string detail)
    {
        Dispatcher.Invoke(() =>
        {
            var item = _progressItems.FirstOrDefault(x => x.Id == id);
            if (item is null) return;
            item.State = state;
            item.Detail = detail;
            item.Color = UiChrome.ProgressColor(state);
            ProgressCurrentText.Text = detail;
            var finished = _progressItems.Count(x => x.State is "Complete" or "Warning");
            var percent = _progressItems.Count == 0 ? 100 : (int)Math.Round(finished * 100d / _progressItems.Count);
            OverallProgressBar.Value = percent;
            ProgressPercentText.Text = percent + "%";
        });
    }

    private void AppendProgressLog(string message) => Dispatcher.Invoke(() =>
    {
        ProgressLogBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}\r\n");
        ProgressLogBox.ScrollToEnd();
    });

    private void ReadWorkerEvents(string path, ref long position, ref bool receivedDone, ref bool stopped)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        stream.Seek(position, SeekOrigin.Begin);
        using var reader = new StreamReader(stream);
        while (reader.ReadLine() is { } line)
        {
            if (line.Length == 0) continue;
            SetupWorkerEvent? message;
            try { message = JsonSerializer.Deserialize<SetupWorkerEvent>(line); }
            catch { continue; }
            if (message is null) continue;
            switch (message.Type)
            {
                case "stage": UpdateProgressStage(message.Id, message.State, message.Message); break;
                case "log": AppendProgressLog(message.Message); break;
                case "done": receivedDone = true; break;
                case "fatal": stopped = true; AppendProgressLog(message.Message); break;
            }
        }
        position = stream.Position;
    }

    private void FinishProgressUi(bool stopped)
    {
        if (stopped)
        {
            CompletionText.Text = "Setup stopped. Check the output log for details.";
            ProgressTitleText.Text = "Setup stopped";
            ProgressStateText.Text = UiChrome.SetupPhaseLabel("stopped");
        }
        else
        {
            var warnings = _progressItems.Count(x => x.State == "Warning");
            CompletionText.Text = warnings == 0 ? "All tasks finished." : $"{warnings} task(s) need a look — check the log.";
            ProgressTitleText.Text = "Setup complete";
            ProgressStateText.Text = UiChrome.SetupPhaseLabel(warnings == 0 ? "complete" : "review");
        }
        CompletionBanner.Visibility = Visibility.Visible;
        ProgressBackButton.IsEnabled = true;
    }

    private void ProgressBack_Click(object sender, RoutedEventArgs e)
    {
        ShowSetup();
        UpdateSetupSummary();
    }
}
