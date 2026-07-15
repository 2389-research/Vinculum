import XCTest
@testable import VinculumLayout

/// oracle tests: `MathTableParser` against the committed raw `MATH`
/// table of Latin Modern Math (`Tests/fixtures/math-table/`), cross-checked
/// with fontTools 4.62.1 ground truth (values in the assertions below were
/// dumped independently with fontTools.ttLib; LM Math has unitsPerEm 1000).
///
/// Historical note: this oracle caught three bugs in the hand transcription
/// the engine shipped through v0.23 — `spaceAfterScript` was 0.041 (font:
/// 0.056), `radicalVerticalGap` was 0.148 (the *display* value; text is
/// 0.050), and `stackGapMin` was 0.150 (font: 0.120 text / 0.280 display).
final class MathTableParserTests: XCTestCase {

    private static let fixture = TestFixtures.mathTable("latinmodern-math")

    // MARK: - MathConstants sub-table

    func testParsedConstantsMatchFontToolsGroundTruth() throws {
        let parsed = try XCTUnwrap(MathTableParser.constants(from: Self.fixture, unitsPerEm: 1000))
        // The .latinModern preset is written as designUnits/1000 divisions,
        // so exact equality against the parsed values is well-defined.
        XCTAssertEqual(parsed, MathFontConstants.latinModern)
    }

    func testSpotValuesAgainstFontTools() throws {
        let c = try XCTUnwrap(MathTableParser.constants(from: Self.fixture, unitsPerEm: 1000))
        // Percentages become fractions.
        XCTAssertEqual(c.scriptPercentScaleDown, 0.70)
        XCTAssertEqual(c.scriptScriptPercentScaleDown, 0.50)
        // Values the old transcription already had right.
        XCTAssertEqual(c.axisHeight, 0.250)
        XCTAssertEqual(c.superscriptShiftUp, 0.363)
        XCTAssertEqual(c.superscriptShiftUpCramped, 0.289)
        XCTAssertEqual(c.subscriptShiftDown, 0.247)
        XCTAssertEqual(c.fractionNumeratorShiftUp, 0.394)
        XCTAssertEqual(c.fractionDenominatorShiftDown, 0.345)
        XCTAssertEqual(c.fractionRuleThickness, 0.040)
        XCTAssertEqual(c.accentBaseHeight, 0.450)
        XCTAssertEqual(c.upperLimitBaselineRiseMin, 0.111)
        XCTAssertEqual(c.lowerLimitBaselineDropMin, 0.600)
        // The three the transcription got wrong (font is authoritative).
        XCTAssertEqual(c.spaceAfterScript, 0.056)
        XCTAssertEqual(c.radicalVerticalGap, 0.050)
        XCTAssertEqual(c.stackGapMin, 0.120)
        // A negative FWORD proves signed parsing.
        XCTAssertEqual(c.radicalKernAfterDegree, -0.556)
        // RadicalDegreeBottomRaisePercent is a percentage, not a length.
        XCTAssertEqual(c.radicalDegreeBottomRaisePercent, 0.60)
    }

    func testConstantsTheTranscriptionNeverHad() throws {
        let c = try XCTUnwrap(MathTableParser.constants(from: Self.fixture, unitsPerEm: 1000))
        XCTAssertEqual(c.displayOperatorMinHeight, 1.300)
        XCTAssertEqual(c.delimitedSubFormulaMinHeight, 1.300)
        XCTAssertEqual(c.subSuperscriptGapMin, 0.160)
        XCTAssertEqual(c.superscriptBottomMin, 0.108)
        XCTAssertEqual(c.superscriptBottomMaxWithSubscript, 0.344)
        XCTAssertEqual(c.subscriptTopMax, 0.344)
        XCTAssertEqual(c.superscriptBaselineDropMax, 0.250)
        XCTAssertEqual(c.subscriptBaselineDropMin, 0.200)
        XCTAssertEqual(c.radicalDisplayStyleVerticalGap, 0.148)
        XCTAssertEqual(c.stackDisplayStyleGapMin, 0.280)
        XCTAssertEqual(c.fractionNumeratorGapMin, 0.040)
        XCTAssertEqual(c.fractionNumeratorDisplayStyleGapMin, 0.120)
        XCTAssertEqual(c.radicalKernBeforeDegree, 0.278)
    }

    // MARK: - MathGlyphInfo sub-table

