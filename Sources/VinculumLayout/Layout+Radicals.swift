import Foundation

extension MathLayoutEngine {

    /// `\sqrt[n]{…}` (TeX Rule 11): the radical drawn with the font's √
    /// glyph — size variants (with the shortfall heuristic), then glyph
    /// assembly for very tall radicands — falling back to the hand-stroked
    /// polyline when no delimiter provider is injected (headless/Linux).
    /// The degree is placed by the font's `RadicalKernBefore/AfterDegree`
    /// and 60% bottom-raise in the glyph paths.
    func radicalBox(_ degree: MathNode?, _ radicand: MathNode, size: CGFloat, style: MathStyle) -> MathBox {
        // The radicand is cramped (an exponent under the root rides lower).
        var radicandEngine = self; radicandEngine.cramped = true
        let body = radicandEngine.box(for: radicand, size: size, style: style)
        let ruleThickness = max(1, size * constants.radicalRuleThickness)
        // The font distinguishes display/text radicand clearance (LM Math:
        // 0.148 vs 0.050 em); the old transcription used the display value
        // everywhere.
        var gap = size * (style.isDisplay ? constants.radicalDisplayStyleVerticalGap
                                          : constants.radicalVerticalGap)
        // The degree is typeset in scriptscript style (TeX Rule 11); its
        // forced-style anchor is its own size (a \displaystyle in a degree
        // stays degree-sized).
        var degreeEngine = self
        degreeEngine.styleAnchorSize = size * MathLayout.Radical.degreeScale
        let degreeBox = degree.map { degreeEngine.box(for: $0, size: size * MathLayout.Radical.degreeScale, style: .scriptScript) }

        // Font-glyph paths: a purpose-drawn surd from the MATH table.
        let target = body.ascent + body.descent + gap + ruleThickness
        var sign: (elements: (CGFloat) -> [MathElement], width: CGFloat,
                   ascent: CGFloat, descent: CGFloat)?
        if let shape = delimiters?("√", target, size) {
            let m = shape.metrics
            let excess = (m.ascent + m.descent) - target
            if excess > 0 { gap += excess / 2 }                 // Rule 11's ψ centering
            let glyphTop = body.ascent + gap + ruleThickness
            let baselineY = glyphTop - m.ascent
            sign = ({ x in [.glyph(id: shape.glyphID, size: size,
                                   origin: CGPoint(x: x, y: baselineY),
                                   color: self.colorOverride)] },
                    m.width, glyphTop, max(body.descent, m.descent - baselineY))
        } else if let asm = delimiterAssembly?("√", target, size) {
            let excess = asm.height - target
            if excess > 0 { gap += excess / 2 }
            let glyphTop = body.ascent + gap + ruleThickness
            let columnBottom = glyphTop - asm.height
            sign = ({ x in asm.placements.map {
                        .glyph(id: $0.glyphID, size: size,
                               origin: CGPoint(x: x, y: columnBottom + $0.offset),
                               color: self.colorOverride) } },
                    asm.width, glyphTop, max(body.descent, -columnBottom))
        }

        if let sign {
            let kernBefore = size * constants.radicalKernBeforeDegree
            let kernAfter = size * constants.radicalKernAfterDegree
            let signX = degreeBox.map { max(0, kernBefore + $0.width + kernAfter) } ?? 0
            let bodyX = signX + sign.width
            let glyphTop = sign.ascent
            var ascent = glyphTop + size * constants.radicalExtraAscender
            var elements = sign.elements(signX)
            elements.append(rule(x: bodyX, y: glyphTop - ruleThickness,
                                 width: body.width, height: ruleThickness))
            elements += body.placed(at: CGPoint(x: bodyX, y: 0))
            if let degreeBox {
                // Degree baseline at 60% of the sign's height above its
                // bottom (RadicalDegreeBottomRaisePercent).
                let signHeight = glyphTop + sign.descent
                let degreeY = -sign.descent + constants.radicalDegreeBottomRaisePercent * signHeight
                elements += degreeBox.placed(at: CGPoint(x: kernBefore, y: degreeY))
                ascent = max(ascent, degreeY + degreeBox.ascent)
            }
            return MathBox(width: bodyX + body.width, ascent: ascent,
                           descent: sign.descent, elements: elements)
        }

        // Polyline fallback (no provider injected — headless/Linux).
        let signWidth = size * MathLayout.Radical.signWidth
        let degreeAdvance = degreeBox.map { max(0, $0.width - signWidth * MathLayout.Radical.degreeOverlap) } ?? 0

        let ascent = body.ascent + gap + ruleThickness + size * MathLayout.Radical.extraAscent
        let descent = body.descent
        let width = degreeAdvance + signWidth + body.width + size * MathLayout.Radical.vinculumOverhang

        let signX = degreeAdvance
        let topY = ascent - ruleThickness / 2
        let bottomY = -descent

        var elements: [MathElement] = [stroke([
            .move(CGPoint(x: signX, y: body.height * MathLayout.Radical.tickStartHeight - body.descent)),
            .line(CGPoint(x: signX + signWidth * MathLayout.Radical.shoulderFrac,
                          y: body.height * MathLayout.Radical.notchHeight - body.descent)),
            .line(CGPoint(x: signX + signWidth * MathLayout.Radical.valleyFrac, y: bottomY)),
            .line(CGPoint(x: signX + signWidth, y: topY)),
            .line(CGPoint(x: signX + signWidth + body.width + size * MathLayout.Radical.vinculumOverhang, y: topY)),
        ], width: ruleThickness, cap: .round, join: .miter)]

        elements += body.placed(at: CGPoint(x: signX + signWidth + size * MathLayout.Radical.bodyInset, y: 0))
        if let degreeBox {
            elements += degreeBox.placed(at: CGPoint(x: 0, y: body.height * MathLayout.Radical.degreeRaise - body.descent))
        }
        return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)
    }
}
