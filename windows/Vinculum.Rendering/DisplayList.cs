// The decoded VDL1 display list — the Vinculum counterpart of Kotlin's
// ai.vinc.VinculumWire model. Pure C#, no SkiaSharp, so it's testable without a
// graphics stack. Colors are 8-bit ARGB packed into a uint (Android/SkiaSharp
// convention); the renderer converts to SKColor.
namespace Vinculum.Rendering;

public enum SegOp : byte { Move = 0, Line = 1, Quad = 2, Cubic = 3, Close = 4 }

/// A path segment. Pts layout: move/line = [x,y]; quad = [endX,endY, ctrlX,ctrlY]
/// (endpoint FIRST, per the wire); cubic = [endX,endY, c1x,c1y, c2x,c2y]; close = [].
public readonly record struct Seg(SegOp Op, float[] Pts);

public abstract record Op;
public sealed record FillPath(IReadOnlyList<Seg> Subpaths, uint Color) : Op;
public sealed record FillRect(float X, float Y, float W, float H, uint Color) : Op;
public sealed record StrokePath(IReadOnlyList<Seg> Path, float Width, byte Cap, byte Join, uint Color) : Op;

public sealed record DisplayList(float Width, float Ascent, float Descent, IReadOnlyList<Op> Ops)
{
    public float Height => Ascent + Descent;
}
