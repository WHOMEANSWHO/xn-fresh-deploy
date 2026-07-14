using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace XnFreshDeploy;

public static class AppVersion
{
    public static string Full
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version is null ? "4.1.1.0" : version.ToString();
        }
    }

    public static string Display
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version is null ? "4.1.1" : $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }
}

public static class SingleInstance
{
    private const string MutexName = "Global\\XnFreshDeploy.SingleInstance";
    private static Mutex? _mutex;

    public static bool TryStart(string[] args)
    {
        _mutex = new Mutex(true, MutexName, out var created);
        if (created) return true;

        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(Environment.ProcessPath ?? "XnFreshDeploy")))
        {
            if (process.Id == Environment.ProcessId) continue;
            if (process.MainWindowHandle == IntPtr.Zero) continue;
            NativeMethods.SetForegroundWindow(process.MainWindowHandle);
            NativeMethods.ShowWindow(process.MainWindowHandle, NativeMethods.SW_RESTORE);
            break;
        }

        if (args.Length >= 2 && args[0].Equals("--play", StringComparison.OrdinalIgnoreCase))
            MessageBox.Show($"Xn Fresh Deploy is already running.\nSwitch to the open window and use Play on \"{args[1]}\".", "Already open", MessageBoxButton.OK, MessageBoxImage.Information);
        else
            MessageBox.Show("Xn Fresh Deploy is already running.", "Already open", MessageBoxButton.OK, MessageBoxImage.Information);

        return false;
    }

    private static class NativeMethods
    {
        internal const int SW_RESTORE = 9;

        [DllImport("user32.dll")]
        internal static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}

public static class WindowChrome
{
    private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public static void ApplyDarkTitleBar(Window window)
    {
        window.SourceInitialized += (_, _) =>
        {
            try
            {
                var useDark = 1;
                _ = DwmSetWindowAttribute(new WindowInteropHelper(window).Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, ref useDark, sizeof(int));
            }
            catch { }
        };
    }
}
