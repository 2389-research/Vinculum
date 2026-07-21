import XCTest
import Foundation
@testable import VinculumLayout

/// Prescripts & multiscripts (`\prescript`, `\sideset`) — headless geometry on
/// the deterministic mock, so these are platform-free and run on Linux.
final class MathMultiScriptsTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    private func glyphRuns(_ scene: MathScene) -> [(text: String, x: CGFloat, y: CGFloat)] {
        scene.elements.compactMap {
            if case let .glyphs(text, _, _, origin, _) = $0 { return (text, origin.x, origin.y) }
            return nil
        }
    }

    // MARK: parsing

    func testPrescriptParsesToMultiScripts() {
        guard case let .multiScripts(base, preSub, preSuper, postSub, postSuper) =
                MathParser.parse(#"\prescript{2}{1}{X}"#) else {
            return XCTFail("expected multiScripts")
        }
        XCTAssertEqual(base.toLaTeX(), "X")
        XCTAssertEqual(preSuper?.toLaTeX(), "2")
        XCTAssertEqual(preSub?.toLaTeX(), "1")
        XCTAssertNil(postSub); XCTAssertNil(postSuper)
    }

    func testPrescriptEmptyGroupDropsThatSide() {
        guard case let .multiScripts(_, preSub, preSuper, _, _) =
                MathParser.parse(#"\prescript{}{n}{X}"#) else {
            return XCTFail("expected multiScripts")
        }
        XCTAssertNil(preSuper, "empty super group must drop out")
        XCTAssertEqual(preSub?.toLaTeX(), "n")
    }

    func testSidesetParsesAllFourCorners() {
        guard case let .multiScripts(_, preSub, preSuper, postSub, postSuper) =
                MathParser.parse(#"\sideset{_a^b}{_c^d}{\sum}"#) else {
            return XCTFail("expected multiScripts")
        }
        XCTAssertEqual(preSub?.toLaTeX(), "a")
        XCTAssertEqual(preSuper?.toLaTeX(), "b")
        XCTAssertEqual(postSub?.toLaTeX(), "c")
        XCTAssertEqual(postSuper?.toLaTeX(), "d")
    }

    func testBothAreFullySupported() {
        func supported(_ s: String) -> Bool { MathParser.isFullySupported(MathParser.parse(s)) }
        XCTAssertTrue(supported(#"\prescript{2}{1}{X}"#))
        XCTAssertTrue(supported(#"\sideset{_a^b}{_c^d}{\sum}"#))
        XCTAssertTrue(supported(#"\prescript{14}{6}{C}"#))   // isotope ¹⁴₆C
    }

    // MARK: geometry

    func testPrescriptsSitLeftOfBaseAndOnCorrectRows() {
        let scene = engine().layout(MathParser.parse(#"\prescript{2}{1}{X}"#))
        let runs = glyphRuns(scene)
        XCTAssertEqual(runs.count, 3, "base + pre-super + pre-sub")
        // The base is the remaining run (it renders as Math-Italic 𝑋, not "X").
        guard let preSup = runs.first(where: { $0.text == "2" }),
              let preSub = runs.first(where: { $0.text == "1" }),
              let base = runs.first(where: { $0.text != "2" && $0.text != "1" }) else {
            return XCTFail("missing a glyph run: \(runs.map(\.text))")
        }
        // Both prescripts start left of the base (they hug its left edge).
        XCTAssertLessThan(preSup.x, base.x)
        XCTAssertLessThan(preSub.x, base.x)
        // Super rides above sub.
        XCTAssertGreaterThan(preSup.y, preSub.y)
        // The base is not at the origin — the pre-cluster pushed it right.
        XCTAssertGreaterThan(base.x, 0)
    }

    func testMultiscriptWiderThanPlainBase() {
        let plain = engine().layout(.symbol("X", .ordinary, style: .italic)).width
        let multi = engine().layout(MathParser.parse(#"\sideset{_a^b}{_c^d}{X}"#)).width
        XCTAssertGreaterThan(multi, plain, "four corner scripts widen the base")
    }

    // MARK: round-trip

    func testRoundTripStaysSupported() {
        for src in [#"\prescript{2}{1}{X}"#, #"\sideset{_a^b}{_c^d}{X}"#, #"\prescript{}{n}{X}"#] {
            let once = MathParser.parse(src).toLaTeX()
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(once)),
                          "round-trip of \(src) → \(once) must re-parse cleanly")
            if case .multiScripts = MathParser.parse(once) {} else {
                XCTFail("round-trip of \(src) lost the multiScripts shape → \(once)")
            }
        }
    }
}
