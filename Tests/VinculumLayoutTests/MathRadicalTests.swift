import XCTest
import Foundation
@testable import VinculumLayout

/// the radical drawn with the font's √ glyph (variants →
/// assembly → polyline fallback), the variant shortfall heuristic, and the
/// font's degree-placement constants (TeX Rule 11).
final class MathRadicalTests: XCTestCase {

    private let mock = standardMockMeasurer

    // MARK: - Variant selection heuristic

    func testBestVariantPrefersJustShortOverBigJump() {
        let ladder = MathVariantsData.Construction(variants: [
            .init(glyphID: 1, advance: 1.0),
            .init(glyphID: 2, advance: 1.1),
            .init(glyphID: 3, advance: 3.0),
        ], assembly: nil)
        // 1.13 target: next fit is a 2.7× jump and 1.1 is within 3% → take 1.1.
        XCTAssertEqual(ladder.bestVariant(forTarget: 1.13)?.glyphID, 2)
        // 1.15 target: 1.1 misses by >3% → take the 3.0 despite the jump.
        XCTAssertEqual(ladder.bestVariant(forTarget: 1.15)?.glyphID, 3)
        // Taller than everything → nil (caller assembles or scales).
        XCTAssertNil(ladder.bestVariant(forTarget: 4.0))
    }

    // MARK: - Font-glyph radical path (mock delimiter provider)

    private func fontRadicalEngine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(services: .init(measure: mock, delimiters: { glyph, minHeight, _ in
            guard glyph == "√" else { return nil }
            return DelimiterShape(glyphID: 99, metrics: GlyphMetrics(
                width: 5, ascent: minHeight * 0.8, descent: minHeight * 0.2,
                inkAscent: minHeight * 0.8, inkDescent: -minHeight * 0.2))
        }), baseSize: size)
    }

    func testRadicalUsesFontGlyphWhenProviderServes() {
        let scene = fontRadicalEngine().layout(MathParser.parse("\\sqrt{x}"))
        let glyphIDs = scene.elements.compactMap { e -> UInt16? in
            if case let .glyph(id, _, _, _) = e { return id }
            return nil
        }
        XCTAssertEqual(glyphIDs, [99], "the surd is the font glyph, not a polyline")
        let strokes = scene.elements.filter { if case .stroke = $0 { return true }; return false }
        XCTAssertTrue(strokes.isEmpty, "no hand-stroked surd")
        let rules = scene.elements.filter { if case .rule = $0 { return true }; return false }
        XCTAssertEqual(rules.count, 1, "the vinculum is a filled rule")
    }

    func testRadicalFallsBackToPolylineWithoutProvider() {
        let scene = MathLayoutEngine(measure: mock, baseSize: 10)
            .layout(MathParser.parse("\\sqrt{x}"))
        let strokes = scene.elements.filter { if case .stroke = $0 { return true }; return false }
        XCTAssertFalse(strokes.isEmpty, "headless keeps the polyline surd")
    }

    func testDegreeUsesFontKernsAndRaise() {
        // \sqrt[3]{x} at 10pt: degree x = RadicalKernBeforeDegree (2.78);
        // sign x = kernBefore + degreeWidth + kernAfter (−5.56), floored at 0.
        let scene = fontRadicalEngine().layout(MathParser.parse("\\sqrt[3]{x}"))
        var signX: CGFloat?, degreeX: CGFloat?
        for e in scene.elements {
            if case let .glyph(99, _, origin, _) = e { signX = origin.x }
            if case let .glyphs("3", _, _, origin, _) = e { degreeX = origin.x }
        }
        let degreeWidth = 10 * MathLayout.Radical.degreeScale
        XCTAssertEqual(degreeX ?? -1, 0.278 * 10, accuracy: 0.001)
        XCTAssertEqual(signX ?? -1, max(0, 0.278 * 10 + degreeWidth - 0.556 * 10), accuracy: 0.001)
    }
}
