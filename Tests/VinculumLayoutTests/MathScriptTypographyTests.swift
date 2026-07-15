import XCTest
import Foundation
@testable import VinculumLayout

/// geometry tests: per-glyph script typography (TeX Rules 17/18 +
/// OpenType cut-in kerning), headless via the mock measurer and a mock
/// `MathGlyphTypographyProvider`.
final class MathScriptTypographyTests: XCTestCase {

    private let mock = standardMockMeasurer

    /// Provider giving the italic 𝑓 (U+1D453) a 0.2 em italic correction and
    /// everything else zero. Values are returned in points at `size`.
    private func engineWithItalicF(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(services: .init(measure: mock, typography: { glyph, size in
            glyph == "𝑓" ? GlyphTypography(italicsCorrection: 0.2 * size) : nil
        }), baseSize: size)
    }

    private func glyphOrigins(_ scene: MathScene) -> [(text: String, x: CGFloat, size: CGFloat)] {
        scene.elements.compactMap {
            if case let .glyphs(text, size, _, origin, _) = $0 { return (text, origin.x, size) }
            return nil
        }
    }

    // MARK: - Rule 17/18f: italic correction splits super from sub

    func testSuperscriptShiftsByItalicCorrectionSubscriptDoesNot() {
        // f^2_3 at base 10: δ = 2. The superscript starts at base.width + δ;
        // the subscript tucks in at base.width, un-shifted.
        let scene = engineWithItalicF().layout(MathParser.parse("f^2_3"))
        let runs = glyphOrigins(scene)
        let sup = runs.first { $0.text == "2" }
        let sub = runs.first { $0.text == "3" }
        XCTAssertEqual(sup?.x ?? -1, 10 + 2, accuracy: 0.001, "superscript at advance + δ")
        XCTAssertEqual(sub?.x ?? -1, 10, accuracy: 0.001, "subscript at the advance, under the overhang")
    }

    func testScriptSpaceComesAfterTheScripts() {
        // x^2 with no italic correction: width = base + script + spaceAfterScript
        // — the \scriptspace analog trails the script (TeX 18b), it does not
        // precede it.
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        let scene = engine.layout(MathParser.parse("x^2"))
        XCTAssertEqual(scene.width, 10 + 7 + 0.56, accuracy: 0.001)
        let sup = glyphOrigins(scene).first { $0.text == "2" }
        XCTAssertEqual(sup?.x ?? -1, 10, accuracy: 0.001, "script starts at the base advance")
    }

    // MARK: - Rule 18a: composite nuclei use the baseline-drop constants

    func testCompositeNucleusUsesBaselineDrops() {
        // (fraction)^2: the superscript baseline sits at
        // base.ascent − scriptSize·SuperscriptBaselineDropMax, if that beats
        // the style's nominal shift.
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        let frac = MathParser.parse("\\frac{a}{b}")
        let scene = engine.layout(.scripts(base: frac, subscript: nil, superscript: .symbol("2", .ordinary, style: .roman)))
        // Fraction (text style): shiftUp = 3.94 bumped for clearance; its
        // ascent A. Expected raise = A − 7·0.250. Recover A from a bare
        // fraction layout, then find the script's y.
        let bare = engine.layout(frac)
        let supRun = scene.elements.compactMap { e -> CGPoint? in
            if case let .glyphs("2", _, _, origin, _) = e { return origin }
            return nil
        }.first
        XCTAssertNotNil(supRun)
        XCTAssertEqual(supRun!.y, bare.ascent - 7 * 0.250, accuracy: 0.01,
                       "u = h − q·scriptsize (TeX 18a) governs tall composite bases")
    }

    // MARK: - Rule 18d: the font's SubSuperscriptGapMin separates colliding scripts

    func testSubSuperGapOpensToFontMinimum() throws {
        // Deep sup + tall sub forced together: the vertical gap between the
        // superscript's bottom and subscript's top must be ≥ 0.160 em.
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        let scene = engine.layout(MathParser.parse("x^{y}_{z}"))
        var supBottom: CGFloat?, subTop: CGFloat?
        for e in scene.elements {
            guard case let .glyphs(text, size, _, origin, _) = e else { continue }
            if text == "𝑦" { supBottom = origin.y - size * 0.25 }
            if text == "𝑧" { subTop = origin.y + size * 0.75 }
        }
        let gap = try XCTUnwrap(supBottom) - XCTUnwrap(subTop)
        XCTAssertGreaterThanOrEqual(gap + 0.001, 0.160 * 10, "18d minimum script gap")
    }

    // MARK: - Cut-in kerning (MathKernInfo staircases)

    func testTopRightCutInKernTucksSuperscript() {
        // A base whose top-right corner cuts in by 0.15 em at every height:
        // the superscript moves LEFT by the kern.
        let stair = MathGlyphInfo.KernStaircase(correctionHeights: [], kernValues: [-0.15])
        let engine = MathLayoutEngine(services: .init(measure: mock, typography: { glyph, size in
            glyph == "𝑇" ? GlyphTypography(kernTopRight: stair.scaled(by: size)) : nil
        }), baseSize: 10)
        let scene = engine.layout(MathParser.parse("T^2"))
        let sup = glyphOrigins(scene).first { $0.text == "2" }
        XCTAssertEqual(sup?.x ?? -1, 10 - 1.5, accuracy: 0.001, "superscript tucks into the cut corner")
    }

    // MARK: - Large operators: δ tucks the subscript, splits stacked limits

    func testIntegralSubscriptTucksUnderItalicOverhang() {
        // ∫ with δ = 0.3 em keeps side scripts (nolimits): the subscript
        // shifts left by δ; the superscript does not.
        let engine = MathLayoutEngine(services: .init(measure: mock, typography: { glyph, size in
            glyph == "∫" ? GlyphTypography(italicsCorrection: 0.3 * size) : nil
        }), baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\int_a^b"), display: true)
        let runs = glyphOrigins(scene)
        let sub = runs.first { $0.text == "𝑎" }
        let sup = runs.first { $0.text == "𝑏" }
        XCTAssertNotNil(sub); XCTAssertNotNil(sup)
        XCTAssertEqual((sup?.x ?? 0) - (sub?.x ?? 0), 3, accuracy: 0.001,
                       "subscript sits δ left of the superscript")
    }

    func testStackedLimitsShiftByHalfDelta() {
        // ∑ with δ = 0.2 em stacking its limits: upper limit center shifts
        // +δ/2, lower −δ/2 relative to each other (TeX Rule 13a).
        let engine = MathLayoutEngine(services: .init(measure: mock, typography: { glyph, size in
            glyph == "∑" ? GlyphTypography(italicsCorrection: 0.2 * size) : nil
        }), baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\sum_a^b"), display: true)
        let runs = glyphOrigins(scene)
        let lower = runs.first { $0.text == "𝑎" }
        let upper = runs.first { $0.text == "𝑏" }
        XCTAssertNotNil(lower); XCTAssertNotNil(upper)
        // Same-width limits: centers differ by exactly δ (upper +δ/2, lower −δ/2).
        XCTAssertEqual((upper?.x ?? 0) - (lower?.x ?? 0), 2, accuracy: 0.001)
    }
}
