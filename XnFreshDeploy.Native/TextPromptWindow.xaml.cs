using System.Windows;

namespace XnFreshDeploy;

public partial class TextPromptWindow : Window
{
    public string Value => ValueBox.Text.Trim();

    public TextPromptWindow(string title, string label, string value)
    {
        InitializeComponent();
        Title = title + " · Xn Fresh Deploy";
        PromptTitle.Text = title;
        PromptLabel.Text = label;
        ValueBox.Text = value;
        Loaded += (_, _) => { ValueBox.Focus(); ValueBox.SelectAll(); };
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (Value.Length == 0) return;
        DialogResult = true;
    }
}
