using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Vinculum.Rendering;

/// <summary>
/// P/Invoke bridge to the Swift <c>@_cdecl</c> C ABI, built as <c>VinculumAndroid.dll</c>
/// on Windows (the same dynamic product Android loads via JNI). This is MermaidKit-pattern
/// piece 2 — the native seam — and the deliberate contrast with Android: .NET calls the C
/// functions <b>directly with [DllImport]</b>, no JNI shim.
///
/// The four entry points mirror <c>ai.vinc.VinculumNative</c> (Kotlin) exactly. The wire
/// bytes this returns are the same <c>VDL1</c> format <see cref="VinculumWire.Decode"/>
/// already decodes — so the native path and the fixture path converge on one decoder.
///
/// Availability: the DLL is produced by the <c>native DLL + P/Invoke (Windows)</c> CI job
/// (it needs vcpkg FreeType). When the DLL is not on the load path these calls throw
/// <see cref="DllNotFoundException"/>; callers that must degrade gracefully should probe
/// with <see cref="IsAvailable"/> first.
/// </summary>
public static class VinculumNative
{
    // Matches the product name `VinculumAndroid` (type: .dynamic). The OS resolves
    // "VinculumAndroid" → VinculumAndroid.dll on Windows / libVinculumAndroid.so on Linux.
    private const string Lib = "VinculumAndroid";

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    private static extern int vinculum_abi_version();

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void vinculum_set_font_dir([MarshalAs(UnmanagedType.LPUTF8Str)] string? dir);

    // const char* latexPtr, int32 byteLen, int32 display, double baseSize, int32* outLen -> uint8*
    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr vinculum_render_displaylist(
        byte[] latexUtf8, int byteLen, int display, double baseSize, out int outLen);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    private static extern void vinculum_free(IntPtr ptr);

    /// <summary>The ABI version the loaded DLL exposes (currently 1). Doubles as a
    /// cheap "is the DLL loadable and its symbols resolvable" probe.</summary>
    public static int AbiVersion() => vinculum_abi_version();

    /// <summary>True if the native DLL loads and its exports resolve. Never throws.</summary>
    public static bool IsAvailable()
    {
        try { return vinculum_abi_version() == 1; }
        catch (DllNotFoundException) { return false; }
        catch (EntryPointNotFoundException) { return false; }
    }

    /// <summary>
    /// Points the ABI at a directory of bundled math <c>.otf</c> fonts, replacing the
    /// <c>Bundle.module</c> lookup (which traps outside a SwiftPM bundle — same reason the
    /// Android host stages fonts and calls this). Pass <c>null</c> to clear. Calling this
    /// suppresses the automatic embedded-font provisioning done on first render.
    /// </summary>
    public static void SetFontDirectory(string? directory)
    {
        lock (FontLock) { vinculum_set_font_dir(directory); _fontDirSet = true; }
    }

    static bool _fontDirSet;
    static readonly object FontLock = new();

    /// On first render, extract the math fonts embedded in this assembly to a temp dir and
    /// point the ABI at them — so a NuGet-consumed app needs no font files on disk and no
    /// setup call. No-op if the caller already set a font directory, or if no fonts are
    /// embedded (e.g. a source build that didn't link them — the ABI's default path applies).
    static void EnsureFonts()
    {
        if (_fontDirSet) return;
        lock (FontLock)
        {
            if (_fontDirSet) return;
            var asm = typeof(VinculumNative).Assembly;
            var fonts = asm.GetManifestResourceNames()
                           .Where(n => n.EndsWith(".otf", StringComparison.OrdinalIgnoreCase)).ToArray();
            if (fonts.Length == 0) { _fontDirSet = true; return; }   // nothing to provision
            var dir = Path.Combine(Path.GetTempPath(), "vinculum-fonts-" + (asm.GetName().Version?.ToString() ?? "0"));
            Directory.CreateDirectory(dir);
            foreach (var res in fonts)
            {
                var name = res[(res.LastIndexOf('/') + 1)..];
                var path = Path.Combine(dir, name);
                if (!File.Exists(path))
                {
                    using var src = asm.GetManifestResourceStream(res)!;
                    using var dst = File.Create(path);
                    src.CopyTo(dst);
                }
            }
            vinculum_set_font_dir(dir);
            _fontDirSet = true;
        }
    }

    /// <summary>
    /// Renders <paramref name="latex"/> to <c>VDL1</c> wire bytes through the native ABI,
    /// or <c>null</c> for unsupported / malformed input — the never-half-broken contract,
    /// carried across the P/Invoke boundary. The native buffer is copied into a managed
    /// array and freed via <c>vinculum_free</c> before returning (no leak, no dangling).
    /// </summary>
    public static byte[]? RenderWire(string latex, bool display, double baseSize)
    {
        ArgumentNullException.ThrowIfNull(latex);
        EnsureFonts();
        var utf8 = Encoding.UTF8.GetBytes(latex);
        IntPtr ptr = vinculum_render_displaylist(utf8, utf8.Length, display ? 1 : 0, baseSize, out int len);
        if (ptr == IntPtr.Zero || len <= 0) return null;
        try
        {
            var bytes = new byte[len];
            Marshal.Copy(ptr, bytes, 0, len);
            return bytes;
        }
        finally { vinculum_free(ptr); }
    }

    /// <summary>Convenience: render straight to a decoded <see cref="DisplayList"/>, or
    /// <c>null</c> if unsupported. Combines <see cref="RenderWire"/> with the shared
    /// <see cref="VinculumWire.Decode"/> — the identical decoder the fixture tests use.</summary>
    public static DisplayList? Render(string latex, bool display, double baseSize)
    {
        var wire = RenderWire(latex, display, baseSize);
        return wire is null ? null : VinculumWire.Decode(wire);
    }
}
