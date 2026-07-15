# Fonts

Vinculum typesets with **OpenType MATH fonts** — the same font technology
LuaTeX, XeTeX, and Microsoft Word's equation editor use. Five fonts are
bundled, and any `.otf` carrying a MATH table loads at runtime. This
document covers what each bundled font is for, exactly what Vinculum reads
from a font, how to select and supply fonts, and what happens when
something is missing.

The always-current specimen (CI regenerates it on every push):

![The same equations in all four bundled fonts](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/07-fonts.png)

---

## The bundled five

| | `.latinModern` | `.termes` | `.pagella` | `.stixTwo` | `.firaMath` |
| --- | --- | --- | --- | --- | --- |
| Full name | Latin Modern Math | TeX Gyre Termes Math | TeX Gyre Pagella Math | STIX Two Math | Fira Math |
| Lineage | Computer Modern (Knuth) | Times | Palatino (Zapf) | STIX / Times tradition | Fira Sans (Mozilla) |
| Pair with | LaTeX-look documents, code-adjacent docs | Times, Georgia, most serif body text | Palatino, Book Antiqua, humanist serifs | Scientific publishing stacks | SF, Helvetica, modern UI text |
| Voice | The classic TeX look: high contrast, fine hairlines | Narrow, upright, editorial | Round, calligraphic, warm | Sturdy, dense, designed for small print | Sans-serif, monolinear, contemporary |
| License | GUST Font License | GUST Font License | GUST Font License | SIL Open Font License | SIL Open Font License |
| File size | ~730 KB | ~530 KB | ~600 KB | ~840 KB | ~180 KB |

**An honest note on how different they look:** all four are serif math
faces from the same broad tradition, so at body sizes they read as
siblings — that is deliberate. Math fonts are chosen to *harmonize with
the surrounding text face*, not to stand out from each other; the
differences live in the italic letterforms (compare `a g x y` in the
specimen), the script/calligraphic alphabets (each font's `\mathcal{L}`
is practically its own design), stroke contrast, and the display-operator
sizes. For a genuinely different voice, `.firaMath` is the bundled sans-serif —
unmistakable next to the serif four — and Noto Sans Math loads via
`MathFont(url:)`.

The alphabet sub-specimen shows each face's letterforms, Greek, and
script alphabets side by side (CI-regenerated):

![Alphabets and scripts per font](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/09-font-alphabets.png)

Glyph by glyph, the designs diverge clearly (CI-regenerated):

