import XCTest
@testable import VinculumLayout

/// Headless (Linux-safe) tests of the GSUB `ssty` parser, driven by a
/// hand-built minimal GSUB table so the parse logic is pinned with no font.
final class GsubScriptStyleParserTests: XCTestCase {

    /// Builds a minimal but spec-valid GSUB table with a single `ssty`
    /// feature → one AlternateSubst lookup mapping base 10→(11,12) and
    /// 20→(21,22). Big-endian throughout.
    private func syntheticGsub() -> [UInt8] {
        var b = [UInt8]()
        func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

        // Contiguous layout (byte offsets in comments):
        // Header 0..10 | FeatureList 10..18 | Feature 18..24 | LookupList 24..28 |
        // Lookup 28..36 | AlternateSubst 36.. (sets + coverage).
        b += u16(1) + u16(0)          // @0  version 1.0
        b += u16(0)                   // @4  scriptList offset (unused)
        b += u16(10)                  // @6  featureList offset → @10
        b += u16(24)                  // @8  lookupList offset → @24

        // FeatureList @10: count=1, record{tag "ssty", offset=8 (rel → Feature @18)}.
        b += u16(1)                                   // @10 featureCount
        b += [0x73, 0x73, 0x74, 0x79]                 // @12 "ssty"
        b += u16(8)                                   // @16 feature offset
        // Feature @18: featureParams=0, lookupCount=1, lookupIndex[0]=0.
        b += u16(0) + u16(1) + u16(0)                 // @18..24

        // LookupList @24: count=1, offset[0]=4 (rel → Lookup @28).
        b += u16(1) + u16(4)                          // @24..28
        // Lookup @28: type=3 (Alternate), flag=0, subCount=1, subOffset[0]=8 (→ @36).
        b += u16(3) + u16(0) + u16(1) + u16(8)        // @28..36

        // AlternateSubst @36 (subStart): format, coverageOffset, count, setOffsets[2].
        //   body 10 bytes → set0 @+10, set1 @+16, coverage @+22.
        let subStart = 36
        b += u16(1)                                   // @36 format 1
        b += u16(22)                                  // @38 coverage offset (rel to subStart)
        b += u16(2)                                   // @40 alternateSetCount
        b += u16(10) + u16(16)                        // @42 setOffsets (rel to subStart)
        b += u16(2) + u16(11) + u16(12)               // @46 set0: count 2, [11,12]
        b += u16(2) + u16(21) + u16(22)               // @52 set1: count 2, [21,22]
        b += u16(1) + u16(2) + u16(10) + u16(20)      // @58 coverage: fmt1, count 2, [10,20]
        XCTAssertEqual(b.count, subStart + 22 + 8, "synthetic GSUB layout")   // 66
        return b
    }

    func testParsesAlternateSubstitutions() {
        let v = GsubScriptStyleParser.parse(syntheticGsub())
        XCTAssertFalse(v.isEmpty)
        XCTAssertEqual(v.variant(for: 10, level: 1), 11)   // .st
        XCTAssertEqual(v.variant(for: 10, level: 2), 12)   // .sts
        XCTAssertEqual(v.variant(for: 20, level: 1), 21)
        XCTAssertEqual(v.variant(for: 20, level: 2), 22)
        XCTAssertNil(v.variant(for: 99, level: 1))          // uncovered glyph
        XCTAssertNil(v.variant(for: 10, level: 0))          // no ssty at base level
    }

    func testScriptScriptFallsBackToScriptWhenSingle() {
        var v = MathScriptVariants()
        v.script[5] = 6                                     // only a level-1 variant
        XCTAssertEqual(v.variant(for: 5, level: 2), 6)
    }

    func testMalformedBytesDegradeToEmpty() {
        XCTAssertTrue(GsubScriptStyleParser.parse([]).isEmpty)
        XCTAssertTrue(GsubScriptStyleParser.parse([0, 1, 0, 0]).isEmpty)          // truncated header
        XCTAssertTrue(GsubScriptStyleParser.parse([UInt8](repeating: 0xFF, count: 64)).isEmpty)
        // A valid header pointing past the buffer must not crash.
        var b: [UInt8] = [0, 1, 0, 0, 0, 0, 0xFF, 0xFE, 0xFF, 0xFE]
        XCTAssertTrue(GsubScriptStyleParser.parse(b).isEmpty)
        b = syntheticGsub(); b.removeLast(20)                                     // chop the tail
        _ = GsubScriptStyleParser.parse(b)                                        // must not crash
    }
}
