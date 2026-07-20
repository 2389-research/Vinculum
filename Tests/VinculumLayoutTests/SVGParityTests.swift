import XCTest
import Foundation
@testable import VinculumLayout

/// The universal cross-platform parity gate (docs/DISPLAYLIST.md, #62, #101).
///
/// `MathSVGRenderer` is platform-free (Foundation only), and driven by the
/// deterministic mock measurer the whole layout suite uses, the pipeline
/// LaTeX → parse → layout → SVG has **no platform inputs at all**. So its output
/// is a pure function of the code — byte-identical on macOS, Linux, wasm, and
/// Windows. This test pins that: a corpus is rendered to SVG and compared to
/// committed goldens.
///
/// Because it lives in `VinculumLayoutTests` (Foundation-only), it runs in EVERY
/// job — macOS, Linux, Windows, and the wasm CI job — so if any platform's
/// layout or SVG code drifts by even a formatted digit, that platform goes red.
/// That is the enforced invariant #62 asked for: platform-free must mean
/// identical output, not merely no platform imports.
///
/// (This gate deliberately uses the mock measurer, so it isolates the
/// platform-free engine. Measurer-seam parity across real font engines
/// — CoreText vs FreeType — is a separate, tolerance-based concern.)
final class SVGParityTests: XCTestCase {

    /// Corpus chosen to exercise the SVG element kinds without needing a glyph-
    /// outline provider: `<text>` runs, `<rect>` (fraction bars), and `<path>`
    /// (radical surds are stroked polylines, not `.glyph(id:)`). Stretchy
    /// delimiters are intentionally avoided — those emit `.glyph(id:)`, which the
    /// provider-less SVG path skips, so they carry no parity signal here.
    private static let corpus: [(name: String, latex: String)] = [
        ("quadratic",  #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#),
        ("fraction",   #"\frac{a+b}{c-d}"#),
        ("scripts",    #"x^{2} + y_{i}^{n} - z"#),
        ("radical",    #"\sqrt{x^2 + y^2}"#),
        ("sum",        #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#),
        ("mixed",      #"e^{i\pi} + 1 = 0"#),
    ]

    private func goldenURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/fixtures/svg-golden/\(name).svg")
    }

    private func renderSVG(_ latex: String) -> String {
        let scene = standardMockEngine(20).layout(MathParser.parse(latex), display: true)
        return MathSVGRenderer.svg(for: scene)
    }

    func testCorpusRendersToGoldenSVGIdenticallyOnEveryPlatform() throws {
        let update = ProcessInfo.processInfo.environment["VINCULUM_UPDATE_SVG_GOLDENS"] != nil
        if update {
            let dir = goldenURL("x").deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, latex) in Self.corpus {
                try renderSVG(latex).write(to: goldenURL(name), atomically: true, encoding: .utf8)
            }
            throw XCTSkip("regenerated \(Self.corpus.count) SVG goldens")
        }

        for (name, latex) in Self.corpus {
            let fresh = renderSVG(latex)
            let golden = try XCTUnwrap(try? String(contentsOf: goldenURL(name), encoding: .utf8),
                "missing golden svg-golden/\(name).svg — regenerate with VINCULUM_UPDATE_SVG_GOLDENS=1")
            XCTAssertEqual(fresh, golden,
                "\(name): the platform-free LaTeX→SVG pipeline drifted from the committed golden. "
                + "If intentional, regenerate with VINCULUM_UPDATE_SVG_GOLDENS=1; otherwise this "
                + "platform is producing different geometry from the others.")
        }
    }

    /// A golden must actually carry ink — guards against committing an empty
    /// render that would make the parity check vacuous.
    func testGoldensAreNonEmpty() throws {
        for (name, _) in Self.corpus {
            let golden = try XCTUnwrap(try? String(contentsOf: goldenURL(name), encoding: .utf8))
            XCTAssertTrue(golden.contains("<text") || golden.contains("<path") || golden.contains("<rect"),
                          "\(name) golden carries no ink")
        }
    }
}
