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

/// Renders the siunitx specimen (`cmd-units.png`): numbers, angles, quantities, units.
final class SIUnitxGalleryGenerator: XCTestCase {

    func testGenerateUnitsFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the units figure")
        }
        let font: MathFont = .latinModern
        let engine = MathLayoutEngine.make(font: font, baseSize: 21)

        let rows: [(String, String)] = [
            (#"\num{1.5e3}"#, "scientific notation"),
            (#"\num{12345.678}"#, "digit grouping"),
            (#"\ang{45;30;15}"#, "degrees; minutes; seconds"),
            (#"\SI{9.8}{m/s^2}"#, "quantity with units"),
            (#"\SI{299792458}{m/s}"#, "grouped quantity"),
            (#"\qty{1.38e-23}{J/K}"#, "v3 spelling (\\qty)"),
            (#"\si{kg.m.s^{-1}}"#, "unit product & powers"),
            (#"\unit{\kilo\gram}"#, "unit macros"),
            (#"\SI{25}{\degreeCelsius}"#, "named unit"),
            (#"\si{\micro\metre}"#, "prefix + unit"),
        ]
        let scenes = rows.map { (src: $0.0, cap: $0.1, scene: engine.layout(MathParser.parse($0.0), display: false)) }

        let margin: CGFloat = 34, rowGap: CGFloat = 26, titleH: CGFloat = 44
        let srcX: CGFloat = margin
        let renderX: CGFloat = 300
        let capX: CGFloat = 560
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let monoFont = CTFontCreateWithName("Menlo" as CFString, 14, nil)
        let capFont = CTFontCreateWithName("Helvetica" as CFString, 14, nil)

        let title = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Units — siunitx: \\num, \\ang, \\si / \\unit, \\SI / \\qty",
            attributes: [.font: titleFont, .foregroundColor: PlatformColor.systemBlue]))

        let rowH: CGFloat = 40
        let width: CGFloat = 820
        let height = margin + titleH + CGFloat(scenes.count) * (rowH + rowGap) + margin

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
            let mid = y - rowH / 2
            let src = CTLineCreateWithAttributedString(NSAttributedString(
                string: s.src, attributes: [.font: monoFont, .foregroundColor: PlatformColor.darkGray]))
            ctx.textPosition = CGPoint(x: srcX, y: mid - 5)
            CTLineDraw(src, ctx)

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
                URL(fileURLWithPath: dir).appendingPathComponent("cmd-units.png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw XCTSkip("no image") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
