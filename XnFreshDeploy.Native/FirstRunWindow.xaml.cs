using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace XnFreshDeploy;

public partial class FirstRunWindow : Window
{
    private int _step;

    public FirstRunWindow()
    {
        InitializeComponent();
        UpdateStep();
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (_step > 0) _step--;
        UpdateStep();
    }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (_step < 2)
        {
            _step++;
            UpdateStep();
            return;
        }

        DialogResult = true;
    }

    private void UpdateStep()
    {
        Highlight(Step1Panel, _step == 0);
        Highlight(Step2Panel, _step == 1);
        Highlight(Step3Panel, _step == 2);
        BackButton.Visibility = _step == 0 ? Visibility.Collapsed : Visibility.Visible;
        NextButton.Content = _step == 2 ? "Get started" : "Next";
    }

    private static void Highlight(Border panel, bool active)
    {
        panel.Opacity = active ? 1 : 0.55;
        panel.Background = active
            ? (Brush)Application.Current.FindResource("AccentSoftBrush")
            : (Brush)Application.Current.FindResource("SurfaceBrush");
    }
}
