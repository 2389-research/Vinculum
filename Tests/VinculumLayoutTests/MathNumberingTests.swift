import XCTest
import Foundation
@testable import VinculumLayout

/// Document-scoped equation numbering + cross-references. Platform-free string logic.
final class MathNumberingTests: XCTestCase {

    func testAutoNumbersDisplayEquationsSequentially() {
        let n = MathNumbering.number(#"$$a=1$$ text $$b=2$$"#, autoNumber: true)
        XCTAssertEqual(n.autoTags[0], "1")
        XCTAssertEqual(n.autoTags[1], "2")
    }

    func testLabelsMapToNumbers() {
        let n = MathNumbering.number(#"$$a=1 \label{first}$$ $$b=2 \label{second}$$"#, autoNumber: true)
        XCTAssertEqual(n.labels["first"], "1")
        XCTAssertEqual(n.labels["second"], "2")
    }

    func testManualTagWinsAndDoesNotAdvanceAuto() {
        // The tagged eq keeps its tag; the next auto eq still numbers from the counter.
        let n = MathNumbering.number(#"$$a \label{a}$$ $$b \tag{★} \label{b}$$ $$c \label{c}$$"#, autoNumber: true)
        XCTAssertEqual(n.labels["a"], "1")
        XCTAssertEqual(n.labels["b"], "★")     // manual tag
        XCTAssertNil(n.autoTags[1])            // manual, not injected
        XCTAssertEqual(n.labels["c"], "2")     // auto counter unaffected by the manual tag
    }

    func testNotagSuppressesNumber() {
        let n = MathNumbering.number(#"$$a \notag \label{a}$$ $$b \label{b}$$"#, autoNumber: true)
        XCTAssertNil(n.autoTags[0])
        XCTAssertNil(n.labels["a"], "an unnumbered (\\notag) label is not recorded")
        XCTAssertEqual(n.labels["b"], "1")     // first NUMBERED equation
    }

    func testAutoOffStillCollectsManualTags() {
        let n = MathNumbering.number(#"$$a \label{a}$$ $$b \tag{7} \label{b}$$"#, autoNumber: false)
        XCTAssertTrue(n.autoTags.isEmpty, "no auto numbers when the flag is off")
        XCTAssertEqual(n.labels["b"], "7", "a manual tag still resolves references")
        XCTAssertNil(n.labels["a"], "an untagged equation (auto off) has no number")
    }

    func testResolveReferences() {
        let labels = ["eq:a": "1", "eq:c": "3.1"]
        XCTAssertEqual(MathNumbering.resolveReferences(#"see \eqref{eq:a}"#, labels: labels), "see (1)")
        XCTAssertEqual(MathNumbering.resolveReferences(#"eq \ref{eq:c}"#, labels: labels), "eq 3.1")
        XCTAssertEqual(MathNumbering.resolveReferences(#"\eqref{missing}"#, labels: labels), "(?)")
    }

    func testReferenceCommandBoundary() {
        // \ref must not fire inside a longer command name.
        XCTAssertEqual(MathNumbering.resolveReferences(#"\reflectbox{x} \ref{a}"#, labels: ["a": "9"]),
                       #"\reflectbox{x} 9"#)
    }

    func testInlineMathIsNotNumbered() {
        let n = MathNumbering.number(#"inline $x=1$ only"#, autoNumber: true)
        XCTAssertTrue(n.autoTags.isEmpty)
    }

    func testStripDirectivesRemovesLabelNotagKeepsTag() {
        XCTAssertEqual(MathNumbering.stripDirectives(#"E = mc^2 \label{eq:e}"#), "E = mc^2 ")
        XCTAssertEqual(MathNumbering.stripDirectives(#"x = 1 \notag"#), "x = 1 ")
        XCTAssertEqual(MathNumbering.stripDirectives(#"y \tag{3} \label{k}"#), #"y \tag{3} "#)
        // The stripped equation is fully supported (no stray unknown command).
        XCTAssertTrue(MathParser.isFullySupported(
            MathParser.parse(MathNumbering.stripDirectives(#"E = mc^2 \label{eq:e}"#))))
    }
}
