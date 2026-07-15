import XCTest
@testable import VinculumLayout

final class MathParserTests: XCTestCase {

    func testSimpleExpression() {
        let node = MathParser.parse("x+1")
        guard case .row(let children) = node else { return XCTFail("expected row") }
        XCTAssertEqual(children, [
            .symbol("x", .ordinary, style: .italic),
            .symbol("+", .binary, style: .roman),
            .symbol("1", .ordinary, style: .roman),
        ])
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    func testFraction() {
        let node = MathParser.parse("\\frac{a}{b}")
        guard case .fraction(let n, let d) = node else { return XCTFail("expected fraction") }
        XCTAssertEqual(n, .symbol("a", .ordinary, style: .italic))
        XCTAssertEqual(d, .symbol("b", .ordinary, style: .italic))
    }

    func testMathbfIsBold() {
        // \mathbf must produce an upright bold symbol, distinct from roman.
        guard case .symbol(let glyph, _, let style) = MathParser.parse("\\mathbf{x}") else {
            return XCTFail("expected symbol")
        }
        XCTAssertEqual(glyph, "x")
        XCTAssertEqual(style, .bold)
    }

    func testTextPreservesInteriorSpaces() {
        // \text{if } must keep its trailing space (the tokenizer strips math
        // whitespace, so text bodies are captured verbatim).
        guard case .functionName(let s) = MathParser.parse("\\text{if x}") else {
            return XCTFail("expected functionName")
        }
        XCTAssertEqual(s, "if x")
    }

    func testPrimeBecomesRaisedSuperscript() {
        // f' → f^{′}, not a baseline apostrophe.
        guard case .scripts(let base, let sub, let sup) = MathParser.parse("f'") else {
            return XCTFail("expected scripts")
        }
        XCTAssertEqual(base, .symbol("f", .ordinary, style: .italic))
        XCTAssertNil(sub)
        XCTAssertEqual(sup, .symbol("\u{2032}", .ordinary, style: .roman))
    }

    func testDoublePrimeCoalesces() {
        guard case .scripts(_, _, .some(.symbol(let g, _, _))) = MathParser.parse("x''") else {
            return XCTFail("expected scripts with a prime superscript")
        }
        XCTAssertEqual(g, "\u{2032}\u{2032}")
    }

    func testPrimeThenExplicitExponent() {
        // f'^2 → superscript is the prime followed by the 2.
        guard case .scripts(_, _, .some(.row(let sup))) = MathParser.parse("f'^2") else {
            return XCTFail("expected scripts with a composite superscript")
        }
        XCTAssertEqual(sup.first, .symbol("\u{2032}", .ordinary, style: .roman))
    }

    func testDfracForcesDisplayStyle() {
        // \dfrac wraps its fraction in a display-forcing style node.
        guard case .mathStyle(let base, let style) = MathParser.parse("\\dfrac{a}{b}") else {
            return XCTFail("expected mathStyle")
        }
        XCTAssertEqual(style, .display)
        guard case .fraction = base else { return XCTFail("expected a fraction inside") }
    }

    func testTfracForcesTextStyle() {
        guard case .mathStyle(_, let style) = MathParser.parse("\\tfrac{a}{b}") else {
            return XCTFail("expected mathStyle")
        }
        XCTAssertEqual(style, .text)
    }

    func testPlainFracInheritsStyle() {
        // \frac is NOT wrapped — it inherits the ambient style.
        guard case .fraction = MathParser.parse("\\frac{a}{b}") else {
            return XCTFail("expected a bare fraction")
        }
    }

    func testBigDelimiterCarriesFactorAndClass() {
        // \bigl( is an opening delimiter enlarged 1.2×.
        guard case .bigDelimiter(let glyph, let factor, let cls) = MathParser.parse("\\bigl(") else {
            return XCTFail("expected bigDelimiter")
        }
        XCTAssertEqual(glyph, "(")
        XCTAssertEqual(factor, 1.2, accuracy: 0.001)
        XCTAssertEqual(cls, .opening)
    }

    func testBiggRightBracketIsClosingAndTaller() {
        guard case .bigDelimiter(let glyph, let factor, let cls) = MathParser.parse("\\biggr]") else {
            return XCTFail("expected bigDelimiter")
        }
        XCTAssertEqual(glyph, "]")
        XCTAssertEqual(factor, 2.4, accuracy: 0.001)
        XCTAssertEqual(cls, .closing)
    }

    func testPmodProducesParenthesizedMod() {
        // \pmod{n} → a leading space, "(mod " n ")".
        guard case .row(let parts) = MathParser.parse("\\pmod{n}") else {
            return XCTFail("expected a row")
        }
        XCTAssertTrue(parts.contains(.symbol("mod", .ordinary, style: .roman)))
        XCTAssertTrue(parts.contains(.symbol("(", .opening, style: .roman)))
    }

    func testBmodIsABinaryOperator() {
        guard case .symbol("mod", .binary, _) = MathParser.parse("\\bmod") else {
            return XCTFail("expected a binary mod symbol")
        }
    }

    func testArrayColumnSpecParsed() {
        guard case .matrix(_, _, _, .array(let spec)) =
                MathParser.parse(#"\begin{array}{l|cr} a & b & c \end{array}"#) else {
            return XCTFail("expected an array-style matrix")
        }
        XCTAssertEqual(spec.alignments, [.left, .center, .right])
        XCTAssertTrue(spec.columnRules.contains(1), "the | sits after column 0")
        XCTAssertFalse(spec.columnRules.contains(0))
    }

    func testArrayHlineRecordedAtRowBoundary() {
        guard case .matrix(_, _, _, .array(let spec)) =
                MathParser.parse(#"\begin{array}{cc} a & b \\ \hline c & d \end{array}"#) else {
            return XCTFail("expected an array")
        }
        XCTAssertEqual(spec.rowRules.count, 1)
        XCTAssertEqual(spec.rowRules.first?.boundary, 1, "\\hline sits below row 0")
    }

    func testClineSpansColumnRange() {
        guard case .matrix(_, _, _, .array(let spec)) =
                MathParser.parse(#"\begin{array}{ccc} a & b & c \\ \cline{2-3} d & e & f \end{array}"#) else {
            return XCTFail("expected an array")
        }
        let rule = spec.rowRules.first
        XCTAssertEqual(rule?.fromColumn, 1)   // \cline{2-3} → 0-based 1…2
        XCTAssertEqual(rule?.toColumn, 2)
    }

    func testTextWithEmbeddedMathParsesMath() {
        // \text{$n$ terms} → italic math n, then upright " terms".
        guard case .row(let parts) = MathParser.parse(#"\text{$n$ terms}"#) else {
            return XCTFail("expected a row of math + text")
        }
        XCTAssertEqual(parts.first, .symbol("n", .ordinary, style: .italic))
        XCTAssertEqual(parts.last, .functionName(" terms"))
    }

    func testMathbinForcesBinaryClass() {
        guard case .classified(_, let cls) = MathParser.parse(#"\mathbin{\star}"#) else {
            return XCTFail("expected .classified")
        }
        XCTAssertEqual(cls, .binary)
    }

    func testStatefulColorAppliesToRestOfGroup() {
        // {\color{red} a + b} + c : the color wraps a+b (rest of the group).
        guard case .row(let outer) = MathParser.parse(#"{\color{red} a + b} + c"#) else {
            return XCTFail("expected a row")
        }
        guard case .styled(_, "red") = outer.first else {
            return XCTFail("first element is the red-styled a+b")
        }
    }

    func testAlignatConsumesColumnCount() {
        // \begin{alignat}{2} must consume the {2}; it used to leak as cell 1.
        guard case .matrix(let rows, _, _, _) =
                MathParser.parse(#"\begin{alignat}{2} x &= 1 \end{alignat}"#) else {
            return XCTFail("expected a matrix")
        }
        XCTAssertEqual(rows.first?.first, .symbol("x", .ordinary, style: .italic),
                       "first cell is x, not the count 2")
    }

    func testStarredMatrixTakesAlignmentBracket() {
        // pmatrix*[r] → array-style right alignment, and the [r] is consumed.
        guard case .matrix(let rows, "(", ")", .array(let spec)) =
                MathParser.parse(#"\begin{pmatrix*}[r] a & b \\ c & d \end{pmatrix*}"#) else {
            return XCTFail("expected an array-styled pmatrix")
        }
        XCTAssertEqual(spec.alignments, [.right])
        XCTAssertEqual(rows.first?.first, .symbol("a", .ordinary, style: .italic))
    }

    func testMiddleProducesFenced() {
        guard case .fenced(let fences, let segments) = MathParser.parse(#"\left( a \middle| b \right)"#) else {
            return XCTFail("expected a fenced node")
        }
        XCTAssertEqual(fences, ["(", "|", ")"])
        XCTAssertEqual(segments.count, 2)
    }

    func testLeftRightWithoutMiddleStaysDelimited() {
        // No \middle → the original .delimited path, unchanged.
        guard case .delimited = MathParser.parse(#"\left( a \right)"#) else {
            return XCTFail("expected .delimited")
        }
    }

    func testOperatornameStarTakesLimits() {
        guard case .limitsOperator = MathParser.parse(#"\operatorname*{Fix}"#) else {
            return XCTFail("expected .limitsOperator")
        }
        // Plain \operatorname is NOT wrapped.
        guard case .functionName = MathParser.parse(#"\operatorname{Fix}"#) else {
            return XCTFail("expected a bare functionName")
        }
    }

    func testTagAppendsParenthesizedNumber() {
        guard case .row(let parts) = MathParser.parse(#"x = 1 \tag{3.1}"#) else {
            return XCTFail("expected a row")
        }
        XCTAssertEqual(parts.last, .symbol(")", .closing, style: .roman))
        XCTAssertTrue(parts.contains(.symbol("(", .opening, style: .roman)))
    }

    func testHspaceParsesEmLength() {
        guard case .space(let w) = MathParser.parse("\\hspace{2em}") else { return XCTFail("expected space") }
        XCTAssertEqual(w, 2.0, accuracy: 0.001)
    }

    func testMspaceParsesMuBraced() throws {
        let space = try XCTUnwrap(spaceWidth(in: "a\\mspace{18mu}b"))   // 18mu = 1em
        XCTAssertEqual(space, 1.0, accuracy: 0.001)
    }

    func testMkernParsesMuUnbraced() throws {
        let space = try XCTUnwrap(spaceWidth(in: "a\\mkern18mu b"))
        XCTAssertEqual(space, 1.0, accuracy: 0.001)
    }

    private func spaceWidth(in latex: String) -> Double? {
        guard case .row(let parts) = MathParser.parse(latex) else { return nil }
        return parts.compactMap { if case .space(let w) = $0 { return w } else { return nil } }.first
    }

    func testMathbbStaysRoman() {
        guard case .symbol(let glyph, _, let style) = MathParser.parse("\\mathbb{R}") else {
            return XCTFail("expected symbol")
        }
        XCTAssertEqual(glyph, "ℝ")
        XCTAssertEqual(style, .roman)
    }

    func testScripts() {
        let node = MathParser.parse("x_i^2")
        guard case .scripts(let base, let sub, let sup) = node else { return XCTFail("expected scripts") }
        XCTAssertEqual(base, .symbol("x", .ordinary, style: .italic))
        XCTAssertEqual(sub, .symbol("i", .ordinary, style: .italic))
        XCTAssertEqual(sup, .symbol("2", .ordinary, style: .roman))
    }

    func testGroupedSuperscript() {
        let node = MathParser.parse("e^{i\\pi}")
        guard case .scripts(_, _, let sup) = node,
              case .row(let children) = sup else { return XCTFail("expected grouped sup") }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[1], .symbol("π", .ordinary, style: .roman))
    }

