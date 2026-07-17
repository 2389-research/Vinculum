import XCTest
@testable import VinculumLayout

/// `MathTableParser` rejects the whole (sub)structure on any malformed field —
/// the discipline every parser in the file follows and `glyphInfo` documents.
///
/// The size-variant ladder was the one outlier: on a short read it `break`ed and
/// then kept the PARTIAL ladder anyway, never checking `vars.count == vCount`. A
/// truncated font therefore gave a glyph a short ladder — missing exactly its
/// LARGEST variants, since `MathGlyphVariantRecord`s are ordered smallest-first
/// — so a `\left(` would quietly stop growing at some size and get scaled
/// instead. Degraded typography, no error, nothing red (#36).
final class MathVariantsTruncationTests: XCTestCase {

    func testIntactLadderIsParsedInFull() throws {
        let v = try XCTUnwrap(MathTableParser.variants(from: Self.truncatedVariantTable,
                                                       unitsPerEm: 1000))
        // The control glyph, whose records are all present, is unaffected — the
        // truncation must cost only the corrupt structure, not its neighbour.
        let intact = try XCTUnwrap(v.vertical[100], "the intact glyph must survive")
        XCTAssertEqual(intact.variants.map(\.glyphID), [101, 102])
        XCTAssertEqual(intact.variants.map(\.advance), [0.5, 0.7])
        XCTAssertEqual(v.minConnectorOverlap, 0.020)
    }

    func testTruncatedLadderDropsTheGlyphRatherThanKeepingAPartialLadder() throws {
        let v = try XCTUnwrap(MathTableParser.variants(from: Self.truncatedVariantTable,
                                                       unitsPerEm: 1000))
        // Glyph 200 declares variantCount=3 but the table ends after 2 records.
        // Keeping [201, 202] would look perfectly healthy to the layout engine
        // while silently missing the largest size — the failure mode this guards.
        XCTAssertNil(v.vertical[200],
                     "a glyph whose variant ladder is truncated must be dropped, not "
                     + "kept with a partial ladder that silently loses its largest sizes")
    }

    /// A real font must be untouched by the stricter check — the guard only ever
    /// fires on already-malformed data.
    func testRealFontIsUnaffected() throws {
        let data = TestFixtures.mathTable("latinmodern-math")
        let v = try XCTUnwrap(MathTableParser.variants(from: data, unitsPerEm: 1000))
        XCTAssertFalse(v.vertical.isEmpty, "LM Math has vertical variant constructions")
        for (glyph, c) in v.vertical where c.variants.isEmpty && c.assembly == nil {
            XCTFail("glyph \(glyph) parsed to an empty construction")
        }
    }

    // MARK: - Synthetic MathVariants fixture

    /// Minimal MATH table: header → MathVariants with a 2-glyph vertical
    /// coverage. Glyph 100's construction is intact (2 records); glyph 200's
    /// declares variantCount=3 but the data ends after 2 — i.e. a truncated
    /// font. Offsets inside MathVariants are relative to its own start (10).
    private static let truncatedVariantTable: Data = {
        func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        var t: [UInt8] = []
        t += u16(1) + u16(0)     // 0:  version 1.0
        t += u16(0)              // 4:  mathConstants: absent
        t += u16(0)              // 6:  mathGlyphInfo: absent
        t += u16(10)             // 8:  mathVariants at 10

        // MathVariants (starts at 10; inner offsets are relative to it)
        t += u16(20)             // 10: minConnectorOverlap = 20/1000
        t += u16(14)             // 12: vertGlyphCoverage   -> abs 24
        t += u16(0)              // 14: horizGlyphCoverage: none
        t += u16(2)              // 16: vertGlyphCount = 2
        t += u16(0)              // 18: horizGlyphCount = 0
        t += u16(22)             // 20: vertConstruction[0] -> abs 32
        t += u16(34)             // 22: vertConstruction[1] -> abs 44

        // Coverage format 1 (abs 24): glyphs 100, 200
        t += u16(1) + u16(2) + u16(100) + u16(200)

        // Construction for glyph 100 (abs 32) — INTACT
        t += u16(0) + u16(2)                       // no assembly, variantCount = 2
        t += u16(101) + u16(500)                   // record 0
        t += u16(102) + u16(700)                   // record 1

        // Construction for glyph 200 (abs 44) — TRUNCATED
        t += u16(0) + u16(3)                       // no assembly, variantCount = 3 …
        t += u16(201) + u16(500)                   // record 0
        t += u16(202) + u16(700)                   // record 1
        // …record 2 is missing: the table simply ends here.
        return Data(t)
    }()
}
