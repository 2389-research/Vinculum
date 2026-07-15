import XCTest
import Foundation
@testable import VinculumLayout

// Shared test scaffolding for the headless layout suite. Every geometry
// test builds on the SAME deterministic mock, so its shape is a contract:
// change it here and the expected values across the suite change with it.

/// The standard mock measurer: every glyph run is a `count × size` cell
/// with ascent 0.75·size, descent 0.25·size, ink top 0.7·size, ink bottom
/// −0.05·size. Assertions throughout the suite are computed from these
/// ratios ("x=y is 3 cells plus two thick spaces").
let standardMockMeasurer: MathTextMeasurer = { text, size, _ in
    GlyphMetrics(width: CGFloat(text.count) * size, ascent: size * 0.75, descent: size * 0.25,
                 inkAscent: size * 0.7, inkDescent: -size * 0.05)
}

/// An engine over the standard mock at `size` (default 10 — the round
/// numbers the assertions are written against).
func standardMockEngine(_ size: CGFloat = 10) -> MathLayoutEngine {
    MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
}

enum TestFixtures {
    /// Repo-root-relative fixture URL (tests run from the source tree; the
    /// walk-up from `#filePath` is the golden suite's long-standing idiom).
    static func url(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }

    /// A committed raw MATH table (`Tests/fixtures/math-table/<name>.bin`),
    /// failing LOUDLY with the path when missing — a moved fixture must not
    /// masquerade as a parser bug.
    static func mathTable(_ name: String, file: StaticString = #filePath,
                          line: UInt = #line) -> Data {
        let url = url("Tests/fixtures/math-table/\(name).bin")
        guard let data = try? Data(contentsOf: url) else {
            XCTFail("missing fixture: \(url.path) — regenerate with VINCULUM_UPDATE_MATH_FIXTURES=1",
                    file: file, line: line)
            return Data()
        }
        return data
    }
}
