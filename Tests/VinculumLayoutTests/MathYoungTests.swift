import XCTest
import Foundation
@testable import VinculumLayout

/// Young diagrams / tableaux (`\ydiagram`, `\ytableaushort`). Platform-free geometry.
final class MathYoungTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    func testYdiagramPartitionToEmptyRows() {
        guard case let .youngTableau(rows) = MathParser.parse(#"\ydiagram{4,2,1}"#) else {
            return XCTFail("expected youngTableau")
        }
        XCTAssertEqual(rows.map(\.count), [4, 2, 1])
        XCTAssertTrue(rows.flatMap { $0 }.allSatisfy { $0 == nil }, "ydiagram cells are empty")
    }

    func testYtableaushortFilled() {
        guard case let .youngTableau(rows) = MathParser.parse(#"\ytableaushort{134,25,6}"#) else {
            return XCTFail("expected youngTableau")
        }
        XCTAssertEqual(rows.map(\.count), [3, 2, 1])
        XCTAssertEqual(rows[0][0]?.toLaTeX(), "1")
        XCTAssertEqual(rows[1][1]?.toLaTeX(), "5")
    }

    func testFullySupportedAndRoundTrips() {
        for src in [#"\ydiagram{3,2,1}"#, #"\ytableaushort{ab,c}"#, #"\ydiagram{2,2}"#] {
            let node = MathParser.parse(src)
            XCTAssertTrue(MathParser.isFullySupported(node))
            XCTAssertEqual(node.toLaTeX(), src, "round-trips verbatim: \(src)")
        }
    }

    func testLayoutDrawsOneBorderPerCell() {
        let scene = engine().layout(MathParser.parse(#"\ydiagram{3,1}"#))
        let strokes = scene.elements.filter { if case .stroke = $0 { return true }; return false }.count
        XCTAssertEqual(strokes, 4, "3 + 1 = 4 bordered cells")
        XCTAssertGreaterThan(scene.width, 0); XCTAssertGreaterThan(scene.height, 0)
    }

    func testFilledCellsCarryContent() {
        let scene = engine().layout(MathParser.parse(#"\ytableaushort{12,3}"#))
        let glyphs = scene.elements.filter { if case .glyphs = $0 { return true }; return false }.count
        XCTAssertGreaterThanOrEqual(glyphs, 3, "three filled cells → three glyph runs")
    }

    func testWiderRowSetsTheWidth() {
        // A 4-wide first row is wider than a 4-tall column.
        let wide = engine().layout(MathParser.parse(#"\ydiagram{4}"#)).width
        let tall = engine().layout(MathParser.parse(#"\ydiagram{1,1,1,1}"#)).width
        XCTAssertGreaterThan(wide, tall)
    }
}
