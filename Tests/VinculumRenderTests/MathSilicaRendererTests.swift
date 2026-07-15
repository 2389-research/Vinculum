#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
@testable import VinculumRender

/// Linux (Silica/Cairo/FreeType) render smoke tests — run by `swift test` on
/// Linux. They prove the backend produces valid PNGs for representative math;
/// the visual parity vs. macOS is checked out-of-band against the corpus.
final class MathSilicaRendererTests: XCTestCase {

    private func isPNG(_ data: Data) -> Bool {
        data.count > 100 && data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testRendersRepresentativeEquations() throws {
        let cases = [
            #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
            #"\sum_{i=1}^{n} i^2"#,
            #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
            #"e^{i\pi} + 1 = 0"#,
        ]
        for latex in cases {
            let png = try XCTUnwrap(MathSilicaRenderer.renderPNG(latex: latex, baseSize: 24, display: true),
                                    "render returned nil for \(latex)")
            XCTAssertTrue(isPNG(png), "not a PNG for \(latex)")
        }
    }

    func testEveryBundledFontRenders() {
        for res in ["latinmodern-math", "texgyretermes-math", "texgyrepagella-math",
                    "stixtwo-math", "firamath"] {
            let png = MathSilicaRenderer.renderPNG(latex: #"\frac{a}{b} + \sqrt{x}"#,
                                                   resource: res, baseSize: 24)
            XCTAssertNotNil(png, "\(res) failed to render")
            if let png { XCTAssertTrue(isPNG(png), "\(res) produced non-PNG") }
        }
    }

    func testUnsupportedReturnsNil() {
        XCTAssertNil(MathSilicaRenderer.renderPNG(latex: #"\nosuchcommand{x}"#))
    }
}
#endif
