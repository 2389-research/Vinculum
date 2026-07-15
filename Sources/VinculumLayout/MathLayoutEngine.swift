import Foundation

/// Lays a `MathNode` tree out into a platform-free `MathScene`. Geometry only:
/// it measures glyphs through the injected `MathTextMeasurer` and emits
/// positioned primitives, so it runs headless (and on Linux). The per-domain
/// builders live in `Layout+*.swift` extensions; this file is the entry point,
/// the node dispatch, glyph boxes, and TeX inter-atom spacing.
public struct MathLayoutEngine: Sendable {

    let measure: MathTextMeasurer
    /// Optional MATH-table delimiter variant provider; `nil` → continuous
    /// glyph scaling (the platform-free / headless default).
    let delimiters: MathDelimiterProvider?
    /// Optional MATH-table glyph assembly for heights beyond the largest
    /// size variant; `nil` → fall through to scaling.
    let delimiterAssembly: MathDelimiterAssemblyProvider?
    /// Optional MATH-table horizontal accent variants (wide hats/tildes);
    /// `nil` → scale the spacing accent glyph.
    let accentVariants: MathAccentVariantProvider?
    let baseSize: CGFloat
    /// The font's MATH-table constants. Defaults to Latin Modern Math's
    /// values (`.latinModern`) so headless hosts need no font; the renderer
    /// passes constants parsed from the live font (`MathTableParser`).
    let constants: MathFontConstants
    /// Optional per-glyph typography (italic correction, accent attachment,
    /// cut-in kerns); `nil` → neutral defaults (headless default).
    let typography: MathGlyphTypographyProvider?
    /// Optional `ssty` optical-script variants; `nil` → the base glyph is
    /// scaled (headless default), as before.
    let scriptVariants: MathScriptVariantProvider?
    /// The active `\color` override for the current subtree; `nil` primitives
    /// take the renderer's theme ink.
    var colorOverride: MathColor?
    /// TeX "cramped" style: set under a radical, in a denominator, and on a
    /// subscript. In cramped style superscripts are shifted up less, so an
    /// exponent inside √(x²) or a denominator rides lower. Propagated by
    /// sub-context copies of the engine, like `colorOverride`.
    var cramped = false
    /// The size the current material would have at TEXT/DISPLAY style — the
    /// anchor a FORCED style (`\displaystyle` et al.) scales from. Fraction
    /// parts, radical degrees, and substacks move the anchor with their own
    /// part scales, so `\displaystyle` inside a text fraction returns to the
    /// fraction's full size and can never overshoot the surrounding text
    /// (an expert-review layout bug: 0.8·s × 1/0.7 ≈ 1.14·s). Set at init;
    /// propagated by sub-context copies, like `cramped`.
    var styleAnchorSize: CGFloat = 0

    /// When true, every laid-out subtree also emits a `.region` element —
    /// the hit-testing substrate (`MathScene.hitTest`). Off by default:
    /// plain rendering shouldn't pay for metadata it never reads.
    let collectHitRegions: Bool

    /// The primary initializer: a services bundle plus the base size.
    public init(services: MathFontServices, baseSize: CGFloat,
                collectHitRegions: Bool = false) {
        self.collectHitRegions = collectHitRegions
        self.measure = services.measure
        self.delimiters = services.delimiters
        self.delimiterAssembly = services.delimiterAssembly
        self.accentVariants = services.accentVariants
        self.baseSize = baseSize
        self.constants = services.constants
        self.typography = services.typography
        self.scriptVariants = services.scriptVariants
        self.colorOverride = nil
        self.styleAnchorSize = baseSize
    }

    /// Headless convenience: measurement only, Latin Modern preset
    /// constants, no per-glyph refinements (they all degrade gracefully).
    public init(measure: @escaping MathTextMeasurer, baseSize: CGFloat,
                collectHitRegions: Bool = false) {
        self.init(services: MathFontServices(measure: measure), baseSize: baseSize,
                  collectHitRegions: collectHitRegions)
    }

    /// Per-glyph typography of a node that renders as a single glyph run —
    /// the italic correction and kern data scripts attach against. Composite
    /// nodes (fractions, fenced bodies…) have none; transparents unwrap.
    func glyphTypography(of node: MathNode, size: CGFloat) -> GlyphTypography? {
        guard let typography else { return nil }
        switch node {
        case .symbol(let glyph, _, let style):
            let rendered = Self.mathVariant(glyph, italic: style == .italic, bold: style == .bold)
            return typography(rendered, size)
        case .classified(let base, _), .limitsOperator(let base):
            return glyphTypography(of: base, size: size)
        default:
            return nil
        }
    }

