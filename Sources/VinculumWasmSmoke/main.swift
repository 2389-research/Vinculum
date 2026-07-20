import Foundation
import VinculumLayout

// Headless SVG render smoke — the CI proof that VinculumLayout + MathSVGRenderer
// work on the target (notably wasm32, where it runs under wasmtime). Renders the
// parity corpus to SVG with the deterministic mock measurer and asserts each is a
// non-empty SVG carrying ink. Foundation-only, so it builds and runs anywhere the
// layout product does — and doubles as the reference headless/server-side SVG
// entry point. Exits non-zero on any failure so CI catches it.

let mock: MathTextMeasurer = { text, size, _ in
    GlyphMetrics(width: CGFloat(text.count) * size * 0.5, ascent: size * 0.7,
                 descent: size * 0.2, inkAscent: size * 0.6, inkDescent: -size * 0.05)
}

let corpus = [
    #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
    #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#,
    #"e^{i\pi} + 1 = 0"#,
]

var failures = 0
for latex in corpus {
    let scene = MathLayoutEngine(measure: mock, baseSize: 20).layout(MathParser.parse(latex), display: true)
    let svg = MathSVGRenderer.svg(for: scene)
    let ok = svg.contains("<svg") && (svg.contains("<text") || svg.contains("<rect") || svg.contains("<path"))
    print("\(ok ? "OK " : "FAIL") \(svg.utf8.count) bytes  \(latex)")
    if !ok { failures += 1 }
}
if failures == 0 {
    print("VINCULUM_SVG_SMOKE: PASS (\(corpus.count) equations)")
} else {
    print("VINCULUM_SVG_SMOKE: FAIL (\(failures)/\(corpus.count))")
    exit(1)
}
