using Microsoft.Win32;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace XnFreshDeploy;

public partial class LibrarySection : UserControl
{
    private readonly LibraryService _library = new();
    private DataService? _data;
    private IList<ServerProfile>? _profiles;

    public LibrarySection() => InitializeComponent();

    public void Initialize(DataService data, IList<ServerProfile> profiles)
    {
        _data = data;
        _profiles = profiles;
        RefreshItems();
    }

    public void RefreshItems()
    {
        if (_profiles is null) return;
        SoundpackList.ItemsSource = _library.GetEntries(LibraryKind.Soundpack, _profiles);
        ReShadeList.ItemsSource = _library.GetEntries(LibraryKind.ReShade, _profiles);
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        var kind = KindFromTag((sender as FrameworkElement)?.Tag);
        var choice = MessageBox.Show(HostWindow, "Choose the source type.\n\nYes: folder\nNo: ZIP archive", "Import pack", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (choice == MessageBoxResult.Cancel) return;
        IReadOnlyList<string> sources = [];
        if (choice == MessageBoxResult.Yes)
        {
            var dialog = new OpenFolderDialog { Title = $"Choose one or more {Display(kind)} folders", Multiselect = true };
            if (dialog.ShowDialog(HostWindow) == true) sources = dialog.FolderNames;
        }
        else
        {
            var dialog = new OpenFileDialog { Title = $"Choose one or more {Display(kind)} ZIPs", Filter = "ZIP archives (*.zip)|*.zip", Multiselect = true };
            if (dialog.ShowDialog(HostWindow) == true) sources = dialog.FileNames;
        }
        if (sources.Count > 0) await ImportSourcesAsync(sources, kind);
    }

    private async void Pack_Drop(object sender, DragEventArgs e)
    {
        if (sender is Border zone) SetDragHighlight(zone, false);
        if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
        var paths = (string[])e.Data.GetData(DataFormats.FileDrop);
        await ImportSourcesAsync(paths, KindFromTag((sender as FrameworkElement)?.Tag));
    }

    private void Pack_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void Pack_DragEnter(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop) && sender is Border zone)
            SetDragHighlight(zone, true);
    }

    private void Pack_DragLeave(object sender, DragEventArgs e)
    {
        if (sender is Border zone)
            SetDragHighlight(zone, false);
    }

    private static void SetDragHighlight(Border zone, bool active)
    {
        zone.BorderBrush = (Brush)Application.Current.FindResource(active ? "AccentBrush" : "EdgeBrush");
        zone.Background = (Brush)Application.Current.FindResource(active ? "AccentSoftBrush" : "SurfaceBrush");
    }

    private async Task ImportSourcesAsync(IReadOnlyList<string> selectedSources, LibraryKind kind)
    {
        try
        {
            var sources = selectedSources.Where(path => !string.IsNullOrWhiteSpace(path)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (sources.Count == 1 && Directory.Exists(sources[0]))
            {
                var subfolders = Directory.EnumerateDirectories(sources[0]).Where(folder => !new DirectoryInfo(folder).Attributes.HasFlag(FileAttributes.ReparsePoint)).ToList();
                if (subfolders.Count >= 2)
                {
                    var split = MessageBox.Show(HostWindow,
                        $"'{new DirectoryInfo(sources[0]).Name}' contains {subfolders.Count} direct subfolders.\n\nImport every direct subfolder as a separate {Display(kind)}?\n\nYes: import {subfolders.Count} separate packs\nNo: import the selected parent as one pack",
                        "Parent folder detected", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
                    if (split == MessageBoxResult.Cancel) { StatusText.Text = "Import cancelled."; return; }
                    if (split == MessageBoxResult.Yes) sources = subfolders;
                }
            }
            if (sources.Count == 0) return;

            StatusText.Text = $"Inspecting {sources.Count} import source{(sources.Count == 1 ? "" : "s")}…";
            var reviews = new List<(string Source, string Name, ImportPreview Preview)>();
            foreach (var source in sources)
            {
                var preview = await _library.PreviewAsync(source);
                var name = Directory.Exists(source) ? new DirectoryInfo(source).Name : Path.GetFileNameWithoutExtension(source);
                reviews.Add((source, name, preview));
            }
            var risky = reviews.SelectMany(item => item.Preview.RiskyFiles.Select(file => $"{item.Name}: {file}")).ToList();
            var types = reviews.SelectMany(item => item.Preview.FileTypes).Distinct(StringComparer.OrdinalIgnoreCase).Take(18).ToList();
            var names = string.Join("\n", reviews.Take(16).Select(item => $"• {item.Name} — {item.Preview.FileCount:N0} files"));
            if (reviews.Count > 16) names += $"\n• …and {reviews.Count - 16} more";
            var warning = risky.Count == 0 ? "No executable, script, or DLL files detected." : $"Warning: {risky.Count} executable, script, or DLL file(s) detected:\n{string.Join("\n", risky.Take(12))}";
            var icon = risky.Count == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning;
            var answer = MessageBox.Show(HostWindow,
                $"Import {reviews.Count} {DisplayPlural(kind, reviews.Count)}?\n\n{names}\n\nTotal files: {reviews.Sum(item => item.Preview.FileCount):N0}\nTypes: {(types.Count == 0 ? "No extensions" : string.Join(", ", types))}\n\n{warning}\n\nNo files will be run. Continue?",
                "Review pack import", MessageBoxButton.YesNo, icon);
            if (answer != MessageBoxResult.Yes) { StatusText.Text = "Import cancelled."; return; }

            var rename = MessageBox.Show(HostWindow,
                reviews.Count == 1
                    ? $"The {Display(kind)} will be named '{reviews[0].Name}'.\n\nWould you like to rename it before the import finishes?"
                    : $"The {reviews.Count} detected folder/ZIP names will be used as pack names.\n\nWould you like to review and rename them before the batch finishes?",
                "Confirm pack names", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            if (rename == MessageBoxResult.Cancel) { StatusText.Text = "Import cancelled."; return; }
            if (rename == MessageBoxResult.Yes)
            {
                for (var index = 0; index < reviews.Count; index++)
                {
                    var prompt = new TextPromptWindow($"Name imported pack {index + 1} of {reviews.Count}", "Pack name", reviews[index].Name) { Owner = HostWindow };
                    if (prompt.ShowDialog() != true) { StatusText.Text = "Import cancelled."; return; }
                    reviews[index] = (reviews[index].Source, prompt.Value, reviews[index].Preview);
                }
            }

            var imported = new List<string>();
            try
            {
                foreach (var item in reviews)
                {
                    StatusText.Text = $"Importing {item.Name} ({imported.Count + 1} of {reviews.Count})…";
                    imported.Add(await _library.ImportAsync(item.Source, kind, item.Name));
                }
            }
            catch
            {
                foreach (var name in imported.AsEnumerable().Reverse()) try { _library.Delete(kind, name); } catch { }
                throw;
            }
            RefreshItems();
            StatusText.Text = $"Imported {imported.Count} {DisplayPlural(kind, imported.Count)}. Review complete; no files were executed.";
        }
        catch (Exception ex) { StatusText.Text = ex.Message; }
    }

    private void Rename_Click(object sender, RoutedEventArgs e)
    {
        if (_profiles is null || _data is null) return;
        var kind = KindFromTag((sender as FrameworkElement)?.Tag);
        var item = Selected(kind);
        if (item is null) { StatusText.Text = $"Select a {Display(kind)} first."; return; }
        var prompt = new TextPromptWindow("Rename library item", "New name", item.Name) { Owner = HostWindow };
        if (prompt.ShowDialog() != true) return;
        try
        {
            var name = _library.Rename(kind, item.Name, prompt.Value, _profiles);
            _data.SaveProfiles(_profiles);
            RefreshItems();
            StatusText.Text = $"Renamed {item.Name} to {name}; linked profiles were updated.";
        }
        catch (Exception ex) { StatusText.Text = ex.Message; }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        var kind = KindFromTag((sender as FrameworkElement)?.Tag);
        var item = Selected(kind);
        if (item is null) { StatusText.Text = $"Select a {Display(kind)} first."; return; }
        var warning = item.Usage.StartsWith("Used by", StringComparison.OrdinalIgnoreCase) ? $"\n\nWarning: {item.Usage}. Those profiles will show Pack missing." : "";
        if (MessageBox.Show(HostWindow, $"Delete '{item.Name}' and its {item.FileCount:N0} files?{warning}", "Delete library item", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try { _library.Delete(kind, item.Name); RefreshItems(); StatusText.Text = $"Deleted {item.Name}."; }
        catch (Exception ex) { StatusText.Text = ex.Message; }
    }

    private Window HostWindow => Window.GetWindow(this);
    private static LibraryKind KindFromTag(object? tag) => tag?.ToString() == "ReShade" ? LibraryKind.ReShade : LibraryKind.Soundpack;
    private LibraryEntry? Selected(LibraryKind kind) => (kind == LibraryKind.Soundpack ? SoundpackList.SelectedItem : ReShadeList.SelectedItem) as LibraryEntry;
    private static string Display(LibraryKind kind) => kind == LibraryKind.Soundpack ? "soundpack" : "ReShade look";
    private static string DisplayPlural(LibraryKind kind, int count) => kind == LibraryKind.Soundpack ? (count == 1 ? "soundpack" : "soundpacks") : (count == 1 ? "ReShade look" : "ReShade looks");
    private void OpenFolders_Click(object sender, RoutedEventArgs e) => Process.Start(new ProcessStartInfo("explorer.exe", $"\"{AppPaths.LibraryDirectory}\"") { UseShellExecute = true });
}
