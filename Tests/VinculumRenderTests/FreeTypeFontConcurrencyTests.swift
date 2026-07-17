#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
import Foundation
@testable import VinculumRender

/// `FreeTypeFont` is `@unchecked Sendable` — a promise that instances are safe to
/// share across threads. This is the test that makes the promise checkable (#3).
///
/// The hazard is concrete, not theoretical: every accessor calls `FT_Load_Glyph`,
/// which fills the face's **shared** glyph slot. Two threads interleaving
/// `load(A); read slot` and `load(B); read slot` can make thread A read B's
/// metrics — so an unsynchronized race shows up as *wrong numbers*, not merely as
/// a sanitizer report. Both are checked: values must match the serial baseline,
/// and `--sanitize=thread` must stay quiet.
final class FreeTypeFontConcurrencyTests: XCTestCase {

    func testSharedFontSurvivesConcurrentUse() throws {
        let loaded = try XCTUnwrap(MathSilicaRenderer.loadFont(resource: "latinmodern-math"))
        let font = loaded.font
        let scalars: [Unicode.Scalar] = ["x", "y", "+", "=", "1", "2", "a", "b"]

        // Serial baseline — the truth each concurrent reader must agree with.
        let expected = scalars.map { font.advanceEm(glyph: font.glyphIndex($0)) }
        XCTAssertTrue(expected.allSatisfy { $0 > 0 }, "baseline advances should be non-zero")

        DispatchQueue.concurrentPerform(iterations: 256) { i in
            let idx = i % scalars.count
            let gid = font.glyphIndex(scalars[idx])
            let advance = font.advanceEm(glyph: gid)
            // A torn read of the shared glyph slot surfaces here as another
            // glyph's advance.
            XCTAssertEqual(advance, expected[idx], accuracy: 1e-9,
                           "advance for \(scalars[idx]) disagreed with the serial baseline under concurrency")
            _ = font.inkExtentEm(glyph: gid)
            _ = font.outline(glyph: gid, size: 20)
        }
    }
}
#endif
