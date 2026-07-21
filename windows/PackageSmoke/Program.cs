using Vinculum.Rendering;

// Exercises the packaged native path end-to-end from a clean consumer: the ABI loads
// (proving the bundled Swift runtime + FreeType satisfy VinculumAndroid.dll), fonts
// self-provision from the embedded resources, and a real equation renders to a display
// list. Non-zero exit = the package is not self-contained. Run by CI with the Swift
// toolchain scrubbed from PATH.

if (VinculumNative.AbiVersion() != 1)
{
    Console.Error.WriteLine("FAIL: unexpected ABI version");
    return 2;
}

var dl = VinculumNative.Render(@"x = \frac{-b}{2a}", display: true, baseSize: 24);
if (dl is null || dl.Ops.Count == 0)
{
    Console.Error.WriteLine("FAIL: native render produced no display list");
    return 3;
}

Console.WriteLine($"OK — packaged native render works: ops={dl.Ops.Count} width={dl.Width:F1}");
return 0;
