import XCTest
import Foundation
@testable import VinculumLayout

/// physics package (Dirac notation, derivatives, brackets). A transpiler to LaTeX —
/// verify the transpiled template and that the result is fully supported.
final class MathPhysicsTests: XCTestCase {

    // MARK: - Dirac notation

    func testBraKet() {
        XCTAssertEqual(Physics.bra("\\psi"), "\\left\\langle \\psi \\right|")
        XCTAssertEqual(Physics.ket("\\psi"), "\\left| \\psi \\right\\rangle")
    }

    func testBraketTwoAndOneArg() {
        XCTAssertEqual(Physics.braket("\\phi", "\\psi"),
                       "\\left\\langle \\phi \\middle| \\psi \\right\\rangle")
        // Single argument is used on both sides.
        XCTAssertEqual(Physics.braket("\\psi", nil),
                       "\\left\\langle \\psi \\middle| \\psi \\right\\rangle")
    }

    func testExpvalWithAndWithoutState() {
        XCTAssertEqual(Physics.expval("A", nil), "\\left\\langle A \\right\\rangle")
        XCTAssertEqual(Physics.expval("A", "\\psi"),
                       "\\left\\langle \\psi \\right| A \\left| \\psi \\right\\rangle")
    }

    func testMatrixElement() {
        XCTAssertEqual(Physics.mel("\\phi", "H", "\\psi"),
                       "\\left\\langle \\phi \\right| H \\left| \\psi \\right\\rangle")
    }

    // MARK: - Derivatives

    func testDifferential() {
        XCTAssertEqual(Physics.dd("x"), "\\mathrm{d} x")
        XCTAssertEqual(Physics.dd(nil), "\\mathrm{d}")
    }

    func testOrdinaryDerivative() {
        XCTAssertEqual(Physics.dv("f", "x", order: nil), "\\frac{\\mathrm{d} f}{\\mathrm{d} x}")
        XCTAssertEqual(Physics.dv("f", "x", order: "2"),
                       "\\frac{\\mathrm{d}^{2} f}{\\mathrm{d} x^{2}}")
        // Order 1 is the same as no order (no exponent).
        XCTAssertEqual(Physics.dv("f", "x", order: "1"), "\\frac{\\mathrm{d} f}{\\mathrm{d} x}")
    }

    func testPartialDerivativeAndMixed() {
        XCTAssertEqual(Physics.pdv("f", "x", nil, order: nil), "\\frac{\\partial f}{\\partial x}")
        XCTAssertEqual(Physics.pdv("f", "x", "y", order: nil),
                       "\\frac{\\partial^{2} f}{\\partial x \\partial y}")
        XCTAssertEqual(Physics.pdv("f", "x", nil, order: "2"),
                       "\\frac{\\partial^{2} f}{\\partial x^{2}}")
    }

    // MARK: - Brackets

    func testBrackets() {
        XCTAssertEqual(Physics.abs("x"), "\\left| x \\right|")
        XCTAssertEqual(Physics.norm("v"), "\\left\\| v \\right\\|")
        XCTAssertEqual(Physics.comm("A", "B"), "\\left[ A, B \\right]")
        XCTAssertEqual(Physics.acomm("A", "B"), "\\left\\{ A, B \\right\\}")
    }

    // MARK: - The `\|` norm-delimiter fix

    func testNormDelimiterParsesToDoubleBar() {
        guard case let .delimited(left, _, right) = MathParser.parse(#"\left\| v \right\|"#) else {
            return XCTFail("expected delimited")
        }
        XCTAssertEqual(left, "‖")
        XCTAssertEqual(right, "‖")
    }

    func testNormRendersWithDoubleBar() {
        guard case let .delimited(left, _, right) = MathParser.parse(#"\norm{\psi}"#) else {
            return XCTFail("expected delimited")
        }
        XCTAssertEqual(left, "‖", "\\norm uses the ‖ delimiter, not fallback parens")
        XCTAssertEqual(right, "‖")
    }

    // MARK: - Vector operators

    func testVectorOperators() {
        XCTAssertEqual(Physics.vectorOperator("grad"), "\\nabla")
        XCTAssertEqual(Physics.vectorOperator("curl"), "\\nabla \\times")
        XCTAssertEqual(Physics.vectorOperator("laplacian"), "\\nabla^{2}")
        XCTAssertNil(Physics.vectorOperator("div"), "\\div stays the core division sign")
    }

    // MARK: - End-to-end

    func testEndToEndFullySupported() {
        for src in [#"\bra{\phi}"#, #"\ket{\psi}"#, #"\braket{\phi}{\psi}"#, #"\braket{\psi}"#,
                    #"\ketbra{\psi}{\phi}"#, #"\expval{\hat{H}}{\psi}"#, #"\mel{\phi}{\hat{A}}{\psi}"#,
                    #"\dv{f}{x}"#, #"\dv[2]{f}{x}"#, #"\pdv{f}{x}"#, #"\pdv{f}{x}{y}"#, #"\dd{x}"#,
                    #"\abs{x}"#, #"\norm{v}"#, #"\comm{A}{B}"#, #"\acomm{A}{B}"#, #"\order{x^2}"#,
                    #"\grad \phi"#, #"\curl \vec{F}"#, #"\laplacian \phi"#, #"\Tr \rho"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(src)), "\(src) fully supported")
        }
    }
}
