using SkiaSharp;
using Vinculum.Rendering;
using Xunit;

namespace Vinculum.Rendering.Tests;

/// C# cross-language conformance for the VDL1 wire format — the third decoder
/// (Swift, Kotlin, C#) checked against the SAME committed fixture, so a fourth
/// platform can't drift the contract. Mirrors ai.vinc.VinculumWireConformance.
public class ConformanceTests
{
    static byte[] Fixture() =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "displaylist-wire-v1.bin"));

    [Fact]
    public void DecodesCommittedFixtureToCanonicalList()
    {
        var dl = VinculumWire.Decode(Fixture());
        Assert.NotNull(dl);
        Assert.Equal(10f, dl!.Width, 3);
        Assert.Equal(8f, dl.Ascent, 3);
        Assert.Equal(2f, dl.Descent, 3);
        Assert.Equal(3, dl.Ops.Count);

        // op0: fillRect (1,2,6,0.5), opaque black.
        var r = Assert.IsType<FillRect>(dl.Ops[0]);
        Assert.Equal((1f, 2f, 6f, 0.5f), (r.X, r.Y, r.W, r.H));
        Assert.Equal(0xFF000000u, r.Color);

        // op1: fillPath, opaque red, 5 segs incl. quad/cubic (endpoint-first).
        var fp = Assert.IsType<FillPath>(dl.Ops[1]);
        Assert.Equal(0xFFFF0000u, fp.Color);
        Assert.Equal(5, fp.Subpaths.Count);
        Assert.Equal(SegOp.Move, fp.Subpaths[0].Op);
        Assert.Equal(new[] { 0f, 0f }, fp.Subpaths[0].Pts);
        Assert.Equal(SegOp.Quad, fp.Subpaths[2].Op);
        Assert.Equal(new[] { 2f, 0f, 1.5f, 0.5f }, fp.Subpaths[2].Pts);         // endpoint, control
        Assert.Equal(SegOp.Cubic, fp.Subpaths[3].Op);
        Assert.Equal(new[] { 3f, 0f, 2.2f, 0.2f, 2.8f, -0.2f }, fp.Subpaths[3].Pts);
        Assert.Equal(SegOp.Close, fp.Subpaths[4].Op);

        // op2: strokePath, width 1.5, round cap / bevel join, color 336699.
        var sp = Assert.IsType<StrokePath>(dl.Ops[2]);
        Assert.Equal(1.5f, sp.Width, 3);
        Assert.Equal(1, sp.Cap);
        Assert.Equal(2, sp.Join);
        Assert.Equal(0xFF336699u, sp.Color);
        Assert.Equal(2, sp.Path.Count);
    }

    [Theory]
    [InlineData(new byte[0])]                                   // empty
    [InlineData(new byte[] { (byte)'X', (byte)'X', (byte)'X', (byte)'X' })]   // wrong magic
    public void MalformedReturnsNullNotThrow(byte[] bad) => Assert.Null(VinculumWire.Decode(bad));

    [Fact]
    public void TruncatedAndForgedCountReturnNull()
    {
        var good = Fixture();
        Assert.Null(VinculumWire.Decode(good[..^3]));           // truncated tail
        // magic + 3 f32 zeros + a ~2.1B opCount must not over-allocate.
        var forged = new byte[] { (byte)'V', (byte)'D', (byte)'L', (byte)'1',
                                  0,0,0,0, 0,0,0,0, 0,0,0,0, 0xFF,0xFF,0xFF,0x7F };
        Assert.Null(VinculumWire.Decode(forged));
    }

    [Fact]
    public void RendersToBitmapWithoutThrowing()
    {
        var dl = VinculumWire.Decode(Fixture())!;
        using var bmp = SceneRenderer.ToBitmap(dl, pad: 4f, background: SKColors.White);
        Assert.True(bmp.Width > 0 && bmp.Height > 0);
        // Something was painted: not every pixel is the white background.
        bool anyInk = false;
        for (int y = 0; y < bmp.Height && !anyInk; y++)
            for (int x = 0; x < bmp.Width; x++)
                if (bmp.GetPixel(x, y) != SKColors.White) { anyInk = true; break; }
        Assert.True(anyInk, "the SkiaSharp render produced no ink");
    }
}
