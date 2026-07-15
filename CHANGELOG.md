# Changelog

## 1.4.1 — 2026-07-15

**The Silica dependency is now opt-in — default consumers are Silica-free.**
1.4.0 declared the Silica/Cairo dependency unconditionally, so *every*
consumer (even Apple-only, even on a stable `from:`) was forced to resolve the
whole Silica/Cairo/PureSwift graph — SwiftPM resolves declared dependencies
regardless of platform. Fixed with a **package trait** (`LinuxRaster`, default
OFF): the Silica dependency and its product links are gated behind it, so a
default resolve fetches **zero external dependencies** (verified: a downstream
consumer on both macOS and Linux pulls nothing). Opt in for the native Linux
raster backend with `traits: ["LinuxRaster"]` (or `--traits LinuxRaster`).
`Package.resolved` is now git-ignored — a committed trait-on lockfile would
re-pull Cairo even for default builds. No render logic changed.

## 1.4.0 — 2026-07-15

**Linux rendering works.** `VinculumRender` now draws a `MathScene` to a PNG
on Linux via Silica/Cairo and FreeType — the render half to go with the
already-platform-free layout stage. `MathSilicaRenderer.renderPNG(latex:…)`
is the one-call entry; all five bundled MATH fonts render.

- **How it draws.** `FreeTypeFont` loads a bundled `.otf` from bytes
  (`FT_New_Memory_Face`) and provides glyph advances, real per-glyph ink
  extents (so accents seat on the actual ink), and outlines via
  `FT_Outline_Decompose` → `PathOp`s. `MathSilicaRenderer` fills those
  outlines, rules, and strokes into a Silica `CairoContext` and encodes PNG.
  It loads fonts with FreeType directly because Silica's font-by-name path
  never runs `FcFontMatch` and so can't resolve our non-default families.
- **macOS parity.** A 20-equation corpus (`Tests/fixtures/parity-corpus.txt`)
  renders near-identically on both backends — fractions, radicals, scripts,
  matrices, cases, delimiters, binomials, the arrow family, braces, boxes,
  color, alphabets, sums, limits, Stirling numbers. Documented gaps
  (Linux, base services only): large-operator display variants, `ssty`
  optical scripts, and `ec`/`ar` accent glyphs — follow-ups, not limits.
- **New docs:** [docs/LINUX.md](docs/LINUX.md) — usage, build recipe, the
  parity report, and the known gaps. INTEGRATION/ARCHITECTURE/PRODUCT/README
  updated to reflect that Linux is now a rendering platform, not layout-only.
- Linux CI runs the render tests (all five fonts) alongside the headless
  layout suite; Apple builds are unchanged (Silica never linked).

## 1.3.0 — 2026-07-15

**Linux rendering backend — foundation.** Vinculum now builds on Linux with
the PureSwift/Silica (Cairo/FontConfig) rendering backend wired into the
graph, behind a platform-conditioned dependency so Apple platforms never
link it. This is the *foundation* — the dependency, the `Package.resolved`
pins that keep the transitive graph on a Swift-6.2-compatible commit set,
the `PlatformLinux.swift` Silica↔CoreGraphics adapter, and a CI Linux job
that builds the whole stack with Cairo/FreeType/FontConfig installed. The
actual Silica scene renderer (drawing a `MathScene` to a PNG on Linux, with
the bundled MATH fonts) lands in a follow-up; `VinculumRender` is still
inert on Linux today. Apple platforms are unchanged (258 tests green,
Silica resolved but never linked).

## 1.2.0 — 2026-07-15

**The typography + coverage release.** Optical scripts, every extensible
arrowhead, iosMath's whole example set, and SVG that draws them all — on a
Swift 6.2 toolchain. Highlights below; the API additions are source-additive
(new `MathAtomClass.inner`, new `MathOverUnder` arrow cases, `PathOp.cubic`,
and optional provider parameters), but adding cases to these public enums can
break exhaustive `switch`es in client code, and the toolchain floor moved to
Swift 6.2 — hence the minor bump, called out here for anyone pattern-matching
the scene primitives.

- **SVG renders `.glyph(id:)` — no more missing scripts or fences.** The SVG
  renderer skipped font-specific glyphs (delimiter size variants, and — after
  `ssty` — every optical superscript/subscript). It now takes an optional
  `outlines` provider and draws them as filled `<path>`s;
  `CoreTextGlyphOutlineProvider.make(font:)` supplies them on Apple (a Linux
  host can back the same seam with FreeType). `PathOp` gains a `.cubic` case
  for glyph outlines (CFF curves). Without a provider the elements are still
  skipped with a comment, so headless scenes are unchanged.

- **`ssty` optical scripts — script glyphs are redrawn, not just shrunk.**
  Superscripts, subscripts, and deeply nested indices now use the font's
  purpose-drawn `ssty` variants (heavier strokes, more open forms) instead
  of point-scaled copies of the base glyph, so a shrunk glyph keeps the
  visual weight of the surrounding text rather than thinning out — the
  optical-size compensation TeX does and iosMath does not. A new
  bounds-checked `GsubScriptStyleParser` reads the `ssty` map from the GSUB
  table (995 glyphs in Latin Modern Math; all five bundled fonts ship it),
  exposed as the `MathScriptVariantProvider` seam and drawn by glyph ID.
  Headless/Linux layout with no provider scales the base glyph exactly as
  before, so geometry tests are unchanged; the render goldens were re-blessed
  to the heavier script glyphs. This closes the last typography item on the
  roadmap.

- **Minimum toolchain is now Swift 6.2** (`swift-tools-version: 6.2`). CI
  builds on the `swift:6.2` Linux image and the newest Xcode on macOS.

- **The extensible `\x…arrow` family now draws its real head.** Every
  variant beyond `\xrightarrow`/`\xleftarrow` used to collapse to a plain
  stretchy shaft; each now draws distinctly: `\xLongrightarrow`/`\xLongleftarrow`
  as double-lined shafts (⟹ ⟸), `\xleftrightarrow` with heads on both ends,
  `\xhookrightarrow`/`\xhookleftarrow` with a tail hook (↪ ↩), `\xmapsto`
  with a tail bar (↦), the four `\x…harpoon…` as single-barb heads (⇀ ⇁ ↼ ↽),
  and `\xrightleftharpoons` as two opposed stacked harpoons (⇌ — the chemical
  equilibrium arrow). The `[under]` label also keeps its scripts now
  (`\xrightleftharpoons[k_r]{k_f}`). New `cmd-arrows.png` specimen; closes
  the last ⚠️ in COVERAGE.