    /// Lays `node` out at the engine's base size into a device-independent
    /// scene. `display` enables display-style conventions (stacked limits,
    /// larger fraction parts).
    public func layout(_ node: MathNode, display: Bool = false) -> MathScene {
        let box = box(for: node, size: baseSize, style: display ? .display : .text)
        return MathScene(width: box.width, ascent: box.ascent, descent: box.descent,
                         elements: box.elements)
    }

    // MARK: - Node dispatch

    func box(for node: MathNode, size s: CGFloat, style: MathStyle) -> MathBox {
        let box = dispatch(node, size: s, style: style)
        // Hit-testing substrate: record where this subtree landed. Parents
        // translate the region with the other elements via placed(at:).
        if collectHitRegions, !isInvisible(node) {
            var b = box
            b.elements.append(.region(
                CGRect(origin: CGPoint(x: 0, y: -b.descent),
                       size: CGSize(width: b.width, height: b.ascent + b.descent)),
                node: node))
            return b
        }
        return box
    }

    private func isInvisible(_ node: MathNode) -> Bool {
        if case .space = node { return true }
        return false
    }

    private func dispatch(_ node: MathNode, size s: CGFloat, style: MathStyle) -> MathBox {
        switch node {
        case .symbol(let glyph, let cls, let symbolStyle):
            // TeX Rule 13: in display style a large operator swaps in the
            // font's display-size variant (DisplayOperatorMinHeight),
            // centered on the math axis.
            if cls == .largeOperator, style.isDisplay, let opBox = largeOperatorBox(glyph, size: s) {
                return opBox
            }
            return glyphBox(glyph, size: s, italic: symbolStyle == .italic, bold: symbolStyle == .bold,
                            sstyLevel: style.sstyLevel)

        case .functionName(let name):
            return glyphBox(name, size: s, italic: false)

        case .limitsOperator(let base):
            return box(for: base, size: s, style: style)   // transparent; limits handled in scriptsBox

        case .classified(let base, _):
            return box(for: base, size: s, style: style)   // transparent; only the atom class changes

        case .ruleBox(let w, let h):
            let ww = CGFloat(w) * s, hh = CGFloat(h) * s
            return MathBox(width: ww, ascent: hh, descent: 0, elements: [rule(x: 0, y: 0, width: ww, height: hh)])

        case .raised(let base, let shift):
            let b = box(for: base, size: s, style: style)
            let dy = CGFloat(shift) * s
            return MathBox(width: b.width, ascent: b.ascent + dy, descent: b.descent - dy,
                           inkAscent: b.inkAscent + dy, elements: b.placed(at: CGPoint(x: 0, y: dy)))

        case .colorbox(let base, let bg, let border):
            return colorboxBox(base, background: bg, border: border, size: s, style: style)

        case .space(let ems):
            return MathBox(width: CGFloat(ems) * s, ascent: 0, descent: 0)

        case .row(let children):
            return rowBox(children, size: s, style: style)

        case .fraction(let numerator, let denominator):
            return fractionBox(numerator, denominator, size: s, style: style)

        case .cfrac(let num, let den, let align):
            return cfracBox(num, den, align: align, size: s)

        case .radical(let degree, let radicand):
            return radicalBox(degree, radicand, size: s, style: style)

        case .scripts(let base, let sub, let sup):
            // TeX Rule 12: scripts on an accented single character move onto
            // the character itself — \hat{f}^2 puts the ² on the f, under
            // the hat's reach, not after the accent box.
            if case .accent(let inner, let acc) = base, acc.glyph != nil,
               case .symbol = inner {
                return accentBox(inner, accent: acc, size: s, style: style, scripts: (sub, sup))
            }
            return scriptsBox(base, sub: sub, sup: sup, size: s, style: style)

        case .delimited(let left, let body, let right):
            return delimitedBox(left, body, right, size: s, style: style)

        case .fenced(let fences, let segments):
            return fencedBox(fences, segments, size: s, style: style)

        case .matrix(let rows, let left, let right, let style):
            return matrixBox(rows, left: left, right: right, style: style, size: s)

        case .accent(let base, let accent):
            return accentBox(base, accent: accent, size: s, style: style)

        case .genfrac(let top, let bottom, let hasRule, let left, let right):
            return genfracBox(top, bottom, hasRule: hasRule, left: left, right: right,
                              size: s, style: style)

        case .overUnder(let base, let over, let under, let kind):
            return overUnderBox(base, over: over, under: under, kind: kind,
                                size: s, style: style)

        case .decorated(let base, let decoration):
            return decoratedBox(base, decoration: decoration, size: s, style: style)

        case .styled(let base, let color):
            // Lay the subtree out with a color override; nested \color nests.
            var sub = self
            sub.colorOverride = MathColor.resolve(color) ?? colorOverride
            return sub.box(for: base, size: s, style: style)

        case .mathStyle(let base, let forced):
            // \dfrac/\tfrac/\genfrac style/\displaystyle…: force the
            // subtree's style — and the size that style implies, scaled from
            // the enclosing full-size ANCHOR (not the running size, whose
            // relationship to the style is deliberately loosened by the
            // fraction part-scale): \scriptstyle shrinks, \displaystyle
            // inside a script returns to full size, and nothing can ever
            // exceed the anchor.
            return box(for: base, size: styleAnchorSize * forced.sizeFactor(constants),
                       style: forced)

        case .bigDelimiter(let glyph, let factor, _):
            return bigDelimiterBox(glyph, factor: factor, size: s)

        case .unsupported(let source):
            // Callers gate on isFullySupported; draw something sane regardless.
            return glyphBox(source, size: s * MathLayout.unsupportedSourceScale, italic: false, mono: true)
        }
    }

