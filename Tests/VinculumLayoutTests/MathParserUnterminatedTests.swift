import XCTest
@testable import VinculumLayout

/// Unterminated arguments must degrade LOUDLY.
///
/// The parser's contract is "unknown input degrades, never crashes" — and,
/// crucially, never loses content silently. Every `{…}` / `[…]` reader scanned
/// to its closer with an unbounded loop, so one missing delimiter let a reader
/// consume the whole rest of the stream as a single argument. The argument was
/// then discarded (it's a colour/thickness/alignment *name*), leaving an empty
/// body — while `isFullySupported` still reported **true**. That last part is
/// what made it dangerous: a true there means `rendered()` returns non-nil and
/// the host's fallback never fires, so the equation's content simply vanished
/// behind a successful-looking render (#8).
final class MathParserUnterminatedTests: XCTestCase {

    /// The load-bearing assertion. `isFullySupported == false` is what makes the
    /// host degrade to its own fallback instead of showing a confident blank.
    private func assertDegradesLoudly(_ latex: String, _ message: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let node = MathParser.parse(latex)
        XCTAssertFalse(MathParser.isFullySupported(node),
                       "\(message) — parsed as fully supported, so the host renders "
                       + "it as if nothing were wrong: \(node.toLaTeX())",
                       file: file, line: line)
    }

    // MARK: - Missing closing brace

    func testUnterminatedColorArgumentDoesNotSwallowTheFormula() {
        // Was: colour name "reda+b", body .row([]) — `a+b` gone, reported supported.
        assertDegradesLoudly(#"\textcolor{red a+b"#, "missing } after a colour name")
    }

    func testUnterminatedBraceKeepsTheWholeSourceForTheHost() {
        // Degrading is only half of it: the source must survive so an inline
        // error card (or the host's fallback) can show what the user typed.
        let node = MathParser.parse(#"\textcolor{red a+b"#)
        XCTAssertEqual(node.toLaTeX(), #"\textcolor{red a+b"#,
                       "the original source must survive the degrade")
    }

    func testUnterminatedFracAndColorbox() {
        assertDegradesLoudly(#"\frac{a"#, "missing } in \\frac")
        assertDegradesLoudly(#"x + \textcolor{red"#, "\\textcolor at end of stream")
        assertDegradesLoudly(#"\colorbox{yellow x^2"#, "missing } in \\colorbox")
    }

    func testStrayClosingBraceDegrades() {
        // TeX errors with "Too many }" — it must not parse clean.
        assertDegradesLoudly(#"x}"#, "a } with nothing open")
    }

    // MARK: - Missing closing bracket

    func testUnterminatedSqrtDegreeDoesNotSwallowTheRadicand() {
        // Was: degree "3x+y", radicand empty, reported supported.
        assertDegradesLoudly(#"\sqrt[3{x} + y"#, "missing ] in a \\sqrt degree")
    }

    func testUnterminatedBracketLeavesTheRestParsable() {
        // The guard PEEKS without consuming, so only \sqrt degrades; the tokens
        // after `[` still parse as ordinary content and nothing is lost.
        let node = MathParser.parse(#"\sqrt[3{x} + y"#)
        let latex = node.toLaTeX()
        XCTAssertTrue(latex.contains("3"), "content after the unterminated [ was lost: \(latex)")
        XCTAssertTrue(latex.contains("y"), "content after the unterminated [ was lost: \(latex)")
    }

    func testUnterminatedXrightarrowAndRule() {
        assertDegradesLoudly(#"\xrightarrow[n \to \infty {f}"#, "missing ] in \\xrightarrow")
        assertDegradesLoudly(#"\rule[2pt {1em}{1pt}"#, "missing ] in \\rule")
    }

    // MARK: - Well-formed input is untouched (the false-positive guard)

    /// The brace check is escape-aware: `\{` and `\}` are literal delimiters,
    /// not grouping. If this regressed, every `\left\{ … \right\}` in the wild
    /// would silently stop rendering — a far worse bug than the one being fixed.
    func testEscapedBracesAreNotCountedAsGrouping() {
        for latex in [#"\left\{ x \right\}"#, #"\{ x \}"#, #"\{"#, #"\}"#,
                      #"\lbrace x \rbrace"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(latex)),
                          "escaped braces must not read as unbalanced grouping: \(latex)")
        }
    }

    func testUnbalancedBracketsRemainValidMath() {
        // Brackets, unlike braces, are legitimately unbalanced in real math —
        // which is exactly why balance is checked per-reader, not up front.
        for latex in [#"[0,1)"#, #"(0,1]"#, #"x[1"#, #"a] + b"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(latex)),
                          "an unbalanced bracket is ordinary math: \(latex)")
        }
    }

    func testWellFormedOptionalArgumentsStillParse() {
        for latex in [#"\sqrt[3]{x}"#, #"\cfrac[l]{1}{2}"#, #"\xrightarrow[n]{f}"#,
                      #"\rule[2pt]{1em}{1pt}"#, #"\smash[t]{x}"#,
                      #"\textcolor{red}{a+b}"#, #"\frac{a}{b}"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(latex)),
                          "well-formed input must be untouched: \(latex)")
        }
    }
}
