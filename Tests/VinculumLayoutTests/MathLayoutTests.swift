import XCTest
import Foundation
@testable import VinculumLayout

/// Headless geometry tests: the layout engine runs with a DETERMINISTIC mock
/// measurer (no CoreText, no font), so these prove the layout is platform-free
/// and assert scene structure directly — the analog of MermaidKit's layout
/// linter. They run on Linux.
final class MathLayoutTests: XCTestCase {

    /// Every glyph is a `size`-square cell, so metrics are exact and testable.
    private let mock = standardMockMeasurer
    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: mock, baseSize: size)
    }

    func testSymbolSceneHasOneGlyphRun() {
        let scene = engine().layout(.symbol("x", .ordinary, style: .italic))
        XCTAssertEqual(scene.width, 10, accuracy: 0.001)       // one 10-wide cell
        let glyphs = scene.elements.filter { if case .glyphs = $0 { return true }; return false }
        XCTAssertEqual(glyphs.count, 1)
    }

    func testFractionEmitsARuleAndStacks() {
        let scene = engine().layout(MathParser.parse("\\frac{1}{2}"))
        let rules = scene.elements.filter { if case .rule = $0 { return true }; return false }
        XCTAssertEqual(rules.count, 1, "a fraction has exactly one rule (the bar)")
        // Numerator + rule + denominator is far taller than a single cell.
        XCTAssertGreaterThan(scene.height, 10 * 1.5)
    }

    func testRelationSpacingIsTeXThickSpace() {
        // With a mock where each glyph is `size` wide, x=y is 3 cells (30) plus
        // two TeX thick spaces (2 · 5/18 · size) around the relation.
        let s = engine().layout(MathParser.parse("x=y"))
        let expected = 30 + 2 * (5.0 / 18.0) * 10
        XCTAssertEqual(s.width, expected, accuracy: 0.001)
    }

    func testColorSubtreeCarriesResolvedSRGB() {
        let s = engine().layout(MathParser.parse("\\color{red}{x}"))
        guard case let .glyphs(_, _, _, _, color) = s.elements.first else {
            return XCTFail("expected a glyph run")
        }
        XCTAssertEqual(color, MathColor.resolve("red"))
    }

    func testIntegralKeepsSideScriptsButSumStacksInDisplay() {
        // In display, ∑ stacks its limits (taller than wide) while ∫ keeps them
        // to the side (wider, shorter) — TeX's \limits vs \nolimits defaults.
        let sum = engine().layout(MathParser.parse("\\sum_{i=1}^{n}"), display: true)
        let int = engine().layout(MathParser.parse("\\int_{0}^{1}"), display: true)
        XCTAssertGreaterThan(sum.height, sum.width, "∑ stacks its limits")
        XCTAssertGreaterThan(int.width, int.height, "∫ keeps side scripts")
    }

    func testNamedOperatorLimitStacksInDisplay() {
        // \lim_{x} stacks the limit underneath in display (it's a function name,
        // which used to miss the limits path).
        let e = engine()
        let stacked = e.layout(MathParser.parse("\\lim_{x}"), display: true)
        let inline  = e.layout(MathParser.parse("\\lim_{x}"), display: false)
        XCTAssertGreaterThan(stacked.height, inline.height, "the limit moves under the operator")
    }

    func testDfracForcesDisplaySizeInline() {
        // \dfrac inline lays out at display size — taller than an inline \frac.
        let e = engine()
        let inlineFrac = e.layout(MathParser.parse("\\frac{a}{b}"), display: false)
        let dfrac = e.layout(MathParser.parse("\\dfrac{a}{b}"), display: false)
        XCTAssertGreaterThan(dfrac.height, inlineFrac.height, "\\dfrac forces the larger display style")
    }

    func testBigDelimiterEnlargesTheGlyph() {
        // \Big( is markedly taller than a plain (.
        let e = engine()
        let plain = e.layout(MathParser.parse("("), display: false)
        let big = e.layout(MathParser.parse("\\Big("), display: false)
        XCTAssertGreaterThan(big.height, plain.height * 1.4, "\\Big enlarges the delimiter")
    }

    func testUnaryMinusAfterRelationIsReclassified() {
        // x = -1 : the minus after a relation is unary → Ord (tight spacing).
        let out = MathLayoutEngine.reclassifyBinaries([.ordinary, .relation, .binary, .ordinary])
        XCTAssertEqual(out[2], .ordinary)
    }

    func testLeadingBinaryIsUnary() {
        XCTAssertEqual(MathLayoutEngine.reclassifyBinaries([.binary, .ordinary])[0], .ordinary)
    }

    func testBinaryBetweenOrdinariesStaysBinary() {
        XCTAssertEqual(MathLayoutEngine.reclassifyBinaries([.ordinary, .binary, .ordinary])[1], .binary)
    }

    func testBinaryBeforeRelationBecomesOrdinary() {
        // `+ =` : the binary left of a relation becomes Ord.
        let out = MathLayoutEngine.reclassifyBinaries([.ordinary, .binary, .relation, .ordinary])
        XCTAssertEqual(out[1], .ordinary)
    }

    func testCrampedSuperscriptRidesLower() {
        // The same z^2 laid out in cramped style is shorter — the exponent
        // sits lower (superscriptShiftUpCramped < superscriptShiftUp). Uses a
        // low-ink measurer so the nominal shift, not the tall-base clamp,
        // decides the height.
        let lowInk: MathTextMeasurer = { text, size, _ in
            GlyphMetrics(width: CGFloat(text.count) * size, ascent: size * 0.7, descent: size * 0.2,
                         inkAscent: size * 0.4, inkDescent: 0)
        }
        let node = MathParser.parse("z^2")
        var normal = MathLayoutEngine(measure: lowInk, baseSize: 10)
        var cramped = MathLayoutEngine(measure: lowInk, baseSize: 10); cramped.cramped = true
        let n = normal.box(for: node, size: 10, style: .text)
        let c = cramped.box(for: node, size: 10, style: .text)
        XCTAssertLessThan(c.ascent, n.ascent, "the cramped superscript rides lower")
    }

    func testArrayDrawsColumnAndRowRules() {
        let e = engine()
        let bare = e.layout(MathParser.parse(#"\begin{array}{cc} a & b \\ c & d \end{array}"#), display: false)
        let ruled = e.layout(MathParser.parse(#"\begin{array}{|c|c|} \hline a & b \\ \hline c & d \\ \hline \end{array}"#), display: false)
        func ruleCount(_ s: MathScene) -> Int {
            s.elements.filter { if case .rule = $0 { return true }; return false }.count
        }
        XCTAssertEqual(ruleCount(bare), 0, "a bare array draws no rules")
        // |c|c| = 3 vertical rules, three \hline = 3 horizontal → 6.
        XCTAssertGreaterThanOrEqual(ruleCount(ruled), 6, "bordered array draws its rules")
    }

    func testLapBoxesHaveZeroWidth() {
        // \mathrlap advances zero width; its content still draws.
        let e = engine()
        let lap = e.layout(MathParser.parse(#"\mathrlap{xyz}"#), display: false)
        let plain = e.layout(MathParser.parse("xyz"), display: false)
        XCTAssertEqual(lap.width, 0, accuracy: 0.001)
        XCTAssertEqual(lap.elements.count, plain.elements.count, "content is still drawn")
    }

    func testSmashReportsZeroHeight() {
        let e = engine()
        let smashed = e.layout(MathParser.parse(#"\smash{\sqrt{2}}"#), display: false)
        XCTAssertEqual(smashed.ascent, 0, accuracy: 0.001)
        XCTAssertEqual(smashed.descent, 0, accuracy: 0.001)
    }

    func testRadicalEmitsAStroke() {
        let s = engine().layout(MathParser.parse("\\sqrt{2}"))
        let strokes = s.elements.filter { if case .stroke = $0 { return true }; return false }
        XCTAssertEqual(strokes.count, 1, "the radical sign is one stroked path")
    }

    func testLayoutIsDeterministic() {
        let a = engine().layout(MathParser.parse("\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}"))
        let b = engine().layout(MathParser.parse("\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}"))
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.elements.count, b.elements.count)
    }
}