    /// The font's display-size variant of a large operator (∑, ∫, …) at
    /// `DisplayOperatorMinHeight`, centered on the math axis (TeX's
    /// `½(h − d) − a` shift). Nil headless or when the font has no variant.
    func largeOperatorBox(_ glyph: String, size: CGFloat) -> MathBox? {
        guard let provider = delimiters,
              let shape = provider(glyph, size * constants.displayOperatorMinHeight, size)
        else { return nil }
        let m = shape.metrics
        let offset = size * constants.axisHeight - (m.ascent - m.descent) / 2
        return MathBox(width: m.width, ascent: m.ascent + offset, descent: m.descent - offset,
                       inkAscent: m.inkAscent + offset,
                       elements: [.glyph(id: shape.glyphID, size: size,
                                         origin: CGPoint(x: 0, y: offset), color: colorOverride)])
    }

    /// TeX Rule 19's fence height: ψ measured from the axis, covered to at
    /// least `\delimiterfactor`/1000 of full (901 → 90.1%) or within
    /// `\delimitershortfall` (5 pt) of it, whichever demands more.
    func fenceTarget(ascent: CGFloat, descent: CGFloat, size: CGFloat) -> CGFloat {
        let axis = size * constants.axisHeight
        let psi = max(ascent - axis, descent + axis)
        return max(psi * 2 * 0.901, 2 * psi - 5)
    }

    // MARK: - Glyph boxes

    /// A box holding one glyph run. Style is expressed by remapping to a
    /// Mathematical-Alphanumeric codepoint (`mathVariant`), so the math font
    /// draws true italic/bold; the measurer supplies the metrics.
    func glyphBox(_ text: String, size: CGFloat, italic: Bool, bold: Bool = false,
                  mono: Bool = false, sstyLevel: Int = 0) -> MathBox {
        let glyph = mono ? text : Self.mathVariant(text, italic: italic, bold: bold)
        // `ssty` optical scripts: at script/scriptscript level, swap the base
        // glyph for the font's purpose-redrawn variant (heavier strokes so a
        // shrunk glyph keeps the base text's weight). Drawn by glyph ID —
        // the variants are unencoded — falling through to the scaled base
        // glyph when the font (or a headless host) provides no variant.
        if sstyLevel > 0, !mono, let scriptVariants,
           let sg = scriptVariants(glyph, size, sstyLevel) {
            let m = sg.metrics
            let element = MathElement.glyph(id: sg.glyphID, size: size,
                                            origin: CGPoint(x: 0, y: 0), color: colorOverride)
            return MathBox(width: m.width, ascent: m.ascent, descent: m.descent,
                           inkAscent: m.inkAscent, elements: [element])
        }
        let m = measure(glyph, size, mono)
        let element = MathElement.glyphs(text: glyph, size: size, mono: mono,
                                         origin: CGPoint(x: 0, y: 0), color: colorOverride)
        return MathBox(width: m.width, ascent: m.ascent, descent: m.descent, inkAscent: m.inkAscent,
                       elements: [element])
    }

