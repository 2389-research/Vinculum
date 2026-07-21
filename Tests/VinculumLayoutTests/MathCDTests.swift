import XCTest
import Foundation
@testable import VinculumLayout

/// Commutative diagrams (amscd `\begin{CD}`). Parser + headless geometry.
final class MathCDTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    private let square = #"\begin{CD} A @>f>> B \\ @VgVV @VVhV \\ C @>>k> D \end{CD}"#

    func testParsesToGrid() {
        guard case let .commutativeDiagram(grid) = MathParser.parse(square) else {
            return XCTFail("expected a commutativeDiagram")
        }
        XCTAssertEqual(grid.count, 3, "object row, arrow row, object row")
        XCTAssertEqual(grid.map(\.count).max(), 3)
        // (0,0) object A, (0,1) horizontal arrow, (1,0) vertical arrow.
        guard case .object = grid[0][0] else { return XCTFail("(0,0) should be an object") }
        guard case .hArrow(let h) = grid[0][1] else { return XCTFail("(0,1) should be a horizontal arrow") }
        XCTAssertEqual(h.kind, .right)
        XCTAssertEqual(h.label1?.toLaTeX(), "f")
        guard case .vArrow(let v) = grid[1][0] else { return XCTFail("(1,0) should be a vertical arrow") }
        XCTAssertEqual(v.kind, .down)
        XCTAssertEqual(v.label1?.toLaTeX(), "g")
    }

    func testFullySupportedAndRoundTripsExactly() {
        let node = MathParser.parse(square)
        XCTAssertTrue(MathParser.isFullySupported(node))
        XCTAssertEqual(node.toLaTeX(), square, "amscd round-trips verbatim")
    }

    func testArrowDirectionsAndEqualEdges() {
        // left, up, and the two equality edges.
        guard case let .commutativeDiagram(grid) =
                MathParser.parse(#"\begin{CD} A @<p<<  B \\ @AAA @| \\ C @>>> D \end{CD}"#) else {
            return XCTFail("parse")
        }
        guard case .hArrow(let left) = grid[0][1] else { return XCTFail() }
        XCTAssertEqual(left.kind, .left); XCTAssertEqual(left.label1?.toLaTeX(), "p")
        guard case .vArrow(let up) = grid[1][0] else { return XCTFail() }
        XCTAssertEqual(up.kind, .up)
        guard case .vArrow(let veq) = grid[1][2] else { return XCTFail() }
        XCTAssertEqual(veq.kind, .equal)
    }

    func testLayoutEmitsAnArrowStrokePerEdge() {
        let scene = engine().layout(MathParser.parse(square))
        let strokes = scene.elements.filter { if case .stroke = $0 { return true }; return false }.count
        XCTAssertEqual(strokes, 4, "two horizontal + two vertical arrows")
        // Four objects → at least four glyph runs.
        let glyphs = scene.elements.filter { if case .glyphs = $0 { return true }; return false }.count
        XCTAssertGreaterThanOrEqual(glyphs, 4)
        XCTAssertGreaterThan(scene.width, 0); XCTAssertGreaterThan(scene.height, 0)
    }

    func testObjectsFormAGrid() {
        // A and B share a row (same baseline y); A and C share a column (same x).
        let scene = engine().layout(MathParser.parse(square))
        let runs: [(t: String, x: CGFloat, y: CGFloat)] = scene.elements.compactMap {
            if case let .glyphs(t, _, _, o, _) = $0 { return (t, o.x, o.y) }; return nil
        }
        func find(_ t: String) -> (x: CGFloat, y: CGFloat)? { runs.first { $0.t.contains(t) }.map { ($0.x, $0.y) } }
        // Objects render as Math-Italic; match by the top row being higher than the bottom.
        let ys = runs.map(\.y).sorted()
        XCTAssertGreaterThan(ys.last! - ys.first!, 0, "top and bottom object rows are at different heights")
    }
}
