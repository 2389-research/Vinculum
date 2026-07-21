import XCTest
import Foundation
@testable import VinculumLayout
@testable import VinculumRender
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#if canImport(AppKit)
import AppKit
#endif

/// Renders the automatic-line-breaking specimen (`alg-linebreak.png`): long
/// equations wrapped to a width budget, with the budget drawn as a faint rule so
/// you can see each line breaks at an operator/relation and stays within it.
final class LineBreakGalleryGenerator: XCTestCase {

    func testGenerateLineBreakFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the line-break figure")
        }
        let font: MathFont = .latinModern
        let baseSize: CGFloat = 22
        let engine = MathLayoutEngine.make(font: font, baseSize: baseSize)

        struct Row { let latex: String; let maxWidth: CGFloat }
        let rows = [
            Row(latex: #"f(x) = a_0 + a_1 x + a_2 x^2 + a_3 x^3 + a_4 x^4 + a_5 x^5 + a_6 x^6"#, maxWidth: 360),
            Row(latex: #"S = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15"#, maxWidth: 300),
            Row(latex: #"\nabla \cdot E = \rho / \varepsilon_0 \quad \text{and} \quad \nabla \times B = \mu_0 J + \mu_0 \varepsilon_0 \partial_t E"#, maxWidth: 420),
        ]

        let scenes = rows.map { (row: $0, scene: engine.layout(MathParser.parse($0.latex), display: true, maxWidth: $0.maxWidth)) }

        let margin: CGFloat = 32, rowGap: CGFloat = 34, titleH: CGFloat = 40
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let titleStr = "Automatic line breaking — wraps at operators & relations, within a width budget"
        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: titleStr, attributes: [.font: titleFont, .foregroundColor: PlatformColor.systemBlue]))
        let titleW = CGFloat(CTLineGetTypographicBounds(title, nil, nil, nil))
        let contentW = max(scenes.map { max($0.scene.width, $0.row.maxWidth) }.max() ?? 400, titleW)
        let width = margin * 2 + contentW
        var height = margin + titleH
        for s in scenes { height += s.scene.height + rowGap }
        height += margin

        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("no context")
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(PlatformColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Title.
        ctx.textPosition = CGPoint(x: margin, y: height - margin)
        CTLineDraw(title, ctx)

        var y = height - margin - titleH
        for s in scenes {
            y -= s.scene.ascent
            // Faint width-budget rule.
            ctx.saveGState()
            ctx.setStrokeColor(PlatformColor.systemGray.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: margin + s.row.maxWidth, y: y + s.scene.ascent + 6))
            ctx.addLine(to: CGPoint(x: margin + s.row.maxWidth, y: y - s.scene.descent - 6))
            ctx.strokePath()
            ctx.restoreGState()
            MathSceneRenderer.draw(s.scene, theme: .light, in: ctx, at: CGPoint(x: margin, y: y), font: font)
            y -= s.scene.descent + rowGap
        }

        let url = URL(fileURLWithPath: dir).appendingPathComponent("alg-linebreak.png")
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw XCTSkip("no image")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
