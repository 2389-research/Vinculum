# Contributing to Vinculum

Vinculum is the native LaTeX math engine extracted from
[Quoin](https://github.com/clintecker/quoin), following the same pattern as
[MermaidKit](https://github.com/clintecker/MermaidKit): a small, published,
zero-dependency Swift package that a host app consumes from GitHub.

The current release is **0.24.0**. Roughly **~400 symbol commands** and over
three dozen function-name operators parse and lay out natively — no
JavaScript, no WebView, no third-party dependencies.

## Build & test

`swift build` and `swift test` at the repo root is the whole loop — it is
exactly what CI runs. There is no code generation or bootstrap step.

- **`swift test`** runs both suites: the headless parser/layout tests
  (`VinculumLayoutTests`, Linux-safe) and the golden-image + typesetter
  tests (`VinculumRenderTests`, Apple-only).
- The package is **Swift 6, strict concurrency** (`swift-tools-version: 6.0`).
  Keep new types `Sendable` where the public API touches them.
- **Local green does not guarantee CI green.** The iOS render branch has no
  test host but must compile, and Swift-version skew between local and CI is
  real; CI builds `VinculumRender` for the iOS Simulator for exactly this
  reason. Push and watch CI.

### The golden-image workflow

Rendered output is pinned by PNG fixtures in `Tests/fixtures/math-golden/`,
rendered with `MathTheme.light`. `MathGoldenRenderTests` diffs live renders
against them.

```
VINCULUM_UPDATE_SNAPSHOTS=1 swift test --filter MathGolden
```

regenerates the goldens; then **eyeball the PNGs** before committing — the
test only tells you a render changed, your eyes decide whether it changed for
the better. Each fixture is tagged `.mustRender` or `.knownUnsupported`; the
fixture list is the coverage ledger. A `.knownUnsupported` fixture that
starts rendering **fails the build until you promote it**, so the docs can
never overstate what Vinculum supports.

### Headless layout tests

Because the layout engine measures glyphs through an injected
`MathTextMeasurer` seam, its geometry is unit-tested with a **mock measurer**
in `MathLayoutTests` — no font, no screen, runs on Linux in CI. Prefer adding
geometry assertions here (they are fast and portable) over relying on a golden
PNG whenever the property you care about is a number rather than a look.

### Stress corpus & gallery generators

- **Coverage ratchet.** `MathStressGallery.testCorpusCoverageReport` parses a
  dense real-world corpus (integrals, quantum-info, aligned derivations) and
  prints a native-coverage percentage plus the exact degraded commands. It
  asserts a **floor** so coverage can't silently regress. When you raise
  coverage, the report tells you what's still falling back.
- **Poster generators** (env-var gated, skipped by default):
  `MathStressGallery.testGenerateStressPages` writes to `$VINCULUM_STRESS_DIR`,
  and `GalleryGenerator.testGenerateGallery` writes the LaTeX-↔-render gallery
  posters to `$VINCULUM_GALLERY_DIR`. Set the env var to produce PNGs; leave it
  unset and the test `XCTSkip`s.

## Architecture (where to put things)

The design mirrors TeX's device-independent split (and MermaidKit's): layout
decides WHAT to draw as a platform-free scene; a renderer decides HOW.

- **VinculumLayout** (platform-free, Foundation only, zero deps — builds on
  Linux) does parsing AND all typesetting geometry:
  - *Parse* — `MathTokenizer` (lexer), `MathParser` (recursive descent),
    `MathSymbolTable` (the command → glyph/atom-class data), `MathScanner`
    (`$…$` delimiters), `MathMacros` (`\newcommand`/`\def`), `MathAlphabet`
    (Unicode math alphabets), `MathDiagnostics` (support classification). The
    AST is `MathNode`.
  - *Lay out* — `MathLayoutEngine` measures glyphs through the injected
    `MathTextMeasurer` and (for tall fences) the optional
    `MathDelimiterProvider`, emitting a `MathScene` of positioned primitives
    (`MathElement`: glyph runs, glyph-by-ID, rules, stroked paths) in
    `MathColor`. Per-domain builders live in the `Layout+*.swift` files
    (Fractions, Scripts, Radicals, Delimiters, Accents, OverUnder,
    Decorations). `MathBox` is the compositional unit; `MathConstants` holds
    the font's OpenType MATH-table metrics; `MathLayoutMetrics` holds
    Vinculum's own drawn-shape numbers. Inter-atom spacing uses the TeX
    atom-class pair table with binary/unary reclassification; color and the
    cramped flag thread through struct-copy sub-contexts.
  - No CoreGraphics/CoreText/AppKit — only Foundation geometry types.
- **VinculumRender** (Apple platforms) is the thin platform seam:
  `CoreTextMeasurer` (implements `MathTextMeasurer` via CTLine),
  `MathVariantTable` + a `MathDelimiterProvider` (a runtime OpenType
  **MATH**-table parser that reads `MathVariants` for purpose-drawn tall
  delimiter glyphs), `MathSceneRenderer` (draws a `MathScene` into a
  `CGContext`), `MathFont` (the bundled Latin Modern Math), `MathTheme` (the
  host coupling: ink + light/dark appearance), and `MathImageRenderer` (cached
  `NSTextAttachment`, orchestrating measure → layout → render). Guarded
  `#if canImport(AppKit) || canImport(UIKit)`.

## Adding a command (the recipe)

This is the highest-value contribution. What you touch depends on the kind of
command.

### 1. A plain symbol

One row in `MathSymbolTable.symbolTable`:

```swift
"nleq": ("≰", .relation),
```

The **atom class is load-bearing** — it drives inter-atom spacing (a `.binary`
spaces differently from a `.relation` or an `.ordinary`) and delimiter
handling. Pick it deliberately from `MathAtomClass`
(`ordinary`/`largeOperator`/`binary`/`relation`/`opening`/`closing`/
`punctuation`). Then add a fixture and regenerate goldens (below). That's the
entire change for a symbol — no parser or layout code.

A **function-name operator** (`\sin`-like) is one entry in
`MathSymbolTable.functionNames`; if it should stack its limits like `\lim`
rather than sitting beside them like `\sin`, also list it in the
limits-stacking set in `Layout+Scripts.swift`.

### 2. A structural command

Something with its own geometry (a new kind of fraction, box, accent, arrow):

1. **Parse it** — add a `case "yourcmd":` in `MathParser` that consumes its
   arguments and returns a `MathNode`.
2. **Lay it out** — add or extend a builder in the appropriate
   `Layout+*.swift` file, driven off the node.
3. **If it needs a new `MathNode` case**, wire that case through the **four
   exhaustive switches** (the compiler will force you to, since none has a
   `default`):
   - `MathLayoutEngine.box(for:)` — how it lays out.
   - `MathLayoutEngine.atomClass(of:)` — its spacing class (or `nil`).
   - `MathDiagnostics.isFullySupported(_:)` — recurse into its children so
     coverage classification stays honest.
   - `MathDiagnostics.unsupportedCommands(in:)` — same, for the named-culprit
     list the diagnostics surface.
   Miss one and the build won't compile — that is by design.
4. **Add a golden fixture** in `MathGoldenRenderTests` and regenerate with
   `VINCULUM_UPDATE_SNAPSHOTS=1 swift test --filter MathGolden`, then look at
   the PNG. Add a headless geometry assertion in `MathLayoutTests` too if the
   node has a measurable invariant.

### The never-crash contract

Vinculum must never trap on input, however malformed. Unknown or malformed
commands degrade to `.unsupported(raw)` (which renders a visible fallback),
never a `fatalError` and never a force-unwrap. Keep the layout sources
force-unwrap-free — the existing code has none. When you can't fully handle
something, return `.unsupported` and let the coverage tests record it as a
documented gap; do not paper over it.

## Co-development with Quoin

Vinculum is published and consumed **from GitHub**, like MermaidKit — Quoin
declares it as `.package(url: "…/Vinculum.git", from: "0.24.0")`. It is not
vendored. To co-develop against a host app, point that dependency at a local
checkout (`.package(path: "../Vinculum")` or `swift package edit`, and don't
commit that), make your change here, then **publish → tag → bump**: push to
the Vinculum repo, tag the new version, and raise the `from:` in the host's
`Package.swift`. Engine changes are tested by Vinculum's own CI, not the
host's.

## API stability (pre-1.0)

Entry points are stable: `MathParser.parse`, `MathParser.isFullySupported`,
`MathParser.unsupportedCommands`, `MathMacros`, `MathImageRenderer`,
`MathTheme`, and the `MathScene`/`MathElement` scene IR. The `MathNode` model
and typesetter internals may still reshape before 1.0 as coverage grows.