    func testSqrtWithDegree() {
        let node = MathParser.parse("\\sqrt[3]{x}")
        guard case .radical(let degree, let radicand) = node else { return XCTFail("expected radical") }
        XCTAssertEqual(degree, .symbol("3", .ordinary, style: .roman))
        XCTAssertEqual(radicand, .symbol("x", .ordinary, style: .italic))
    }

    func testGreekAndOperators() {
        let node = MathParser.parse("\\alpha \\leq \\sum")
        guard case .row(let children) = node else { return XCTFail("expected row") }
        XCTAssertEqual(children, [
            .symbol("α", .ordinary, style: .roman),
            .symbol("≤", .relation, style: .roman),
            .symbol("∑", .largeOperator, style: .roman),
        ])
    }

    func testLeftRightDelimiters() {
        let node = MathParser.parse("\\left( \\frac{x}{2} \\right)")
        guard case .delimited(let l, let body, let r) = node else { return XCTFail("expected delimited") }
        XCTAssertEqual(l, "(")
        XCTAssertEqual(r, ")")
        if case .fraction = body {} else { XCTFail("expected fraction body") }
    }

    func testFunctionName() {
        let node = MathParser.parse("\\sin x")
        guard case .row(let children) = node else { return XCTFail("expected row") }
        XCTAssertEqual(children.first, .functionName("sin"))
    }

