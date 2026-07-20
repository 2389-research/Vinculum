# Vinculum on Android — design exploration

> **Status: DESIGN, NOT BUILT (2026-07-17).** No Android code exists yet. This
> document captures the ideas considered, the reasoning, and the decisions, so
> the build can start from a settled architecture instead of a blank page.
> Nothing here has been compiled against an Android toolchain; treat effort and
> risk estimates as informed guesses, not measurements. The website and README
> deliberately make **no** Android claims until this ships — see
> [PERFORMANCE.md](PERFORMANCE.md)'s discipline: claims must not outrun reality.

## The goal

The highest achievable **fidelity** (Android output that matches the Apple
render, including the hard cases — stretchy delimiters, `ssty` script glyphs,
cramped-style shifts) and the highest **utility** for Android developers: bridges
they snap into a project with one Gradle line and no NDK, no C toolchain, no
server, and no surprises.

Everything below serves those two words. Where a choice trades fidelity or
frictionlessness for less work, we noted it and chose against it.

---

## Why this is tractable at all

Vinculum is two products, and the split is what makes Android reachable:

- **`VinculumLayout`** imports **Foundation only** (27 files, verified). It owns
  parsing, macros, all typesetting geometry, and the OpenType MATH-table
  constants (parsed by the platform-free `MathTableParser`). It already builds
  and passes its geometry tests **headless on Linux**. It emits a
  device-independent `MathScene` — a list of positioned primitives.
- **`VinculumRender`** is where the platform lives: CoreText/CoreGraphics on
  Apple, Silica/Cairo/FreeType on Linux.

So the "port" is not a rewrite. It is: get `VinculumLayout` running on Android's
runtime, and give it an Android-shaped way to turn a `MathScene` into pixels.
Those are the two walls, and they are independent.

### The two walls

1. **Runtime** — Android apps are Kotlin/Java on ART. Swift does not run there
   natively. `VinculumLayout` must cross-compile to a native `.so` (Swift
   Android SDK / NDK) and be reached over JNI.
2. **Render backend** — neither existing backend runs on Android. Cairo is not a
   platform library there; `PureSwift/Silica`+`Cairo` are niche packages pinned
   to `branch: master`, and their NDK buildability is unproven. **FreeType,
   however, is present on Android** (Skia is built on it).

### The lever that collapses wall 2

`FreeTypeFont` already decodes glyph outlines to **platform-neutral `PathOp`s**
(`move`/`line`/`quad`/`close`), and Cairo only enters at the final
surface-fill/PNG step. That means the outline-and-measure half — the part that
needs a real font engine — is **Cairo-free and reusable**. We can drive it with
FreeType (which Android has) and draw the resulting paths on an Android `Canvas`,
never touching Cairo or Silica.

The `MathScene` IR is already the right shape to hand across the boundary:

```swift
public enum MathElement {
    case glyphs(text: String, size: CGFloat, mono: Bool, origin: CGPoint, color: MathColor?)
    case rule(CGRect, color: MathColor?)          // fraction bars, radical rules, matrix lines
    case glyph(id: UInt16, size: CGFloat, origin: CGPoint, color: MathColor?)  // variants, ssty
}
```

Resolve each element to filled paths + rects in Swift (via FreeType), and the
Android side just paints a flat display list. No text shaping, no font logic,
and no CoreText/Cairo on the Kotlin side.

> **Done:** the FreeType tier is trait-separated from Cairo (a `FreeTypeRaster`
> trait links only the FreeType shim; `LinuxRaster` enables it and adds Cairo on
> top), and the whole tier now **cross-compiles to an Android `.so`** — see the
> roadmap below. `FreeTypeFont`, the outliner, the font loader, and the C ABI build
> without Cairo on Linux (`swift test --traits FreeTypeRaster`, guarded in CI) and
> link into `libVinculumAndroid.so` for `aarch64-android`.

---

## Decisions

### 1. On-device native, not server-SVG and not a WebView

**Considered:**
- *Server-side layout → SVG → WebView / AndroidSVG.* `VinculumLayout` runs on
  Linux today and `MathSVGRenderer` is platform-free, so this works with zero
  device Swift. Cheapest by far.
- *On-device native.* Cross-compile the layout, render on-device.

