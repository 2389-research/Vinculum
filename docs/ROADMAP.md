# Vinculum Roadmap

> **Status (2026-07-16, v1.4.2):** The best-in-class bar the original roadmap
> set is met. Everything the July-2026 iosMath audit flagged as a gap is
> closed, the "firsts" no native library had are shipped, and Vinculum now
> **renders on Linux** as well as Apple. What remains is a short, well-scoped
> set of open lanes — chiefly bringing the Linux raster backend to full
> font-truth parity with the Apple path.

This document is the *what and why*. The *how* — the execution history and the
current active plan — is in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

The original goal: **the best native math typesetting library on any platform —
not "iosMath, but Swift."** That meant closing the typographic-fidelity gaps
where iosMath was ahead, *then* shipping the things no native library had. Both
halves are done.

---

## Where we stand (the ledger, closed out)

The July-2026 audit compared Vinculum 0.23 against iosMath 2.5. Every row is
now at or past the best-in-class bar:

| Mechanism | Then (Vinculum 0.23) | Now (Vinculum 1.4) |
| --- | --- | --- |
| MATH constants | hardcoded transcription | **all 56, parsed per font at load** (fixture-pinned on Linux) |
| Italic correction | none | **per-glyph** (scripts, operators, integral tuck) |
| Cut-in kerning (`MathKernInfo`) | none | **implemented** — no other native library has it (STIX Two ships data for 233 glyphs) |
| Tall delimiters | variants for `()[]{}`, else scaled | **size-variant ladders → glyph assembly → scaling**, all delimiters |
| Radical | hand-stroked polyline | **the font's √ glyph** via variants + assembly (polyline is the headless fallback only) |
| Accent placement | geometric centering | **`topAccentAttachment` skew, `AccentBaseHeight` seat, wide-accent width variants**, script promotion |
| Script sizing | scale 0.70 / 0.50 | font scale-down **+ `ssty` optical script glyphs** (heavier redraws from GSUB) |
| Style machinery | `display: Bool` | **full display/text/script/scriptscript × cramped lattice** |
| Inter-atom spacing | approximate | **the complete TeXbook p. 170 pair table**, all 8 classes incl. Inner, cell-pinned |
| Fonts | 1 hardcoded | **5 bundled** (Latin Modern, Termes, Pagella, STIX Two, Fira Math) + any OTF via `MathFont(url:)` |
| Parse errors | supported-Bool | **typed diagnostics with `Range<String.Index>` source ranges** |
| Round-trip (tree → LaTeX) | none | **`MathNode.toLaTeX()`**, render-equivalent |
| Drop-in view | attachment only | **`VinculumLabel`** (AppKit/UIKit) + first-party SwiftUI **`MathView`** |
| Accessibility | none | **spoken math** (ClearSpeak-style) on every attachment and view |
| Hit-testing | none | **opt-in region substrate** → point maps to the deepest subtree + its LaTeX |
| Document pipeline | none | **`MathText.attributedString(from:)`** — prose with embedded math in one call |
| Server-side output | none | **self-contained SVG** (`MathSVGRenderer`) + **Linux raster PNG** (`MathSilicaRenderer`) |
| Platforms | Apple only | **Apple (CoreText) + Linux (Silica/Cairo/FreeType)**; layout is platform-free |
| Line breaking | none | still open (see below) |

---

## Shipped (releases)

The eight themes of the original plan all landed, plus a post-1.0 wave and the
Linux backend. Condensed:

- **1.0** — font-truth (parsed constants, the style lattice, italic correction,
  cut-in kerning, accents, glyph assembly), five fonts, spoken math,
  round-trip, diagnostics, the drop-in view, and the SwiftUI view; API frozen,
  performance ceilings enforced, iOS-simulator CI.
- **1.1** — the integration release: the `MathText` document pipeline, DocC +
  a runnable demo, hit-testing, the SVG renderer, and Fira Math as a fifth
  (sans) font.
- **1.2** — the typography + coverage release: `ssty` optical scripts, the full
  extensible `\x…arrow` family (double-lined, hooked, mapsto, harpoons), the
  complete p. 170 spacing chart with the Inner class, iosMath's whole example
  set (20/20), SVG that draws `.glyph(id:)` outlines, on a Swift 6.2 toolchain.
- **1.3 / 1.4** — the Linux rendering backend: `VinculumRender` draws a
  `MathScene` to a PNG via Silica/Cairo + FreeType. **1.4.1** put that behind
  the `LinuxRaster` package trait (default OFF) so default consumers keep a
  Silica-free dependency graph.

Full detail: [CHANGELOG.md](../CHANGELOG.md).

---

## Open lanes

Short and well-scoped. In rough priority.

> **Now issue-tracked.** A July-2026 multi-expert code review turned these lanes
> (and finer-grained quality/correctness/hygiene items) into **47 triaged GitHub
> issues** across six milestones (P0–P5). The sequenced execution order — safety
> nets first, correctness before enhancement, breaking changes batched — is in
> [docs/ISSUE_REMEDIATION_PLAN.md](ISSUE_REMEDIATION_PLAN.md). The lanes below are
> the high-level summary; the milestones are the working board.

### 1. Linux render parity (the active work)
The Linux path currently wires only the *base* services — a FreeType measurer
and font-parsed MATH constants — so the platform-free layout is faithful but a
few font-truth refinements the Apple path has are not yet drawn on Linux:

- large-operator **display variants** (`\int`/`\oint` render at base size),
- **`ssty`** optical scripts,
- **delimiter size variants** (tall fences point-scale),
- **`\vec`/`\bar` accent glyphs** and per-glyph typography.

The provider *seams* for all of these already exist and are platform-free
(`MathDelimiterProvider`, `MathScriptVariantProvider`,
`MathGlyphTypographyProvider`, `MathAccentVariantProvider`). The work is
FreeType-backed implementations of those closures on the Linux side — the same
shape the measurer already took. See [LINUX.md](LINUX.md) for the current gap
table. This closes the last daylight between the two backends.

### 2. Width-aware line breaking (stretch, still droppable)
Top-level Rel/Bin break points with penalties (TeX Rules 21/22). Math lays out
atomically today; breaking is the host's problem. Independently shippable, and
explicitly optional — nothing depends on it.

### 3. Minor coverage
`\DeclareMathOperator` (needs a macro-table branch), `\sideset`,
`\mathchoice`, and harpoon/`\utilde` accents — small, additive, good first
contributions. Tracked in [COVERAGE.md](COVERAGE.md)'s "not yet supported"
list.

---

## Non-goals (unchanged)

mhchem, siunitx, `\href`, embedded HTML, `\begin{CD}` — the WebView libraries
keep those. WYSIWYG *editing* stays out of scope, though the diagnostics,
round-trip, and hit-testing substrate deliberately leave the door open (a
path-indexed editor is a natural build-on).
