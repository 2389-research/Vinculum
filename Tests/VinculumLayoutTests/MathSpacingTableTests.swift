import XCTest
import Foundation
@testable import VinculumLayout

/// Pins the inter-atom spacing to the 8×8 pair table on p. 170 of The
/// TeXbook, transcribed here independently of the engine's own copy so a
/// transcription slip in either place fails loudly. Headless (mock measurer,
/// Linux-safe): each glyph is a `size`-square cell, so widths are exact.
final class MathSpacingTableTests: XCTestCase {

    private let mock = standardMockMeasurer
    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: mock, baseSize: size)
    }

    private let thin = (3.0 / 18.0) * 10
    private let em = { (mu: Int) -> CGFloat in CGFloat(mu) / 18.0 * 10 }

    // MARK: - The whole table, cell by cell

    /// The TeXbook p. 170 chart verbatim: 0/1/2/3 = none/thin/medium/thick;
    /// negative = parenthesized (display/text only); `*` cells — which
    /// reclassification guarantees never arise — are expected to be 0.
    func testPairTableMatchesTheTeXbookChart() {
        let order: [MathAtomClass] = [.ordinary, .largeOperator, .binary, .relation,
                                      .opening, .closing, .punctuation, .inner]
        let book: [[Int]] = [
            [ 0,  1, -2, -3,  0,  0,  0, -1],  // Ord
            [ 1,  1,  0, -3,  0,  0,  0, -1],  // Op
            [-2, -2,  0,  0, -2,  0,  0, -2],  // Bin
            [-3, -3,  0,  0, -3,  0,  0, -3],  // Rel
            [ 0,  0,  0,  0,  0,  0,  0,  0],  // Open
            [ 0,  1, -2, -3,  0,  0,  0, -1],  // Close
            [-1, -1,  0, -1, -1, -1, -1, -1],  // Punct
            [-1,  1, -2, -3, -1,  0, -1, -1],  // Inner
        ]
        let mu: [Int: CGFloat] = [0: 0, 1: 3.0 / 18.0, 2: 4.0 / 18.0, 3: 5.0 / 18.0]
        let e = engine()
        for (i, left) in order.enumerated() {
            for (j, right) in order.enumerated() {
                let cell = book[i][j]
                XCTAssertEqual(e.spacing(between: left, and: right, style: .text),
                               mu[abs(cell)]!, accuracy: 0.0001,
                               "text-style \(left)→\(right)")
                XCTAssertEqual(e.spacing(between: left, and: right, style: .script),
                               cell < 0 ? 0 : mu[cell]!, accuracy: 0.0001,
                               "script-style \(left)→\(right)")
            }
        }
    }

    // MARK: - The consequences a reader can see

    func testOperatorBeforeOpeningParenSetsTight() {
        // p. 170's own example: TeX inserts NO space before the parenthesis
        // in \log n(x)-shaped formulas (Op→Open = 0). sin + ( + x + ).
        let s = engine().layout(MathParser.parse(#"\sin(x)"#))
        XCTAssertEqual(s.width, 30 + 30, accuracy: 0.001)
    }

    func testAdjacentOperatorsGetThinSpace() {
        // Op→Op = thin (the unparenthesized 1 in the chart).
        let s = engine().layout(MathParser.parse(#"\sin\cos"#))
        XCTAssertEqual(s.width, 30 + thin + 30, accuracy: 0.001)
    }

    func testFractionSpacesAsInnerAtom() {
        // "fractions are treated as type Inner" — Ord→Inner and Inner→Ord
        // are thin, where Ord→Ord would be 0.
        let frac = engine().layout(MathParser.parse(#"\frac{1}{2}"#)).width
        let row = engine().layout(MathParser.parse(#"a\frac{1}{2}b"#)).width
        XCTAssertEqual(row, 10 + thin + frac + thin + 10, accuracy: 0.001)
    }

    func testDelimitedGroupSpacesAsInnerAtom() {
        // \left…\right is a delimited subformula → Inner on both sides.
        let group = engine().layout(MathParser.parse(#"\left(y\right)"#)).width
        let row = engine().layout(MathParser.parse(#"x\left(y\right)z"#)).width
        XCTAssertEqual(row, 10 + thin + group + thin + 10, accuracy: 0.001)
    }

    func testPunctuationThinSpaceIsSuppressedInScripts() {
        // Punct→Ord is (1): thin in text, GONE at script level.
        let text = engine().layout(MathParser.parse("a,b"))
        XCTAssertEqual(text.width, 30 + thin, accuracy: 0.001)
        let scripted = engine().layout(MathParser.parse("x^{a,b}"))
        XCTAssertEqual(scripted.width, 10 + 0.56 + 3 * 7, accuracy: 0.001,
                       "no thin space after the comma inside a superscript")
    }

    func testMathinnerClassifiesAndRoundTrips() {
        let node = MathParser.parse(#"a\mathinner{x}b"#)
        XCTAssertEqual(node.toLaTeX(), #"a\mathinner{x}b"#)
        let s = engine().layout(node)
        XCTAssertEqual(s.width, 30 + 2 * thin, accuracy: 0.001)
    }

    func testDotsAreInnerAtoms() {
        // TeXbook p. 172: \ldots between commas draws thin spaces on BOTH
        // sides (Punct→Inner and Inner→Punct are each (1)); an Ord there
        // would only get the leading one.
        let s = engine().layout(MathParser.parse(#"a,\ldots,b"#))
        XCTAssertEqual(s.width, 5 * 10 + 3 * thin, accuracy: 0.001,
                       "thin after each comma AND before the second comma")
        // \cdots between binaries keeps the medium Bin spacing: Bin→Inner (2).
        let c = engine().layout(MathParser.parse(#"x+\cdots+y"#))
        XCTAssertEqual(c.width, 5 * 10 + 4 * em(4), accuracy: 0.001)
    }

    func testFencedMatrixIsInnerButBareGridIsOrdinary() {
        // pmatrix arrives with fences → Inner (TeX's \left(\vcenter…\right));
        // aligned has none → Ord (a plain \vcenter box).
        let pWidth = engine().layout(MathParser.parse(#"\begin{pmatrix} 1 \end{pmatrix}"#)).width
        let pRow = engine().layout(MathParser.parse(#"a\begin{pmatrix} 1 \end{pmatrix}"#)).width
        XCTAssertEqual(pRow, 10 + thin + pWidth, accuracy: 0.001)

        let aWidth = engine().layout(MathParser.parse(#"\begin{aligned} 1 \end{aligned}"#)).width
        let aRow = engine().layout(MathParser.parse(#"a\begin{aligned} 1 \end{aligned}"#)).width
        XCTAssertEqual(aRow, 10 + aWidth, accuracy: 0.001)
    }
}
