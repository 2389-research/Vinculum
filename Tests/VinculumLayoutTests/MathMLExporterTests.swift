import XCTest
import Foundation
#if canImport(FoundationXML)
import FoundationXML   // On Linux, XMLParser lives here, not in base Foundation.
#endif
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

    /// Every exported document must be well-formed XML — the whole point of an
    /// interop/accessibility serializer.
    func testOutputIsWellFormedXML() {
        let cases = ["x^2", #"\frac{a}{b}"#, #"\sqrt[3]{x+1}"#, #"\sum_{i=1}^{n} i"#,
                     #"\begin{bmatrix}1&0\\0&1\end{bmatrix}"#, "a < b & c",
                     #"\prescript{14}{6}{C}"#, #"\left( \frac{a}{b} \right)"#,
                     #"\hat{x} + \vec{v}"#, #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#]
        for src in cases {
            let xml = MathMLExporter.export(MathParser.parse(src))
            let parser = XMLParser(data: Data(xml.utf8))
            XCTAssertTrue(parser.parse(), "not well-formed XML for \(src): \(xml)  err=\(String(describing: parser.parserError))")
        }
    }
}