- **iosMath's full example set now renders (20/20).** Probing Vinculum
  against every equation in iosMath's README found five that fell back;
  all five traced to three classic TeX features, now added:
  **infix generalized fractions** (`\over` `\atop` `\choose` `\brace`
  `\brack` — `{n \brace k}` for Stirling numbers), **old-style font
  switches** (`\bf` `\rm` `\it` `\cal` `\frak` `\bb` `\scr` `\sf`
  `\tt`, stateful to the current group, so `\vec{\bf E}` and `{\cal C}`
  work), and **`\limits`** to force operator-limit stacking
  (`\int\limits_a^b`). Also: `eqalign`/`displaylines` environment aliases,
  and a bare inline `\` degrades to a no-op instead of a fallback card.
  Fixed two bugs the new round-trip cases exposed — stateful switches
  overran `\right`/`&`/`\\` boundaries (a latent bug `\color`/`\displaystyle`
  shared), and `\brace`/`\brack` genfracs serialized their `{`/`}` fences
  into un-parseable `\genfrac{{}…}`.

- **PRODUCT.md refreshed against the shipped reality.** Version, Fira
  Math licensing, exact command counts (404+37), the p. 170-verified
  spacing and `\vec` seating in the typography table, five-font specimen
  links, test/golden counts (235/93), and a new image-asset inventory: all
  38 CI-refreshed gallery URLs cataloged with what each shows and what
  page it suits — every referenced asset verified present on the gallery
  branch. Documentation-index descriptions updated to reflect the
  illustrated docs.

- **Issue #1 investigated: the scanner was innocent.** The reported
  multi-line `\[…\]` fall-through reproduces only when a *host*
  block-parses markdown before scanning — to cmark, the stress document's
  lone `=` line is a setext-heading underline, so the span is split before
  any math pass sees it. MathScanner claims every reported shape correctly
  (verified against the verbatim block, ~1,000 fuzzed variants, and every
  historical version of the file). The scanner header now states the
  integration contract — scan raw source or blank-line-cut slices, never
  cmark block boundaries — and five new tests pin the multi-line claiming
  behavior, including `\[…\]` across blank lines (matching `$$…$$`) and
  the unterminated-opener case. The remaining fix belongs in Quoin.

- **COVERAGE.md and INTEGRATION.md caught up with the engine.** COVERAGE
  gains a figure per section and sheds stale claims (glyph assembly and
  un-gated delimiter variants shipped in 0.24 but were still listed as
  gaps; the ellipses moved to the Inner class; `\vec`'s seating documented).
  INTEGRATION's §7 sample used a dead initializer
  (`MathLayoutEngine(measure:baseSize:delimiters:)`) and omitted the
  now-required `font:` in the draw call — both fixed against the real API —
  plus four new sections for everything 1.0–1.1 added: the `MathText`
  document pipeline, `MathView`/`VinculumLabel`, server-side SVG, and
  accessibility + hit-testing. The DocC landing page gains the design
  rationale and pointers to the illustrated GitHub docs.

- **`\vec` seats its arrow on the letter.** The arrow (U+20D7, the one
  point accent whose only spelling is a combining mark) rendered off the
  base's top-right: a lone combining mark drawn as a *string* gets
  shaping-dependent ink placement, defeating attachment-point math. It now
  routes through the glyph-ID variant path, whose metrics locate the ink
  exactly; the accent-variants provider returns the base glyph when no
  wider cut fits, so the same path serves `\widehat` on narrow bases too.
  The amsmath `\dotsb`/`\dotsc`/`\dotsm`/`\dotsi`/`\dotso` join
  `\ldots`/`\cdots` as Inner atoms.
- **ALGORITHM.md and COMMANDS.md show their work.** Every major Appendix G
  rule cluster now has a CI-regenerated figure beside its audit entry
  (`alg-*.png`: radicals, accents, operators, fractions, scripts,
  decorations — via the new `AlgorithmGalleryGenerator`), and COMMANDS.md
  embeds the symbol charts under the sections they document, including the
  new `sym-inner.png` (with a sync guard so a future atom class can't
  silently drop its commands from the charts). `\mathinner` gets its own
  row in the atom-class table; stale phase-scrub artifacts cleaned up.

- **The complete TeXbook p. 170 spacing chart, including the Inner class.**
  Verified cell-by-cell against the book: operators now set tight against
  parentheses (`\log n(x)` — Op→Open is 0, we inserted a thin space),
  adjacent operators get their thin space, and thin space after punctuation
  vanishes in scripts (it is parenthesized in the chart). New
  `MathAtomClass.inner`: fractions, `\left…\right` groups, fenced matrices,
  and `\ldots`/`\cdots`/`\ddots` (plain TeX defines them as `\mathinner`)
  now attract TeX's thin Inner spaces — `f(x_1,\ldots,x_n)` finally spaces
  like the book sets it. `\mathinner{…}` classifies and round-trips.
  `MathSpacingTableTests` pins all 128 text/script cells against an
  independent transcription; goldens re-blessed knowingly.
- **ARCHITECTURE.md engages the "why" and shows its work.** New
  CI-regenerated figures (`arch-*.png`: the pair table in action, the
  delimiter stretch chain, the style lattice, graceful fallback) embedded
  beside the sections they illustrate, plus explicit answers to the
  questions a reader would ask: why two products, why an IR, why closures
  not a protocol, why three renderers and what the fourth box is.
  ALGORITHM.md gains the Appendix G sources (the TeXbook PDF and
  Jackowski's *Appendix G Illuminated*) and the classification-first
  framing.

- **Readable diagrams and specimens.** The architecture diagram is now a
  small high-level flow plus per-stage sub-diagrams (layout pipeline,
  render products) with the detail in prose — it previously crammed
  four lines into every node, and a literal `\newcommand` in a Mermaid
  label rendered as a newline escape. The font showcase (`07-fonts.png`)
  is now a scannable one-equation-per-font overview with separators and
  the five-font title; letterform detail moved to a new
  `09-font-alphabets.png` sub-specimen alongside the `08` glyph grid.

## 1.1.0 — 2026-07-15

**The integration release**: whole documents in one call, server-side SVG,
hit-testing, DocC + a runnable demo — and a fifth font.

- **Fira Math bundled** (`.firaMath`, OFL, ~180 KB) — the sans-serif
  option, visibly distinct from the serif four; pairs with SF/Helvetica
  UI text. Full per-font pipeline (constants: axis 0.280, dispOpMin 1.5),
  fixture, canary golden, showcase row.
- **`MathView` baseline alignment** — inline math sits on the text
  baseline in `HStack(alignment: .firstTextBaseline)` rows via automatic
  alignment guides derived from the rendered descent.

- **`MathSVGRenderer` — server-side math.** The platform-free renderer:
  a headless `MathScene` (the Linux default) becomes self-contained SVG —
  baseline-exact `<text>` runs, `<rect>` bars, `<path>` strokes, `\color`
  fills, optional `@font-face`-embedded font bytes. `VinculumLayout`
  already laid out on Linux; now it renders there too (Vapor, static
  sites, email pipelines).
- **Fixed: `swift run VinculumDemo` showed no window** — an SPM
  executable has no app bundle, so AppKit kept it a background process;
  the demo now promotes itself to a regular activated app.
- **Hit-testing substrate** — build the engine with
  `collectHitRegions: true` and every laid-out subtree records its
  footprint; `MathScene.hitTest(_:)` maps a scene point to the DEEPEST
  containing subtree (`MathHitRegion`: rect + node + round-tripped
  LaTeX). Tap a numerator, get the numerator and its source. Off by
  default (zero cost for plain rendering); ignored by renderers. The
  foundation for tap-to-inspect, selection, and editing.
- **DocC documentation catalog** — open the package in Xcode and build
  documentation for the curated API reference (landing page, getting
  started, the document-pipeline article), built on the existing symbol
  docs.
- **`VinculumDemo`** — `swift run VinculumDemo` opens a macOS demo: paste
  prose with math (LLM output, markdown), watch it render live, switch
  among the four bundled fonts, toggle dark rendering.
- **`MathText.attributedString(from:)` — the document pipeline.** One call
  takes a whole string of prose with embedded math and returns an
  `NSAttributedString` with the math flowed inline: all four delimiter
  styles (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`), display math on its own
  centered paragraph, document-scoped `\newcommand`/`\def` macros,
  escaped `\$` as prose, and unsupported math degrading to VISIBLE styled
  source. The API for the dominant real-world case — markdown notes, chat
  messages, and LLM output are documents with math in them, not isolated
  LaTeX strings.
