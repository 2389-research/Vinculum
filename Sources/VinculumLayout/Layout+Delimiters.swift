import Foundation

extension MathLayoutEngine {

    /// A single fence glyph scaled to `targetHeight` and vertically centered on
    /// the body's extent. Shared by the inline delimiter and matrix paths,
    /// which differ only in the target height they pass.
    func stretchedFence(_ glyph: String, targetHeight: CGFloat, around bodyBox: MathBox, size: CGFloat) -> MathBox {
        guard !glyph.isEmpty else { return .empty }
        let axis = size * constants.axisHeight
        // The caller passes a Rule 19 target (ψ-based, axis-symmetric);
        // floor it at one em so a short body still gets a real fence.
        let target = max(targetHeight, size)
        // For clearly-tall fences, prefer a discrete MATH-table size variant
        // (constant stroke weight). Small stretches scale fine with negligible
        // distortion, so we skip the variant path there.
        if target >= size * 2.0, let provider = delimiters, let shape = provider(glyph, target, size) {
            let m = shape.metrics
            let offset = axis - (m.ascent - m.descent) / 2
            return MathBox(width: m.width, ascent: m.ascent + offset, descent: m.descent - offset,
                           inkAscent: m.inkAscent + offset,
                           elements: [.glyph(id: shape.glyphID, size: size,
                                             origin: CGPoint(x: 0, y: offset), color: colorOverride)])
        }
        // Beyond the largest size variant: assemble the fence from the
        // font's parts (end caps + extenders, constant stroke weight),
        // centered on the axis like the variant path.
        if target >= size * 2.0, let provider = delimiterAssembly,
           let asm = provider(glyph, target, size) {
            let bottom = axis - asm.height / 2
            let elements = asm.placements.map {
                MathElement.glyph(id: $0.glyphID, size: size,
                                  origin: CGPoint(x: 0, y: bottom + $0.offset),
                                  color: colorOverride)
            }
            return MathBox(width: asm.width, ascent: bottom + asm.height, descent: -bottom,
                           inkAscent: bottom + asm.height, elements: elements)
        }
        let probe = glyphBox(glyph, size: size, italic: false)
        let scale = max(1, target / max(probe.height, 1))
        let scaled = glyphBox(glyph, size: size * scale, italic: false)
        // Center the fence's midline on the axis, not the body midline.
        let offset = axis - (scaled.ascent - scaled.descent) / 2
        return MathBox(width: scaled.width, ascent: scaled.ascent + offset, descent: scaled.descent - offset,
                       elements: scaled.placed(at: CGPoint(x: 0, y: offset)))
    }

    /// A lone `\big( … \Bigg]` delimiter: one glyph scaled to `factor × size`
    /// and centered vertically on the math axis (not a body midline — there is
    /// no body).
    func bigDelimiterBox(_ glyph: String, factor: CGFloat, size: CGFloat) -> MathBox {
        guard !glyph.isEmpty else { return .empty }
        let probe = glyphBox(glyph, size: size, italic: false)
        let scale = max(1, size * factor / max(probe.height, 1))
        let scaled = glyphBox(glyph, size: size * scale, italic: false)
        let axis = size * constants.axisHeight
        let offset = axis - (scaled.ascent - scaled.descent) / 2   // midpoint → axis
        return MathBox(width: scaled.width, ascent: scaled.ascent + offset,
                       descent: scaled.descent - offset,
                       elements: scaled.placed(at: CGPoint(x: 0, y: offset)))
    }

    /// `\left … \middle| … \right`: segments split on `\middle`, every fence
    /// (left, each middle, right) stretched to the common tallest-segment
    /// height and centered on the math axis via `stretchedFence`.
    func fencedBox(_ fences: [String], _ segments: [MathNode], size: CGFloat, style: MathStyle) -> MathBox {
        let segBoxes = segments.map { box(for: $0, size: size, style: style) }
        let bodyAscent = segBoxes.map(\.ascent).max() ?? 0
        let bodyDescent = segBoxes.map(\.descent).max() ?? 0
        let combined = MathBox(width: 0, ascent: bodyAscent, descent: bodyDescent)
        let target = fenceTarget(ascent: bodyAscent, descent: bodyDescent, size: size)
        let fenceBoxes = fences.map { stretchedFence($0, targetHeight: target, around: combined, size: size) }

        var elements: [MathElement] = []
        var x: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0
        for i in fenceBoxes.indices {
            let f = fenceBoxes[i]
            elements += f.placed(at: CGPoint(x: x, y: 0)); x += f.width
            ascent = max(ascent, f.ascent); descent = max(descent, f.descent)
            if i < segBoxes.count {
                let b = segBoxes[i]
                elements += b.placed(at: CGPoint(x: x, y: 0)); x += b.width
                ascent = max(ascent, b.ascent); descent = max(descent, b.descent)
            }
        }
        return MathBox(width: x, ascent: ascent, descent: descent, elements: elements)
    }

