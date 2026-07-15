import Foundation

extension MathLayoutEngine {

    /// Sub/superscripts. In display style a big operator takes its scripts as
    /// stacked limits (∑ᵢ₌₁ⁿ), like TeX's `\limits`; otherwise they sit to the
    /// right of the base.
    func scriptsBox(_ base: MathNode, sub: MathNode?, sup: MathNode?,
                    size: CGFloat, style: MathStyle) -> MathBox {
        if style.isDisplay, takesDisplayLimits(base) {
            // Symbol operators (∑, ∏) enlarge; named ones (lim, max) stay text-size.
            let enlarge: Bool
            if case .symbol(_, .largeOperator, _) = base { enlarge = true } else { enlarge = false }
            return limitsBox(base, sub: sub, sup: sup, size: size, style: style, enlarge: enlarge)
        }
        let baseBox = box(for: base, size: size, style: style)
        // Descend one script level: 70% from text, but only down to the 50%
        // scriptscript floor from there (TeX sizes, not compounding shrink).
        let scriptSize = size * style.scriptSizeRatio(constants)
        // A superscript is uncramped; a subscript is cramped (TeX sup_style /
        // sub_style), so nested exponents inside a subscript ride lower.
        var supEngine = self; supEngine.cramped = false
        var subEngine = self; subEngine.cramped = true
        let supBox = sup.map { supEngine.box(for: $0, size: scriptSize, style: style.scriptStyle) }
        let subBox = sub.map { subEngine.box(for: $0, size: scriptSize, style: style.scriptStyle) }

        // Per-glyph typography of a glyph-run base: the italic correction δ
        // separates the superscript from the subscript (Rules 17/18f), the
        // kern staircases tuck scripts into the glyph's corners.
        let typo = glyphTypography(of: base, size: size)
        let delta = typo?.italicsCorrection ?? 0
        let isGlyphBase: Bool = {
            switch base { case .symbol, .functionName: return true; default: return false }
        }()

        // 18a — nominal shifts. Character bases start from the style's shift
        // constants; boxy bases (fractions, fenced groups) hang the scripts
        // off their edges via the baseline-drop constants (u = h − q·script,
        // v = d + r·script). The ink floors keep an exponent above (…)²'s
        // paren regardless.
        var supRaise = size * (cramped ? constants.superscriptShiftUpCramped
                                       : constants.superscriptShiftUp)
        var subDrop = size * constants.subscriptShiftDown
        if !isGlyphBase {
            supRaise = max(supRaise, baseBox.ascent - scriptSize * constants.superscriptBaselineDropMax)
            subDrop = max(subDrop, baseBox.descent + scriptSize * constants.subscriptBaselineDropMin)
        }
        supRaise = max(supRaise, baseBox.inkAscent - scriptSize * 0.25)
        subDrop = max(subDrop, baseBox.descent + scriptSize * 0.15)

        // 18b/18c — the font's clamps: a superscript's bottom stays above
        // SuperscriptBottomMin; a lone subscript's top below SubscriptTopMax.
        if let supBox {
            supRaise = max(supRaise, supBox.descent + size * constants.superscriptBottomMin)
        }
        if let subBox, supBox == nil {
            subDrop = max(subDrop, subBox.ascent - size * constants.subscriptTopMax)
        }

        // 18d/18e — coexisting scripts: open the gap to SubSuperscriptGapMin
        // by dropping the subscript, then if the superscript's bottom sank
        // below its floor, shift the pair up together.
        if let supBox, let subBox {
            let gapMin = size * constants.subSuperscriptGapMin
            let gap = (supRaise - supBox.descent) - (subBox.ascent - subDrop)
            if gap < gapMin {
                subDrop += gapMin - gap
                let bottomMin = size * constants.superscriptBottomMaxWithSubscript
                let deficit = bottomMin - (supRaise - supBox.descent)
                if deficit > 0 { supRaise += deficit; subDrop -= deficit }
            }
        }

        // Cut-in kerns: sample each staircase at the script's near edge.
        var supKern: CGFloat = 0, subKern: CGFloat = 0
        if let supBox, let stair = typo?.kernTopRight {
            supKern = stair.kern(atHeight: supRaise - supBox.descent)
        }
        if let subBox, let stair = typo?.kernBottomRight {
            subKern = stair.kern(atHeight: subBox.ascent - subDrop)
        }

        // 18f — horizontal split: on a large operator the subscript tucks
        // LEFT under the overhang (∫'s δ is big); elsewhere the superscript
        // moves right by δ. The \scriptspace analog trails the scripts.
        let isLargeOp: Bool = {
            if case .symbol(_, .largeOperator, _) = base { return true }; return false
        }()
        let supX = baseBox.width + (isLargeOp ? 0 : delta) + supKern
        // Clamped: a huge δ or negative kern must not push the subscript
        // left of the box origin (the row would misreport the overhang).
        let subX = max(0, baseBox.width - (isLargeOp ? delta : 0) + subKern)
        var width = baseBox.width
        var ascent = baseBox.ascent
        var descent = baseBox.descent
        if let supBox {
            width = max(width, supX + supBox.width)
            ascent = max(ascent, supRaise + supBox.ascent)
        }
        if let subBox {
            width = max(width, subX + subBox.width)
            descent = max(descent, subDrop + subBox.descent)
        }
        width += size * constants.spaceAfterScript

        var elements = baseBox.elements
        if let supBox { elements += supBox.placed(at: CGPoint(x: supX, y: supRaise)) }
        if let subBox { elements += subBox.placed(at: CGPoint(x: subX, y: -subDrop)) }
        return MathBox(width: width, ascent: ascent, descent: descent,
                       inkAscent: baseBox.inkAscent, elements: elements)
    }

