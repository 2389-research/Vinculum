import XCTest
@testable import VinculumLayout

/// 1.0 hardening: the whole pipeline — parse → diagnostics → layout →
/// serialize → speech — must survive arbitrary garbage. Parse is total by
/// design (unknown input degrades to `.unsupported`, never throws, never
/// crashes); this proves it under deterministic fuzz (fixed-seed LCG, so
/// failures reproduce).
final class MathFuzzTests: XCTestCase {

    private let mock = standardMockMeasurer

    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func below(_ n: Int) -> Int { Int(next()) % max(1, n) }
    }

    private func exercise(_ latex: String, engine: MathLayoutEngine) {
        let node = MathParser.parse(latex)
        _ = MathParser.isFullySupported(node)
        _ = MathParser.unsupportedCommands(in: node)
        _ = MathParser.diagnostics(for: latex)
        _ = node.toLaTeX()
        _ = MathSpeech.describe(node)
        let scene = engine.layout(node, display: true)
        XCTAssertTrue(scene.width.isFinite && scene.ascent.isFinite && scene.descent.isFinite,
                      "non-finite geometry for: \(latex)")
    }

    func testGrammarFuzzNeverCrashes() {
        let atoms = [
            "\\frac", "{", "}", "^", "_", "\\left(", "\\right)", "\\right", "\\left",
            "x", "1", "+", "=", "\\sum", "\\int", "\\begin{pmatrix}", "\\end{pmatrix}",
            "\\begin{cases}", "\\end{aligned}", "&", "\\\\", "\\sqrt", "[", "]",
            "\\alpha", "\\hat", "\\text{a b}", "\\color{red}", "\\middle|", "\\big",
            "\\newcommand", "\\def", "#1", "%", "$", "\\", "√", "∑", "😀", "\u{0000}",
            "\\operatorname*", "\\genfrac", "\\scriptstyle", "\\not", "'", "\\hline",
        ]
        var rng = LCG(state: 0x5EED_5EED)
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        for _ in 0..<2000 {
            var s = ""
            for _ in 0..<rng.below(40) { s += atoms[rng.below(atoms.count)] }
            exercise(s, engine: engine)
        }
    }

    func testMutationFuzzNeverCrashes() {
        // Real expressions, randomly sliced and spliced — half-valid input is
        // the live-editor hot path (every keystroke is a truncated formula).
        let seeds = [
            #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#,
            #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
            #"\left\langle u, \middle| v \right\rangle + \sum_{i=1}^{n} x_i"#,
            #"\cfrac{1}{1 + \cfrac{1}{x}} + \genfrac{[}{]}{0pt}{2}{a}{b}"#,
        ]
        var rng = LCG(state: 0xBADC_0FFE)
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        for _ in 0..<2000 {
            let a = Array(seeds[rng.below(seeds.count)])
            let b = Array(seeds[rng.below(seeds.count)])
            let cut = rng.below(a.count)
            let paste = rng.below(b.count)
            var s = String(a.prefix(cut)) + String(b.suffix(from: b.index(b.startIndex, offsetBy: paste)))
            if rng.below(4) == 0, !s.isEmpty {
                s.remove(at: s.index(s.startIndex, offsetBy: rng.below(s.count)))
            }
            exercise(s, engine: engine)
        }
    }

    func testAdversarialDepthDegradesGracefully() {
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        exercise(String(repeating: "{", count: 5_000), engine: engine)
        exercise(String(repeating: "\\frac{", count: 2_000), engine: engine)
        exercise(String(repeating: "\\begin{pmatrix}", count: 1_000), engine: engine)
        exercise(String(repeating: "x^", count: 3_000), engine: engine)
    }

    func testBraceFreeRecursiveCommandsDegradeGracefully() {
        // Commands that take an atom argument recurse WITHOUT braces, so the
        // brace pre-scan can't see the depth — a runtime counter must.
        // (Expert review: \sqrt×10k crashed with SIGSEGV before the guard.)
        let engine = MathLayoutEngine(measure: mock, baseSize: 10)
        exercise(String(repeating: "\\sqrt", count: 20_000) + "{x}", engine: engine)
        exercise(String(repeating: "\\hat", count: 20_000) + "{x}", engine: engine)
        exercise(String(repeating: "\\not", count: 20_000) + "=", engine: engine)
        exercise(String(repeating: "\\mathbf", count: 20_000) + "{x}", engine: engine)
        exercise(String(repeating: "\\phantom", count: 20_000) + "{x}", engine: engine)

        // Sane nesting still parses natively: 20 nested \sqrt is legitimate.
        let sane = String(repeating: "\\sqrt{", count: 20) + "x"
            + String(repeating: "}", count: 20)
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(sane)))
    }
}
