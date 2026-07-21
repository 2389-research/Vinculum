import XCTest
import Foundation
@testable import VinculumLayout

/// Spacing and escaped-character commands inside `\text`/`\mathrm`/`\operatorname`
/// resolve instead of printing literally (`\operatorname{arg\,max}` → "arg max").
final class MathTextSpacingTests: XCTestCase {

    private func glyphText(_ src: String) -> String {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: 10)
            .layout(MathParser.parse(src)).elements.compactMap {
                if case let .glyphs(t, _, _, _, _) = $0 { return t }; return nil
            }.joined()
    }

    func testOperatornameThinSpaceIsNotLiteral() {
        let t = glyphText(#"\operatorname{arg\,max}"#)
        XCTAssertFalse(t.contains(#"\,"#), "the \\, must not print literally: \(t)")
        XCTAssertTrue(t.contains("arg") && t.contains("max"), "both words present: \(t)")
        XCTAssertTrue(t.contains("\u{2009}"), "a thin space separates them: \(t)")
    }

    func testTextEscapedAmpersand() {
        let t = glyphText(#"\text{a\&b}"#)
        XCTAssertEqual(t, "a&b")
    }

    func testPlainTextUnchanged() {
        // No commands, no math: still a single verbatim run (fast path).
        XCTAssertEqual(glyphText(#"\text{if }"#), "if ")
    }

    func testQuadInsideText() {
        let t = glyphText(#"\text{a\quad b}"#)
        XCTAssertTrue(t.contains("\u{2003}"), "\\quad becomes an em space: \(t)")
        XCTAssertFalse(t.contains("quad"), "the command name must not leak: \(t)")
    }

    func testEmbeddedMathStillWorks() {
        // $…$ inside \text still parses as math (the italic x variant appears).
        let t = glyphText(#"\text{value $x$ here}"#)
        XCTAssertTrue(t.contains("value ") && t.contains("𝑥"), "embedded math survives: \(t)")
    }
}
