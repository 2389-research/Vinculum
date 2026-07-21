import XCTest
import Foundation
@testable import VinculumLayout

/// The arithmetic expression evaluator behind function plots.
final class MathExpressionTests: XCTestCase {

    private func eval(_ s: String, at x: Double) -> Double? { MathExpression(s).map { $0(x) } }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(eval("2 + 3 * 4", at: 0)!, 14, accuracy: 1e-12)
        XCTAssertEqual(eval("(2 + 3) * 4", at: 0)!, 20, accuracy: 1e-12)
        XCTAssertEqual(eval("x^2", at: 3)!, 9, accuracy: 1e-12)
        XCTAssertEqual(eval("2*x + 1", at: 4)!, 9, accuracy: 1e-12)
    }

    func testUnaryMinusBindsLooserThanPower() {
        XCTAssertEqual(eval("-x^2", at: 2)!, -4, accuracy: 1e-12, "-x^2 is -(x^2)")
        XCTAssertEqual(eval("-2^2", at: 0)!, -4, accuracy: 1e-12)
    }

    func testPowerRightAssociative() {
        XCTAssertEqual(eval("2^3^2", at: 0)!, 512, accuracy: 1e-9, "2^(3^2) = 512")
    }

    func testFunctionsAndConstants() {
        XCTAssertEqual(eval("sin(0)", at: 0)!, 0, accuracy: 1e-12)
        XCTAssertEqual(eval("cos(0)", at: 0)!, 1, accuracy: 1e-12)
        XCTAssertEqual(eval("exp(0)", at: 0)!, 1, accuracy: 1e-12)
        XCTAssertEqual(eval("sqrt(x)", at: 16)!, 4, accuracy: 1e-12)
        XCTAssertEqual(eval("pi", at: 0)!, Double.pi, accuracy: 1e-12)
        XCTAssertEqual(eval("1/(1+x^2)", at: 1)!, 0.5, accuracy: 1e-12)
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(MathExpression("x +"))
        XCTAssertNil(MathExpression("(x"))
        XCTAssertNil(MathExpression("*x"))
    }

    func testNiceStepAndFormat() {
        XCTAssertEqual(MathLayoutEngine.niceStep(10, 5), 2, accuracy: 1e-9)
        XCTAssertEqual(MathLayoutEngine.niceStep(1, 5), 0.2, accuracy: 1e-9)
        XCTAssertEqual(MathLayoutEngine.fmt(0), "0")
        XCTAssertEqual(MathLayoutEngine.fmt(2.5), "2.5")
        XCTAssertEqual(MathLayoutEngine.fmt(3), "3")
    }
}
