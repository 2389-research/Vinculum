import XCTest
import Foundation
@testable import VinculumLayout

/// Presentation MathML export. Platform-free string building; tests verify both the
/// structure (msup/mfrac/mmultiscripts…) and that the output is well-formed XML.
final class MathMLExporterTests: XCTestCase {

    private func ml(_ src: String, display: Bool = false) -> String {
        MathMLExporter.export(MathParser.parse(src), display: display)
    }

    func testDocumentWrapperAndNamespace() {
        let s = ml("x")
        XCTAssertTrue(s.hasPrefix(#"<math xmlns="http://www.w3.org/1998/Math/MathML">"#))
        XCTAssertTrue(s.hasSuffix("</math>"))
        XCTAssertTrue(ml("x", display: true).contains(#"display="block""#))
    }

    func testTokenClasses() {
        XCTAssertTrue(ml("x").contains("<mi>x</mi>"))       // identifier
        XCTAssertTrue(ml("2").contains("<mn>2</mn>"))       // number
        XCTAssertTrue(ml("a+b").contains("<mo>+</mo>"))     // operator
    }

    func testStructures() {
        XCTAssertTrue(ml("x^2").contains("<msup><mi>x</mi><mn>2</mn></msup>"))
        XCTAssertTrue(ml("x_i").contains("<msub>"))
        XCTAssertTrue(ml("x_i^2").contains("<msubsup>"))
        XCTAssertTrue(ml(#"\frac{a}{b}"#).contains("<mfrac><mi>a</mi><mi>b</mi></mfrac>"))
        XCTAssertTrue(ml(#"\sqrt{x}"#).contains("<msqrt>"))
        XCTAssertTrue(ml(#"\sqrt[3]{x}"#).contains("<mroot>"))
        XCTAssertTrue(ml(#"\hat{x}"#).contains(#"<mover accent="true">"#))
        XCTAssertTrue(ml(#"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#).contains("<mtable><mtr><mtd>"))
    }

    func testPrescriptsUseMmultiscripts() {
        let s = ml(#"\prescript{14}{6}{C}"#)
        XCTAssertTrue(s.contains("<mmultiscripts>"))
        XCTAssertTrue(s.contains("<mprescripts/>"))
    }

    func testXmlSpecialCharactersEscaped() {
        let s = ml("a < b & c > d")
        XCTAssertTrue(s.contains("&lt;"))
        XCTAssertTrue(s.contains("&gt;"))
        XCTAssertTrue(s.contains("&amp;"))
        XCTAssertFalse(s.contains("<mo><</mo>"), "raw < would be invalid XML")
    }

    func testUnsupportedBecomesMerror() {
        XCTAssertTrue(ml(#"\notarealcommand{x}"#).contains("<merror>"))
    }

    /// Every exported document must be well-formed markup — the whole point of an
    /// interop/accessibility serializer (a malformed string is silently dropped).
    /// Checked with a tiny dependency-free scanner, not an XML library, so the test
    /// suite stays free of the Linux `FoundationXML` split.
    func testOutputIsWellFormed() {
        let cases = ["x^2", #"\frac{a}{b}"#, #"\sqrt[3]{x+1}"#, #"\sum_{i=1}^{n} i"#,
                     #"\begin{bmatrix}1&0\\0&1\end{bmatrix}"#, "a < b & c",
                     #"\prescript{14}{6}{C}"#, #"\left( \frac{a}{b} \right)"#,
                     #"\hat{x} + \vec{v}"#, #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#]
        for src in cases {
            let xml = MathMLExporter.export(MathParser.parse(src))
            XCTAssertNil(wellFormednessError(xml), "malformed for \(src): \(xml)")
        }
    }

    /// Returns the first well-formedness problem in `xml`, or nil if it's clean:
    /// every tag balances (nesting order respected), and text between tags carries
    /// no raw `<`/`&`. Void tags (`<mprescripts/>`, `<none/>`, `<mspace…/>`) self-close.
    private func wellFormednessError(_ xml: String) -> String? {
        // Scan UNICODE SCALARS, not Characters: MathML embeds combining marks
        // (e.g. \vec's U+20D7) that would otherwise cluster with the preceding
        // '>' and hide a tag boundary.
        let s = Array(xml.unicodeScalars)
        func str(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(s[range])) }
        var i = 0
        var stack: [String] = []
        while i < s.count {
            let c = s[i]
            if c == "<" {
                var j = i + 1
                while j < s.count, s[j] != ">" { j += 1 }
                guard j < s.count else { return "unterminated tag" }
                let tag = str((i + 1)..<j)
                i = j + 1
                if tag.hasPrefix("/") {                          // closing tag
                    let name = String(tag.dropFirst())
                    guard stack.popLast() == name else { return "mismatched </\(name)>" }
                } else if tag.hasSuffix("/") {                   // self-closing — no push
                    continue
                } else {                                         // opening tag
                    let name = tag.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? tag
                    stack.append(name)
                }
            } else {
                if c == "&" {                                    // must begin a valid entity
                    let rest = str(i..<min(i + 6, s.count))
                    let ok = ["&amp;", "&lt;", "&gt;", "&quot;", "&apos;"].contains { rest.hasPrefix($0) }
                    if !ok { return "raw & in text" }
                }
                i += 1
            }
        }
        return stack.isEmpty ? nil : "unclosed \(stack)"
    }
}
