import Foundation

// OpenType MATH glyph assembly — building arbitrarily-tall (or
// -wide) glyphs from font-drawn parts (end caps + repeatable extenders)
// joined at connector overlaps, at constant stroke weight. The types and
// solver are pure geometry: platform-free, fixture-testable on Linux.

/// One `GlyphAssembly` from the MATH table: the ordered part list (bottom→top
/// for vertical assemblies, left→right for horizontal) with connector
/// lengths, in em fractions.
public struct MathGlyphAssembly: Sendable, Equatable {
    public struct Part: Sendable, Equatable {
        public let glyphID: UInt16
        public let startConnector: CGFloat
        public let endConnector: CGFloat
        public let fullAdvance: CGFloat
        public let isExtender: Bool
        public init(glyphID: UInt16, startConnector: CGFloat, endConnector: CGFloat,
                    fullAdvance: CGFloat, isExtender: Bool) {
            self.glyphID = glyphID
            self.startConnector = startConnector
            self.endConnector = endConnector
            self.fullAdvance = fullAdvance
            self.isExtender = isExtender
        }
    }
    public let italicsCorrection: CGFloat
    public let parts: [Part]
    public init(italicsCorrection: CGFloat, parts: [Part]) {
        self.italicsCorrection = italicsCorrection
        self.parts = parts
    }
}

/// The parsed `MathVariants` sub-table: discrete size-variant ladders and
/// (where the font provides one) the extensible assembly, per base glyph.
/// `package`: served to layout through the delimiter/accent provider seams.
package struct MathVariantsData: Sendable {
    public struct Variant: Sendable, Equatable {
        public let glyphID: UInt16
        public let advance: CGFloat   // em; the glyph's extent along the stretch axis
        public init(glyphID: UInt16, advance: CGFloat) {
            self.glyphID = glyphID; self.advance = advance
        }
    }
    public struct Construction: Sendable {
        public let variants: [Variant]
        public let assembly: MathGlyphAssembly?
        public init(variants: [Variant], assembly: MathGlyphAssembly?) {
            self.variants = variants; self.assembly = assembly
        }

        /// The smallest variant reaching `target` (em) — with the shortfall
        /// heuristic: when the fitting variant is a big jump up (≥1.3×) and
        /// the previous one misses by ≤3%, prefer the smaller cut so a
        /// radical hugs its radicand instead of towering over it.
        public func bestVariant(forTarget target: CGFloat) -> Variant? {
            var previous: Variant?
            for v in variants {
                if v.advance >= target {
                    if let p = previous, v.advance >= p.advance * 1.3,
                       p.advance >= target * 0.97 {
                        return p
                    }
                    return v
                }
                previous = v
            }
            return nil
        }
    }
    public let minConnectorOverlap: CGFloat
    public let vertical: [UInt16: Construction]
    public let horizontal: [UInt16: Construction]
    public init(minConnectorOverlap: CGFloat,
                vertical: [UInt16: Construction], horizontal: [UInt16: Construction]) {
        self.minConnectorOverlap = minConnectorOverlap
        self.vertical = vertical
        self.horizontal = horizontal
    }
}

/// An assembled tall delimiter ready to draw: per-part baseline draw
/// offsets from the column bottom (points), plus overall extent.
public struct DelimiterAssembly: Sendable {
    public let placements: [MathAssemblySolver.Placement]
    public let width: CGFloat
    public let height: CGFloat
    public init(placements: [MathAssemblySolver.Placement], width: CGFloat, height: CGFloat) {
        self.placements = placements
        self.width = width
        self.height = height
    }
}

/// Injected MATH-table glyph assembly: given a base delimiter glyph and a
/// minimum height (points) at `size`, returns an assembled column of font
/// parts reaching it, or nil (no assembly in the font → caller scales).
public typealias MathDelimiterAssemblyProvider =
    @Sendable (_ baseGlyph: String, _ minHeight: CGFloat, _ size: CGFloat) -> DelimiterAssembly?

/// Solves part placement for a target extent: fewest extender repeats whose
/// reachable range covers the target, joints opened equally from maximal
/// overlap to land on it exactly (the HarfBuzz algorithm).
public enum MathAssemblySolver {

    public struct Placement: Sendable, Equatable {
        public let glyphID: UInt16
        /// Offset of the part's start edge from the column start, along the
        /// stretch axis, in the same unit as the part data.
        public let offset: CGFloat
        public init(glyphID: UInt16, offset: CGFloat) {
            self.glyphID = glyphID; self.offset = offset
        }
    }

    /// Returns part placements reaching at least `target` (overshoot allowed
    /// when the caps alone exceed it), or the tallest achievable column if
    /// `maxExtenderRepeats` still falls short, or nil for degenerate data.
    public static func solve(_ assembly: MathGlyphAssembly, minOverlap: CGFloat,
                             target: CGFloat, maxExtenderRepeats: Int = 32)
        -> (placements: [Placement], total: CGFloat)? {
        let parts = assembly.parts
        guard !parts.isEmpty,
              !parts.contains(where: { $0.isExtender && $0.fullAdvance <= 0 }) else { return nil }

        var best: (placements: [Placement], total: CGFloat)?
        for repeats in 0...maxExtenderRepeats {
            var seq: [MathGlyphAssembly.Part] = []
            for p in parts {
                if p.isExtender {
                    seq.append(contentsOf: Array(repeating: p, count: repeats))
                } else {
                    seq.append(p)
                }
            }
            guard !seq.isEmpty else { continue }

            // Joint overlap bounds: at least minOverlap, at most what both
            // connectors allow (tolerating fonts whose connectors are shorter
            // than the minimum).
            var lo: [CGFloat] = [], hi: [CGFloat] = []
            for i in 1..<seq.count {
                let cap = min(seq[i - 1].endConnector, seq[i].startConnector)
                lo.append(minOverlap)
                hi.append(max(minOverlap, cap))
            }
            let sumFull = seq.reduce(0) { $0 + $1.fullAdvance }
            let minTotal = sumFull - hi.reduce(0, +)
            let maxTotal = sumFull - lo.reduce(0, +)

            func build(overlaps: [CGFloat]) -> (placements: [Placement], total: CGFloat) {
                var placements = [Placement(glyphID: seq[0].glyphID, offset: 0)]
                var offset: CGFloat = 0
                for i in 1..<seq.count {
                    offset += seq[i - 1].fullAdvance - overlaps[i - 1]
                    placements.append(Placement(glyphID: seq[i].glyphID, offset: offset))
                }
                return (placements, offset + (seq.last?.fullAdvance ?? 0))
            }

            if minTotal >= target {
                return build(overlaps: hi)      // caps alone reach it; tightest column
            }
            if maxTotal >= target {
                // Open every joint by the same fraction of its slack.
                let capacity = maxTotal - minTotal
                let t = capacity > 0 ? (target - minTotal) / capacity : 0
                let overlaps = zip(lo, hi).map { l, h in h - t * (h - l) }
                return build(overlaps: overlaps)
            }
            best = build(overlaps: lo)          // tallest at this repeat count
        }
        return best
    }
}
