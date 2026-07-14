using System.Diagnostics;
using System.IO;
using System.Windows;

namespace XnFreshDeploy;

public partial class AboutWindow : Window
{
    private readonly Func<Task<UpdateInfo?>> _checkUpdates;

    public AboutWindow(Func<Task<UpdateInfo?>> checkUpdates)
    {
        _checkUpdates = checkUpdates;
        InitializeComponent();
        VersionLabel.Text = $"Version {AppVersion.Display}";
        StatusLabel.Text = "Ready.";
        WindowChrome.ApplyDarkTitleBar(this);
    }

    private async void CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        StatusLabel.Text = "Checking GitHub for updates…";
        var update = await _checkUpdates();
        StatusLabel.Text = update is null
            ? "You're on the latest published release."
            : $"Update {update.Version} is available. Open GitHub releases to download it.";
    }

    private void OpenAppFolder_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{AppPaths.BaseDirectory}\"") { UseShellExecute = true });

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        var logs = Path.Combine(AppPaths.BaseDirectory, "logs");
        Directory.CreateDirectory(logs);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{logs}\"") { UseShellExecute = true });
    }

    private void OpenReleases_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo($"https://github.com/{UpdateChecker.GitHubRepo}/releases") { UseShellExecute = true });

    private void ReportIssue_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo($"https://github.com/{UpdateChecker.GitHubRepo}/issues/new/choose") { UseShellExecute = true });

    private void ShowGuide_Click(object sender, RoutedEventArgs e)
    {
        var guide = new FirstRunWindow { Owner = this };
        guide.ShowDialog();
    }
}