- **Fixed (scanner):** inline math ending in a command (`$x \in \R$`)
  never closed — the escape-skip didn't count the escaped character as
  ink, so the closing `$` looked whitespace-preceded. Found by the new
  pipeline's macro test; pinned by new `MathScannerTests`.

## 1.0.0 — 2026-07-14

**1.0.** The promise, as the roadmap wrote it: *TeX-quality output measured
against the font's own MATH table, on every Apple platform and
Linux-headless, with a one-line integration.* What this release adds on
top of 0.25:

- **API freeze** — `MathFontServices` bundles the measurer, constants, and
  all four refinement seams (an engine can no longer be half-configured);
  `MathLayoutEngine(services:baseSize:)` is the primary initializer with a
  headless `(measure:baseSize:)` convenience; internals moved to `package`
  visibility; `MathFont.ctFont(size:)` is public so custom renderers of
  the `MathScene` IR can resolve glyph IDs; the engine is `Sendable`.
- **iOS is tested, not just compiled** — CI runs the label and font suites
  on an iOS simulator. The very first run caught a real bug: template-mode
  images drawn raw on UIKit tint to black, so dark-theme `VinculumLabel`
  ink vanished on dark canvases. Fixed (explicit theme-ink tinting).
- **The 1.0 bar, ratcheted** — the full 66-equation real-world stress
  corpus lays out with sane geometry under EVERY bundled font's complete
  pipeline; the golden comparator now checks all color channels.
- **Measured performance** — cold parse+layout+raster ~0.3 ms, warm cache
  hit ~0.7 µs, headless layout ~40 µs (Apple silicon medians, enforced as
  ceilings by `MathPerformanceTests`).

Deliberately not in 1.0 (tracked in docs/ROADMAP.md): `ssty` optical
script glyphs, width-aware line breaking.

## 0.25.0 — 2026-07-14

**The reviewed release.** A six-lens expert panel (decomposition,
correctness, concurrency, cleanliness, DRY, dead code) audited the entire
font-truth run; every critical and important finding is fixed below, the
API took its pre-1.0 breaking changes, and the fonts got their showcase
and documentation.

Review backlog completed + the font showcase.

- **`MathNode.children`** — the canonical child traversal; the three
  hand-rolled diagnostics walks collapse onto it (−115 lines; a new node
  case now touches one accessor plus the semantic visitors).
- **Fixed: `\displaystyle` inside a text fraction rendered larger than
  the surrounding text** — forced styles now scale from a propagated
  size anchor that part scales move with them.
- **Pre-1.0 API cleanup** — deprecated `MathConstants` enum deleted;
  `fractionNum/Denom…` constants renamed to the full OpenType spec
  spelling; `italicsCorrection` spelling unified; dead tuning constants
  removed.
- **Font showcase** — new CI-published `07-fonts.png` gallery poster
  (the same equations in all four bundled fonts, including the italic
  alphabets and script faces where they differ most), a README Fonts
  section, and a comprehensive [docs/FONTS.md](docs/FONTS.md) (what each
  font is for, per-font metric differences, custom-font requirements,
  exactly what Vinculum reads from a MATH table, licensing).
