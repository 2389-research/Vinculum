import Foundation

extension MathLayoutEngine {

    /// `\colorbox{bg}{…}` / `\fcolorbox{border}{bg}{…}`: a filled background
    /// rectangle behind the content, with an optional stroked border.
    func colorboxBox(_ base: MathNode, background: String, border: String?,
                     size: CGFloat, style: MathStyle) -> MathBox {
        let baseBox = box(for: base, size: size, style: style)
        let pad = size * MathLayout.Box.padding
        let width = baseBox.width + pad * 2
        let ascent = baseBox.ascent + pad
        let descent = baseBox.descent + pad
        var elements: [MathElement] = []
        if let bg = MathColor.resolve(background) {   // filled background, drawn first (behind)
            let bgRect = CGRect(origin: CGPoint(x: 0, y: -descent),
                                size: CGSize(width: width, height: ascent + descent))
            elements.append(MathElement.rule(bgRect, color: bg))
        }
        elements += baseBox.placed(at: CGPoint(x: pad, y: 0))
        if let border, let bc = MathColor.resolve(border) {
            let line = max(1, size * constants.defaultRuleThickness)
            let rx = line / 2, ry = -descent + line / 2, rw = width - line, rh = ascent + descent - line
            elements.append(.stroke(path: [.move(CGPoint(x: rx, y: ry)), .line(CGPoint(x: rx + rw, y: ry)),
                                           .line(CGPoint(x: rx + rw, y: ry + rh)), .line(CGPoint(x: rx, y: ry + rh)),
                                           .close], width: line, cap: .butt, join: .miter, color: bc))
        }
        return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)
    }

    /// `\boxed` (a stroked frame with padding) and the `\phantom` family
    /// (reserve space, draw nothing).
    func decoratedBox(_ base: MathNode, decoration: MathDecoration,
                      size: CGFloat, style: MathStyle) -> MathBox {
        let baseBox = box(for: base, size: size, style: style)
        switch decoration {
        case .phantom:
            return MathBox(width: baseBox.width, ascent: baseBox.ascent, descent: baseBox.descent)
        case .hphantom:
            return MathBox(width: baseBox.width, ascent: 0, descent: 0)
        case .vphantom:
            return MathBox(width: 0, ascent: baseBox.ascent, descent: baseBox.descent)
        case .boxed:
            let pad = size * MathLayout.Box.padding
            let line = max(1, size * constants.defaultRuleThickness)
            let width = baseBox.width + pad * 2
            let ascent = baseBox.ascent + pad
            let descent = baseBox.descent + pad
            var elements = baseBox.placed(at: CGPoint(x: pad, y: 0))
            // A closed rectangle stroked centered on its edge (== stroke(rect)).
            let rx = line / 2, ry = -descent + line / 2
            let rw = width - line, rh = ascent + descent - line
            elements.append(stroke([
                .move(CGPoint(x: rx, y: ry)),
                .line(CGPoint(x: rx + rw, y: ry)),
                .line(CGPoint(x: rx + rw, y: ry + rh)),
                .line(CGPoint(x: rx, y: ry + rh)),
                .close,
            ], width: line, cap: .butt, join: .miter))
            return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)

        case .cancel, .bcancel, .xcancel:
            // Diagonal strike(s) across the base's box, base kept underneath.
            let t = max(1, size * constants.defaultRuleThickness)
            let yb = -baseBox.descent, yt = baseBox.ascent
            var elements = baseBox.elements
            if decoration != .bcancel {   // forward ╱
                elements.append(stroke([.move(CGPoint(x: 0, y: yb)), .line(CGPoint(x: baseBox.width, y: yt))], width: t))
            }
            if decoration != .cancel {    // backward ╲
                elements.append(stroke([.move(CGPoint(x: 0, y: yt)), .line(CGPoint(x: baseBox.width, y: yb))], width: t))
            }
            return MathBox(width: baseBox.width, ascent: baseBox.ascent, descent: baseBox.descent,
                           inkAscent: baseBox.inkAscent, elements: elements)

        case .negation:
            // \not — a short steep slash centered on the atom (a ≠ from =).
            let t = max(1, size * constants.defaultRuleThickness)
            let axis = size * constants.axisHeight
            let cx = baseBox.width / 2
            let halfH = size * 0.42, halfW = size * 0.15
            var elements = baseBox.elements
            elements.append(stroke([.move(CGPoint(x: cx - halfW, y: axis - halfH)),
                                    .line(CGPoint(x: cx + halfW, y: axis + halfH))], width: t))
            return MathBox(width: baseBox.width, ascent: max(baseBox.ascent, axis + halfH),
                           descent: baseBox.descent, inkAscent: baseBox.inkAscent, elements: elements)

        case .smash:
            // Draw the content but report zero height/depth so it overlaps.
            return MathBox(width: baseBox.width, ascent: 0, descent: 0, elements: baseBox.elements)

        case .rlap:  // zero-width, content overhangs right (drawn at x = 0)
            return MathBox(width: 0, ascent: baseBox.ascent, descent: baseBox.descent, elements: baseBox.elements)

        case .llap:  // zero-width, content overhangs left
            return MathBox(width: 0, ascent: baseBox.ascent, descent: baseBox.descent,
                           elements: baseBox.placed(at: CGPoint(x: -baseBox.width, y: 0)))

        case .clap:  // zero-width, content centered on the point
            return MathBox(width: 0, ascent: baseBox.ascent, descent: baseBox.descent,
                           elements: baseBox.placed(at: CGPoint(x: -baseBox.width / 2, y: 0)))
        }
    }
}
