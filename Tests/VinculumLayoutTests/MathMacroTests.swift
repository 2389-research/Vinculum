import XCTest
@testable import VinculumLayout

/// Document-scoped math macros: \newcommand/\def collected from all math,
/// expanded at use, order-independent, recursion-capped.
final class MathMacroTests: XCTestCase {

    // MARK: - Definition collection

    func testCollectsNewcommandZeroArg() {
        let table = MathMacros.collectDefinitions(from: "text $$\\newcommand{\\R}{\\mathbb{R}}$$ more")
        XCTAssertEqual(table.macros["R"]?.body, "\\mathbb{R}")
        XCTAssertEqual(table.macros["R"]?.argCount, 0)
    }

    func testCollectsNewcommandWithArgs() {
        let table = MathMacros.collectDefinitions(from: "$$\\newcommand{\\abs}[1]{\\left|#1\\right|}$$")
        XCTAssertEqual(table.macros["abs"]?.argCount, 1)
        XCTAssertEqual(table.macros["abs"]?.body, "\\left|#1\\right|")
    }

    func testCollectsDef() {
        let table = MathMacros.collectDefinitions(from: "$$\\def\\Z{\\mathbb{Z}}$$")
        XCTAssertEqual(table.macros["Z"]?.body, "\\mathbb{Z}")
    }

    func testIgnoresDefinitionsOutsideMath() {
        // A \newcommand in prose or a code fence must not register.
        let table = MathMacros.collectDefinitions(from: "Here is `\\newcommand{\\R}{x}` in code.")
        XCTAssertTrue(table.isEmpty)
    }

    func testLaterDefinitionWins() {
        let table = MathMacros.collectDefinitions(from: "$$\\def\\a{1}$$ $$\\def\\a{2}$$")
        XCTAssertEqual(table.macros["a"]?.body, "2")
    }

    // MARK: - Expansion

    func testExpandsZeroArgMacro() {
        let table = MathMacros.collectDefinitions(from: "$$\\newcommand{\\R}{\\mathbb{R}}$$")
        XCTAssertEqual(MathMacros.expand("x \\in \\R", with: table), "x \\in \\mathbb{R}")
    }

    func testExpandsArgMacro() {
        let table = MathMacros.collectDefinitions(from: "$$\\newcommand{\\abs}[1]{\\left|#1\\right|}$$")
        XCTAssertEqual(MathMacros.expand("\\abs{x}", with: table), "\\left|x\\right|")
    }

    func testExpandsNestedMacros() {
        let table = MathMacros.collectDefinitions(
            from: "$$\\newcommand{\\R}{\\mathbb{R}}\\newcommand{\\Rn}{\\R^n}$$")
        XCTAssertEqual(MathMacros.expand("\\Rn", with: table), "\\mathbb{R}^n")
    }

    func testStripsDefinitionsFromOutput() {
        let table = MathMacros.collectDefinitions(from: "$$\\newcommand{\\R}{\\mathbb{R}}$$")
        // A block that both defines and uses: the def contributes no output.
        XCTAssertEqual(
            MathMacros.expand("\\newcommand{\\R}{\\mathbb{R}} \\R^n", with: table).trimmingCharacters(in: .whitespaces),
            "\\mathbb{R}^n")
    }

    func testDefinitionOnlyDetected() {
        let table = MathMacros.collectDefinitions(from: "$$\\newcommand{\\R}{\\mathbb{R}}$$")
        XCTAssertTrue(MathMacros.isDefinitionOnly("\\newcommand{\\R}{\\mathbb{R}}", table: table))
        XCTAssertFalse(MathMacros.isDefinitionOnly("\\R^n", table: table))
    }

    func testRecursionBombTerminates() {
        // A self-referential macro must not hang — it expands to the budget
        // and stops (degrading, never looping).
        let table = MathMacros.collectDefinitions(from: "$$\\def\\loop{\\loop x}$$")
        let result = MathMacros.expand("\\loop", with: table, limit: 50)
        XCTAssertTrue(result.contains("x"))   // made progress, then bailed
    }

    func testMissingArgumentLeavesCommandLiteral() {
        let table = MathMacros.collectDefinitions(from: "$$\\newcommand{\\abs}[1]{|#1|}$$")
        // No brace argument follows — leave \abs alone (it'll degrade).
        XCTAssertEqual(MathMacros.expand("\\abs", with: table), "\\abs")
    }

    func testLargeMacroDocumentStaysCheap() {
        // A document with many definitions + uses must collect + expand well
        // within the parse budget (macro work is a pre-tokenize string pass).
        var source = ""
        for i in 0..<500 { source += "$$\\newcommand{\\m\(i)}{x_{\(i)}}$$\n\n" }
        var uses = "$$"
        for i in 0..<500 { uses += "\\m\(i) + " }
        uses += "0$$"
        source += uses
        let start = Date()
        let table = MathMacros.collectDefinitions(from: source)
        _ = MathMacros.expand(uses, with: table)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(table.count, 500)
        XCTAssertLessThan(elapsed, 0.25, "macro collection + expansion should be cheap")
    }

    // NOTE: the end-to-end "macro resolves across blocks in a document" test
    // lives in Quoin (QuoinCoreTests) — it exercises MarkdownConverter's
    // document-scoped collection, which is host integration, not the engine.
}
