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

/// Renders the commutative-diagram specimen (`cmd-diagrams.png`): a few classic
/// `\begin{CD}` diagrams — squares and a short exact sequence.
final class CDGalleryGenerator: XCTestCase {

    func testGenerateCDFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the CD figure")
        }
        let font: MathFont = .latinModern
        let engine = MathLayoutEngine.make(font: font, baseSize: 26)

        let items: [(String, String)] = [
            ("A commuting square", #"\begin{CD} A @>f>> B \\ @VgVV @VVhV \\ C @>>k> D \end{CD}"#),
            ("A short exact sequence", #"\begin{CD} 0 @>>> A @>f>> B @>g>> C @>>> 0 \end{CD}"#),
            ("Isomorphism & equality edges", #"\begin{CD} X @>\sim>> Y \\ @| @VVV \\ X @>>\varphi> Z \end{CD}"#),
        ]
        let scenes = items.map { (title: $0.0, scene: engine.layout(MathParser.parse($0.1), display: true)) }

        let margin: CGFloat = 34, rowGap: CGFloat = 40, titleH: CGFloat = 42, capH: CGFloat = 30
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let capFont = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Commutative diagrams — \\begin{CD}: objects joined by labelled arrows",
            attributes: [.font: titleFont, .foregroundColor: PlatformColor.systemBlue]))
        let titleW = CGFloat(CTLineGetTypographicBounds(title, nil, nil, nil))

        let contentW = max(scenes.map(\.scene.width).max() ?? 300, titleW)
        let width = margin * 2 + contentW
        var height = margin + titleH
        for s in scenes { height += capH + s.scene.height + rowGap }
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

        ctx.textPosition = CGPoint(x: margin, y: height - margin)
        CTLineDraw(title, ctx)

        var y = height - margin - titleH
        for s in scenes {
            let cap = CTLineCreateWithAttributedString(NSAttributedString(
                string: s.title, attributes: [.font: capFont, .foregroundColor: PlatformColor.darkGray]))
            ctx.textPosition = CGPoint(x: margin, y: y - 16)
            CTLineDraw(cap, ctx)
            y -= capH
            y -= s.scene.ascent
            MathSceneRenderer.draw(s.scene, theme: .light, in: ctx,
                                   at: CGPoint(x: margin + 20, y: y), font: font)
            y -= s.scene.descent + rowGap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: dir).appendingPathComponent("cmd-diagrams.png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw XCTSkip("no image") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
