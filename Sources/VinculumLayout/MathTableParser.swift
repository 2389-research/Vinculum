import Foundation

// The font's OpenType MATH table, parsed from raw bytes into pure data. This file is platform-free — bytes
// in (obtained by the renderer via CGFont, or from a fixture on Linux),
// values out, everything bounds-checked, `nil` on malformation, never a trap.
//
// Values are exposed as em fractions (design units ÷ unitsPerEm) so layout
// code multiplies by the point size directly, matching the convention the
// hand-transcribed `MathConstants` used. Percentages become fractions (÷100).

/// The 56 values of the MATH table's `MathConstants` sub-table — the σ/ξ
/// parameters TeX reads from the font (Appendix G), OpenType edition.
///
/// `.latinModern` carries Latin Modern Math's values (fontTools-verified,
/// test-pinned against the committed fixture bytes) so headless/Linux hosts
/// and mock-measurer tests have TeX-true numbers without a font present.
public struct MathFontConstants: Equatable, Sendable {
    // Percentages, as fractions.
    public var scriptPercentScaleDown: CGFloat
    public var scriptScriptPercentScaleDown: CGFloat
    public var radicalDegreeBottomRaisePercent: CGFloat
    // Minimum heights.
    public var delimitedSubFormulaMinHeight: CGFloat
    public var displayOperatorMinHeight: CGFloat
    // General.
    public var mathLeading: CGFloat
    public var axisHeight: CGFloat
    public var accentBaseHeight: CGFloat
    public var flattenedAccentBaseHeight: CGFloat
    // Scripts.
    public var subscriptShiftDown: CGFloat
    public var subscriptTopMax: CGFloat
    public var subscriptBaselineDropMin: CGFloat
    public var superscriptShiftUp: CGFloat
    public var superscriptShiftUpCramped: CGFloat
    public var superscriptBottomMin: CGFloat
    public var superscriptBaselineDropMax: CGFloat
    public var subSuperscriptGapMin: CGFloat
    public var superscriptBottomMaxWithSubscript: CGFloat
    public var spaceAfterScript: CGFloat
    // Limits.
    public var upperLimitGapMin: CGFloat
    public var upperLimitBaselineRiseMin: CGFloat
    public var lowerLimitGapMin: CGFloat
    public var lowerLimitBaselineDropMin: CGFloat
    // Stacks (\atop, \binom).
    public var stackTopShiftUp: CGFloat
    public var stackTopDisplayStyleShiftUp: CGFloat
    public var stackBottomShiftDown: CGFloat
    public var stackBottomDisplayStyleShiftDown: CGFloat
    public var stackGapMin: CGFloat
    public var stackDisplayStyleGapMin: CGFloat
    // Stretch stacks (\overbrace rows, \xrightarrow labels).
    public var stretchStackTopShiftUp: CGFloat
    public var stretchStackBottomShiftDown: CGFloat
    public var stretchStackGapAboveMin: CGFloat
    public var stretchStackGapBelowMin: CGFloat
    // Fractions.
    public var fractionNumeratorShiftUp: CGFloat
    public var fractionNumeratorDisplayStyleShiftUp: CGFloat
    public var fractionDenominatorShiftDown: CGFloat
    public var fractionDenominatorDisplayStyleShiftDown: CGFloat
    public var fractionNumeratorGapMin: CGFloat
    public var fractionNumeratorDisplayStyleGapMin: CGFloat
    public var fractionRuleThickness: CGFloat
    public var fractionDenominatorGapMin: CGFloat
    public var fractionDenominatorDisplayStyleGapMin: CGFloat
    public var skewedFractionHorizontalGap: CGFloat
    public var skewedFractionVerticalGap: CGFloat
    // Over/underbars.
    public var overbarVerticalGap: CGFloat
    public var overbarRuleThickness: CGFloat
    public var overbarExtraAscender: CGFloat
    public var underbarVerticalGap: CGFloat
    public var underbarRuleThickness: CGFloat
    public var underbarExtraDescender: CGFloat
    // Radicals.
    public var radicalVerticalGap: CGFloat
    public var radicalDisplayStyleVerticalGap: CGFloat
    public var radicalRuleThickness: CGFloat
    public var radicalExtraAscender: CGFloat
    public var radicalKernBeforeDegree: CGFloat
    public var radicalKernAfterDegree: CGFloat

