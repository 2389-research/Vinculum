# Platform support

Vinculum is two products, and they reach different distances. **`VinculumLayout`**
(parse → TeX layout → device-independent `MathScene`/`DisplayList`) is
Foundation-only and runs anywhere Swift does. **`VinculumRender`** is the
per-platform drawer. The portable [`DisplayList` / `VDL1`](DISPLAYLIST.md) protocol
is what lets a new platform be a thin drawer rather than a fork.

This page is the honest status. It distinguishes three levels, because they are
not the same promise:

- **Shipped** — released, packaged, a consumer can depend on it today.
- **Gated** — built and/or tested on every PR in CI, so it can't silently rot.
- **Proven** — demonstrated working with a verified artifact, but not yet gated
  or packaged (a one-off that could drift until it's gated).

## Matrix

| Platform | Layout (`VinculumLayout`) | Rendering | Notes |
| --- | --- | --- | --- |
| **macOS / iOS / visionOS / tvOS** | Shipped · gated (CI) | **Shipped** — CoreText / CoreGraphics; `NSTextAttachment`, `VinculumLabel`, SwiftUI `MathView` | the reference platform (release 1.5.0) |
| **Linux** | Shipped · gated (CI) | **Shipped** — Silica/Cairo/FreeType behind the `LinuxRaster` trait; PNG. SVG is Foundation-only, no trait needed | headless / server-side |
| **Android** | Gated (Linux CI builds the exact FreeType tier every PR) | **Proven on-device** — FreeType outlines → `Canvas` via the JNI/`VDL1` bridge; renders correctly on an emulator. Kotlin decoder **gated** (conformance CI). **Not yet packaged** (no AAR/Maven) | see [ANDROID.md](ANDROID.md) |
| **WebAssembly** | **Gated (CI)** — cross-compiles to `wasm32-unknown-wasip1` and renders SVG under wasmtime on every PR | SVG (Foundation-only). Pixel/Canvas rendering is a browser-side drawer, **not yet built**. Binary-size work pending | real TeX layout in the browser, no server |
| **Windows** | **Gated (CI)** — `swift build` + `swift test` on the official Windows toolchain every PR | **No drawer yet** — recommended Direct2D consuming `VDL1`; layout + SVG work today | code audited clean, no changes needed |

## What "gated" buys you, concretely

Every PR runs, on GitHub's own runners:

- **Linux** — the platform-free layout suite, plus the FreeType tier (Cairo-absent, the Android dependency shape) and the full Silica/Cairo backend.
- **Windows** — `VinculumLayout` build + the geometry/parser/wire suites on the official Swift Windows toolchain.
- **wasm** — cross-compile to `wasm32` + an actual SVG render under wasmtime.
- **kotlin** — the Kotlin `VDL1` decoder decodes the committed fixture (cross-language wire conformance, no emulator).
- **macOS** — the full suite + the iOS simulator.

The **Linux, macOS, and kotlin** jobs are **blocking**. The **Windows** and **wasm**
jobs are currently **advisory** (`continue-on-error`) while they settle — they run
every PR and go red on drift, but don't yet block merge; they'll be promoted to
blocking once stable across a few runs.

And two cross-platform invariants are enforced:

- **Wire conformance** — one committed `VDL1` fixture round-trips byte-identically in Swift (macOS/Linux/Windows) and Kotlin. See [DISPLAYLIST.md](DISPLAYLIST.md).
- **SVG parity** — the platform-free layout→SVG pipeline renders a corpus to byte-identical goldens on every platform; any drift (even a formatted digit, even a line-ending) fails the build.

## Do all platforms render identically?

Measured, layer by layer:

- **Layout geometry** — **identical.** CoreText (Apple) and FreeType (Linux/Android) produce byte-identical scene geometry to 3 decimals for representative equations, because both read the same font's advance metrics. Android/Windows use FreeType, so they equal Linux exactly.
- **Display-list bytes** — **identical** (the conformance fixture, cross-platform).
- **Glyph coverage for exotic Unicode** — *can differ*: CoreText may substitute a system font where FreeType returns `.notdef`. Narrow; tracked by [#62](https://github.com/2389-research/Vinculum/issues/62).
- **Final pixels** — *differ by design*: anti-aliasing, hinting, and subpixel positioning are each platform rasterizer's own house style, even for identical geometry.

So: **same math, same positions, same bytes — down to where each pixel goes; the pixels themselves are drawn by each platform's native rasterizer.**

## Adding a platform

The display list is a documented protocol, so a new platform is a decoder + a
drawer, not a fork. See the short recipe in [DISPLAYLIST.md](DISPLAYLIST.md#adding-a-platform-the-short-version)
and the worked Android example in [ANDROID.md](ANDROID.md).
