#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import VinculumRender
import VinculumLayout

/// Validates the GSUB `ssty` parser against the REAL bundled fonts (their
/// live GSUB bytes), the way the golden PNGs pin rendering. Fixed glyph IDs
/// come from fontTools on Latin Modern Math.
final class SstyFontParseTests: XCTestCase {

    func testLatinModernSstyMapMatchesFontTools() throws {
        let font = MathFont.latinModern
        let v = try XCTUnwrap(font.scriptVariants, "LM Math should have parsed ssty")
        XCTAssertFalse(v.isEmpty)
        // base → (.st, .sts) glyph IDs, verified with fontTools.
        XCTAssertEqual(v.variant(for: 19, level: 1), 1013)   // two → two.st
        XCTAssertEqual(v.variant(for: 19, level: 2), 606)    // two → two.sts
        XCTAssertEqual(v.variant(for: 89, level: 1), 1026)   // x → x.st
        XCTAssertEqual(v.variant(for: 89, level: 2), 619)    // x → x.sts
        XCTAssertEqual(v.variant(for: 4179, level: 1), 4241) // β → beta.st
        // LM Math ships ssty for essentially its whole repertoire.
        XCTAssertGreaterThan(v.script.count, 800)
    }

    func testEveryBundledFontHasSsty() {
        for font in MathFont.bundled {
            guard font.isAvailable else { continue }
            let v = font.scriptVariants
            XCTAssertNotNil(v, "\(font.name) should have a parsed ssty map")
            XCTAssertFalse(v?.isEmpty ?? true, "\(font.name) ssty map is empty")
        }
    }

    // MARK: - End-to-end: ssty reaches the scene

    func testScriptSymbolsBecomeSstyGlyphRuns() {
        // A superscript symbol should now emit a .glyph(id:) (the optical
        // variant, drawn by ID) while the full-size base stays a text run.
        let engine = MathLayoutEngine.make(font: .latinModern, baseSize: 30)
        let scene = engine.layout(MathParser.parse(#"x^{2}"#))
        var glyphID = 0, text = 0
        for e in scene.elements {
            if case .glyph = e { glyphID += 1 }
            if case .glyphs = e { text += 1 }
        }
        XCTAssertEqual(glyphID, 1, "the superscript 2 is an ssty glyph-ID run")
        XCTAssertEqual(text, 1, "the base x stays a normal text run")
    }

    func testNoSstyAtBaseLevel() {
        // A formula with no scripts must emit no ssty glyph-ID runs.
        let engine = MathLayoutEngine.make(font: .latinModern, baseSize: 30)
        let scene = engine.layout(MathParser.parse(#"x + y = z"#))
        for e in scene.elements {
            if case .glyph = e { XCTFail("no ssty substitution should happen at base level") }
        }
    }

    func testHeadlessLayoutSkipsSsty() {
        // The bare (mock-measurer) engine has no ssty provider, so scripts
        // stay text runs — headless geometry is unchanged by this feature.
        let mock: MathTextMeasurer = { t, s, _ in
            GlyphMetrics(width: s * CGFloat(t.count), ascent: s * 0.7, descent: s * 0.2,
                         inkAscent: s * 0.7, inkDescent: 0)
        }
        let scene = MathLayoutEngine(measure: mock, baseSize: 20).layout(MathParser.parse(#"x^{2}"#))
        for e in scene.elements {
            if case .glyph = e { XCTFail("headless layout must not emit ssty glyph-ID runs") }
        }
    }
}
#endif
