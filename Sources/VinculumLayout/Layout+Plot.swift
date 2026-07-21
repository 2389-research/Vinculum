#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

extension MathLayoutEngine {

    /// Lays out a function plot: samples each curve, auto-ranges y, draws a framed
    /// axis with nice-numbered ticks + gridlines, and the curves as stroked polylines
    /// (broken across discontinuities). Everything is stroked paths + small glyph
    /// runs, so it renders identically on every platform through the VDL1 wire.
    func plotBox(_ curves: [PlotCurve], xMin: Double, xMax: Double, size: CGFloat) -> MathBox {
        // Sample.
        struct Sampled { var pts: [(x: Double, y: Double)] }
        let sampled: [Sampled] = curves.map { curve in
            guard let f = MathExpression(curve.expression), xMax > xMin else { return Sampled(pts: []) }
            let n = max(2, curve.samples)
            var pts: [(Double, Double)] = []
            for k in 0...n {
                let x = xMin + (xMax - xMin) * Double(k) / Double(n)
                pts.append((x, f(x)))
            }
            return Sampled(pts: pts)
        }

        // Auto y-range from finite samples; robust to a stray asymptote via the
        // interquartile-ish trim (drop the extreme 2% each end).
        var ys = sampled.flatMap { $0.pts.map(\.y) }.filter { $0.isFinite }
        ys.sort()
        var yMin = -1.0, yMax = 1.0
        if !ys.isEmpty {
            let lo = ys[Int(Double(ys.count - 1) * 0.02)]
            let hi = ys[Int(Double(ys.count - 1) * 0.98)]
            yMin = min(lo, hi); yMax = max(lo, hi)
            if yMax - yMin < 1e-9 { yMin -= 1; yMax += 1 }
            let pad = (yMax - yMin) * 0.08
            yMin -= pad; yMax += pad
        }

        // Frame geometry.
        let plotW = size * MathLayout.Plot.width
        let plotH = size * MathLayout.Plot.height
        let labelSize = size * MathLayout.Plot.labelScale
        let leftMargin = size * MathLayout.Plot.leftMargin
        let bottomMargin = size * MathLayout.Plot.bottomMargin
        let totalW = leftMargin + plotW
        let totalH = plotH + bottomMargin
        let axis = size * constants.axisHeight
        let ascent = totalH / 2 + axis
        let descent = totalH / 2 - axis
        let plotBottom = -descent + bottomMargin
        let plotTop = plotBottom + plotH
        let plotLeft = leftMargin
        let plotRight = plotLeft + plotW

        func mapX(_ x: Double) -> CGFloat { plotLeft + CGFloat((x - xMin) / (xMax - xMin)) * plotW }
        func mapY(_ y: Double) -> CGFloat { plotBottom + CGFloat((y - yMin) / (yMax - yMin)) * plotH }

        let thin = max(0.5, size * constants.defaultRuleThickness * 0.8)
        let grid = MathColor(red: 0.85, green: 0.85, blue: 0.87)
        let axisColor = colorOverride ?? MathColor(red: 0.35, green: 0.35, blue: 0.38)
        var elements: [MathElement] = []

        // Gridlines + ticks + labels.
        let xStep = Self.niceStep(xMax - xMin, 6)
        let yStep = Self.niceStep(yMax - yMin, 5)
        func labelBox(_ s: String) -> MathBox { glyphBox(s, size: labelSize, italic: false) }

        var vx = (xMin / xStep).rounded(.up) * xStep
        while vx <= xMax + 1e-9 {
            let px = mapX(vx)
            elements.append(.stroke(path: [.move(CGPoint(x: px, y: plotBottom)), .line(CGPoint(x: px, y: plotTop))],
                                    width: thin, cap: .butt, join: .miter, color: grid))
            let lb = labelBox(Self.fmt(vx))
            elements += lb.placed(at: CGPoint(x: px - lb.width / 2, y: plotBottom - labelSize * 0.9 - lb.ascent))
            vx += xStep
        }
        var vy = (yMin / yStep).rounded(.up) * yStep
        while vy <= yMax + 1e-9 {
            let py = mapY(vy)
            elements.append(.stroke(path: [.move(CGPoint(x: plotLeft, y: py)), .line(CGPoint(x: plotRight, y: py))],
                                    width: thin, cap: .butt, join: .miter, color: grid))
            let lb = labelBox(Self.fmt(vy))
            elements += lb.placed(at: CGPoint(x: plotLeft - labelSize * 0.4 - lb.width, y: py - (lb.ascent - lb.descent) / 2))
            vy += yStep
        }

        // Axes (through the origin if it's in range, else on the frame edge).
        let axisW = max(0.7, size * constants.defaultRuleThickness)
        let xAxisY = (yMin < 0 && yMax > 0) ? mapY(0) : plotBottom
        let yAxisX = (xMin < 0 && xMax > 0) ? mapX(0) : plotLeft
        elements.append(.stroke(path: [.move(CGPoint(x: plotLeft, y: xAxisY)), .line(CGPoint(x: plotRight, y: xAxisY))],
                                width: axisW, cap: .butt, join: .miter, color: axisColor))
        elements.append(.stroke(path: [.move(CGPoint(x: yAxisX, y: plotBottom)), .line(CGPoint(x: yAxisX, y: plotTop))],
                                width: axisW, cap: .butt, join: .miter, color: axisColor))

        // Curves — a polyline per contiguous in-range run.
        let curveW = max(0.9, size * constants.defaultRuleThickness * 1.6)
        for s in sampled {
            var run: [PathOp] = []
            var started = false
            for p in s.pts {
                let inRange = p.y.isFinite && p.y >= yMin - (yMax - yMin) && p.y <= yMax + (yMax - yMin)
                if inRange {
                    let pt = CGPoint(x: mapX(p.x), y: mapY(min(max(p.y, yMin), yMax)))
                    if started { run.append(.line(pt)) } else { run.append(.move(pt)); started = true }
                } else if started {
                    elements.append(.stroke(path: run, width: curveW, cap: .round, join: .round, color: colorOverride))
                    run = []; started = false
                }
            }
            if run.count >= 2 { elements.append(.stroke(path: run, width: curveW, cap: .round, join: .round, color: colorOverride)) }
        }

        return MathBox(width: totalW, ascent: ascent, descent: descent, elements: elements)
    }

    /// A "nice" tick step (1/2/5 × 10ⁿ) giving about `target` intervals over `range`.
    static func niceStep(_ range: Double, _ target: Int) -> Double {
        guard range > 0 else { return 1 }
        let raw = range / Double(max(1, target))
        let mag = pow(10, (log10(raw)).rounded(.down))
        let norm = raw / mag
        let step = norm < 1.5 ? 1.0 : norm < 3 ? 2.0 : norm < 7 ? 5.0 : 10.0
        return step * mag
    }

    /// Compact tick label: trims trailing zeros, drops "-0".
    static func fmt(_ v: Double) -> String {
        if abs(v) < 1e-9 { return "0" }
        var s = String(format: "%.2f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s
    }
}
