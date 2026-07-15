# Vinculum Roadmap

> **Status (2026-07-15):** Themes A–G and the speech/wide-accent halves of
> H shipped in the 0.24 line, with a six-lens expert review applied on top;
> `ssty` optical scripts now ship too (the font's script/scriptscript
> glyph redraws, parsed from GSUB). Open: width-aware line breaking only
> (stretch, droppable per decision below).

**Goal: the best native math typesetting library on any platform — not
"iosMath, but Swift."** That means closing the typographic-fidelity gaps
where iosMath is currently ahead, then shipping the things *no* native
library has: per-glyph cut-in kerning, optical script glyphs, positioned
parse diagnostics, VoiceOver speech, and width-aware line breaking.

This document is the *what and why*, ordered into releases. The *how* —
phase-by-phase, test-first — is in
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

Grounding: a mechanism-level audit of iosMath v2.5.0 (July 2026) against
Vinculum 0.23.0. iosMath is actively maintained and typographically deeper
than us in three areas (font-read constants, per-glyph italic correction,
glyph assembly). We are ahead on architecture (device-independent IR,
Linux-headless layout, render caching, macro processor, golden-image CI
ratchet, Swift 6). Neither library has math kerning, `ssty` scripts,
accessibility, error positions, or line breaking — that's the open lane.

---

## Where we stand (honest ledger)

| Mechanism | Vinculum 0.23 | iosMath 2.5 | Best-in-class bar |
| --- | --- | --- | --- |
| MATH constants | hardcoded LM Math transcription | ~50 constants read per font | read from font, per font |
| Italic correction | none | per-glyph, scripts + operators | per-glyph, everywhere Rule 17/18 wants it |
| Cut-in kerning (MathKernInfo) | none | none | **open lane** |
| Tall delimiters | size variants for `()[]{}`, else scaled | variants + full glyph assembly | variants + assembly, all delimiters |
| Radical | hand-stroked polyline | font glyph + variants + assembly | font glyph + variants + assembly |
| Accent placement | geometric centering | `topAccentAttachment` skew + width variants | same, plus `flac` flattening |
| Script sizing | scale 0.70 / 0.50 | scale via font's `ScriptPercentScaleDown` | **font scale-down + `ssty` optical glyphs** ✓ |
| Style machinery | `display: Bool` + cramped bit | 4-style lattice + cramped bit | full D/T/S/SS × cramped |
| Fonts | Latin Modern, hardcoded | 8 bundled + any OTF | multiple bundled + any OTF |
| Parse errors | supported-Bool + command names | typed codes + messages | codes + messages + **source ranges** |
| Round-trip (tree → LaTeX) | none | yes | yes |
| Drop-in view | none (attachment only) | `MTMathUILabel` | AppKit/UIKit label + first-party SwiftUI |
| Accessibility | none | none | **open lane** |
| Line breaking | none | none | **open lane** |
| Render caching | content+theme+size, negative entries | none | keep ours |
| Headless/Linux tests | full layout product | none | keep ours |

---

## Themes → releases

Eight themes, sequenced so each release ships user-visible improvement while
laying substrate for the next. Version numbers are intent, not contract.

### Theme A — Font truth (v0.24)
Parse `MathConstants` and `MathGlyphInfo` from the font's MATH table at
runtime; retire the hardcoded transcription. The parser moves to
`VinculumLayout` (bytes in, data out — Linux-testable); obtaining table
bytes stays in `VinculumRender`. **This unblocks every other theme.**
The existing hardcoded values become the *expected values* of the new
parser's tests — the transcription retires only after the parser reproduces
it exactly.

### Theme B — The style lattice (v0.25)
Replace `display: Bool` with the real four-style lattice
(display/text/script/scriptscript × cramped). Inter-atom spacing suppressed
in script styles (the `NSThin/NSMedium/NSThick` rule), style-correct
constant selection, `\scriptstyle`/`\scriptscriptstyle` commands. Mostly
invisible on its own; everything in C–E selects constants by style.