    /// TeX's ξ8 `default_rule_thickness`, which has no dedicated OpenType
    /// constant — used for bars with no MATH-table value of their own
    /// (arrow shafts, `\boxed` frames). OpenType splits ξ8 across the
    /// fraction/overbar/underbar/radical rule constants; the fraction one
    /// stands in, as they coincide in TeX-derived fonts.
    public var defaultRuleThickness: CGFloat { fractionRuleThickness }

    /// Latin Modern Math (unitsPerEm 1000), fontTools-verified. Written as
    /// designUnits-over-denominator divisions so equality against runtime-
    /// parsed values is exact.
    public static let latinModern = MathFontConstants(
        scriptPercentScaleDown: 70 / 100,
        scriptScriptPercentScaleDown: 50 / 100,
        radicalDegreeBottomRaisePercent: 60 / 100,
        delimitedSubFormulaMinHeight: 1300 / 1000,
        displayOperatorMinHeight: 1300 / 1000,
        mathLeading: 154 / 1000,
        axisHeight: 250 / 1000,
        accentBaseHeight: 450 / 1000,
        flattenedAccentBaseHeight: 664 / 1000,
        subscriptShiftDown: 247 / 1000,
        subscriptTopMax: 344 / 1000,
        subscriptBaselineDropMin: 200 / 1000,
        superscriptShiftUp: 363 / 1000,
        superscriptShiftUpCramped: 289 / 1000,
        superscriptBottomMin: 108 / 1000,
        superscriptBaselineDropMax: 250 / 1000,
        subSuperscriptGapMin: 160 / 1000,
        superscriptBottomMaxWithSubscript: 344 / 1000,
        spaceAfterScript: 56 / 1000,
        upperLimitGapMin: 200 / 1000,
        upperLimitBaselineRiseMin: 111 / 1000,
        lowerLimitGapMin: 167 / 1000,
        lowerLimitBaselineDropMin: 600 / 1000,
        stackTopShiftUp: 444 / 1000,
        stackTopDisplayStyleShiftUp: 677 / 1000,
        stackBottomShiftDown: 345 / 1000,
        stackBottomDisplayStyleShiftDown: 686 / 1000,
        stackGapMin: 120 / 1000,
        stackDisplayStyleGapMin: 280 / 1000,
        stretchStackTopShiftUp: 111 / 1000,
        stretchStackBottomShiftDown: 600 / 1000,
        stretchStackGapAboveMin: 200 / 1000,
        stretchStackGapBelowMin: 167 / 1000,
        fractionNumeratorShiftUp: 394 / 1000,
        fractionNumeratorDisplayStyleShiftUp: 677 / 1000,
        fractionDenominatorShiftDown: 345 / 1000,
        fractionDenominatorDisplayStyleShiftDown: 686 / 1000,
        fractionNumeratorGapMin: 40 / 1000,
        fractionNumeratorDisplayStyleGapMin: 120 / 1000,
        fractionRuleThickness: 40 / 1000,
        fractionDenominatorGapMin: 40 / 1000,
        fractionDenominatorDisplayStyleGapMin: 120 / 1000,
        skewedFractionHorizontalGap: 350 / 1000,
        skewedFractionVerticalGap: 96 / 1000,
        overbarVerticalGap: 120 / 1000,
        overbarRuleThickness: 40 / 1000,
        overbarExtraAscender: 40 / 1000,
        underbarVerticalGap: 120 / 1000,
        underbarRuleThickness: 40 / 1000,
        underbarExtraDescender: 40 / 1000,
        radicalVerticalGap: 50 / 1000,
        radicalDisplayStyleVerticalGap: 148 / 1000,
        radicalRuleThickness: 40 / 1000,
        radicalExtraAscender: 40 / 1000,
        radicalKernBeforeDegree: 278 / 1000,
        radicalKernAfterDegree: -556 / 1000)
}