    /// `\left…\right`: a body flanked by fences sized to its height.
    func delimitedBox(_ left: String, _ body: MathNode, _ right: String, size: CGFloat, style: MathStyle) -> MathBox {
        let bodyBox = box(for: body, size: size, style: style)
        let target = fenceTarget(ascent: bodyBox.ascent, descent: bodyBox.descent, size: size)
        let leftBox = stretchedFence(left, targetHeight: target, around: bodyBox, size: size)
        let rightBox = stretchedFence(right, targetHeight: target, around: bodyBox, size: size)
        let width = leftBox.width + bodyBox.width + rightBox.width

        var elements = leftBox.elements
        elements += bodyBox.placed(at: CGPoint(x: leftBox.width, y: 0))
        elements += rightBox.placed(at: CGPoint(x: leftBox.width + bodyBox.width, y: 0))
        return MathBox(width: width,
                       ascent: max(bodyBox.ascent, leftBox.ascent, rightBox.ascent),
                       descent: max(bodyBox.descent, leftBox.descent, rightBox.descent),
                       elements: elements)
    }

    /// Fences an already-laid-out box (a grid or stack) with stretched fences.
    func delimitedBoxAround(_ bodyBox: MathBox, left: String, right: String, size: CGFloat) -> MathBox {
        let target = fenceTarget(ascent: bodyBox.ascent, descent: bodyBox.descent, size: size)
        let leftBox = stretchedFence(left, targetHeight: target, around: bodyBox, size: size)
        let rightBox = stretchedFence(right, targetHeight: target, around: bodyBox, size: size)
        let width = leftBox.width + bodyBox.width + rightBox.width + size * MathLayout.Grid.fencePadding

        var elements = leftBox.elements
        elements += bodyBox.placed(at: CGPoint(x: leftBox.width + size * MathLayout.Grid.fenceInset, y: 0))
        elements += rightBox.placed(at: CGPoint(x: leftBox.width + bodyBox.width + size * MathLayout.Grid.fenceInset, y: 0))
        return MathBox(width: width,
                       ascent: max(bodyBox.ascent, leftBox.ascent, rightBox.ascent),
                       descent: max(bodyBox.descent, leftBox.descent, rightBox.descent),
                       elements: elements)
    }

