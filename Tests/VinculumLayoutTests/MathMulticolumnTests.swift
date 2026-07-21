import XCTest
import Foundation
@testable import VinculumLayout

/// `\multicolumn` — column-spanning table cells. Headless geometry on the mock,
/// so it's platform-free and runs on Linux.
final class MathMulticolumnTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    /// Glyph runs as (text, centerX): the mock makes width = count·size.
    private func runs(_ scene: MathScene, size: CGFloat = 10) -> [(text: String, cx: CGFloat)] {
        scene.elements.compactMap {
            if case let .glyphs(text, s, _, origin, _) = $0 {
                return (text, origin.x + CGFloat(text.count) * s / 2)
            }
            return nil
        }
    }

    func testParsesToSpannedCell() {
        let node = MathParser.parse(#"\begin{array}{cc}\multicolumn{2}{c}{WW}\\a&b\end{array}"#)
        guard case let .matrix(rows, _, _, _) = node, let first = rows.first?.first else {
            return XCTFail("expected a matrix")
        }
        guard case let .spanned(cols, align, _) = first else {
            return XCTFail("expected the first cell to be .spanned, got \(first)")
        }
        XCTAssertEqual(cols, 2)
        XCTAssertEqual(align, .center)
    }

    func testFullySupportedAndRoundTrips() {
        let src = #"\begin{array}{cc}\multicolumn{2}{c}{WW}\\a&b\end{array}"#
        let node = MathParser.parse(src)
        XCTAssertTrue(MathParser.isFullySupported(node))
        XCTAssertTrue(node.toLaTeX().contains(#"\multicolumn{2}{c}"#),
                      "round-trip must carry the span: \(node.toLaTeX())")
    }

    func testSpannedCellCentersAcrossItsColumns() {
        // Row 1 spans both columns; row 2 fills them. The spanned title should sit
        // between the two single-column cells below it. Split by row (y) so the test
        // doesn't depend on how letters map to Math-Italic glyph runs.
        let scene = engine().layout(
            MathParser.parse(#"\begin{array}{cc}\multicolumn{2}{c}{WW}\\a&b\end{array}"#))
        let all: [(cx: CGFloat, y: CGFloat)] = scene.elements.compactMap {
            if case let .glyphs(text, s, _, origin, _) = $0 {
                return (origin.x + CGFloat(text.count) * s / 2, origin.y)
            }
            return nil
        }
        let midY = ((all.map(\.y).max() ?? 0) + (all.map(\.y).min() ?? 0)) / 2
        let top = all.filter { $0.y > midY }                              // spanned title
        let bottom = all.filter { $0.y <= midY }.sorted { $0.cx < $1.cx } // a, b left→right
        XCTAssertFalse(top.isEmpty, "no spanned-title glyphs")
        XCTAssertEqual(bottom.count, 2, "two bottom-row cells")
        let titleCx = top.map(\.cx).reduce(0, +) / CGFloat(top.count)
        XCTAssertLessThan(bottom[0].cx, titleCx, "title sits right of the left cell")
        XCTAssertLessThan(titleCx, bottom[1].cx, "…and left of the right cell — spanning both")
    }

    func testWideSpanGrowsTheGrid() {
        // A very wide \multicolumn must widen the grid beyond the natural columns.
        let narrow = engine().layout(
            MathParser.parse(#"\begin{array}{cc}x&y\\a&b\end{array}"#)).width
        let wide = engine().layout(
            MathParser.parse(#"\begin{array}{cc}\multicolumn{2}{c}{WWWWWWWW}\\a&b\end{array}"#)).width
        XCTAssertGreaterThan(wide, narrow, "an overflowing span grows the grid")
    }
}