- **Docs refresh** — ARCHITECTURE.md rewritten to the current design
  (font-parsed constants, the full provider stretch chain, the engine
  factory); version references brought current; implementation-phase
  bookkeeping and competitor comparisons removed from reference docs
  (they remain in the roadmap/plan, where they're the subject).
- Hardening: `VinculumLabel` coalesces configuration into one render
  (with synchronous flush on read); subscript positions clamped against
  extreme kerns; script-descent ratio guarded against malformed fonts;
  the per-font CTFont cache is bounded; shared test scaffolding replaces
  13 copies of mocks/fixture loaders.

Expert-review fixes (six-lens panel: decomposition, correctness,
concurrency, cleanliness, DRY, dead code — findings tracked from the
0.24.0 review).

- **Fixed: parser stack overflow on brace-free recursive commands**
  (`\sqrt\sqrt\sqrt…` ×10k crashed; the pre-scan guard only counted
  braces). A thread-local runtime depth counter in `parseAtom` now bounds
  ALL recursion; past it, input degrades to fallback. New fuzz probes pin
  the class.
- **Fixed: cached-image data race** — the Phase 9a accessibility stamp
  mutated the shared cached image on every call from any thread. Speech
  is now computed once per cache miss, stored on the entry, and stamped
  pre-publication; cache hits no longer re-parse (restoring the cache's
  contract) and `MathView` no longer parses twice per body evaluation.
- **New `MathImageRenderer.rendered(latex:…) → RenderedMath`** — image +
  baseline descent + spoken description; `VinculumLabel`/`MathView` build
  on it instead of fishing images out of attachment strings.
- **Fixed: CI galleries rendered through a crippled engine** — the
  generators injected only a measurer, so the published posters showed
  the pre-font-truth pipeline (scaled fences, polyline radicals, no
  kerning). New `MathLayoutEngine.make(font:baseSize:)` factory is the
  one way render-side code builds engines; adopted everywhere.
- **Fixed: `\not a` round-tripped to `\nota`** (unsupported); negation
  now serializes braced.
- **Fixed: `\cfrac` used the numerator gap minimum for the denominator;
  `\underline` used the overbar constants** — both invisible in Latin
  Modern (equal values) but divergent in other fonts.
- **Hardened: coverage format-2 parsing caps total expansion at 65,536
  glyphs** — crafted range records could previously force a multi-GB
  allocation before validation ran.
- **Breaking: `MathSceneRenderer.draw` requires an explicit `font:`** —
  the `.latinModern` default silently drew wrong glyphs for scenes
  measured with any other font.

## 0.24.0 — 2026-07-14

**The font-truth release.** Everything the OpenType MATH table knows,
Vinculum now uses: all 56 layout constants, per-glyph italic corrections,
accent attachment points, cut-in kerning staircases, size-variant ladders,
and glyph assemblies — parsed from the live font at load, for four bundled
fonts or any OTF you supply. Plus the TeX style lattice, drop-in views,
LaTeX round-trip, locatable parse diagnostics, spoken math for VoiceOver,
and a fuzz-hardened pipeline. The phase-by-phase story is below; the
rule-by-rule audit lives in docs/ALGORITHM.md.

Phase 5c + 8c + hardening: wide accents, error ranges, fuzz.

- **Wide accents from the font** — `\widehat`/`\widetilde`/`\widecheck`
  walk the MATH table's HORIZONTAL variant ladder (via the combining-mark
  glyphs that carry it) and pick the widest drawn cut not exceeding the
  accentee (TeX Rule 12's successor walk), centered on the attachment
  point; scaling remains the headless fallback. `GlyphMetrics` gains
  `inkLeft` (default 0) to place combining-mark ink.
- **`MathParser.diagnostics(for:parsing:)`** — one `MathParseIssue` per
  unsupported token in source order, each with the snippet, a message,
  and its `Range<String.Index>` (duplicates map to successive
  occurrences; macro-rewritten snippets report nil rather than a wrong
  range). The editor squiggle substrate iosMath's message-only errors
  can't provide.
- **Deterministic fuzz suite** — 4,000 grammar/mutation inputs plus
  depth attacks (5,000 open braces, 2,000 nested `\frac{`): the whole
  pipeline never crashes, never emits non-finite geometry.

Phase 9a: spoken math — VoiceOver reads the equation, a native-library
first.

- **`MathSpeech.describe(MathNode)`** generates ClearSpeak-style utterances
  from the same tree that was typeset ("x equals the fraction minus b plus
  or minus the square root of b squared minus 4 a c, over 2 a"), covering
  fractions (with "1 half"-style simple forms), roots, scripts
  (squared/cubed/to-the-power), fences, matrices (row-by-row), cases,
  binomials ("n choose k"), accents ("vector v", "x hat"), operators, and
  ~80 spoken symbol names. Invisible nodes (spacing, phantoms) are silent.
- Wired everywhere: `VinculumLabel` and `MathView` expose it as their
  accessibility label, and every `MathImageRenderer` attachment image
  carries it — so math in an `NSTextView`/`UITextView` reads aloud too.

Phase 8 (a+b): round-trip and drop-in views.

- **`MathNode.toLaTeX()`** — every node kind serializes back to LaTeX,
  proven render-equivalent (scene-identical) and idempotent over a
  23-expression corpus. The substrate for copy-as-LaTeX, editing, and
  spoken-math accessibility.
- **`VinculumLabel`** (AppKit/UIKit) — `label.latex = "…"` and done:
  alignment, content insets, font/theme/size, intrinsic sizing, and
  opt-in `displayErrorInline` (OFF by default — unsupported input renders
  nothing, preserving the never-half-broken contract; `isRendered` tells
  the host to use its fallback).
- **`MathView`** (SwiftUI) — `MathView("e^{i\pi}+1=0").mathFont(.pagella)`
  with `.inlineStyle()`, `.mathTheme()`, `.mathSize()` modifiers.

Phase 7: multi-font — four bundled math fonts, or bring your own.

- **`MathFont` is now a value you pick**: `.latinModern` (default),
  `.termes` (Times companion), `.pagella` (Palatino companion), and
  `.stixTwo` — plus `MathFont(url:)` for any OTF with a MATH table. Pass
  `font:` to `MathImageRenderer.attachmentString` / `MathSceneRenderer.draw`
  or build providers with `CoreTextMeasurer.make(font:)` et al. Every
  font's MATH table (constants, glyph typography, variants, assemblies)
  is parsed once at load; caches key on the font.
- **STIX Two lights up cut-in kerning for real** — it ships MathKernInfo
  for 233 glyphs, so Phase 3's staircase kerning now runs on live font
  data, a first for native math rendering.
- Per-font raw MATH-table fixtures committed (Linux-testable) and
  per-font canary goldens (`canary-termes/pagella/stixtwo`) pin the same
  equation under each font. Existing Latin Modern goldens: zero churn.
- Fonts are GUST-GFL (TeX Gyre) / OFL (STIX Two) licensed; licenses ship
  in the bundle beside the fonts.

Phase 6: display operators from the font + TeX fence sizing.

- **Display-size operator variants** — in display style, ∑ ∏ ∫ and every
  large operator swap in the font's bigger cut (`DisplayOperatorMinHeight`,
  1.3 em in LM Math), centered on the math axis, replacing the 1.35×
  scale (which survives headless). `\int` in display is finally the tall
  slanted integral.
- **Rule 13a limit clearances** — stacked limits attach at
  `max(Upper/LowerLimitGapMin, BaselineRiseMin − d(sup) / DropMin − h(sub))`
  instead of a single stack gap.
- **Rule 19 fence sizing** — `\left…\right` heights follow TeX's
  `\delimiterfactor`/`\delimitershortfall` formula (ψ from the axis,
  ≥ max(2ψ·0.901, 2ψ − 5pt)), so fences carry TeX's proportions instead
  of enveloping the body completely.
- 4 new tests (`MathOperatorSizingTests`); 32 goldens re-blessed.

Phase 5b: the radical is the font's √ glyph.

- **Font surd** — `\sqrt` draws Latin Modern's radical glyph via size
  variants (nested radicals step through purpose-drawn cuts exactly like
  TeX), assembling from parts beyond the largest variant; glyph excess
  splits into the radicand clearance (Rule 11's ψ centering). The
  hand-stroked polyline remains only as the headless/no-provider fallback.
- **Shortfall heuristic** (`Construction.bestVariant`): a variant within
  3% of the target beats a ≥1.3× jump, keeping signs snug — applied to
  all delimiter variant selection.
- **Font-true degree placement** — `RadicalKernBeforeDegree` (0.278 em),
  `RadicalKernAfterDegree` (−0.556 em, tucking the sign back over the
  degree), and the 60% bottom-raise replace the hand proportions in the
  glyph path.
- 4 new tests (`MathRadicalTests`); 10 radical goldens re-blessed.

Phase 5a: glyph assembly — arbitrarily tall fences from font parts.

- **`MathAssemblySolver`** (pure, Linux-tested): OpenType GlyphAssembly
  placement — fewest extender repeats whose reachable range covers the
  target, joint overlaps opened equally from the maximum, respecting
  `MinConnectorOverlap`; degenerate extenders (advance ≤ 0) rejected at
  parse. `MathTableParser.variants` now reads the full `MathVariants`
  sub-table (ladders + assemblies + minConnectorOverlap), fixture-tested.
- **The stretch chain is complete**: size variants → glyph assembly →
  scaling. A fence taller than the largest variant (~3 em) is now BUILT
  from the font's caps and extenders at constant stroke weight (new
  `assembly-tall` golden: a 9 em paren). Assemblies render as stacked
  glyph-ID elements; no scene format change.
- **The `()[]{}`-only gate is gone** — `MathVariantTable` is backed by the
  fixture-tested parser (the old in-place parser mis-mapped some coverage),
  so `⟨ ⟩ ‖ ⌈ ⌉ ⌊ ⌋` and every other covered delimiter now step through
  true size variants (new `tall-angle` golden). `\vec`/accent marks now
  sit at the font's attachment points (combining-mark data honored).
- 8 new tests (`MathAssemblyTests`); goldens re-blessed after review.

Phase 4: accents placed by the font.

- **`topAccentAttachment` skew** — the accent's x position is the base
  glyph's attachment point minus the accent glyph's own (advance-center
  fallback), so `\hat{f}` leans with the letter. Strictly better than
  TeX's `\skewchar` mechanism.
- **`AccentBaseHeight` seat** — the accent hugs the base's ink but never
  sinks below the font's designed accent height (the constant was defined
  and unused since 0.x; now honored: δ = min(h, AccentBaseHeight)).
- **Script promotion** — `\hat{f}^2` attaches the ² to the f under the
  hat's reach (TeX Rule 12's single-character accentee rule), instead of
  scripting the whole accent box.
- 4 new geometry tests (`MathAccentTests`).

Phase 3: per-glyph script typography — italic correction and cut-in
kerning. No native math library has the latter.

