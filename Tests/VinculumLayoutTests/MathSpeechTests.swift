import XCTest
@testable import VinculumLayout

/// spoken-math descriptions — the VoiceOver text no native math
/// library generates. Table-driven: LaTeX → expected utterance.
final class MathSpeechTests: XCTestCase {

    private func speech(_ latex: String) -> String {
        MathSpeech.describe(MathParser.parse(latex))
    }

    func testCoreUtterances() {
        XCTAssertEqual(speech(#"x = y + z"#), "x equals y plus z")
        XCTAssertEqual(speech(#"x^2"#), "x squared")
        XCTAssertEqual(speech(#"x^3 + a_i"#), "x cubed plus a sub i")
        XCTAssertEqual(speech(#"x^{n+1}"#), "x to the power n plus 1")
        XCTAssertEqual(speech(#"\frac{1}{2}"#), "1 half")
        XCTAssertEqual(speech(#"\frac{2}{3}"#), "2 thirds")
        XCTAssertEqual(speech(#"\frac{x}{y}"#), "the fraction x, over y")
        XCTAssertEqual(speech(#"\sqrt{x}"#), "the square root of x")
        XCTAssertEqual(speech(#"\sqrt[3]{x}"#), "the cube root of x")
    }

    func testQuadraticFormula() {
        XCTAssertEqual(
            speech(#"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#),
            "x equals the fraction minus b plus or minus the square root of "
            + "b squared minus 4 a c, over 2 a")
    }

    func testStructures() {
        XCTAssertEqual(speech(#"\left( x + y \right)"#), "open paren x plus y close paren")
        XCTAssertEqual(speech(#"\binom{n}{k}"#), "n choose k")
        XCTAssertEqual(speech(#"\vec{v} + \hat{x} + \bar{y}"#), "vector v plus x hat plus y bar")
        XCTAssertEqual(speech(#"\sin\theta"#), "sine theta")
        XCTAssertEqual(speech(#"x \in \mathbb{R}"#), "x is in the real numbers")
        XCTAssertEqual(
            speech(#"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
            "a 2 by 2 matrix: row 1: a, b; row 2: c, d")
    }

    func testOperatorsAndLimits() {
        XCTAssertEqual(speech(#"\sum_{i=1}^{n} i"#),
                       "the sum sub i equals 1 to the power n i")
        XCTAssertEqual(speech(#"\lim_{x \to 0} f"#),
                       "the limit sub x goes to 0 f")
        XCTAssertEqual(speech(#"\int_0^1 x\,dx"#),
                       "the integral sub 0 to the power 1 x d x")
    }

    func testInvisiblesAreSilent() {
        XCTAssertEqual(speech(#"x\,\quad y"#), "x y")
        XCTAssertEqual(speech(#"\phantom{x} y"#), "y")
    }
}
