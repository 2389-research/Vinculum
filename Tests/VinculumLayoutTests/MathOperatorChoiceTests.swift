import XCTest
import Foundation
@testable import VinculumLayout

/// `\DeclareMathOperator` (via the macro system) and `\mathchoice` (style-picked
/// material). Headless / platform-free.
final class MathOperatorChoiceTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    // MARK: \DeclareMathOperator — a document macro expanding to \operatorname

    func testDeclareMathOperatorRegistersAndExpands() {
        let table = MathMacros.collectDefinitions(
            from: #"$$\DeclareMathOperator{\argmax}{arg\,max}$$"#)
        XCTAssertEqual(MathMacros.expand(#"\argmax_x f(x)"#, with: table),
                       #"\operatorname{arg\,max}_x f(x)"#)
    }

    func testDeclareMathOperatorStarredTakesLimits() {
        let table = MathMacros.collectDefinitions(
            from: #"$$\DeclareMathOperator*{\Argmax}{argmax}$$"#)
        XCTAssertEqual(MathMacros.expand(#"\Argmax_{x}"#, with: table),
                       #"\operatorname*{argmax}_{x}"#)
    }

    func testDeclareMathOperatorDefinitionProducesNoInk() {
        // The declaration itself is stripped (it defines, it doesn't print).
        let table = MathMacros.collectDefinitions(from: #"$$\DeclareMathOperator{\di}{d}$$"#)
        XCTAssertEqual(MathMacros.expand(#"\DeclareMathOperator{\di}{d}"#, with: table)
                        .vTrimmingWhitespaceAndNewlines(), "")
    }

    // MARK: \mathchoice — pick by style

    func testMathChoiceParsesToFourBranches() {
        guard case let .mathChoice(d, t, s, ss) = MathParser.parse(#"\mathchoice{D}{T}{S}{Z}"#) else {
            return XCTFail("expected mathChoice")
        }
        XCTAssertEqual(d.toLaTeX(), "D")
        XCTAssertEqual(t.toLaTeX(), "T")
        XCTAssertEqual(s.toLaTeX(), "S")
        XCTAssertEqual(ss.toLaTeX(), "Z")
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(#"\mathchoice{D}{T}{S}{Z}"#)))
    }

    func testMathChoicePicksDisplayVsTextBranch() {
        // Display style takes the wide branch; text style the narrow one.
        let node = MathParser.parse(#"\mathchoice{AAAA}{A}{A}{A}"#)
        let displayW = engine().layout(node, display: true).width
        let textW = engine().layout(node, display: false).width
        XCTAssertGreaterThan(displayW, textW,
                             "display picks {AAAA} (wide); text picks {A} (narrow)")
    }

    func testMathChoiceRoundTrips() {
        let src = #"\mathchoice{D}{T}{S}{Z}"#
        XCTAssertEqual(MathParser.parse(src).toLaTeX(), src)
    }
}
