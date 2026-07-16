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

    // The site's own wordmark, dogfooded: √(Vinculum) — the name under a real
    // radical, whose vinculum bar IS the brand, rendered by the engine in STIX
    // Two. Two-tone in the brand palette: cobalt radical, ink/parchment word.
    func testGenerateWordmark() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_CMP_DIR"] else {
            throw XCTSkip("set VINCULUM_CMP_DIR to generate the wordmark")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        NSApp?.appearance = NSAppearance(named: .aqua)

        func c(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
        }
        // (name, radical ink, word color hex, prefersDark)
        let variants: [(String, NSColor, String, Bool)] = [
            ("wordmark-light", c(0x31, 0x5C, 0x9B), "#18212B", false),  // cobalt √ · ink word
            ("wordmark-dark",  c(0x6E, 0xA8, 0xFF), "#F4F0E6", true),   // light cobalt √ · parchment word
        ]
        for (name, ink, word, dark) in variants {
            let latex = "\\sqrt{\\color{\(word)}{\\mathrm{Vinculum}}}"
            let theme = MathTheme(ink: ink, prefersDark: dark)
            guard let r = MathImageRenderer.rendered(
                latex: latex, display: true, mathTheme: theme, baseSize: 44, font: .stixTwo)
            else { throw XCTSkip("unsupported wordmark") }
            guard let tiff = r.image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { throw XCTSkip("no png") }
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }
    }

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
