#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import VinculumRender
import VinculumLayout

final class MathFontConstantsTests: XCTestCase {

    /// The live CGFont path (bundle → CGFont → raw MATH bytes → parser) must
    /// produce exactly the `.latinModern` preset, which is itself pinned to
    /// the committed fixture bytes and fontTools ground truth. Three-way
    /// agreement: font ↔ fixture ↔ preset.
    func testLiveFontConstantsMatchPreset() {
        XCTAssertTrue(MathFont.latinModern.isAvailable)
        XCTAssertEqual(MathFont.latinModern.constants, .latinModern)
    }

    /// Every bundled font loads with its own parsed metrics — and they
    /// genuinely differ (fontTools: STIX axis 0.258 vs LM 0.250;
    /// DisplayOperatorMinHeight 1.8 vs 1.3 em), which is the whole point
    /// of parsing per font.
    func testBundledFontsCarryTheirOwnConstants() {
        for font in MathFont.bundled {
            XCTAssertTrue(font.isAvailable, font.name)
            XCTAssertGreaterThan(font.constants.axisHeight, 0, font.name)
        }
        XCTAssertEqual(MathFont.stixTwo.constants.axisHeight, 0.258)
        XCTAssertEqual(MathFont.stixTwo.constants.displayOperatorMinHeight, 1.800)
        XCTAssertEqual(MathFont.pagella.constants.displayOperatorMinHeight, 1.500)
    }

    /// STIX Two ships MathKernInfo (233 glyphs) — the data that drives
    /// Phase 3's cut-in kerning for real.
    func testStixTwoCarriesCutInKerns() {
        XCTAssertEqual(MathFont.stixTwo.glyphInfo?.kerns.isEmpty, false)
    }
}
#endif
