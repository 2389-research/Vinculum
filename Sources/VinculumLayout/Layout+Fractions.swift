import Foundation

extension MathLayoutEngine {

    /// `\frac`: numerator over denominator, separated by a rule. It is exactly
    /// a ruled `genfrac` with no fences — one stacking implementation, kept DRY.
    func fractionBox(_ numerator: MathNode, _ denominator: MathNode,
                     size: CGFloat, style: MathStyle) -> MathBox {
        genfracBox(numerator, denominator, hasRule: true, left: "", right: "",
                   size: size, style: style)
    }

    /// `\cfrac`: a continued fraction. Parts are laid out at FULL display size
    /// (so nesting doesn't shrink) with the denominator aligned; the numerator
    /// is always centered.
    func cfracBox(_ num: MathNode, _ den: MathNode, align: CfracAlign, size: CGFloat) -> MathBox {
        var numEngine = self; numEngine.cramped = false
        var denEngine = self; denEngine.cramped = true
        let topBox = numEngine.box(for: num, size: size, style: .display)    // full size + display
        let bottomBox = denEngine.box(for: den, size: size, style: .display)

        let ruleThickness = max(1, size * constants.fractionRuleThickness)
        let axis = size * constants.axisHeight
        let width = max(topBox.width, bottomBox.width) + size * MathLayout.Fraction.sidePadding
        var shiftUp = size * constants.fractionNumeratorDisplayStyleShiftUp
        var shiftDown = size * constants.fractionDenominatorDisplayStyleShiftDown
        let numGapMin = size * constants.fractionNumeratorDisplayStyleGapMin
        let denGapMin = size * constants.fractionDenominatorDisplayStyleGapMin
        let numClear = (shiftUp - topBox.descent) - (axis + ruleThickness / 2)
        if numClear < numGapMin { shiftUp += numGapMin - numClear }
        let denClear = (axis - ruleThickness / 2) - (bottomBox.ascent - shiftDown)
        if denClear < denGapMin { shiftDown += denGapMin - denClear }

        let inset = size * MathLayout.Fraction.ruleInset
        func placeX(_ b: MathBox, _ a: CfracAlign) -> CGFloat {
            switch a {
            case .center: return (width - b.width) / 2
            case .left:   return inset
            case .right:  return width - b.width - inset
            }
        }
        var elements: [MathElement] = [rule(x: inset, y: axis - ruleThickness / 2,
                                            width: width - inset * 2, height: ruleThickness)]
        elements += topBox.placed(at: CGPoint(x: placeX(topBox, .center), y: shiftUp))
        elements += bottomBox.placed(at: CGPoint(x: placeX(bottomBox, align), y: -shiftDown))
        return MathBox(width: width, ascent: shiftUp + topBox.ascent,
                       descent: shiftDown + bottomBox.descent, elements: elements)
    }

    /// `\binom` and ruleless stacks: numerator over denominator with an
    /// optional rule and optional enclosing fences.
    func genfracBox(_ top: MathNode, _ bottom: MathNode, hasRule: Bool,
                    left: String, right: String, size: CGFloat, style: MathStyle) -> MathBox {
        let partSize = size * (style.isDisplay ? MathLayout.Fraction.partScaleDisplay
                                               : MathLayout.Fraction.partScaleText)
        // Numerator uncramped, denominator cramped (TeX num_style / denom_style)
        // — so an exponent in the denominator rides lower than in the numerator.
        // The part scale moves the forced-style anchor with it (a
        // \displaystyle inside returns to the PART's full size).
        var numEngine = self; numEngine.cramped = false; numEngine.styleAnchorSize = partSize
        var denEngine = self; denEngine.cramped = true; denEngine.styleAnchorSize = partSize
        let topBox = numEngine.box(for: top, size: partSize, style: style.fractionStyle)
        let bottomBox = denEngine.box(for: bottom, size: partSize, style: style.fractionStyle)

        let ruleThickness = hasRule ? max(1, size * constants.fractionRuleThickness) : 0
        let axis = size * constants.axisHeight
        let width = max(topBox.width, bottomBox.width) + size * MathLayout.Fraction.sidePadding

        // TeX shift-model (Appendix G Rule 15): position each part by the
        // font's NOMINAL baseline shift for the style — fraction constants
        // with a rule (15d), stack constants without (15c) — so a short `1`
        // and a deep numerator share the same baseline, then increase the
        // shift only as needed to keep the font's minimum clearance.
        var shiftUp = size * (hasRule
            ? (style.isDisplay ? constants.fractionNumeratorDisplayStyleShiftUp
                               : constants.fractionNumeratorShiftUp)
            : (style.isDisplay ? constants.stackTopDisplayStyleShiftUp
                               : constants.stackTopShiftUp))
        var shiftDown = size * (hasRule
            ? (style.isDisplay ? constants.fractionDenominatorDisplayStyleShiftDown
                               : constants.fractionDenominatorShiftDown)
            : (style.isDisplay ? constants.stackBottomDisplayStyleShiftDown
                               : constants.stackBottomShiftDown))
        if hasRule {
            let numGapMin = size * (style.isDisplay ? constants.fractionNumeratorDisplayStyleGapMin
                                                    : constants.fractionNumeratorGapMin)
            let denGapMin = size * (style.isDisplay ? constants.fractionDenominatorDisplayStyleGapMin
                                                    : constants.fractionDenominatorGapMin)
            let numClear = (shiftUp - topBox.descent) - (axis + ruleThickness / 2)
            if numClear < numGapMin { shiftUp += numGapMin - numClear }
            let denClear = (axis - ruleThickness / 2) - (bottomBox.ascent - shiftDown)
            if denClear < denGapMin { shiftDown += denGapMin - denClear }
        } else {
            let minGap = size * (style.isDisplay ? constants.stackDisplayStyleGapMin
                                                 : constants.stackGapMin)
            let gap = (shiftUp - topBox.descent) - (bottomBox.ascent - shiftDown)
            if gap < minGap { let d = (minGap - gap) / 2; shiftUp += d; shiftDown += d }
        }

        let ascent = shiftUp + topBox.ascent
        let descent = shiftDown + bottomBox.descent

        var elements: [MathElement] = []
        if hasRule {
            elements.append(rule(x: size * MathLayout.Fraction.ruleInset, y: axis - ruleThickness / 2,
                                 width: width - size * MathLayout.Fraction.ruleInset * 2, height: ruleThickness))
        }
        elements += topBox.placed(at: CGPoint(x: (width - topBox.width) / 2, y: shiftUp))
        elements += bottomBox.placed(at: CGPoint(x: (width - bottomBox.width) / 2, y: -shiftDown))
        let stack = MathBox(width: width, ascent: ascent, descent: descent, elements: elements)

        guard !left.isEmpty || !right.isEmpty else { return stack }
        return delimitedBoxAround(stack, left: left, right: right, size: size)
    }
}
