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

## 2. The P/Invoke bridge — next slice
Unlike Android (which needs a C shim because `JNIEnv` is awkward from Swift), .NET
`[DllImport]` calls the `@_cdecl` C functions directly — no shim. The plan:
- Build the Swift C ABI (`VinculumRender`'s `vinculum_render_displaylist` etc.) as
  a dynamic DLL, P/Invoked from a C# `VinculumNative` (`Marshal.PtrToStringUTF8`-
  style, honoring the `vinculum_free` ownership contract).
- **The Vinculum-specific wrinkle:** the C ABI needs FreeType (math glyphs *are*
  the bundled font, unlike a diagram library's device-font labels), so the Windows
  DLL needs FreeType-on-Windows (vcpkg) — an extra step MermaidKit didn't have.
- Verify on `windows-latest` CI (`compnerd/gha-setup-swift` builds the DLL; the
  .NET tests P/Invoke it), since there's no local Windows box.

Also pending (mirroring Android): threading the device-font measure callback
through P/Invoke (the #62 measure-seam lesson), a WinUI/WPF control, themed
rendering across the ABI, and a NuGet package bundling the DLL.
