import XCTest
import Foundation
@testable import VinculumLayout

/// Syntax / parse trees (`\Tree`, qtree). Platform-free tidy-tree geometry: labelled
/// nodes over their children, joined by stroked edges.
final class MathSyntaxTreeTests: XCTestCase {

    private func engine(_ size: CGFloat = 10) -> MathLayoutEngine {
        MathLayoutEngine(measure: standardMockMeasurer, baseSize: size)
    }

    private func nodeCount(_ n: SyntaxTreeNode) -> Int {
        1 + n.children.reduce(0) { $0 + nodeCount($1) }
    }

    func testParsesNestedStructure() {
        guard case let .syntaxTree(root) = MathParser.parse(#"\Tree [.S [.NP a ] [.VP b ] ]"#) else {
            return XCTFail("expected syntaxTree")
        }
        XCTAssertEqual(root.label.toLaTeX(), "S")
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[0].label.toLaTeX(), "NP")
        XCTAssertEqual(root.children[0].children.count, 1, "NP has one leaf child")
        XCTAssertTrue(root.children[0].children[0].isLeaf)
    }

    func testLeafHasNoChildren() {
        guard case let .syntaxTree(root) = MathParser.parse(#"\Tree [.A b c ]"#) else {
            return XCTFail("expected syntaxTree")
        }
        XCTAssertEqual(nodeCount(root), 3, "A over b, c")
        XCTAssertTrue(root.children.allSatisfy(\.isLeaf))
    }

    func testBracedMultiCharLabels() {
        guard case let .syntaxTree(root) = MathParser.parse(#"\Tree [.{S} [.{NP} \text{Kim} ] ]"#) else {
            return XCTFail("expected syntaxTree")
        }
        XCTAssertEqual(root.children.count, 1)
        // The {NP} label survives as a group, the \text{Kim} leaf too.
        XCTAssertEqual(nodeCount(root), 3)
    }

    func testQtreeAlias() {
        if case .syntaxTree = MathParser.parse(#"\qtree [.A b ]"#) {} else {
            XCTFail("\\qtree should also produce a syntaxTree")
        }
    }

    func testFullySupported() {
        for src in [#"\Tree [.S [.NP [.D the ] [.N dog ] ] [.VP barks ] ]"#,
                    #"\Tree [.A b c ]"#, #"\Tree [.{+} [.{\times} a b ] c ]"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(src)), "\(src) fully supported")
        }
    }

    func testLayoutDrawsOneEdgePerParentChildLink() {
        // S→NP, S→VP, NP→D, NP→N, D→the, N→dog, VP→barks = 7 edges.
        let scene = engine().layout(MathParser.parse(
            #"\Tree [.S [.NP [.D the ] [.N dog ] ] [.VP barks ] ]"#))
        let edges = scene.elements.filter { if case .stroke = $0 { return true }; return false }.count
        XCTAssertEqual(edges, 7)
        XCTAssertGreaterThan(scene.width, 0)
        XCTAssertGreaterThan(scene.height, 0)
    }

    func testDeeperTreeIsTaller() {
        let shallow = engine().layout(MathParser.parse(#"\Tree [.A b c ]"#)).height
        let deep = engine().layout(MathParser.parse(#"\Tree [.A [.B [.C d ] ] ]"#)).height
        XCTAssertGreaterThan(deep, shallow, "more levels → taller")
    }

    func testLeafGlyphsPresent() {
        let scene = engine().layout(MathParser.parse(#"\Tree [.A b c ]"#))
        let glyphs = scene.elements.filter { if case .glyphs = $0 { return true }; return false }.count
        XCTAssertGreaterThanOrEqual(glyphs, 3, "A, b, c each draw a glyph run")
    }

    func testRoundTripsToTree() {
        let src = #"\Tree [.S [.NP a ] [.VP b ] ]"#
        let latex = MathParser.parse(src).toLaTeX()
        XCTAssertTrue(latex.hasPrefix("\\Tree "))
        // Re-parsing the emitted LaTeX yields the same structure.
        guard case let .syntaxTree(root) = MathParser.parse(latex) else {
            return XCTFail("re-parse failed: \(latex)")
        }
        XCTAssertEqual(root.children.count, 2)
    }

    func testSpeechDescribesStructure() {
        let speech = MathSpeech.describe(MathParser.parse(#"\Tree [.S a b ]"#))
        XCTAssertTrue(speech.contains("tree"), "speech names it a tree: \(speech)")
        XCTAssertTrue(speech.contains("over"), "parent-over-children: \(speech)")
    }
}
