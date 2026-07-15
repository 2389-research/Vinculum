import Foundation

public enum MathParser {

    /// Recursion bound. Enforced twice: a linear pre-scan rejects extreme
    /// brace/environment nesting up front, and a RUNTIME depth counter in
    /// `parseAtom` bounds the recursion the pre-scan cannot see — commands
    /// that take an atom argument without braces (`\sqrt\sqrt\sqrt…`) recurse
    /// once per command with zero braces. Past the bound, input degrades to
    /// `.unsupported` (PRD rule: unknown input degrades, never crashes).
    static let maxNestingDepth = 64

    // Runtime recursion depth, thread-local so concurrent parses don't
    // interfere (the parser is a static API used from multiple threads).
    private static let depthKey = "VinculumMathParserDepth"
    private static var currentDepth: Int {
        get { Thread.current.threadDictionary[depthKey] as? Int ?? 0 }
        set { Thread.current.threadDictionary[depthKey] = newValue }
    }

    /// Parses a LaTeX math string. Unknown commands become `.unsupported`
    /// leaves; the parse itself never fails.
    public static func parse(_ latex: String) -> MathNode {
        // Linear pre-scan bounds recursion before it starts: parse recursion
        // depth ≤ max brace nesting + \begin count.
        var depth = 0, maxDepth = 0
        for ch in latex {
            if ch == "{" { depth += 1; maxDepth = max(maxDepth, depth) }
            if ch == "}" { depth = max(0, depth - 1) }
        }
        let begins = latex.components(separatedBy: "\\begin").count - 1
        guard maxDepth <= maxNestingDepth, begins <= maxNestingDepth else {
            return .unsupported(latex)
        }

        var tokens = Tokenizer(latex).tokenize()
        let tag = extractTag(&tokens)                 // pulls out \tag{…}/\tag*{…}
        var slice = tokens[...]
        let nodes = parseRow(&slice, until: nil)
        let body: MathNode = nodes.count == 1 ? nodes[0] : .row(nodes)
        guard let tag else { return body }
        // Append the tag inline: `body \qquad (tag)` (or no parens for \tag*).
        // True flush-right placement is a host concern (needs the column width).
        if tag.starred {
            return .row([body, .space(2.0), tag.node])
        }
        return .row([body, .space(2.0),
                     .symbol("(", .opening, style: .roman), tag.node,
                     .symbol(")", .closing, style: .roman)])
    }

    /// Removes a top-level `\tag{…}` / `\tag*{…}` from the token stream and
    /// returns its parsed body (nil if none). Balanced-brace slice so
    /// `\tag{\text{A}}` works.
    private static func extractTag(_ tokens: inout [Token]) -> (node: MathNode, starred: Bool)? {
        guard let idx = tokens.firstIndex(of: .command("tag")) else { return nil }
        var i = idx + 1
        var starred = false
        if i < tokens.count, tokens[i] == .character("*") { starred = true; i += 1 }
        guard i < tokens.count, tokens[i] == .groupOpen else {
            tokens.remove(at: idx); return nil          // malformed \tag — just drop it
        }
        var depth = 0, j = i
        var bodyTokens: [Token] = []
        while j < tokens.count {
            let t = tokens[j]
            if t == .groupOpen { depth += 1; if depth == 1 { j += 1; continue } }
            else if t == .groupClose { depth -= 1; if depth == 0 { j += 1; break } }
            bodyTokens.append(t); j += 1
        }
        tokens.removeSubrange(idx..<j)
        var slice = bodyTokens[...]
        let tagNodes = parseRow(&slice, until: nil)
        return (tagNodes.count == 1 ? tagNodes[0] : .row(tagNodes), starred)
    }

    // MARK: - Parser

    private static func parseRow(_ tokens: inout ArraySlice<Token>, until terminator: Token?) -> [MathNode] {
        var nodes: [MathNode] = []
        while let token = tokens.first {
            if let terminator, token == terminator {
                tokens.removeFirst()
                break
            }
            // Infix generalized fractions (`{a \over b}`, `{n \brace k}`, …):
            // TeX's one infix construct. Everything parsed in this group so far
            // is the numerator; everything remaining (to the terminator) is the
            // denominator. Only one may appear per group, and it takes over the
            // whole group — so build the node and return it as the row.
            if case .command(let n) = token, let infix = InfixFraction(command: n) {
                tokens.removeFirst()
                let numerator = nodes.count == 1 ? nodes[0] : .row(nodes)
                let denomNodes = parseRow(&tokens, until: terminator)  // consumes the terminator
                let denominator = denomNodes.count == 1 ? denomNodes[0] : .row(denomNodes)
                return [infix.node(numerator: numerator, denominator: denominator)]
            }
            guard let node = parseAtom(&tokens) else { continue }
            let modified = applyLimitsModifier(node, &tokens)
            nodes.append(attachScriptsAndPrimes(modified, &tokens))
        }
        return nodes
    }

    /// TeX's infix generalized-fraction operators. Each restructures its
    /// enclosing group into a numerator-over-denominator, differing only in
    /// the fences and whether a rule is drawn — so all map onto the existing
    /// `.fraction` / `.genfrac` nodes (no new node kind).
    private enum InfixFraction {
        case over, atop, choose, brace, brack

        init?(command: String) {
            switch command {
            case "over": self = .over
            case "atop": self = .atop
            case "choose": self = .choose
            case "brace": self = .brace
            case "brack": self = .brack
            default: return nil
            }
        }

