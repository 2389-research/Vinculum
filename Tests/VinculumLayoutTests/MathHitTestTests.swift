import XCTest
import Foundation
@testable import VinculumLayout

/// The hit-testing substrate: scene points map back to the deepest node
/// subtree and its LaTeX — the foundation for tap-to-inspect, selection,
/// and editing.
final class MathHitTestTests: XCTestCase {

    private func engine() -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: 10, collectHitRegions: true)
    }

    private func origin(of glyph: String, in scene: MathScene) -> CGPoint? {
        for e in scene.elements {
            if case let .glyphs(text, _, _, o, _) = e, text == glyph { return o }
        }
        return nil
    }

    func testHitOnNumeratorGlyphReturnsIt() throws {
        let scene = engine().layout(MathParser.parse(#"\frac{a}{b} + c"#))
        let a = try XCTUnwrap(origin(of: "𝑎", in: scene))
        let hit = try XCTUnwrap(scene.hitTest(CGPoint(x: a.x + 1, y: a.y + 1)))
        XCTAssertEqual(hit.latex, "a", "deepest region wins: the glyph, not the fraction")
    }

    func testHitOnFractionBarReturnsTheFraction() throws {
        // Between numerator and denominator, only the fraction's own region
        // contains the point.
        let scene = engine().layout(MathParser.parse(#"\frac{a}{b} + c"#))
        let a = try XCTUnwrap(origin(of: "𝑎", in: scene))
        let axisPoint = CGPoint(x: a.x + 1, y: 2.5)   // axisHeight ≈ 0.25·10
        let hit = try XCTUnwrap(scene.hitTest(axisPoint))
        if case .fraction = hit.node {} else {
            XCTFail("expected the fraction, got: \(hit.latex)")
        }
        XCTAssertTrue(hit.latex.contains(#"\frac{a}{b}"#))
    }

    func testMissReturnsNil() {
        let scene = engine().layout(MathParser.parse("x"))
        XCTAssertNil(scene.hitTest(CGPoint(x: -50, y: 0)))
        XCTAssertNil(scene.hitTest(CGPoint(x: scene.width + 50, y: 0)))
    }

    func testRegionsNestSanely() throws {
        let scene = engine().layout(MathParser.parse(#"\frac{a}{b}"#))
        let regions = scene.hitRegions
        let frac = try XCTUnwrap(regions.first { if case .fraction = $0.node { return true }; return false })
        let numerator = try XCTUnwrap(regions.first { $0.latex == "a" })
        XCTAssertTrue(frac.rect.size.height > numerator.rect.size.height,
                      "the fraction's footprint contains its numerator's")
    }

    func testOffByDefault() {
        let scene = MathLayoutEngine(measure: standardMockMeasurer, baseSize: 10)
            .layout(MathParser.parse(#"\frac{a}{b}"#))
        XCTAssertTrue(scene.hitRegions.isEmpty, "plain rendering carries no metadata")
    }
}
