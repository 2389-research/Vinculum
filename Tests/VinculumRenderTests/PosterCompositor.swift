#if canImport(AppKit)
import XCTest
import AppKit
import CoreText
import CoreGraphics
@testable import VinculumRender
import VinculumLayout

/// Shared poster compositor for the gallery generators: labeled rows (LaTeX
/// source in gray Menlo beside its native render), grouped under optional
/// section headers, written as a 2× PNG. Extracted from `GalleryGenerator`
/// so `ArchitectureGalleryGenerator` can emit the same house style.
@MainActor
enum PosterCompositor {

    static func poster(to url: URL, title: String,
                       sections: [(String, [String])],
                       font: MathFont = .latinModern,
                       baseSize: CGFloat = 22) throws {
        let engine = MathLayoutEngine.make(font: font, baseSize: baseSize)
        let labelFont = CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let headerFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 15, nil)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 20, nil)
        let gray = PlatformColor(white: 0.45, alpha: 1)
        let ink = PlatformColor.black
        let accent = PlatformColor(red: 0.20, green: 0.47, blue: 0.96, alpha: 1)

        struct Row { let scene: MathScene; let labelLine: CTLine?; let labelW: CGFloat; let labelAsc: CGFloat; let labelDesc: CGFloat }

        func line(_ s: String, _ font: CTFont) -> (CTLine, CGFloat, CGFloat, CGFloat) {
            let attr = NSAttributedString(string: s, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true])
            let l = CTLineCreateWithAttributedString(attr)
            var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(l, &a, &d, &lead))
            return (l, w, a, d)
        }

        // Pre-layout every row + section header.
        struct Section { let header: (CTLine, CGFloat, CGFloat, CGFloat)?; let rows: [Row] }
        var built: [Section] = []
        var labelColW: CGFloat = 0, boxColW: CGFloat = 0
        for (header, exprs) in sections {
            var rows: [Row] = []
            for latex in exprs {
                // Expand \newcommand macros the way a host does.
                // collectDefinitions scans math SEGMENTS, so wrap the raw
                // latex as a $$…$$ block first.
                let table = MathMacros.collectDefinitions(from: "$$" + latex + "$$")
                let expanded = MathMacros.expand(latex, with: table)
                let scene = engine.layout(MathParser.parse(expanded), display: true)
                let (ll, lw, la, ld) = line(latex, labelFont)
                rows.append(Row(scene: scene, labelLine: ll, labelW: lw, labelAsc: la, labelDesc: ld))
                labelColW = max(labelColW, lw)
                boxColW = max(boxColW, scene.width)
            }
            let h = header.isEmpty ? nil : line(header, headerFont)
            built.append(Section(header: h, rows: rows))
        }

        let margin: CGFloat = 28, gutter: CGFloat = 40, rowGap: CGFloat = 22, sectionGap: CGFloat = 26
        let (titleLine, titleW, titleAsc, titleDesc) = line(title, titleFont)
        let width = margin * 2 + max(labelColW + gutter + boxColW, titleW)

        // Total height.
        var height = margin + (titleAsc + titleDesc) + sectionGap
        for s in built {
            if let h = s.header { height += h.2 + h.3 + rowGap * 0.6 }
            for r in s.rows { height += max(r.scene.height, r.labelAsc + r.labelDesc) + rowGap }
            height += sectionGap
        }
        height += margin - rowGap

        // Bitmap at 2x.
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("no context")
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(PlatformColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        func draw(_ l: CTLine, x: CGFloat, baseline y: CGFloat, color: PlatformColor) {
            ctx.saveGState(); ctx.setFillColor(resolvedCGColor(color)); ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(l, ctx); ctx.restoreGState()
        }

        // Draw top-down (y-up coords: start near the top = height - margin).
        var y = height - margin - titleAsc
        draw(titleLine, x: margin, baseline: y, color: accent)
        y -= titleDesc + sectionGap

        let boxX = margin + labelColW + gutter
        for s in built {
            if let h = s.header {
                y -= h.2
                draw(h.0, x: margin, baseline: y, color: ink)
                y -= h.3 + rowGap * 0.6
            }
            for r in s.rows {
                let rowAsc = max(r.scene.ascent, r.labelAsc)
                let rowDesc = max(r.scene.descent, r.labelDesc)
                y -= rowAsc
                // Label right-aligned in its column.
                if let ll = r.labelLine {
                    draw(ll, x: margin + (labelColW - r.labelW), baseline: y, color: gray)
                }
                // Math left-aligned, baseline shared with the label.
                MathSceneRenderer.draw(r.scene, theme: .light, in: ctx, at: CGPoint(x: boxX, y: y), font: font)
                y -= rowDesc + rowGap
            }
            y -= sectionGap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw XCTSkip("no image")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