        func node(numerator: MathNode, denominator: MathNode) -> MathNode {
            switch self {
            case .over:   return .fraction(numerator: numerator, denominator: denominator)
            case .atop:   return .genfrac(top: numerator, bottom: denominator, hasRule: false, left: "", right: "")
            case .choose: return .genfrac(top: numerator, bottom: denominator, hasRule: false, left: "(", right: ")")
            case .brace:  return .genfrac(top: numerator, bottom: denominator, hasRule: false, left: "{", right: "}")
            case .brack:  return .genfrac(top: numerator, bottom: denominator, hasRule: false, left: "[", right: "]")
            }
        }
    }

    /// `\limits` / `\nolimits` / `\displaylimits` after an operator. `\limits`
    /// forces the stacked (over/under) form via `.limitsOperator`; the other
    /// two are consumed and leave the operator's default placement (so an
    /// unknown-limits leaf never blocks a render). Runs before scripts attach,
    /// since TeX writes `\int\limits_a^b`.
    private static func applyLimitsModifier(_ node: MathNode, _ tokens: inout ArraySlice<Token>) -> MathNode {
        guard case .command(let n)? = tokens.first else { return node }
        switch n {
        case "limits":
            tokens.removeFirst()
            return .limitsOperator(base: node)
        case "nolimits", "displaylimits":
            tokens.removeFirst()
            return node
        default:
            return node
        }
    }

    /// One atom: a group, a command, or a single character.
    /// Runtime recursion cap for `parseAtom`. Sized for the SMALLEST stack
    /// the parser really runs on: XCTest parallel workers and many host
    /// threads get 512 KB, and one parse level costs several unoptimized
    /// frames — 48 levels stays comfortably inside that while far exceeding
    /// any legitimate formula's atom-argument nesting (~30 worst case).
    static let maxRuntimeDepth = 48

    private static func parseAtom(_ tokens: inout ArraySlice<Token>) -> MathNode? {
        // The runtime half of the recursion bound (see maxNestingDepth):
        // groups AND brace-free command arguments both pass through here.
        let depth = currentDepth
        guard depth < maxRuntimeDepth else {
            // Consume one token so every caller still makes progress.
            guard let token = tokens.first else { return nil }
            tokens.removeFirst()
            if case .command(let name) = token { return .unsupported("\\" + name) }
            return .unsupported("…")
        }
        currentDepth = depth + 1
        defer { currentDepth = depth }
        return parseAtomBody(&tokens)
    }

    private static func parseAtomBody(_ tokens: inout ArraySlice<Token>) -> MathNode? {
        guard let token = tokens.first else { return nil }
        tokens.removeFirst()

        switch token {
        case .groupOpen:
            let nodes = parseRow(&tokens, until: .groupClose)
            return nodes.count == 1 ? nodes[0] : .row(nodes)

        case .groupClose:
            return nil // stray brace: ignore

        case .superscriptMark, .subscriptMark:
            return nil // handled by caller; stray marks ignored

        case .character(let ch):
            return characterNode(ch)

        case .command(let name):
            return commandNode(name, &tokens)

        case .rawText(let s):
            // Only appears right after a text command (consumed there); a stray
            // one degrades to upright text rather than vanishing.
            return .functionName(s)
        }
    }

    /// Attaches trailing primes (`f'` → `f^{′}`) and any `^`/`_` scripts to a
    /// just-parsed atom. Shared by `parseRow` and `parseAtomWithScripts` so the
    /// two paths can't drift.
    private static func attachScriptsAndPrimes(_ node: MathNode, _ tokens: inout ArraySlice<Token>) -> MathNode {
        // Primes bind before scripts: a run of ' becomes a superscript of ′.
        var primes = 0
        while tokens.first == .character("'") { tokens.removeFirst(); primes += 1 }

        var sub: MathNode?
        var sup: MathNode?
        while let mark = tokens.first, mark == .superscriptMark || mark == .subscriptMark {
            tokens.removeFirst()
            let script = parseAtom(&tokens) ?? .row([])
            if mark == .superscriptMark { sup = script } else { sub = script }
        }
        if primes > 0 {
            let primeGlyphs = MathNode.symbol(String(repeating: "\u{2032}", count: primes), .ordinary, style: .roman)
            // f'^2 → the primes lead, then the explicit exponent.
            sup = sup.map { .row([primeGlyphs, $0]) } ?? primeGlyphs
        }
        guard sub != nil || sup != nil else { return node }
        return .scripts(base: node, subscript: sub, superscript: sup)
    }

    private static func characterNode(_ ch: Character) -> MathNode {
        if ch.isNumber || ch == "." {
            return .symbol(String(ch), .ordinary, style: .roman)
        }
        // ASCII letters are italic variables; other letters (Greek α typed
        // directly, etc.) keep the class the symbol table assigns their
        // glyph so `α` matches `\alpha` and stays italic ordinary.
        if ch.isLetter {
            if ch.isASCII {
                return .symbol(String(ch), .ordinary, style: .italic)
            }
            let cls = glyphAtomClass[String(ch)] ?? .ordinary
            return .symbol(String(ch), cls, style: .italic)
        }
        switch ch {
        case "+", "−": return .symbol(String(ch), .binary, style: .roman)
        case "-": return .symbol("−", .binary, style: .roman) // proper minus
        case "*": return .symbol("∗", .binary, style: .roman)
        case "/": return .symbol("/", .ordinary, style: .roman)
        case "=": return .symbol("=", .relation, style: .roman)
        case "<": return .symbol("<", .relation, style: .roman)
        case ">": return .symbol(">", .relation, style: .roman)
        case "(", "[": return .symbol(String(ch), .opening, style: .roman)
        case ")", "]": return .symbol(String(ch), .closing, style: .roman)
        case ",", ";": return .symbol(String(ch), .punctuation, style: .roman)
        case "!", "?", "'", "|", ":": return .symbol(String(ch), .ordinary, style: .roman)
        default:
            // A directly-typed math glyph (∫ ∑ ≤ →): give it the atom class
            // its `\command` form would, so spacing and (for operators)
            // stacked limits work. `∫x` typed raw now behaves like `\int x`.
            if let cls = glyphAtomClass[String(ch)] {
                return .symbol(String(ch), cls, style: .roman)
            }
            return .symbol(String(ch), .ordinary, style: .roman)
        }
    }

