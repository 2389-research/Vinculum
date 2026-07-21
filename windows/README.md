# Vinculum on Windows / .NET

The Windows story mirrors Android's: one platform-free Swift layout core → a
fully-resolved display list crosses the C ABI as the language-neutral `VDL1`
binary → a thin native renderer paints it. Windows reuses the *exact* seam — the
scene contract is already proven byte-identical there (the wire-conformance gate).

Two pieces, mirroring Android's renderer + JNI:

## 1. The renderer — `Vinculum.Rendering` (this, done + gated)
A .NET library: a `VDL1` decoder (`VinculumWire`, the C# twin of Kotlin's
`ai.vinc.VinculumWire`) and a `SceneRenderer` over `SKCanvas`. **SkiaSharp** by
choice — it's the same Skia engine the Android `Canvas` uses, so Windows is a
fidelity match for Android by construction, and it's headless-testable on
Linux/macOS/Windows (Direct2D would be Windows-only + untestable in CI; SVG was
off the table). Vinculum's wire is *binary*, not JSON, so the decoder is a
`BinaryReader` — no `System.Text.Json` polymorphism wrinkle.

Verified: `dotnet test` runs the C# decoder against the **same committed
`displaylist-wire-v1.bin`** the Swift and Kotlin conformance tests use, plus a
SkiaSharp render smoke — gated in CI (the `dotnet` job) on every PR.

## 2. The P/Invoke bridge — verified green on `windows-latest`
Unlike Android (which needs a C shim because `JNIEnv` is awkward from Swift), .NET
`[DllImport]` calls the `@_cdecl` C functions directly — no shim.

- **`VinculumNative.cs`** P/Invokes the four ABI entry points
  (`vinculum_render_displaylist` / `vinculum_free` / `vinculum_abi_version` /
  `vinculum_set_font_dir`), honoring the `vinculum_free` ownership contract
  (copy-then-free, no leak). It mirrors Kotlin's `ai.vinc.VinculumNative`. The
  `RenderWire`/`Render` helpers carry the never-half-broken contract across the
  boundary (unsupported LaTeX → `null`, not a half-drawn glyph).
- **The Swift side needed no `#if os()` changes.** The three FreeType sources
  guard on `canImport(CFreetypeShim)` alone, so admitting `.windows` to the shim's
  `FreeTypeRaster` gate in `Package.swift` is the whole diff — the identical C ABI
  compiles into a Windows DLL.
- **The Vinculum-specific wrinkle:** the C ABI needs FreeType (math glyphs *are*
  the bundled font, unlike a diagram library's device-font labels), so the Windows
  DLL links **vcpkg's `freetype`** — an extra step MermaidKit didn't have.
- **`@_cdecl` marks symbols `extern "C"` but does not `dllexport` them** on
  Windows, so the DLL build passes `/EXPORT:` linker directives for the four
  entry points; `dumpbin /exports` proves they're on the export table.

**Verified where?** The `native DLL + P/Invoke (Windows)` CI job on `windows-latest`
builds the DLL (vcpkg FreeType, `/LIBPATH:` + `/EXPORT:` linker flags), proves the
four `@_cdecl` symbols are on the export table with `llvm-readobj --coff-exports`,
then runs the .NET tests with `VINC_NATIVE=1` — which flips the native
`[SkippableFact]` tests from soft-skip to **required** (mirrors Android's
`MMK_NATIVE`). The end-to-end test renders `\frac`/`\sqrt` through the native ABI →
`VDL1` bytes → the shared `VinculumWire.Decode` → SkiaSharp ink, entirely on Windows.
It is a **real gate now** (no `continue-on-error`), so the native render path can't
silently drift.

Both spike questions came back yes: `@_cdecl` symbols export cleanly from a
`.dynamic` product on the Swift Windows toolchain (given `/EXPORT:` directives —
`@_cdecl` alone gives `extern "C"` naming but not `dllexport`), and vcpkg FreeType
links without transitive-DLL gaps (its `bin` dir goes on the loader `PATH`).

On managed-only hosts (the ubuntu `dotnet` job, local dev) the native tests
soft-skip, so the pure decoder/renderer suite still runs everywhere.

## 3. The drop-in control — `Vinculum.Windows.Wpf` (`VinculumMathView`)
The consumable UI piece — the Windows analog of Apple's `VinculumLabel`, and the
**first drop-in control outside Apple**. It's an `SKElement` (a WPF control backed by
a SkiaSharp canvas) with dependency properties that mirror `VinculumLabel`:

```xml
<vinc:VinculumMathView Latex="x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"
                       DisplayMode="True" BaseSize="24" Ink="Black" />
```

Set `Latex` and it paints: the native ABI renders → `VDL1` → `VinculumWire.Decode` →
`SceneRenderer` on the control's canvas. `Ink` maps to a light/dark theme foreground
and rides the `SceneRenderer` ink override (recolor-preserving-alpha, unit-tested
headless) — no ABI round-trip. `MeasureOverride` sizes the control from the display
list, so it lays out like any WPF element.

WPF is `net8.0-windows` (Windows-only), so it's **compile-verified** on the
`windows-latest` CI job against the real WPF + SkiaSharp.Views SDK; its *render*
correctness rests on `SceneRenderer`, which is pixel-tested headlessly (including the
ink override) in the cross-platform `dotnet` job. Requires the native
`VinculumAndroid.dll` + FreeType deps on the load path at runtime (the NuGet package
will ship them as native assets).

## Still pending (the road to 2.0.0 "full Windows")
- **NuGet package** bundling `Vinculum.Rendering` + `VinculumNative` + the native DLL
  and its FreeType deps as native assets, so a Windows dev just adds a package ref.
- **WinUI 3 control** (fast-follow: same `SceneRenderer`, `SKXamlCanvas` instead of
  `SKElement`; needs the Windows App SDK workload in CI).
- Threading the device-font **measure callback** through P/Invoke (the #62 lesson) —
  lower priority on Windows since math glyphs come from the bundled fonts, not device
  fonts.