- **Italic correction (Rules 17/18f/13a)** via a new injected
  `MathGlyphTypographyProvider` (backed by the font's parsed
  MathItalicsCorrectionInfo; `CoreTextTypographyProvider` on Apple,
  optional/neutral headless): superscripts shift right by δ while
  subscripts stay at the advance (`f^2_3` splits correctly), large
  operators tuck the subscript δ LEFT under the overhang (`\int_a^b` —
  ∫'s δ is 0.332 em), and stacked limits split ±δ/2.
- **The full Rule 18 ladder**: σ₁₈/σ₁₉ baseline drops for composite nuclei
  (fractions, fenced groups), `SuperscriptBottomMin`/`SubscriptTopMax`
  clamps, and 18d–e collision resolution via `SubSuperscriptGapMin` +
  `SuperscriptBottomMaxWithSubscript` (replacing the 4·ruleThickness
  heuristic). `SpaceAfterScript` now trails the scripts (it preceded them).
- **MathKernInfo cut-in kerning**: scripts sample the base glyph's corner
  kern staircase at their near edge — mechanics live and tested with
  synthetic data (LM Math ships no MathKernInfo; STIX Two, arriving with
  multi-font support, does).
- 7 new geometry tests (`MathScriptTypographyTests`); 19 goldens
  re-blessed after visual review.

Phase 2: the TeX style lattice — plus a long-standing fence-rendering bug
found and fixed. (Phases 0–1 below.)

- **`MathStyle` (display/text/script/scriptScript)** replaces the internal
  `display: Bool`, giving the full eight-style lattice with the existing
  cramped flag. TeX successor maps (`scriptStyle`, `fractionStyle`) thread
  through every builder. `MathNode.mathStyle` now carries a `MathStyle`
  (breaking for exhaustive matchers).
- **Style-true geometry** — medium/thick inter-atom spacing vanishes in
  script styles (TeX ch. 18): `\sum_{i=1}^{n}`'s lower limit tightens.
  Nested scripts land on TeX sizes: 70% then the 50% scriptscript floor,
  not 0.7ⁿ compounding shrink. Fractions use the font's Rule 15b–d
  constant pairs (`FractionNum/DenomShift` + `GapMin`, display vs text;
  stacks use the `StackTop/Bottom` pairs) — the 1.35 display boost and the
  hand-tuned `ruleGap`/`atopGap` retire. `\cfrac` uses the display pair.
- **`\displaystyle` / `\textstyle` / `\scriptstyle` / `\scriptscriptstyle`**
  — stateful to the rest of the group (like stateful `\color`), forcing
  both the style and the size it implies. `\genfrac`'s style argument now
  honors all four values (2/3 properly shrink).
- **Fixed: variant fences drawn at the previous text run's position.**
  `CTFontDrawGlyphs` positions go through the context's text matrix, which
  `saveGState` does not protect — every MATH-variant delimiter drawn after
  a glyph run landed shifted right (visible as `\binom`'s right paren
  overlapping the following `=` since 0.23). The renderer now resets the
  text matrix; every fenced golden improved.
- 33 golden fixtures re-blessed after visual review; 8 new geometry tests
  (`MathStyleTests`) pin the lattice headless.

Phase 1: MATH-table constants parsed from the font (and Phase 0's docs +
fixtures below).

- **`MathTableParser`** (VinculumLayout, platform-free): parses the raw
  `MATH` table's full 56-value `MathConstants` sub-table into
  `MathFontConstants`, and the `MathGlyphInfo` sub-table — per-glyph italic
  corrections (1,002 glyphs in LM Math), `topAccentAttachment` (2,475),
  extended shapes (250), and MathKernInfo cut-in kern staircases — into
  `MathGlyphInfo`. Bounds-checked, `nil` on malformation, fixture-tested
  headless against committed table bytes and fontTools ground truth.
- **The engine now carries the constants as data.**
  `MathLayoutEngine(…, constants:)` defaults to the `.latinModern` preset;
  `MathImageRenderer` passes `MathFont.constants`, parsed once from the
  live bundled font. The static `MathConstants` enum is deprecated. This is
  the keystone for multi-font support (roadmap Theme F).
- **The parser oracle caught three transcription bugs** in the old
  hardcoded constants, now fixed font-true: `spaceAfterScript` 0.041 →
  **0.056** (scripts breathe slightly more), `radicalVerticalGap` 0.148 was
  the *display* value — text style now uses the font's **0.050** (inline
  radicals hug their radicand like real TeX), and `stackGapMin` 0.150 →
  **0.120** (stacked limits sit slightly tighter). 36 golden fixtures
  re-blessed after visual review; `MathGlyphInfo` is parsed but not yet
  consumed (that's Phases 3–4: italic correction, cut-in kerning, accent
  attachment).

Phase 0 of the best-in-class plan (docs + fixtures, no behavior change).

- **Roadmap + phased implementation plan.** New
  [docs/ROADMAP.md](docs/ROADMAP.md) (release-level: font truth → style
  lattice → script typography/cut-in kerning → accents → glyph assembly →
  multi-font → DX → accessibility/firsts) and
  [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) (phase-by-phase,
  test-first), grounded in a mechanism-level audit against iosMath v2.5.0.
- **docs/ALGORITHM.md** — honest rule-by-rule TeX Appendix G audit of the
  current engine (Implemented / Partial / Deviation / ABSENT), with a
  constants ledger and a gap→phase map. The doc the README answers to.
- **Raw MATH-table fixtures.** `Tests/fixtures/math-table/
  latinmodern-math.bin` (the font's raw `MATH` table), regenerated via the
  env-gated `MathTableFixtureExtraction` test
  (`VINCULUM_UPDATE_MATH_FIXTURES=1`), sanity-checked headless by
  `MathTableFixtureTests` — the Linux-testable ground truth Phase 1's
  constants/glyph-info parser will be developed against.
- **README honesty pass** — the metrics claims now say "test-pinned
  transcription of Latin Modern's MATH-table values" (font-parsed at
  runtime is Phase 1), and the iosMath comparison names where iosMath is
  currently ahead.

## 0.23.0 — 2026-07-13

Delimiter size-variants (the big one) + `\cancelto`.

- **Discrete delimiter size-variants from the font's MATH table.** Tall
  `\left…\right` fences now use the font's purpose-drawn size-variant glyphs
  (constant stroke weight) instead of continuous point-scaling (which fattened
  strokes). New: a runtime OpenType **MATH**-table parser
  (`MathVariantTable` reads `MathVariants` → vertical glyph construction), a
  glyph-by-ID scene primitive (`MathScene.glyph(id:)`), and an injected,
  optional `MathDelimiterProvider` seam (nil on Linux/headless → the old
  scaling path, so no regression). Engaged for clearly-tall fences of the
  verified delimiters `( ) [ ] { }`; other delimiters and short stretches use
  scaling. (Extensible assembly for arbitrarily-tall fences, and the remaining
  delimiters, are the staged follow-up.)
- **`\cancelto{target}{expr}`** — strike-through with a raised target label.

`\sideset` and `\mathchoice` remain a low-frequency tail. All CIs green.

## 0.22.0 — 2026-07-13

Box & rule decorations (Batch 15).

