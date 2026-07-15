import Foundation

/// Inter-atom spacing, in *math units* (`mu` = 1/18 em) — the unit Knuth
/// defines in Chapter 18 of *The TeXbook*. TeX never spaces atoms with a raw
/// length; it uses `\thinmuskip` (3mu), `\medmuskip` (4mu), `\thickmuskip`
/// (5mu), selected by the atom-class pair table (TeXbook p. 170). Expressed
/// as em fractions so a builder multiplies by the current size.
package enum MathSpacing {
    /// 3mu — Ord↔Op and after Punct.
    public static let thin: CGFloat = 3.0 / 18.0
    /// 4mu — around Bin (binary operators).
    public static let medium: CGFloat = 4.0 / 18.0
    /// 5mu — around Rel (relations).
    public static let thick: CGFloat = 5.0 / 18.0
}

/// Layout and drawing proportions that are Vinculum's own — the parts TeX
/// delegates to *font glyphs* (the radical hook, the brace, the arrowhead)
/// or to the *style lattice* (D→T→S→SS shrink) rather than to a numbered
/// `\fontdimen`. There is no OpenType MATH constant for these, so we name and
/// document them here instead of leaving bare literals. Everything that DOES
/// have a font parameter lives in `MathConstants` and is read from there.
package enum MathLayout {
    /// Unsupported source drawn in mono, one notch down from the run size.
    public static let unsupportedSourceScale: CGFloat = 0.85
    /// Big operator (∑, ∫) enlargement when it takes stacked limits. TeX
    /// swaps in the display-size glyph from family 3; we scale instead.
    public static let displayOperatorScale: CGFloat = 1.35
    /// General vertical clearance for over/under-set material (`\overset`,
    /// brace/arrow labels). Not a single `\fontdimen`; TeX derives it from the
    /// big-op spacing family — Vinculum uses one tuned clearance.
    public static let overUnderGap: CGFloat = 0.08

    /// `\frac` / `\genfrac`: numerator & denominator shrink. TeX's style
    /// lattice would use textstyle (1.0) in display and scriptstyle (0.70) in
    /// text; Vinculum uses a gentler ramp for on-screen legibility.
    public enum Fraction {
        public static let partScaleDisplay: CGFloat = 0.9
        public static let partScaleText: CGFloat = 0.8
        /// Horizontal breathing room added to the wider part, and the rule's
        /// inset from each edge (half on each side).
        public static let sidePadding: CGFloat = 0.24
        public static let ruleInset: CGFloat = 0.04
    }

    /// `\sqrt[n]{…}`: the hand-stroked sign is drawn as a polyline, so its
    /// vertices are fractions of the sign width / body height, not font metrics.
    public enum Radical {
        public static let signWidth: CGFloat = 0.55
        public static let degreeScale: CGFloat = 0.6
        /// How far the degree box tucks back over the sign's shoulder.
        public static let degreeOverlap: CGFloat = 0.35
        public static let degreeRaise: CGFloat = 0.45     // × body height
        /// Sign polyline vertices, as fractions of body height / sign width.
        public static let tickStartHeight: CGFloat = 0.25 // × body height
        public static let notchHeight: CGFloat = 0.12     // × body height
        public static let shoulderFrac: CGFloat = 0.3     // × sign width
        public static let valleyFrac: CGFloat = 0.55      // × sign width
        /// Space between the sign and the radicand, and extra ascent above
        /// the vinculum, and the vinculum overhang past the radicand.
        public static let bodyInset: CGFloat = 0.06
        public static let extraAscent: CGFloat = 0.06
        public static let vinculumOverhang: CGFloat = 0.12
    }

    /// Accents (`\hat \vec …`): point accents keep near-natural size; stretchy
    /// ones (`\widehat`) grow toward the base width, clamped.
    public enum Accent {
        public static let pointScale: CGFloat = 0.9
        public static let stretchyMax: CGFloat = 1.6      // × size
        public static let stretchyMin: CGFloat = 0.7      // × size
        public static let stretchyTarget: CGFloat = 0.9   // × base width
        /// Ink-to-ink clearance between accent bottom and base top.
        public static let clearance: CGFloat = 0.02
    }

    /// `\xrightarrow`/`\xleftarrow`: a stretchy rule + drawn head sized to fit
    /// its annotations.
    public enum Arrow {
        public static let minWidth: CGFloat = 1.4         // × size
        public static let labelPadding: CGFloat = 0.5     // added to label width
        public static let headLength: CGFloat = 0.28
    }

    /// `\overbrace`/`\underbrace`: a curly brace as four quadratic arcs with a
    /// center notch (same hand-stroked philosophy as the radical).
    public enum Brace {
        public static let height: CGFloat = 0.22
        public static let thicknessFrac: CGFloat = 0.18   // × brace height
        /// Arc anchor/control x-positions, as fractions of the span width.
        public static let leftArcEnd: CGFloat = 0.25
        public static let leftArcControl: CGFloat = 0.18
        public static let leftNotchControl: CGFloat = 0.32
        public static let rightArcEnd: CGFloat = 0.75
        public static let rightNotchControl: CGFloat = 0.68
        public static let rightArcControl: CGFloat = 0.82
    }

    /// `\boxed`: padding between content and frame.
    public enum Box {
        public static let padding: CGFloat = 0.18
    }

    /// Fences (`\left…\right`) and matrix/environment grids.
    public enum Grid {
        /// Extra width and body offset when fencing a pre-laid-out grid.
        public static let fencePadding: CGFloat = 0.1
        public static let fenceInset: CGFloat = 0.05
        public static let matrixRowGap: CGFloat = 0.35
        public static let substackRowGap: CGFloat = 0.18
        public static let alignedColGap: CGFloat = 0.16
        public static let matrixColGap: CGFloat = 0.7
        /// Half-height reserved for an empty row (e.g. a blank `\\` line).
        public static let emptyRowAscent: CGFloat = 0.5
        public static let emptyRowDescent: CGFloat = 0.2
    }
}
