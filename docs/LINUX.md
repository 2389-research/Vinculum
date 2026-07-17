# Vinculum on Linux

Vinculum renders math on Linux — not just lays it out. The layout stage
(`VinculumLayout`) has always been platform-free (Foundation only); this
document covers the **rendering** half, which on Linux draws with
[PureSwift/Silica](https://github.com/PureSwift/Silica) (a pure-Swift
CoreGraphics over Cairo) plus FreeType, and produces PNGs.

On Apple platforms `VinculumRender` uses CoreText/CoreGraphics and never links
Silica. On Linux it uses the Silica/Cairo/FreeType path. The public layout API
and the `MathScene` IR are identical across both.

---

## Enabling the backend (the `LinuxRaster` trait)

The Silica raster backend is behind a **package trait**, `LinuxRaster`, which
is **off by default** — so a plain `swift build` (and every downstream
consumer, on any platform) resolves a **Silica-free** dependency graph. Opt in
where you actually want the native raster backend:

```swift
// A consumer that wants Linux rendering:
.package(url: "https://github.com/2389-research/Vinculum.git", from: "1.4.2",
         traits: ["LinuxRaster"])
```

Or on the command line: `swift build --traits LinuxRaster` /
`swift test --traits LinuxRaster`. Apple platforms never link Silica even with
the trait on (the products are also `platforms: [.linux]`-gated), so enabling
it is harmless in a cross-platform package.

> `Package.resolved` is deliberately **git-ignored**: a committed trait-on
> lockfile would re-pull the whole Cairo graph even for default (trait-off)
> builds.

## Quick start

```swift
import VinculumRender   // Linux backend linked when the LinuxRaster trait is on

let png: Data? = MathSilicaRenderer.renderPNG(
    latex: #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
    resource: "latinmodern-math",   // any bundled font, see below
    baseSize: 24,
    display: true)                  // display style (stacked limits, larger parts)

try png?.write(to: URL(fileURLWithPath: "quadratic.png"))
```

