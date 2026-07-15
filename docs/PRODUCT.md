# Vinculum — Product Data

Structured product facts for downstream consumption (site design, marketing
copy, comparison pages). **Pure data**: no taglines, no visual/format
decisions. Every claim here is implemented and tested on `main`; deep
detail is linked per item.

---

## Identity

| Key | Value |
| --- | --- |
| Name | Vinculum |
| What it is | Native LaTeX math typesetting library. Renders on Apple platforms (CoreText) and on Linux (Silica/Cairo/FreeType → PNG); layout is platform-free |
| Version | 1.4.0+ (SemVer; see [CHANGELOG.md](https://github.com/2389-research/Vinculum/blob/main/CHANGELOG.md)) |
| License (code) | MIT |
| License (bundled fonts) | GUST Font License (Latin Modern, TeX Gyre Termes/Pagella), SIL OFL (STIX Two, Fira Math) — redistribution/embedding permitted |
| Repo | https://github.com/2389-research/Vinculum |
| Install | SwiftPM: `.package(url: "https://github.com/2389-research/Vinculum.git", from: "1.0.0")` |
| Products | `VinculumRender` (rendering — CoreText on Apple, Silica/Cairo/FreeType on Linux), `VinculumLayout` (Foundation-only parsing + layout, all platforms) |
| Platforms | macOS 14+, iOS 17+, visionOS 1+, tvOS 17+; **Linux (rendering via Silica + layout)** |
| Language/runtime | Swift 6.2+ toolchain (Swift 6 language mode), strict concurrency, `Sendable` API, zero third-party dependencies |
| Origin | Extracted from [Quoin](https://github.com/clintecker/quoin); sibling of [MermaidKit](https://github.com/clintecker/MermaidKit) |

## Target audiences

| Audience | Job to be done | Features that matter most (see groups below) |
| --- | --- | --- |
| AI/LLM chat-app developers | Render model responses containing `\(…\)`/`\[…\]`/`$…$` math natively in message views | G3 document pipeline, G6 fallback contract, G6 caching/perf, G5 accessibility |
| Notes / education / flashcard apps | Math inside user documents and study material, flowing with text | G3 (all surfaces), G2 command coverage, G4 fonts |
| Scientific/technical publishing tools | Print-grade typography matching TeX output | G1 typography, G4 fonts, G2 environments |
| Accessibility-focused teams | Math that VoiceOver reads meaningfully | G5 spoken math |
| Platform/infra engineers | Deterministic, testable, dependency-free rendering; server-side layout | G7 engineering, G3 custom-renderer seam |
| Editor/tool builders | Selection, inspection, source round-tripping over rendered math | G7 hit-testing, round-trip, diagnostics |

## Feature groups

### G1 — Typography quality (the font is the authority)

Everything the OpenType MATH standard defines, read from the live font at
load and used in layout. Deep detail: [ALGORITHM.md](https://github.com/2389-research/Vinculum/blob/main/docs/ALGORITHM.md)
(rule-by-rule TeX Appendix G audit), [ARCHITECTURE.md](https://github.com/2389-research/Vinculum/blob/main/docs/ARCHITECTURE.md).

| Feature | Specific |
| --- | --- |
| Font-parsed layout constants | All 56 `MathConstants` values (axis height, every shift/clearance/thickness, script scales) — no hardcoded metrics |
| TeX style lattice | display/text/script/scriptscript × cramped; style-correct constant pairs; spacing suppression in scripts; `\displaystyle` family |
| Italic correction | Per-glyph: superscript/subscript split (`f^2_3`), integral subscript tuck (`\int_a^b`), stacked-limit skew |
| Cut-in kerning | OpenType `MathKernInfo` staircases position scripts against the base glyph's corner profile (STIX Two ships data for 233 glyphs) |
| Optical scripts (`ssty`) | Script/scriptscript glyphs use the font's purpose-redrawn heavier-stroked variants (parsed from GSUB, 995 glyphs in LM Math), so shrunk superscripts and deep indices keep the base text's weight instead of thinning out |
| Accent placement | Per-glyph `topAccentAttachment` (better than TeX's `\skewchar`); `AccentBaseHeight` seat; wide accents from horizontal variant ladders; combining-mark accents (`\vec`) via the glyph-ID path for exact ink seating; `\hat{f}^2` script promotion |
| Tall delimiters | Size-variant ladders → glyph assembly (end caps + extenders, constant stroke weight) → scaling, for every covered glyph |
| Radicals | The font's √ glyph via variants + assembly; font-true degree kerns and 60% raise |
| Display operators | Font's display-size variants at `DisplayOperatorMinHeight`, axis-centered; TeX Rule 13a limit clearances |
| Fence sizing | TeX's `\delimiterfactor`/`\delimitershortfall` formula |
| Inter-atom spacing | The complete TeXbook p. 170 pair table — all 8 atom classes including Inner (fractions, `\left…\right` groups, ellipses), transcribed cell-for-cell and test-pinned against an independent transcription; parenthesized entries suppressed in script styles; binary→unary reclassification (Appendix G rules 5–6) |

Screenshots (CI-regenerated from current code, stable raw URLs):
- Real equations: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/04-equations.png
- Tall fences/assembly: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/02-structures.png
- The pair-spacing table in action (reclassification, Inner atoms, script suppression): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-spacing.png
- The delimiter stretch chain (variants → assembly → \big family): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-delimiters.png
- The style lattice (script shrink, forced styles, display operators): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/arch-styles.png
- Per-rule figures (radicals, accents, operators, fractions, scripts, decorations): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-radicals.png · https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-accents.png · https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-operators.png · https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-fractions.png · https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-scripts.png · https://raw.githubusercontent.com/2389-research/Vinculum/gallery/alg-decorations.png
- Stress corpus page: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/page-06.png

### G2 — LaTeX coverage

Deep detail: [COMMANDS.md](https://github.com/2389-research/Vinculum/blob/main/docs/COMMANDS.md) (every supported command),
[COVERAGE.md](https://github.com/2389-research/Vinculum/blob/main/docs/COVERAGE.md) (feature-by-feature with examples).

| Feature | Specific |
| --- | --- |
| Symbols | 404 symbol commands + 37 named operators (Greek, operators, relations, arrows, delimiters, letterlike sets), each with its correct TeX atom class — including the Inner class for ellipses (`f(x_1,\ldots,x_n)` spaces as TeX sets it) |
| Structures | Fractions (`\frac`/`\cfrac`/`\genfrac`/`\binom`), radicals with degree, scripts, accents, over/under constructs, boxes/rules/strikes, `\phantom` family, colors |
| Environments | All matrix variants, `cases`, `aligned`/`align`/`gather`/`split`/`multline`, `array` with column specs + `\hline`/`\cline`, `\substack`, `\tag` |
| Macros | Document-scoped `\newcommand`/`\renewcommand`/`\def` with `#1…#9`, recursion-capped |
| Direct Unicode | `∫ ∑ ≤ α` classed like their command spellings |
| Named operators | 37 function names; `\operatorname`/`\operatorname*` |
| Explicitly out of scope | mhchem, siunitx, `\href`, embedded HTML, `\begin{CD}` |

Screenshots: one specimen chart per atom class, CI-regenerated with a sync
guard (a new atom class cannot silently drop commands from the charts):
- Relations: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-relations.png
- Binary operators: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-binary.png
- Big operators: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-operators.png
- Ordinary/Greek/letterlike/arrows: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-ordinary.png
- Opening/closing delimiters: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-open.png · https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-close.png
- Punctuation: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-punct.png · Inner (ellipses): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-inner.png
- Function-name operators: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/sym-functions.png
- Structural commands, source beside render: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/cmd-structural.png

### G3 — Integration surfaces

Deep detail: [INTEGRATION.md](https://github.com/2389-research/Vinculum/blob/main/docs/INTEGRATION.md), DocC catalog (Xcode ▸
Product ▸ Build Documentation).

| Surface | Call | Use case |
| --- | --- | --- |
| Document pipeline | `MathText.attributedString(from: wholeString)` | Prose with embedded math: markdown, chat, LLM output; all 4 delimiter styles; display math centered; document-scoped macros; unsupported math stays visible as source |
| Drop-in view | `VinculumLabel().latex = "…"` (AppKit/UIKit) | Standalone equations; alignment, insets, intrinsic size, opt-in inline errors |
| SwiftUI | `MathView("…").mathFont(.pagella)` | SwiftUI apps; modifiers for font/theme/size/inline |
| Attachment | `MathImageRenderer.attachmentString(latex:…)` | Rich-text composition; baseline-aligned `NSTextAttachment`; cached |
| Image + metadata | `MathImageRenderer.rendered(latex:…)` | Image, baseline descent, spoken description |
| Scene IR + custom renderer | `MathLayoutEngine.make(font:baseSize:)` → `MathScene` → `MathSceneRenderer.draw` or your own (glyph resolution via public `MathFont.ctFont(size:)`) | PDF pipelines, custom drawing, headless layout |
| SVG (server-side) | `MathSVGRenderer.svg(for: scene, embeddedFont: otfBytes)` | Linux/Vapor/static-site rendering; self-contained SVG with embedded font |
| Linux PNG | `MathSilicaRenderer.renderPNG(latex:resource:baseSize:display:)` | Native raster rendering on Linux via Silica/Cairo/FreeType; loads the bundled MATH fonts from bytes ([LINUX.md](https://github.com/2389-research/Vinculum/blob/main/docs/LINUX.md)) |

Code example (the LLM case):

```swift
textView.textStorage?.setAttributedString(
    MathText.attributedString(from: modelResponse))
```

### G4 — Fonts

Deep detail: [FONTS.md](https://github.com/2389-research/Vinculum/blob/main/docs/FONTS.md).

| Feature | Specific |
| --- | --- |
| Bundled fonts | Latin Modern Math (default), TeX Gyre Termes Math, TeX Gyre Pagella Math, STIX Two Math, Fira Math (sans-serif) |
| Bring-your-own | `MathFont(url:)` for any OTF with a MATH table; refuses fonts without one |
| Per-font truth | Constants/typography/variants/assemblies parsed per font at load; per-font render caching |
| Measured differences | Axis heights 0.250 (LM) / 0.258 (STIX) / 0.280 (Fira); `DisplayOperatorMinHeight` 1.3–1.8 em across faces; STIX ships cut-in kern data for 233 glyphs |

Screenshots:
- One equation per font (scannable overview): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/07-fonts.png
- Glyph-by-glyph comparison grid (fonts as columns): https://raw.githubusercontent.com/2389-research/Vinculum/gallery/08-font-glyphs.png
- Alphabet/script letterform sub-specimen per font: https://raw.githubusercontent.com/2389-research/Vinculum/gallery/09-font-alphabets.png

### G5 — Accessibility

| Feature | Specific |
| --- | --- |
| Spoken math | ClearSpeak-style utterances generated from the same tree that was typeset ("x equals the fraction negative b plus or minus the square root of b squared minus 4 a c, over 2 a") |
| Coverage | Fractions (incl. "1 half" simple forms), roots, scripts (squared/cubed/power), fences, matrices row-by-row, cases, binomials, accents, operators, ~80 symbol names |
| Where it applies | `VinculumLabel`, `MathView`, and every attachment image (math inside text views reads aloud) |
| API | `MathSpeech.describe(node)`; `RenderedMath.spokenDescription` |

### G6 — Reliability, safety, performance

| Feature | Specific |
| --- | --- |
| The fallback contract | Unsupported input degrades to named, visible source — never a broken half-render; `nil`/`isRendered` lets hosts keep their own fallback |
| Bounded parsing | Linear pre-scan + runtime depth counter; adversarial input (50 KB of `\sqrt\sqrt…`, 5,000 open braces) degrades instead of crashing |
| Fuzz-proven | Deterministic grammar/mutation/depth-attack corpora (4,000+ inputs): zero crashes, zero non-finite geometry |
| Adversarial font bytes | MATH-table parser is fully bounds-checked; crafted tables can't OOB or force multi-GB allocations |
| Caching | Content+theme+size+font keyed `NSCache`, count- and byte-bounded; negative caching for known-unsupported input |
| Measured performance | Cold parse→layout→raster ~0.3 ms; warm cache hit ~0.7 µs; headless layout ~40 µs (Apple silicon medians, enforced as test ceilings) |
| Concurrency | Swift 6 strict concurrency; immutable `Sendable` fonts/engines; audited lock discipline |

### G7 — Developer tooling

| Feature | Specific |
| --- | --- |
| Parse diagnostics with source ranges | `MathParser.diagnostics(for:)` → snippet + message + `Range<String.Index>` per issue (editor squiggles) |
| LaTeX round-trip | `MathNode.toLaTeX()`, render-equivalent and idempotent (copy-as-LaTeX, editing) |
| Hit-testing substrate | Opt-in `collectHitRegions` → `MathScene.hitTest(point)` → deepest subtree + rect + LaTeX (tap-to-inspect, selection) |
| Node model | Public `MathNode` tree with `children` traversal; `isFullySupported`, `unsupportedCommands` |
| DocC | Curated catalog (landing, Getting Started, Rendering Documents) |
| Demo app | `swift run VinculumDemo` — paste-and-render with font picker and dark toggle |

### G8 — Engineering & verification (trust signals)

| Feature | Specific |
| --- | --- |
| Test suite | 235 tests: headless geometry (Linux), golden-image regression with coverage ratchet, per-font canaries, fuzz, performance ceilings, the p. 170 spacing chart pinned cell-by-cell |
| CI matrix | Linux (headless layout), macOS (full suite), iOS simulator (runtime tests), gallery auto-publish |
| Golden discipline | 93 pixel-pinned fixtures; a fixture that *starts* rendering fails CI until promoted (coverage can't silently change) |
| Ground truth | MATH-table parsing pinned against committed raw font bytes and fontTools; inter-atom spacing pinned against the TeXbook p. 170 chart |
| Docs as verification | ~38 gallery images regenerate from the live engine on every push to `main`; a wrong-looking figure means a wrong engine (this pipeline caught a mis-seated `\vec` arrow and a chart-coverage regression) |
| Docs | Rule-by-rule TeX Appendix G audit ([ALGORITHM.md](https://github.com/2389-research/Vinculum/blob/main/docs/ALGORITHM.md)) stating Implemented/Partial/ABSENT honestly, with a rendered figure per rule cluster |

## Approach matrix (generic, no named competitors)

| Concern | WebView JS renderer | Server-side image | Vinculum |
| --- | --- | --- | --- |
| Runtime footprint | JS engine + web process per view | Network dependency | In-process, zero dependencies |
| Text integration (baseline, selection, line-breaking) | Snapshot only | Snapshot only | Native `NSTextAttachment` in the text system |
| Offline / privacy | Varies | No | Yes, fully on-device |
| Typography source | Web fonts + CSS | Varies | The font's own MATH table, per glyph |
| Macro-package breadth (mhchem, siunitx…) | Widest | Widest | Everyday-math subset by design |
| Deterministic/testable output | Engine-version dependent | Service dependent | Golden-pinned, headless-testable |
| Accessibility of math content | Varies | None (image) | Generated spoken math everywhere |

## Image asset inventory (all stable URLs, CI-refreshed on every push to `main`)

Every image regenerates from the live engine — always current, never
hand-made. Base URL: `https://raw.githubusercontent.com/2389-research/Vinculum/gallery/`.
White background, 2× resolution, PNG. Full set browsable on the
[gallery branch](https://github.com/2389-research/Vinculum/tree/gallery).

| Asset | Shows | Suited for |
| --- | --- | --- |
| `01-core.png` | Fractions, roots, scripts, big operators with limits — source beside render | Hero/feature: core typesetting |
| `02-structures.png` | Auto-sized delimiters, matrices, cases, aligned environments | Feature: structures/environments |
| `03-notation.png` | Accents, binomials, braces, arrows, math alphabets, color | Feature: notation breadth |
| `04-equations.png` | Six famous real-world equations (quadratic, Euler, Schrödinger, Bayes, Maxwell, ζ) | Hero: "what the output looks like" |
| `05-macros.png` | Document-scoped `\newcommand` definitions in use | Feature: macros |
| `06-symbols.png` | Standalone delimiters, relations/operators symbol coverage | Feature: symbol breadth |
| `07-fonts.png` | The same equation in each of the five bundled fonts, separated rows | Feature: font choice |
| `08-font-glyphs.png` | Glyph-by-glyph grid, fonts as columns | Font comparison detail |
| `09-font-alphabets.png` | Italic/Greek/script alphabets per font | Font letterform detail |
| `arch-spacing.png` | The TeXbook p. 170 pair table's visible consequences (classes, reclassification, Inner atoms, script suppression) | Typography-quality proof |
| `arch-delimiters.png` | Delimiter stretch chain: size variants → glyph assembly → `\big` family | Typography-quality proof |
| `arch-styles.png` | Style lattice: script shrink to the 50% floor, `\dfrac`/`\tfrac`, display operators | Typography-quality proof |
| `arch-fallback.png` | Unknown commands degrading to legible in-place source cards | Reliability/fallback story |
| `alg-radicals.png` · `alg-accents.png` · `alg-operators.png` · `alg-fractions.png` · `alg-scripts.png` · `alg-decorations.png` | One figure per TeX Appendix G rule cluster (matches ALGORITHM.md sections) | Deep-dive/algorithm pages |
| `sym-relations.png` · `sym-binary.png` · `sym-operators.png` · `sym-ordinary.png` · `sym-open.png` · `sym-close.png` · `sym-punct.png` · `sym-inner.png` · `sym-functions.png` | Specimen chart per atom class — every one of the 404+37 commands rendered | Command-reference pages |
| `cmd-structural.png` | Every structural command, source beside render | Command-reference pages |
| `page-01.png` … `page-09.png` | The 66-equation real-world stress corpus, all rendering natively | Depth/credibility ("it handles real documents") |

## Documentation index (link targets for any site)

| Module | Content |
| --- | --- |
| [README](https://github.com/2389-research/Vinculum/blob/main/README.md) | Overview, quick start, support matrix, gallery |
| [FONTS.md](https://github.com/2389-research/Vinculum/blob/main/docs/FONTS.md) | The five fonts, specimen comparisons, BYO fonts, licensing |
| [COMMANDS.md](https://github.com/2389-research/Vinculum/blob/main/docs/COMMANDS.md) | Every supported command, with a rendered specimen chart per section |
| [COVERAGE.md](https://github.com/2389-research/Vinculum/blob/main/docs/COVERAGE.md) | Feature-by-feature support matrix, one figure per section |
| [ALGORITHM.md](https://github.com/2389-research/Vinculum/blob/main/docs/ALGORITHM.md) | TeX Appendix G audit, illustrated per rule; sources (TeXbook, *Appendix G Illuminated*) |
| [ARCHITECTURE.md](https://github.com/2389-research/Vinculum/blob/main/docs/ARCHITECTURE.md) | The layout/render split, seams, IR — with design rationale ("why") sections and figures |
| [INTEGRATION.md](https://github.com/2389-research/Vinculum/blob/main/docs/INTEGRATION.md) | Host integration guide: attachments, documents, views, SVG, accessibility, hit-testing, threading, caching |
| [LINUX.md](https://github.com/2389-research/Vinculum/blob/main/docs/LINUX.md) | The Linux rendering backend (Silica/Cairo/FreeType): usage, build, macOS parity, known gaps |
| [ROADMAP.md](https://github.com/2389-research/Vinculum/blob/main/docs/ROADMAP.md) / [IMPLEMENTATION_PLAN.md](https://github.com/2389-research/Vinculum/blob/main/docs/IMPLEMENTATION_PLAN.md) | History + open items (internal planning) |
| [CHANGELOG.md](https://github.com/2389-research/Vinculum/blob/main/CHANGELOG.md) | Release history |
| DocC catalog | In-Xcode API reference |
| [Gallery branch](https://github.com/2389-research/Vinculum/tree/gallery) | Every screenshot above, CI-refreshed |

## Note on documentation modularization

Current modules are already single-topic. If further splitting is wanted
for a site, the natural seams are: FONTS.md → per-font pages;
COVERAGE.md → per-category pages (structures/environments/symbols);
ALGORITHM.md → per-rule anchors already exist (deep-linkable as-is).
Cross-linking is in place between README ↔ docs/* ↔ gallery.