/// Per-glyph typography from the MATH table's `MathGlyphInfo` sub-table:
/// italic corrections (Rule 17/18f), top-accent attachment points (Rule 12),
/// extended shapes, and cut-in kerning staircases (script positioning
/// against the base glyph's actual corner profile).
public struct MathGlyphInfo: Sendable {
    /// Piecewise-constant kern against one corner of a glyph: `kernValues`
    /// has one more entry than `correctionHeights`; band `i` applies below
    /// `correctionHeights[i]`.
    public struct KernStaircase: Equatable, Sendable {
        public let correctionHeights: [CGFloat]
        public let kernValues: [CGFloat]

        public func kern(atHeight height: CGFloat) -> CGFloat {
            var i = 0
            while i < correctionHeights.count && height >= correctionHeights[i] { i += 1 }
            return kernValues[i]
        }

        /// The staircase with every height and kern multiplied by `factor` —
        /// how em-relative table data becomes point values at a size.
        public func scaled(by factor: CGFloat) -> KernStaircase {
            KernStaircase(correctionHeights: correctionHeights.map { $0 * factor },
                          kernValues: kernValues.map { $0 * factor })
        }
    }

    /// The four corners of a glyph's cut-in kern data; absent corners are nil.
    public struct KernEntry: Equatable, Sendable {
        public let topRight: KernStaircase?
        public let topLeft: KernStaircase?
        public let bottomRight: KernStaircase?
        public let bottomLeft: KernStaircase?
    }

    /// Glyph ID → italic correction (em fractions).
    public let italicsCorrection: [UInt16: CGFloat]
    /// Glyph ID → top-accent attachment x (em fractions from the origin).
    public let topAccentAttachment: [UInt16: CGFloat]
    /// Glyphs the font marks as extended shapes (tall variants).
    public let extendedShapes: Set<UInt16>
    /// Glyph ID → cut-in kern staircases, per corner.
    public let kerns: [UInt16: KernEntry]
}

