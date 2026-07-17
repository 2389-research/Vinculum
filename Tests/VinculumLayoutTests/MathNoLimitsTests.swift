import XCTest
@testable import VinculumLayout

/// `\nolimits` forces an operator's scripts to the SIDE even in display style —
/// TeX's standard way to keep an operator compact inside a display equation
/// (`\sum\nolimits_{i=1}^n` → ∑ᵢ₌₁ⁿ, scripts to the right).
///
/// The parser recognised `\nolimits`, consumed the token, and threw the modifier
/// away. Placement is decided from the operator's identity alone, so the request
/// had no effect and a real LaTeX semantic was silently dropped — including from
/// `toLaTeX()`, so a round-trip lost it too (#20).
final class MathNoLimitsTests: XCTestCase {

    private func scene(_ latex: String, display: Bool = true) -> MathScene {
        standardMockEngine(10).layout(MathParser.parse(latex), display: display)
    }

    /// The defining behaviour: side-set scripts make the box WIDER and much
    /// shorter than the stacked form.
    func testNoLimitsSetsScriptsToTheSideInDisplayStyle() {
        let stacked = scene(#"\sum_a^b"#)
        let noLimits = scene(#"\sum\nolimits_a^b"#)

        XCTAssertGreaterThan(noLimits.width, stacked.width,
                             "side-set scripts sit beside the operator, so the box widens")
        XCTAssertLessThan(noLimits.ascent, stacked.ascent,
                          "nothing is stacked above the operator any more")
    }

    /// It must match the side-set placement text style already produces —
    /// same script positions, since only the placement rule changed.
    func testNoLimitsMatchesTextStyleScriptPlacement() {
        let noLimits = scene(#"\sum\nolimits_a^b"#, display: true)
        let textStyle = scene(#"\sum_a^b"#, display: false)
        XCTAssertEqual(noLimits.width, textStyle.width, accuracy: 0.001,
                       "\\nolimits places scripts exactly where text style does")
    }

    /// …but the OPERATOR itself stays display-size. `\nolimits` moves the
    /// scripts; it does not demote the operator to text size. If this ever goes
    /// red, the fix has overreached into changing the operator's own geometry.
    func testNoLimitsKeepsTheOperatorAtDisplaySize() {
        let noLimits = scene(#"\sum\nolimits_a^b"#, display: true)
        let textStyle = scene(#"\sum_a^b"#, display: false)
        XCTAssertGreaterThan(noLimits.ascent, textStyle.ascent,
                             "the operator stays display-size — only its scripts moved")
    }

    // MARK: - What must NOT change

    func testPlainDisplaySumStillStacks() {
        let stacked = scene(#"\sum_a^b"#)
        XCTAssertGreaterThan(stacked.ascent, stacked.width * 0.5,
                             "an unmodified display \\sum still stacks its limits")
    }

    func testLimitsStillForcesStacking() {
        let forced = scene(#"\int\limits_a^b"#)
        let plain = scene(#"\int_a^b"#)
        XCTAssertGreaterThan(forced.ascent, plain.ascent,
                             "\\limits still forces an integral to stack")
    }

    /// `\displaylimits` restores the CURRENT style's default placement, which for
    /// an unmodified display \sum is already stacked — so dropping it is correct,
    /// unlike `\nolimits`. This pins that distinction.
    func testDisplayLimitsRemainsANoOp() {
        let plain = scene(#"\sum_a^b"#)
        let explicit = scene(#"\sum\displaylimits_a^b"#)
        XCTAssertEqual(explicit.width, plain.width, accuracy: 0.001)
        XCTAssertEqual(explicit.ascent, plain.ascent, accuracy: 0.001)
    }

    // MARK: - Round-trip, speech, support

    func testRoundTripPreservesNoLimits() {
        // Previously `\sum\nolimits_a^b` serialized to `{∑}_{a}^{b}` — the
        // modifier vanished, so a round-trip silently re-stacked.
        let latex = MathParser.parse(#"\sum\nolimits_a^b"#).toLaTeX()
        XCTAssertTrue(latex.contains(#"\nolimits"#), "round-trip dropped \\nolimits: \(latex)")
        // And it survives a second pass unchanged in behaviour.
        let reparsed = standardMockEngine(10).layout(MathParser.parse(latex), display: true)
        XCTAssertEqual(reparsed.width, scene(#"\sum\nolimits_a^b"#).width, accuracy: 0.001)
    }

    func testNoLimitsIsFullySupportedAndTransparentToSpeech() {
        let node = MathParser.parse(#"\sum\nolimits_{i=1}^{n} x_i"#)
        XCTAssertTrue(MathParser.isFullySupported(node),
                      "\\nolimits must not degrade the expression")
        let speech = MathSpeech.describe(node)
        XCTAssertTrue(speech.contains("sum"), "the operator is still spoken: \(speech)")
        XCTAssertFalse(speech.contains("nolimits"), "the modifier is layout-only: \(speech)")
    }
}