### Theme C — Per-glyph script typography (v0.26)
Italic correction on scripts and big operators (TeX Rules 17/18f), the
composite-nucleus baseline drops (σ₁₈/σ₁₉), the 18d–e collision rules
(`SubSuperscriptGapMin`, `SuperscriptBottomMaxWithSubscript`), and —
**past iosMath** — MathKernInfo cut-in kerning, which no native library
implements. `f^2`, `W_j`, `\int_a^b` stop looking loose.

### Theme D — Accents that know their font (v0.27)
`topAccentAttachment` skew, `AccentBaseHeight` clamping, horizontal width
variants for wide accents, single-char accentee script promotion
(`\hat{f}^2` puts the 2 on `f`).

### Theme E — Glyph assembly (v0.28–0.29)
Arbitrarily tall delimiters assembled from MATH `GlyphAssembly` parts
(extenders + connectors, constant stroke weight), the radical drawn with the
font's √ glyph (variants, then assembly) instead of a polyline, then
horizontal assembly for wide braces/arrows. Includes iosMath's two
robustness lessons: validate extender advances at load, and the
radical shortfall heuristic (prefer the just-short variant over a huge
jump). The "fat stroke" tail in COVERAGE.md closes.

### Theme F — Multi-font (v0.30)
Fonts become values, not a hardcoded enum: bundle 2–4 additional OFL/GFL
math fonts (candidates: TeX Gyre Termes, TeX Gyre Pagella, STIX Two, Fira
Math), accept any user OTF with a MATH table. Only possible because
constants now come from the font (Theme A). **Decided (2026-07-14): bundle
TeX Gyre Termes, TeX Gyre Pagella, and STIX Two Math** (~2–3 MB total;
serif companions plus the industry standard).

### Theme G — Developer experience (v0.31)
Typed parse diagnostics **with source ranges** (better than iosMath's
message-only errors), `MathNode → LaTeX` round-trip, a drop-in
`VinculumLabel` (AppKit/UIKit) and first-party SwiftUI `MathView` with
alignment, insets, and inline error display — **decided (2026-07-14):
off by default**, preserving the never-half-broken fallback contract as
the default posture. The one-line adoption story.

### Theme H — Firsts (v0.32+)
Things no native math library has: a spoken-math description generated from
the node tree (`accessibilityLabel` on every attachment and label — "x
equals the fraction: negative b plus or minus…"), `ssty` optical script
glyphs, and width-aware line breaking at top-level Rel/Bin boundaries
(TeX Rule 21) — **decided (2026-07-14): line breaking is a stretch goal,
explicitly droppable from 1.0**. Each is independently shippable.

### v1.0
When Themes A–G are done and the stress corpus renders at 100% with
font-read metrics under at least three bundled fonts, tag 1.0. The 1.0
promise: *TeX-quality output measured against the font's own MATH table,
on every Apple platform and Linux-headless, with a one-line integration.*

---

## Standing docs work (every release)

- **ALGORITHM.md** — start a rule-by-rule TeX Appendix G audit like
  iosMath's (their best artifact): per-rule status, deviations, and the
  σ/ξ → OpenType constant map. Grows with each theme.
- **README honesty pass** — soften "TeX-faithful metrics … the way Knuth's
  algorithm intends" until Theme A ships it for real; refresh the iosMath
  comparison bullets (they now have 8 fonts, SPM, macOS).
- The coverage ratchet, golden suite, and gallery CI continue as the
  regression floor for every phase.

## Non-goals (unchanged)

mhchem, siunitx, `\href`, embedded HTML, `\begin{CD}` — the WebView
libraries keep those. WYSIWYG *editing* stays out of scope for 1.0, but
Theme G's diagnostics and round-trip deliberately leave the door open
(iosMath's `MTMathListIndex` path-index design is the template if we ever
walk through it).
