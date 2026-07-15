import XCTest
import Foundation
@testable import VinculumLayout

/// display-style large operators use the font's bigger variant
/// (DisplayOperatorMinHeight) centered on the axis, and `\left…\right`
/// fences size by TeX's `\delimiterfactor`/`\delimitershortfall` formula.
final class MathOperatorSizingTests: XCTestCase {

    private let mock = standardMockMeasurer

    /// Serves a big-∑/∫ variant (gid 42) when asked for at least the
    /// DisplayOperatorMinHeight (1.3 em in LM Math).
    private func operatorProvider() -> MathDelimiterProvider {
        { glyph, minHeight, size in
            guard glyph == "∑" || glyph == "∫", minHeight >= size * 1.3 else { return nil }
            return DelimiterShape(glyphID: 42, metrics: GlyphMetrics(
                width: size * 1.4, ascent: size * 1.0, descent: size * 0.4,
                inkAscent: size * 1.0, inkDescent: -size * 0.4))
        }
    }

    func testDisplaySumUsesFontVariantCenteredOnAxis() {
        let engine = MathLayoutEngine(services: .init(measure: mock, delimiters: operatorProvider()), baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\sum_a^b"), display: true)
        let op = scene.elements.compactMap { e -> CGPoint? in
            if case let .glyph(42, _, origin, _) = e { return origin }
            return nil
        }.first
        XCTAssertNotNil(op, "display ∑ swaps in the font's display-size variant")
        // Axis-centered: baseline offset = axisHeight − (ascent−descent)/2
        // = 2.5 − (10−4)/2 = −0.5.
        XCTAssertEqual(op!.y, 2.5 - (10 - 4) / 2, accuracy: 0.001)
    }

    func testDisplayIntegralUsesVariantAndKeepsSideScripts() {
        let engine = MathLayoutEngine(services: .init(measure: mock, delimiters: operatorProvider()), baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\int_a^b"), display: true)
        let hasVariant = scene.elements.contains {
            if case .glyph(42, _, _, _) = $0 { return true }; return false
        }
        XCTAssertTrue(hasVariant, "display ∫ also enlarges to the variant")
        let scripts = scene.elements.compactMap { e -> String? in
            if case let .glyphs(text, _, _, _, _) = e { return text }
            return nil
        }
        XCTAssertTrue(scripts.contains("𝑎") && scripts.contains("𝑏"), "side scripts intact")
    }

    func testTextStyleOperatorStaysBaseSize() {
        let engine = MathLayoutEngine(services: .init(measure: mock, delimiters: operatorProvider()), baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\sum_a^b"))   // text style
        let hasVariant = scene.elements.contains {
            if case .glyph = $0 { return true }; return false
        }
        XCTAssertFalse(hasVariant, "no display variant outside display style")
    }

    // MARK: - Rule 19 fence target

    func testFenceTargetFollowsDelimiterFactorFormula() {
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        // ψ = max(20 − 2.5, 10 + 2.5) = 17.5;
        // target = max(17.5·1.802, 2·17.5 − 5) = max(31.535, 30) = 31.535.
        XCTAssertEqual(engine.fenceTarget(ascent: 20, descent: 10, size: 10),
                       31.535, accuracy: 0.001)
        // Small body: 2ψ − 5 wins… ψ=5 → max(9.01, 5) = 9.01.
        XCTAssertEqual(engine.fenceTarget(ascent: 7.5, descent: 2.5, size: 10),
                       9.01, accuracy: 0.001)
    }
}
