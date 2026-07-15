import XCTest
import Foundation
@testable import VinculumLayout

/// geometry tests: accents positioned by the font's attachment
/// points (TeX Rule 12, OpenType topAccentAttachment), the AccentBaseHeight
/// floor, and single-character accentee script promotion.
final class MathAccentTests: XCTestCase {

    private let mock = standardMockMeasurer

    private func accentRun(_ scene: MathScene) -> (x: CGFloat, y: CGFloat, size: CGFloat)? {
        for e in scene.elements {
            if case let .glyphs("^", size, _, origin, _) = e { return (origin.x, origin.y, size) }
        }
        return nil
    }

    func testAccentSkewsToAttachmentPoint() {
        // 𝑓's attachment point is at 0.7 of its advance (7pt at base 10);
        // the accent (no data → centered on its own width, 9·0.5 = 4.5)
        // lands at 7 − 4.5 = 2.5, not geometric center 0.5.
        let engine = MathLayoutEngine(services: .init(measure: mock, typography: { glyph, size in
            glyph == "𝑓" ? GlyphTypography(topAccentAttachment: 0.7 * size) : nil
        }), baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\hat{f}"))
        let run = accentRun(scene)
        XCTAssertEqual(run?.x ?? -1, 0.7 * 10 - (run?.size ?? 0) / 2, accuracy: 0.001,
                       "accent x = baseAttach − accentAttach")
    }

    func testAccentCentersWithoutAttachmentData() {
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\hat{x}"))
        let run = accentRun(scene)
        XCTAssertEqual(run?.x ?? -1, (10 - (run?.size ?? 0)) / 2, accuracy: 0.001,
                       "no data → centered on the advance")
    }

    func testAccentBaseHeightFloorsLowBases() {
        // A low-ink base (ink top at 0.2·size): the accent floors at the
        // font's AccentBaseHeight (0.450 em) instead of sinking to the ink.
        let lowInk: MathTextMeasurer = { text, size, _ in
            GlyphMetrics(width: CGFloat(text.count) * size, ascent: size * 0.75, descent: size * 0.25,
                         inkAscent: size * 0.2, inkDescent: -size * 0.05)
        }
        let engine = MathLayoutEngine(measure: lowInk, baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\hat{x}"))
        let run = accentRun(scene)
        let expectedY = 0.450 * 10 + MathLayout.Accent.clearance * 10 - (-(run?.size ?? 0) * 0.05)
        XCTAssertEqual(run?.y ?? -1, expectedY, accuracy: 0.001,
                       "δ = min(h, AccentBaseHeight) keeps the accent at its design height")
    }

    func testSingleCharAccenteePromotesScripts() {
        // \hat{f}^2: the scripts move onto f (inside the accent), so the
        // accent stays over the f while the ² attaches to the letter.
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        let scene = engine.layout(MathParser.parse("\\hat{f}^2"))
        let accent = accentRun(scene)
        let sup = scene.elements.compactMap { e -> CGFloat? in
            if case let .glyphs("2", _, _, origin, _) = e { return origin.x }
            return nil
        }.first
        XCTAssertNotNil(accent); XCTAssertNotNil(sup)
        XCTAssertLessThan(accent!.x + accent!.size, 10.5, "accent hugs the f, not the scripted width")
        XCTAssertEqual(sup ?? -1, 10, accuracy: 0.001, "script attaches at the f's advance")
    }
}
