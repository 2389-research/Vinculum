using SkiaSharp;
using Vinculum.Rendering;
using Xunit;

namespace Vinculum.Rendering.Tests;

/// End-to-end conformance for the native P/Invoke bridge (MermaidKit-pattern piece 2):
/// the Swift @_cdecl C ABI, built as VinculumAndroid.dll and driven from .NET.
///
/// Gating mirrors Android's MMK_NATIVE / the project's "no claim without a verified
/// artifact" rule: the DLL only exists where the `native DLL + P/Invoke (Windows)` CI
/// job built it (it needs vcpkg FreeType). So —
///   • With VINC_NATIVE=1 (that CI job) these are REQUIRED — a missing/broken DLL fails.
///   • Otherwise (the ubuntu `dotnet` job, local dev without the DLL) they soft-skip,
///     so the pure-managed decoder/renderer suite still runs everywhere.
public class NativeBridgeTests
{
    static bool NativeRequired =>
        Environment.GetEnvironmentVariable("VINC_NATIVE") == "1";

    /// Skip.If unless the native path is required OR actually present — so the suite is
    /// green on managed-only hosts but can't silently pass when the DLL was expected.
    static bool Runnable => NativeRequired || VinculumNative.IsAvailable();

    [SkippableFact]
    public void AbiVersionIsOne()
    {
        Skip.IfNot(Runnable, "native VinculumAndroid DLL not present (set VINC_NATIVE=1 to require it)");
        Assert.Equal(1, VinculumNative.AbiVersion());
    }

    [SkippableFact]
    public void RendersSupportedLatexToADecodableDisplayList()
    {
        Skip.IfNot(Runnable, "native VinculumAndroid DLL not present");
        PointAtBundledFonts();

        // The native ABI renders; the SAME VinculumWire.Decode the fixture tests use decodes.
        var dl = VinculumNative.Render(@"x = \frac{-b}{2a}", display: true, baseSize: 24);
        Assert.NotNull(dl);
        Assert.True(dl!.Width > 0);
        Assert.NotEmpty(dl.Ops);
        // A fraction's bar survives the whole pipeline as a fillRect.
        Assert.Contains(dl.Ops, op => op is FillRect);

        // And it paints ink through SkiaSharp — the full native→wire→Skia loop.
        using var bmp = SceneRenderer.ToBitmap(dl, pad: 4f, background: SKColors.White);
        bool anyInk = false;
        for (int y = 0; y < bmp.Height && !anyInk; y++)
            for (int x = 0; x < bmp.Width; x++)
                if (bmp.GetPixel(x, y) != SKColors.White) { anyInk = true; break; }
        Assert.True(anyInk, "native-rendered equation produced no ink");
    }

    [SkippableFact]
    public void UnsupportedLatexReturnsNullAcrossTheBoundary()
    {
        Skip.IfNot(Runnable, "native VinculumAndroid DLL not present");
        PointAtBundledFonts();
        // The never-half-broken contract crosses P/Invoke intact.
        Assert.Null(VinculumNative.RenderWire(@"\notacommand{x}", display: true, baseSize: 24));
        Assert.Null(VinculumNative.RenderWire("", display: true, baseSize: 24));
    }

    /// The native ABI and the committed fixture must agree on the wire GRAMMAR: bytes the
    /// DLL emits decode with the same C# decoder that decodes the cross-language fixture.
    [SkippableFact]
    public void NativeWireDecodesWithTheSharedDecoder()
    {
        Skip.IfNot(Runnable, "native VinculumAndroid DLL not present");
        PointAtBundledFonts();
        var wire = VinculumNative.RenderWire(@"\sqrt{x^2 + 1}", display: true, baseSize: 24);
        Assert.NotNull(wire);
        Assert.Equal(new[] { (byte)'V', (byte)'D', (byte)'L', (byte)'1' }, wire![..4]);
        Assert.NotNull(VinculumWire.Decode(wire));   // same decoder as ConformanceTests
    }

    // Point the ABI at the bundled .otf math fonts — Bundle.module traps outside a SwiftPM
    // bundle (same reason Android stages them). The CI job sets VINC_FONT_DIR; a source
    // checkout falls back to Sources/VinculumRender/Resources.
    static void PointAtBundledFonts()
    {
        var env = Environment.GetEnvironmentVariable("VINC_FONT_DIR");
        if (!string.IsNullOrEmpty(env) && Directory.Exists(env))
        {
            VinculumNative.SetFontDirectory(env);
            return;
        }
        // bin/Release/net8.0 → up 5 → repo root → Sources/VinculumRender/Resources.
        var repo = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "Sources", "VinculumRender", "Resources"));
        if (Directory.Exists(repo)) VinculumNative.SetFontDirectory(repo);
    }
}
