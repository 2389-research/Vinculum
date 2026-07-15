import XCTest
@testable import VinculumLayout

/// parse diagnostics with SOURCE RANGES — an editor host
/// can underline the exact offending token.
final class MathDiagnosticsRangeTests: XCTestCase {

    func testUnknownCommandCarriesItsRange() throws {
        let latex = #"x + \badcmd{y} + z"#
        let issues = MathParser.diagnostics(for: latex)
        XCTAssertEqual(issues.count, 1)
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.source, "\\badcmd")
        XCTAssertTrue(issue.message.contains("badcmd"))
        let range = try XCTUnwrap(issue.range)
        XCTAssertEqual(String(latex[range]), "\\badcmd")
    }

    func testMultipleIssuesInSourceOrderWithDistinctRanges() throws {
        let latex = #"\foo + \frac{\foo}{\baz}"#
        let issues = MathParser.diagnostics(for: latex)
        XCTAssertEqual(issues.map(\.source), ["\\foo", "\\foo", "\\baz"])
        let r0 = try XCTUnwrap(issues[0].range)
        let r1 = try XCTUnwrap(issues[1].range)
        let r2 = try XCTUnwrap(issues[2].range)
        // The duplicate \foo maps to its SECOND occurrence, not the first again.
        XCTAssertLessThan(r0.lowerBound, r1.lowerBound)
        XCTAssertLessThan(r1.lowerBound, r2.lowerBound)
        XCTAssertEqual(String(latex[r1]), "\\foo")
        XCTAssertEqual(String(latex[r2]), "\\baz")
    }

    func testSupportedInputHasNoIssues() {
        XCTAssertTrue(MathParser.diagnostics(for: #"x = \frac{a}{b} + \sqrt{c}"#).isEmpty)
    }

    func testUnlocatableIssueKeepsNilRange() {
        // Macro expansion rewrites the source before parsing, so a leaf's
        // snippet may not exist verbatim in the ORIGINAL input; the issue is
        // still reported, honestly range-less (never a wrong range).
        let issues = MathParser.diagnostics(for: "x + y", parsing: #"\nosuchcmd"#)
        XCTAssertEqual(issues.first?.source, "\\nosuchcmd")
        XCTAssertNil(issues.first?.range)
    }
}
