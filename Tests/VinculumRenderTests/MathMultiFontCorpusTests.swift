#if canImport(AppKit)
import XCTest
@testable import VinculumRender
import VinculumLayout

/// The 1.0 bar: the full real-world stress corpus lays out under EVERY
/// bundled font's complete pipeline (font constants, variants, assemblies,
/// per-glyph typography) with sane geometry — not just the default font
/// plus per-font canaries.
@MainActor
final class MathMultiFontCorpusTests: XCTestCase {

    func testStressCorpusLaysOutUnderEveryBundledFont() {
        let corpus = MathStressGallery.pages.flatMap(\.equations)
        XCTAssertGreaterThan(corpus.count, 50, "corpus unexpectedly small")
        for font in MathFont.bundled {
            let engine = MathLayoutEngine.make(font: font, baseSize: 16)
            var supported = 0
            for latex in corpus {
                let node = MathParser.parse(latex)
                guard MathParser.isFullySupported(node) else { continue }
                supported += 1
                let scene = engine.layout(node, display: true)
                XCTAssertTrue(scene.width.isFinite && scene.width > 0,
                              "\(font.name): degenerate width for \(latex)")
                XCTAssertTrue(scene.ascent.isFinite && scene.descent.isFinite
                              && scene.ascent + scene.descent > 0,
                              "\(font.name): degenerate height for \(latex)")
            }
            // The ratchet: everything the parser supports must lay out, in
            // every font — and support is corpus-wide (pinned elsewhere).
            XCTAssertEqual(supported, corpus.count,
                           "\(font.name): corpus support regressed")
        }
    }
}
#endif
