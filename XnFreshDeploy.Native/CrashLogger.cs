using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace XnFreshDeploy;

public static class CrashLogger
{
    private static string LogsDirectory => Path.Combine(AppPaths.BaseDirectory, "logs");

    public static void Install(Application app)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            Write("fatal", args.ExceptionObject as Exception ?? new Exception(args.ExceptionObject?.ToString() ?? "Unknown fatal error"));

        app.DispatcherUnhandledException += (_, args) =>
        {
            Write("ui", args.Exception);
            args.Handled = true;
            MessageBox.Show(
                $"Something went wrong. Details were saved to:\n{LatestLogPath()}\n\n{args.Exception.Message}",
                "Xn Fresh Deploy",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        };

        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Write("task", args.Exception);
            args.SetObserved();
        };
    }

    public static void Write(string kind, Exception ex)
    {
        try
        {
            Directory.CreateDirectory(LogsDirectory);
            var file = Path.Combine(LogsDirectory, $"crash-{DateTime.Now:yyyy-MM-dd}.log");
            var entry = $"[{DateTime.Now:O}] [{kind}]\r\n{ex}\r\n\r\n";
            File.AppendAllText(file, entry);
        }
        catch { }
    }

    public static string LatestLogPath()
    {
        if (!Directory.Exists(LogsDirectory)) return LogsDirectory;
        var latest = Directory.GetFiles(LogsDirectory, "crash-*.log").OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
        return latest ?? LogsDirectory;
    }
}
