#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import VinculumRender
import VinculumLayout

/// The SVG renderer draws `.glyph(id:)` elements (ssty scripts, delimiter
/// variants) as filled `<path>`s when given an outline provider — and skips
/// them (with a comment) without one.
final class SVGGlyphOutlineTests: XCTestCase {

    private func scriptScene() -> MathScene {
        // x^2 on Apple emits the base x as text and the ssty "2" as .glyph(id:).
        MathLayoutEngine.make(font: .latinModern, baseSize: 24)
            .layout(MathParser.parse(#"x^{2}"#))
    }

    func testGlyphElementsSkippedWithoutProvider() {
        let svg = MathSVGRenderer.svg(for: scriptScene())
        XCTAssertTrue(svg.contains("skipped .glyph(id:)"), "no provider → the script is skipped")
        XCTAssertFalse(svg.contains("fill=\"#000000\"/>\n"), "and no filled glyph path emitted")
    }

    func testGlyphElementsBecomeFilledPathsWithProvider() {
        let outlines = CoreTextGlyphOutlineProvider.make(font: .latinModern)
        let svg = MathSVGRenderer.svg(for: scriptScene(), outlines: outlines)
        XCTAssertFalse(svg.contains("skipped .glyph(id:)"), "the ssty script must be drawn now")
        // A filled path (fill set, no stroke) is the glyph outline; several
        // curve ops prove it's a real glyph, not a rule.
        XCTAssertTrue(svg.contains("<path d=\"M"), "a path is emitted for the glyph")
        XCTAssertTrue(svg.contains(" C "), "glyph outline carries cubic segments")
        XCTAssertTrue(svg.contains("<text"), "the base x is still a text run")
    }

    func testProducesWellFormedXML() throws {
        let svg = MathSVGRenderer.svg(for: scriptScene(),
                                      outlines: CoreTextGlyphOutlineProvider.make(font: .latinModern))
        #if canImport(Foundation.NSXMLParser) || canImport(FoundationXML) || canImport(AppKit)
        let parser = XMLParser(data: Data(svg.utf8))
        XCTAssertTrue(parser.parse(), "SVG must be well-formed XML: \(parser.parserError?.localizedDescription ?? "")")
        #endif
    }
}
#endif
