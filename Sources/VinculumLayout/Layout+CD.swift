#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension MathLayoutEngine {

    /// Lays out a commutative diagram (amscd `\begin{CD}`): objects on a grid,
    /// joined by labelled arrows. Objects sit at even (row, col); horizontal arrows
    /// at (even row, odd col) span the column gap; vertical arrows at (odd row, even
    /// col) span the row gap. Arrows are stroked paths (shaft + chevron head), labels
    /// are laid out at script size — so the whole thing renders on every platform
    /// through the VDL1 wire with no new primitive.
    func commutativeDiagramBox(_ grid: [[CDCell]], size: CGFloat, style: MathStyle) -> MathBox {
        let rows = grid.count
        let cols = grid.map(\.count).max() ?? 0
        guard rows > 0, cols > 0 else { return .empty }

        // Object boxes (text style — CD objects don't shrink).
        var boxes = Array(repeating: [MathBox?](repeating: nil, count: cols), count: rows)
        for r in 0..<rows {
            for c in 0..<grid[r].count {
                if case .object(let n) = grid[r][c] { boxes[r][c] = box(for: n, size: size, style: .text) }
            }
        }

        var colW = [CGFloat](repeating: 0, count: cols)
        var rowAsc = [CGFloat](repeating: 0, count: rows)
        var rowDesc = [CGFloat](repeating: 0, count: rows)
        for r in stride(from: 0, to: rows, by: 2) {
            for c in stride(from: 0, to: cols, by: 2) where c < grid[r].count {
                if let b = boxes[r][c] {
                    colW[c] = max(colW[c], b.width)
                    rowAsc[r] = max(rowAsc[r], b.ascent)
                    rowDesc[r] = max(rowDesc[r], b.descent)
                }
            }
        }
        // Object rows with no object still need a minimum height.
        for r in stride(from: 0, to: rows, by: 2) where rowAsc[r] + rowDesc[r] == 0 {
            rowAsc[r] = size * 0.5; rowDesc[r] = size * 0.2
        }

        let hGap = size * MathLayout.CD.columnGap   // room for a horizontal arrow + labels
        let vGap = size * MathLayout.CD.rowGap      // room for a vertical arrow + labels

        // Object-column centre X.
        var colCenterX = [CGFloat](repeating: 0, count: cols)
        var x: CGFloat = 0
        for c in stride(from: 0, to: cols, by: 2) {
            colCenterX[c] = x + colW[c] / 2
            x += colW[c] + hGap
        }
        let totalWidth = max(0, x - hGap)

        // Total height + object-row baselines (top-down), centred on the math axis.
        let objectRows = Array(stride(from: 0, to: rows, by: 2))
        var totalHeight: CGFloat = 0
        for (i, r) in objectRows.enumerated() {
            totalHeight += rowAsc[r] + rowDesc[r]
            if i > 0 { totalHeight += vGap }
        }
        let axis = size * constants.axisHeight
        let ascent = totalHeight / 2 + axis
        let descent = totalHeight / 2 - axis

        var rowBaseline = [CGFloat](repeating: 0, count: rows)
        var yTop = ascent
        for r in objectRows {
            rowBaseline[r] = yTop - rowAsc[r]
            yTop = rowBaseline[r] - rowDesc[r] - vGap
        }

        var elements: [MathElement] = []

        // Objects.
        for r in stride(from: 0, to: rows, by: 2) {
            for c in stride(from: 0, to: cols, by: 2) where c < grid[r].count {
                if let b = boxes[r][c] {
                    elements += b.placed(at: CGPoint(x: colCenterX[c] - b.width / 2, y: rowBaseline[r]))
                }
            }
        }

        // Arrows.
        let scriptSize = size * style.scriptSizeRatio(constants)
        let pad = size * MathLayout.CD.endPad
        for r in 0..<rows {
            for c in 0..<grid[r].count {
                switch grid[r][c] {
                case .hArrow(let a):
                    guard c - 1 >= 0, c + 1 < cols else { continue }
                    let y = rowBaseline[r] + axis
                    let x0 = colCenterX[c - 1] + colW[c - 1] / 2 + pad
                    let x1 = colCenterX[c + 1] - colW[c + 1] / 2 - pad
                    elements += horizontalArrow(a, x0: x0, x1: x1, y: y, size: size, scriptSize: scriptSize)
                case .vArrow(let a):
                    guard r - 1 >= 0, r + 1 < rows else { continue }
                    let x = colCenterX[c]
                    let y0 = rowBaseline[r - 1] - rowDesc[r - 1] - pad
                    let y1 = rowBaseline[r + 1] + rowAsc[r + 1] + pad
                    elements += verticalArrow(a, x: x, y0: y0, y1: y1, size: size, scriptSize: scriptSize)
                default:
                    break
                }
            }
        }

        return MathBox(width: totalWidth, ascent: ascent, descent: descent, elements: elements)
    }

    // MARK: - Arrow drawing

    private func strokeWidth(_ size: CGFloat) -> CGFloat { max(0.6, size * constants.defaultRuleThickness) }

    private func horizontalArrow(_ a: CDArrow, x0: CGFloat, x1: CGFloat, y: CGFloat,
                                 size: CGFloat, scriptSize: CGFloat) -> [MathElement] {
        var els: [MathElement] = []
        let w = strokeWidth(size)
        let hl = size * MathLayout.CD.headLength, hw = size * MathLayout.CD.headWidth
        if a.kind == .equal {
            let g = size * 0.06
            els.append(.stroke(path: [.move(CGPoint(x: x0, y: y + g)), .line(CGPoint(x: x1, y: y + g))],
                               width: w, cap: .butt, join: .miter, color: colorOverride))
            els.append(.stroke(path: [.move(CGPoint(x: x0, y: y - g)), .line(CGPoint(x: x1, y: y - g))],
                               width: w, cap: .butt, join: .miter, color: colorOverride))
        } else {
            let rightward = a.kind != .left
            let tip = CGPoint(x: rightward ? x1 : x0, y: y)
            let dir: CGFloat = rightward ? -1 : 1   // head opens back toward the shaft
            var path: [PathOp] = [.move(CGPoint(x: x0, y: y)), .line(CGPoint(x: x1, y: y))]
            path += [.move(CGPoint(x: tip.x + dir * hl, y: tip.y + hw)), .line(tip),
                     .line(CGPoint(x: tip.x + dir * hl, y: tip.y - hw))]
            els.append(.stroke(path: path, width: w, cap: .round, join: .round, color: colorOverride))
        }
        // Labels: above / below, centred on the shaft midpoint.
        let midX = (x0 + x1) / 2
        let gap = size * MathLayout.CD.labelGap
        if let l = a.label1 { els += labelBox(l, scriptSize).placedCentered(atX: midX, aboveY: y + gap) }
        if let l = a.label2 { els += labelBox(l, scriptSize).placedCentered(atX: midX, belowY: y - gap) }
        return els
    }

    private func verticalArrow(_ a: CDArrow, x: CGFloat, y0: CGFloat, y1: CGFloat,
                               size: CGFloat, scriptSize: CGFloat) -> [MathElement] {
        var els: [MathElement] = []
        let w = strokeWidth(size)
        let hl = size * MathLayout.CD.headLength, hw = size * MathLayout.CD.headWidth
        if a.kind == .equal {
            let g = size * 0.06
            els.append(.stroke(path: [.move(CGPoint(x: x + g, y: y0)), .line(CGPoint(x: x + g, y: y1))],
                               width: w, cap: .butt, join: .miter, color: colorOverride))
            els.append(.stroke(path: [.move(CGPoint(x: x - g, y: y0)), .line(CGPoint(x: x - g, y: y1))],
                               width: w, cap: .butt, join: .miter, color: colorOverride))
        } else {
            let downward = a.kind != .up
            let tip = CGPoint(x: x, y: downward ? y1 : y0)
            let dir: CGFloat = downward ? 1 : -1
            var path: [PathOp] = [.move(CGPoint(x: x, y: y0)), .line(CGPoint(x: x, y: y1))]
            path += [.move(CGPoint(x: tip.x + hw, y: tip.y + dir * hl)), .line(tip),
                     .line(CGPoint(x: tip.x - hw, y: tip.y + dir * hl))]
            els.append(.stroke(path: path, width: w, cap: .round, join: .round, color: colorOverride))
        }
        // Labels: left / right of the shaft midpoint.
        let midY = (y0 + y1) / 2
        let gap = size * MathLayout.CD.labelGap
        if let l = a.label1 { els += labelBox(l, scriptSize).placedRightAligned(toX: x - gap, atY: midY) }
        if let l = a.label2 { els += labelBox(l, scriptSize).placedLeftAligned(fromX: x + gap, atY: midY) }
        return els
    }

    private func labelBox(_ node: MathNode, _ scriptSize: CGFloat) -> MathBox {
        var e = self
        return e.box(for: node, size: scriptSize, style: .script)
    }
}

private extension MathBox {
    /// Centred horizontally on `atX`, with the box's BOTTOM at `aboveY`.
    func placedCentered(atX: CGFloat, aboveY: CGFloat) -> [MathElement] {
        placed(at: CGPoint(x: atX - width / 2, y: aboveY + descent))
    }
    /// Centred horizontally on `atX`, with the box's TOP at `belowY`.
    func placedCentered(atX: CGFloat, belowY: CGFloat) -> [MathElement] {
        placed(at: CGPoint(x: atX - width / 2, y: belowY - ascent))
    }
    /// Right edge at `toX`, vertically centred on `atY`.
    func placedRightAligned(toX: CGFloat, atY: CGFloat) -> [MathElement] {
        placed(at: CGPoint(x: toX - width, y: atY - (ascent - descent) / 2))
    }
    /// Left edge at `fromX`, vertically centred on `atY`.
    func placedLeftAligned(fromX: CGFloat, atY: CGFloat) -> [MathElement] {
        placed(at: CGPoint(x: fromX, y: atY - (ascent - descent) / 2))
    }
}