/// Bounds-checked big-endian parser for the raw `MATH` table bytes.
/// `package`: VinculumRender consumes it; hosts get parsed results through
/// `MathFont` and the provider seams, never raw bytes.
package enum MathTableParser {

    // MARK: - Public entry points

    /// Parses the `MathConstants` sub-table. Returns nil when the header is
    /// malformed, the sub-table is absent/truncated, or `unitsPerEm <= 0`.
    package static func constants(from data: Data, unitsPerEm: Int) -> MathFontConstants? {
        guard unitsPerEm > 0 else { return nil }
        let b = [UInt8](data)
        guard let start = subTable(at: 4, in: b) else { return nil }
        // 2 percents + 2 UFWORDs + 51 MathValueRecords + 1 percent = 214 bytes.
        guard start + 214 <= b.count else { return nil }
        let em = CGFloat(unitsPerEm)

        func percent(_ field: Int) -> CGFloat { CGFloat(i16(b, start + field)) / 100 }
        func ufword(_ field: Int) -> CGFloat { CGFloat(u16v(b, start + field)) / em }
        // MathValueRecord: FWORD value + Offset16 device table (ignored).
        func value(_ index: Int) -> CGFloat { CGFloat(i16(b, start + 8 + 4 * index)) / em }

        return MathFontConstants(
            scriptPercentScaleDown: percent(0),
            scriptScriptPercentScaleDown: percent(2),
            radicalDegreeBottomRaisePercent: CGFloat(i16(b, start + 212)) / 100,
            delimitedSubFormulaMinHeight: ufword(4),
            displayOperatorMinHeight: ufword(6),
            mathLeading: value(0),
            axisHeight: value(1),
            accentBaseHeight: value(2),
            flattenedAccentBaseHeight: value(3),
            subscriptShiftDown: value(4),
            subscriptTopMax: value(5),
            subscriptBaselineDropMin: value(6),
            superscriptShiftUp: value(7),
            superscriptShiftUpCramped: value(8),
            superscriptBottomMin: value(9),
            superscriptBaselineDropMax: value(10),
            subSuperscriptGapMin: value(11),
            superscriptBottomMaxWithSubscript: value(12),
            spaceAfterScript: value(13),
            upperLimitGapMin: value(14),
            upperLimitBaselineRiseMin: value(15),
            lowerLimitGapMin: value(16),
            lowerLimitBaselineDropMin: value(17),
            stackTopShiftUp: value(18),
            stackTopDisplayStyleShiftUp: value(19),
            stackBottomShiftDown: value(20),
            stackBottomDisplayStyleShiftDown: value(21),
            stackGapMin: value(22),
            stackDisplayStyleGapMin: value(23),
            stretchStackTopShiftUp: value(24),
            stretchStackBottomShiftDown: value(25),
            stretchStackGapAboveMin: value(26),
            stretchStackGapBelowMin: value(27),
            fractionNumeratorShiftUp: value(28),
            fractionNumeratorDisplayStyleShiftUp: value(29),
            fractionDenominatorShiftDown: value(30),
            fractionDenominatorDisplayStyleShiftDown: value(31),
            fractionNumeratorGapMin: value(32),
            fractionNumeratorDisplayStyleGapMin: value(33),
            fractionRuleThickness: value(34),
            fractionDenominatorGapMin: value(35),
            fractionDenominatorDisplayStyleGapMin: value(36),
            skewedFractionHorizontalGap: value(37),
            skewedFractionVerticalGap: value(38),
            overbarVerticalGap: value(39),
            overbarRuleThickness: value(40),
            overbarExtraAscender: value(41),
            underbarVerticalGap: value(42),
            underbarRuleThickness: value(43),
            underbarExtraDescender: value(44),
            radicalVerticalGap: value(45),
            radicalDisplayStyleVerticalGap: value(46),
            radicalRuleThickness: value(47),
            radicalExtraAscender: value(48),
            radicalKernBeforeDegree: value(49),
            radicalKernAfterDegree: value(50))
    }

    /// Parses the `MathGlyphInfo` sub-table. Returns nil when the header is
    /// malformed or the sub-table is absent; individually malformed inner
    /// tables degrade to empty maps (same discipline as the variants parser).
    package static func glyphInfo(from data: Data, unitsPerEm: Int) -> MathGlyphInfo? {
        guard unitsPerEm > 0 else { return nil }
        let b = [UInt8](data)
        guard let gi = subTable(at: 6, in: b) else { return nil }
        let em = CGFloat(unitsPerEm)

        var italics: [UInt16: CGFloat] = [:]
        var accents: [UInt16: CGFloat] = [:]
        var extended: Set<UInt16> = []
        var kerns: [UInt16: MathGlyphInfo.KernEntry] = [:]

        // MathItalicsCorrectionInfo and MathTopAccentAttachment share a
        // shape: coverage offset, count, then count MathValueRecords.
        func valueMap(at tableStart: Int) -> [UInt16: CGFloat] {
            guard let covOff = u16(b, tableStart), covOff > 0,
                  let count = u16(b, tableStart + 2),
                  let glyphs = coverage(b, at: tableStart + covOff),
                  glyphs.count == count else { return [:] }
            var map: [UInt16: CGFloat] = [:]
            map.reserveCapacity(count)
            for (index, glyph) in glyphs.enumerated() {
                let rec = tableStart + 4 + 4 * index
                guard rec + 1 < b.count else { return [:] }
                map[glyph] = CGFloat(i16(b, rec)) / em
            }
            return map
        }

        if let off = u16(b, gi), off > 0 { italics = valueMap(at: gi + off) }
        if let off = u16(b, gi + 2), off > 0 { accents = valueMap(at: gi + off) }
        if let off = u16(b, gi + 4), off > 0, let glyphs = coverage(b, at: gi + off) {
            extended = Set(glyphs)
        }
        if let off = u16(b, gi + 6), off > 0 {
            kerns = kernInfo(b, at: gi + off, em: em)
        }
        return MathGlyphInfo(italicsCorrection: italics, topAccentAttachment: accents,
                             extendedShapes: extended, kerns: kerns)
    }

    /// Parses the `MathVariants` sub-table: minConnectorOverlap plus, per
    /// covered glyph, the size-variant ladder and (if present) the
    /// extensible `GlyphAssembly`. Assemblies with a degenerate extender
    /// (fullAdvance ≤ 0, would loop forever) are dropped at parse.
    package static func variants(from data: Data, unitsPerEm: Int) -> MathVariantsData? {
        guard unitsPerEm > 0 else { return nil }
        let b = [UInt8](data)
        guard let mv = subTable(at: 8, in: b) else { return nil }
        let em = CGFloat(unitsPerEm)
        guard let mco = u16(b, mv),
              let vertCovOff = u16(b, mv + 2), let horizCovOff = u16(b, mv + 4),
              let vertCount = u16(b, mv + 6), let horizCount = u16(b, mv + 8) else { return nil }

        func assembly(at start: Int) -> MathGlyphAssembly? {
            guard start + 5 < b.count, let count = u16(b, start + 4) else { return nil }
            var parts: [MathGlyphAssembly.Part] = []
            parts.reserveCapacity(count)
            for i in 0..<count {
                let rec = start + 6 + 10 * i
                guard let g = u16(b, rec), let sc = u16(b, rec + 2), let ec = u16(b, rec + 4),
                      let fa = u16(b, rec + 6), let flags = u16(b, rec + 8) else { return nil }
                parts.append(.init(glyphID: UInt16(g),
                                   startConnector: CGFloat(sc) / em,
                                   endConnector: CGFloat(ec) / em,
                                   fullAdvance: CGFloat(fa) / em,
                                   isExtender: flags & 1 == 1))
            }
            guard !parts.isEmpty,
                  !parts.contains(where: { $0.isExtender && $0.fullAdvance <= 0 }) else { return nil }
            return MathGlyphAssembly(italicsCorrection: CGFloat(i16(b, start)) / em, parts: parts)
        }

        func constructions(covOff: Int, count: Int, offsetsBase: Int)
            -> [UInt16: MathVariantsData.Construction] {
            guard covOff > 0, count > 0,
                  let glyphs = coverage(b, at: mv + covOff), glyphs.count == count else { return [:] }
            var out: [UInt16: MathVariantsData.Construction] = [:]
            out.reserveCapacity(count)
            for (i, glyph) in glyphs.enumerated() {
                guard let cOff = u16(b, offsetsBase + 2 * i), cOff > 0 else { continue }
                let c = mv + cOff
                guard let asmOff = u16(b, c), let vCount = u16(b, c + 2) else { continue }
                var vars: [MathVariantsData.Variant] = []
                vars.reserveCapacity(vCount)
                for k in 0..<vCount {
                    guard let vg = u16(b, c + 4 + 4 * k), let adv = u16(b, c + 6 + 4 * k) else { break }
                    vars.append(.init(glyphID: UInt16(vg), advance: CGFloat(adv) / em))
                }
                out[glyph] = MathVariantsData.Construction(
                    variants: vars,
                    assembly: asmOff > 0 ? assembly(at: c + asmOff) : nil)
            }
            return out
        }

        return MathVariantsData(
            minConnectorOverlap: CGFloat(mco) / em,
            vertical: constructions(covOff: vertCovOff, count: vertCount, offsetsBase: mv + 10),
            horizontal: constructions(covOff: horizCovOff, count: horizCount,
                                      offsetsBase: mv + 10 + 2 * vertCount))
    }

    // MARK: - Inner tables

    private static func kernInfo(_ b: [UInt8], at start: Int, em: CGFloat)
        -> [UInt16: MathGlyphInfo.KernEntry] {
        guard let covOff = u16(b, start), covOff > 0,
              let count = u16(b, start + 2),
              let glyphs = coverage(b, at: start + covOff),
              glyphs.count == count else { return [:] }

        func staircase(_ off: Int) -> MathGlyphInfo.KernStaircase? {
            guard off > 0 else { return nil }
            let k = start + off
            guard let heightCount = u16(b, k) else { return nil }
            var heights: [CGFloat] = []
            var values: [CGFloat] = []
            for i in 0..<heightCount {
                let rec = k + 2 + 4 * i
                guard rec + 1 < b.count else { return nil }
                heights.append(CGFloat(i16(b, rec)) / em)
            }
            for i in 0...heightCount {
                let rec = k + 2 + 4 * heightCount + 4 * i
                guard rec + 1 < b.count else { return nil }
                values.append(CGFloat(i16(b, rec)) / em)
            }
            return MathGlyphInfo.KernStaircase(correctionHeights: heights, kernValues: values)
        }

        var out: [UInt16: MathGlyphInfo.KernEntry] = [:]
        for (index, glyph) in glyphs.enumerated() {
            let rec = start + 4 + 8 * index
            guard let tr = u16(b, rec), let tl = u16(b, rec + 2),
                  let br = u16(b, rec + 4), let bl = u16(b, rec + 6) else { return [:] }
            let entry = MathGlyphInfo.KernEntry(
                topRight: staircase(tr), topLeft: staircase(tl),
                bottomRight: staircase(br), bottomLeft: staircase(bl))
            if entry.topRight != nil || entry.topLeft != nil
                || entry.bottomRight != nil || entry.bottomLeft != nil {
                out[glyph] = entry
            }
        }
        return out
    }

    /// OpenType coverage table → glyph IDs in coverage-index order.
    private static func coverage(_ b: [UInt8], at start: Int) -> [UInt16]? {
        guard let format = u16(b, start) else { return nil }
        if format == 1 {
            guard let count = u16(b, start + 2) else { return nil }
            var glyphs: [UInt16] = []
            glyphs.reserveCapacity(count)
            for i in 0..<count {
                guard let g = u16(b, start + 4 + 2 * i) else { return nil }
                glyphs.append(UInt16(g))
            }
            return glyphs
        }
        if format == 2 {
            guard let ranges = u16(b, start + 2) else { return nil }
            var byIndex: [(index: Int, glyph: UInt16)] = []
            for r in 0..<ranges {
                let rec = start + 4 + 6 * r
                guard let s = u16(b, rec), let e = u16(b, rec + 2),
                      let startIndex = u16(b, rec + 4), s <= e,
                      // A font has at most 65536 glyphs; crafted overlapping
                      // ranges could otherwise force a multi-GB expansion
                      // before the callers' count checks ever run.
                      byIndex.count + (e - s + 1) <= 0x1_0000 else { return nil }
                for g in s...e { byIndex.append((startIndex + (g - s), UInt16(g))) }
            }
            return byIndex.sorted { $0.index < $1.index }.map(\.glyph)
        }
        return nil
    }

    // MARK: - Primitives

    /// Validates the MATH header (version 1.0) and returns the absolute,
    /// in-bounds start of the sub-table whose offset lives at `headerOffset`.
    private static func subTable(at headerOffset: Int, in b: [UInt8]) -> Int? {
        guard u16(b, 0) == 1, u16(b, 2) == 0,
              let off = u16(b, headerOffset), off > 0, off < b.count else { return nil }
        return off
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int? {
        (o >= 0 && o + 1 < b.count) ? Int(b[o]) << 8 | Int(b[o + 1]) : nil
    }

    /// Unchecked variants for offsets already bounds-validated by the caller.
    private static func u16v(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }
    private static func i16(_ b: [UInt8], _ o: Int) -> Int {
        Int(Int16(bitPattern: UInt16(b[o]) << 8 | UInt16(b[o + 1])))
    }
}
