# ``VinculumRender``

Native LaTeX math typesetting: real glyph shapes and TeX metrics from the
font's OpenType MATH table — no WebView, zero dependencies.

## Overview

Vinculum parses LaTeX math into a TeX-style node tree and typesets it with
an OpenType MATH font, following Knuth's algorithm (Appendix G of *The
TeXbook*) with everything read from the font at runtime: all 56 layout
constants, per-glyph italic corrections and accent attachment points,
cut-in kerning, size-variant ladders, and glyph assemblies for arbitrarily
tall fences and radicals.

Three ways in, from highest-level to lowest:

```swift
// 1. A whole document — prose with embedded math (chat/LLM output, notes):
textView.textStorage?.setAttributedString(
    MathText.attributedString(from: modelResponse))

// 2. A drop-in view:
let label = VinculumLabel()
label.latex = #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#

// 3. One equation as a baseline-aligned attachment:
let attributed = MathImageRenderer.attachmentString(
    latex: #"e^{i\pi} + 1 = 0"#, display: true,
    mathTheme: .light, baseSize: 15)
```

Every equation carries a spoken-math description, so VoiceOver reads
mathematics aloud. Unsupported input degrades to visible styled source —
never a broken half-render.

### Why it's built this way

Vinculum borrows TeX's own separation: layout compiles LaTeX into a
device-independent `MathScene` (positioned primitives, y-up baseline
coordinates), and thin renderers project that scene into pixels, an
attachment, or SVG. The layout stage is Foundation-only — it builds and
tests headlessly on Linux — because glyph measurement is *injected* rather
than imported. That one seam is what makes the geometry unit-testable, the
caching sound, and the SVG backend possible.

The reference documentation on GitHub shows every claim as a CI-regenerated
render: [ARCHITECTURE](https://github.com/2389-research/Vinculum/blob/main/docs/ARCHITECTURE.md)
(the design and its whys, illustrated),
[ALGORITHM](https://github.com/2389-research/Vinculum/blob/main/docs/ALGORITHM.md)
(the rule-by-rule TeX Appendix G audit, one figure per rule cluster),
[COMMANDS](https://github.com/2389-research/Vinculum/blob/main/docs/COMMANDS.md)
(every supported command with specimen charts), and
[FONTS](https://github.com/2389-research/Vinculum/blob/main/docs/FONTS.md)
(the five bundled faces, compared).

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:RenderingDocuments>

### Rendering documents and equations

- ``MathText``
- ``VinculumLabel``
- ``MathView``
- ``MathImageRenderer``

### Fonts

- ``MathFont``
- ``MathTheme``

### The rendering pipeline

- ``MathSceneRenderer``
- ``CoreTextMeasurer``
- ``CoreTextDelimiterProvider``
- ``CoreTextTypographyProvider``
