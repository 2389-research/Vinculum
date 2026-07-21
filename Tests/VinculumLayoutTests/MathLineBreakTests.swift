import XCTest
import Foundation
@testable import VinculumLayout

/// Automatic line breaking (width-aware layout). Headless / platform-free.
final class MathLineBreakTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    /// Distinct baseline y-values among glyph runs = number of lines.
    private func lineCount(_ scene: MathScene) -> Int {
        var ys = Set<Int>()
        for el in scene.elements {
            if case let .glyphs(_, _, _, origin, _) = el { ys.insert(Int((origin.y * 100).rounded())) }
        }
        return ys.count
    }

    func testNoMaxWidthIsSingleLineAndByteIdentical() {
        let node = MathParser.parse("a + b + c + d")
        let e = engine()
        let plain = e.layout(node)
        let nilMax = e.layout(node, maxWidth: nil)
        let wideMax = e.layout(node, maxWidth: 100000)
        XCTAssertEqual(plain.width, nilMax.width, accuracy: 0.0001)
        XCTAssertEqual(plain.height, nilMax.height, accuracy: 0.0001)
        XCTAssertEqual(plain.height, wideMax.height, accuracy: 0.0001, "content narrower than maxWidth doesn't break")
        XCTAssertEqual(lineCount(plain), 1)
    }

    func testLongRowBreaksIntoMultipleLines() {
        let node = MathParser.parse("a + b + c + d + e + f + g + h + i + j")
        let e = engine()
        let single = e.layout(node)
        let broken = e.layout(node, maxWidth: single.width / 3)
        XCTAssertLessThanOrEqual(broken.width, single.width, "wrapped lines are no wider than the whole")
        XCTAssertGreaterThan(broken.height, single.height * 1.8, "several stacked lines are much taller")
        XCTAssertGreaterThan(lineCount(broken), 2, "broke into 3+ lines")
    }

    func testEachWrappedLineFitsTheWidth() {
        let node = MathParser.parse("aa + bb + cc + dd + ee + ff + gg + hh")
        let e = engine()
        let maxW = e.layout(node).width / 2.5
        let broken = e.layout(node, maxWidth: maxW)
        // No wrapped line's width exceeds the budget by more than one atom's slack.
        XCTAssertLessThanOrEqual(broken.width, maxW * 1.15, "lines respect the width budget")
        XCTAssertGreaterThan(lineCount(broken), 1)
    }

    func testBreaksAfterOperatorsNotMidTerm() {
        // A relation is a valid break point; the break should land at "=" / "+",
        // so each line ends on an operator and starts on a term.
        let node = MathParser.parse("x = a + b + c + d + e + f")
        let e = engine()
        let broken = e.layout(node, maxWidth: e.layout(node).width / 2)
        XCTAssertGreaterThan(lineCount(broken), 1)
    }

    func testUnbreakableTopLevelNodeIsNotBroken() {
        // A single fraction is not a top-level row, so line breaking never touches it —
        // its geometry is identical with or without a (too-small) maxWidth.
        let node = MathParser.parse(#"\frac{aaaaaaaaaa}{bbbbbbbbbb}"#)
        let e = engine()
        let plain = e.layout(node)
        let squeezed = e.layout(node, maxWidth: 5)
        XCTAssertEqual(plain.width, squeezed.width, accuracy: 0.0001, "an unbreakable node is left intact")
        XCTAssertEqual(plain.height, squeezed.height, accuracy: 0.0001)
    }
}
