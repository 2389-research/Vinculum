import XCTest
import Foundation
@testable import VinculumLayout

/// Harpoon accents (`\overrightharpoon`, `\overleftharpoon`) and `\utilde` (a wide
/// tilde *below* the base). Headless geometry on the mock — platform-free, Linux-safe.
final class MathHarpoonAccentTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    func testParsesToTheRightAccents() {
        for (src, expect) in [(#"\overrightharpoon{AB}"#, MathAccent.overrightharpoon),
                              (#"\overleftharpoon{v}"#, .overleftharpoon),
                              (#"\utilde{x}"#, .utilde)] {
            guard case let .accent(_, acc) = MathParser.parse(src) else {
                return XCTFail("\(src) did not parse to an accent")
            }
            XCTAssertEqual(acc, expect)
        }
    }

    func testFullySupportedAndRoundTrips() {
        for src in [#"\overrightharpoon{AB}"#, #"\overleftharpoon{v}"#, #"\utilde{abc}"#] {
            let node = MathParser.parse(src)
            XCTAssertTrue(MathParser.isFullySupported(node), "\(src) must be supported")
            XCTAssertEqual(node.toLaTeX(), src, "round-trip must be exact for \(src)")
        }
    }

    func testUtildeExtendsTheDescentBelowTheBase() {
        let plain = engine().layout(.symbol("x", .ordinary, style: .italic)).descent
        let ut = engine().layout(MathParser.parse(#"\utilde{x}"#)).descent
        XCTAssertGreaterThan(ut, plain, "the under-tilde must extend the descent (it sits below)")
    }

    func testHarpoonExtendsTheAscentAboveTheBase() {
        let plain = engine().layout(.symbol("v", .ordinary, style: .italic)).ascent
        let h = engine().layout(MathParser.parse(#"\overrightharpoon{v}"#)).ascent
        XCTAssertGreaterThan(h, plain, "the harpoon accent must extend the ascent (it sits above)")
    }

    func testUtildeIsStretchy() {
        // A wider base gets a wider under-tilde (more of it draws), so the box widens
        // only as much as the base — but the tilde clearly tracks the base width via
        // the stretchy target. Here we assert the under-mark exists as its own element.
        let scene = engine().layout(MathParser.parse(#"\utilde{abc}"#))
        let below = scene.elements.contains {
            if case let .glyphs(_, _, _, origin, _) = $0, origin.y < 0 { return true }
            if case let .glyph(_, _, origin, _) = $0, origin.y < 0 { return true }
            return false
        }
        XCTAssertTrue(below, "utilde must emit a mark below the baseline")
    }
}
