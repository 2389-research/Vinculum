using SkiaSharp;

namespace Vinculum.Rendering;

/// Draws a decoded VDL1 DisplayList on a SkiaSharp SKCanvas — the Windows/.NET
/// renderer. SkiaSharp (not Direct2D, not SVG) is a deliberate choice: it's the
/// same Skia engine the Android Canvas uses, so Windows is a fidelity match for
/// Android by construction, and it runs headless (Linux/macOS/Windows) so it's
/// testable everywhere. The display list carries glyphs as filled outlines, so no
/// font is needed. Scene coords are y-up, baseline origin; the single y-flip is here.
public static class SceneRenderer
{
    public static SKBitmap ToBitmap(DisplayList list, float pad = 4f, SKColor? background = null)
    {
        int w = Math.Max(1, (int)Math.Ceiling(list.Width + pad * 2));
        int h = Math.Max(1, (int)Math.Ceiling(list.Height + pad * 2));
        var bmp = new SKBitmap(w, h);
        using var canvas = new SKCanvas(bmp);
        if (background is SKColor bg) canvas.Clear(bg);
        Draw(canvas, list, pad);
        return bmp;
    }

    public static void Draw(SKCanvas canvas, DisplayList list, float pad = 4f)
    {
        using var paint = new SKPaint { IsAntialias = true };
        canvas.Save();
        canvas.Translate(pad, pad + list.Ascent);   // origin -> baseline
        canvas.Scale(1, -1);                          // scene y-up -> canvas y-down
        foreach (var op in list.Ops)
        {
            switch (op)
            {
                case FillRect r:
                    paint.Style = SKPaintStyle.Fill; paint.Color = ToColor(r.Color);
                    canvas.DrawRect(r.X, r.Y, r.W, r.H, paint);
                    break;
                case FillPath fp:
                    paint.Style = SKPaintStyle.Fill; paint.Color = ToColor(fp.Color);
                    using (var path = BuildPath(fp.Subpaths)) canvas.DrawPath(path, paint);
                    break;
                case StrokePath sp:
                    paint.Style = SKPaintStyle.Stroke;
                    paint.Color = ToColor(sp.Color);
                    paint.StrokeWidth = sp.Width;
                    paint.StrokeCap = sp.Cap switch { 1 => SKStrokeCap.Round, 2 => SKStrokeCap.Square, _ => SKStrokeCap.Butt };
                    paint.StrokeJoin = sp.Join switch { 1 => SKStrokeJoin.Round, 2 => SKStrokeJoin.Bevel, _ => SKStrokeJoin.Miter };
                    using (var path = BuildPath(sp.Path)) canvas.DrawPath(path, paint);
                    break;
            }
        }
        canvas.Restore();
    }

    static SKColor ToColor(uint argb) =>
        new((byte)(argb >> 16), (byte)(argb >> 8), (byte)argb, (byte)(argb >> 24));

    static SKPath BuildPath(IReadOnlyList<Seg> segs)
    {
        var p = new SKPath();
        foreach (var s in segs)
        {
            switch (s.Op)
            {
                case SegOp.Move: p.MoveTo(s.Pts[0], s.Pts[1]); break;
                case SegOp.Line: p.LineTo(s.Pts[0], s.Pts[1]); break;
                case SegOp.Quad: p.QuadTo(s.Pts[2], s.Pts[3], s.Pts[0], s.Pts[1]); break;         // ctrl, endpoint
                case SegOp.Cubic: p.CubicTo(s.Pts[2], s.Pts[3], s.Pts[4], s.Pts[5], s.Pts[0], s.Pts[1]); break;
                case SegOp.Close: p.Close(); break;
            }
        }
        return p;
    }
}