    func testGlyphInfoCoverageCounts() throws {
        let info = try XCTUnwrap(MathTableParser.glyphInfo(from: Self.fixture, unitsPerEm: 1000))
        // fontTools: italics=1002 glyphs, topAccent=2475, extendedShapes=250.
        XCTAssertEqual(info.italicsCorrection.count, 1002)
        XCTAssertEqual(info.topAccentAttachment.count, 2475)
        XCTAssertEqual(info.extendedShapes.count, 250)
        // Latin Modern Math ships no MathKernInfo (verified with fontTools);
        // cut-in kern parsing is exercised with synthetic bytes below and
        // with STIX Two once Phase 7 bundles it.
        XCTAssertTrue(info.kerns.isEmpty)
    }

    func testGlyphInfoSpotValues() throws {
        let info = try XCTUnwrap(MathTableParser.glyphInfo(from: Self.fixture, unitsPerEm: 1000))
        // fontTools ground truth, by glyph ID (LM Math glyph order):
        XCTAssertEqual(info.italicsCorrection[71], 0.079)    // 'f'
        XCTAssertEqual(info.italicsCorrection[3049], 0.332)  // 'integral'
        XCTAssertEqual(info.italicsCorrection[24], 0.013)    // 'seven'
        XCTAssertEqual(info.italicsCorrection[51], 0.024)    // 'R'
        XCTAssertEqual(info.italicsCorrection[56], 0.009)    // 'W'
        XCTAssertEqual(info.topAccentAttachment[34], 0.375)  // 'A'
    }

    func testSyntheticKernStaircase() throws {
        // Hand-built MathKernInfo: one glyph (id 7), topRight staircase with
        // heights [100, 300] and kerns [10, 20, 30] (design units, upm 1000).
        let info = try XCTUnwrap(
            MathTableParser.glyphInfo(from: Self.syntheticKernTable, unitsPerEm: 1000))
        let entry = try XCTUnwrap(info.kerns[7])
        let stair = try XCTUnwrap(entry.topRight)
        XCTAssertNil(entry.topLeft)
        XCTAssertEqual(stair.correctionHeights, [0.100, 0.300])
        XCTAssertEqual(stair.kernValues, [0.010, 0.020, 0.030])
        // Staircase evaluation: below first height → first kern; between →
        // middle; at/above last → last.
        XCTAssertEqual(stair.kern(atHeight: 0.050), 0.010)
        XCTAssertEqual(stair.kern(atHeight: 0.200), 0.020)
        XCTAssertEqual(stair.kern(atHeight: 0.900), 0.030)
    }

    // MARK: - Malformation

    func testMalformedTablesYieldNil() {
        XCTAssertNil(MathTableParser.constants(from: Data(), unitsPerEm: 1000))
        XCTAssertNil(MathTableParser.glyphInfo(from: Data(), unitsPerEm: 1000))
        XCTAssertNil(MathTableParser.constants(from: Self.fixture.prefix(10), unitsPerEm: 1000))
        XCTAssertNil(MathTableParser.constants(from: Data(repeating: 0xFF, count: 64), unitsPerEm: 1000))
        XCTAssertNil(MathTableParser.constants(from: Self.fixture, unitsPerEm: 0))
    }

    // MARK: - Synthetic MathKernInfo fixture

    /// Minimal MATH table: header → MathGlyphInfo with only MathKernInfo →
    /// coverage(format 1, glyph 7) → one MathKernInfoRecord (topRight only) →
    /// MathKern(heightCount=2, heights [100,300], kerns [10,20,30]).
    private static let syntheticKernTable: Data = {
        func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        var t: [UInt8] = []
        t += u16(1) + u16(0)     // version 1.0
        t += u16(0)              // mathConstants: absent
        t += u16(10)             // mathGlyphInfo at offset 10
        t += u16(0)              // mathVariants: absent
        // MathGlyphInfo (at 10): italics=0, topAccent=0, extShapes=0, kernInfo=8
        t += u16(0) + u16(0) + u16(0) + u16(8)
        // MathKernInfo (at 18): coverage@12, kernCount=1,
        // record: topRight@18, topLeft=0, bottomRight=0, bottomLeft=0
        t += u16(12) + u16(1)
        t += u16(18) + u16(0) + u16(0) + u16(0)
        // Coverage (at 18+12=30): format 1, count 1, glyph 7
        t += u16(1) + u16(1) + u16(7)
        // MathKern (at 18+18=36): heightCount=2,
        // heights: MathValueRecords (100,0) (300,0), kerns: (10,0) (20,0) (30,0)
        t += u16(2)
        t += u16(100) + u16(0) + u16(300) + u16(0)
        t += u16(10) + u16(0) + u16(20) + u16(0) + u16(30) + u16(0)
        return Data(t)
    }()
}