- **`\fbox`** — framed box (like `\boxed`).
- **`\colorbox{bg}{…}`** / **`\fcolorbox{border}{bg}{…}`** — filled background
  box, optionally framed (new `.colorbox` node; background rule drawn behind
  the content).
- **`\rule{w}{h}`** — a solid filled rectangle at explicit em/pt lengths (new
  `.ruleBox` node).
- **`\raisebox{shift}{…}`** — vertically shift the content (new `.raised`
  node).

`\sideset` and `\mathchoice` remain a low-frequency tail. +3 nodes.

## 0.21.0 — 2026-07-13

Over/under constructs & accents (Batch 14).

- **`\overbracket` / `\underbracket`** — square-bracket (⎴/⎵) over/under the
  content, with `^`/`_` labels.
- **`\overparen` / `\underparen`** — parenthesis-arc (⏜/⏝) over/under.
- **`\widecheck`** — stretchy check accent.

New `MathOverUnder` cases + `horizontalBracket`/`horizontalParen` stroke
helpers; `MathAccent.widecheck`. (`\cancelto`, `\utilde`, harpoon accents are a
small remaining tail.)

## 0.20.0 — 2026-07-13

True **`\cfrac`** continued fractions. Parts now lay out at full display size
(no per-level shrink) with the denominator aligned — `\cfrac[l]` / `\cfrac[r]`
/ default center. New `.cfrac(numerator:denominator:align:)` node, isolated
from the shared `\frac`/`\genfrac` path. Goldens for the nested continued
fraction regenerated (now full-size at every level).

## 0.19.0 — 2026-07-13

Operator & atom-class machinery (Batch 12).

- **Atom-class overrides:** `\mathbin \mathrel \mathop \mathord \mathopen
  \mathclose \mathpunct \mathinner` force the inter-atom spacing class of a
  subexpression (new transparent `.classified` node; `\mathop` also takes
  display limits).
- **`\pmb`** (poor-man bold) → rendered bold.
- **Stateful `\color{name}`** — the one-arg form now applies to the rest of the
  current group (`{\color{red} a+b} + c`), in addition to the localized
  `\color{name}{body}` / `\textcolor{name}{body}` forms.

`\DeclareMathOperator` is a planned follow-up (needs a macro-table branch).
+2 tests (117 total).

## 0.18.0 — 2026-07-12

Environment fixes (Batch 13) — two real parser bugs + two new environments.

- **`alignat{n}` bug fixed.** The mandatory `{n}` column-count argument was not
  consumed, so it leaked into the first cell. Now consumed (like `alignedat`).
- **`matrix*[r]` / `pmatrix*[r]` bug fixed.** The optional `[l|c|r]` alignment
  bracket leaked as literal `[ r ]` into cell 1. Now consumed and applied —
  uniform column alignment via the array path (great for signed numeric
  matrices). The `.array` alignment falls back to the last spec entry, so one
  entry covers all columns.
- **`gathered`** and **`multline`/`multline*`** now lay out aligned (were
  falling through to a centered grid).

+2 tests (115 total).

## 0.17.0 — 2026-07-12

Symbol sweep (Batch 11) — **157 new symbols** with correct TeX atom classes
(so inter-atom spacing is right), taking the table to ~400 commands.

- **Relations:** `\leqslant \geqslant \eqsim \approxeq \lessapprox \gtrapprox
  \lll \ggg \leqq \geqq \subseteqq \supseteqq \Subset \Supset \frown \smile
  \vDash \Vdash \multimap \trianglelefteq \pitchfork …`
- **Negations:** `\nleq \ngeq \nless \ngtr \nsim \ncong \nprec \nsucc \nvdash
  \subsetneqq \lneq \gneq \lnsim \gnsim \ntrianglelefteq …`
- **Arrows:** `\rightsquigarrow \twoheadrightarrow \dashrightarrow
  \circlearrowleft \curvearrowright \leftrightarrows \Rrightarrow \longmapsto
  \nrightarrow \looparrowright …`
- **Harpoons:** `\leftharpoonup \rightharpoondown \upharpoonright
  \leftrightharpoons …`
- **Binary ops:** `\ltimes \rtimes \Cap \Cup \barwedge \veebar \boxdot
  \circledast \dotplus \lessdot \gtrdot \intercal …`
- **Letterlike:** `\hslash \Bbbk \digamma \varkappa \varrho \lozenge
  \blacktriangle \measuredangle \sphericalangle \beth \gimel \daleth …`

+3 fixtures; all render with real font glyphs (no tofu).

## 0.16.0 — 2026-07-12

Resolves three previously-deferred items (planned by a specialist squad).

- **`\middle`.** `\left( … \middle| … \right)` splits the body into segments and
  stretches every fence — left, each `\middle`, right — to the common height:
  set-builder `\left\{ x \mid P \right\}`, divided forms, conditional
  probability. New `.fenced(fences:segments:)` node; the no-`\middle` path still
  emits `.delimited` unchanged (zero regression).
- **`\operatorname*` limits.** A starred custom operator now stacks its scripts
  as under/over limits in display (`\operatorname*{Fix}_x`, `\operatorname*{ess\,sup}`),
  via a transparent `.limitsOperator` wrapper — no change to `.functionName`.
- **`\tag{…}` / `\tag*{…}`** (+ `\notag`/`\nonumber` no-ops). The tag is appended
  inline after a `\qquad` (`= r^2 \qquad (3.1)`). True flush-right / auto-numbering
  are host concerns (need the column width) and remain out of scope by design.

+8 tests (113 total). New public node cases `.fenced`, `.limitsOperator`.

## 0.15.0 — 2026-07-12

`\smallmatrix` (Batch 10) — script-size inline matrices, e.g.
`\left(\begin{smallmatrix} 1 & 0 \\ 0 & 1 \end{smallmatrix}\right)`. Stress
corpus grows to 66 equations (a "New notation" showcase page) at 100% native.

## 0.14.0 — 2026-07-12

General fractions & arrow variants (Batch 9).

- **`\genfrac{ldelim}{rdelim}{thickness}{style}{num}{denom}`** — the general
  fraction form: custom delimiters, rule on/off (`0pt` → no rule, e.g. a
  Legendre bracket `\genfrac{[}{]}{0pt}{}{n}{k}`), and forced style.
- **More stretchy arrows:** `\xLongrightarrow \xLongleftarrow \xhookrightarrow
  \xhookleftarrow \xmapsto \xrightharpoonup \xrightharpoondown \xleftharpoonup
  \xleftharpoondown \xleftrightarrow \xrightleftharpoons` — all take `{over}` /
  `[under]` labels (approximated to a stretchy left/right shaft).

+2 fixtures.

## 0.13.0 — 2026-07-12

Math-in-text and symbol fill-in (Batch 8).

- **Math inside `\text{}`.** `$…$` segments in a text body now render as math:
  `\text{$n$ terms}` gives an italic `n` then upright " terms";
  `\text{for all $\epsilon>0$}` embeds the inequality. (Closes the gap the
  stress-test surfaced where `$n$` rendered literally.)
- **More symbols:** `\land \lor \gets \colon \rightleftharpoons \triangleq
  \coloneqq \bigstar \dotsb \dotsc \dotsm` — with correct atom classes
  (`\colon` is punctuation, `\land`/`\lor` binary).

+1 test (109 total).

## 0.12.0 — 2026-07-12

Vector / over-arrows (Batch 7).