    /// ∑/∫-style stacked limits: the operator enlarged, superscript centered
    /// above, subscript centered below.
    func limitsBox(_ base: MathNode, sub: MathNode?, sup: MathNode?,
                   size: CGFloat, style: MathStyle, enlarge: Bool) -> MathBox {
        // The operator body: the font's display-size variant when available
        // (axis-centered), else the scaled fallback laid out in text style
        // so it can't recurse into limits.
        var opBox: MathBox?
        if enlarge, case .symbol(let glyph, .largeOperator, _) = base {
            opBox = largeOperatorBox(glyph, size: size)
        }
        let op = opBox ?? box(for: base, size: enlarge ? size * MathLayout.displayOperatorScale : size,
                              style: .text)
        let scriptSize = size * style.scriptSizeRatio(constants)
        let supBox = sup.map { box(for: $0, size: scriptSize, style: style.scriptStyle) }
        let subBox = sub.map { box(for: $0, size: scriptSize, style: style.scriptStyle) }
        // TeX Rule 13a: limit clearance is the font's gap minimum, or as
        // much more as the baseline rise/drop minimums demand.
        let upperGap = supBox.map { max(size * constants.upperLimitGapMin,
                                        size * constants.upperLimitBaselineRiseMin - $0.descent) } ?? 0
        let lowerGap = subBox.map { max(size * constants.lowerLimitGapMin,
                                        size * constants.lowerLimitBaselineDropMin - $0.ascent) } ?? 0

        let width = max(op.width, supBox?.width ?? 0, subBox?.width ?? 0)
        var ascent = op.ascent
        var descent = op.descent
        if let supBox { ascent += upperGap + supBox.height }
        if let subBox { descent += lowerGap + subBox.height }

        // TeX Rule 13a: the upper limit shifts right by δ/2 (half the italic
        // correction), the lower limit left by δ/2, hugging the slant.
        let delta = glyphTypography(of: base, size: size)?.italicsCorrection ?? 0
        var elements = op.placed(at: CGPoint(x: (width - op.width) / 2, y: 0))
        if let supBox {
            elements += supBox.placed(at: CGPoint(x: (width - supBox.width) / 2 + delta / 2,
                                                  y: op.ascent + upperGap + supBox.descent))
        }
        if let subBox {
            elements += subBox.placed(at: CGPoint(x: (width - subBox.width) / 2 - delta / 2,
                                                  y: -op.descent - lowerGap - subBox.ascent))
        }
        return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)
    }

    // Integral-family glyphs default to \nolimits in TeX: their scripts stay to
    // the side even in display style (∫₀¹, not a stacked lower/upper limit).
    private static let integralGlyphs: Set<Character> = ["∫", "∬", "∭", "⨌", "∮", "∯", "∰", "∱", "∲", "∳"]
    // Named operators that DO take stacked limits (unlike \sin, \log, \cos …).
    private static let limitFunctionNames: Set<String> = [
        "lim", "max", "min", "sup", "inf", "det", "gcd", "Pr",
        "limsup", "liminf", "injlim", "projlim",
        "varinjlim", "varprojlim", "varliminf", "varlimsup", "argmax", "argmin"]

    /// Whether an operator stacks its scripts as over/under limits in display
    /// style. Symbol operators do (∑, ∏, ⋃) except integrals; among the upright
    /// function names, only the lim/max family does.
    func takesDisplayLimits(_ base: MathNode) -> Bool {
        switch base {
        case let .symbol(glyph, .largeOperator, _):
            return !(glyph.count == 1 && Self.integralGlyphs.contains(glyph[glyph.startIndex]))
        case let .functionName(name):
            return Self.limitFunctionNames.contains(name)
        case .limitsOperator:
            return true                       // \operatorname* always stacks
        case let .classified(_, cls):
            return cls == .largeOperator      // \mathop takes limits
        default:
            return false
        }
    }
}
