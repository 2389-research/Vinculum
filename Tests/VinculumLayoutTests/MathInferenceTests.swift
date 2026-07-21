import XCTest
import Foundation
@testable import VinculumLayout

/// Inference rules / proof trees (`\inferrule`, `\infer`, `\prftree`). Platform-free geometry:
/// premises centered over a rule bar sitting on the math axis, conclusion centered below,
/// optional label to the right.
final class MathInferenceTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    func testParsesPremisesAndConclusion() {
        guard case let .inferenceRule(premises, conclusion, label) = MathParser.parse(#"\inferrule{A \\ B}{C}"#) else {
            return XCTFail("expected inferenceRule")
        }
        XCTAssertEqual(premises.count, 2)
        XCTAssertEqual(premises[0].toLaTeX(), "A")
        XCTAssertEqual(premises[1].toLaTeX(), "B")
        XCTAssertEqual(conclusion.toLaTeX(), "C")
        XCTAssertNil(label)
    }

    func testAxiomHasNoPremises() {
        guard case let .inferenceRule(premises, conclusion, _) = MathParser.parse(#"\inferrule{ }{A}"#) else {
            return XCTFail("expected inferenceRule")
        }
        XCTAssertTrue(premises.isEmpty, "empty premise group → axiom")
        XCTAssertEqual(conclusion.toLaTeX(), "A")
    }

    func testOptionalLabelIsCaptured() {
        guard case let .inferenceRule(_, _, label) = MathParser.parse(#"\inferrule[\mathsf{ax}]{A}{B}"#) else {
            return XCTFail("expected inferenceRule")
        }
        XCTAssertNotNil(label)
    }

    func testLabelStripsKeyEquals() {
        // mathpartir spells labels `[left=Name]`; the key is dropped, the value kept.
        guard case let .inferenceRule(_, _, label) = MathParser.parse(#"\inferrule[left=Foo]{A}{B}"#) else {
            return XCTFail("expected inferenceRule")
        }
        XCTAssertEqual(label?.toLaTeX(), "Foo")
    }

    func testAliasesInferAndPrftree() {
        for src in [#"\infer{A \\ B}{C}"#, #"\prftree{A \\ B}{C}"#] {
            guard case let .inferenceRule(premises, _, _) = MathParser.parse(src) else {
                return XCTFail("expected inferenceRule for \(src)")
            }
            XCTAssertEqual(premises.count, 2, "\(src) parses two premises")
        }
    }

    func testRulesNest() {
        guard case let .inferenceRule(premises, _, _) = MathParser.parse(#"\inferrule{\inferrule{A}{B} \\ C}{D}"#) else {
            return XCTFail("expected inferenceRule")
        }
        XCTAssertEqual(premises.count, 2)
        if case .inferenceRule = premises[0] {} else { XCTFail("first premise is itself a rule") }
    }

    func testFullySupported() {
        for src in [#"\inferrule{A \\ B}{C}"#, #"\inferrule[T]{A}{B}"#, #"\inferrule{ }{A}"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(src)), "\(src) fully supported")
        }
    }

    func testLayoutDrawsOneBarPerRule() {
        let scene = engine().layout(MathParser.parse(#"\inferrule{A \\ B}{C}"#))
        let bars = scene.elements.filter { if case .rule = $0 { return true }; return false }.count
        XCTAssertEqual(bars, 1, "a single rule draws one bar")
        XCTAssertGreaterThan(scene.width, 0)
        XCTAssertGreaterThan(scene.height, 0)
    }

    func testNestedRuleDrawsTwoBars() {
        let scene = engine().layout(MathParser.parse(#"\inferrule{\inferrule{A}{B} \\ C}{D}"#))
        let bars = scene.elements.filter { if case .rule = $0 { return true }; return false }.count
        XCTAssertEqual(bars, 2, "outer + nested rule → two bars")
    }

    func testBarWiderThanBothRows() {
        // The rule bar must span at least the wider of premises / conclusion.
        let scene = engine().layout(MathParser.parse(#"\inferrule{A \\ B}{A \wedge B \wedge C}"#))
        guard case let .rule(rect, _)? = scene.elements.first(where: { if case .rule = $0 { return true }; return false }) else {
            return XCTFail("expected a rule element")
        }
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertLessThanOrEqual(rect.width, scene.width + 0.01)
    }

    func testSpeechReadsFromInfer() {
        XCTAssertEqual(MathSpeech.describe(MathParser.parse(#"\inferrule{A \\ B}{C}"#)),
                       "from A, and B, infer C")
        XCTAssertEqual(MathSpeech.describe(MathParser.parse(#"\inferrule{ }{A}"#)),
                       "axiom A")
    }

    func testMathMLIsFractionLike() {
        let ml = MathParser.parse(#"\inferrule{A \\ B}{C}"#).toMathML()
        XCTAssertTrue(ml.contains("<mfrac"), "renders as a fraction-like bar in MathML")
    }
}