![The same glyphs in all four fonts, side by side](https://raw.githubusercontent.com/2389-research/Vinculum/gallery/08-font-glyphs.png)

They are not interchangeable metrics-wise — that is the point. A few
numbers Vinculum reads from each font's `MathConstants` (em fractions):

| Constant | Latin Modern | Termes | Pagella | STIX Two | Fira Math |
| --- | --- | --- | --- | --- | --- |
| `AxisHeight` (fraction-bar height) | 0.250 | 0.250 | 0.250 | 0.258 | 0.280 |
| `DisplayOperatorMinHeight` (∑/∫ display size) | 1.300 | 1.300 | 1.500 | 1.800 | 1.500 |
| Cut-in kerning coverage (`MathKernInfo`) | — | — | — | **233 glyphs** | — |

So STIX Two draws noticeably larger display operators, sits its fraction
bars slightly higher, and positions scripts against per-glyph corner
profiles no other bundled font provides. None of this is configured —
it is read from the font at load.

## Selecting a font

Every render surface takes a `MathFont`; the default everywhere is
`.latinModern`.

```swift
// The label:
let label = VinculumLabel()
label.font = .pagella
label.latex = #"\oint_C \vec{F}\cdot d\vec{r}"#

// SwiftUI:
MathView(#"\zeta(s) = \sum_{n=1}^{\infty} n^{-s}"#).mathFont(.stixTwo)

// The attachment API (inline math in a text view):
MathImageRenderer.attachmentString(latex: src, display: false,
                                   mathTheme: .light, baseSize: 15,
                                   font: .termes)

// The full pipeline, if you drive it yourself:
let engine = MathLayoutEngine.make(font: .stixTwo, baseSize: 15)
let scene = engine.layout(node, display: true)
MathSceneRenderer.draw(scene, theme: .light, in: ctx, at: pen, font: .stixTwo)
```

**A scene must be drawn with the font it was measured with** — `MathScene`
carries font-specific glyph IDs, which is why `MathSceneRenderer.draw`
takes `font:` with no default. `MathLayoutEngine.make(font:baseSize:)` is
the one correct way to build an engine on Apple platforms: it wires the
measurer, the font's constants, delimiter variants, glyph assemblies,
per-glyph typography, and wide-accent variants in one call. (The bare
`MathLayoutEngine(measure:baseSize:)` initializer exists for headless
hosts injecting their own seams; it deliberately carries no font
capabilities.)

Renders are cached per font: the cache key includes the font's name along
with content, theme, and size, so switching fonts never serves stale
bitmaps.

## Bringing your own font

```swift
guard let custom = MathFont(url: myFontURL) else {
    // Not a loadable font, or no MATH table — see below.
    return
}
label.font = custom
```

Requirements and behavior:

- **The MATH table is mandatory.** `MathFont(url:)` returns `nil` for
  fonts without one — a text font cannot typeset math, and Vinculum
  refuses to guess. Math-capable free fonts include the TeX Gyre family,
  XITS, Libertinus Math, Fira Math, and Noto Sans Math.
- Everything is parsed **once, eagerly, at load**: the 56 layout
  constants, per-glyph italic corrections / accent attachment points /
  cut-in kerns, size-variant ladders, and glyph assemblies. A `MathFont`
  is immutable afterwards and safe to share across threads.
- Malformed sub-tables degrade gracefully: a font with (say) a corrupt
  variants table still renders — tall delimiters fall back to continuous
  scaling, exactly like the headless path.
- Give custom fonts distinct file names: the render cache keys on the
  font's `name` (derived from the file name).

## What Vinculum reads from a font

| MATH sub-table | What it drives |
| --- | --- |
| `MathConstants` (56 values) | Axis height, all rule thicknesses and clearances, script scale-downs and shifts, fraction/stack constant pairs (display vs text), limit gaps, radical geometry, `SpaceAfterScript`, `DisplayOperatorMinHeight` |
| `MathItalicsCorrectionInfo` | Superscript/subscript split on slanted glyphs (`f^2_3`), integral subscript tuck, stacked-limit skew |
| `MathTopAccentAttachment` | Where `\hat`/`\vec`/… sit on each glyph |
| `MathKernInfo` | Cut-in kerning: scripts nestle into the base glyph's corner profile (staircase-sampled at the script's height) |
| `MathVariants` — variant ladders | Purpose-drawn taller/wider cuts for delimiters, radicals, display operators, and wide accents |
| `MathVariants` — glyph assemblies | Arbitrarily tall fences and radicals built from end caps + extenders at constant stroke weight |

If a font omits an optional piece (Latin Modern ships no `MathKernInfo`;
some fonts have no horizontal variants), the corresponding refinement is
skipped — layout falls back to the constant-driven behavior, never to a
broken render.

## Headless / Linux

`VinculumLayout` builds without any font: the engine's constants default
to `.latinModern` — a fontTools-verified transcription of Latin Modern
Math's values, pinned by tests against committed raw MATH-table bytes —
so geometry tests and server-side layout produce TeX-true numbers with no
font file present. All per-glyph refinements (kerning, attachment points,
variants, assemblies) are provider seams that headless hosts may supply
or omit.

## Licensing

All bundled fonts permit redistribution and embedding. License texts ship
inside the package next to the fonts (`Sources/VinculumRender/Resources/`):

- **Latin Modern Math, TeX Gyre Termes Math, TeX Gyre Pagella Math** —
  [GUST Font License](../Sources/VinculumRender/Resources/GUST-FONT-LICENSE.txt)
  (an OFL-style license).
- **STIX Two Math** —
  [SIL Open Font License](../Sources/VinculumRender/Resources/OFL-STIXTwo.txt).

When you bundle your own font, its license travels with your app — check
that it permits embedding.
