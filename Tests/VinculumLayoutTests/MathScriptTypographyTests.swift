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

    // MARK: - Cramped inheritance (TeX sup_style / num_style)

    /// Low-ink glyphs so Rule 18a's *nominal* shift governs the raise.
    ///
    /// This matters: with the standard mock's 0.7-em ink, the ink floor
    /// `max(supRaise, inkAscent − 0.25·scriptSize)` ≈ 0.525·size dominates BOTH
    /// shift constants (0.363 / 0.289), so cramped and uncramped land on the
    /// identical clamped value and the assertion below could never fail.
    private static let lowInkMeasurer: MathTextMeasurer = { text, size, _ in
        GlyphMetrics(width: CGFloat(text.count) * size, ascent: size * 0.75, descent: size * 0.25,
                     inkAscent: size * 0.1, inkDescent: -size * 0.05)
    }

    /// How far the inner exponent rides above its own base — the `z` above the
    /// `y` in `x^{y^z}`. Absolute positions differ between expressions, so this
    /// relative rise is what isolates the superscript shift under test.
    private func innerExponentRise(_ latex: String) -> CGFloat? {
        let engine = MathLayoutEngine(measure: Self.lowInkMeasurer, baseSize: 10)
        let scene = engine.layout(MathParser.parse(latex), display: true)
        var yOrigin: CGFloat?, zOrigin: CGFloat?
        for e in scene.elements {
            guard case let .glyphs(text, _, _, origin, _) = e else { continue }
            if text == "\u{1D466}" { yOrigin = origin.y }   // math italic y
            if text == "\u{1D467}" { zOrigin = origin.y }   // math italic z
        }
        guard let yOrigin, let zOrigin else { return nil }
        return zOrigin - yOrigin
    }

    func testSuperscriptInheritsEnclosingCrampedBit() throws {
        // TeX's sup_style PRESERVES the enclosing cramped bit (only sub_style and
        // denom_style force it). A radicand is cramped, so the exponent nested
        // inside \sqrt{x^{y^z}} must take superscriptShiftUpCramped and ride
        // LOWER than the same exponent at top level (#10).
        let uncramped = try XCTUnwrap(innerExponentRise(#"x^{y^z}"#))
        let cramped = try XCTUnwrap(innerExponentRise(#"\sqrt{x^{y^z}}"#))
        XCTAssertLessThan(cramped, uncramped,
                          "an exponent nested inside a cramped radicand must use the cramped shift")
    }

    func testNumeratorInheritsEnclosingCrampedBit() throws {
        // num_style preserves the bit too, so a scripted numerator inside a
        // cramped context is itself cramped (#10).
        let uncramped = try XCTUnwrap(innerExponentRise(#"\frac{x^{y^z}}{d}"#))
        let cramped = try XCTUnwrap(innerExponentRise(#"\sqrt{\frac{x^{y^z}}{d}}"#))
        XCTAssertLessThan(cramped, uncramped,
                          "a numerator inside a cramped context must itself be laid out cramped")
    }
}
