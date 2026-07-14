using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace XnFreshDeploy;

internal static class UiChrome
{
    public const string Accent = "#D4845A";
    public const string Success = "#5EAD7A";
    public const string Warning = "#D4A84B";
    public const string Danger = "#D45D68";
    public const string Muted = "#8E8E96";

    public static void SetActiveNav(Button active, Button profiles, Button library, Button setup)
    {
        foreach (var button in new[] { profiles, library, setup })
        {
            var isActive = ReferenceEquals(button, active);
            if (isActive) button.Tag = "active";
            else button.ClearValue(Button.TagProperty);
            button.FontWeight = isActive ? FontWeights.SemiBold : FontWeights.Normal;
        }
    }

    public static void ShowScreen(FrameworkElement target, params FrameworkElement[] hide)
    {
        foreach (var screen in hide)
        {
            screen.Visibility = Visibility.Collapsed;
            screen.BeginAnimation(UIElement.OpacityProperty, null);
        }

        target.Opacity = 0;
        target.Visibility = Visibility.Visible;
        var fade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        target.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    public static void Pulse(FrameworkElement element)
    {
        if (element.RenderTransform is not ScaleTransform transform)
        {
            transform = new ScaleTransform(1, 1);
            element.RenderTransform = transform;
            element.RenderTransformOrigin = new Point(0.5, 0.5);
        }

        var animation = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(280) };
        animation.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.Zero)));
        animation.KeyFrames.Add(new EasingDoubleKeyFrame(1.03, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(140))) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } });
        animation.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(280))) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn } });
        transform.BeginAnimation(ScaleTransform.ScaleXProperty, animation);
        transform.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
    }

    public static string ReadinessColor(string readiness) => readiness switch
    {
        "Ready" => Success,
        _ when readiness.StartsWith("Ready", StringComparison.OrdinalIgnoreCase) => Success,
        _ when readiness.StartsWith("Online", StringComparison.OrdinalIgnoreCase) => Success,
        _ when readiness.Contains("Close", StringComparison.OrdinalIgnoreCase) => Warning,
        _ when readiness.Contains("Checking", StringComparison.OrdinalIgnoreCase) => Muted,
        _ => Danger
    };

    public static string ProgressColor(string state) => state switch
    {
        "Running" => Accent,
        "Complete" => Success,
        "Warning" => Warning,
        _ => "#5A5A62"
    };

    public static string ProgressLabel(string state) => state switch
    {
        "Running" => "Running",
        "Complete" => "Done",
        "Warning" => "Review",
        _ => "Waiting"
    };

    public static string SetupPhaseLabel(string phase) => phase switch
    {
        "waiting" => "Waiting for permission",
        "active" => "In progress",
        "stopped" => "Stopped",
        "complete" => "Finished",
        "review" => "Needs review",
        _ => phase
    };
}
