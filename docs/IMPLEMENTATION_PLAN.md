# Implementation Plan

The execution record and the *current* active plan behind [ROADMAP.md](ROADMAP.md).
The original phased plan (Themes A–H) is **fully executed** — its phases are
listed as a completion ledger below. The live work is [Linux render
parity](#active-plan--linux-render-parity), written in the same test-first
style.

---

## The TDD loop this repo runs on

Every phase runs the same four-ring loop, innermost first. This is unchanged
and still the working discipline:

1. **Byte-level tests (Linux).** Parser work is tested against *committed
   fixture bytes* — the raw `MATH` table extracted from the bundled fonts into
   `Tests/fixtures/math-table/*.bin`, and hand-built synthetic tables (e.g.
   `GsubScriptStyleParserTests`) — so table parsing is verified headless, no
   CoreText, no display.
2. **Geometry tests (Linux).** Layout behavior is asserted through the mock
   measurer in `Tests/VinculumLayoutTests/` as *exact numbers*: "the `\over`
   numerator is the full row before the operator," "`\int\limits` wraps the
   operator in `.limitsOperator`," "the p. 170 pair table matches an
   independent transcription cell for cell." Write the failing assertion
   first; it is the spec.
3. **Golden images (macOS).** Each visible change adds or re-blesses fixtures
   in `Tests/fixtures/math-golden/` (`VINCULUM_UPDATE_SNAPSHOTS=1`). A phase
   that claims "no visual change" must leave every golden green — that *is* the
   refactor test. Re-bless knowingly, never wholesale.
4. **The ratchet.** New capability promotes stress/golden entries to
   `.mustRender`; the suite fails if coverage silently improves or regresses.

Plus, since the docs became illustrated: **figures are CI-regenerated from the
live engine** on every push (`GalleryGenerator`, `AlgorithmGalleryGenerator`,
`CommandGalleryGenerator`, …). A wrong-looking figure means a wrong engine —
this has caught real bugs (a mis-seated `\vec`, dropped chart coverage).

House rules (unchanged):

- **Never regress the fallback contract.** Everything new is additive;
  unsupported input degrades to a named source card, never a half-render.
- **New knobs default off or default-equal.** A new provider must reproduce the
  prior behavior when absent (headless/Linux keeps working).
- **Small commits; the phase's exit criteria are the merge bar.**

---

## Completed phases (the executed plan)

All shipped; each row's tests and goldens are in the suite. See
[CHANGELOG.md](../CHANGELOG.md) and [ALGORITHM.md](ALGORITHM.md) (rule-by-rule
status) for detail.

| Theme / phase | Delivered in | What landed |
| --- | --- | --- |
| **A — Font truth** | 1.0 | `MathTableParser` (bytes → `MathFontConstants`/`MathGlyphInfo`/`MathVariantsData`, Linux-fixture-pinned); the `.latinModern` preset; hardcoded transcription retired (found 3 transcription bugs). |
| **B — Style lattice** | 1.0 | Full display/text/script/scriptscript × cramped; style-selected constants; script-style spacing suppression; `\displaystyle` family; `styleAnchorSize`. |
| **C — Per-glyph script typography** | 1.0 | Italic correction (scripts, operators, integral tuck), Rule 18a–f baseline drops + collision clamps, and **`MathKernInfo` cut-in kerning**. |
| **D — Accents** | 1.0 | `topAccentAttachment` skew, `AccentBaseHeight` seat, wide-accent horizontal variants, single-char script promotion. |
| **E — Glyph assembly** | 1.0 | Delimiter size-variant ladders → `GlyphAssembly` (extenders + connectors) → scaling; radical drawn with the font's √; shortfall heuristic; extender validation. |
| **F — Multi-font** | 1.0 / 1.1 | Latin Modern, TeX Gyre Termes & Pagella, STIX Two, then Fira Math; per-font MATH parse + render caching; `MathFont(url:)`. |
| **G — Developer experience** | 1.0 | Diagnostics with `Range<String.Index>`; `MathNode.toLaTeX()`; `VinculumLabel`; SwiftUI `MathView`; inline errors off by default. |
| **H — Firsts** | 1.0 / 1.2 | Spoken math (ClearSpeak-style) and **`ssty` optical scripts** (GSUB `AlternateSubst` → `MathScriptVariantProvider`). |
| **Post-1.0 wave** | 1.1 | `MathText` document pipeline; DocC + `VinculumDemo`; hit-testing substrate; `MathSVGRenderer`. |
| **Coverage + typography** | 1.2 | The full p. 170 spacing chart (Inner class); the extensible `\x…arrow` family with real heads; iosMath's example set (20/20); SVG glyph-outline drawing (`PathOp.cubic`); Swift 6.2. |
| **Linux backend** | 1.3 / 1.4 | `FreeTypeFont` + `MathSilicaRenderer` (outlines → Cairo → PNG); the `LinuxRaster` package trait (default OFF) so default consumers stay Silica-free. |

Six-lens expert review and a review backlog were also applied on top of 1.0
(criticals fixed: parser recursion overflow, a cached-image mutation race, the
gallery engines rendering the pre-font-truth pipeline).

---

## Active plan — Linux render parity

**Goal.** Bring the Linux (Silica/Cairo/FreeType) backend to full font-truth
parity with the Apple path. The layout is already identical (platform-free
engine); the gaps are the *providers* the Linux path doesn't yet supply. The
seams already exist and are platform-free — this is FreeType-backed
implementations of the same closures the measurer already fills. Verify each
against the parity corpus (`Tests/fixtures/parity-corpus.txt`,
`ParityGenerator` on macOS vs `MathSilicaRenderer` on Linux).

Ordered by visible impact; each is independently shippable and gated by the
`LinuxRaster` trait, so none touches default consumers or the Apple path.

### LP-1 — Accent typography + glyph coverage
**Symptom.** `\vec`'s arrow sits slightly off-centre; `\bar`'s overbar glyph
can be missing.
**Work.** A FreeType-backed `MathGlyphTypographyProvider` (the glyph's
`topAccentAttachment` / italic correction from the MATH table — already parsed
in `MathTableParser`, just not wired to a FreeType glyph on Linux), and make
sure the accent/combining glyphs resolve through the cmap.
**Tests first.** Geometry assertions already cover accent placement headlessly;
add a Linux render check that `\hat`/`\vec`/`\bar`/`\widehat` produce ink where
the scene says. Re-run the parity corpus.

### LP-2 — `ssty` optical scripts
**Symptom.** Superscripts/subscripts scale the base glyph instead of the
optical redraw.
**Work.** Wire `MathScriptVariantProvider` on Linux — the GSUB `ssty` map is
already parsed (`GsubScriptStyleParser`, platform-free); the Linux provider
resolves the base glyph ID via FreeType's cmap, looks up the variant, and hands
back a `ScriptGlyph` with FreeType metrics (the same shape
`CoreTextScriptVariantProvider` returns).
**Tests first.** A scene test that a script-level symbol emits a `.glyph(id:)`
variant run on Linux (mirrors the Apple `SstyFontParseTests`).

### LP-3 — Delimiter size variants + large-operator display cuts
**Symptom.** Tall fences point-scale; `\int`/`\oint` render at base size.
**Work.** A FreeType-backed `MathDelimiterProvider` (+ assembly) reading the
already-parsed `MathVariantsData`: choose the size variant / assembly by glyph
ID, measure by ID. This also feeds the display-operator path.
**Tests first.** Render checks that a `\left(\dfrac{a}{b}\right)` fence and a
display `\int` grow on Linux; parity corpus.

### LP-4 — Golden pipeline for Linux
Once the providers land, add committed Linux golden PNGs (Cairo-decoded pixel
compare, gated by the trait) so Linux rendering has the same regression floor
the Apple goldens give — the parity corpus becomes a ratchet, not a one-off.

**Exit for the lane.** The parity corpus renders indistinguishably (within a
small tolerance) on both backends, and LINUX.md's "known gaps" table is empty.

---

## Later / optional

- **Width-aware line breaking** (ROADMAP open lane 2) — TeX Rules 21/22 at
  top-level Rel/Bin boundaries. A `MathScene`-level pass with break penalties;
  independently shippable, explicitly droppable.
- **Minor coverage** (ROADMAP open lane 3) — `\DeclareMathOperator` (a
  macro-table branch), `\sideset`, `\mathchoice`, harpoon/`\utilde` accents.
  Each is one parser case + a golden; good first contributions.
- **`LayoutContext` internal refactor** — thread the ambient layout state
  (style, cramped, color, size) through one value rather than several engine
  fields. Pure internal cleanliness, no behavior change; deferred deliberately
  since the factory + `styleAnchorSize` already deliver the behavior.
