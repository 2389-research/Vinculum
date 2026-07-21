#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension MathLayoutEngine {

    /// Greedy automatic line breaking of a top-level row to fit `maxWidth`.
    ///
    /// TeX allows a display-math line to break **after a binary operator or a
    /// relation** (the operator ends the line). We break only the top-level
    /// sequence — nested subformulas (fractions, roots, fenced groups) stay whole,
    /// exactly as TeX does — and stack the resulting lines, each baseline-aligned,
    /// the block's baseline being the first line's (natural for inline flow).
    ///
    /// Returns nil when nothing usefully breaks (a single unbreakable run, or one
    /// atom wider than `maxWidth`), so the caller keeps the ordinary one-line box.
    func brokenRowBox(_ children: [MathNode], maxWidth: CGFloat,
                      size: CGFloat, style: MathStyle) -> MathBox? {
        guard children.count > 1 else { return nil }
        let boxes = children.map { box(for: $0, size: size, style: style) }
        let classes = Self.reclassifyBinaries(children.map { atomClass(of: $0) })

        func gapBefore(prev: MathAtomClass?, _ i: Int) -> CGFloat {
            guard let prev, let cls = classes[i] else { return 0 }
            return spacing(between: prev, and: cls, style: style) * size
        }
        // A break is allowed AFTER a binary operator or relation.
        func breakableAfter(_ i: Int) -> Bool { classes[i] == .binary || classes[i] == .relation }

        // Width of a run of child indices, including inter-atom spacing.
        func runWidth(_ idxs: ArraySlice<Int>) -> (w: CGFloat, lastClass: MathAtomClass?) {
            var w: CGFloat = 0, prev: MathAtomClass?
            for idx in idxs { w += gapBefore(prev: prev, idx) + boxes[idx].width; prev = classes[idx] ?? prev }
            return (w, prev)
        }

        var lines: [[Int]] = []
        var line: [Int] = []
        var lineWidth: CGFloat = 0
        var prevClass: MathAtomClass?
        var lastBreak: Int? = nil       // position within `line` after which a break is allowed

        for i in 0..<children.count {
            let add = gapBefore(prev: prevClass, i) + boxes[i].width
            if lineWidth + add > maxWidth, let bp = lastBreak {
                // Commit line[0...bp]; the tail after the break starts the next line.
                lines.append(Array(line[0...bp]))
                line = Array(line[(bp + 1)...])
                // Recompute the break candidate inside the carried-over tail.
                lastBreak = nil
                for (k, idx) in line.enumerated() where breakableAfter(idx) && k < line.count - 1 { lastBreak = k }
            }
            line.append(i)
            (lineWidth, prevClass) = runWidth(line[...])   // exact width + trailing class
            if breakableAfter(i) { lastBreak = line.count - 1 }
        }
        if !line.isEmpty { lines.append(line) }
        guard lines.count > 1 else { return nil }

        let lineBoxes = lines.map { rowBox($0.map { children[$0] }, size: size, style: style) }
        return stackLines(lineBoxes, size: size)
    }

    /// Stacks line boxes vertically, left-aligned, with the block baseline on the
    /// first line. Gap between lines is the font's line gap analog.
    private func stackLines(_ lineBoxes: [MathBox], size: CGFloat) -> MathBox {
        let gap = size * MathLayout.LineBreak.lineGap
        var baselines: [CGFloat] = [0]
        for i in 1..<lineBoxes.count {
            baselines.append(baselines[i - 1] - lineBoxes[i - 1].descent - gap - lineBoxes[i].ascent)
        }
        var elements: [MathElement] = []
        for (i, b) in lineBoxes.enumerated() {
            elements += b.placed(at: CGPoint(x: 0, y: baselines[i]))
        }
        let width = lineBoxes.map(\.width).max() ?? 0
        let ascent = lineBoxes[0].ascent
        let descent = -(baselines.last ?? 0) + (lineBoxes.last?.descent ?? 0)
        return MathBox(width: width, ascent: ascent, descent: descent, elements: elements)
    }
}
