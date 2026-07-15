import XCTest
import Foundation
@testable import VinculumLayout

/// `MathNode.toLaTeX()` round-trip. The contract is RENDER
/// equivalence: `parse(toLaTeX(parse(x)))` lays out to the same scene as
/// `parse(x)` under the deterministic mock measurer — string identity is
/// not required (Unicode symbols serialize as themselves).
final class MathRoundTripTests: XCTestCase {

    private let mock = standardMockMeasurer

    /// A representative corpus spanning every node kind.
    private static let corpus: [String] = [
        #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
        #"\sum_{i=1}^{n} i^2 \le \int_0^\infty e^{-x^2}\,dx"#,
        #"\sqrt[3]{x^2 + y^2} + \cfrac[r]{1}{1 + \cfrac{1}{x}}"#,
        #"\left( \frac{a}{b} \right) \left\langle u, v \right\rangle"#,
        #"\begin{pmatrix} a & b \\ c & d \end{pmatrix} \begin{cases} x & y \\ z & w \end{cases}"#,
        #"\begin{bmatrix} 1 \\ 2 \end{bmatrix} \begin{vmatrix} p & q \\ r & s \end{vmatrix}"#,
        #"\hat{x} + \vec{v} + \widehat{abc} + \overline{AB} + \underline{z}"#,
        #"\binom{n}{k} + \dbinom{n}{k} + \genfrac{[}{]}{0pt}{}{a}{b}"#,
        #"\overbrace{a+b}^{s} + \underbrace{c+d}_{t} + \overrightarrow{AB}"#,
        #"A \xLongrightarrow{f} B \xhookrightarrow{g} C \xmapsto{h} D \xrightleftharpoons{k}[l] E"#,
        #"P \xleftrightarrow{a} Q \xrightharpoonup{b} R \xleftharpoondown{c} S"#,
        #"\xrightarrow[g]{f} \quad \overset{!}{=} \quad \underset{k}{\to}"#,
        #"\boxed{E=mc^2} + \cancel{x} + \phantom{y} + \mathrlap{z}"#,
        #"\textcolor{red}{a} + \colorbox{yellow}{b}"#,
        #"\mathbin{\ast} \mathrel{\sim} \operatorname{softmax}(z) \operatorname*{argmin}_x"#,
        #"\lim_{x \to 0} \frac{\sin x}{x} \quad \sin\theta + \log n"#,
        #"{\scriptstyle small} + {\displaystyle big} + \dfrac{1}{2} + \tfrac{3}{4}"#,
        #"\bigl( x \bigr) + \Bigg[ y \Bigg]"#,
        #"\rule{1em}{0.5em} + \raisebox{0.5em}{up}"#,
        #"\mathbf{Av} + \mathrm{const} + \alpha\beta\gamma"#,
        #"a \not= b \quad \sum_{\substack{i < n \\ i > 0}} i"#,
        #"\not a + \not\alpha + \not\subset"#,   // letter args must not fuse into \nota
        #"\begin{array}{l|c} a & b \\ \hline c & d \end{array}"#,
        #"\begin{aligned} a &= b \\ &= c \end{aligned}"#,
        #"\left\{ x \middle| x > 0 \right\}"#,
        #"\hspace{0.3em} x \qquad y \, z \; w"#,
        // Legacy/infix constructs (iosMath corpus): infix fractions, old-style
        // font switches, and \int\limits stacking must all round-trip. Each
        // switch is braced to its own group (a stateful switch's scope is the
        // group; nesting two unbraced switches is genuinely order-dependent).
        #"{a+b \over c+d} + {n \choose k} + {n \atop k} + {p \brace q} + {r \brack s}"#,
        #"\vec{\bf E} + {\cal C} + {\frak Q} + {\bb R} + {\scr S}"#,
        #"\int\limits_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}"#,
    ]

    func testCorpusRoundTripsToIdenticalScenes() {
        let engine = MathLayoutEngine(measure: mock, baseSize: 12)
        for latex in Self.corpus {
            let original = MathParser.parse(latex)
            XCTAssertTrue(MathParser.isFullySupported(original),
                          "corpus entry unsupported outright: \(latex)")
            let serialized = original.toLaTeX()
            let reparsed = MathParser.parse(serialized)
            XCTAssertTrue(MathParser.isFullySupported(reparsed),
                          "round-trip output failed to parse: \(serialized)")

            let a = engine.layout(original, display: true)
            let b = engine.layout(reparsed, display: true)
            XCTAssertEqual(a.width, b.width, accuracy: 0.001, "width drift: \(latex) → \(serialized)")
            XCTAssertEqual(a.ascent, b.ascent, accuracy: 0.001, "ascent drift: \(latex) → \(serialized)")
            XCTAssertEqual(a.descent, b.descent, accuracy: 0.001, "descent drift: \(latex) → \(serialized)")
            XCTAssertEqual(String(describing: a.elements), String(describing: b.elements),
                           "scene drift: \(latex) → \(serialized)")
        }
    }

    func testSerializationIsStable() {
        // toLaTeX ∘ parse must be a fixed point after one iteration.
        for latex in Self.corpus {
            let once = MathParser.parse(latex).toLaTeX()
            let twice = MathParser.parse(once).toLaTeX()
            XCTAssertEqual(once, twice, "serialization not idempotent for: \(latex)")
        }
    }
}