- **`\overrightarrow` / `\overleftarrow` / `\overleftrightarrow`** draw a
  stretchy arrow over the content, sized to its width — the vector notation
  (`\overrightarrow{AB}`), with correct single- or double-headed arrows.
- **`\underrightarrow` / `\underleftarrow` / `\underleftrightarrow`** draw the
  same beneath the content.

New `MathOverUnder` cases + a shared `horizontalArrow` stroke helper. +1
fixture.

## 0.11.0 — 2026-07-12

Spacing & box commands (Batch 6).

- **Named spaces:** `\thinspace \medspace \thickspace \negthinspace
  \negmedspace \negthickspace \enspace \>`.
- **Explicit lengths:** `\hspace{…}` / `\kern…` (em/pt) and `\mspace{…}` /
  `\mkern…` (mu), parsed braced or unbraced (`\mkern18mu`), converted to em.
- **`\smash`** (keep width, zero height/depth), **`\mathstrut`** (invisible
  paren-height strut), and the lap boxes **`\mathrlap` / `\mathllap` /
  `\mathclap`** (zero-width right/left/center overlap).

New `MathDecoration` cases `.smash`/`.rlap`/`.llap`/`.clap`. +5 tests
(108 total).

## 0.10.0 — 2026-07-12

Coverage expansion (Batch 5) — beyond the original roadmap.

- **Extended big operators.** `\iiint`, `\iiiint`, `\oiint`, `\oiiint`,
  `\coprod`, `\biguplus`, `\bigsqcup`, `\bigvee`, `\bigwedge`, `\bigoplus`,
  `\bigotimes`, `\bigodot` — all with the large-operator class (correct
  spacing) and display-limit stacking.
- **`\cancel` / `\bcancel` / `\xcancel`.** A diagonal strike (forward,
  backward, or both) across the content, drawn over the kept base — the
  fraction-cancellation notation.
- **`\not`.** Slashes the following atom, so `\not=` → ≠, `\not\in` → ∉,
  `\not\subset` → ⊄ — works over *any* relation, not just precomposed ones.

New `MathDecoration` cases `.cancel`/`.bcancel`/`.xcancel`/`.negation`. +3
golden fixtures.

## 0.9.0 — 2026-07-12

Structural `array` (Batch 4) — completes the four-batch typesetting roadmap.

- **Column specs** `{l c r}` are parsed into per-column alignment (previously
  read and discarded), so array columns align left / center / right.
- **Vertical rules** from `|` in the spec are drawn at the right boundaries,
  including edge rules (with outer padding) and multiple interior rules.
- **Horizontal rules** `\hline` (full width) and `\cline{i-j}` (column range)
  are drawn at their row boundaries.
- Together these give **augmented matrices** `[A | b]`, **bordered/truth
  tables**, and rule-separated systems — e.g.
  `\left[\begin{array}{ccc|c} … \end{array}\right]`.

Modeled as a new `ArraySpec` carried by a `.array(ArraySpec)` `MathMatrixStyle`
case, so `.matrix` layout stays shared. +6 tests (103 total); stress corpus
grows to 59 equations (a "Tables, arrays & linear systems" page) at 100% native.

## 0.8.0 — 2026-07-12

Deep TeX-fidelity batch (Batch 3) — the subtle metrics a typographer notices,
straight from Appendix G. Rendering changes; goldens regenerated and each
change verified by eye.

- **Binary/unary reclassification** (TeXbook p.170). A `Bin` atom with no left
  operand — at the start of a list or after Bin/Op/Rel/Open/Punct — is really a
  unary sign and becomes `Ord`; a `Bin` just left of a Rel/Close/Punct does
  too. So `x = -1` now sets a thick space after `=` and a tight unary minus,
  instead of medium space around the minus.
- **Cramped style.** Superscripts sit lower in cramped contexts — denominators,
  radicands, and subscripts — using the font's σ15 (`superscriptShiftUpCramped`).
  The exponent in `√(x²)` or a fraction's denominator now rides lower than in a
  numerator, matching TeX. Threaded through the engine like `\color`
  (numerator uncramped / denominator cramped; superscript uncramped / subscript
  cramped; radicand cramped).
- **TeX fraction shift-model.** Numerator and denominator are positioned by a
  nominal baseline shift (the font's `fractionNumeratorShiftUp` /
  `DenominatorShiftDown`, previously declared-but-unused), increased only as
  needed to keep a minimum gap from the rule — so a short `1` and a deep
  numerator share a stable baseline, instead of floating a fixed gap above the
  bar.
- **Axis-centered delimiters.** Auto-sized `\left…\right` fences are now
  centered on the math axis and sized to cover the body symmetrically about it
  (TeX measures each side from the axis), so an off-baseline body gets a fence
  tall enough on both ends. (Discrete size-variant selection is a follow-up —
  see COVERAGE.md.)

+11 tests (99 total). No new commands — pure fidelity.

## 0.7.0 — 2026-07-12

Common-commands batch (Batch 2 of the typesetting roadmap) — the constructs
real math reaches for, prioritized by the stress-corpus coverage audit.

- **`\pmod` / `\bmod` / `\pod`.** `a \equiv b \pmod{n}` renders `(mod n)` with
  the correct leading space; `\bmod` is a binary operator (`a \bmod n`). These
  were the *only* two commands the 46-equation stress corpus couldn't render —
  the corpus now renders **100% natively**.
- **`\dfrac` / `\tfrac` / `\dbinom` / `\tbinom` force their style.** A new
  `.mathStyle` node forces display or text style regardless of context, so
  `\dfrac` is large inline and `\tfrac` is small in a display block.
- **`\big \Big \bigg \Bigg` (+ `l`/`r`/`m`) actually enlarge** the delimiter to
  1.2 / 1.8 / 2.4 / 3.0× the base size, centered on the math axis, with the
  suffix selecting opening/closing/relation spacing (new `.bigDelimiter` node).
- **More `\left…\right` fences:** `\lceil \rceil \lfloor \rfloor`, `\uparrow`
  `\downarrow` `\Uparrow` `\Downarrow` `\updownarrow`, and `\backslash` now
  auto-size (previously fell back to `(`).
- **`\operatorname*`** parses correctly (renders upright; `*` limit-stacking is
  a follow-up) instead of degrading.

**Quantum-information corpus + fixtures.** Added an entanglement page to the
stress corpus (Bell/GHZ states, density matrices, the CHSH inequality with the
Tsirelson bound, Schmidt decomposition, von Neumann entropy) and promoted
several to golden fixtures. Corpus is now 55 equations at 100% native coverage.

+17 tests (94 total). New public node cases: `.mathStyle`, `.bigDelimiter`.

## 0.6.0 — 2026-07-12

Everyday-correctness batch (from the typesetting review) — the fidelity gaps
that bite common writing. Rendering changes; goldens regenerated and visually
verified.

- **Named operators stack their limits.** `\lim`, `\max`, `\min`, `\sup`,
  `\inf`, `\det`, `\gcd`, `\limsup`, … now put their limit *underneath* in
  display style (`\lim_{x\to0}`), like TeX. They parse to function names,
  which the stacked-limits path previously missed.
- **Integrals keep side-scripts.** `\int`, `\oint`, `\iint` no longer
  over-stack in display — they default to `\nolimits` (scripts to the side),
  while `\sum`-class operators still stack. Limit-taking is now decided per
  operator, not by node shape.
