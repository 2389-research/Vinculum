# Performance

How Vinculum spends its time — **measured, not asserted.** Every number here
comes from two committed harnesses in `Tests/VinculumRenderTests/`:

- **`MathProfileTests`** — a phase profiler that decomposes the cold render into
  parse / support-check / speech / layout (with CoreText measurement isolated) /
  rasterize, and checks whether rasterization is deferred.
- **`MathPerformanceTests`** — loose CI ceilings (fail if cold/warm/headless
  regress an order of magnitude) that print medians on every run.

Reproduce the table below:

```
VINCULUM_PROFILE=1 swift test -c release --filter MathProfileTests/testProfilePipeline
```

Figures are **release-build medians on Apple silicon (M-series), Latin Modern,
macOS/CoreText** (80 iterations, first 15 dropped as warmup). Your hardware will
differ — the **shares** are the durable finding, not the absolute microseconds.
Always quote release: debug is 2–5× slower for the Swift phases (see the end).

---

## TL;DR — three regimes

| Path | Time | What it is |
| --- | --- | --- |
| **Warm render** (cache hit) | **~0.5 µs** | An `NSCache` lookup keyed by content + theme + size + font. No parse, no layout, no draw. |
| **Cold cache-fill** (parse → layout → scene) | **~0.2 ms** | First time an equation is seen: builds the atom tree, lays it out, constructs the image — but **not the pixels** (see *deferred raster*). |
| **First paint** (rasterization) | **+~0.23 ms** | The glyphs are actually drawn the first time the image is displayed. *Deferred* on macOS; eager on iOS. |
| **Headless layout** (pure Swift — the Linux / SVG path) | **~8 µs** | Parse + geometry with a caller-supplied measurer; no CoreText, no raster. |

A never-before-seen equation costs **~0.2 ms to lay out** and **~0.44 ms to first
show**. Every subsequent show is **~0.5 µs** plus the OS blitting a cached bitmap.

---

## Where every microsecond goes

The quadratic formula, `x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}` (12 glyph runs),
cold path, release:

| Phase | Time | Share | Notes |
| --- | --- | --- | --- |
| **Rasterize** (glyphs → pixels) | ~150 µs | **60%** | CoreText/CoreGraphics glyph drawing + rule fills. *Deferred on macOS.* |
| **Layout** | ~62 µs | 25% | of which… |
| &nbsp;&nbsp;· CoreText measurement | ~41 µs | 17% | one `CTLine` measure per glyph run (12 here) |
| &nbsp;&nbsp;· pure geometry (Swift) | ~21 µs | 8% | Appendix-G arithmetic, struct math |
| **Parse** (LaTeX → atom tree) | ~23 µs | 9% | |
| **Speech** (ClearSpeak description) | ~13 µs | 5% | **always paid** — see below |
| **Support check** | ~0.7 µs | <1% | one tree walk |
| **Total** (cold, incl. the deferred paint) | **~250 µs** | | |

