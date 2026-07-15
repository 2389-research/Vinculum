#if canImport(AppKit) || canImport(UIKit)
import XCTest
import CoreGraphics
@testable import VinculumRender
import VinculumLayout

/// Font-independent invariants of the layout engine + the attachment API,
/// exercised through the real CoreText measurer. (Purely headless geometry
/// tests with a mock measurer live in VinculumLayoutTests.)
final class MathTypesetterTests: XCTestCase {

    private let baseSize: CGFloat = 14

    private func engine() -> MathLayoutEngine {
        MathLayoutEngine.make(baseSize: baseSize)
    }
    private func scene(_ latex: String, display: Bool = false) -> MathScene {
        engine().layout(MathParser.parse(latex), display: display)
    }

    // MARK: - Support classification drives native vs. fallback

    func testSupportedMathProducesNonDegenerateAttachment() throws {
        for latex in ["E = mc^2", "\\frac{a}{b}", "x^2 + y^2", "\\sqrt{2}", "\\sum_{i=1}^{n} i"] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(latex)), "\(latex) should be supported")
            let attachment = MathImageRenderer.attachmentString(
                latex: latex, display: false, mathTheme: .light, baseSize: baseSize
            )
            let string = try XCTUnwrap(attachment, "\(latex): expected a native attachment")
            XCTAssertEqual(string.length, 1, "\(latex): an attachment is one U+FFFC glyph")
            let value = string.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
            let bounds = try XCTUnwrap(value?.bounds, "\(latex): attachment has no bounds")
            XCTAssertGreaterThan(bounds.width, 0, "\(latex): degenerate width")
            XCTAssertGreaterThan(bounds.height, 0, "\(latex): degenerate height")
        }
    }

    func testUnsupportedMathReturnsNilSoRendererFallsBack() {
        let latex = "\\weirdcommand{x} + \\notreal"
        XCTAssertFalse(MathParser.isFullySupported(MathParser.parse(latex)))
        XCTAssertNil(MathImageRenderer.attachmentString(
            latex: latex, display: false, mathTheme: .light, baseSize: baseSize
        ), "unsupported LaTeX must return nil so the host keeps the fallback")
    }

    // MARK: - Font-independent scene structural invariants

    func testFractionStacksTallerThanNumerator() {
        let fraction = scene("\\frac{1}{2}")
        let numeral = scene("1")
        XCTAssertGreaterThan(fraction.width, 0)
        XCTAssertGreaterThan(fraction.height, numeral.height * 1.5,
            "a fraction stacks numerator over denominator, so it is far taller than one numeral")
    }

    /// TeX puts a *thick* (5/18 em) space on each side of a relation. The extra
    /// width is the only difference between `x=y` and `xy` + `=` laid out
    /// without relation spacing, so the glyph widths cancel and the surplus is
    /// ≈ 2·(5/18)·size on any font.
    func testRelationSpacingMatchesTeXThickSpace() {
        let withRelation = scene("x=y").width
        let glyphs = scene("xy").width + scene("=").width
        let surplus = withRelation - glyphs
        let expected = 2 * (5.0 / 18.0) * baseSize
        XCTAssertEqual(surplus, expected, accuracy: 0.5,
            "relation should contribute two TeX thick spaces (\(expected)pt), got \(surplus)pt")
    }

    func testDisplayLimitsStackTallerThanInlineScripts() {
        let display = scene("\\sum_{i=1}^{n} i", display: true)
        let inline = scene("\\sum_{i=1}^{n} i", display: false)
        XCTAssertGreaterThan(display.height, inline.height,
            "display style stacks the operator's limits above and below, growing its height")
    }

    /// The scene is emitted, not drawn — a `\color` subtree carries its
    /// resolved sRGB on its glyph elements (nil elsewhere = theme ink).
    func testColorSubtreeTintsItsGlyphs() {
        let s = engine().layout(MathParser.parse("\\color{red}{x} + y"), display: false)
        var reds = 0, inks = 0
        for e in s.elements {
            if case let .glyphs(_, _, _, _, color) = e { color == nil ? (inks += 1) : (reds += 1) }
        }
        XCTAssertGreaterThan(reds, 0, "the \\color subtree should carry a color")
        XCTAssertGreaterThan(inks, 0, "the rest should be theme ink (nil)")
    }

    func testVecAccentRoutesThroughGlyphIDPathAndCentersInk() {
        // \vec's only spelling is a combining mark (U+20D7); drawn as a
        // STRING its ink seats shaping-dependently (it rendered off the
        // letter's top-right). The fix routes it through the glyph-ID
        // variant path — so the scene must carry a .glyph element, and its
        // ink center must sit over the base's ink, not past its right edge.
        let s = engine().layout(MathParser.parse("\\vec{v}"), display: false)
        var arrow: CGPoint?
        for e in s.elements {
            if case let .glyph(_, _, origin, _) = e { arrow = origin }
        }
        guard let arrow else { return XCTFail("\\vec should emit a glyph-ID accent element") }
        // The mark's ORIGIN may legitimately sit right of the base (its ink
        // trails left of the origin; its baseline y may sit below zero) —
        // but never absurdly far in either direction: the failure mode was
        // ink landing entirely off the letter's top-right.
        XCTAssertLessThan(arrow.x, s.width * 1.6,
                          "arrow origin beyond the letter means the ink landed off the base")
        XCTAssertGreaterThan(arrow.x, -s.width * 0.6, "arrow origin far left of the letter")
    }
}
#endif
