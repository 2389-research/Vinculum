#if canImport(AppKit)
import XCTest
import AppKit
@testable import VinculumRender

/// Renders individual equations to tight single-equation PNGs (black ink on
/// white, Latin Modern — Computer Modern's lineage, matching pdfTeX's default),
/// so they can be composed side-by-side with a real TeX render of the same
/// source. Writes to $VINCULUM_CMP_DIR; skipped when unset, so it never runs in
/// normal CI. Companion to scripts/compare-tex.sh.
@MainActor
final class ComparisonGenerator: XCTestCase {

    // Kept in lockstep with scripts/compare-tex.sh (same order, same source).
    static let equations = [
        #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
        #"\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}"#,
        #"\left( \frac{\partial f}{\partial x} \right)_{\! y} \cfrac{1}{1 + \cfrac{1}{x}}"#,
    ]

    func testGenerateComparisonEquations() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_CMP_DIR"] else {
            throw XCTSkip("set VINCULUM_CMP_DIR to generate comparison equations")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Pin Aqua so .light ink resolves to solid black.
        NSApp?.appearance = NSAppearance(named: .aqua)

        for (i, eq) in Self.equations.enumerated() {
            guard let r = MathImageRenderer.rendered(
                latex: eq, display: true, mathTheme: .light, baseSize: 48, font: .latinModern)
            else { throw XCTSkip("unsupported: \(eq)") }
            guard let tiff = r.image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { throw XCTSkip("no png for: \(eq)") }
            try png.write(to: out.appendingPathComponent("vinc-\(i).png"))
        }
    }
}
#endif