    private static func commandNode(_ name: String, _ tokens: inout ArraySlice<Token>) -> MathNode {
        // Structural commands.
        switch name {
        case "frac", "tfrac", "dfrac":
            let numerator = parseAtom(&tokens) ?? .row([])
            let denominator = parseAtom(&tokens) ?? .row([])
            let frac = MathNode.fraction(numerator: numerator, denominator: denominator)
            switch name {                          // \dfrac/\tfrac force the style
            case "dfrac": return .mathStyle(base: frac, style: .display)
            case "tfrac": return .mathStyle(base: frac, style: .text)
            default: return frac
            }

        case "cfrac":
            var align: CfracAlign = .center        // amsmath default is centered
            if tokens.first == .character("[") {
                tokens.removeFirst()
                var s = ""
                while let t = tokens.first, t != .character("]") {
                    if case .character(let ch) = t { s.append(ch) }
                    tokens.removeFirst()
                }
                if tokens.first == .character("]") { tokens.removeFirst() }
                switch s.trimmingCharacters(in: .whitespaces) {
                case "l": align = .left; case "r": align = .right; default: align = .center
                }
            }
            return .cfrac(numerator: parseAtom(&tokens) ?? .row([]),
                          denominator: parseAtom(&tokens) ?? .row([]), align: align)

        case "binom", "dbinom", "tbinom":
            let top = parseAtom(&tokens) ?? .row([])
            let bottom = parseAtom(&tokens) ?? .row([])
            let binom = MathNode.genfrac(top: top, bottom: bottom, hasRule: false, left: "(", right: ")")
            switch name {
            case "dbinom": return .mathStyle(base: binom, style: .display)
            case "tbinom": return .mathStyle(base: binom, style: .text)
            default: return binom
            }

        case "genfrac":
            // \genfrac{ldelim}{rdelim}{thickness}{style}{num}{denom}
            let ldelim = readBraceName(&tokens), rdelim = readBraceName(&tokens)
            let thickness = readBraceName(&tokens), styleArg = readBraceName(&tokens)
            let num = parseAtom(&tokens) ?? .row([]), den = parseAtom(&tokens) ?? .row([])
            let numeric = thickness.filter { $0.isNumber || $0 == "." }
            let hasRule = thickness.isEmpty || (Double(numeric) ?? 1) != 0   // "0pt" → no rule
            let gf = MathNode.genfrac(top: num, bottom: den, hasRule: hasRule, left: ldelim, right: rdelim)
            switch styleArg {                       // \genfrac style: 0=D 1=T 2=S 3=SS
            case "0": return .mathStyle(base: gf, style: .display)
            case "1": return .mathStyle(base: gf, style: .text)
            case "2": return .mathStyle(base: gf, style: .script)
            case "3": return .mathStyle(base: gf, style: .scriptScript)
            default: return gf
            }

        case "sqrt":
            // Optional degree: \sqrt[3]{x}
            var degree: MathNode?
            if tokens.first == .character("[") {
                tokens.removeFirst()
                var nodes: [MathNode] = []
                while let t = tokens.first, t != .character("]") {
                    if let atom = parseAtom(&tokens) { nodes.append(atom) }
                }
                if tokens.first == .character("]") { tokens.removeFirst() }
                degree = nodes.count == 1 ? nodes[0] : .row(nodes)
            }
            let radicand = parseAtom(&tokens) ?? .row([])
            return .radical(degree: degree, radicand: radicand)

        case "left":
            let leftDelim = takeDelimiter(&tokens) ?? "("
            var segments: [MathNode] = []
            var middles: [String] = []
            var current: [MathNode] = []
            var rightDelim = ")"
            func flush() { segments.append(current.count == 1 ? current[0] : .row(current)); current = [] }
            while let t = tokens.first {
                if case .command("right") = t {
                    tokens.removeFirst()
                    rightDelim = takeDelimiter(&tokens) ?? ")"
                    break
                }
                if case .command("middle") = t {
                    tokens.removeFirst()
                    middles.append(takeDelimiter(&tokens) ?? "|")
                    flush()
                    continue
                }
                if let atom = parseAtomWithScripts(&tokens) { current.append(atom) }
                else if tokens.first != nil { tokens.removeFirst() }   // never spin
            }
            flush()
            // No \middle → the original .delimited path, byte-for-byte unchanged.
            if middles.isEmpty {
                return .delimited(left: leftDelim, body: segments[0], right: rightDelim)
            }
            return .fenced(fences: [leftDelim] + middles + [rightDelim], segments: segments)

        case "text", "mathrm", "operatorname", "textrm":
            // \operatorname* takes stacked limits — capture the star and wrap.
            var starred = false
            if tokens.first == .character("*") { tokens.removeFirst(); starred = true }
            // The tokenizer captured the body verbatim (spaces preserved).
            var result: MathNode = .row([])
            if case .rawText(let s)? = tokens.first {
                tokens.removeFirst()
                result = textWithEmbeddedMath(s)
            }
            return starred ? .limitsOperator(base: result) : result

        case "mathbb", "mathcal", "mathscr", "mathfrak", "mathsf",
             "mathtt", "mathbf", "boldsymbol", "bm":
            let inner = parseAtom(&tokens) ?? .row([])
            return styledLetters(inner, command: name)

        case "pmb":                              // poor-man bold ≈ bold
            return styledLetters(parseAtom(&tokens) ?? .row([]), command: "mathbf")

        case "bf", "rm", "it", "mit", "sl", "sf", "tt", "cal", "frak", "bb", "scr":
            // Old-style (plain TeX / legacy amsmath) font switches. Unlike the
            // `\mathbf{…}` argument form, these are STATEFUL — they apply to
            // the rest of the current group (the same mechanism as stateful
            // `\color` / `\displaystyle`). Common in hand-written and legacy
            // LaTeX; `\vec{\bf E}` and `{\cal C}` are the usual shapes.
            var rest: [MathNode] = []
            while let t = tokens.first, !endsStatefulScope(t) {
                guard let atom = parseAtomWithScripts(&tokens) else { break }
                rest.append(atom)
            }
            let body: MathNode = rest.count == 1 ? rest[0] : .row(rest)
            return Self.oldFontStyled(body, switchName: name)

        // Atom-class overrides: force the inter-atom spacing class of a subexpr.
        case "mathbin":   return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .binary)
        case "mathrel":   return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .relation)
        case "mathop":    return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .largeOperator)
        case "mathord":   return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .ordinary)
        case "mathinner": return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .inner)
        case "mathopen":  return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .opening)
        case "mathclose": return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .closing)
        case "mathpunct": return .classified(base: parseAtom(&tokens) ?? .row([]), atomClass: .punctuation)

        case "begin":
            return parseEnvironment(&tokens)

        case "hat", "check", "tilde", "bar", "vec", "dot", "ddot", "breve",
             "mathring", "acute", "grave", "widehat", "widetilde", "widecheck",
             "overline", "underline":
            // The case list and MathAccent.init? must agree; rather than trust
            // that (a force-unwrap would violate the never-crash contract),
            // degrade to .unsupported if they ever drift.
            guard let accent = MathAccent(command: name) else { return .unsupported("\\" + name) }
            let base = parseAtom(&tokens) ?? .row([])
            return .accent(base: base, accent: accent)

        case "overset", "stackrel":
            // \overset{over}{base}; \stackrel is the same with a relation base.
            let over = parseAtom(&tokens) ?? .row([])
            let base = parseAtom(&tokens) ?? .row([])
            return .overUnder(base: base, over: over, under: nil, kind: .plain)

        case "underset":
            let under = parseAtom(&tokens) ?? .row([])
            let base = parseAtom(&tokens) ?? .row([])
            return .overUnder(base: base, over: nil, under: under, kind: .plain)

        case "overrightarrow", "overleftarrow", "overleftrightarrow",
             "underrightarrow", "underleftarrow", "underleftrightarrow":
            let kind: MathOverUnder
            switch name {
            case "overrightarrow": kind = .overRightArrow
            case "overleftarrow": kind = .overLeftArrow
            case "overleftrightarrow": kind = .overLeftRightArrow
            case "underrightarrow": kind = .underRightArrow
            case "underleftarrow": kind = .underLeftArrow
            default: kind = .underLeftRightArrow
            }
            return .overUnder(base: parseAtom(&tokens) ?? .row([]), over: nil, under: nil, kind: kind)

        case "overbrace":
            let body = parseAtom(&tokens) ?? .row([])
            var label: MathNode?
            if tokens.first == .superscriptMark {
                tokens.removeFirst()
                label = parseAtom(&tokens)
            }
            return .overUnder(base: body, over: label, under: nil, kind: .overbrace)

        case "underbrace":
            let body = parseAtom(&tokens) ?? .row([])
            var label: MathNode?
            if tokens.first == .subscriptMark {
                tokens.removeFirst()
                label = parseAtom(&tokens)
            }
            return .overUnder(base: body, over: nil, under: label, kind: .underbrace)

        case "overbracket", "overparen":
            let body = parseAtom(&tokens) ?? .row([])
            var label: MathNode?
            if tokens.first == .superscriptMark { tokens.removeFirst(); label = parseAtom(&tokens) }
            return .overUnder(base: body, over: label, under: nil,
                              kind: name == "overbracket" ? .overbracket : .overparen)

        case "underbracket", "underparen":
            let body = parseAtom(&tokens) ?? .row([])
            var label: MathNode?
            if tokens.first == .subscriptMark { tokens.removeFirst(); label = parseAtom(&tokens) }
            return .overUnder(base: body, over: nil, under: label,
                              kind: name == "underbracket" ? .underbracket : .underparen)

        case "xrightarrow", "xleftarrow", "xLongrightarrow", "xLongleftarrow",
             "xhookrightarrow", "xhookleftarrow", "xmapsto", "xrightharpoonup",
             "xrightharpoondown", "xleftharpoonup", "xleftharpoondown",
             "xleftrightarrow", "xrightleftharpoons":
            // \xrightarrow[under]{over} — optional [under], then {over}. Each
            // variant draws its own head/shaft (hook, harpoon, mapsto, double).
            var under: MathNode?
            if tokens.first == .character("[") {
                tokens.removeFirst()
                var nodes: [MathNode] = []
                while let t = tokens.first, t != .character("]") {
                    // parseAtomWithScripts so `[k_r]` keeps its subscript.
                    if let atom = parseAtomWithScripts(&tokens) { nodes.append(atom) }
                }
                if tokens.first == .character("]") { tokens.removeFirst() }
                under = nodes.count == 1 ? nodes[0] : .row(nodes)
            }
            let over = parseAtom(&tokens) ?? .row([])
            let kind: MathOverUnder
            switch name {
            case "xleftarrow":         kind = .leftarrow
            case "xLongrightarrow":    kind = .longRightArrow
            case "xLongleftarrow":     kind = .longLeftArrow
            case "xleftrightarrow":    kind = .leftRightArrow
            case "xhookrightarrow":    kind = .hookRightArrow
            case "xhookleftarrow":     kind = .hookLeftArrow
            case "xmapsto":            kind = .mapsToArrow
            case "xrightharpoonup":    kind = .rightHarpoonUp
            case "xrightharpoondown":  kind = .rightHarpoonDown
            case "xleftharpoonup":     kind = .leftHarpoonUp
            case "xleftharpoondown":   kind = .leftHarpoonDown
            case "xrightleftharpoons": kind = .rightLeftHarpoons
            default:                   kind = .rightarrow   // xrightarrow
            }
            return .overUnder(base: .row([]), over: over, under: under, kind: kind)

        case "substack":
            return parseSubstack(&tokens)

        case "boxed", "fbox":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .boxed)
        case "rule":
            if tokens.first == .character("[") {                 // optional [raise] — skip
                while let t = tokens.first, t != .character("]") { tokens.removeFirst() }
                if tokens.first == .character("]") { tokens.removeFirst() }
            }
            let w = readLength(&tokens, muDefault: false)
            let h = readLength(&tokens, muDefault: false)
            return .ruleBox(width: w, height: h)
        case "raisebox":
            let shift = readLength(&tokens, muDefault: false)
            return .raised(base: parseAtom(&tokens) ?? .row([]), shift: shift)
        case "colorbox":
            let bg = readBraceName(&tokens)
            return .colorbox(base: parseAtom(&tokens) ?? .row([]), background: bg, border: nil)
        case "fcolorbox":
            let border = readBraceName(&tokens)
            let bg = readBraceName(&tokens)
            return .colorbox(base: parseAtom(&tokens) ?? .row([]), background: bg, border: border)
        case "cancel":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .cancel)
        case "bcancel":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .bcancel)
        case "xcancel":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .xcancel)
        case "cancelto":
            // \cancelto{target}{expr}: strike expr, target as a raised label.
            let target = parseAtom(&tokens) ?? .row([])
            let expr = parseAtom(&tokens) ?? .row([])
            return .scripts(base: .decorated(base: expr, decoration: .cancel),
                            subscript: nil, superscript: target)
        case "not":
            // \not\subset, \not= : negate the FOLLOWING atom with a slash.
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .negation)
        case "phantom":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .phantom)
        case "hphantom":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .hphantom)
        case "vphantom":
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .vphantom)

        case "textcolor":
            // \textcolor{name}{body} — always localized to the body.
            let color = readBraceName(&tokens)
            return .styled(base: parseAtom(&tokens) ?? .row([]), color: color)

        case "color":
            // \color{name}{body} (localized) OR stateful \color{name} — applies
            // to the rest of the current group.
            let color = readBraceName(&tokens)
            if tokens.first == .groupOpen {
                return .styled(base: parseAtom(&tokens) ?? .row([]), color: color)
            }
            var rest: [MathNode] = []
            while let t = tokens.first, !endsStatefulScope(t) {
                guard let atom = parseAtomWithScripts(&tokens) else { break }
                rest.append(atom)
            }
            return .styled(base: rest.count == 1 ? rest[0] : .row(rest), color: color)

        case "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle":
            // TeX style commands: stateful, applying to the rest of the
            // current group (same mechanism as stateful \color).
            let forced: MathStyle = name == "displaystyle" ? .display
                : name == "textstyle" ? .text
                : name == "scriptstyle" ? .script : .scriptScript
            var rest: [MathNode] = []
            while let t = tokens.first, !endsStatefulScope(t) {
                guard let atom = parseAtomWithScripts(&tokens) else { break }
                rest.append(atom)
            }
            return .mathStyle(base: rest.count == 1 ? rest[0] : .row(rest), style: forced)

        // Spacing.
        case ",", "thinspace": return .space(3.0 / 18.0)
        case ":", "medspace", ">": return .space(4.0 / 18.0)
        case ";", "thickspace": return .space(5.0 / 18.0)
        case "!", "negthinspace": return .space(-3.0 / 18.0)   // negative thin space
        case "negmedspace": return .space(-4.0 / 18.0)
        case "negthickspace": return .space(-5.0 / 18.0)
        case "enspace": return .space(0.5)
        case "notag", "nonumber": return .row([])   // no auto-numbering to suppress
        case "\\":
            // A bare row break OUTSIDE any environment (inside matrix/cases/
            // gather it's consumed by the environment parser). Inline math is
            // a single line — multi-line splitting is a deliberate non-goal —
            // so this degrades to a no-op instead of an unsupported card; the
            // author's surrounding `\quad`/spaces carry the intended gap.
            return .row([])
        case "quad": return .space(1.0)
        case "qquad": return .space(2.0)
        case " ": return .space(6.0 / 18.0)

        // Explicit lengths. \hspace/\kern take em/pt; \mspace/\mkern take mu.
        case "hspace", "kern":
            return .space(readLength(&tokens, muDefault: false))
        case "mspace", "mkern":
            return .space(readLength(&tokens, muDefault: true))

        // Struts, smashing, and lap (overlap) boxes.
        case "mathstrut":
            return .decorated(base: .symbol("(", .opening, style: .roman), decoration: .vphantom)
        case "smash":
            if tokens.first == .character("[") {   // \smash[t]/[b] — treat as plain smash
                while let t = tokens.first, t != .character("]") { tokens.removeFirst() }
                if tokens.first == .character("]") { tokens.removeFirst() }
            }
            return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .smash)
        case "mathrlap": return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .rlap)
        case "mathllap": return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .llap)
        case "mathclap": return .decorated(base: parseAtom(&tokens) ?? .row([]), decoration: .clap)

        // Manual delimiter sizing: \big( … \Bigg]. The prefix sets the target
        // height; the l/r/m suffix sets the spacing class.
        case "big", "Big", "bigg", "Bigg",
             "bigl", "Bigl", "biggl", "Biggl",
             "bigr", "Bigr", "biggr", "Biggr",
             "bigm", "Bigm", "biggm", "Biggm":
            guard let glyph = takeDelimiter(&tokens), !glyph.isEmpty else { return .row([]) }
            return .bigDelimiter(glyph: glyph, factor: bigFactor(name), atomClass: bigClass(name))

        case "pmod":
            let n = parseAtom(&tokens) ?? .row([])
            return .row([.space(0.6), .symbol("(", .opening, style: .roman),
                         .symbol("mod", .ordinary, style: .roman), .space(3.0 / 18.0),
                         n, .symbol(")", .closing, style: .roman)])
        case "pod":
            let n = parseAtom(&tokens) ?? .row([])
            return .row([.space(0.6), .symbol("(", .opening, style: .roman),
                         n, .symbol(")", .closing, style: .roman)])
        case "bmod":
            return .symbol("mod", .binary, style: .roman)

        default:
            if let (glyph, atomClass) = symbolTable[name] {
                return .symbol(glyph, atomClass, style: .roman)
            }
            if functionNames.contains(name) {
                return .functionName(name)
            }
            return .unsupported("\\" + name)
        }
    }

    /// An atom plus any attached scripts — needed inside \left…\right.
    private static func parseAtomWithScripts(_ tokens: inout ArraySlice<Token>) -> MathNode? {
        guard let node = parseAtom(&tokens) else { return nil }
        return attachScriptsAndPrimes(node, &tokens)
    }

    /// Reads a brace-delimited literal name like `{pmatrix}` or `{3}`.
    /// Tokens that end a stateful switch's "rest of the current group" scan
    /// (`\color`, `\displaystyle`, `\bf`, …). Beyond the closing brace, a
    /// switch must not run past the structural boundaries its enclosing
    /// context is itself waiting on — `\right`/`\middle` (a `\left…\right`
    /// body), `&` and `\\` (matrix cells and rows) — or it swallows the
    /// boundary and breaks the enclosing construct (`{\cal C\right|}`).
    private static func endsStatefulScope(_ token: Token) -> Bool {
        switch token {
        case .groupClose, .character("&"): return true
        case .command(let n): return n == "right" || n == "middle" || n == "\\"
        default: return false
        }
    }

    private static func readBraceName(_ tokens: inout ArraySlice<Token>) -> String {
        guard tokens.first == .groupOpen else { return "" }
        tokens.removeFirst()
        var name = ""
        while let t = tokens.first, t != .groupClose {
            tokens.removeFirst()
            if case .character(let ch) = t { name.append(ch) }
        }
        if tokens.first == .groupClose { tokens.removeFirst() }
        return name
    }

    /// Parses the body of `\begin{env} … \end{env}` into a `.matrix`. Cells
    /// are split on `&`, rows on `\\`; unknown environments still lay out as a
    /// bare centered grid so the content survives.
    private static func parseEnvironment(_ tokens: inout ArraySlice<Token>) -> MathNode {
        let env = readBraceName(&tokens)
        let starred = env.hasSuffix("*")
        let base = starred ? String(env.dropLast()) : env

        // `array` carries a column spec (l/c/r + `|` rules); `alignedat`/
        // `alignat` a column count we don't need.
        var columnAligns: [ArraySpec.Align] = []
        var columnRules: Set<Int> = []
        if base == "array" {
            (columnAligns, columnRules) = parseColumnSpec(readBraceName(&tokens))
        } else if base == "alignedat" || base == "alignat" {
            _ = readBraceName(&tokens)          // consume the {n} count (was leaking into cell 1)
        }

        var (left, right, style): (String, String, MathMatrixStyle)
        switch base {
        case "pmatrix": (left, right, style) = ("(", ")", .centered)
        case "bmatrix": (left, right, style) = ("[", "]", .centered)
        case "Bmatrix": (left, right, style) = ("{", "}", .centered)
        case "vmatrix": (left, right, style) = ("|", "|", .centered)
        case "Vmatrix": (left, right, style) = ("‖", "‖", .centered)
        case "cases":   (left, right, style) = ("{", "", .cases)
        case "smallmatrix": (left, right, style) = ("", "", .substack)   // script-size grid
        case "aligned", "align", "alignedat", "alignat", "split",
             "gather", "gathered", "multline",
             "eqalign", "displaylines":     // legacy amsmath/plain-TeX aliases
            (left, right, style) = ("", "", .aligned)
        default:        (left, right, style) = ("", "", .centered)   // matrix, array, …
        }

        // Starred matrix variants (`pmatrix*[r]`, `matrix*[l]`, …) carry an
        // optional column-alignment bracket. Consume it (it used to leak into
        // the first cell) and apply it uniformly via the array alignment path.
        if starred, tokens.first == .character("[") {
            tokens.removeFirst()
            var spec = ""
            while let t = tokens.first, t != .character("]") {
                if case .character(let ch) = t { spec.append(ch) }
                tokens.removeFirst()
            }
            if tokens.first == .character("]") { tokens.removeFirst() }
            let a: ArraySpec.Align = spec.contains("r") ? .right : spec.contains("l") ? .left : .center
            if style == .centered { style = .array(ArraySpec(alignments: [a], columnRules: [], rowRules: [])) }
        }

        var rows: [[MathNode]] = []
        var rowRules: [ArraySpec.RowRule] = []
        var row: [MathNode] = []
        var cell: [MathNode] = []
        func endCell() {
            row.append(cell.count == 1 ? cell[0] : .row(cell))
            cell = []
        }
        func endRow() {
            endCell()
            rows.append(row)
            row = []
        }

        while let token = tokens.first {
            if case .command("end") = token {
                tokens.removeFirst()
                _ = readBraceName(&tokens)          // consume {env}
                break
            }
            if case .command("\\") = token { tokens.removeFirst(); endRow(); continue }
            if case .character("&") = token { tokens.removeFirst(); endCell(); continue }
            // Row rules: `\hline` spans every column at the current boundary;
            // `\cline{i-j}` spans columns i…j. Recorded (and drawn) for `array`;
            // for other environments the ArraySpec is ignored so they're just
            // consumed (previously they degraded the whole grid to a source card).
            if case .command(let c) = token, c == "hline" || c == "hdashline" || c == "cline" {
                tokens.removeFirst()
                if c == "cline" {
                    let arg = readBraceName(&tokens)            // "i-j"
                    if let dash = arg.firstIndex(of: "-"),
                       let i = Int(arg[..<dash]), let j = Int(arg[arg.index(after: dash)...]) {
                        rowRules.append(.init(boundary: rows.count, fromColumn: max(0, i - 1), toColumn: max(0, j - 1)))
                    }
                } else {
                    rowRules.append(.init(boundary: rows.count, fromColumn: 0, toColumn: .max))
                }
                continue
            }
            if let atom = parseAtomWithScripts(&tokens) {
                cell.append(atom)
            } else if tokens.first != nil {
                tokens.removeFirst()                // never spin on an unconsumable token
            }
        }
        // Flush a trailing partial row (no closing `\\`).
        if !cell.isEmpty || !row.isEmpty { endRow() }

        let finalStyle: MathMatrixStyle = base == "array"
            ? .array(ArraySpec(alignments: columnAligns, columnRules: columnRules, rowRules: rowRules))
            : style
        return .matrix(rows: rows, left: left, right: right, style: finalStyle)
    }

    /// Splits a `\text{…}` body on `$` so embedded math renders as math:
    /// `\text{$n$ terms}` → the italic variable `n` followed by upright " terms".
    private static func textWithEmbeddedMath(_ s: String) -> MathNode {
        guard s.contains("$") else { return .functionName(s) }
        var parts: [MathNode] = []
        var inMath = false
        var buf = ""
        func flush() {
            guard !buf.isEmpty else { return }
            parts.append(inMath ? parse(buf) : .functionName(buf))
            buf = ""
        }
        for ch in s {
            if ch == "$" { flush(); inMath.toggle() } else { buf.append(ch) }
        }
        flush()
        return parts.count == 1 ? parts[0] : .row(parts)
    }

    /// Parses an `array` column spec like `l|c|r` into per-column alignment and
    /// the set of column boundaries (0…n) that carry a vertical `|` rule.
    private static func parseColumnSpec(_ spec: String) -> ([ArraySpec.Align], Set<Int>) {
        var aligns: [ArraySpec.Align] = []
        var rules: Set<Int> = []
        for ch in spec {
            switch ch {
            case "l": aligns.append(.left)
            case "c": aligns.append(.center)
            case "r": aligns.append(.right)
            case "|": rules.insert(aligns.count)          // boundary before the next column
            case "p", "m", "b": aligns.append(.left)      // paragraph column → left
            default: break                                // spaces, @{…}, >{…} ignored
            }
        }
        return (aligns, rules)
    }

    /// `\substack{ line1 \\ line2 }` — a tight vertical stack, one cell per
    /// line, used under summation limits. Lowered to a single-column matrix
    /// with the `.substack` style so it reuses the grid layout.
    private static func parseSubstack(_ tokens: inout ArraySlice<Token>) -> MathNode {
        guard tokens.first == .groupOpen else { return .row([]) }
        tokens.removeFirst()
        var rows: [[MathNode]] = []
        var line: [MathNode] = []
        func endLine() { rows.append([line.count == 1 ? line[0] : .row(line)]); line = [] }
        while let token = tokens.first {
            if token == .groupClose { tokens.removeFirst(); break }
            if case .command("\\") = token { tokens.removeFirst(); endLine(); continue }
            if let atom = parseAtomWithScripts(&tokens) {
                line.append(atom)
            } else if tokens.first != nil {
                tokens.removeFirst()
            }
        }
        if !line.isEmpty { endLine() }
        return .matrix(rows: rows, left: "", right: "", style: .substack)
    }

    /// `\big`→1.2, `\Big`→1.8, `\bigg`→2.4, `\Bigg`→3.0 × base size (the
    /// l/r/m suffix doesn't affect height).
    private static func bigFactor(_ name: String) -> CGFloat {
        var core = name
        if let last = core.last, "lrm".contains(last) { core.removeLast() }
        switch core {
        case "Big": return 1.8
        case "bigg": return 2.4
        case "Bigg": return 3.0
        default: return 1.2      // \big
        }
    }

    /// The l/r/m suffix selects the spacing class: `\bigl(` opens, `\bigr)`
    /// closes, `\bigm|` is a relation; a bare `\big` is ordinary.
    private static func bigClass(_ name: String) -> MathAtomClass {
        switch name.last {
        case "l": return .opening
        case "r": return .closing
        case "m": return .relation
        default: return .ordinary
        }
    }

    /// Reads a length argument (`{1em}`, `{18mu}`, or an unbraced `18mu`) and
    /// returns it as an em fraction. `muDefault` picks the unit when none is
    /// given (`\mkern`/`\mspace` default to mu, `\hspace`/`\kern` to pt).
    private static func readLength(_ tokens: inout ArraySlice<Token>, muDefault: Bool) -> Double {
        var s: String
        if tokens.first == .groupOpen {
            s = readBraceName(&tokens)
        } else {
            s = ""
            while let t = tokens.first, case .character(let ch) = t,
                  ch.isNumber || ch == "." || ch == "-" || ch == "+" {
                s.append(ch); tokens.removeFirst()
            }
            var unit = 0                                  // units are 2 letters (em/mu/pt/ex)
            while unit < 2, let t = tokens.first, case .character(let ch) = t, ch.isLetter {
                s.append(ch); tokens.removeFirst(); unit += 1
            }
        }
        return lengthToEm(s, muDefault: muDefault)
    }

    private static func lengthToEm(_ raw: String, muDefault: Bool) -> Double {
        var num = "", unit = ""
        for ch in raw {
            if ch.isNumber || ch == "." || ch == "-" || ch == "+" { num.append(ch) }
            else if ch.isLetter { unit.append(ch) }
        }
        guard let v = Double(num) else { return 0 }
        switch unit.lowercased() {
        case "em": return v
        case "mu": return v / 18.0
        case "ex": return v * 0.43
        case "pt": return v / 10.0
        case "": return muDefault ? v / 18.0 : v / 10.0
        default:  return v / 10.0                          // cm/mm/in — rare inline, approximated
        }
    }

    private static func takeDelimiter(_ tokens: inout ArraySlice<Token>) -> String? {
        guard let token = tokens.first else { return nil }
        tokens.removeFirst()
        switch token {
        case .character(let ch):
            return ch == "." ? "" : String(ch)
        case .command(let name):
            switch name {
            case "{": return "{"
            case "}": return "}"
            case "langle": return "⟨"
            case "rangle": return "⟩"
            case "lvert", "rvert", "vert": return "|"
            case "lVert", "rVert", "Vert": return "‖"
            case "lceil": return "⌈"
            case "rceil": return "⌉"
            case "lfloor": return "⌊"
            case "rfloor": return "⌋"
            case "uparrow": return "↑"
            case "downarrow": return "↓"
            case "updownarrow": return "↕"
            case "Uparrow": return "⇑"
            case "Downarrow": return "⇓"
            case "backslash": return "\\"
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Math font commands. `\mathbf` stays a system-font bold style;
    /// `\boldsymbol`/`\bm` are bold-italic; the rest map each letter/digit
    /// to its Mathematical-Alphanumeric-Symbols codepoint (𝔸 𝒜 𝔞 𝗔 𝚊 …),
    /// which CoreText resolves through STIX/Apple Symbols. The mapped glyph
    /// already encodes the styling, so it carries `.roman` to avoid a
    /// synthetic italic slant on top of it.
    private static func styledLetters(_ node: MathNode, command: String) -> MathNode {
        // `\mathbf` is the one command we render with a real bold system
        // font rather than a codepoint (matches long-standing behavior).
        if command == "mathbf" {
            switch node {
            case .symbol(let s, let cls, _):
                return .symbol(s, cls, style: .bold)
            case .row(let children):
                return .row(children.map { styledLetters($0, command: command) })
            default:
                return node
            }
        }
        guard let alphabet = MathAlphabet(command: command) else { return node }
        switch node {
        case .symbol(let s, let cls, _):
            let mapped = s.count == 1 ? (alphabet.glyph(for: s.first!) ?? s) : s
            return .symbol(mapped, cls, style: .roman)
        case .row(let children):
            return .row(children.map { styledLetters($0, command: command) })
        default:
            return node
        }
    }

    /// Maps an old-style font switch (`\bf`, `\cal`, `\rm`, …) onto the same
    /// styling the `\math*` argument commands produce: alphabet-mapped faces
    /// reuse `styledLetters`; `\rm`/`\it` just set the symbol style.
    private static func oldFontStyled(_ node: MathNode, switchName: String) -> MathNode {
        switch switchName {
        case "bf":   return styledLetters(node, command: "mathbf")
        case "cal":  return styledLetters(node, command: "mathcal")
        case "frak": return styledLetters(node, command: "mathfrak")
        case "bb":   return styledLetters(node, command: "mathbb")
        case "scr":  return styledLetters(node, command: "mathscr")
        case "sf":   return styledLetters(node, command: "mathsf")
        case "tt":   return styledLetters(node, command: "mathtt")
        case "rm":   return restyle(node, to: .roman)
        default:     return restyle(node, to: .italic)   // it, mit, sl
        }
    }

    /// Sets the font style on every symbol in a subtree (for `\rm`/`\it`,
    /// which change slant without remapping to alphabet codepoints).
    private static func restyle(_ node: MathNode, to style: MathSymbolStyle) -> MathNode {
        switch node {
        case .symbol(let s, let cls, _): return .symbol(s, cls, style: style)
        case .row(let kids): return .row(kids.map { restyle($0, to: style) })
        default: return node
        }
    }

}
