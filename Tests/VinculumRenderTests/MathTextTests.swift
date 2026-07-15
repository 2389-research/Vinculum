#if canImport(AppKit) || canImport(UIKit)
import XCTest
@testable import VinculumRender
import VinculumLayout

/// The document pipeline: whole strings with embedded math become styled
/// text with inline attachments — the LLM-output / markdown-note use case.
@MainActor
final class MathTextTests: XCTestCase {

    private func attachmentCount(_ s: NSAttributedString) -> Int {
        var count = 0
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, _ in
            if v is NSTextAttachment { count += 1 }
        }
        return count
    }

    func testMixedProseAndInlineMath() {
        let doc = #"The identity $e^{i\pi} + 1 = 0$ is due to Euler."#
        let out = MathText.attributedString(from: doc)
        XCTAssertEqual(attachmentCount(out), 1)
        XCTAssertTrue(out.string.hasPrefix("The identity "))
        XCTAssertTrue(out.string.hasSuffix(" is due to Euler."))
    }

    func testAllFourDelimiterStyles() {
        let doc = #"a $x$ b \(y\) c $$z$$ d \[w\] e"#
        let out = MathText.attributedString(from: doc)
        XCTAssertEqual(attachmentCount(out), 4)
        for word in ["a ", " b ", " c ", " d ", " e"] {
            XCTAssertTrue(out.string.contains(word), "prose lost around math: \(word)")
        }
    }

    func testDisplayMathGetsItsOwnCenteredParagraph() throws {
        let out = MathText.attributedString(from: #"Before $$\frac{a}{b}$$ after."#)
        XCTAssertEqual(attachmentCount(out), 1)
        // The attachment is surrounded by newlines and carries centering.
        let attachmentRange = try XCTUnwrap(rangeOfFirstAttachment(out))
        let style = out.attribute(.paragraphStyle, at: attachmentRange.location,
                                  effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.alignment, .center)
        let before = (out.string as NSString).substring(to: attachmentRange.location)
        XCTAssertTrue(before.hasSuffix("\n"), "display math starts a new paragraph")
    }

    func testUnsupportedMathFallsBackToVisibleSource() {
        let out = MathText.attributedString(from: #"see $\nosuchcmd{x}$ here"#)
        XCTAssertEqual(attachmentCount(out), 0)
        XCTAssertTrue(out.string.contains(#"$\nosuchcmd{x}$"#),
                      "unsupported math must stay VISIBLE as source, never dropped")
        XCTAssertTrue(out.string.contains("see "), "surrounding prose intact")
    }

    func testDocumentScopedMacros() {
        let doc = #"Define $\newcommand{\R}{\mathbb{R}}$ then use $x \in \R$."#
        let out = MathText.attributedString(from: doc)
        // The definition segment renders nothing; the use renders natively.
        XCTAssertEqual(attachmentCount(out), 1)
        XCTAssertFalse(out.string.contains("newcommand"))
    }

    func testEscapedDollarIsProse() {
        let out = MathText.attributedString(from: #"It costs \$5 today."#)
        XCTAssertEqual(attachmentCount(out), 0)
        XCTAssertTrue(out.string.contains("$5"), "escaped dollar renders as a dollar sign")
    }

    func testLLMStyleResponse() {
        // The exact shape a model emits: prose, inline \( \), display \[ \].
        let doc = """
        The quadratic formula solves \\(ax^2 + bx + c = 0\\):

        \\[ x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a} \\]

        where \\(a \\ne 0\\).
        """
        let out = MathText.attributedString(from: doc)
        XCTAssertEqual(attachmentCount(out), 3)
        XCTAssertTrue(out.string.contains("The quadratic formula solves"))
        XCTAssertTrue(out.string.contains("where"))
    }

    private func rangeOfFirstAttachment(_ s: NSAttributedString) -> NSRange? {
        var found: NSRange?
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, r, stop in
            if v is NSTextAttachment { found = r; stop.pointee = true }
        }
        return found
    }
}
#endif
