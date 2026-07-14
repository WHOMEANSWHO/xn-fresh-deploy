using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace XnFreshDeploy;

public enum ToastKind
{
    Info,
    Success,
    Warning,
    Error
}

public sealed class ToastHost
{
    private readonly Panel _panel;
    private readonly Dispatcher _dispatcher;

    public ToastHost(Panel panel)
    {
        _panel = panel;
        _dispatcher = panel.Dispatcher;
    }

    public void Show(string message, ToastKind kind = ToastKind.Info, int milliseconds = 4200)
    {
        _dispatcher.Invoke(() =>
        {
            var (background, border, foreground) = kind switch
            {
                ToastKind.Success => ("#1E2D24", "#2A4A38", "#5EAD7A"),
                ToastKind.Warning => ("#2E2818", "#4A3E20", "#D4A84B"),
                ToastKind.Error => ("#2E1A1D", "#5A3038", "#D45D68"),
                _ => ("#222226", "#34343A", "#ECECEF")
            };

            var toast = new Border
            {
                Background = (Brush)new BrushConverter().ConvertFromString(background)!,
                BorderBrush = (Brush)new BrushConverter().ConvertFromString(border)!,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(14, 10, 14, 10),
                Margin = new Thickness(0, 0, 0, 8),
                MaxWidth = 420,
                Opacity = 0,
                Child = new TextBlock
                {
                    Text = message,
                    Foreground = (Brush)new BrushConverter().ConvertFromString(foreground)!,
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 12.5
                }
            };

            _panel.Children.Insert(0, toast);
            toast.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));

            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(180));
                fade.Completed += (_, _) => _panel.Children.Remove(toast);
                toast.BeginAnimation(UIElement.OpacityProperty, fade);
            };
            timer.Start();
        });
    }
}
