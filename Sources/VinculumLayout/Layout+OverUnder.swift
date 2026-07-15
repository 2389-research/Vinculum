import Foundation

extension MathLayoutEngine {

    /// Material set over/under a base: `\overset`/`\underset` (plain stacking),
    /// `\overbrace`/`\underbrace` (a drawn brace + label), and `\xrightarrow`/
    /// `\xleftarrow` (a stretchy arrow sized to its annotations).
    func overUnderBox(_ base: MathNode, over: MathNode?, under: MathNode?,
                      kind: MathOverUnder, size: CGFloat, style: MathStyle) -> MathBox {
        let annotationSize = size * constants.scriptPercentScaleDown
        let overBox = over.map { box(for: $0, size: annotationSize, style: style.scriptStyle) }
        let underBox = under.map { box(for: $0, size: annotationSize, style: style.scriptStyle) }
        let gap = size * MathLayout.overUnderGap

        switch kind {
        case .rightarrow, .leftarrow, .longRightArrow, .longLeftArrow, .leftRightArrow,
             .hookRightArrow, .hookLeftArrow, .mapsToArrow,
             .rightHarpoonUp, .rightHarpoonDown, .leftHarpoonUp, .leftHarpoonDown,
             .rightLeftHarpoons:
            let labelWidth = max(overBox?.width ?? 0, underBox?.width ?? 0)
            let arrowWidth = max(size * MathLayout.Arrow.minWidth, labelWidth + size * MathLayout.Arrow.labelPadding)
            let arrowThickness = max(1, size * constants.defaultRuleThickness)
            let headLength = size * MathLayout.Arrow.headLength
            let axis = size * constants.axisHeight
            // Double shafts and the stacked harpoons paint above/below the
            // axis, so the box must grow to cover the outer shaft.
            let shaftSpread = kind == .rightLeftHarpoons ? headLength * 0.5
                : (kind == .longRightArrow || kind == .longLeftArrow) ? arrowThickness : 0
            var ascent = axis + arrowThickness / 2 + shaftSpread
            var descent = arrowThickness / 2 - axis + shaftSpread
            if let overBox { ascent += gap + overBox.height }
            if let underBox { descent += gap + underBox.height }

            var elements = stretchyArrow(kind: kind, width: arrowWidth, axis: axis,
                                         thickness: arrowThickness, head: headLength)
            if let overBox {
                elements += overBox.placed(at: CGPoint(x: (arrowWidth - overBox.width) / 2,
                                                       y: axis + arrowThickness / 2 + shaftSpread + gap + overBox.descent))
            }
            if let underBox {
                elements += underBox.placed(at: CGPoint(x: (arrowWidth - underBox.width) / 2,
                                                        y: axis - arrowThickness / 2 - shaftSpread - gap - underBox.ascent))
            }
            return MathBox(width: arrowWidth, ascent: ascent, descent: max(descent, 0), elements: elements)

        case .overbrace, .underbrace, .overbracket, .underbracket, .overparen, .underparen:
            let baseBox = box(for: base, size: size, style: style)
            let braceHeight = size * MathLayout.Brace.height
            let isOver = kind == .overbrace || kind == .overbracket || kind == .overparen
            let label = isOver ? overBox : underBox
            var ascent = baseBox.ascent
            var descent = baseBox.descent
            if isOver {
                ascent += gap + braceHeight + (label.map { gap + $0.height } ?? 0)
            } else {
                descent += gap + braceHeight + (label.map { gap + $0.height } ?? 0)
            }
            let width = max(baseBox.width, label?.width ?? 0)

            var elements = baseBox.placed(at: CGPoint(x: (width - baseBox.width) / 2, y: 0))
            let braceY = isOver ? baseBox.ascent + gap : -baseBox.descent - gap - braceHeight
            switch kind {
            case .overbracket, .underbracket:
                elements.append(horizontalBracket(x: 0, y: braceY, width: width, height: braceHeight, pointingUp: isOver))
            case .overparen, .underparen:
                elements.append(horizontalParen(x: 0, y: braceY, width: width, height: braceHeight, pointingUp: isOver))
            default:
                elements.append(horizontalBrace(x: 0, y: braceY, width: width, height: braceHeight, pointingUp: isOver))
            }
            if let label {
                let labelY = isOver ? braceY + braceHeight + gap + label.descent
                                    : braceY - gap - label.ascent
                elements += label.placed(at: CGPoint(x: (width - label.width) / 2, y: labelY))
            }
            return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)

        case .overRightArrow, .overLeftArrow, .overLeftRightArrow,
             .underRightArrow, .underLeftArrow, .underLeftRightArrow:
            let baseBox = box(for: base, size: size, style: style)
            let isOver = kind == .overRightArrow || kind == .overLeftArrow || kind == .overLeftRightArrow
            let left = kind == .overLeftArrow || kind == .overLeftRightArrow
                    || kind == .underLeftArrow || kind == .underLeftRightArrow
            let right = kind == .overRightArrow || kind == .overLeftRightArrow
                     || kind == .underRightArrow || kind == .underLeftRightArrow
            let thickness = max(1, size * constants.defaultRuleThickness)
            let head = size * MathLayout.Arrow.headLength * 0.75
            let width = max(baseBox.width, head * 2)
            var elements = baseBox.placed(at: CGPoint(x: (width - baseBox.width) / 2, y: 0))
            if isOver {
                let y = baseBox.ascent + gap + head * 0.5
                elements.append(horizontalArrow(x0: 0, x1: width, y: y, thickness: thickness,
                                                 head: head, left: left, right: right))
                return MathBox(width: width, ascent: y + head * 0.5, descent: baseBox.descent, elements: elements)
            } else {
                let y = -baseBox.descent - gap - head * 0.5
                elements.append(horizontalArrow(x0: 0, x1: width, y: y, thickness: thickness,
                                                 head: head, left: left, right: right))
                return MathBox(width: width, ascent: baseBox.ascent, descent: -y + head * 0.5, elements: elements)
            }

        case .plain:
            let baseBox = box(for: base, size: size, style: style)
            let width = max(baseBox.width, overBox?.width ?? 0, underBox?.width ?? 0)
            var ascent = baseBox.ascent
            var descent = baseBox.descent
            if let overBox { ascent += gap + overBox.height }
            if let underBox { descent += gap + underBox.height }
            var elements = baseBox.placed(at: CGPoint(x: (width - baseBox.width) / 2, y: 0))
            if let overBox {
                elements += overBox.placed(at: CGPoint(x: (width - overBox.width) / 2,
                                                       y: baseBox.ascent + gap + overBox.descent))
            }
            if let underBox {
                elements += underBox.placed(at: CGPoint(x: (width - underBox.width) / 2,
                                                        y: -baseBox.descent - gap - underBox.ascent))
            }
            return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)
        }
    }

    /// The stretchy `\x…arrow` family, each with its own drawn shaft and
    /// head(s): plain/long(double)/bidirectional arrows, hooks, the mapsto
    /// tail bar, and single- or paired-barb harpoons. `axis` is the shaft
    /// centerline; the arrow spans `0…width`.
    private func stretchyArrow(kind: MathOverUnder, width: CGFloat, axis: CGFloat,
                               thickness: CGFloat, head: CGFloat) -> [MathElement] {
        let halfBarb: CGFloat = head * 0.5
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        // A full or half arrowhead at one end. `dir` is +1 for a head opening
        // rightward (drawn at the right tip) and -1 for the left tip.
        func headOps(tipX: CGFloat, dir: CGFloat, upper: Bool, lower: Bool) -> [PathOp] {
            let backX: CGFloat = tipX + dir * head
            // A full head is one connected V through the tip (a crisp point);
            // a harpoon is the single barb.
            if upper && lower {
                return [.move(pt(backX, axis + halfBarb)), .line(pt(tipX, axis)),
                        .line(pt(backX, axis - halfBarb))]
            }
            let barbY: CGFloat = upper ? axis + halfBarb : axis - halfBarb
            return [.move(pt(backX, barbY)), .line(pt(tipX, axis))]
        }

        // The stacked opposed harpoons (⇌): upper points right, lower left.
        if kind == .rightLeftHarpoons {
            let dy: CGFloat = halfBarb
            let topY: CGFloat = axis + dy, botY: CGFloat = axis - dy
            let top: [PathOp] = [.move(pt(0, topY)), .line(pt(width, topY)),
                                 .move(pt(width - head, topY + halfBarb)), .line(pt(width, topY))]
            let bot: [PathOp] = [.move(pt(0, botY)), .line(pt(width, botY)),
                                 .move(pt(head, botY - halfBarb)), .line(pt(0, botY))]
            return [stroke(top, width: thickness, cap: .round), stroke(bot, width: thickness, cap: .round)]
        }

        var ops: [PathOp] = []
        let leftward = kind == .leftarrow || kind == .longLeftArrow || kind == .hookLeftArrow
            || kind == .leftHarpoonUp || kind == .leftHarpoonDown
        let doubled = kind == .longRightArrow || kind == .longLeftArrow

        // Shaft: a single centerline, or two parallel rails for the long
        // (double-lined) arrows.
        if doubled {
            let hi: CGFloat = axis + thickness, lo: CGFloat = axis - thickness
            ops += [.move(pt(0, hi)), .line(pt(width, hi)), .move(pt(0, lo)), .line(pt(width, lo))]
        } else {
            ops += [.move(pt(0, axis)), .line(pt(width, axis))]
        }

        // Heads.
        switch kind {
        case .leftRightArrow:
            ops += headOps(tipX: width, dir: -1, upper: true, lower: true)
            ops += headOps(tipX: 0, dir: 1, upper: true, lower: true)
        case .rightHarpoonUp:   ops += headOps(tipX: width, dir: -1, upper: true, lower: false)
        case .rightHarpoonDown: ops += headOps(tipX: width, dir: -1, upper: false, lower: true)
        case .leftHarpoonUp:    ops += headOps(tipX: 0, dir: 1, upper: true, lower: false)
        case .leftHarpoonDown:  ops += headOps(tipX: 0, dir: 1, upper: false, lower: true)
        default:
            let tipX: CGFloat = leftward ? 0 : width
            ops += headOps(tipX: tipX, dir: leftward ? 1 : -1, upper: true, lower: true)
        }

        // Tail decorations: the mapsto bar, and the hook curl.
        if kind == .mapsToArrow {
            let barTop: CGFloat = axis + head * 0.6, barBot: CGFloat = axis - head * 0.6
            ops += [.move(pt(0, barTop)), .line(pt(0, barBot))]
        }
        if kind == .hookRightArrow {
            // A downward curl at the LEFT (tail) end of a rightward arrow.
            let curlX: CGFloat = head * 0.9, curlY: CGFloat = axis - head
            ops += [.move(pt(0, axis)), .quad(to: pt(curlX, curlY), control: pt(0, curlY))]
        }
        if kind == .hookLeftArrow {
            let curlX: CGFloat = width - head * 0.9, curlY: CGFloat = axis - head
            ops += [.move(pt(width, axis)), .quad(to: pt(curlX, curlY), control: pt(width, curlY))]
        }
        return [stroke(ops, width: thickness, cap: .round)]
    }

    /// A horizontal shaft from `x0` to `x1` at height `y`, with a drawn
    /// arrowhead on the left and/or right end.
    private func horizontalArrow(x0: CGFloat, x1: CGFloat, y: CGFloat, thickness: CGFloat,
                                 head: CGFloat, left: Bool, right: Bool) -> MathElement {
        var ops: [PathOp] = [.move(CGPoint(x: x0, y: y)), .line(CGPoint(x: x1, y: y))]
        if right {
            ops += [.move(CGPoint(x: x1 - head, y: y + head * 0.5)),
                    .line(CGPoint(x: x1, y: y)),
                    .line(CGPoint(x: x1 - head, y: y - head * 0.5))]
        }
        if left {
            ops += [.move(CGPoint(x: x0 + head, y: y + head * 0.5)),
                    .line(CGPoint(x: x0, y: y)),
                    .line(CGPoint(x: x0 + head, y: y - head * 0.5))]
        }
        return stroke(ops, width: thickness, cap: .round)
    }

    /// A square bracket (⎴/⎵) spanning `width`: a spine line away from the base
    /// with short turned ends toward it.
    private func horizontalBracket(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, pointingUp: Bool) -> MathElement {
        let thickness = max(1, height * MathLayout.Brace.thicknessFrac)
        let baseSide = pointingUp ? y : y + height
        let spineSide = pointingUp ? y + height : y
        return stroke([
            .move(CGPoint(x: x, y: baseSide)),
            .line(CGPoint(x: x, y: spineSide)),
            .line(CGPoint(x: x + width, y: spineSide)),
            .line(CGPoint(x: x + width, y: baseSide)),
        ], width: thickness, cap: .round, join: .miter)
    }

    /// A shallow parenthesis arc (⏜/⏝) spanning `width`, one quadratic bowing
    /// away from the base.
    private func horizontalParen(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, pointingUp: Bool) -> MathElement {
        let thickness = max(1, height * MathLayout.Brace.thicknessFrac)
        let baseSide = pointingUp ? y : y + height
        let spineSide = pointingUp ? y + height : y
        let control = baseSide + (spineSide - baseSide) * 2.0   // overshoot → rounded arc reaching the spine
        return stroke([
            .move(CGPoint(x: x, y: baseSide)),
            .quad(to: CGPoint(x: x + width, y: baseSide), control: CGPoint(x: x + width / 2, y: control)),
        ], width: thickness, cap: .round)
    }

    /// A horizontal curly brace spanning `width`, as four quadratic arcs with
    /// a center notch — the same hand-stroked approach as the radical.
    private func horizontalBrace(x: CGFloat, y: CGFloat, width: CGFloat,
                                 height: CGFloat, pointingUp: Bool) -> MathElement {
        let thickness = max(1, height * MathLayout.Brace.thicknessFrac)
        let notch = pointingUp ? y + height : y            // tip toward the label
        let shoulder = pointingUp ? y : y + height         // ends toward the base
        let midX = x + width / 2
        return stroke([
            .move(CGPoint(x: x, y: shoulder)),
            .quad(to: CGPoint(x: x + width * MathLayout.Brace.leftArcEnd, y: (shoulder + notch) * 0.5),
                  control: CGPoint(x: x + width * MathLayout.Brace.leftArcControl, y: shoulder)),
            .quad(to: CGPoint(x: midX, y: notch),
                  control: CGPoint(x: x + width * MathLayout.Brace.leftNotchControl, y: notch)),
            .quad(to: CGPoint(x: x + width * MathLayout.Brace.rightArcEnd, y: (shoulder + notch) * 0.5),
                  control: CGPoint(x: x + width * MathLayout.Brace.rightNotchControl, y: notch)),
            .quad(to: CGPoint(x: x + width, y: shoulder),
                  control: CGPoint(x: x + width * MathLayout.Brace.rightArcControl, y: shoulder)),
        ], width: thickness, cap: .round)
    }
}
