#if canImport(AppKit)
import XCTest
import AppKit
import CoreText
@testable import VinculumRender
import VinculumLayout

/// Generates `07-fonts.png` — the same equations rendered in every bundled
/// math font, labeled — for the CI-published gallery. Run with:
///
///     VINCULUM_GALLERY_DIR=/tmp/vinculum-gallery \
///       swift test --filter FontShowcaseGenerator
@MainActor
final class FontShowcaseGenerator: XCTestCase {

    // 07 (overview): ONE representative equation per font, quick to scan.
    // Letterform detail lives in the sub-specimens: 08 (glyph grid) and
    // 09 (alphabets).
    private static let samples = [
        #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} \qquad \sum_{n=1}^{\infty} \frac{1}{n^s} = \prod_p \frac{1}{1-p^{-s}}"#,
    ]
    // 09 (alphabet specimen): the glyphs where the faces diverge most.
    private static let alphabetSample =
        #"a\, g\, x\, y\, \alpha\, \gamma\, \delta\, \xi\, \partial \qquad \mathcal{L}\, \mathbb{R}\, \mathfrak{g} \qquad \int_0^\infty \oint_C"#

    private static let fonts: [(MathFont, String, String)] = [
        (.latinModern, "Latin Modern Math", "the Computer Modern classic — Vinculum's default"),
        (.termes, "TeX Gyre Termes Math", "Times companion — for Times/serif body text"),
        (.pagella, "TeX Gyre Pagella Math", "Palatino companion — calligraphic warmth"),
        (.stixTwo, "STIX Two Math", "the scientific-publishing standard; ships cut-in kerning data"),
        (.firaMath, "Fira Math", "sans-serif — pairs with SF/Helvetica-style UI text"),
    ]

