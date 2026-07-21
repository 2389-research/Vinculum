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

/// Renders the chemistry specimen (`cmd-chem.png`): mhchem `\ce{…}` formulas,
/// ions, hydrates, and reaction equations (including an equilibrium arrow).
final class MHChemGalleryGenerator: XCTestCase {

    func testGenerateChemFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the chemistry figure")
        }
        let font: MathFont = .latinModern
        let engine = MathLayoutEngine.make(font: font, baseSize: 24)

        let items: [(String, String)] = [
            ("Formulas & ions", #"\ce{H2O} \quad \ce{H2SO4} \quad \ce{Ca(OH)2} \quad \ce{SO4^2-} \quad \ce{Fe^3+}"#),
            ("Combustion", #"\ce{CH4 + 2O2 -> CO2 + 2H2O}"#),
            ("Haber process (equilibrium)", #"\ce{N2 + 3H2 <=> 2NH3}"#),
            ("Hydrate & conditional arrow", #"\ce{CuSO4 * 5H2O} \qquad \ce{CaCO3 ->[\Delta] CaO + CO2}"#),
        ]
        let scenes = items.map { (title: $0.0, scene: engine.layout(MathParser.parse($0.1), display: true)) }

        let margin: CGFloat = 34, rowGap: CGFloat = 30, titleH: CGFloat = 42, capH: CGFloat = 28
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let capFont = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Chemistry — mhchem \\ce{…}: auto-subscripts, charges, states, reaction arrows",
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
            MathSceneRenderer.draw(s.scene, theme: .light, in: ctx, at: CGPoint(x: margin, y: y), font: font)
            y -= s.scene.descent + rowGap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: dir).appendingPathComponent("cmd-chem.png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw XCTSkip("no image") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