`renderPNG` returns `nil` for unsupported LaTeX (the same "never a broken
half-render" contract as the Apple attachment API) or if the font can't load.

Bundled `resource` values: `latinmodern-math` (default), `texgyretermes-math`,
`texgyrepagella-math`, `stixtwo-math`, `firamath`.

---

## How it works

1. **Parse + lay out** — `MathParser` → `MathLayoutEngine` → `MathScene`. This
   is the platform-free `VinculumLayout` code, unchanged from Apple.
2. **Load the font with FreeType** — `FreeTypeFont` loads the bundled `.otf`
   from its bytes (`FT_New_Memory_Face`) and provides glyph advances, real
   per-glyph ink extents (so accents seat on the actual ink), and glyph
   outlines via `FT_Outline_Decompose` → `PathOp`s. The MATH-table constants
   come from the platform-free `MathTableParser`, exactly as on Apple.
3. **Draw into Cairo** — `MathSilicaRenderer` fills each glyph's outline, each
   rule, and each stroked path into a Silica `CairoContext`, mapping the
   scene's y-up baseline coordinates to Cairo's y-down image surface, then
   encodes a PNG.

### Why FreeType outlines instead of Silica's font-by-name?

Silica loads fonts by family name through FontConfig (`CGFont(name:)`). That
works for installed system fonts, but **not** for our bundled MATH fonts:
Silica's font path never calls `FcFontMatch`, so Cairo can't build a face for
any family but the default. Loading the exact `.otf` with FreeType and drawing
its glyph *outlines* sidesteps FontConfig entirely — Silica is purely the
canvas — and works with every bundled font (and any `MathFont(url:)` OTF).

---

## Building on Linux

The Silica backend needs three C libraries at build time (SwiftPM builds the
Cairo/FreeType/FontConfig interop modules against them):

```sh
apt-get install -y pkg-config libcairo2-dev libfreetype6-dev libfontconfig1-dev
swift build --traits LinuxRaster      # or: swift test --traits LinuxRaster
```

Without `--traits LinuxRaster` the backend compiles out (no Cairo/FreeType
needed) and `VinculumRender` is layout-only on Linux, exactly like a
default consumer.

The toolchain floor is **Swift 6.2** — pulling Silica into the graph requires
it (and package traits themselves are SwiftPM 6.1+). Vinculum does **not**
commit `Package.resolved` (a trait-on lockfile would re-pull Cairo for default
builds); the branch pins live in `Package.swift`, and enabling `LinuxRaster`
resolves the PureSwift graph fresh.

### Docker

On Apple Silicon, build the **native arm64** image — do **not** use
`--platform linux/amd64`, whose QEMU emulation faults `swiftc` during heavy
compiles:

```sh
docker run --rm -v "$PWD":/work -w /work swift:6.2 bash -c '
  apt-get update && apt-get install -y pkg-config libcairo2-dev libfreetype6-dev libfontconfig1-dev
  swift test --traits LinuxRaster'
```

No system fonts are required — FreeType loads the bundled `.otf`s from bytes.

---

## Render regression tests (Linux goldens)

`MathSilicaGoldenTests` renders the shared parity corpus and compares each
render against a committed **ink signature** in `Tests/fixtures/linux-golden.txt`
— a size-normalized 32×8 grid, each cell holding how many tenths of it carry ink
(0–9). It runs automatically in the Linux CI job (`swift test --traits
LinuxRaster`).

**Why a signature, not a golden PNG.** The Apple goldens are produced and diffed
in the same environment; a Linux golden has to survive whatever FreeType/Cairo
the CI image ships. Quantizing coverage into a coarse grid (±1 level tolerated,
>2% of cells drifting fails) absorbs anti-aliasing noise while still failing on
what actually regresses — a blank, garbled, or wrongly-laid-out render, none of
which the old "is it a valid PNG?" smoke check could see.

**Re-blessing** (deliberately, after an intended render change) — do it in the
CI image so the signature matches what CI will compute:

```bash
docker run --rm -v "$PWD":/work -w /work swift:6.2 bash -c '
  apt-get update && apt-get install -y pkg-config libcairo2-dev libfreetype6-dev libfontconfig1-dev fonts-dejavu
  cp ci/Package.resolved.linux Package.resolved
  VINCULUM_UPDATE_LINUX_GOLDENS=1 swift test --traits LinuxRaster'
```

Review the diff before committing: a re-bless is a claim that the render changed
*on purpose*.

## Parity with macOS

The layout is identical (same platform-free engine), so the geometry matches.
A 20-equation corpus (`Tests/fixtures/parity-corpus.txt`, rendered by
`ParityGenerator` on macOS and `VinculumLinuxSmoke` on Linux) shows
near-perfect parity for **fractions, radicals, scripts, matrices, cases,
delimiters, binomials, the whole `\x…arrow` family, over/underbraces, boxes,
`\color`, math alphabets, sums, limits, and Stirling numbers**.

### Known gaps (Linux)

These come from the Linux path wiring only the **base** services (measurer +
MATH constants), not the full font-truth provider stack that the Apple path
has. They are follow-ups, not fundamental limits:

| Gap | Effect | Provider not yet wired |
| --- | --- | --- |
| Large-operator display variants | `\int` / `\oint` render at base size, not the larger display cut | `MathDelimiterProvider` (display-operator path) |
| `ssty` optical scripts | Superscripts/subscripts scale the base glyph instead of the optical redraw | `MathScriptVariantProvider` |
| Delimiter size variants | Tall fences point-scale rather than using purpose-drawn cuts | `MathDelimiterProvider` / assembly |
| `\vec` / `\bar` accent glyphs | Arrow slightly off-center; the overbar glyph may be missing | per-glyph typography + accent-variant providers |

Everything the Apple path draws with hand-stroked primitives (braces, arrows,
radical hooks, cancels, boxes) is identical on Linux, because those need no
font provider.

---

## Server-side SVG (the other headless option)

If you want markup rather than pixels — or a fully platform-free path with no
Cairo/FreeType — `MathSVGRenderer` turns a `MathScene` into self-contained SVG
on any platform, including a headless Linux host with no rendering backend at
all. See [INTEGRATION.md](INTEGRATION.md) §12. The Silica backend is for when
you want a rasterized PNG on Linux.
