import XCTest
import Foundation
@testable import VinculumLayout

/// The platform-free SVG renderer — server-side math. Headless (runs on
/// Linux, like the layout it renders).
final class MathSVGRendererTests: XCTestCase {

    private func scene(_ latex: String, display: Bool = true) -> MathScene {
        standardMockEngine().layout(MathParser.parse(latex), display: display)
    }

    func testTextRunsBecomeBaselineTextElements() {
        let svg = MathSVGRenderer.svg(for: scene("x + y"))
        XCTAssertTrue(svg.contains("<svg xmlns="))
        XCTAssertEqual(svg.components(separatedBy: "<text ").count - 1, 3, "x, +, y")
        XCTAssertTrue(svg.contains(#"font-size="10""#))
        XCTAssertTrue(svg.contains("𝑥"))
    }

    func testFractionBarBecomesARect() {
        let svg = MathSVGRenderer.svg(for: scene(#"\frac{a}{b}"#))
        XCTAssertTrue(svg.contains("<rect "), "the fraction bar is a rect")
    }

    func testHeadlessRadicalBecomesAPath() {
        let svg = MathSVGRenderer.svg(for: scene(#"\sqrt{x}"#))
        XCTAssertTrue(svg.contains("<path d=\"M "), "the polyline surd strokes a path")
        XCTAssertTrue(svg.contains("stroke-linecap"))
    }

    func testColorOverridesInk() {
        let svg = MathSVGRenderer.svg(for: scene(#"\color{red}{x} + y"#), ink: "#123456")
        XCTAssertTrue(svg.contains("fill=\"#123456\""), "theme ink on uncolored elements")
        let textFills = svg.components(separatedBy: "<text ").dropFirst()
        XCTAssertFalse(textFills.allSatisfy { $0.contains("#123456") },
                       "the \\color'd x carries its own fill, not the ink")
    }

    func testEscapesMarkupCharacters() {
        let svg = MathSVGRenderer.svg(for: scene("a < b"))
        XCTAssertTrue(svg.contains("&lt;"))
        XCTAssertFalse(svg.contains("> <text x") == false && svg.contains("<b"),
                       "raw '<' must never reach markup")
    }

    func testEmbeddedFontEmitsFontFace() {
        let bytes = Data([0x4F, 0x54, 0x54, 0x4F])   // "OTTO"
        let svg = MathSVGRenderer.svg(for: scene("x"), embeddedFont: bytes)
        XCTAssertTrue(svg.contains("@font-face"))
        XCTAssertTrue(svg.contains("data:font/otf;base64,T1RUTw=="))
    }

    func testGlyphIDElementsAreSkippedWithoutOutlineProvider() {
        var s = scene("x")
        s = MathScene(width: s.width, ascent: s.ascent, descent: s.descent,
                      elements: s.elements + [.glyph(id: 42, size: 10, origin: .zero, color: nil)])
        let svg = MathSVGRenderer.svg(for: s)
        XCTAssertTrue(svg.contains("skipped .glyph(id:)"))
    }

    func testGlyphIDElementsDrawAsPathsWithOutlineProvider() {
        var s = scene("x")
        s = MathScene(width: s.width, ascent: s.ascent, descent: s.descent,
                      elements: s.elements + [.glyph(id: 42, size: 10, origin: .zero, color: nil)])
        // A trivial outline provider: a unit triangle for any glyph.
        let outlines: GlyphOutlineProvider = { _, _ in
            [.move(CGPoint(x: 0, y: 0)), .line(CGPoint(x: 5, y: 0)),
             .cubic(to: CGPoint(x: 0, y: 5), control1: CGPoint(x: 3, y: 2), control2: CGPoint(x: 1, y: 4)),
             .close]
        }
        let svg = MathSVGRenderer.svg(for: s, outlines: outlines)
        XCTAssertFalse(svg.contains("skipped .glyph(id:)"))
        XCTAssertTrue(svg.contains(" C "), "the cubic outline op becomes an SVG C command")
    }

    func testViewBoxMatchesSceneMetricsPlusPadding() {
        let s = scene("x")
        let svg = MathSVGRenderer.svg(for: s, padding: 2)
        XCTAssertTrue(svg.contains(#"viewBox="0 0 14 14""#),
                      "10-wide 10-tall mock cell + 2pt padding each side")
    }
}
