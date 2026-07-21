import XCTest
import Foundation
@testable import VinculumLayout

/// siunitx (`\num`, `\ang`, `\si`/`\unit`, `\SI`/`\qty`). A transpiler to LaTeX —
/// verify the transpiled string and that the result is fully supported.
final class MathSIUnitxTests: XCTestCase {

    // MARK: - Numbers

    func testScientificNotation() {
        XCTAssertEqual(SIUnitx.number("1.5e3"), "1.5 \\times 10^{3}")
        XCTAssertEqual(SIUnitx.number("3.0e8"), "3.0 \\times 10^{8}")
    }

    func testNegativeAndSignedExponent() {
        XCTAssertEqual(SIUnitx.number("-3.2e-4"), "-3.2 \\times 10^{-4}")
    }

    func testDigitGroupingAppliesFromFiveDigits() {
        XCTAssertEqual(SIUnitx.number("12345"), "12\\,345")
        XCTAssertEqual(SIUnitx.number("1234"), "1234", "four digits are not grouped")
        XCTAssertEqual(SIUnitx.number("299792458"), "299\\,792\\,458")
    }

    func testFractionGrouping() {
        // Integer part grouped, short fraction left alone.
        XCTAssertEqual(SIUnitx.number("12345.678"), "12\\,345.678")
    }

    // MARK: - Angles

    func testAngleDegreesOnly() {
        XCTAssertEqual(SIUnitx.angle("45"), "45^{\\circ}")
    }

    func testAngleDMS() {
        XCTAssertEqual(SIUnitx.angle("45;30;15"), "45^{\\circ}30'15''")
    }

    // MARK: - Units

    func testLiteralUnitProductAndPower() {
        XCTAssertEqual(SIUnitx.units("kg.m.s^{-1}"),
                       "\\mathrm{kg}\\,\\mathrm{m}\\,\\mathrm{s}^{-1}")
    }

    func testUnitSolidus() {
        XCTAssertEqual(SIUnitx.units("m/s^2"), "\\mathrm{m}/\\mathrm{s}^{2}")
    }

    func testPrefixHugsUnit() {
        // \kilo\gram → a single upright run "kg", not two spaced atoms.
        XCTAssertEqual(SIUnitx.units("\\kilo\\gram"), "\\mathrm{kg}")
    }

    func testMicroUsesUnicodeGlyph() {
        // µ (U+00B5) so \mathrm keeps it upright without re-tokenizing a command.
        XCTAssertEqual(SIUnitx.units("\\micro\\metre"), "\\mathrm{\u{00B5}m}")
    }

    func testPerAndSquaredMacros() {
        XCTAssertEqual(SIUnitx.units("\\metre\\per\\second\\squared"),
                       "\\mathrm{m}/\\mathrm{s}^{2}")
    }

    func testDegreeCelsius() {
        XCTAssertEqual(SIUnitx.units("\\degreeCelsius"), "^{\\circ}\\mathrm{C}")
    }

    func testUnknownMacroPassesThrough() {
        // A non-unit command survives as a real command (renders, never dropped).
        XCTAssertEqual(SIUnitx.units("\\alpha"), "\\alpha ")
    }

    // MARK: - Quantities & end-to-end parse

    func testQuantityJoinsNumberAndUnit() {
        XCTAssertEqual(SIUnitx.quantity("9.8", "m/s^2"),
                       "9.8\\,\\mathrm{m}/\\mathrm{s}^{2}")
    }

    func testEndToEndFullySupported() {
        for src in [#"\num{1.5e3}"#, #"\num{12345.678}"#, #"\ang{45;30;15}"#,
                    #"\si{kg.m.s^{-1}}"#, #"\unit{\kilo\gram}"#, #"\SI{9.8}{m/s^2}"#,
                    #"\qty{3.0e8}{m/s}"#, #"\si{\ohm}"#, #"\si{\micro\metre}"#,
                    #"\SI{25}{\degreeCelsius}"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(src)), "\(src) fully supported")
        }
    }

    func testSIWithMissingSecondArgFallsBackToNumber() {
        // Defensive: \SI with only one body still renders the number.
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(#"\SI{42}"#)))
    }
}