    func testMathbb() {
        let node = MathParser.parse("\\mathbb{R}")
        XCTAssertEqual(node, .symbol("ℝ", .ordinary, style: .roman))
    }

    func testUnknownCommandIsUnsupportedNotFatal() {
        let node = MathParser.parse("x + \\undefinedmacro{y}")
        XCTAssertFalse(MathParser.isFullySupported(node))
    }

    func testMinusBecomesProperGlyph() {
        let node = MathParser.parse("a-b")
        guard case .row(let children) = node else { return XCTFail("expected row") }
        XCTAssertEqual(children[1], .symbol("−", .binary, style: .roman))
    }

    func testEulerIdentityFullySupported() {
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse("e^{i\\pi} + 1 = 0")))
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse("\\int_0^1 x^2 \\, dx = \\frac{1}{3}")))
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse("\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}")))
    }

    func testPmatrixParsesRowsColumnsAndFences() {
        let node = MathParser.parse("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}")
        guard case .matrix(let rows, let left, let right, let style) = node else {
            return XCTFail("expected matrix, got \(node)")
        }
        XCTAssertEqual(left, "(")
        XCTAssertEqual(right, ")")
        XCTAssertEqual(style, .centered)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[1].count, 2)
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    func testCasesEnvironmentIsLeftAlignedBraced() {
        let node = MathParser.parse("f(x) = \\begin{cases} 0, & x < 0 \\\\ 1, & x \\geq 0 \\end{cases}")
        guard case .row(let children) = node,
              let matrix = children.first(where: { if case .matrix = $0 { return true }; return false }),
              case .matrix(let rows, let left, _, let style) = matrix else {
            return XCTFail("expected a cases matrix in the row")
        }
        XCTAssertEqual(left, "{")
        XCTAssertEqual(style, .cases)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    func testAlignedEnvironmentParses() {
        let node = MathParser.parse("\\begin{aligned} x &= a + b \\\\ y &= c \\end{aligned}")
        guard case .matrix(let rows, _, _, let style) = node else {
            return XCTFail("expected aligned matrix")
        }
        XCTAssertEqual(style, .aligned)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    func testAlignedatSkipsColumnCountArgument() {
        // The `{3}` after alignedat must not leak into the first cell.
        let node = MathParser.parse("\\begin{alignedat}{3} a &= b \\end{alignedat}")
        guard case .matrix(let rows, _, _, _) = node else { return XCTFail("expected matrix") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    // MARK: - Diagnostics (Phase 0)

    func testUnsupportedCommandsNamesTheCulprit() {
        let node = MathParser.parse("\\sideset{x}")   // \sideset is genuinely unsupported
        XCTAssertFalse(MathParser.isFullySupported(node))
        XCTAssertEqual(MathParser.unsupportedCommands(in: node), ["\\sideset"])
    }

    func testUnsupportedCommandsDedupesAndPreservesOrder() {
        let node = MathParser.parse("\\foo x + \\zzz y + \\foo z")
        XCTAssertEqual(MathParser.unsupportedCommands(in: node), ["\\foo", "\\zzz"])
    }

    func testUnsupportedCommandsCaps() {
        let node = MathParser.parse("\\a \\b \\c \\d \\e \\f")
        XCTAssertEqual(MathParser.unsupportedCommands(in: node, limit: 4).count, 4)
    }

    func testUnsupportedCommandsFindsCulpritInsideStructure() {
        // A single unsupported command buried in a fraction still surfaces.
        let node = MathParser.parse("\\frac{1}{\\notacommand{a}}")
        XCTAssertEqual(MathParser.unsupportedCommands(in: node), ["\\notacommand"])
    }

    func testFullySupportedExpressionHasNoUnsupportedCommands() {
        let node = MathParser.parse("\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}")
        XCTAssertTrue(MathParser.unsupportedCommands(in: node).isEmpty)
    }

    // MARK: - Math alphabets (Phase 1)

    func testMathbbFullAlphabet() {
        // Blackboard maps every letter, with the Letterlike holes.
        XCTAssertEqual(glyph("\\mathbb{R}"), "ℝ")  // hole
        XCTAssertEqual(glyph("\\mathbb{A}"), "𝔸")  // contiguous block
        XCTAssertEqual(glyph("\\mathbb{k}"), "𝕜")  // lowercase
    }

    func testCalligraphicAndFraktur() {
        XCTAssertEqual(glyph("\\mathcal{L}"), "ℒ")   // script hole
        XCTAssertEqual(glyph("\\mathcal{A}"), "𝒜")   // script block
        XCTAssertEqual(glyph("\\mathfrak{g}"), "𝔤")  // fraktur
        XCTAssertEqual(glyph("\\mathscr{B}"), "ℬ")   // scr == cal
    }

    func testSansAndMonospace() {
        XCTAssertEqual(glyph("\\mathsf{X}"), "𝖷")
        XCTAssertEqual(glyph("\\mathtt{x}"), "𝚡")
        XCTAssertEqual(glyph("\\mathsf{5}"), "𝟧")   // sans digits
    }

    func testMathbfStillBoldStyle() {
        // Unchanged: \mathbf renders with a bold system font, not a codepoint.
        guard case .symbol("x", _, let style) = MathParser.parse("\\mathbf{x}") else {
            return XCTFail("expected symbol")
        }
        XCTAssertEqual(style, .bold)
    }

    // MARK: - Direct-typed Unicode (Phase 1)

    func testDirectUnicodeOperatorGetsLargeOperatorClass() {
        guard case .symbol("∫", .largeOperator, _) = MathParser.parse("∫") else {
            return XCTFail("a directly-typed ∫ must class as a large operator")
        }
    }

    func testDirectUnicodeRelationGetsRelationClass() {
        guard case .symbol("≤", .relation, _) = MathParser.parse("≤") else {
            return XCTFail("≤ must class as a relation")
        }
    }

    func testDirectGreekMatchesCommandForm() {
        guard case .symbol("α", let cls, .italic) = MathParser.parse("α") else {
            return XCTFail("α should be italic ordinary")
        }
        XCTAssertEqual(cls, .ordinary)
    }

    // MARK: - Operators & \big (Phase 1)

    func testBigDelimitersAreTransparent() {
        // \big( no longer degrades — it passes the ( through as an opening.
        let node = MathParser.parse("\\big( x \\big)")
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    func testNegativeThinSpace() {
        guard case .space(let width) = MathParser.parse("\\!") else {
            return XCTFail("expected space")
        }
        XCTAssertLessThan(width, 0)
    }

    func testExtraOperatorNames() {
        for op in ["\\Pr", "\\argmax", "\\limsup"] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(op)), "\(op) should render")
        }
    }

    // MARK: - Accents & genfrac (Phase 2)

    func testAccentParses() {
        guard case .accent(_, let accent) = MathParser.parse("\\hat{x}") else {
            return XCTFail("expected accent")
        }
        XCTAssertEqual(accent, .hat)
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse("\\vec{v} + \\bar{y} + \\dot{z}")))
    }

    func testOverlineUnderlineAreAccents() {
        guard case .accent(_, .overline) = MathParser.parse("\\overline{AB}") else {
            return XCTFail("expected overline accent")
        }
        guard case .accent(_, .underline) = MathParser.parse("\\underline{x}") else {
            return XCTFail("expected underline accent")
        }
    }

    func testWideAccentsAreStretchy() {
        guard case .accent(_, let accent) = MathParser.parse("\\widehat{abc}") else {
            return XCTFail("expected accent")
        }
        XCTAssertTrue(accent.isStretchy)
    }

    func testBinomialIsGenfracWithParensNoRule() {
        guard case .genfrac(_, _, let hasRule, let left, let right) = MathParser.parse("\\binom{n}{k}") else {
            return XCTFail("expected genfrac")
        }
        XCTAssertFalse(hasRule)
        XCTAssertEqual(left, "(")
        XCTAssertEqual(right, ")")
    }

    func testCfracIsItsOwnNode() {
        guard case .cfrac(_, _, .center) = MathParser.parse("\\cfrac{1}{x}") else {
            return XCTFail("expected .cfrac with default center alignment")
        }
        guard case .cfrac(_, _, .left) = MathParser.parse("\\cfrac[l]{1}{x}") else {
            return XCTFail("expected left-aligned cfrac")
        }
    }

    func testAccentAndBinomFullySupported() {
        XCTAssertTrue(MathParser.isFullySupported(
            MathParser.parse("\\widehat{abc} + \\dbinom{n}{k} + \\overline{z}")))
    }

    // MARK: - Over/under & substack (Phase 3)

    func testOversetUnderset() {
        guard case .overUnder(_, let over, nil, .plain) = MathParser.parse("\\overset{!}{=}") else {
            return XCTFail("expected overset")
        }
        XCTAssertNotNil(over)
        guard case .overUnder(_, nil, let under, .plain) = MathParser.parse("\\underset{x}{y}") else {
            return XCTFail("expected underset")
        }
        XCTAssertNotNil(under)
    }

    func testOverbraceCapturesSuperscriptLabel() {
        // \overbrace{…}^{label} — the ^label becomes the brace annotation,
        // not a superscript on the whole brace.
        guard case .overUnder(_, let over, nil, .overbrace) = MathParser.parse("\\overbrace{a+b}^{s}") else {
            return XCTFail("expected overbrace")
        }
        XCTAssertNotNil(over)
    }

    func testUnderbraceCapturesSubscriptLabel() {
        guard case .overUnder(_, nil, let under, .underbrace) = MathParser.parse("\\underbrace{a+b}_{s}") else {
            return XCTFail("expected underbrace")
        }
        XCTAssertNotNil(under)
    }

    func testStretchyArrows() {
        guard case .overUnder(_, let over, _, .rightarrow) = MathParser.parse("\\xrightarrow{f}") else {
            return XCTFail("expected rightarrow")
        }
        XCTAssertNotNil(over)
        // \xrightarrow[below]{above} — both annotations.
        guard case .overUnder(_, let a, let b, .rightarrow) = MathParser.parse("\\xrightarrow[g]{f}") else {
            return XCTFail("expected rightarrow with both")
        }
        XCTAssertNotNil(a); XCTAssertNotNil(b)
    }

    func testExtensibleArrowVariantsMapToDistinctKinds() {
        let cases: [(String, MathOverUnder)] = [
            ("\\xleftarrow{f}", .leftarrow),
            ("\\xLongrightarrow{f}", .longRightArrow),
            ("\\xLongleftarrow{f}", .longLeftArrow),
            ("\\xleftrightarrow{f}", .leftRightArrow),
            ("\\xhookrightarrow{f}", .hookRightArrow),
            ("\\xhookleftarrow{f}", .hookLeftArrow),
            ("\\xmapsto{f}", .mapsToArrow),
            ("\\xrightharpoonup{f}", .rightHarpoonUp),
            ("\\xrightharpoondown{f}", .rightHarpoonDown),
            ("\\xleftharpoonup{f}", .leftHarpoonUp),
            ("\\xleftharpoondown{f}", .leftHarpoonDown),
            ("\\xrightleftharpoons{f}", .rightLeftHarpoons),
        ]
        for (latex, expected) in cases {
            guard case .overUnder(_, _, _, let kind) = MathParser.parse(latex) else {
                XCTFail("\(latex) did not parse to an overUnder arrow"); continue
            }
            XCTAssertEqual(kind, expected, "\(latex) mapped to the wrong arrow kind")
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(latex)), "\(latex) should render")
        }
    }

    func testExtensibleArrowsAreRelations() {
        // Each annotated arrow spaces as a relation (thick space around it).
        let engine = standardMockEngine()
        for latex in ["\\xhookrightarrow{f}", "\\xmapsto{f}", "\\xrightleftharpoons{f}"] {
            XCTAssertEqual(engine.atomClass(of: MathParser.parse(latex)), .relation, latex)
        }
    }

    func testHarpoonDrawsFewerStrokesThanFullArrow() {
        // A single-barb harpoon head has strictly fewer path vertices than a
        // full (two-barb) arrowhead — a cheap proxy that the head differs.
        func strokeVertexCount(_ latex: String) -> Int {
            let scene = standardMockEngine().layout(MathParser.parse(latex))
            var n = 0
            for e in scene.elements { if case let .stroke(path, _, _, _, _) = e { n += path.count } }
            return n
        }
        XCTAssertLessThan(strokeVertexCount("\\xrightharpoonup{f}"),
                          strokeVertexCount("\\xrightarrow{f}"),
                          "a harpoon (one barb) should draw fewer vertices than a full head")
    }

    func testSubstackIsATightMatrix() {
        guard case .matrix(let rows, _, _, .substack) = MathParser.parse("\\substack{a \\\\ b \\\\ c}") else {
            return XCTFail("expected substack matrix")
        }
        XCTAssertEqual(rows.count, 3)
    }

    func testPhase3ConstructsFullySupported() {
        XCTAssertTrue(MathParser.isFullySupported(
            MathParser.parse("\\sum_{\\substack{i<n \\\\ i\\text{ odd}}} \\overbrace{i}^{k} \\xrightarrow{f}")))
    }

    // MARK: - Decorations & color (Phase 5)

    func testBoxedAndPhantom() {
        guard case .decorated(_, .boxed) = MathParser.parse("\\boxed{x}") else {
            return XCTFail("expected boxed")
        }
        guard case .decorated(_, .phantom) = MathParser.parse("\\phantom{x}") else {
            return XCTFail("expected phantom")
        }
        guard case .decorated(_, .vphantom) = MathParser.parse("\\vphantom{x}") else {
            return XCTFail("expected vphantom")
        }
    }

    func testColorTakesNameThenBody() {
        guard case .styled(_, let color) = MathParser.parse("\\color{red}{x + y}") else {
            return XCTFail("expected styled")
        }
        XCTAssertEqual(color, "red")
        guard case .styled(_, let hex) = MathParser.parse("\\textcolor{#00aa88}{z}") else {
            return XCTFail("expected styled")
        }
        XCTAssertEqual(hex, "#00aa88")
    }

    func testDecorationsFullySupported() {
        XCTAssertTrue(MathParser.isFullySupported(
            MathParser.parse("\\boxed{\\color{red}{a} + \\phantom{b}}")))
    }

    // MARK: - Arrays with rules (Phase 4)

    func testHlineNoLongerDegradesArray() {
        // \hline used to become an .unsupported leaf, flipping the whole
        // array to a source card. Now it's consumed; the grid survives.
        let node = MathParser.parse("\\begin{array}{cc} a & b \\\\ \\hline c & d \\end{array}")
        XCTAssertTrue(MathParser.isFullySupported(node))
        guard case .matrix(let rows, _, _, _) = node else { return XCTFail("expected matrix") }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 2)
    }

    func testClineArgumentConsumed() {
        let node = MathParser.parse("\\begin{array}{cc} a & b \\\\ \\cline{1-2} c & d \\end{array}")
        XCTAssertTrue(MathParser.isFullySupported(node))
    }

    // MARK: - Legacy/infix constructs (iosMath corpus)

    func testInfixOverIsAFraction() {
        guard case .fraction(let num, let den) = MathParser.parse(#"{a \over b}"#) else {
            return XCTFail("`\\over` should build a fraction")
        }
        if case .symbol("a", _, _) = num, case .symbol("b", _, _) = den { } else {
            XCTFail("numerator/denominator split wrong: \(num) / \(den)")
        }
    }

    func testInfixChooseBraceBrackAtop() {
        // Each maps to a genfrac with the right fences and no rule.
        for (latex, l, r) in [(#"{n \choose k}"#, "(", ")"),
                              (#"{n \brace k}"#, "{", "}"),
                              (#"{n \brack k}"#, "[", "]"),
                              (#"{n \atop k}"#, "", "")] {
            guard case .genfrac(_, _, let hasRule, let left, let right) = MathParser.parse(latex) else {
                return XCTFail("\(latex) should build a genfrac")
            }
            XCTAssertFalse(hasRule, "\(latex) has no rule")
            XCTAssertEqual(left, l); XCTAssertEqual(right, r)
        }
    }

    func testInfixNumeratorIsEverythingBefore() {
        // `a + b \over c` → the whole `a + b` is the numerator, not just `b`.
        guard case .fraction(let num, _) = MathParser.parse(#"a + b \over c"#) else {
            return XCTFail("expected a fraction")
        }
        guard case .row(let kids) = num else { return XCTFail("numerator should be the row a + b") }
        XCTAssertEqual(kids.count, 3, "numerator is the full row before \\over")
    }

    func testOldStyleFontSwitchesAreSupported() {
        for latex in [#"\bf x"#, #"\rm x"#, #"\it x"#, #"\cal C"#, #"\frak Q"#,
                      #"\bb R"#, #"\scr S"#, #"\sf A"#, #"\tt m"#, #"\vec{\bf E}"#] {
            XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(latex)),
                          "\(latex) should render natively")
        }
    }

    func testFontSwitchScopesToGroup() {
        // `{\cal C} D`: the switch styles only C; D stays a normal symbol.
        guard case .row(let kids) = MathParser.parse(#"{\cal C} D"#) else {
            return XCTFail("expected a row")
        }
        guard case .symbol("D", _, _) = kids.last else {
            XCTFail("the trailing D must not inherit \\cal styling: \(kids)")
            return
        }
    }

    func testFontSwitchDoesNotSwallowRightDelimiter() {
        // Regression: a switch's rest-of-group scan must stop at \right,
        // or `\left| \cal C \right|` loses its closing fence and degrades.
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(#"\left| \cal C \right|"#)))
    }

    func testIntLimitsForcesStackedForm() {
        // `\int\limits_a^b` wraps the operator so its scripts stack, like \sum.
        let node = MathParser.parse(#"\int\limits_{-\infty}^{\infty}"#)
        XCTAssertTrue(MathParser.isFullySupported(node))
        guard case .scripts(let base, _, _) = node else { return XCTFail("expected scripts") }
        guard case .limitsOperator = base else {
            return XCTFail("\\limits should wrap the operator in .limitsOperator, got \(base)")
        }
    }

    func testBareRowBreakDegradesToNoOp() {
        // A `\\` outside any environment can't break a line inline; it must
        // NOT become an unsupported card (it did before).
        XCTAssertTrue(MathParser.isFullySupported(MathParser.parse(#"a + b \\ + c"#)))
    }

    /// Convenience: the single mapped glyph of a one-atom expression.
    private func glyph(_ latex: String) -> String? {
        if case .symbol(let g, _, _) = MathParser.parse(latex) { return g }
        return nil
    }
}
