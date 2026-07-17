#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
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

        for res in MathSilicaRenderer.resources {
            let loaded = try XCTUnwrap(MathSilicaRenderer.loadFont(resource: res), "\(res): failed to load")
            let upm = Int(loaded.font.unitsPerEm)

            // The bug, asserted directly: a font FILE is not a MATH table.
            XCTAssertNil(MathTableParser.constants(from: loaded.otf, unitsPerEm: upm),
                         "\(res): the whole .otf must not parse as a MATH table")

            XCTAssertNotNil(loaded.font.sfntTable(tag: 0x4D41_5448 /* 'MATH' */),
                            "\(res): no MATH table could be extracted")
            // Goes through the same resolution the renderer uses, so reverting the
            // fix to the font-file form fails here.
            let constants = try XCTUnwrap(MathSilicaRenderer.mathConstants(for: loaded.font),
                                          "\(res): its own MATH table must parse")
            axisHeights[res] = constants.axisHeight
        }

        XCTAssertEqual(axisHeights.count, MathSilicaRenderer.resources.count)
        // The fallback's signature: every font reporting one identical constant.
        XCTAssertGreaterThan(Set(axisHeights.values).count, 1,
                             "all bundled fonts report the same axis height — constants are still falling back: \(axisHeights)")
    }
}
#endif