**The dominant cost is CoreText, not Vinculum.** Measurement (41 µs) +
rasterization (150 µs) = **~77% of the cold path** is spent inside
CoreText/CoreGraphics measuring and drawing glyphs — the same work *any* native
text renderer does. Vinculum's own contribution — parse + layout geometry — is
~44 µs, under a fifth. That's also why release optimization barely moves raster
(it's already C) but halves parse and geometry.

### The deferred-rasterization finding (macOS)

`MathImageRenderer.rendered()` on macOS returns an `NSImage(size:flipped:)` whose
draw block is **lazy** — it runs the first time the image is *painted*, not when
`rendered()` returns. Measured on the quadratic:

- `rendered()` returns the (unpainted) image: **~205 µs**
- forcing the pixels (`cgImage(forProposedRect:…)`): **+~230 µs**

So the cache stores a *recipe*; the ~230 µs of glyph drawing is paid once, on
first display, after which the OS caches the bitmap. **Implication:** pre-warming
the cache off the main thread pays the ~0.2 ms there, but the first on-screen
frame still owes the ~0.23 ms paint. On **UIKit/iOS**, `buildEntry` uses
`UIGraphicsImageRenderer.image {}`, which rasterizes **eagerly** — iOS pays the
full ~0.44 ms at cache-fill and the first paint is free. Same total work,
different moment.

> A subtlety worth flagging: `NSImage.tiffRepresentation` is **not** a clean way
> to force the paint — it adds ~2 ms of TIFF *encoding* that has nothing to do
> with rendering. Use `cgImage(forProposedRect:context:hints:)`.

### Speech is always paid

`buildEntry` computes the ClearSpeak spoken-math description on every cold render
(~13 µs, 5%) whether or not the host uses accessibility. It rides on the cached
entry so it's never recomputed — but a host that never reads it pays it once per
equation. A candidate for lazy computation (open optimization).

---

## Scaling with complexity

Cold cost tracks **glyph-run count** (measure calls) and **ink area** (raster) —
not character count. Release medians, µs:

| Equation | runs | parse | layout | raster | cold Σ |
| --- | --- | --- | --- | --- | --- |
| `\frac{a}{b}` | 2 | 8 | 54 | 33 | 99 |
| `a + b = c` † | 5 | 8 | 73 | 62 | 147 |
| `\begin{pmatrix} a&b\\c&d \end{pmatrix}` | 4 | 12 | 14 | 62 | 93 |
| `x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}` | 12 | 23 | 62 | 150 | 250 |
| `\sum i^2 = \frac{n(n+1)(2n+1)}{6}` | 16 | 31 | 118 | 213 | 376 |
| `\zeta(s)=\sum \frac1{n^s}=\prod\frac1{1-p^{-s}}` | 14 | 41 | 132 | 240 | 433 |

The 2×2 matrix is *cheaper* than the quadratic despite its structure — four
one-glyph cells and two delimiters is less work than a nested fraction under a
radical. **Cost is structural, not visual size.**

> † The `a + b = c` row's layout is inflated: it's the first equation in the
> sweep, so its glyph sizes are cold in CoreText's per-size cache; later rows
> reuse the warmed sizes. The quadratic (fully warm, representative) is the
> canonical figure. Within any one row the phase *shares* are stable; absolute
> cross-row numbers carry this first-touch bias (±~10%).

---

## Debug vs release

`swift test` defaults to debug. The Swift phases are 2–5× slower there; the
CoreText phases barely change (already optimized C):

| | debug | release |
| --- | --- | --- |
| Headless layout (pure Swift) | ~43 µs | **~8 µs** |
| Parse (quadratic) | ~52 µs | ~23 µs |
| Layout geometry | ~67 µs | ~21 µs |
| Rasterize | ~163 µs | ~150 µs |
| Warm hit | ~0.6 µs | ~0.5 µs |

The README's historical "~0.3 ms cold / ~40 µs headless" were **debug** numbers,
and the "cold" figure was mislabeled — it excluded the deferred paint. This doc
supersedes them.

---

## What we never pay

No WebView spin-up, no JavaScript engine, no network round-trip, no document
reflow. A cold render is a parse, a dozen CoreText calls, and a draw — that is
the entire bill. The parser is bounded twice (a linear nesting pre-scan and a
runtime depth counter), so even adversarial input degrades to fallback in
bounded time instead of overflowing — proven by the deterministic fuzz suite.

---

## Accuracy caveats

- Medians over 80 iterations, first 15 dropped as warmup; CoreText warmed before
  the sweep so no row absorbs process-wide font-system init.
- The measurement/geometry split wraps the measurer with two `ContinuousClock`
  reads per call (~tens of ns each); at ~12 calls this adds <1 µs to layout,
  attributed to measurement.
- CoreText's internal per-font-size caches warm across the sweep, so absolute
  cross-equation attribution is ±~10%; within-equation shares are stable.
- One machine, one font. Re-run the harness on your target to get your numbers.
