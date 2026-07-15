import Foundation

extension MathLayoutEngine {

    /// Accents over a base (`\hat \vec \bar …`), stretchy variants, and the
    /// `\overline`/`\underline` rules (TeX Rule 12).
    ///
    /// Placement is font-true: the accent's x comes from the base's and the
    /// accent's `topAccentAttachment` points (falling back to advance
    /// centers), so `\hat{f}` leans with the letter; its height floors at
    /// the font's `AccentBaseHeight` (δ = min(h, AccentBaseHeight)) so a low
    /// base keeps the accent at its design height, while a tall base pushes
    /// it up ink-to-ink. `scripts` carries a promoted sub/superscript from a
    /// single-character accentee (`\hat{f}^2` puts the ² on the f).
    func accentBox(_ base: MathNode, accent: MathAccent, size: CGFloat, style: MathStyle,
                   scripts: (sub: MathNode?, sup: MathNode?)? = nil) -> MathBox {
        let coreBox = box(for: base, size: size, style: style)
        let baseBox: MathBox
        if let scripts {
            baseBox = scriptsBox(base, sub: scripts.sub, sup: scripts.sup, size: size, style: style)
        } else {
            baseBox = coreBox
        }
        // Drawn rules: \overline above, \underline below — each with ITS
        // OWN font constants (they coincide in LM Math but not necessarily
        // in other fonts; the underbar set was parsed-but-unread before).
        if accent == .overline || accent == .underline {
            let over = accent == .overline
            let ruleThickness = max(1, size * (over ? constants.overbarRuleThickness
                                                    : constants.underbarRuleThickness))
            let gap = size * (over ? constants.overbarVerticalGap
                                   : constants.underbarVerticalGap)
            let ascent = baseBox.ascent + (over ? gap + ruleThickness : 0)
            let descent = baseBox.descent + (over ? 0 : gap + ruleThickness)
            var elements = baseBox.elements
            let y = over ? baseBox.ascent + gap : -baseBox.descent - gap - ruleThickness
            elements.append(rule(x: 0, y: y, width: baseBox.width, height: ruleThickness))
            return MathBox(width: baseBox.width, ascent: ascent, descent: descent, elements: elements)
        }

        guard let rawGlyph = accent.glyph else { return baseBox }
        let clearance = size * MathLayout.Accent.clearance
        let baseAttach = glyphTypography(of: base, size: size)?.topAccentAttachment
            ?? coreBox.width / 2
        // Vertical: hug the ink, but never sink below the font's designed
        // accent seat (AccentBaseHeight ≈ x-height).
        let seat = max(baseBox.inkAscent, size * constants.accentBaseHeight)

        // The glyph-ID path serves two accent families the string path
        // can't: stretchy accents walking the font's HORIZONTAL width
        // variants (TeX Rule 12's successor walk — widest drawn cut not
        // exceeding the accentee), and combining-only accents like \vec,
        // whose lone mark a text engine seats unpredictably when drawn as a
        // string. Target width 0 for the latter: the design-size cut.
        let markGlyph = accent.isStretchy ? accent.stretchyGlyph : accent.combiningGlyph
        if let markGlyph,
           let shape = accentVariants?(markGlyph, accent.isStretchy ? coreBox.width : 0, size) {
            let m = shape.metrics
            let accentBaselineY = seat + clearance - m.inkDescent
            let ascent = max(baseBox.ascent, accentBaselineY + m.inkAscent)
            var elements = baseBox.elements
            // Center the variant's INK on the attachment point (combining
            // marks draw behind their origin — inkLeft locates the ink).
            let x = baseAttach - (m.inkLeft + m.width / 2)
            elements.append(.glyph(id: shape.glyphID, size: size,
                                   origin: CGPoint(x: x, y: accentBaselineY),
                                   color: colorOverride))
            return MathBox(width: baseBox.width, ascent: ascent, descent: baseBox.descent,
                           inkAscent: baseBox.inkAscent, elements: elements)
        }

        // Scaling path: stretchy accents scale toward the CHAR width
        // (scripts don't widen the accent); point accents keep natural size.
        let accentSize = accent.isStretchy
            ? min(size * MathLayout.Accent.stretchyMax,
                  max(size * MathLayout.Accent.stretchyMin, coreBox.width * MathLayout.Accent.stretchyTarget))
            : size * MathLayout.Accent.pointScale
        let glyph = Self.mathVariant(rawGlyph, italic: false, bold: false)
        let m = measure(glyph, accentSize, false)

        // Horizontal: attachment-point skew (strictly better than TeX's
        // \skewchar — the font states where each glyph's accent belongs).
        let accentAttach = typography?(glyph, accentSize)?.topAccentAttachment
            ?? m.width / 2
        let accentX = baseAttach - accentAttach

        let accentBaselineY = seat + clearance - m.inkDescent
        let ascent = max(baseBox.ascent, accentBaselineY + m.inkAscent)

        var elements = baseBox.elements
        elements.append(.glyphs(text: glyph, size: accentSize, mono: false,
                                origin: CGPoint(x: accentX, y: accentBaselineY),
                                color: colorOverride))
        return MathBox(width: baseBox.width, ascent: ascent, descent: baseBox.descent,
                       inkAscent: baseBox.inkAscent, elements: elements)
    }
}
