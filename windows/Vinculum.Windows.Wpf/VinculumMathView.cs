using System.Windows;
using System.Windows.Media;
using SkiaSharp;
using SkiaSharp.Views.Desktop;
using SkiaSharp.Views.WPF;
using Vinculum.Rendering;

namespace Vinculum.Windows.Wpf;

/// <summary>
/// A drop-in WPF control that renders a LaTeX math expression. Set <see cref="Latex"/> and it
/// paints — the Windows analog of Apple's <c>VinculumLabel</c> and the first drop-in control
/// outside Apple.
///
/// It rides the proven native seam: the <c>@_cdecl</c> C ABI renders the expression to
/// <c>VDL1</c> wire bytes (<see cref="VinculumNative"/>), the shared <see cref="VinculumWire"/>
/// decodes them, and <see cref="SceneRenderer"/> paints the display list on this control's
/// <see cref="SKElement"/> canvas — the same SkiaSharp engine as Android, so a Windows app and
/// an Android app render byte-for-byte alike.
///
/// Requires the native <c>VinculumAndroid.dll</c> (+ its FreeType deps) on the load path at
/// runtime; the NuGet package ships them as native assets. Unsupported LaTeX renders as empty
/// (the never-half-broken contract), never a crash.
/// </summary>
public class VinculumMathView : SKElement
{
    /// <summary>The LaTeX math to render (e.g. <c>x = \frac{-b}{2a}</c>).</summary>
    public static readonly DependencyProperty LatexProperty = DependencyProperty.Register(
        nameof(Latex), typeof(string), typeof(VinculumMathView),
        new FrameworkPropertyMetadata("", Remeasure));

    public string Latex
    {
        get => (string)GetValue(LatexProperty);
        set => SetValue(LatexProperty, value);
    }

    /// <summary>Display style (centered, full-size operators) vs inline. Default true.</summary>
    public static readonly DependencyProperty DisplayModeProperty = DependencyProperty.Register(
        nameof(DisplayMode), typeof(bool), typeof(VinculumMathView),
        new FrameworkPropertyMetadata(true, Remeasure));

    public bool DisplayMode
    {
        get => (bool)GetValue(DisplayModeProperty);
        set => SetValue(DisplayModeProperty, value);
    }

    /// <summary>Base point size the equation is laid out at. Default 17 (matches VinculumLabel).</summary>
    public static readonly DependencyProperty BaseSizeProperty = DependencyProperty.Register(
        nameof(BaseSize), typeof(double), typeof(VinculumMathView),
        new FrameworkPropertyMetadata(17.0, Remeasure));

    public double BaseSize
    {
        get => (double)GetValue(BaseSizeProperty);
        set => SetValue(BaseSizeProperty, value);
    }

    /// <summary>Ink color for the math (the analog of VinculumLabel.textColor). Default black.
    /// Set it to the theme foreground for light/dark. Repaints only — no relayout.</summary>
    public static readonly DependencyProperty InkProperty = DependencyProperty.Register(
        nameof(Ink), typeof(Color), typeof(VinculumMathView),
        new FrameworkPropertyMetadata(Colors.Black, Repaint));

    public Color Ink
    {
        get => (Color)GetValue(InkProperty);
        set => SetValue(InkProperty, value);
    }

    // Points of padding around the ink on every side.
    const float Pad = 4f;

    DisplayList? _list;
    bool _dirty = true;

    static void Remeasure(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var v = (VinculumMathView)d;
        v._dirty = true;
        v.InvalidateMeasure();
        v.InvalidateVisual();
    }

    static void Repaint(DependencyObject d, DependencyPropertyChangedEventArgs e)
        => ((VinculumMathView)d).InvalidateVisual();

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

    protected override void OnPaintSurface(SKPaintSurfaceEventArgs e)
    {
        var canvas = e.Surface.Canvas;
        canvas.Clear(SKColors.Transparent);
        EnsureList();
        if (_list is null) return;

        // The SKElement backing surface is in device pixels; WPF lays the control out in DIPs.
        // Scale so the equation's DIP-sized display list fills the pixel surface 1:1 in DIPs.
        float scale = (float)(e.Info.Width / Math.Max(1.0, ActualWidth));
        canvas.Scale(scale);

        var ink = new SKColor(Ink.R, Ink.G, Ink.B, Ink.A);
        SceneRenderer.Draw(canvas, _list, Pad, ink);
    }
}
