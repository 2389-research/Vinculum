#if canImport(AppKit)
import XCTest
import AppKit
import CoreGraphics
@testable import VinculumRender
@testable import VinculumLayout

/// A0 (issue #76): the platform-free `DisplayList` emitter — a `MathScene`
/// reduced to outlines + rects that needs no font to draw.
///
/// The load-bearing claim is **"the display list fully determines the picture"**
/// — everything the Android `Canvas` needs is in it. Proven the only honest way:
/// rasterize the display list independently and compare its ink signature to
/// what `MathImageRenderer` draws for the same equation. They must match,
/// because both fill the same glyph outlines — which is exactly why an
/// all-outlines list is the *highest-fidelity* choice against our own render,
/// not a compromise.
final class MathDisplayListTests: XCTestCase {

    // Build a scene the way MathImageRenderer does (display → baseSize×1.15),
    // then emit its display list with the CoreText outliner.
    private func displayList(_ latex: String, baseSize: CGFloat = 17) throws -> DisplayList {
        let node = MathParser.parse(latex)
        try XCTSkipUnless(MathParser.isFullySupported(node), "unsupported: \(latex)")
        let engine = MathLayoutEngine.make(font: .latinModern, baseSize: baseSize * 1.15)
        let scene = engine.layout(node, display: true)
        return MathDisplayListRenderer.displayList(for: scene, outliner: CoreTextOutliner.make())
    }

    // MARK: - Structure