**Chosen: on-device native.** The server path fails all three of the goal's
constraints: it breaks offline, adds round-trip latency to every equation (fatal
in a scrolling list or a live editor), and — without a glyph-outline provider on
the server — renders `.glyph(id:)` elements as holes, so the fidelity ceiling is
capped below the Apple output. A WebView carries its own weight, its own theming
mismatch, and is the opposite of "snaps into the system." Native is the only
path that clears "highest fidelity" and "no frustration" at once.

The server-SVG path is still worth keeping documented as a fallback for hosts
that genuinely cannot load a native lib, but it is not the product.

### 2. One font engine — FreeType — for BOTH measuring and drawing

**Reasoning, learned the hard way.** Layout geometry is a function of the
measurer's metrics. If the thing that *measures* glyphs and the thing that
*draws* them disagree, the output is subtly wrong with no error — this is
[#62](https://github.com/2389-research/Vinculum/issues/62), the seam-parity
problem, and it is not hypothetical: the render-fuzz work in
[#12](https://github.com/2389-research/Vinculum/issues/12) found two Unicode
inputs that render on CoreText but degrade on FreeType, *the same layout code,
different output per platform*.

So Android uses **FreeType for both** — `advanceEm`/`inkExtentEm` for the
measurer seam, and `outline` for the glyph paths. One engine, one source of
truth, no seam to disagree across. (Tempting alternative: measure with Android's
own `Paint`/HarfBuzz. Rejected — it reintroduces exactly the two-engines gap
#62 is about.)

Bonus: the Linux backend already uses FreeType for both, so the Android
measurer/outline provider is close kin to code that already exists and is tested.

#### Why not draw with Android's native text stack, the way a diagram library would?

A sibling project (MermaidKit) is planning the opposite for its Android backend —
draw with `android.graphics.Canvas`/`Paint` (→ Skia) and the **device's real
fonts** (Roboto), on the principle that on Android, fidelity *means* using the
platform's own 2D stack and native fonts, and that drawing bundled-font outlines
yourself is the *anti*-pattern.

**That principle is correct for MermaidKit and wrong for Vinculum, and the reason
is the domain, not a disagreement about Android.** MermaidKit draws diagram labels
— ordinary prose in whatever sans-serif the app uses. For text-as-text, the
device font via Skia is genuinely higher fidelity: DPI-perfect hinting, Material
theming, matches the rest of the UI, no font to bundle.

Vinculum draws **math**, where the glyphs *are* the font. Math typesetting is
driven by an OpenType **MATH table**: stretchy delimiter size-variants, big-operator
alternates, `ssty` script glyphs, italic corrections, per-glyph MATH constants.
None of that exists in Roboto — there is no √ that grows to fit its radicand and no
display-size ∑ in a system font. So the bundled math `.otf` is not a fidelity
*compromise*; it **is** the fidelity, and it must be drawn from its own outlines.
Equally, math glyphs can't be measured with `Paint.measureText` — placement comes
from the MATH table, not from a text-run advance.

The law underneath both projects is the same — **measure with the exact engine
that draws** (the seam-parity lesson, #62). The two just satisfy it with different
engines because their fonts differ: MermaidKit uses the *device's* font for both
(ideally via a batched `Paint.measureText` callback into layout, so the same Skia
face measures and draws); Vinculum uses *FreeType* for both. Same principle,
opposite implementation. Copying MermaidKit's font strategy into Vinculum would
break math; copying Vinculum's into MermaidKit would make its labels look foreign.

### 3. Tiered render: vector on Canvas, with a bitmap cache for hot repeats

**Considered:**
- *Bitmap across JNI* — Swift rasterizes, Kotlin blits. Simplest bridge, mirrors
  the Apple `MathImageRenderer` image cache. But scale and color are **baked at
  render time**: zoom or a theme change forces a re-render, and a bitmap made at
  one display's density is wrong on another. That is literally
  [#17](https://github.com/2389-research/Vinculum/issues/17) — the raster
  scale-lock — reproduced on Android.
- *Vector on Canvas* — Swift returns a display list (paths + rules + colors);
  Kotlin draws it. Resolution-independent, re-themes and re-scales for free,
  crisp at any zoom. More JNI surface and more Kotlin drawing code.
- *Tiered* — vector primary; memoize a bitmap keyed by `(latex, size, scale,
  color)` for equations that repaint often (a re-scrolled list row).

**Chosen: tiered.** Vector is the fidelity path and structurally dodges #17 —
there are no baked pixels to lock a resolution. The bitmap cache is a pure
performance layer on top, keyed *including scale and color* so it can never serve
a stale-resolution or stale-theme bitmap (the mistake #17 is about). Its key is
the design fix #17 asks for, applied from the start. Most moving parts of the
three, and worth it: it is the only option that is both highest-fidelity and
smooth in a long list.

The vector display list is the JNI contract (below); the cache lives entirely on
the Kotlin side, so the Swift boundary stays small and pure.

### 4. Distribution: a prebuilt AAR on Maven, every ABI, zero NDK for the consumer

**Reasoning.** "Snap in without hassle" has a precise meaning in Android: add one
line to `build.gradle`, sync, done. Anything that asks the app developer to
install the NDK, run a Swift cross-compile, or manage `.so` files by hand fails
the brief.

So we publish an **AAR to Maven Central** containing prebuilt native libraries
for every mainstream ABI plus the Kotlin API. The entire Swift/JNI/FreeType
apparatus is invisible to the consumer.

```kotlin
dependencies {
    implementation("ai.2389.vinculum:vinculum-android:1.0.0")   // coordinates TBD
}
```

*Alternative rejected:* ship source + a Gradle plugin that builds Swift locally.
That is the "hassle" the goal forbids — it moves our toolchain problem onto every
consumer's machine.

### 5. Bridges: all four, layered, Compose as the flagship

You deferred this one, so the reasoning is ours to own. The four surfaces are not
alternatives — they are a stack, and each sits on the one below, so building the
bottom first makes the rest cheap:

```
Markwon plugin  ─┐
Compose Math()   ├─►  VinculumMath (Kotlin API)  ─►  JNI  ─►  VinculumLayout(.so)
Classic View     ─┘        (raw: LaTeX → display list / bitmap)
```

Priority, and why:

1. **Raw Kotlin API** (`VinculumMath`) — LaTeX in → display list or bitmap out.
   Built first because everything else is a thin wrapper over it; also the
   surface power users build custom rendering on.
2. **Jetpack Compose** `@Composable Math("...")` — the flagship. New Android UI
   is Compose, and the vector display list maps naturally onto a `Canvas`
   `DrawScope`. Baseline-aligned, theme-reactive via `LocalContentColor`.
3. **Classic `View` + spans** — `VinculumMathView : View`, plus an inline span so
   math drops into a `TextView`/`Spannable`. Covers the large installed base of
   non-Compose apps and mirrors the Apple `VinculumLabel`.
4. **Markwon plugin** — math inside Markdown prose, the Android analog of
   `MathText`, for chat/notes/docs hosts.

Building 1→4 in order means each layer ships usable and the flagship (Compose)
arrives early, on a core that's already proven.

---

## Architecture

```
┌─────────────────────────────────────── Android app (Kotlin) ───────┐
│  Compose Math()   │  VinculumMathView  │  Markwon plugin           │
│         └──────────────────┴───────────────────┘                   │
│                    VinculumMath  (Kotlin, pure)                     │
│         • bitmap cache keyed by (latex,size,scale,color)           │
│         • Canvas draw of the display list                          │
└────────────────────────────┬──────────────────────────────────────┘
                             │  JNI  (narrow C ABI)
┌────────────────────────────┴──────────────────────────────────────┐
│  libvinculum.so   (Swift, cross-compiled)                          │
│    VinculumLayout   parse → layout → MathScene   (unchanged)       │
│    + AndroidRender  MathScene → display list, via FreeType         │
│         • measurer seam   = FreeTypeFont.advanceEm/inkExtentEm     │
│         • glyph outlines  = FreeTypeFont.outline → PathOp          │
│         • rules           = MathElement.rule → rect                │
│    FreeType (NDK)   bundled .otf loaded from bytes                 │
└────────────────────────────────────────────────────────────────────┘
```

The only genuinely new Swift is **`AndroidRender`**: a thin walk of the
`MathScene` that resolves every `MathElement` to paths/rects using
`FreeTypeFont` (which exists) and serializes the result across the C ABI. It is
the Cairo-free sibling of `MathSilicaRenderer` — same font calls, different final
sink.

### The JNI contract (the display list)

Keep the boundary flat, versioned, and pure-data. One call in, one buffer out:

```
vinculum_render(latex:UTF-8, displayMode:bool, size:float, dpiScale:float)
    → DisplayList {
        width, ascent, descent : float          // in px at the given size×dpiScale
        ops : [                                  // painter's order
            FillPath { subpaths:[MoveTo|LineTo|QuadTo|Close], rgba },   // glyphs
            FillRect { x,y,w,h, rgba },                                 // rules
        ]
      }
    | null                                       // unsupported → host shows its fallback
```

Notes that matter:
- **A `null` return is the never-half-broken contract**, preserved across the
  boundary: unsupported LaTeX renders nothing and the host supplies its own
  fallback, exactly as on Apple (`MathImageRenderer.rendered` returning nil).
- Color is resolved in Swift from a single injected ink (the theme), so a
  template equation re-themes by re-requesting with a new `rgba` — cheap, since
  layout is cached and only the fill color changes. Explicit `\color{}` wins per
  element, same as every other backend.
- Coordinates are y-down px (Android's `Canvas` convention), converted once at
  the boundary from the scene's y-up points. One conversion site, not scattered.
- The display list is **self-contained** — no glyph IDs, no font handles leak to
  Kotlin. Everything the Canvas needs is geometry + color. This is what lets the
  Kotlin side stay font-agnostic and the cache key stay simple.

### Serialization format — decided: a hand-rolled binary, not FlatBuffers (#78)

**Chosen: `VDL1`, a small little-endian tagged binary** (`DisplayListWire.swift`),
reversing the issue's initial FlatBuffers lean. Reasoning:

- **The package is dependency-free by charter** (`Package.swift` says so). FlatBuffers
  needs a runtime dependency *and* a `flatc` codegen step — the one thing this format
  must not drag into the core.
- **Zero-copy buys nothing here.** A display list is a few KB; the fixture for a full
  canonical list is **144 bytes**. There is no large buffer to avoid copying.
- **It is a few dozen lines on each side.** The writer is Swift; the reader is
  `ByteBuffer.order(LITTLE_ENDIAN)` in Kotlin, no tools.

Layout: `"VDL1"` magic · `width/ascent/descent` (f32) · `opCount` (u32) · then
`fillPath` / `fillRect` / `strokePath` ops, each carrying 8-bit rgba and f32
coordinates (both match what the Canvas draws). Full grammar is in the
`DisplayListWire` doc comment.

**Versioning:** the `"1"` in the magic *is* the version. A reader MUST check the
4-byte magic and reject an unknown one — that rejection is the compatibility
guarantee (an old reader refuses new data cleanly rather than misreading it). A
change that would mislead an old reader bumps the magic (`VDL2`) and re-cuts the
fixture.

**Cross-language contract:** `Tests/fixtures/displaylist-wire-v1.bin` is a committed
serialization of a canonical list covering every op and segment kind. The Swift
side proves the writer is byte-stable against it and the reference reader decodes
it; the future Kotlin reader is tested against **the same bytes**, so the two ends
cannot drift silently. Regenerate only on a deliberate format change, with
`VINCULUM_UPDATE_WIRE_FIXTURE=1`.

### Kotlin API sketches

```kotlin
// 1. Raw
object VinculumMath {
    fun layout(latex: String, display: Boolean = true, sizePx: Float, dpiScale: Float): MathDisplayList?
    fun renderBitmap(latex: String, display: Boolean = true, sizePx: Float, dpiScale: Float, color: Int): Bitmap?
}

// 2. Compose (flagship)
@Composable
fun Math(
    latex: String,
    display: Boolean = true,
    color: Color = LocalContentColor.current,
    modifier: Modifier = Modifier,
)   // draws the vector display list on a Canvas; caches a bitmap per (latex,size,scale,color)

// 3. Classic View
class VinculumMathView(context: Context) : View(context) {
    var latex: String = ""
    var display: Boolean = true
}   // + a MathSpan for inline use in a Spannable/TextView

// 4. Markwon
Markwon.builder(context).usePlugin(VinculumMarkwonPlugin.create()).build()
```

---

## Build & packaging plan

- **ABIs:** `arm64-v8a` (primary — all modern devices), `x86_64` (emulators),
  `armeabi-v7a` (older devices; drop if the Swift Android SDK can't target it
  cleanly). Ship as ABI splits so an app only pulls the slices it needs.
- **min SDK:** target API 24+ (covers ~99% of devices) pending what the Swift
  Android runtime actually requires — an open question until measured.
- **Fonts:** the bundled `.otf`s ship inside the AAR and load via FreeType from
  bytes (no system-font dependency — this already works on Linux). The one piece
  of plumbing to verify is that SwiftPM's resource bundling reaches the asset
  path inside the `.so`'s packaging.
- **FreeType:** link the NDK's FreeType via a shim analogous to `CFreetypeShim`
  (`module.modulemap` with `link "freetype"`).
- **CI:** a new Android job — cross-compile the `.so`, assemble the AAR, run
  Kotlin unit tests, and (stretch) an instrumented screenshot test on an
  emulator for parity.

---

## Fidelity checklist (what "matches Apple" requires)

Highest fidelity is a testable claim, not a hope. Parity holds only if the
Android path reproduces each of these — the same list the layout engine already
honors, now across a new render sink:

- [ ] **`.glyph(id:)` renders** — stretchy delimiter size variants and `ssty`
      script glyphs, via the FreeType outline provider. Missing this is the
      single biggest fidelity gap (it is what the server-SVG path can't do).
- [ ] **Per-font MATH constants** — already parsed platform-free by
      `MathTableParser`; the Android path must feed the same table for each
      bundled font (the exact bug [#1](https://github.com/2389-research/Vinculum/issues/1)
      was, on Linux).
- [ ] **Measurer/outline agreement** — both from the *same* FreeType face, so no
      #62 seam gap.
- [ ] **Cramped-style shifts, Rule 18a ink floors, aligned display style** — all
      live in `VinculumLayout` and come for free once layout runs; they need no
      Android-specific work, only that the geometry isn't re-derived on the
      Kotlin side.
- [ ] **Template re-theming** — an equation with no explicit `\color` takes the
      host's ink and inverts with selection/dark mode, matching
      `VinculumLabel`/`MathView`.

### Testing strategy

Reuse the machinery that already exists. The **cross-backend agreement** idea
from [#62](https://github.com/2389-research/Vinculum/issues/62) is the right
parity gate: render the shared `parity-corpus.txt` through the Android path and
diff its size-normalized ink signatures against the CoreText and FreeType/Linux
baselines (the format `MathSilicaGoldenTests` and the Linux goldens already use).
That turns "matches Apple" from an assertion into a check — and it would catch an
Android seam that silently disagrees, the same way the Linux golden net does.

---

## Staged roadmap

| Stage | Deliverable | Status |
| --- | --- | --- |
| 0 | **Swift foundation**: platform-free `DisplayList` emitter, FreeType + CoreText outliners, the C ABI, the wire format, the FreeType⊥Cairo trait split. Verified on macOS+Linux. | ✅ **done** (#86 #87 #88 #89 #91) |
| 1 | **Cross-compile to an Android `.so` and RUN it.** `VinculumLayout` → `aarch64-android` (Foundation works), FreeType cross-built for Android, the C ABI + FreeType linked into a self-contained `libVinculumAndroid.so`, and — via a JNI-in-APK harness on an emulator — **LaTeX renders on-device**, byte-identical to the Linux build. | ✅ **DONE, proven on-device** (#75 #92; harness in `android/smoke/`) |
| 2 | `VinculumMath` raw Kotlin API + display-list Canvas draw. | Kotlin/Gradle |
| 3 | **Compose `Math()`** + bitmap cache (the flagship). | Kotlin/Gradle |
| 4 | AAR packaging, ABI splits, Maven publish, Android CI. | Kotlin/Gradle |
| 5 | Classic `View`/span, then Markwon plugin. | Kotlin/Gradle |
| 6 | Cross-backend parity gate vs the corpus (#62 machinery). | Kotlin/Gradle |

**The gate is cleared.** `x = \frac{-b}{2a}` on an API-34 emulator via JNI:
`SUPPORTED OK abi=1 bytes=2681 magic=VDL1` — a valid `VDL1` display list,
**byte-for-byte the same 2681 bytes the Linux build produces**, with
`\notacommand{x}` returning nil (the never-half-broken contract, on-device). The
Swift runtime, Foundation, `Thread.threadDictionary`, and `NSLock` all work under
a real ART process. Harness + reproducible recipe: [`android/smoke/`](../android/smoke/).

### What Stage 1 actually took (the reproducible recipe)

Proven on a Linux x86_64 host + Docker. Two gotchas worth remembering:

- **Toolchain/SDK version lock.** The `swift:6.2` Docker tag floats (it is 6.2.4
  now); finagolfin's Android SDK is fixed at 6.2.0-RELEASE; Swift modules only
  import into the *exact* compiler version. Pin both to the same patch — download
  the 6.2.0 toolchain from swift.org to match the SDK.
- **FreeType isn't in the SDK sysroot.** Cross-build it (no PNG/zlib/harfbuzz/
  brotli, `-fPIC`, `-fuse-ld=lld`, `-resource-dir` pointing at the SDK's
  compiler-rt/unwind) — see [`scripts/build-freetype-android.sh`](../scripts/build-freetype-android.sh).
  It statically links into the `.so`, so nothing extra ships on device.

Then:
```
swift build --swift-sdk aarch64-unknown-linux-android24 --traits FreeTypeRaster \
  -Xcc -I<freetype-include> -Xlinker -L<freetype-lib> --product VinculumAndroid
```
produces `libVinculumAndroid.so` (ELF AArch64, DYN) exporting `vinculum_render_displaylist`,
`vinculum_free`, `vinculum_abi_version`.

The remaining Stage-1 step (**C0c**, #92) is the on-emulator JNI smoke test —
call the entry point, decode the `VDL1` buffer, confirm geometry matches
macOS/Linux, and exercise Foundation runtime behaviour (`Thread.threadDictionary`,
`NSLock`) under a real ART process, which compilation can't prove.

---

## Known risks / open questions

- **Foundation on Android.** `VinculumLayout` leans on `swift-corelibs-Foundation`
  (String, Data, the `CGFloat`/`CGPoint`/`CGRect` shims). Two specific uses to
  verify early: the parser's recursion-depth tracking via
  `Thread.current.threadDictionary` (thread-local storage under JNI-attached
  threads) and the caches' `NSLock`. Neither is exotic; both are where
  corelibs-Foundation differs from Apple's.
- **Swift Android SDK maturity.** The toolchain exists but is far less trodden
  than Apple/Linux. Stage 1 is where this is proven or disproven, and it gates
  everything after.
- **Bitmap cache eviction** on Android's tighter memory budget — port the
  count+cost bounds from `MathImageRenderer` (and its pixel-space cost fix,
  [#5](https://github.com/2389-research/Vinculum/issues/5)); do not recompute
  cost in point space.
- **`.so` size** across bundled fonts + FreeType + Swift runtime — measure, and
  consider making non-default fonts an optional artifact.
- **Text selection / accessibility.** The vector path draws, but Android
  TalkBack needs a content description — carry the same `spokenDescription` the
  Apple side stamps (`MathSpeech`) across the boundary and set it on the
  Composable/View. (The three accessibility fixes this project just shipped —
  [#6](https://github.com/2389-research/Vinculum/issues/6),
  [#7](https://github.com/2389-research/Vinculum/issues/7),
  [#26](https://github.com/2389-research/Vinculum/issues/26) — are the reminder
  to design this in from the start, not bolt it on per-surface.)

---

## Relationship to the other backends

| | Apple | Linux | **Android (planned)** |
| --- | --- | --- | --- |
| Layout | `VinculumLayout` | `VinculumLayout` | `VinculumLayout` (same) |
| Measure | CoreText | FreeType | **FreeType** |
| Glyph outlines | CoreText | FreeType | **FreeType** |
| Draw sink | CoreGraphics | Cairo → PNG | **Canvas (via display list)** |
| Cairo? | no | yes | **no** |
| Output | image/attachment | PNG | vector display list (+ bitmap cache) |

Android is closest to Linux (FreeType for measure+outline) but drops Cairo
entirely — it hands the outlines to a Kotlin `Canvas` instead of filling a Cairo
surface. That is the whole trick: the expensive, font-dependent half is already
Cairo-free and reusable.

See also: [ARCHITECTURE.md](ARCHITECTURE.md) · [LINUX.md](LINUX.md) ·
[#62 seam parity](https://github.com/2389-research/Vinculum/issues/62).
