import XCTest
import Foundation
@testable import VinculumLayout

/// `\mathbf` maps to Mathematical-Alphanumeric codepoints — including bold digits
/// (the last remaining hole). Platform-free.
final class MathBoldDigitsTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    func testBoldDigitsMapToTheBoldBlock() {
        XCTAssertEqual(MathLayoutEngine.mathVariant("0", italic: false, bold: true), "𝟎")
        XCTAssertEqual(MathLayoutEngine.mathVariant("2", italic: false, bold: true), "𝟐")
        XCTAssertEqual(MathLayoutEngine.mathVariant("9", italic: false, bold: true), "𝟗")
    }

    func testNonBoldDigitsStayAscii() {
        XCTAssertEqual(MathLayoutEngine.mathVariant("2", italic: false, bold: false), "2")
        XCTAssertEqual(MathLayoutEngine.mathVariant("2", italic: true, bold: false), "2")
    }

    func testBoldLettersAndGreekUnchanged() {
        XCTAssertEqual(MathLayoutEngine.mathVariant("A", italic: false, bold: true), "𝐀")
        XCTAssertEqual(MathLayoutEngine.mathVariant("z", italic: false, bold: true), "𝐳")
        XCTAssertEqual(MathLayoutEngine.mathVariant("\u{03B1}", italic: false, bold: true), "\u{1D6C2}") // 𝛂
    }

    func testMathbfNumberRendersBoldDigitGlyphs() {
        let texts = engine().layout(MathParser.parse(#"\mathbf{2025}"#)).elements.compactMap {
            if case let .glyphs(t, _, _, _, _) = $0 { return t }; return nil
        }.joined()
        XCTAssertTrue(texts.contains("𝟐") && texts.contains("𝟎") && texts.contains("𝟓"),
                      "\\mathbf{2025} must render bold digit codepoints, got \(texts)")
    }
}
