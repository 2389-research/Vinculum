using Microsoft.UI.Xaml;
using SkiaSharp;
using SkiaSharp.Views.Windows;
using Vinculum.Rendering;
using Windows.Foundation;   // Size (WinUI uses Windows.Foundation.Size, not System.Windows.Size)
using WinColor = Windows.UI.Color;

namespace Vinculum.Windows.WinUI;

/// <summary>
/// A drop-in WinUI 3 control that renders a LaTeX math expression — the modern-stack twin of
/// the WPF <c>VinculumMathView</c>. Same proven seam (native ABI → <c>VDL1</c> →
/// <see cref="VinculumWire"/> → <see cref="SceneRenderer"/>), same SkiaSharp engine as Android,
/// just painted on an <see cref="SKXamlCanvas"/> instead of a WPF <c>SKElement</c>.
///
/// Requires the native engine from the <c>Vinculum.Rendering</c> package at runtime; unsupported
/// LaTeX renders empty (the never-half-broken contract), never a crash.
/// </summary>
public class VinculumMathView : SKXamlCanvas
{
    public VinculumMathView()
    {
        PaintSurface += OnPaintSurface;
    }

    /// <summary>The LaTeX math to render (e.g. <c>x = \frac{-b}{2a}</c>).</summary>
    public static readonly DependencyProperty LatexProperty = DependencyProperty.Register(
        nameof(Latex), typeof(string), typeof(VinculumMathView), new PropertyMetadata("", OnRenderInputChanged));

    public string Latex
    {
        get => (string)GetValue(LatexProperty);
        set => SetValue(LatexProperty, value);
    }

    /// <summary>Display style (centered, full-size operators) vs inline. Default true.</summary>
    public static readonly DependencyProperty DisplayModeProperty = DependencyProperty.Register(
        nameof(DisplayMode), typeof(bool), typeof(VinculumMathView), new PropertyMetadata(true, OnRenderInputChanged));

    public bool DisplayMode
    {
        get => (bool)GetValue(DisplayModeProperty);
        set => SetValue(DisplayModeProperty, value);
    }

    /// <summary>Base point size the equation is laid out at. Default 17 (matches VinculumLabel).</summary>
    public static readonly DependencyProperty BaseSizeProperty = DependencyProperty.Register(
        nameof(BaseSize), typeof(double), typeof(VinculumMathView), new PropertyMetadata(17.0, OnRenderInputChanged));

    public double BaseSize
    {
        get => (double)GetValue(BaseSizeProperty);
        set => SetValue(BaseSizeProperty, value);
    }

    /// <summary>Ink color for the math (the analog of VinculumLabel.textColor). Default black.
    /// Set it to the theme foreground for light/dark. Repaints only.</summary>
    public static readonly DependencyProperty InkProperty = DependencyProperty.Register(
        nameof(Ink), typeof(WinColor), typeof(VinculumMathView),
        new PropertyMetadata(Microsoft.UI.Colors.Black, OnInkChanged));

    public WinColor Ink
    {
        get => (WinColor)GetValue(InkProperty);
        set => SetValue(InkProperty, value);
    }

    const float Pad = 4f;

    DisplayList? _list;
    bool _dirty = true;

    static void OnRenderInputChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var v = (VinculumMathView)d;
        v._dirty = true;
        v.InvalidateMeasure();
        v.Invalidate();   // SKXamlCanvas: request a repaint
    }

    static void OnInkChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        => ((VinculumMathView)d).Invalidate();

    void EnsureList()
    {
        if (!_dirty) return;
        _dirty = false;
        _list = string.IsNullOrEmpty(Latex) ? null : VinculumNative.Render(Latex, DisplayMode, BaseSize);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        EnsureList();
        if (_list is null) return new Size(0, 0);
        return new Size(_list.Width + Pad * 2, _list.Height + Pad * 2);
    }

    void OnPaintSurface(object? sender, SKPaintSurfaceEventArgs e)
    {
        var canvas = e.Surface.Canvas;
        canvas.Clear(SKColors.Transparent);
        EnsureList();
        if (_list is null) return;

        // SKXamlCanvas gives a pixel surface; the control lays out in DIPs. Scale so the
        // DIP-sized display list fills the pixel surface 1:1 in DIPs.
        float scale = (float)(e.Info.Width / Math.Max(1.0, ActualWidth));
        canvas.Scale(scale);

        var ink = new SKColor(Ink.R, Ink.G, Ink.B, Ink.A);
        SceneRenderer.Draw(canvas, _list, Pad, ink);
    }
}
