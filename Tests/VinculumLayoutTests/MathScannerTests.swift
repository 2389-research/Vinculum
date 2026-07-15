import XCTest
@testable import VinculumLayout

/// Delimiter scanning: `$…$` / `$$…$$` / `\(…\)` / `\[…\]` segmentation.
final class MathScannerTests: XCTestCase {

    func testInlineMathEndingInACommandCloses() {
        // Regression: the escape-skip didn't count the escaped char as ink,
        // so the closing `$` after `\R` looked whitespace-preceded and the
        // segment never closed.
        let segments = MathScanner.scan(#"use $x \in \R$ here"#)
        XCTAssertEqual(segments, [
            .text("use "), .inlineMath(#"x \in \R"#), .text(" here"),
        ])
    }

    func testBasicSegmentation() {
        XCTAssertEqual(MathScanner.scan(#"a $x$ b $$y$$ c \(z\) d \[w\] e"#), [
            .text("a "), .inlineMath("x"),
            .text(" b "), .displayMath("y"),
            .text(" c "), .inlineMath("z"),
            .text(" d "), .displayMath("w"),
            .text(" e"),
        ])
    }

    func testMultiLineBracketDisplayWithRowSeparators() {
        // Issue #1's verbatim block (Quoin §19.7): a `\[ … \]` span crossing a
        // physical newline, `\\` row separators in the body. One display segment.
        let input = #"""
        \[ \begin{bmatrix} 2 & -1 & 0 \\ -1 & 2 & -1 \\ 0 & -1 & 2 \end{bmatrix} \begin{bmatrix} x_1\\x_2\\x_3 \end{bmatrix} =
        \begin{bmatrix} 1\\0\\1 \end{bmatrix} \]
        """#
        let expectedBody = #"""
        \begin{bmatrix} 2 & -1 & 0 \\ -1 & 2 & -1 \\ 0 & -1 & 2 \end{bmatrix} \begin{bmatrix} x_1\\x_2\\x_3 \end{bmatrix} =
        \begin{bmatrix} 1\\0\\1 \end{bmatrix}
        """#
        XCTAssertEqual(MathScanner.scan(input), [.displayMath(expectedBody)])
    }

    func testBracketDisplayWithSetextShapedBody() {
        // Issue #1's failing shape in the wild: the `=` alone on its own line.
        // To cmark that line is a setext underline, so a host that block-parses
        // BEFORE scanning never hands the scanner the whole span — the scanner
        // itself must claim it whenever it does see the full slice.
        let input = #"""
        \[ \begin{bmatrix} 2 & -1 \\ 0 & 2 \end{bmatrix}
        =
        \begin{bmatrix} 1\\0 \end{bmatrix} \]
        """#
        let expectedBody = #"""
        \begin{bmatrix} 2 & -1 \\ 0 & 2 \end{bmatrix}
        =
        \begin{bmatrix} 1\\0 \end{bmatrix}
        """#
        XCTAssertEqual(MathScanner.scan(input), [.displayMath(expectedBody)])
    }

    func testMultiLineDoubleDollarWithRowSeparators() {
        let input = "before\n$$ \\begin{bmatrix} a \\\\ b \\end{bmatrix} =\n\\begin{bmatrix} 1\\\\0 \\end{bmatrix} $$\nafter"
        XCTAssertEqual(MathScanner.scan(input), [
            .text("before\n"),
            .displayMath("\\begin{bmatrix} a \\\\ b \\end{bmatrix} =\n\\begin{bmatrix} 1\\\\0 \\end{bmatrix}"),
            .text("\nafter"),
        ])
    }

    func testBracketDisplayClaimsAcrossBlankLine() {
        // Pinned: `\[…\]` claims across a blank line, matching `$$…$$` (only
        // inline `$…$` stops at blank lines). Hosts that split paragraphs at
        // blank lines never feed the scanner one anyway.
        XCTAssertEqual(MathScanner.scan("\\[ a \\\\ b\n\nc \\]"),
                       [.displayMath("a \\\\ b\n\nc")])
        XCTAssertEqual(MathScanner.scan("$$ a \\\\ b\n\nc $$"),
                       [.displayMath("a \\\\ b\n\nc")])
    }

    func testUnterminatedBracketStaysProse() {
        // No closer anywhere: the opener must not claim to end-of-input.
        let input = "\\[ \\begin{bmatrix} 1\\\\2 \\end{bmatrix}\nno closer here"
        XCTAssertEqual(MathScanner.scan(input), [.text(input)])
    }

    func testEscapedDollarAndPrices() {
        XCTAssertEqual(MathScanner.scan(#"costs \$5 or $10"#),
                       [.text(#"costs \$5 or $10"#)],
                       "escaped dollars and price-like text stay prose")
    }
}
