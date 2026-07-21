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

/// Renders the function-plot specimen (`cmd-plot.png`): a few `\begin{axis}` plots.
final class PlotGalleryGenerator: XCTestCase {

    func testGeneratePlotFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the plot figure")
        }
        let font: MathFont = .latinModern
        let engine = MathLayoutEngine.make(font: font, baseSize: 20)

        let items: [(String, String)] = [
            ("Polynomials", #"\begin{axis}[domain=-3:3] \addplot{x^2}; \addplot{x^3 - 3*x}; \end{axis}"#),
            ("Trig & decay", #"\begin{axis}[domain=-6.5:6.5, samples=200] \addplot{sin(x)}; \addplot{cos(x)/2}; \end{axis}"#),
            ("A bell curve", #"\begin{axis}[domain=-3:3, samples=200] \addplot{exp(-x^2)}; \end{axis}"#),
        ]
        let scenes = items.map { (title: $0.0, scene: engine.layout(MathParser.parse($0.1), display: true)) }

        let margin: CGFloat = 34, colGap: CGFloat = 40, titleH: CGFloat = 44, capH: CGFloat = 26
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let capFont = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Function plots — \\begin{axis}\\addplot{expr}: sampled curves, auto-ranged axes",
            attributes: [.font: titleFont, .foregroundColor: PlatformColor.systemBlue]))
        let titleW = CGFloat(CTLineGetTypographicBounds(title, nil, nil, nil))

        // Lay the three plots in a row.
        let rowW = scenes.map(\.scene.width).reduce(0, +) + colGap * CGFloat(scenes.count - 1)
        let rowH = scenes.map(\.scene.height).max() ?? 200
        let width = max(margin * 2 + rowW, margin * 2 + titleW)
        let height = margin + titleH + capH + rowH + margin

        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("no context")
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(PlatformColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.textPosition = CGPoint(x: margin, y: height - margin)
        CTLineDraw(title, ctx)

        var x = margin
        let capBaseline = height - margin - titleH - 6
        let plotBaseline = capBaseline - capH - (rowH - (scenes.map(\.scene.ascent).max() ?? 0))
        for s in scenes {
            let cap = CTLineCreateWithAttributedString(NSAttributedString(
                string: s.title, attributes: [.font: capFont, .foregroundColor: PlatformColor.darkGray]))
            ctx.textPosition = CGPoint(x: x, y: capBaseline)
            CTLineDraw(cap, ctx)
            MathSceneRenderer.draw(s.scene, theme: .light, in: ctx, at: CGPoint(x: x, y: plotBaseline), font: font)
            x += s.scene.width + colGap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: dir).appendingPathComponent("cmd-plot.png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw XCTSkip("no image") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
