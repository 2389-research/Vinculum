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

## 2. The P/Invoke bridge — implemented, under CI verification
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
builds the DLL (vcpkg FreeType), asserts the four exports, then runs the .NET tests
with `VINC_NATIVE=1` — which flips the native `[SkippableFact]` tests from soft-skip
to **required** (mirrors Android's `MMK_NATIVE`). Until that job is green, no Windows
render capability is claimed here or anywhere in the docs/site. The job is advisory
(`continue-on-error`) while the spike settles — the open question it answers is
whether `@_cdecl` symbols export cleanly from a `.dynamic` product on the Swift
Windows toolchain, and whether vcpkg FreeType links without transitive-DLL gaps.

On managed-only hosts (the ubuntu `dotnet` job, local dev) the native tests
soft-skip, so the pure decoder/renderer suite still runs everywhere.

Also pending (mirroring Android): threading the device-font measure callback
through P/Invoke (the #62 measure-seam lesson), a WinUI/WPF control, themed
rendering across the ABI, and a NuGet package bundling the DLL.
