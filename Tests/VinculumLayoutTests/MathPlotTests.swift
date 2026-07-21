import XCTest
import Foundation
@testable import VinculumLayout

/// Function plots (`\begin{axis}…\addplot{…}`). Parser + headless geometry.
final class MathPlotTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    func testAxisParsesCurvesAndDomain() {
        guard case let .plot(curves, xMin, xMax) =
                MathParser.parse(#"\begin{axis}[domain=-2:4] \addplot{x^2}; \addplot{sin(x)}; \end{axis}"#) else {
            return XCTFail("expected a plot")
        }
        XCTAssertEqual(curves.map(\.expression), ["x^2", "sin(x)"])
        XCTAssertEqual(xMin, -2, accuracy: 1e-9)
        XCTAssertEqual(xMax, 4, accuracy: 1e-9)
    }

    func testTikzpictureWrapperIsTransparent() {
        guard case .plot = MathParser.parse(
            #"\begin{tikzpicture}\begin{axis}\addplot{x};\end{axis}\end{tikzpicture}"#) else {
            return XCTFail("tikzpicture should yield the inner plot")
        }
    }

    func testFullySupportedAndRoundTrips() {
        let node = MathParser.parse(#"\begin{axis}[domain=-3:3] \addplot{x^2}; \end{axis}"#)
        XCTAssertTrue(MathParser.isFullySupported(node))
        let round = node.toLaTeX()
        XCTAssertTrue(round.contains(#"\addplot{x^2}"#) && round.contains("domain=-3:3"), round)
    }

    func testLayoutDrawsAxesGridAndCurve() {
        let scene = engine().layout(MathParser.parse(#"\begin{axis}[domain=-3:3] \addplot{x^2}; \end{axis}"#))
        let strokes = scene.elements.filter { if case .stroke = $0 { return true }; return false }.count
        // 2 axes + several gridlines + at least one curve polyline.
        XCTAssertGreaterThan(strokes, 5)
        XCTAssertGreaterThan(scene.width, 0); XCTAssertGreaterThan(scene.height, 0)
        // Tick labels are glyph runs.
        let glyphs = scene.elements.filter { if case .glyphs = $0 { return true }; return false }.count
        XCTAssertGreaterThan(glyphs, 0, "tick labels render")
    }

    func testEmptyOrMalformedPlotDoesNotCrash() {
        _ = engine().layout(MathParser.parse(#"\begin{axis}\addplot{@@bad};\end{axis}"#))  // malformed expr → skipped
        _ = engine().layout(MathParser.parse(#"\begin{axis}\end{axis}"#))                   // no curves
    }
}