- **Primes render as raised glyphs.** `f'`, `f''`, `f'''` become raised,
  coalesced primes (`′`) instead of baseline apostrophes; `f'^2` merges the
  prime with the explicit exponent.
- **Spaces survive inside `\text{…}`.** `\text`, `\mathrm`, `\operatorname`,
  `\textrm` bodies are captured verbatim by the tokenizer, so `\text{if } x`
  keeps its space (and nested braces).
- **Scripts clear tall bases and can't collide.** Super/subscript shifts now
  rise to clear a tall nucleus's ink (an exponent on `(…)²` rides above the
  paren) and a minimum gap is kept between a coexisting super- and subscript
  (TeX Appendix G).

Internal: the `^`/`_`/prime attachment is now one shared helper (was
duplicated across `parseRow` and `parseAtomWithScripts`). +6 tests (83 total).

## 0.5.0 — 2026-07-12

Performance, platform-fitness, and robustness pass, informed by a four-lens
expert review (Apple-platform architecture, performance, Swift/API quality,
typesetting correctness).

**Performance** (realistic load = a live editor re-projecting hundreds of
equations per keystroke):
- **Cache lookup now precedes parsing.** The render cache key is fully
  determined by the arguments, so a hit — positive *or* negative — costs no
  parse or layout. Previously every cache hit re-parsed the LaTeX (~15× on a
  matrix), and unsupported input re-parsed on every re-projection forever;
  unsupported/degenerate results are now remembered as negative entries.
- **Glyph measurement is memoized.** The parser emits one node per character,
  so an N×N matrix of identical entries re-measured each glyph N² times
  (~95% redundant, ~200 CoreText calls for an 8×8 of 15 unique glyphs). A
  shared, lock-guarded `(text, size, mono)` cache turns those into dictionary
  hits (~5× on matrix/large-expression cold renders).
- **CTFont creation is cached** by size (used by both measurement and drawing).

**Platform fitness:**
- **Tintable template images.** When a scene has no explicit `\color`, the
  attachment is emitted as a template image, so selected math inverts with the
  surrounding run and dark-mode adapts without a host re-render. Colored math
  stays baked. (`MathScene.hasExplicitColor` is new public API.)
- **iOS dynamic-ink correctness.** Rasterization pins the trait style so a
  dynamic `UIColor` ink resolves to the variant matching the theme's canvas,
  matching the macOS path.
- **Bounded render cache** (count + pixel-byte cost) instead of memory-pressure
  eviction only.
- **Consistent color across platforms.** `\color` builds its `CGColor` directly
  in sRGB, so AppKit and UIKit render an identical color.

**Robustness / quality:**
- The accent parser no longer force-unwraps `MathAccent(command:)` — it
  degrades to `.unsupported` if the case list and initializer ever drift,
  honoring the never-crash contract every other command already follows.
- Removed a dead `max` branch in the fraction descent and an orphaned doc
  comment; zero build warnings.

Public API additions: `MathScene.hasExplicitColor`, `MathElement.color`.

## 0.4.0 — 2026-07-12

**Every magic number is now a named font parameter.** Following Knuth's rule
that math typesetting reads its constants from the font, never from literals
(Appendix G of *The TeXbook*), the ~35 hand-tuned multipliers scattered
through the layout builders were replaced:

- Values with an OpenType MATH-table equivalent now read the font's real
  number from `MathConstants` — the axis (0.26→**0.250**), fraction/radical/
  overbar rules (0.045→**0.040**), script scale (0.68→**0.70**), superscript
  raise (0.42→**0.363**), subscript drop (0.20→**0.247**), radical gap
  (0.12→**0.148**), overbar gap (0.08→**0.120**). Rendering now matches what
  real LaTeX produces; goldens regenerated.
- Inter-atom spacing is expressed in `mu` (1/18 em) via `MathSpacing`
  (thin/medium/thick = 3/4/5 mu), the unit TeX actually uses.
- Vinculum's own drawing proportions — the hand-stroked radical hook, the
  brace arcs, the arrowhead, the style-lattice shrink — have no font
  parameter, so they are named and documented in `MathLayout` instead of
  left as bare literals. Zero unexplained numbers remain in the builders.

Public API unchanged.

## 0.3.0 — 2026-07-12

Two big things since 0.1.0: an OpenType MATH font for genuine LaTeX quality,
and a device-independent scene-IR re-architecture.

**Latin Modern Math (Computer Modern).** Real glyph shapes, codepoint-based
math italics (variables → Mathematical Italic block, lowercase Greek italic),
the font's MATH-table constants, and ink-hugging accent placement — plus
standalone delimiters (`\langle` outside `\left…\right`) and ~80 more symbols.

**Scene IR.** A radical decomposition mirroring TeX's DVI split and
MermaidKit's layout/render seam. No change to rendered output (the golden
fixtures pass byte-identical), but the internals are now:

- **VinculumLayout is fully platform-free** and owns all typesetting geometry.
  `MathLayoutEngine` measures glyphs through an injected `MathTextMeasurer`
  and emits a `MathScene` of positioned primitives (`MathElement` / `MathColor`
  / `MathConstants`). Builds and tests on **Linux** (headless, mock measurer).
- **VinculumRender shrank to the platform seam**: `CoreTextMeasurer`,
  `MathSceneRenderer`, `MathFont`, `MathTheme`, `MathImageRenderer`. The old
  876-line `MathTypesetter` is gone.
- The two 800-line monoliths are now ~25 single-responsibility files (largest
  452 lines).
- **Swift 6** language mode + strict concurrency; platforms add **tvOS 17**.
- Public API unchanged: `MathParser`, `MathImageRenderer.attachmentString`,
  `MathTheme`. New public surface: `MathLayoutEngine`, `MathScene`,
  `MathTextMeasurer` for hosts that want the device-independent scene.

## 0.1.0 — 2026-07-11

First release. The native LaTeX math engine extracted from
[Quoin](https://github.com/clintecker/quoin), sibling to
[MermaidKit](https://github.com/clintecker/MermaidKit).

**VinculumLayout** (platform-free): `MathParser` (LaTeX → `MathNode` tree,
never fails — unknown commands degrade to `.unsupported` leaves that
`unsupportedCommands(in:)` can name), `MathScanner` (delimiter scanning),
`MathAlphabet` (Unicode math-alphabet codepoints), `MathMacros`
(document-scoped `\newcommand`/`\def` expansion, recursion-capped).

**VinculumRender** (CoreText/CoreGraphics): `MathTypesetter` (`MathNode` →
`MathBox` geometry — fractions, radicals, scripts, stacked limits,
matrices, accents, generalized fractions, over/under braces, stretchy
arrows, boxed/phantom, color), `MathImageRenderer` (cached
`NSTextAttachment` production), and the `MathTheme` seam.

Coverage: everyday KaTeX — fractions, roots, scripts, big operators with
limits, all matrix environments, `\mathbb`/`\mathcal`/`\mathfrak`/…
alphabets, accents, `\binom`, `\overbrace`/`\underbrace`, `\xrightarrow`,
`\substack`, `\boxed`, `\color`, and document macros. ~35 golden-image
fixtures with a promotion ratchet. Swift tools 5.10; Swift 6
strict-concurrency pass is a planned follow-up.
