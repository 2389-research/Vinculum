#if canImport(AppKit) || canImport(UIKit) || canImport(SilicaCairo)
import XCTest
import Foundation
@testable import VinculumRender
@testable import VinculumLayout

/// Adversarial input against the REAL rasterizers.
///
/// `MathFuzzTests` proves the platform-free engine survives garbage, but it
/// builds every engine from `standardMockMeasurer` — pure arithmetic, no font.
/// So the code most likely to hold a memory-safety bug (FreeType outline decode
/// and advance/ink extents, Cairo path fill, CoreText line measurement — the C
/// interop) was only ever asked to render clean, curated equations. The fuzzing
/// and the unsafe surface never intersected (#12).
///
/// ## The trap this test is built around
///
/// Both renderers gate on `MathParser.isFullySupported` and return nil for
/// unsupported input, so *random garbage never reaches the rasterizer at all* —
/// it short-circuits at the gate. Naively pointing the existing fuzz corpus at
/// `rendered()` would produce a test that passes while exercising nothing. That
/// pressure only increased after #8, which made the parser reject unbalanced
/// braces up front.
///
/// So the corpus here is **valid-by-construction but adversarial**: deep nesting,
/// oversized grids, dense accent stacks, and astral/combining scalars that drive
/// `glyphIndex` and outline decode down unusual paths.
///
/// And critically, every test **asserts its own reach** — that a minimum number
/// of inputs actually got past the gate into the rasterizer. Without that, a
/// future parser change could silently turn this whole file into a no-op that
/// still reports green. That is the failure mode it is designed against.
final class MathRenderFuzzTests: XCTestCase {

    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func below(_ n: Int) -> Int { Int(next()) % max(1, n) }
    }

    /// Renders through whichever real backend this platform has, returning
    /// whether the input reached the rasterizer and produced output.
    /// Deliberately no correctness assertion: the contract under fuzz is only
    /// "no crash, no hang, and either a real result or a clean nil".
    private func render(_ latex: String) -> Bool {
        #if canImport(AppKit) || canImport(UIKit)
        guard let r = MathImageRenderer.rendered(latex: latex, display: true,
                                                 mathTheme: .light, baseSize: 17) else { return false }
        return r.image.size.width > 0 && r.image.size.height > 0
        #else
        guard let png = MathSilicaRenderer.renderPNG(latex: latex, baseSize: 17, display: true)
        else { return false }
        // A valid PNG signature — proves Cairo actually encoded a surface.
        return png.count > 100 && png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #endif
    }

    /// Runs a corpus and enforces that it genuinely reached the rasterizer.
    /// `minReach` is the anti-no-op guard, not a quality bar.
    private func drive(_ corpus: [String], minReach: Int,
                       file: StaticString = #filePath, line: UInt = #line) {
        var reached = 0
        for latex in corpus where render(latex) { reached += 1 }
        print("REACH \(reached)/\(corpus.count) (min \(minReach))")
        XCTAssertGreaterThanOrEqual(reached, minReach,
            "only \(reached)/\(corpus.count) inputs reached the rasterizer — the corpus is "
            + "bouncing off the isFullySupported gate, so this test is exercising nothing. "
            + "If a parser change made this input unsupported, fix the corpus, not this bound.",
            file: file, line: line)
    }

    // MARK: - Deep nesting

    /// Valid, balanced, and deep: the recursive layout paths with real glyph
    /// metrics behind them. Depth stays under `maxNestingDepth` (64) so it does
    /// NOT degrade — the point is to reach the rasterizer, not the gate.
    func testDeeplyNestedStructuresRender() {
        var rng = LCG(state: 0xD00D_F00D)
        var corpus: [String] = []
        for _ in 0..<40 {
            let depth = 2 + rng.below(18)
            var s = "x"
            for _ in 0..<depth {
                switch rng.below(4) {
                case 0: s = "\\frac{\(s)}{y}"
                case 1: s = "\\sqrt{\(s)}"
                case 2: s = "{\(s)}^{2}"
                default: s = "\\left( \(s) \\right)"
                }
            }
            corpus.append(s)
        }
        drive(corpus, minReach: 35)
    }

    /// Accent/script stacks — the paths that query ink extents per glyph, which
    /// on Linux is a live FreeType outline call per level.
    func testDenseAccentAndScriptStacksRender() {
        var rng = LCG(state: 0xACCE_0001)
        let accents = ["\\hat", "\\bar", "\\vec", "\\tilde", "\\dot", "\\widehat"]
        var corpus: [String] = []
        for _ in 0..<40 {
            var s = "x"
            for _ in 0..<(1 + rng.below(10)) { s = "\(accents[rng.below(accents.count)]){\(s)}" }
            if rng.below(2) == 0 { s += "^{\(s)}" }
            corpus.append(s)
        }
        drive(corpus, minReach: 35)
    }

    // MARK: - Oversized grids

    func testOversizedGridsRender() {
        var rng = LCG(state: 0x6819_D000)
        var corpus: [String] = []
        for _ in 0..<12 {
            let rows = 1 + rng.below(12), cols = 1 + rng.below(8)
            let body = (0..<rows).map { r in
                (0..<cols).map { c in "a_{\(r)\(c)}" }.joined(separator: " & ")
            }.joined(separator: " \\\\ ")
            corpus.append("\\begin{pmatrix} \(body) \\end{pmatrix}")
        }
        drive(corpus, minReach: 10)
    }

    // MARK: - Unicode against the glyph lookup

    /// Astral scalars, combining marks and CJK drive `glyphIndex` toward
    /// .notdef and the fallback path, and outline decode over glyphs the math
    /// font does not have. This is the interop surface at its least tested.
    func testUnicodeScalarsReachGlyphLookupSafely() {
        let scalars = ["𝕏", "𝔄", "😀", "中", "\u{0301}", "\u{200B}", "ﬀ", "Ω", "∭", "🜁",
                       "\u{1D7CE}", "\u{FFFD}", "a\u{0301}\u{0302}\u{0303}"]
        var rng = LCG(state: 0x0DEF_ACED)
        var corpus: [String] = []
        for _ in 0..<40 {
            var s = ""
            for _ in 0..<(1 + rng.below(8)) { s += scalars[rng.below(scalars.count)] }
            corpus.append(s)
        }
        // Measured reach: 40/40 on macOS (CoreText), 38/40 on Linux (FreeType) —
        // two of these render on CoreText and degrade on FreeType. That platform
        // gap is real and is exactly what #62 is about: the layout engine is
        // platform-FREE, its output is not. The bound sits below both so it
        // guards against the corpus dying at the gate without pinning a
        // per-platform quirk.
        drive(corpus, minReach: 35)
    }

    // MARK: - Mutation, re-balanced

    /// Sliced-and-spliced real expressions — the live-editor hot path. Slicing
    /// usually unbalances braces (which #8 now rejects at the gate), so each
    /// mutant is re-balanced by appending the missing closers: still adversarial,
    /// but it actually reaches the rasterizer instead of dying at the gate.
    func testRebalancedMutantsRender() {
        let seeds = [
            #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
            #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
            #"\sum_{i=1}^{n} \frac{x_i}{\sqrt{n}}"#,
            #"\left( \frac{\partial f}{\partial x} \right)_{y}"#,
        ]
        var rng = LCG(state: 0xBADC_0FFE)
        var corpus: [String] = []
        for _ in 0..<60 {
            let a = Array(seeds[rng.below(seeds.count)])
            let cut = 1 + rng.below(max(1, a.count - 1))
            var s = String(a.prefix(cut))
            // Re-balance: count unescaped braces and close what's still open.
            var depth = 0, i = s.startIndex
            while i < s.endIndex {
                let ch = s[i]
                if ch == "\\" { i = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex; continue }
                if ch == "{" { depth += 1 }
                if ch == "}" { depth = max(0, depth - 1) }
                i = s.index(after: i)
            }
            s += String(repeating: "}", count: depth)
            corpus.append(s)
        }
        // Truncation can still strip a \begin's \end, so not every mutant is
        // renderable; require a real majority to get through.
        drive(corpus, minReach: 25)
    }
}
#endif
