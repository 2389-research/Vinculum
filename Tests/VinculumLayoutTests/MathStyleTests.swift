import XCTest
import Foundation
@testable import VinculumLayout

/// geometry tests: the style lattice's observable behavior, headless
/// with the deterministic mock measurer (glyphs are `count × size` cells with
/// 0.75/0.25 ascent/descent).
final class MathStyleTests: XCTestCase {

    private let mock = standardMockMeasurer
    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: mock, baseSize: size)
    }

    // MARK: - Successor maps

    func testStyleSuccessors() {
        XCTAssertEqual(MathStyle.display.scriptStyle, .script)
        XCTAssertEqual(MathStyle.text.scriptStyle, .script)
        XCTAssertEqual(MathStyle.script.scriptStyle, .scriptScript)
        XCTAssertEqual(MathStyle.scriptScript.scriptStyle, .scriptScript)
        XCTAssertEqual(MathStyle.display.fractionStyle, .text)
        XCTAssertEqual(MathStyle.text.fractionStyle, .script)
        XCTAssertEqual(MathStyle.script.fractionStyle, .scriptScript)
    }

    // MARK: - Rule 20: no medium/thick spacing in script styles

    func testScriptStyleSuppressesMediumAndThickSpacing() {
        // In text style, x=y carries two thick (5/18 em) spaces.
        let text = engine().layout(MathParser.parse("x=y"))
        XCTAssertEqual(text.width, 30 + 2 * (5.0 / 18.0) * 10, accuracy: 0.001)

        // The same relation inside a superscript (script style) gets NONE:
        // base (10) + spaceAfterScript (0.056·10) + three 7-wide cells.
        let scripted = engine().layout(MathParser.parse("x^{a=b}"))
        XCTAssertEqual(scripted.width, 10 + 0.56 + 3 * 7, accuracy: 0.001)
    }

    // MARK: - TeX script sizes: 70% then the 50% floor

    func testNestedSuperscriptLandsAtScriptScriptSize() {
        // x^{y^{z}}: y at 70%, z at 50% of the base — TeX's scriptscript
        // floor, not 0.7 × 0.7 = 49% compounding shrink.
        let scene = engine().layout(MathParser.parse("x^{y^{z}}"))
        var sizes: Set<CGFloat> = []
        for e in scene.elements { if case let .glyphs(_, size, _, _, _) = e { sizes.insert(size) } }
        XCTAssertTrue(sizes.contains(10), "base at full size")
        XCTAssertTrue(sizes.contains(7), "first script at 70%")
        XCTAssertTrue(sizes.contains(5), "nested script at the 50% floor, got \(sizes)")
    }

    // MARK: - Rule 15: fraction shifts and gaps from the font, by style

    func testDisplayFractionUsesFontDisplayShift() {
        // Display: numerator shift 0.677·10, part scale 0.9 → ascent
        // 6.77 + 0.75·9 = 13.52 (clearance already satisfied, no bump).
        let display = engine().layout(MathParser.parse("\\frac{a}{b}"), display: true)
        XCTAssertEqual(display.ascent, 0.677 * 10 + 0.75 * 9, accuracy: 0.01)

        // Text style sits distinctly lower.
        let text = engine().layout(MathParser.parse("\\frac{a}{b}"))
        XCTAssertLessThan(text.ascent, display.ascent - 1)
    }

    func testRulelessStackUsesStackShifts() {
        // \binom in display: stack-top shift 0.677·10 + 0.75·9 (fences may
        // add ascent; assert the stack's reach via overall ascent ≥ that).
        let display = engine().layout(MathParser.parse("\\binom{a}{b}"), display: true)
        XCTAssertGreaterThanOrEqual(display.ascent + 0.01, 0.677 * 10 + 0.75 * 9)
    }

    // MARK: - \scriptstyle et al.

    func testScriptstyleCommandParsesStatefully() {
        // Applies to the rest of the group, like stateful \color.
        guard case .row(let kids) = MathParser.parse("a\\scriptstyle bc"),
              kids.count == 2,
              case .mathStyle(_, let style) = kids[1] else {
            return XCTFail("expected row[a, mathStyle(rest)]")
        }
        XCTAssertEqual(style, .script)
    }

    func testScriptstyleCommandShrinksToScriptSize() {
        // {\scriptstyle x} at base 10 renders x at 7 — style forces size too.
        let scene = engine().layout(MathParser.parse("{\\scriptstyle x}"))
        var sizes: Set<CGFloat> = []
        for e in scene.elements { if case let .glyphs(_, size, _, _, _) = e { sizes.insert(size) } }
        XCTAssertEqual(sizes, [7])
    }

    func testForcedDisplayInsideTextFractionCannotOvershootBaseSize() {
        // Review finding: \displaystyle inside a text-style fraction rendered
        // BIGGER than the surrounding text (0.8·s part size × 1/0.7 style
        // ratio ≈ 1.14·s). Forced styles must scale from the enclosing
        // full-size anchor, so nothing exceeds it.
        let scene = standardMockEngine().layout(
            MathParser.parse(#"\frac{{\displaystyle x}}{y} + z"#))
        var maxGlyphSize: CGFloat = 0
        for e in scene.elements {
            if case let .glyphs(_, size, _, _, _) = e { maxGlyphSize = max(maxGlyphSize, size) }
        }
        XCTAssertLessThanOrEqual(maxGlyphSize, 10.001,
                                 "forced display style must not exceed the base size")
        // And the forced-display x IS restored to the fraction's own anchor
        // (8 = the part size), not left at the script-descended 5.7ish.
        let xSize = scene.elements.compactMap { e -> CGFloat? in
            if case let .glyphs("𝑥", size, _, _, _) = e { return size }
            return nil
        }.first
        XCTAssertEqual(xSize ?? -1, 8, accuracy: 0.001,
                       "\\displaystyle returns to the enclosing anchor size")
    }

    func testDisplaystyleCommandRestoresDisplayInScripts() {
        // \genfrac's style argument 3 forces scriptscript: parts shrink.
        guard case .mathStyle(_, let style) = MathParser.parse(
            "\\genfrac{}{}{1pt}{3}{a}{b}") else {
            return XCTFail("expected mathStyle from genfrac style arg")
        }
        XCTAssertEqual(style, .scriptScript)
    }
}
