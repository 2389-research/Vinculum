#if canImport(CFreetypeShim) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
import Foundation
@testable import VinculumRender
import VinculumLayout

/// Every bundled font must contribute its OWN MATH constants on Linux.
///
/// The regression this guards (#1): `MathTableParser` parses a `MATH` *table*,
/// but the Linux renderer handed it the whole `.otf`. The parser's version guard
/// read the sfnt tag ('OTTO' for our CFF fonts) as a version, failed, and the
/// `?? .latinModern` fallback silently gave Termes, Pagella, STIX Two and Fira
/// Math *Latin Modern's* axis height, script scale-downs and fraction gaps — so
/// font choice had no effect on Linux layout, and nothing went red.
final class MathSilicaFontConstantsTests: XCTestCase {

    func testEachBundledFontParsesItsOwnMathConstants() throws {
        var axisHeights: [String: CGFloat] = [:]

        for res in FreeTypeFonts.resources {
            let loaded = try XCTUnwrap(FreeTypeFonts.loadFont(resource: res), "\(res): failed to load")
            let upm = Int(loaded.font.unitsPerEm)

            // The bug, asserted directly: a font FILE is not a MATH table.
            //
            // This also encodes that every bundled font is CFF-flavoured — bytes
            // 0-3 are 'OTTO', which fails the parser's version guard, so the old
            // code fell back. A TrueType-flavoured MATH font (sfnt 0x00010000)
            // would instead *coincidentally pass* that guard and parse garbage,
            // i.e. the old bug was worse than a fallback for such fonts. If one is
            // ever bundled this assertion fails — which is the right outcome.
            XCTAssertNil(MathTableParser.constants(from: loaded.otf, unitsPerEm: upm),
                         "\(res): the whole .otf must not parse as a MATH table")

            XCTAssertNotNil(loaded.font.sfntTable(tag: FreeTypeFont.mathTableTag),
                            "\(res): no MATH table could be extracted")
            // Goes through the same resolution the renderer uses, so reverting the
            // fix to the font-file form fails here.
            let constants = try XCTUnwrap(FreeTypeFonts.mathConstants(for: loaded.font),
                                          "\(res): its own MATH table must parse")
            axisHeights[res] = constants.axisHeight
        }

        XCTAssertEqual(axisHeights.count, FreeTypeFonts.resources.count)
        // The fallback's signature: every font reporting one identical constant.
        XCTAssertGreaterThan(Set(axisHeights.values).count, 1,
                             "all bundled fonts report the same axis height — constants are still falling back: \(axisHeights)")
    }

    func testSfntTableIsNilForAnAbsentTag() throws {
        let loaded = try XCTUnwrap(FreeTypeFonts.loadFont(resource: "latinmodern-math"))
        XCTAssertNil(loaded.font.sfntTable(tag: 0x5A5A_5A5A /* 'ZZZZ' */),
                     "an absent sfnt tag must yield nil — not empty or garbage bytes")
    }
}
#endif
