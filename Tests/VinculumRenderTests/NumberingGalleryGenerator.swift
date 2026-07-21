#if canImport(AppKit)
import XCTest
import Foundation
import AppKit
@testable import VinculumRender
@testable import VinculumLayout

/// Renders the equation-numbering specimen (`alg-numbering.png`): a short document
/// whose display equations auto-number and whose prose `\eqref` references resolve.
@MainActor
final class NumberingGalleryGenerator: XCTestCase {

    func testGenerateNumberingFigure() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the numbering figure")
        }
        let doc = """
        Einstein’s mass–energy equivalence,
        \\[ E = mc^2 \\label{eq:emc} \\]
        and the source-free wave equation,
        \\[ \\frac{\\partial^2 u}{\\partial t^2} = c^2 \\nabla^2 u \\label{eq:wave} \\]
        underpin much of physics. Equation \\eqref{eq:emc} is algebraic, whereas \\eqref{eq:wave} is a PDE; a manually tagged identity \\[ e^{i\\pi} + 1 = 0 \\tag{3'} \\label{eq:euler} \\] keeps its own number, so \\eqref{eq:euler} resolves to it.
        """
        let attr = MathText.attributedString(from: doc, baseFont: .systemFont(ofSize: 20),
                                             numberEquations: true)

        let pageWidth: CGFloat = 680, pad: CGFloat = 28
        let textWidth = pageWidth - pad * 2
        let bounds = attr.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let pageHeight = ceil(bounds.height) + pad * 2 + 28   // slack so the last line isn't clipped

        let image = NSImage(size: CGSize(width: pageWidth, height: pageHeight))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight).fill()
        attr.draw(with: CGRect(x: pad, y: pad, width: textWidth, height: pageHeight - pad * 2),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("no PNG")
        }
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("alg-numbering.png"))
    }
}
#endif
