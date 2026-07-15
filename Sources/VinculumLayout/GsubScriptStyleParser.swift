import Foundation

/// The OpenType `ssty` (Math Script Style) substitutions parsed from a font's
/// GSUB table. `ssty` maps a base glyph to a purpose-redrawn optical variant
/// for script (level 1) and scriptscript (level 2) sizes — heavier strokes
/// and more open forms so a shrunk glyph keeps the visual weight of the base
/// text instead of thinning out. TeX applies these via the font's design
/// sizes; OpenType math engines apply them via `ssty`.
public struct MathScriptVariants: Sendable, Equatable {
    /// base glyph ID → script (`ssty=1`) variant glyph ID.
    public var script: [UInt16: UInt16]
    /// base glyph ID → scriptscript (`ssty=2`) variant glyph ID.
    public var scriptScript: [UInt16: UInt16]

    public init(script: [UInt16: UInt16] = [:], scriptScript: [UInt16: UInt16] = [:]) {
        self.script = script
        self.scriptScript = scriptScript
    }

    public var isEmpty: Bool { script.isEmpty && scriptScript.isEmpty }

    /// The optical variant for `base` at math-script `level` (1 = script,
    /// 2 = scriptscript), or `nil` if the font supplies none. Level 2 falls
    /// back to the level-1 variant when only one is defined.
    public func variant(for base: UInt16, level: Int) -> UInt16? {
        switch level {
        case 1: return script[base]
        case 2: return scriptScript[base] ?? script[base]
        default: return nil
        }
    }
}

/// Parses just the `ssty` feature out of a raw OpenType GSUB table. Fully
/// bounds-checked: any malformed offset degrades to "no data" (an empty
/// result), never a crash or an out-of-bounds read — the same contract as
/// `MathTableParser`. Only the Alternate-Substitution lookups `ssty`
/// actually uses are read (directly, or wrapped in an Extension lookup).
public enum GsubScriptStyleParser {

    public static func parse(_ b: [UInt8]) -> MathScriptVariants {
        // GSUB header 1.0/1.1: major, minor, scriptList, featureList, lookupList.
        guard u16(b, 0) == 1,
              let featureListOff = u16(b, 6), let lookupListOff = u16(b, 8),
              featureListOff > 0, lookupListOff > 0 else { return MathScriptVariants() }

        // FeatureList → the lookup indices belonging to every `ssty` feature.
        guard let featureCount = u16(b, featureListOff) else { return MathScriptVariants() }
        var sstyLookups: Set<Int> = []
        for i in 0..<min(featureCount, 0x4000) {
            let rec = featureListOff + 2 + 6 * i
            guard rec + 6 <= b.count else { break }
            let tag = b[rec] == 0x73 && b[rec + 1] == 0x73 && b[rec + 2] == 0x74 && b[rec + 3] == 0x79  // "ssty"
            guard tag, let featOff = u16(b, rec + 4), featOff > 0 else { continue }
            let feat = featureListOff + featOff
            guard let lookupCount = u16(b, feat + 2) else { continue }
            for j in 0..<min(lookupCount, 0x4000) {
                if let idx = u16(b, feat + 4 + 2 * j) { sstyLookups.insert(idx) }
            }
        }
        if sstyLookups.isEmpty { return MathScriptVariants() }

        // LookupList → each ssty lookup's Alternate-Substitution subtables.
        guard let lookupTotal = u16(b, lookupListOff) else { return MathScriptVariants() }
        var out = MathScriptVariants()
        for idx in sstyLookups where idx < lookupTotal {
            guard let lookupOff = u16(b, lookupListOff + 2 + 2 * idx) else { continue }
            let lookup = lookupListOff + lookupOff
            guard let type = u16(b, lookup), let subCount = u16(b, lookup + 4) else { continue }
            for s in 0..<min(subCount, 0x4000) {
                guard let subOff = u16(b, lookup + 6 + 2 * s) else { continue }
                readAlternate(b, at: lookup + subOff, lookupType: type, into: &out)
            }
        }
        return out
    }

    /// Reads one Alternate-Substitution subtable (LookupType 3), unwrapping an
    /// Extension subtable (LookupType 7) first if needed.
    private static func readAlternate(_ b: [UInt8], at start: Int, lookupType: Int,
                                      into out: inout MathScriptVariants) {
        var subStart = start
        if lookupType == 7 {
            // ExtensionSubstFormat1: format, extType, Offset32 to the real table.
            guard u16(b, start) == 1, u16(b, start + 2) == 3,
                  let extOff = u32(b, start + 4) else { return }
            subStart = start + extOff
        } else if lookupType != 3 {
            return
        }
        // AlternateSubstFormat1: format, coverageOffset, count, setOffsets[].
        guard u16(b, subStart) == 1,
              let covOff = u16(b, subStart + 2), let count = u16(b, subStart + 4),
              let covered = coverage(b, at: subStart + covOff), covered.count == count else { return }
        for i in 0..<count {
            guard let setOff = u16(b, subStart + 6 + 2 * i) else { continue }
            let set = subStart + setOff
            guard let glyphCount = u16(b, set), glyphCount >= 1,
                  let a0 = u16(b, set + 2) else { continue }
            let base = covered[i]
            out.script[base] = UInt16(a0)                       // alternate[0] = .st
            if glyphCount >= 2, let a1 = u16(b, set + 4) {
                out.scriptScript[base] = UInt16(a1)             // alternate[1] = .sts
            }
        }
    }

    /// OpenType coverage table → glyph IDs in coverage-index order.
    private static func coverage(_ b: [UInt8], at start: Int) -> [UInt16]? {
        guard let format = u16(b, start) else { return nil }
        if format == 1 {
            guard let count = u16(b, start + 2) else { return nil }
            var glyphs: [UInt16] = []; glyphs.reserveCapacity(count)
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
                guard let s = u16(b, rec), let e = u16(b, rec + 2), let si = u16(b, rec + 4),
                      s <= e, byIndex.count + (e - s + 1) <= 0x1_0000 else { return nil }
                for g in s...e { byIndex.append((si + (g - s), UInt16(g))) }
            }
            return byIndex.sorted { $0.index < $1.index }.map(\.glyph)
        }
        return nil
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int? {
        (o >= 0 && o + 1 < b.count) ? Int(b[o]) << 8 | Int(b[o + 1]) : nil
    }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int? {
        (o >= 0 && o + 3 < b.count)
            ? Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]) : nil
    }
}
