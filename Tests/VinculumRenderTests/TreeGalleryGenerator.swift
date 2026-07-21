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

/// Renders the syntax-tree specimen (`cmd-tree.png`): a linguistics parse tree and a
/// small derivation, drawn as labelled nodes joined by edges.
final class TreeGalleryGenerator: XCTestCase {

    func testGenerateTreeFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the tree figure")
        }
        let font: MathFont = .latinModern
        let engine = MathLayoutEngine.make(font: font, baseSize: 20)

        let items: [(String, String)] = [
            ("A syntactic parse tree",
             #"\Tree [.S [.NP [.D \text{the} ] [.N \text{cat} ] ] [.VP [.V \text{saw} ] [.NP [.D \text{a} ] [.N \text{bird} ] ] ] ]"#),
            ("An expression tree",
             #"\Tree [.{+} [.{\times} a b ] [.{\times} c d ] ]"#),
        ]
        let scenes = items.map { (title: $0.0, scene: engine.layout(MathParser.parse($0.1), display: true)) }

        let margin: CGFloat = 34, rowGap: CGFloat = 48, titleH: CGFloat = 42, capH: CGFloat = 30
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let capFont = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Syntax trees — \\Tree [.S [.NP … ] [.VP … ] ] (qtree)",
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
            MathSceneRenderer.draw(s.scene, theme: .light, in: ctx, at: CGPoint(x: margin + 20, y: y), font: font)
            y -= s.scene.descent + rowGap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: dir).appendingPathComponent("cmd-tree.png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw XCTSkip("no image") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
