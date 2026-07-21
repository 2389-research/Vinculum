import XCTest
import Foundation
@testable import VinculumLayout

/// mhchem `\ce{…}` — the transpiler to LaTeX and end-to-end parse. Platform-free.
final class MHChemTests: XCTestCase {

    func testAutoSubscripts() {
        XCTAssertEqual(MHChem.transpile("H2O"), #"\mathrm{H}_{2}\mathrm{O}"#)
        XCTAssertEqual(MHChem.transpile("CO2"), #"\mathrm{C}\mathrm{O}_{2}"#)
    }

    func testCoefficientVsSubscript() {
        // Leading number is a coefficient; a number after an atom is a subscript.
        XCTAssertEqual(MHChem.transpile("2H2"), #"2\mathrm{H}_{2}"#)
    }

    func testGroupSubscript() {
        XCTAssertEqual(MHChem.transpile("Ca(OH)2"), #"\mathrm{Ca}(\mathrm{O}\mathrm{H})_{2}"#)
    }

    func testCharges() {
        XCTAssertEqual(MHChem.transpile("SO4^2-"), #"\mathrm{S}\mathrm{O}_{4}^{2-}"#)
        XCTAssertEqual(MHChem.transpile("Na^+"), #"\mathrm{Na}^{+}"#)
    }

    func testArrows() {
        XCTAssertTrue(MHChem.transpile("A -> B").contains(#"\longrightarrow"#))
        XCTAssertTrue(MHChem.transpile("A <=> B").contains(#"\rightleftharpoons"#))
        XCTAssertTrue(MHChem.transpile("A <- B").contains(#"\longleftarrow"#))
    }

    func testConditionalArrowUsesXrightarrow() {
        let t = MHChem.transpile(#"A ->[\Delta] B"#)
        XCTAssertTrue(t.contains(#"\xrightarrow"#), t)
        XCTAssertTrue(t.contains(#"\Delta"#), "the LaTeX command passes through, not read as an element: \(t)")
    }

    func testHydrateDotAndTripleBond() {
        XCTAssertTrue(MHChem.transpile("CuSO4 * 5H2O").contains(#"\cdot"#))
        XCTAssertTrue(MHChem.transpile("C#N").contains(#"\equiv"#))
    }

    func testEndToEndFullySupported() {
        for src in [#"\ce{H2O}"#, #"\ce{Ca^2+}"#, #"\ce{SO4^2-}"#, #"\ce{2H2 + O2 -> 2H2O}"#,
                    #"\ce{Ca(OH)2}"#, #"\ce{N2 + 3H2 <=> 2NH3}"#, #"\ce{CuSO4 * 5H2O}"#,
                    #"\ce{CaCO3 ->[\Delta] CaO + CO2}"#, #"\ce{CO2(g)}"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(src)),
                          "\(src) must render, not fall back")
        }
    }

    func testCeRendersAsScriptsNotLiteral() {
        // \ce{H2O} lays out with a subscript (a scripts node), not literal "H2O".
        let node = MathParser.parse(#"\ce{H2O}"#)
        let hasScript = node.children.contains { if case .scripts = $0 { return true }; return false }
            || { if case .row(let r) = node { return r.contains { if case .scripts = $0 { return true }; return false } }; return false }()
        XCTAssertTrue(hasScript, "the 2 in H2O is a subscript")
    }
}