    /// One-off evidence strip: a handful of glyphs at poster size, where
    /// letterform differences are unmistakable. Not part of the gallery.
    func testGenerateGiantComparison() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_COMPARE_DIR"] else {
            throw XCTSkip("Set VINCULUM_COMPARE_DIR to generate the comparison strip.")
        }
        let sample = #"a\, g\, x\, \pi\, \xi \quad \mathcal{L} \quad \oint"#
        let nameFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 18, nil)
        var rows: [(NSImage, CTLine, CGFloat)] = []
        for (font, name, _) in Self.fonts {
            let r = try XCTUnwrap(MathImageRenderer.rendered(
                latex: sample, display: true, mathTheme: .light, baseSize: 54, font: font))
            let attr = NSAttributedString(string: name, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: nameFont])
            let line = CTLineCreateWithAttributedString(attr)
            var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &a, &d, &l)
            rows.append((r.image, line, a + d))
        }
        let margin: CGFloat = 20, gap: CGFloat = 14
        let width = (rows.map { $0.0.size.width }.max() ?? 0) + margin * 2
        let height = rows.reduce(margin) { $0 + $1.2 + 4 + $1.0.size.height + gap } + margin - gap
        let scale: CGFloat = 2
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = nil }
        var y = height - margin
        for (image, line, labelH) in rows {
            y -= labelH
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.textPosition = CGPoint(x: margin, y: y)
            CTLineDraw(line, ctx)
            y -= 4 + image.size.height
            image.draw(in: CGRect(x: margin, y: y, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            y -= gap
        }
        let img = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: dir).appendingPathComponent("giant-compare.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("Wrote \(url.path)")
    }

    /// Side-by-side grid: fonts as columns, one glyph per row, so identical
    /// characters sit directly next to each other — where the four designs
    /// visibly diverge. Published to the gallery as 08-font-glyphs.png.
    func testGenerateSideBySide() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"]
            ?? ProcessInfo.processInfo.environment["VINCULUM_COMPARE_DIR"] else {
            throw XCTSkip("Set VINCULUM_GALLERY_DIR to generate the side-by-side glyph grid.")
        }
        let glyphRows = [#"a"#, #"g"#, #"x"#, #"\pi"#, #"\xi"#, #"\mathcal{L}"#,
                         #"\oint"#, #"\sqrt{x}"#, #"\sum"#]
        let headers = ["Latin Modern", "Termes", "Pagella", "STIX Two", "Fira Math"]
        let headerFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 16, nil)

        func line(_ t: String) -> (CTLine, CGFloat, CGFloat) {
            let attr = NSAttributedString(string: t, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: headerFont])
            let l = CTLineCreateWithAttributedString(attr)
            var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(l, &a, &d, &lead))
            return (l, w, a + d)
        }

        // Render every cell.
        var cells: [[NSImage]] = []   // [row][col]
        for glyph in glyphRows {
            var row: [NSImage] = []
            for (font, _, _) in Self.fonts {
                let r = try XCTUnwrap(MathImageRenderer.rendered(
                    latex: glyph, display: true, mathTheme: .light, baseSize: 44, font: font))
                row.append(r.image)
            }
            cells.append(row)
        }
        let headerLines = headers.map(line)

        let margin: CGFloat = 24, colGap: CGFloat = 28, rowGap: CGFloat = 10
        var colW = [CGFloat](repeating: 0, count: headers.count)
        for c in headers.indices {
            colW[c] = max(headerLines[c].1, cells.map { $0[c].size.width }.max() ?? 0)
        }
        let rowH = cells.map { row in row.map(\.size.height).max() ?? 0 }
        let headerH = headerLines.map(\.2).max() ?? 0
        let width = margin * 2 + colW.reduce(0, +) + colGap * CGFloat(headers.count - 1)
        let height = margin * 2 + headerH + 12 + rowH.reduce(0, +) + rowGap * CGFloat(rowH.count - 1)

        let scale: CGFloat = 2
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = nil }

        // Column headers (centered over each column).
        var colX = [CGFloat](); var x = margin
        for c in headers.indices { colX.append(x); x += colW[c] + colGap }
        var y = height - margin - headerH
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for c in headers.indices {
            ctx.textPosition = CGPoint(x: colX[c] + (colW[c] - headerLines[c].1) / 2, y: y)
            CTLineDraw(headerLines[c].0, ctx)
        }
        y -= 12
        // Cells: each glyph row, horizontally centered per column.
        for (r, row) in cells.enumerated() {
            y -= rowH[r]
            for c in headers.indices {
                let img = row[c]
                let cx = colX[c] + (colW[c] - img.size.width) / 2
                let cy = y + (rowH[r] - img.size.height) / 2
                img.draw(in: CGRect(x: cx, y: cy, width: img.size.width, height: img.size.height),
                         from: .zero, operation: .sourceOver, fraction: 1)
            }
            y -= rowGap
        }

        let img = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: dir).appendingPathComponent("08-font-glyphs.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("Wrote \(url.path)")
    }

    /// 09-font-alphabets.png — the letterform sub-specimen: italic
    /// alphabet, Greek, script/blackboard/fraktur, and the integrals, one
    /// labeled line per font.
    func testGenerateAlphabetSpecimen() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("Set VINCULUM_GALLERY_DIR to generate the alphabet specimen.")
        }
        let nameFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 14, nil)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 18, nil)
        func line(_ t: String, _ f: CTFont) -> (CTLine, CGFloat, CGFloat) {
            let attr = NSAttributedString(string: t, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: f])
            let l = CTLineCreateWithAttributedString(attr)
            var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(l, &a, &d, &lead))
            return (l, w, a + d)
        }
        var rows: [((CTLine, CGFloat, CGFloat), NSImage)] = []
        for (font, name, _) in Self.fonts {
            let r = try XCTUnwrap(MathImageRenderer.rendered(
                latex: Self.alphabetSample, display: true, mathTheme: .light,
                baseSize: 22, font: font))
            rows.append((line(name, nameFont), r.image))
        }
        let title = line("Where the faces differ — alphabets, scripts, integrals", titleFont)
        let margin: CGFloat = 24, rowGap: CGFloat = 16, labelGap: CGFloat = 5
        var width = title.1 + margin * 2
        var height = margin * 2 + title.2 + rowGap
        for (label, image) in rows {
            width = max(width, margin * 2 + max(image.size.width, label.1))
            height += label.2 + labelGap + image.size.height + rowGap
        }
        let scale: CGFloat = 2
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = nil }
        var y = height - margin - title.2
        ctx.textPosition = CGPoint(x: margin, y: y)
        CTLineDraw(title.0, ctx)
        y -= rowGap
        for (label, image) in rows {
            y -= label.2
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.textPosition = CGPoint(x: margin, y: y)
            CTLineDraw(label.0, ctx)
            y -= labelGap + image.size.height
            image.draw(in: CGRect(x: margin, y: y, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            y -= rowGap
        }
        let img = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: dir).appendingPathComponent("09-font-alphabets.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("Wrote \(url.path)")
    }

    func testGenerateFontShowcase() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("Set VINCULUM_GALLERY_DIR to generate the font showcase poster.")
        }
        let scale: CGFloat = 2
        let margin: CGFloat = 24, rowGap: CGFloat = 18, labelGap: CGFloat = 6

        func textLine(_ s: String, _ font: CTFont, _ color: NSColor) -> (CTLine, CGFloat, CGFloat) {
            let attr = NSAttributedString(string: s, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color])
            let l = CTLineCreateWithAttributedString(attr)
            var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(l, &a, &d, &lead))
            return (l, w, a + d)
        }

        let nameFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 15, nil)
        let blurbFont = CTFontCreateWithName("HelveticaNeue" as CFString, 12, nil)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 20, nil)

        // Render every font's sample first to size the canvas.
        struct FontRow {
            let name: (CTLine, CGFloat, CGFloat)
            let blurb: (CTLine, CGFloat, CGFloat)
            let images: [NSImage]
        }
        var rows: [FontRow] = []
        for (font, name, blurb) in Self.fonts {
            var images: [NSImage] = []
            for sample in Self.samples {
                let rendered = try XCTUnwrap(
                    MathImageRenderer.rendered(latex: sample, display: true,
                                               mathTheme: .light, baseSize: 22, font: font),
                    "showcase sample failed to render in \(name)")
                images.append(rendered.image)
            }
            rows.append(FontRow(name: textLine(name, nameFont, .black),
                                blurb: textLine("— " + blurb, blurbFont, NSColor(white: 0.42, alpha: 1)),
                                images: images))
        }
        let title = textLine("One engine, five fonts (plus any OTF with a MATH table)", titleFont, .black)

        var width = title.1 + margin * 2
        var height = margin + title.2 + rowGap
        let lineGap: CGFloat = 8
        for row in rows {
            let imgW = row.images.map(\.size.width).max() ?? 0
            let imgH = row.images.map(\.size.height).reduce(0, +)
                + lineGap * CGFloat(max(0, row.images.count - 1))
            width = max(width, margin * 2 + max(imgW, row.name.1 + 8 + row.blurb.1))
            height += row.name.2 + labelGap + imgH + rowGap
        }
        height += margin - rowGap

        let pxW = Int(ceil(width * scale)), pxH = Int(ceil(height * scale))
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = ns
        defer { NSGraphicsContext.current = nil }

        var y = height - margin - title.2
        ctx.textPosition = CGPoint(x: margin, y: y)
        CTLineDraw(title.0, ctx)
        y -= rowGap
        for (i, row) in rows.enumerated() {
            if i > 0 {   // hairline separator: rows scan as distinct sections
                ctx.setFillColor(CGColor(gray: 0.88, alpha: 1))
                ctx.fill(CGRect(x: margin, y: y + rowGap / 2, width: width - margin * 2, height: 0.5))
            }
            y -= row.name.2
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.textPosition = CGPoint(x: margin, y: y)
            CTLineDraw(row.name.0, ctx)
            ctx.textPosition = CGPoint(x: margin + row.name.1 + 8, y: y)
            CTLineDraw(row.blurb.0, ctx)
            y -= labelGap
            for image in row.images {
                y -= image.size.height
                image.draw(in: CGRect(x: margin, y: y,
                                      width: image.size.width, height: image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1)
                y -= lineGap
            }
            y += lineGap
            y -= rowGap
        }

        let image = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: dir).appendingPathComponent("07-fonts.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("Wrote \(url.path)")
    }
}
#endif
