#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension MathLayoutEngine {

    /// Lays out a syntax / parse tree (qtree `\Tree`): a labelled root centered above
    /// its children, joined by straight edges. Classic tidy-tree placement — subtree
    /// widths computed bottom-up, then nodes placed top-down and edges drawn from each
    /// parent label's bottom-center to each child label's top-center. Everything is
    /// label sub-scenes + stroked edges, so it renders on every platform through VDL1.
    func syntaxTreeBox(_ root: SyntaxTreeNode, size: CGFloat, style: MathStyle) -> MathBox {
        // 1. Build a parallel layout tree of label boxes (text style — nodes don't shrink).
        let laid = build(root, size: size)

        // 2. Uniform row height keeps sibling labels and edges aligned across the level.
        var maxLabelH: CGFloat = 0
        forEach(laid) { maxLabelH = max(maxLabelH, $0.box.ascent + $0.box.descent) }
        let rowH = max(maxLabelH, size * 0.5)
        let levelGap = size * MathLayout.Tree.levelGap
        let levelH = rowH + levelGap
        let depth = self.depth(laid)
        let totalH = CGFloat(depth) * levelH + rowH

        // 3. Measure subtree widths / anchors bottom-up.
        measure(laid, size: size)

        // 4. Center on the math axis, place top-down.
        let axis = size * constants.axisHeight
        let ascent = totalH / 2 + axis
        let descent = totalH / 2 - axis
        let row0CenterY = ascent - rowH / 2   // vertical center of the root's label band

        var elements: [MathElement] = []
        place(laid, left: 0, depth: 0,
              rowCenterY: row0CenterY, levelH: levelH, rowH: rowH,
              size: size, into: &elements)

        return MathBox(width: laid.width, ascent: ascent, descent: descent, elements: elements)
    }

    // MARK: - Layout tree

    /// A node's label box plus its laid-out children; `width`/`anchorX` are filled by
    /// `measure` (anchorX is the label center's x within this subtree's own box).
    private final class TN {
        let box: MathBox
        let children: [TN]
        var width: CGFloat = 0
        var anchorX: CGFloat = 0
        init(box: MathBox, children: [TN]) { self.box = box; self.children = children }
    }

    private func build(_ n: SyntaxTreeNode, size: CGFloat) -> TN {
        var e = self
        let box = e.box(for: n.label, size: size, style: .text)
        return TN(box: box, children: n.children.map { build($0, size: size) })
    }

    private func forEach(_ n: TN, _ body: (TN) -> Void) {
        body(n)
        for c in n.children { forEach(c, body) }
    }

    private func depth(_ n: TN) -> Int {
        n.children.isEmpty ? 0 : 1 + (n.children.map { depth($0) }.max() ?? 0)
    }

    /// Bottom-up: a leaf is as wide as its label; an internal node is as wide as the
    /// max of its label and its children laid side by side, and its anchor is the
    /// midpoint between the first and last child anchors.
    private func measure(_ n: TN, size: CGFloat) {
        let labelW = n.box.width
        guard !n.children.isEmpty else {
            n.width = labelW
            n.anchorX = labelW / 2
            return
        }
        let gap = size * MathLayout.Tree.siblingGap
        for c in n.children { measure(c, size: size) }
        let childrenW = n.children.reduce(0) { $0 + $1.width } + gap * CGFloat(n.children.count - 1)
        n.width = max(labelW, childrenW)

        // Children block is centered within the subtree width.
        let blockLeft = (n.width - childrenW) / 2
        var x = blockLeft
        var firstAnchor: CGFloat = 0, lastAnchor: CGFloat = 0
        for (i, c) in n.children.enumerated() {
            let anchor = x + c.anchorX
            if i == 0 { firstAnchor = anchor }
            lastAnchor = anchor
            x += c.width + gap
        }
        n.anchorX = (firstAnchor + lastAnchor) / 2
    }

    /// Top-down: place this node's label centered at `left + anchorX`, recurse for the
    /// children band below, and draw an edge from the label's bottom-center to each
    /// child label's top-center.
    private func place(_ n: TN, left: CGFloat, depth: Int,
                       rowCenterY: CGFloat, levelH: CGFloat, rowH: CGFloat,
                       size: CGFloat, into elements: inout [MathElement]) {
        let labelCenterX = left + n.anchorX
        let box = n.box
        elements += box.placed(at: CGPoint(x: labelCenterX - box.width / 2,
                                           y: rowCenterY - (box.ascent - box.descent) / 2))

        guard !n.children.isEmpty else { return }
        let gap = size * MathLayout.Tree.siblingGap
        let pad = size * MathLayout.Tree.edgePad
        let w = max(0.6, size * constants.defaultRuleThickness)

        let childrenW = n.children.reduce(0) { $0 + $1.width } + gap * CGFloat(n.children.count - 1)
        let blockLeft = left + (n.width - childrenW) / 2
        let childRowCenterY = rowCenterY - levelH

        let parentBottom = rowCenterY - rowH / 2 - pad
        let childTop = childRowCenterY + rowH / 2 + pad

        var x = blockLeft
        for c in n.children {
            let childCenterX = x + c.anchorX
            elements.append(.stroke(path: [.move(CGPoint(x: labelCenterX, y: parentBottom)),
                                           .line(CGPoint(x: childCenterX, y: childTop))],
                                    width: w, cap: .round, join: .round, color: colorOverride))
            place(c, left: x, depth: depth + 1,
                  rowCenterY: childRowCenterY, levelH: levelH, rowH: rowH,
                  size: size, into: &elements)
            x += c.width + gap
        }
    }
}