    /// Matrices, `cases`, `aligned`, `\substack`: a grid of cells with
    /// per-column alignment, centered on the math axis, optionally fenced.
    func matrixBox(_ rows: [[MathNode]], left: String, right: String,
                   style: MathMatrixStyle, size baseSize: CGFloat) -> MathBox {
        guard !rows.isEmpty else { return .empty }
        let size = style == .substack ? baseSize * constants.scriptPercentScaleDown : baseSize
        // Cells anchor forced styles at their own size.
        var cellEngine = self
        cellEngine.styleAnchorSize = size

        let columns = rows.map(\.count).max() ?? 0
        var cellBoxes: [[MathBox]] = []
        var colWidth = [CGFloat](repeating: 0, count: columns)
        var rowAscent = [CGFloat](repeating: 0, count: rows.count)
        var rowDescent = [CGFloat](repeating: 0, count: rows.count)
        for (r, row) in rows.enumerated() {
            var boxes: [MathBox] = []
            for (c, cell) in row.enumerated() {
                let b = cellEngine.box(for: cell, size: size, style: .text)
                boxes.append(b)
                colWidth[c] = max(colWidth[c], b.width)
                rowAscent[r] = max(rowAscent[r], b.ascent)
                rowDescent[r] = max(rowDescent[r], b.descent)
            }
            if row.isEmpty { rowAscent[r] = size * MathLayout.Grid.emptyRowAscent; rowDescent[r] = size * MathLayout.Grid.emptyRowDescent }
            cellBoxes.append(boxes)
        }

        let rowGap = size * (style == .substack ? MathLayout.Grid.substackRowGap : MathLayout.Grid.matrixRowGap)
        let colGap = size * (style == .aligned ? MathLayout.Grid.alignedColGap : MathLayout.Grid.matrixColGap)

        var totalHeight: CGFloat = 0
        for r in 0..<rows.count {
            totalHeight += rowAscent[r] + rowDescent[r]
            if r > 0 { totalHeight += rowGap }
        }
        let gridWidth = colWidth.reduce(0, +) + CGFloat(max(columns - 1, 0)) * colGap

        let axis = size * constants.axisHeight
        let ascent = totalHeight / 2 + axis
        let descent = totalHeight / 2 - axis

        var colX = [CGFloat](repeating: 0, count: columns)
        var running: CGFloat = 0
        for c in 0..<columns { colX[c] = running; running += colWidth[c] + colGap }

        // `array` extras: per-column alignment + drawn rules. Edge vertical
        // rules need outer padding so the grid isn't clipped by them.
        var arraySpec: ArraySpec?
        if case .array(let s) = style { arraySpec = s }
        let ruleT = size * constants.defaultRuleThickness
        let leftPad = (arraySpec?.columnRules.contains(0) ?? false) ? colGap / 2 : 0
        let rightPad = (arraySpec?.columnRules.contains(columns) ?? false) ? colGap / 2 : 0
        let totalWidth = gridWidth + leftPad + rightPad

        func cellOriginX(col: Int, box: MathBox) -> CGFloat {
            let x: CGFloat
            switch style {
            case .cases: x = colX[col]
            case .aligned: x = col % 2 == 0 ? colX[col] + (colWidth[col] - box.width) : colX[col]
            case .centered, .substack: x = colX[col] + (colWidth[col] - box.width) / 2
            case .array(let spec):
                // Out-of-range columns take the last spec entry, so a single
                // uniform alignment (matrix*[r]) covers every column.
                switch col < spec.alignments.count ? spec.alignments[col] : (spec.alignments.last ?? .center) {
                case .left: x = colX[col]
                case .right: x = colX[col] + (colWidth[col] - box.width)
                case .center: x = colX[col] + (colWidth[col] - box.width) / 2
                }
            }
            return x + leftPad
        }

        var elements: [MathElement] = []
        var boundaryY = [CGFloat](repeating: 0, count: rows.count + 1)   // horizontal-rule Y per row boundary
        boundaryY[0] = ascent
        var yTop = ascent
        for (r, boxes) in cellBoxes.enumerated() {
            let baseline = yTop - rowAscent[r]
            for (c, b) in boxes.enumerated() {
                elements += b.placed(at: CGPoint(x: cellOriginX(col: c, box: b), y: baseline))
            }
            let rowBottom = yTop - rowAscent[r] - rowDescent[r]
            boundaryY[r + 1] = r < rows.count - 1 ? rowBottom - rowGap / 2 : rowBottom
            yTop = rowBottom - rowGap
        }

        if let spec = arraySpec {
            for k in spec.columnRules {
                let x: CGFloat = k <= 0 ? 0
                    : k >= columns ? totalWidth - ruleT
                    : leftPad + colX[k] - colGap / 2 - ruleT / 2
                elements.append(rule(x: x, y: -descent, width: ruleT, height: ascent + descent))
            }
            for rr in spec.rowRules where rr.boundary >= 0 && rr.boundary <= rows.count {
                let y = boundaryY[rr.boundary]
                let x0: CGFloat, x1: CGFloat
                if rr.toColumn == .max || (rr.fromColumn <= 0 && rr.toColumn >= columns - 1) {
                    x0 = 0; x1 = totalWidth
                } else {
                    let from = max(0, min(rr.fromColumn, columns - 1))
                    let to = max(0, min(rr.toColumn, columns - 1))
                    x0 = leftPad + colX[from]; x1 = leftPad + colX[to] + colWidth[to]
                }
                elements.append(rule(x: x0, y: y - ruleT / 2, width: x1 - x0, height: ruleT))
            }
        }
        let grid = MathBox(width: totalWidth, ascent: ascent, descent: descent, elements: elements)

        guard !left.isEmpty || !right.isEmpty else { return grid }
        return delimitedBoxAround(grid, left: left, right: right, size: size)
    }
}
