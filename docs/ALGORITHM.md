# TeX Appendix G → Vinculum Implementation Map

An honest, rule-by-rule audit of Knuth's math typesetting algorithm
(*The TeXbook*, Appendix G, "Generating Boxes from Formulas") against what
Vinculum's layout engine actually does. This is the document that keeps the
README honest: each rule is marked **Implemented**, **Partial**,
**Deviation** (deliberate, explained), or **ABSENT**.

It is a living document. [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
phases land against it — a phase isn't done until its rules here flip
status. First audited at v0.24.0; figures and the Rule 20 chart re-verified against the TeXbook at v1.1.

Appendix G's big takeaway — and Vinculum's design premise — is that TeX
does **not** lay out mathematics as decorated text. It compiles a list of
*classified* objects (typed atoms) into a geometric box structure, using
font-supplied constants plus explicit collision-avoidance rules:
classification first, measurement and assembly second. That separation is
why the spacing in `a+b=c` comes from the class sequence Ord–Bin–Ord–Rel–Ord
(never from the characters), and why deeply nested expressions stay
consistent.

**Sources:** [The TeXbook, Appendix G,
p. 440ff](https://web.math.ucsb.edu/~bigelow/books/texbook.pdf) is the
normative text; Bogusław Jackowski's [*Appendix G
Illuminated*](https://www.ntg.nl/maps/34/09.pdf) diagrams the radical,
accent, fraction, limit, and script-collision rules and is the best visual
companion. Chapter 18 (pp. 170–172) carries the inter-atom pair chart, the
`\bigl`-vs-`\left` atom classes, and the `\ldots`/`\cdots` conventions this
engine implements.

---

## 1. Big picture

### 1.1 Pipeline

```mermaid
flowchart LR
    A["LaTeX"] --> B["MathMacros"] --> C["MathParser → MathNode"]
    C --> D["MathLayoutEngine<br/>(box(for:display:) + Layout+*)"]
    D --> E["MathScene"] --> F["MathSceneRenderer / MathImageRenderer"]
```

Vinculum has no separate "finalize" pass: binary→ordinary reclassification
(Rules 5/6) runs inside the engine (`reclassifyBinaries`,
`MathLayoutEngine.swift`), and everything else happens in the single
recursive `box(for:)` descent. Where TeX emits a horizontal list, Vinculum
emits a `MathBox` of positioned `MathElement`s.

### 1.2 Styles — **Implemented**

`MathStyle` (display/text/script/scriptScript, `MathStyle.swift`) threads
through every builder, with the engine's separate `cramped` flag giving the
full eight-style lattice. Successor maps follow TeX: `scriptStyle` (D,T→S;
S,SS→SS) and `fractionStyle` (D→T, T→S, S→SS). Script descent multiplies
size by `scriptSizeRatio` — 70% from text, then only down to the 50%
scriptscript floor (not compounding 0.7ⁿ shrink). `\displaystyle`,
`\textstyle`, `\scriptstyle`, `\scriptscriptstyle` parse statefully (rest
of group, like stateful `\color`) and force both style and its implied
size; `\genfrac`'s style argument honors all four values.

Cramping propagates as before: radicands, denominators, and subscripts set
`cramped`, selecting `superscriptShiftUpCramped`.

**`ssty` optical scripts — Implemented.** Beyond scaling, each script /
scriptscript symbol is swapped for the font's purpose-redrawn optical
variant (`ssty=1` / `ssty=2`), parsed from the GSUB table
(`GsubScriptStyleParser` → `MathScriptVariants`, 995 glyphs in LM Math) and
injected as `MathScriptVariantProvider`. The variant carries heavier strokes
and more open forms so a shrunk glyph keeps the base text's weight instead of
thinning out. Emitted by glyph ID (the variants are unencoded); headless
hosts with no provider scale the base glyph exactly as before.

![The style lattice](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-styles.png)

![ssty optical scripts](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-ssty.png)

### 1.3 Font parameters — **Implemented**

TeX reads σ/ξ parameters from the font; so does Vinculum now.
`MathTableParser` (`VinculumLayout`, platform-free, fixture-tested on raw
committed `MATH` bytes) parses the full 56-value `MathConstants` sub-table
into `MathFontConstants`, and the `MathGlyphInfo` sub-table (per-glyph
italic corrections, top-accent attachment points, extended shapes, cut-in
kern staircases) into `MathGlyphInfo`. The engine carries a
`MathFontConstants` instance — parsed from the live font by the renderer
(`MathFont.constants`), or the `.latinModern` preset headless. The preset
is pinned three ways: live font ↔ fixture bytes ↔ fontTools ground truth.

The a later release oracle caught **three mistranscriptions** in the old hardcoded
constants: `spaceAfterScript` 0.041 → font 0.056; `radicalVerticalGap`
0.148 was the *display* value (text is 0.050, now style-selected in
`radicalBox`); `stackGapMin` 0.150 → font 0.120. The old `MathConstants`
enum is deprecated. Note: `MathGlyphInfo` is *parsed* but not yet
*consumed* — that's Phases 3–4. Latin Modern Math ships no MathKernInfo
(fontTools-verified); kern staircases are exercised with synthetic bytes
until STIX Two arrives in a later release.

Vinculum's own drawing proportions (radical hook, brace arcs, arrowheads,
fraction part-scales) live separately in `MathLayoutMetrics.swift` and are
deliberately not TeX numbers — e.g. fraction part-scales 0.9/0.8 instead
of TeX's 1.0/0.7, documented there as a legibility choice.

---

## 2. Rule-by-rule

### Rule 2 — mu-glue and kerns — **Implemented (fixed values)**
`\, \: \; \! \quad \qquad \mkern \kern \hspace` produce spacing in
mu = em/18 (`MathLayoutMetrics.swift`). `\nonscript` is ABSENT (moot until
the style lattice exists). Thin/med/thick are fixed 3/4/5 mu.

### Rule 3 — style items — **Implemented**
All four style commands, stateful to the group; `.mathStyle(base:style:)`
forces style + implied size (`\dfrac`/`\tfrac`, `\genfrac` styles 0–3).

### Rule 4 — `\mathchoice` — **ABSENT** (degrades to fallback, documented in COVERAGE.md)

### Rules 5/6 — Bin↔Ord reclassification — **Implemented**
`reclassifyBinaries` (`MathLayoutEngine.swift`) retypes a binary with no
left operand, or one following Bin/Rel/Open/Punct/Op, to ordinary, and a
binary before Rel/Close/Punct likewise — the precise Appendix G rules whose
consequence p. 170 states ("Bin atoms must be preceded and followed by
atoms compatible with the nature of binary operations"), and what licenses
the `*` cells in the Rule 20 chart.

### Rule 8 — `\vcenter` — **ABSENT**

### Rules 9/10 — `\overline`/`\underline` — **Implemented**
Rule + gap from `overbarVerticalGap`/`underbarVerticalGap` and rule
thickness constants (`Layout+Decorations.swift`); inner cramped.

![Rules 9/10 — lines, braces, boxes](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-decorations.png)

### Rule 11 — radicals — **Implemented**
The surd is the font's √ glyph: size variants first (with the shortfall
heuristic — a variant within 3% beats a ≥1.3× jump, so the sign hugs the
radicand), then glyph assembly for very tall radicands, excess split into
the clearance (Rule 11's ψ centering). The degree is placed by
`RadicalKernBeforeDegree`/`RadicalKernAfterDegree` (the −0.556 em kern
tucks the sign back over the degree) and the 60%
`RadicalDegreeBottomRaisePercent`. The hand-stroked polyline survives only
as the no-provider fallback (headless/Linux, mock-measurer tests).

![Rule 11 — radicals](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-radicals.png)

### Rule 12 — accents — **Implemented, including width variants**
Accent x comes from the font's `topAccentAttachment` points (base minus
accent, via the typography provider; advance-center fallback) — strictly
better than TeX's `\skewchar`. Vertically the accent hugs the base's ink
but never sinks below the font's `AccentBaseHeight` seat
(δ = min(h, AccentBaseHeight)). Scripts on a single-character accentee
promote onto the character (`\hat{f}^2` puts the ² on the f). Stretchy
accents (`\widehat` family) walk the font's HORIZONTAL variant ladder —
carried by the combining-mark glyphs — taking the widest drawn cut not
exceeding the accentee; scaling is the headless fallback.

![Rule 12 — accents with skew and width variants](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-accents.png)

### Rule 13 — large operators — **Implemented**
In display style, large operators (∑, ∏, ∫, …) swap in the font's
display-size **variant glyph** at `DisplayOperatorMinHeight`, centered on
the math axis (`½(h−d) − a`); the 1.35× scale survives only as the
headless fallback. Limits attach at the Rule 13a clearances —
`max(UpperLimitGapMin, UpperLimitBaselineRiseMin − d(sup))` and the lower
mirror — and split ±δ/2 by the italic correction. Integrals are
`\nolimits` with the δ-tucked subscript; the `\lim` family stacks.
Remaining: no `\displaylimits` tri-state.

![Rules 13/13a — operators and limits](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-operators.png)

### Rule 14 — Ord runs, ligatures, kerns — **Partial**
Adjacent symbols share glyph runs via the measurer. Math ligatures and
inter-glyph math kerns: ABSENT (low priority).

### Rule 15 — fractions — **Implemented**
Rules 15b–d land font-true: with a rule, numerator/denominator shifts come
from the `FractionNumerator/Denominator[DisplayStyle]Shift` pairs and
clearance from `FractionNum/DenomGapMin` (display: 3ξ₈, text: ξ₈); without
a rule (`\atop`, `\binom`), the `StackTop/Bottom[DisplayStyle]Shift` pairs
and `Stack[DisplayStyle]GapMin`. The 1.35 display boost and the hand-tuned
`ruleGap`/`atopGap` numbers retired. `\cfrac` uses the display constants.
Remaining deviation: part-scales 0.9/0.8 (deliberate, see §1.3);
`\above`/`*withdelims` unparsed.

![Rule 15 — fractions on the math axis](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-fractions.png)

### Rule 16 — retype to Ord — **Implemented** via each builder returning a classed box consumed by the spacing walk.

### Rule 17 — nucleus conversion + italic correction — **Implemented**
Per-glyph italic correction flows through the injected
`MathGlyphTypographyProvider` (backed by the font's
MathItalicsCorrectionInfo): the superscript shifts right by δ while the
subscript stays at the advance; a large operator instead tucks its
subscript δ left under the overhang (∫'s δ is 0.332 em in LM Math); and
stacked limits split ±δ/2 (Rule 13a). The `\scriptspace` analog
(`SpaceAfterScript`, the correct 0.056 em) now trails the scripts instead
of preceding them. Remaining gap: no unconditional italic-correction kern
between adjacent unscripted symbols.

### Rule 18 — scripts — **Implemented, including cut-in kerning**
The full 18a–f ladder: style shift constants for character bases and the
σ₁₈/σ₁₉ baseline drops (`Superscript/SubscriptBaselineDrop`) for composite
nuclei, the `SuperscriptBottomMin`/`SubscriptTopMax` clamps (18b–c), the
`SubSuperscriptGapMin` + `SuperscriptBottomMaxWithSubscript` collision
resolution (18d–e), the δ split (18f), and — beyond TeX and beyond every
native library — **MathKernInfo cut-in kerning**: scripts sample the base
glyph's corner staircase at their near edge and tuck in by the kern. LM
Math ships no kern data (staircases exercised with synthetic bytes); STIX
Two in a later release lights this up for real. Ink-clearance floors are retained
so exponents clear tall bases' ink.

![Rules 17/18 — geometric script placement](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-scripts.png)

### Rule 19 — `\left…\right` — **Implemented / minor deviation**
The full stretch chain: MATH size variants (any covered glyph — the old
`()[]{}`-only gate is gone; `⟨ ⟩ ‖ ⌈ ⌋` now step through variants) →
**glyph assembly** from font parts (`MathAssemblySolver`: fewest extender
repeats, joints opened equally from max overlap, `MinConnectorOverlap`
respected, degenerate extenders rejected at parse) → continuous scaling
as the last resort. Assemblies render as stacked `.glyph` elements at
constant stroke weight. Fences size by TeX's formula:
ψ measured from the axis, height ≥ max(2ψ·901/1000, 2ψ − 5pt) — so a
fence may sit up to ~10% short of an extreme body, exactly as TeX's
`\delimiterfactor` intends.

![Rule 19 — the delimiter stretch chain](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-delimiters.png)

### Rule 20 — inter-atom spacing — **Implemented (the full 8×8 chart)**
The complete p. 170 pair table over all 8 atom classes **including Inner**
(`pairSpacing` in `MathLayoutEngine.swift`), transcribed cell for cell and
pinned by `MathSpacingTableTests` against an independent transcription.
Thin/med/thick = 3/4/5 mu; the chart's parenthesized entries (which include
the entire Punct row) vanish in script styles. Fractions, `\left…\right`
groups, fenced matrices, and `\ldots`/`\cdots`/`\ddots` (plain TeX defines
them as `\mathinner`) classify as Inner; `\mathinner{…}` reclassifies
explicitly and round-trips through `toLaTeX()`. ABSENT: fixed muskips
(`\thinmuskip` etc. are not user-settable).

![Rule 20 — the pair table in action](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-spacing.png)

### Rules 21/22 — line-break penalties, `\mathsurround` — **ABSENT**
Math lays out atomically; breaking is the host's problem. Automatic
breaking is a stretch goal.

---

## 3. Constants ledger

**Read from the font at runtime:** the full 56-value `MathConstants`
sub-table (`MathFontConstants`), the `MathGlyphInfo` sub-table (italic
corrections, topAccentAttachment, extended shapes, kern staircases), and
the vertical size-variant lists for the verified delimiter set.

**Parsed but not yet consumed by layout:** everything in `MathGlyphInfo`
(Phases 3–4); the constants the engine doesn't select yet —
SubSuperscriptGapMin, SuperscriptBottomMin, SubscriptTopMax,
SuperscriptBottomMaxWithSubscript, σ₁₈/σ₁₉ baseline drops,
DisplayOperatorMinHeight, RadicalKernBefore/AfterDegree,
RadicalDegreeBottomRaisePercent, FractionNum/DenomGapMin pairs, the
stretch-stack and skewed-fraction sets (Phases 2–6).

**Still missing from the parser:** GlyphAssembly part records +
MinConnectorOverlap.

**Vinculum's own numbers (deliberate, stay):** `MathLayoutMetrics.swift` —
radical polyline proportions (until a later release), brace arcs, arrowheads,
fraction part-scales and side padding, delimiter step factors.

---

## 4. Gap summary → plan mapping

| Gap | Rule(s) | Status |
| --- | --- | --- |
| ~~Constants not read from font~~ **done** | §1.3 | done |
| ~~No style lattice / script spacing rule~~ **done** | §1.2, 3, 20 | done |
| ~~No italic correction~~ **done** | 17, 18f, 13 | done |
| ~~No cut-in kerning~~ **done** (mechanics; live data arrives with STIX Two) | 18 | done |
| ~~Accent attachment points~~ **done** (width variants → 5) | 12 | done |
| ~~No glyph assembly; scaled tall fences~~ **done** (fences) | 19 | done |
| ~~Polyline radical~~ **done** (polyline = headless fallback only) | 11 | done |
| ~~Operators scaled not variant-swapped; Rule 19 formula~~ **done** | 13, 19 | done |
| `\mathchoice`, `\vcenter`, `\above`, `\nonscript` | 4, 8, 15, 2 | open |
| Line breaking | 21 | open (stretch goal) |

---

## 5. Audit checklist (run after layout changes)

- [ ] Every `Layout+*` builder sets width/ascent/descent on its box before
      returning; ink metrics where scripts can attach.
- [ ] Every recursive `box(for:)` call passes the right `display:`/`cramped:`
      (numerator not cramped, denominator/radicand/subscript cramped).
- [ ] New symbols carry a real `MathAtomClass` in `MathSymbolTable` — an
      `.ordinary` default silently breaks Rule 20 spacing.
- [ ] Goldens re-blessed knowingly, never wholesale; the coverage ratchet
      stays green in both directions.
- [ ] This document's statuses still tell the truth.
