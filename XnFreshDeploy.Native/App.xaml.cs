using System.IO;
using System.Windows;

namespace XnFreshDeploy;

public partial class App : Application
{
    private async void Application_Startup(object sender, StartupEventArgs e)
    {
        CrashLogger.Install(this);

        if (e.Args.Length >= 3 && e.Args[0].Equals("--setup-worker", StringComparison.OrdinalIgnoreCase))
        {
            var exitCode = await SetupWorkerCoordinator.RunWorkerAsync(e.Args[1], e.Args[2]);
            Shutdown(exitCode);
            return;
        }
        if (e.Args.Contains("--integration-test", StringComparer.OrdinalIgnoreCase))
        {
            try { await NativeIntegrationTest.RunAsync(); Shutdown(0); }
            catch (Exception ex)
            {
                try { File.WriteAllText(Path.Combine(AppPaths.BaseDirectory, "integration-error.txt"), ex.ToString()); } catch { }
                Shutdown(2);
            }
            return;
        }
        if (e.Args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                AppPaths.EnsurePortableLayout();
                var data = new DataService();
                _ = data.LoadConfig();
                _ = data.LoadProfiles();
                _ = CommandCatalog.ToCommands(CommandCatalog.Create());
                Shutdown(0);
            }
            catch { Shutdown(1); }
            return;
        }
        var splash = new SplashWindow();
        splash.Show();
        var window = new MainWindow(e.Args);
        MainWindow = window;
        window.ContentRendered += (_, _) =>
        {
            splash.Close();
            window.Activate();
        };
        window.Show();
    }
}