    func testSupportedEquationEmitsOnlyConcretePrimitives() throws {
        let list = try displayList(#"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#)
        XCTAssertFalse(list.ops.isEmpty, "a supported equation must emit ink")
        XCTAssertTrue(list.width.isFinite && list.ascent.isFinite && list.descent.isFinite)
        for op in list.ops {
            switch op {
            case let .fillPath(subpaths, _):
                XCTAssertFalse(subpaths.isEmpty, "a fill path with no subpaths is dead ink")
            case .fillRect, .strokePath:
                break
            }
        }
    }

    func testFractionEmitsARuleForTheBar() throws {
        let list = try displayList(#"\frac{a}{b}"#)
        let rects = list.ops.filter { if case .fillRect = $0 { return true }; return false }
        XCTAssertFalse(rects.isEmpty, "the fraction bar must be a fillRect — without it the "
                       + "display list can't draw the bar and the picture is wrong")
    }

    func testGlyphsBecomeFilledOutlines() throws {
        let list = try displayList(#"x"#)
        let fills = list.ops.filter { if case .fillPath = $0 { return true }; return false }
        XCTAssertFalse(fills.isEmpty, "a plain identifier must resolve to a filled outline")
    }

    /// The `.glyph(id:)` path: a tall `\left(…\right)` swaps in a MATH-table size
    /// variant with no character spelling. It must still become filled outlines,
    /// not vanish — this is the case a naive SVG-only path drops.
    func testStretchyDelimiterRendersAsOutlines() throws {
        let plain = try displayList(#"(x)"#)
        let tall  = try displayList(#"\left( \frac{a}{\frac{b}{c}} \right)"#)
        // The tall version has strictly more filled outlines (the big fences +
        // the nested fraction), and renders ink out at its left and right edges.
        let tallFills = tall.ops.filter { if case .fillPath = $0 { return true }; return false }.count
        let plainFills = plain.ops.filter { if case .fillPath = $0 { return true }; return false }.count
        XCTAssertGreaterThan(tallFills, plainFills, "the size-variant fences add filled outlines")
        // The fences make the box far taller than a plain `(x)`; if they'd been
        // dropped (the failure this guards), the height would barely change.
        XCTAssertGreaterThan(tall.height, plain.height * 2,
                             "the stretched fences must actually be tall")
        // That the fences render *correctly* (not just tall) is proven by the
        // whole-image ink comparison below, which includes this exact equation.
    }

    // MARK: - Fidelity: the display list matches what MathImageRenderer draws

    func testDisplayListInkMatchesImageRenderer() throws {
        // Compared at 48pt, not 17: both sides fill the SAME CoreGraphics
        // outlines, so at a real display size they agree to within AA noise;
        // at 17pt the images are barely 20px and sub-pixel AA dominates. This
        // is the standing ink-signature discipline — a size where the signal is
        // real, not a threshold tuned to hide small-image noise.
        let size: CGFloat = 48
        for latex in [#"x^2"#, #"\frac{a}{b}"#, #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
                      #"\sum_{i=1}^{n} i^2"#, #"\left( \frac{a}{\frac{b}{c}} \right)"#] {
            let list = try displayList(latex, baseSize: size)
            let (lp, lw, lh) = raster(list)
            let listSig = try XCTUnwrap(inkSignature(lp, lw, lh), "display list drew no ink: \(latex)")

            let r = try XCTUnwrap(MathImageRenderer.rendered(
                latex: latex, display: true, mathTheme: .light, baseSize: size, font: .latinModern))
            let (ip, iw, ih) = try XCTUnwrap(rgba(r.image))
            let imgSig = try XCTUnwrap(inkSignature(ip, iw, ih), "image drew no ink: \(latex)")

            XCTAssertEqual(listSig.count, imgSig.count)
            let bad = zip(listSig, imgSig).filter { abs($0.0 - $0.1) > 2 }.count
            let ratio = Double(bad) / Double(imgSig.count)
            XCTAssertLessThanOrEqual(ratio, 0.06,
                "\(bad)/\(imgSig.count) cells differ (\(String(format: "%.1f%%", ratio * 100))) — the "
                + "display list does not reproduce what MathImageRenderer draws for \(latex), so it "
                + "does not fully determine the picture")
        }
    }

    // MARK: - A test-only rasterizer for the DisplayList

    /// Draws the (y-up, baseline-origin) display list into an RGBA8 bitmap.
    private func raster(_ list: DisplayList, pad: CGFloat = 2) -> (px: [UInt8], w: Int, h: Int) {
        let w = max(1, Int(ceil(list.width + pad * 2)))
        let h = max(1, Int(ceil(list.height + pad * 2)))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // CGContext is y-up (origin bottom-left); the scene is y-up with the
            // origin on the baseline. Put the baseline at pad+descent from the
            // bottom, then scene coords pass straight through.
            ctx.translateBy(x: pad, y: pad + list.descent)
            for op in list.ops {
                switch op {
                case let .fillPath(subpaths, color):
                    addPath(subpaths, to: ctx); ctx.setFillColor(cg(color)); ctx.fillPath(using: .winding)
                case let .fillRect(rect, color):
                    ctx.setFillColor(cg(color)); ctx.fill(rect)
                case let .strokePath(path, width, cap, join, color):
                    addPath(path, to: ctx)
                    ctx.setStrokeColor(cg(color)); ctx.setLineWidth(width)
                    ctx.setLineCap(cap == .round ? .round : cap == .square ? .square : .butt)
                    ctx.setLineJoin(join == .round ? .round : join == .bevel ? .bevel : .miter)
                    ctx.strokePath()
                }
            }
        }
        return (buf, w, h)
    }

    private func addPath(_ ops: [PathOp], to ctx: CGContext) {
        for op in ops {
            switch op {
            case .move(let p): ctx.move(to: p)
            case .line(let p): ctx.addLine(to: p)
            case let .quad(t, c): ctx.addQuadCurve(to: t, control: c)
            case let .cubic(t, c1, c2): ctx.addCurve(to: t, control1: c1, control2: c2)
            case .close: ctx.closePath()
            }
        }
    }

    private func cg(_ c: MathColor) -> CGColor {
        CGColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    // MARK: - Ink signature (size-normalized, robust to scale/AA)

    // Deliberately COARSER than the pixel resolution of a small equation (~14–40
    // px of ink): each cell aggregates several pixels, so hand-rasterizer vs
    // NSImage anti-aliasing differences average out instead of being amplified.
    // Still fine enough that a missing element (a fraction bar blanks a whole
    // row band) fails the comparison — verified by ablation.
    private static let gridW = 16, gridH = 8

    private func rgba(_ image: NSImage) -> (px: [UInt8], w: Int, h: Int)? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (buf, w, h) : nil
    }

    /// Covered-pixel count per cell over the ink bounding box, 0–9. Trimming to
    /// the ink box makes it independent of padding and absolute scale.
    private func inkSignature(_ px: [UInt8], _ w: Int, _ h: Int) -> [Int]? {
        func a(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where a(x, y) > 32 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        var sums = [Int](repeating: 0, count: Self.gridW * Self.gridH)
        var counts = sums
        for y in minY...maxY { for x in minX...maxX {
            let gx = min(Self.gridW - 1, (x - minX) * Self.gridW / bw)
            let gy = min(Self.gridH - 1, (y - minY) * Self.gridH / bh)
            let i = gy * Self.gridW + gx
            if a(x, y) > 32 { sums[i] += 1 }
            counts[i] += 1
        } }
        return (0..<sums.count).map { counts[$0] == 0 ? 0 : min(9, sums[$0] * 10 / counts[$0]) }
    }

    private func bandHasInk(_ px: [UInt8], _ w: Int, _ h: Int, from: Double, to: Double) -> Bool {
        let x0 = min(w - 1, max(0, Int(Double(w) * from)))
        let x1 = min(w - 1, max(0, Int(Double(w) * to)))
        for x in x0...x1 { for y in 0..<h where px[(y * w + x) * 4 + 3] > 32 { return true } }
        return false
    }
}
#endif
