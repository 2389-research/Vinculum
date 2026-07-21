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

/// Renders the physics-package specimen (`cmd-physics.png`): Dirac notation,
/// derivatives, and bracket macros.
final class PhysicsGalleryGenerator: XCTestCase {

    func testGeneratePhysicsFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the physics figure")
        }
        let font: MathFont = .latinModern
        let engine = MathLayoutEngine.make(font: font, baseSize: 21)

        let rows: [(String, String)] = [
            (#"\braket{\phi}{\psi}"#, "inner product"),
            (#"\ketbra{\psi}{\phi}"#, "outer product (projector)"),
            (#"\mel{\phi}{\hat{H}}{\psi}"#, "matrix element"),
            (#"\expval{\hat{H}}{\psi}"#, "expectation value"),
            (#"\dv{f}{x} \qquad \dv[2]{f}{x}"#, "ordinary derivatives"),
            (#"\pdv{f}{x} \qquad \pdv{f}{x}{y}"#, "partial & mixed partial"),
            (#"\comm{\hat{A}}{\hat{B}} = \hat{A}\hat{B} - \hat{B}\hat{A}"#, "commutator"),
            (#"\abs{\psi}^2 \qquad \norm{\psi}"#, "modulus & norm"),
            (#"\grad \phi \qquad \curl \vec{F} \qquad \laplacian \phi"#, "vector operators"),
        ]
        let scenes = rows.map { (src: $0.0, cap: $0.1, scene: engine.layout(MathParser.parse($0.0), display: true)) }

        let margin: CGFloat = 34, rowGap: CGFloat = 24, titleH: CGFloat = 44
        let renderX: CGFloat = margin + 8
        let capX: CGFloat = 470
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let capFont = CTFontCreateWithName("Helvetica" as CFString, 14, nil)

        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Physics — Dirac notation, derivatives, brackets",
            attributes: [.font: titleFont, .foregroundColor: PlatformColor.systemBlue]))

        let width: CGFloat = 760
        var height = margin + titleH
        for s in scenes { height += max(s.scene.height, 30) + rowGap }
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
            let rowH = max(s.scene.height, 30)
            let mid = y - rowH / 2
            let baseline = mid - s.scene.height / 2 + s.scene.descent
            MathSceneRenderer.draw(s.scene, theme: .light, in: ctx, at: CGPoint(x: renderX, y: baseline), font: font)

            let cap = CTLineCreateWithAttributedString(NSAttributedString(
                string: s.cap, attributes: [.font: capFont, .foregroundColor: PlatformColor.lightGray]))
            ctx.textPosition = CGPoint(x: capX, y: mid - 5)
            CTLineDraw(cap, ctx)

            y -= rowH + rowGap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: dir).appendingPathComponent("cmd-physics.png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw XCTSkip("no image") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