    /// Remaps a single letter to its Mathematical-Alphanumeric codepoint so
    /// the math font renders proper math italic/bold — LaTeX conventions:
    /// ASCII variables italic (per the style flag), lowercase Greek always
    /// italic, uppercase Greek upright.
    static func mathVariant(_ text: String, italic: Bool, bold: Bool) -> String {
        guard text.unicodeScalars.count == 1, let u = text.unicodeScalars.first else { return text }
        let v = u.value
        func s(_ x: UInt32) -> String { UnicodeScalar(x).map(String.init) ?? text }
        if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) {
            let upper = v <= 0x5A
            let i = v - (upper ? 0x41 : 0x61)
            if bold && italic { return s((upper ? 0x1D468 : 0x1D482) + i) }
            if bold { return s((upper ? 0x1D400 : 0x1D41A) + i) }
            if italic { return v == 0x68 ? "\u{210E}" : s((upper ? 0x1D434 : 0x1D44E) + i) } // ℎ hole
            return text
        }
        if (0x3B1...0x3C9).contains(v) { return s((bold ? 0x1D6C2 : 0x1D6FC) + (v - 0x3B1)) }
        if bold, (0x391...0x3A9).contains(v) { return s(0x1D6A8 + (v - 0x391)) }
        return text
    }

    // MARK: - Rows with TeX spacing

    func rowBox(_ children: [MathNode], size: CGFloat, style: MathStyle) -> MathBox {
        var boxes: [(box: MathBox, cls: MathAtomClass?)] = []
        for child in children {
            boxes.append((box(for: child, size: size, style: style), atomClass(of: child)))
        }
        let classes = Self.reclassifyBinaries(boxes.map(\.cls))

        var width: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0
        var placements: [(MathBox, CGFloat)] = []
        var previous: MathAtomClass?

        for (i, entry) in boxes.enumerated() {
            let box = entry.box, cls = classes[i]
            if let previous, let cls {
                width += spacing(between: previous, and: cls, style: style) * size
            }
            placements.append((box, width))
            width += box.width
            ascent = max(ascent, box.ascent)
            descent = max(descent, box.descent)
            previous = cls ?? previous
        }

        var elements: [MathElement] = []
        for (box, x) in placements { elements += box.placed(at: CGPoint(x: x, y: 0)) }
        return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)
    }

    func atomClass(of node: MathNode) -> MathAtomClass? {
        switch node {
        case .symbol(_, let cls, _): return cls
        case .functionName: return .largeOperator
        case .limitsOperator(let base): return atomClass(of: base)
        case .classified(_, let cls): return cls
        case .raised(let base, _): return atomClass(of: base)
        // Fractions and delimited subformulas are TeX's Inner class (TeXbook
        // p. 170: "fractions are treated as type Inner") — they attract a thin
        // space against an adjacent Ord where two Ords would touch.
        case .fraction, .cfrac, .delimited, .fenced: return .inner
        case .matrix(_, let left, let right, _):
            // A fenced matrix (pmatrix, cases) is a delimited subformula →
            // Inner, exactly as TeX's \left(\vcenter{…}\right). A bare grid
            // (aligned, substack) is a \vcenter box → Ord.
            return (!left.isEmpty || !right.isEmpty) ? .inner : .ordinary
        case .radical, .row, .ruleBox, .colorbox: return .ordinary
        case .scripts(let base, _, _): return atomClass(of: base)
        case .accent(let base, _): return atomClass(of: base)
        case .genfrac: return .ordinary
        case .overUnder(_, _, _, let kind):
            switch kind {
            case .rightarrow, .leftarrow, .longRightArrow, .longLeftArrow, .leftRightArrow,
                 .hookRightArrow, .hookLeftArrow, .mapsToArrow,
                 .rightHarpoonUp, .rightHarpoonDown, .leftHarpoonUp, .leftHarpoonDown,
                 .rightLeftHarpoons:
                return .relation   // an annotated arrow is a relation
            default:
                return .ordinary
            }
        case .decorated(let base, _): return atomClass(of: base)
        case .styled(let base, _): return atomClass(of: base)
        case .mathStyle(let base, _): return atomClass(of: base)
        case .bigDelimiter(_, _, let cls): return cls
        case .space, .unsupported: return nil
        }
    }

    /// TeX's binary/unary reclassification (Appendix G rules 5–6; TeXbook
    /// p. 170 states the consequence — "Bin atoms must be preceded and
    /// followed by atoms compatible with the nature of binary operations",
    /// which is why the pair table can leave `*` in the Bin cells): a Bin
    /// atom with no valid left operand (at the start, or after
    /// Bin/Op/Rel/Open/Punct) is really a unary sign, so it becomes Ord; and
    /// a Bin immediately left of a Rel/Close/Punct becomes Ord too. This is
    /// what makes `x = -1` set a thick space after `=` and a tight unary
    /// minus, not a medium space around it. `nil` classes (spacing /
    /// unsupported) don't participate or reset state.
    static func reclassifyBinaries(_ input: [MathAtomClass?]) -> [MathAtomClass?] {
        var classes = input
        var prevIdx: Int?
        for i in classes.indices {
            guard let c = classes[i] else { continue }
            if c == .binary {
                let p = prevIdx.flatMap { classes[$0] }
                if p == nil || p == .binary || p == .largeOperator
                    || p == .relation || p == .opening || p == .punctuation {
                    classes[i] = .ordinary
                }
            } else if c == .relation || c == .closing || c == .punctuation {
                if let pi = prevIdx, classes[pi] == .binary { classes[pi] = .ordinary }
            }
            prevIdx = i
        }
        return classes
    }

    /// TeX's full 8×8 inter-atom pair table, transcribed cell-for-cell from
    /// The TeXbook p. 170. Values: 0 none · 1 thin (3mu) · 2 medium (4mu) ·
    /// 3 thick (5mu). NEGATIVE entries are TeX's parenthesized ones — applied
    /// only in display/text style, suppressed at script level. TeX's `*`
    /// cells (a Bin beside something it can't operate on) are 0 here: by the
    /// time spacing runs, `reclassifyBinaries` has retyped those Bins to Ord,
    /// so the cells genuinely never arise — exactly Knuth's argument for `*`.
    private static let pairSpacing: [[Int8]] = [
        // right:  Ord  Op  Bin  Rel Open Close Punct Inner    left:
        [           0,   1,  -2,  -3,   0,   0,   0,  -1],  // Ord
        [           1,   1,   0,  -3,   0,   0,   0,  -1],  // Op
        [          -2,  -2,   0,   0,  -2,   0,   0,  -2],  // Bin
        [          -3,  -3,   0,   0,  -3,   0,   0,  -3],  // Rel
        [           0,   0,   0,   0,   0,   0,   0,   0],  // Open
        [           0,   1,  -2,  -3,   0,   0,   0,  -1],  // Close
        [          -1,  -1,   0,  -1,  -1,  -1,  -1,  -1],  // Punct
        [          -1,   1,  -2,  -3,  -1,   0,  -1,  -1],  // Inner
    ]

    /// TeX inter-atom spacing in ems: thin 3/18 · medium 4/18 · thick 5/18,
    /// looked up in the p. 170 pair table above.
    func spacing(between left: MathAtomClass, and right: MathAtomClass,
                 style: MathStyle = .text) -> CGFloat {
        let entry = Self.pairSpacing[left.spacingIndex][right.spacingIndex]
        if entry < 0 && style.isScriptLevel { return 0 }
        switch abs(entry) {
        case 1: return MathSpacing.thin
        case 2: return MathSpacing.medium
        case 3: return MathSpacing.thick
        default: return 0
        }
    }

    // MARK: - Primitive helpers (DRY)

    /// A filled rule (bar/rect) in the current color.
    func rule(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> MathElement {
        .rule(CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height)),
              color: colorOverride)
    }

    /// A stroked path in the current color.
    func stroke(_ ops: [PathOp], width: CGFloat,
                cap: StrokeCap = .round, join: StrokeJoin = .miter) -> MathElement {
        .stroke(path: ops, width: width, cap: cap, join: join, color: colorOverride)
    }
}
