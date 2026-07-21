#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

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
#if os(WASI)
    // WASI Foundation ships no `Thread`, and the wasm runtime is single-threaded,
    // so a plain static counter is equivalent — there is no cross-thread
    // interference to guard against. (Verified: this is the ONLY change needed to
    // cross-compile VinculumLayout to wasm32-unknown-wasip1.) Every other platform
    // keeps the thread-local counter unchanged.
    nonisolated(unsafe) private static var currentDepth = 0
#else
    private static let depthKey = "VinculumMathParserDepth"
    private static var currentDepth: Int {
        get { Thread.current.threadDictionary[depthKey] as? Int ?? 0 }
        set { Thread.current.threadDictionary[depthKey] = newValue }
    }
#endif

    /// Parses a LaTeX math string. Unknown commands become `.unsupported`
    /// leaves; the parse itself never fails.
    public static func parse(_ latex: String) -> MathNode {
        // Linear pre-scan bounds recursion before it starts: parse recursion
        // depth ≤ max brace nesting + \begin count. It also rejects UNBALANCED
        // braces, which is a correctness gate and not just a bound (#8): every
        // `readBraceName` caller scans to its closing brace, so a single missing
        // `}` let one reader swallow the entire rest of the stream as a name —
        // `\textcolor{red a+b` yielded colour "reda+b" with an EMPTY body, and
        // reported isFullySupported == true, so the host's fallback never fired
        // and `a+b` simply vanished. Catching imbalance HERE fixes every reader
        // at once, including any added later.
        //
        // Escape-aware: a backslash consumes the next character, so the literal
        // delimiters `\{` / `\}` don't count (`\left\{ x \right\}` stays valid)
        // and `\\{` still counts its brace.
        var depth = 0, maxDepth = 0, balanced = true
        var chars = latex.makeIterator()
        while let ch = chars.next() {
            if ch == "\\" { _ = chars.next(); continue }
            if ch == "{" { depth += 1; maxDepth = max(maxDepth, depth) }
            if ch == "}" {
                if depth == 0 { balanced = false }   // a `}` with nothing open
                depth = max(0, depth - 1)
            }
        }
        if depth != 0 { balanced = false }           // a `{` never closed
        let begins = latex.components(separatedBy: "\\begin").count - 1
        guard balanced, maxDepth <= maxNestingDepth, begins <= maxNestingDepth else {
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
        case "nolimits":
            tokens.removeFirst()
            return .noLimitsOperator(base: node)
        case "displaylimits":
            // Correctly a no-op: \displaylimits restores the CURRENT style's
            // default placement, which is what an unmodified operator already
            // does. Unlike \nolimits, nothing is lost by dropping it.
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

    /// An empty braced group `{}` parses to `.row([])`; treat it as "no script".
    private static func nonEmptyNode(_ n: MathNode?) -> MathNode? {
        if case .row(let r)? = n, r.isEmpty { return nil }
        return n
    }

    /// Parses one `{ … }` group that carries `_x`/`^y` script marks (the argument
    /// shape of `\sideset`), returning the sub/super it found. A missing group
    /// yields `(nil, nil)`; stray content in the group is consumed and ignored.
    private static func parseScriptCluster(_ tokens: inout ArraySlice<Token>) -> (sub: MathNode?, sup: MathNode?) {
        guard tokens.first == .groupOpen else { return (nil, nil) }
        tokens.removeFirst()
        var sub: MathNode?, sup: MathNode?
        while let t = tokens.first, t != .groupClose {
            if t == .subscriptMark { tokens.removeFirst(); sub = parseAtom(&tokens) }
            else if t == .superscriptMark { tokens.removeFirst(); sup = parseAtom(&tokens) }
            else { _ = parseAtom(&tokens) }
        }
        if tokens.first == .groupClose { tokens.removeFirst() }
        return (sub, sup)
    }

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
        var scripts: [(isSup: Bool, atom: MathNode)] = []
        while let mark = tokens.first, mark == .superscriptMark || mark == .subscriptMark {
            tokens.removeFirst()
            let script = parseAtom(&tokens) ?? .row([])
            let isSup = (mark == .superscriptMark)
            if isSup { sup = script } else { sub = script }
            scripts.append((isSup, script))
        }
        // A repeated same-direction script (a_b_c, x^2^3) is a TeX "Double
        // subscript/superscript" error. Rather than silently clobbering the
        // earlier atom — dropping content with no diagnostic, against the
        // degrade-never-vanish contract — reconstruct the source and surface the
        // whole scripted atom as unsupported so nothing is lost silently (#9).
        let supCount = scripts.filter(\.isSup).count
        if supCount > 1 || scripts.count - supCount > 1 {
            // Reconstruct close to user spelling: brace only composite (multi-atom)
            // pieces, so a_b_c → "a_b_c" (locatable by diagnostics(for:)'s
            // range(of:)), while a grouped base/script like {a+b}_c keeps its
            // braces and isn't misread as a bare base.
            func serial(_ n: MathNode) -> String {
                if case .row(let c) = n, c.count != 1 { return "{\(n.toLaTeX())}" }
                return n.toLaTeX()
            }
            var src = serial(node) + String(repeating: "'", count: primes)
            for s in scripts { src += (s.isSup ? "^" : "_") + serial(s.atom) }
            return .unsupported(src)
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
            if hasUnterminatedBracket(tokens) { return .unsupported("\\" + name) }
            if tokens.first == .character("[") {
                tokens.removeFirst()
                var s = ""
                while let t = tokens.first, t != .character("]") {
                    if case .character(let ch) = t { s.append(ch) }
                    tokens.removeFirst()
                }
                if tokens.first == .character("]") { tokens.removeFirst() }
                switch s.vTrimmingWhitespace() {
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
            if hasUnterminatedBracket(tokens) { return .unsupported("\\" + name) }
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

        case "ce":
            // mhchem: transpile the verbatim body to LaTeX, then parse that.
            guard case .rawText(let body)? = tokens.first else { return .row([]) }
            tokens.removeFirst()
            return parse(MHChem.transpile(body))

        case "ydiagram":
            // \ydiagram{3,2,1} — empty boxes; the partition gives each row's length.
            let spec = readBraceName(&tokens)
            let rows = spec.split(separator: ",", omittingEmptySubsequences: false).map { part -> [MathNode?] in
                let n = Int(part.vTrimmingWhitespace()) ?? 0
                return [MathNode?](repeating: nil, count: max(0, n))
            }
            return .youngTableau(rows: rows)

        case "ytableaushort", "young":
            // \ytableaushort{abc,de} — filled cells; each atom is a cell, `,` a new row.
            return .youngTableau(rows: parseYoungRows(&tokens))

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
             "overrightharpoon", "overleftharpoon", "utilde",
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

        case "prescript":
            // mathtools \prescript{presuper}{presub}{base}. Empty groups drop out.
            let sup = parseAtom(&tokens)
            let sub = parseAtom(&tokens)
            let base = parseAtom(&tokens) ?? .row([])
            return .multiScripts(base: base, preSub: nonEmptyNode(sub), preSuper: nonEmptyNode(sup),
                                 postSub: nil, postSuper: nil)

        case "sideset":
            // amsmath \sideset{_l^l}{_r^r}\op — scripts at the base's four corners.
            // parseAtomWithScripts on the base keeps an operator's own limits.
            let (preSub, preSuper) = parseScriptCluster(&tokens)
            let (postSub, postSuper) = parseScriptCluster(&tokens)
            let base = parseAtomWithScripts(&tokens) ?? .row([])
            if preSub == nil && preSuper == nil && postSub == nil && postSuper == nil { return base }
            return .multiScripts(base: base, preSub: preSub, preSuper: preSuper,
                                 postSub: postSub, postSuper: postSuper)

        case "multicolumn":
            // \multicolumn{n}{colspec}{content} — a cell spanning n table columns.
            let n = max(1, Int(readBraceName(&tokens)) ?? 1)
            let spec = readBraceName(&tokens)
            let content = parseAtom(&tokens) ?? .row([])
            let align: ArraySpec.Align = spec.contains("r") ? .right : spec.contains("l") ? .left : .center
            return .spanned(columns: n, alignment: align, content: content)

        case "mathchoice":
            // \mathchoice{D}{T}{S}{SS} — branch chosen by the current math style.
            let d = parseAtom(&tokens) ?? .row([])
            let t = parseAtom(&tokens) ?? .row([])
            let s = parseAtom(&tokens) ?? .row([])
            let ss = parseAtom(&tokens) ?? .row([])
            return .mathChoice(display: d, text: t, script: s, scriptScript: ss)

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
            if hasUnterminatedBracket(tokens) { return .unsupported("\\" + name) }
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
            if hasUnterminatedBracket(tokens) { return .unsupported("\\" + name) }
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
            if hasUnterminatedBracket(tokens) { return .unsupported("\\" + name) }
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

    /// True when an optional `[…]` argument opens here but is never closed
    /// before end-of-stream.
    ///
    /// Each `[…]` reader scans to its `]` with an unbounded loop, so an
    /// unterminated bracket let it swallow the whole rest of the formula as the
    /// optional argument: `\sqrt[3{x} + y` gave degree `3x+y` and an EMPTY
    /// radicand, yet reported `isFullySupported == true` — so the host's
    /// fallback never fired and the body silently vanished (#8).
    ///
    /// Callers degrade to a visible `.unsupported` leaf instead. Because this
    /// only PEEKS — consuming nothing — the tokens after the `[` still parse as
    /// ordinary content, so the input degrades loudly without losing any of it.
    ///
    /// Brace imbalance is caught up front in `parse`; brackets can't be, since
    /// unbalanced `[` is legitimate math (`[0,1)`), so it's checked per reader.
    private static func hasUnterminatedBracket(_ tokens: ArraySlice<Token>) -> Bool {
        tokens.first == .character("[") && !tokens.contains(.character("]"))
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
        // `\end` closes the environment body; a stateful switch that is the last
        // token of a cell must stop here, or its scan runs through `\end{env}`
        // and swallows the environment terminator and everything after it (#2).
        case .command(let n): return n == "right" || n == "middle" || n == "\\" || n == "end"
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

    /// `\ytableaushort{abc,de}` — each atom is a cell, `,` starts a new row.
    private static func parseYoungRows(_ tokens: inout ArraySlice<Token>) -> [[MathNode?]] {
        guard tokens.first == .groupOpen else { return [] }
        tokens.removeFirst()
        var rows: [[MathNode?]] = [[]]
        while let t = tokens.first, t != .groupClose {
            if t == .character(",") { tokens.removeFirst(); rows.append([]); continue }
            if let cell = parseAtom(&tokens) { rows[rows.count - 1].append(cell) }
            else { tokens.removeFirst() }
        }
        if tokens.first == .groupClose { tokens.removeFirst() }
        if let last = rows.last, last.isEmpty { rows.removeLast() }
        return rows
    }

    // MARK: - Function plots (pgfplots subset)

    /// Parses a `\begin{axis}[domain=a:b, samples=n] \addplot{expr}; … \end{axis}`.
    private static func parseAxisBody(_ tokens: inout ArraySlice<Token>) -> MathNode {
        var xMin = -5.0, xMax = 5.0, samples = 120
        if tokens.first == .character("[") {
            (xMin, xMax, samples) = parsePlotOptions(readBracketOptions(&tokens), xMin, xMax, samples)
        }
        var curves: [PlotCurve] = []
        while let t = tokens.first {
            if case .command("end") = t { tokens.removeFirst(); _ = readBraceName(&tokens); break }
            if case .command("addplot") = t {
                tokens.removeFirst()
                var (lo, hi, n) = (xMin, xMax, samples)
                if tokens.first == .character("[") {
                    (lo, hi, n) = parsePlotOptions(readBracketOptions(&tokens), xMin, xMax, samples)
                }
                _ = (lo, hi)   // per-plot domain currently uses the axis domain for a shared frame
                if case .rawText(let expr)? = tokens.first {
                    tokens.removeFirst()
                    curves.append(PlotCurve(expression: expr, samples: n))
                }
                if tokens.first == .character(";") { tokens.removeFirst() }
                continue
            }
            tokens.removeFirst()   // skip legends / unknown axis options
        }
        return .plot(curves: curves, xMin: xMin, xMax: xMax)
    }

    /// Reads a `[ … ]` option list into a string (character tokens only, `_`/`^` mapped).
    private static func readBracketOptions(_ tokens: inout ArraySlice<Token>) -> String {
        guard tokens.first == .character("[") else { return "" }
        tokens.removeFirst()
        var s = "", depth = 1
        while let t = tokens.first {
            tokens.removeFirst()
            switch t {
            case .character(let ch):
                if ch == "[" { depth += 1 } else if ch == "]" { depth -= 1; if depth == 0 { return s } }
                s.append(ch)
            case .subscriptMark: s.append("_")
            case .superscriptMark: s.append("^")
            default: break
            }
        }
        return s
    }

    private static func parsePlotOptions(_ opts: String, _ x0: Double, _ x1: Double, _ n: Int) -> (Double, Double, Int) {
        var xMin = x0, xMax = x1, samples = n
        for part in opts.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0]).vTrimmingWhitespace(), val = String(kv[1]).vTrimmingWhitespace()
            if key == "domain" {
                let r = val.split(separator: ":")
                if r.count == 2, let a = Double(r[0]), let b = Double(r[1]), a < b { xMin = a; xMax = b }
            } else if key == "samples", let s = Int(val) {
                samples = max(2, min(1000, s))
            }
        }
        return (xMin, xMax, samples)
    }

    // MARK: - Commutative diagrams (amscd)

    private enum CDItem { case object(MathNode); case arrow(CDArrow); case noArrow }

    /// Parses a `\begin{CD} … \end{CD}` body. Rows split on `\\`; within a row,
    /// objects and `@`-arrows alternate. An arrow row (all arrows) becomes vertical
    /// arrows at the even columns; an object row becomes objects with horizontal
    /// arrows between them.
    private static func parseCDBody(_ tokens: inout ArraySlice<Token>) -> MathNode {
        var rowTokens: [[Token]] = [[]]
        while let t = tokens.first {
            if case .command("end") = t { tokens.removeFirst(); _ = readBraceName(&tokens); break }
            tokens.removeFirst()
            if case .command("\\") = t { rowTokens.append([]); continue }
            rowTokens[rowTokens.count - 1].append(t)
        }

        var grid: [[CDCell]] = []
        for row in rowTokens {
            var slice = row[...]
            let items = parseCDRow(&slice)
            if items.isEmpty { continue }
            grid.append(cdCells(from: items))
        }
        let cols = grid.map(\.count).max() ?? 0
        for i in grid.indices { while grid[i].count < cols { grid[i].append(.empty) } }
        while let last = grid.last, last.allSatisfy({ $0 == .empty }) { grid.removeLast() }
        guard !grid.isEmpty else { return .row([]) }
        return .commutativeDiagram(grid: grid)
    }

    private static func parseCDRow(_ slice: inout ArraySlice<Token>) -> [CDItem] {
        var items: [CDItem] = []
        while let t = slice.first {
            if case .character("@") = t {
                items.append(parseCDArrow(&slice))
            } else {
                items.append(.object(parseCDObject(&slice)))
            }
        }
        return items
    }

    /// Reads an object cell: atoms up to the next top-level `@`.
    private static func parseCDObject(_ slice: inout ArraySlice<Token>) -> MathNode {
        var toks: [Token] = []
        var depth = 0
        while let t = slice.first {
            if case .character("@") = t, depth == 0 { break }
            if t == .groupOpen { depth += 1 }; if t == .groupClose { depth -= 1 }
            toks.append(t); slice.removeFirst()
        }
        var s = toks[...]
        let nodes = parseRow(&s, until: nil)
        return nodes.count == 1 ? nodes[0] : .row(nodes)
    }

    /// Parses `@>a>b>` / `@<a<b<` / `@VaVbV` / `@AaAbA` / `@=` / `@|` / `@.`.
    private static func parseCDArrow(_ slice: inout ArraySlice<Token>) -> CDItem {
        slice.removeFirst()                       // consume '@'
        guard let t = slice.first, case .character(let d) = t else { return .noArrow }
        slice.removeFirst()                       // consume the direction char
        switch d {
        case "=", "|": return .arrow(CDArrow(kind: .equal))
        case ".":      return .noArrow
        case ">", "<", "V", "A":
            let kind: CDArrow.Kind = d == ">" ? .right : d == "<" ? .left : d == "V" ? .down : .up
            let label1 = readCDLabel(&slice, until: d)
            let label2 = readCDLabel(&slice, until: d)
            return .arrow(CDArrow(kind: kind, label1: label1, label2: label2))
        default:       return .noArrow
        }
    }

    /// Reads a label up to (and consuming) the next top-level direction char `d`.
    private static func readCDLabel(_ slice: inout ArraySlice<Token>, until d: Character) -> MathNode? {
        var toks: [Token] = []
        var depth = 0
        while let t = slice.first {
            if case .character(let c) = t, c == d, depth == 0 { slice.removeFirst(); break }
            if t == .groupOpen { depth += 1 }; if t == .groupClose { depth -= 1 }
            toks.append(t); slice.removeFirst()
        }
        guard !toks.isEmpty else { return nil }
        var s = toks[...]
        let nodes = parseRow(&s, until: nil)
        return nodes.isEmpty ? nil : (nodes.count == 1 ? nodes[0] : .row(nodes))
    }

    private static func cdCells(from items: [CDItem]) -> [CDCell] {
        let isObjectRow = items.contains { if case .object = $0 { return true }; return false }
        if isObjectRow {
            return items.map { item in
                switch item {
                case .object(let n): return .object(n)
                case .arrow(let a): return .hArrow(a)
                case .noArrow: return .empty
                }
            }
        }
        // Vertical-arrow row: arrows land on even columns, gaps between.
        var cells: [CDCell] = []
        for (i, item) in items.enumerated() {
            if i > 0 { cells.append(.empty) }
            if case .arrow(let a) = item { cells.append(.vArrow(a)) } else { cells.append(.empty) }
        }
        return cells
    }

    /// Parses the body of `\begin{env} … \end{env}` into a `.matrix`. Cells
    /// are split on `&`, rows on `\\`; unknown environments still lay out as a
    /// bare centered grid so the content survives.
    private static func parseEnvironment(_ tokens: inout ArraySlice<Token>) -> MathNode {
        let env = readBraceName(&tokens)
        let starred = env.hasSuffix("*")
        let base = starred ? String(env.dropLast()) : env

        // amscd commutative diagrams parse a different grammar (`@`-arrows).
        if base == "CD" { return parseCDBody(&tokens) }
        // Function plots (pgfplots subset). tikzpicture is transparent — its body
        // holds the axis.
        if base == "axis" { return parseAxisBody(&tokens) }
        if base == "tikzpicture" {
            // Transparent: parse atoms until \end{tikzpicture}. The inner \begin{axis}
            // parses (and consumes through its own \end) into the plot node.
            var nodes: [MathNode] = []
            while let t = tokens.first {
                if case .command("end") = t {
                    var look = tokens; look.removeFirst()
                    if readBraceName(&look) == "tikzpicture" { tokens = look; break }
                }
                if let atom = parseAtom(&tokens) { nodes.append(atom) }
                else if tokens.first != nil { tokens.removeFirst() }
            }
            return nodes.count == 1 ? nodes[0] : .row(nodes)
        }

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
        // Only when the bracket is actually closed: an unterminated `[` would
        // otherwise drain the rest of the stream — `\end` included — leaving no
        // rows, so the entire environment silently disappeared. Left unconsumed
        // it degrades visibly as a stray `[` in the first cell instead (#8).
        if starred, !hasUnterminatedBracket(tokens), tokens.first == .character("[") {
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
        // Fast path: literal text, no embedded math and no commands.
        guard s.contains("$") || s.contains("\\") else { return .functionName(s) }
        var parts: [MathNode] = []
        var inMath = false
        var buf = ""
        func flush() {
            guard !buf.isEmpty else { return }
            parts.append(inMath ? parse(buf) : .functionName(buf))
            buf = ""
        }
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "$" { flush(); inMath.toggle(); i += 1; continue }
            // Inside the TEXT run, resolve LaTeX spacing commands (\, \; \: \quad …)
            // and escaped characters (\& \% \_ …) — otherwise \operatorname{arg\,max}
            // printed the literal "\,". Substituted as Unicode spaces so the text
            // stays ONE glyph run (and one atom, keeping the operator's spacing).
            if !inMath, ch == "\\" {
                var j = i + 1
                var cmd = ""
                if j < chars.count, chars[j].isLetter {
                    while j < chars.count, chars[j].isLetter { cmd.append(chars[j]); j += 1 }
                } else if j < chars.count {
                    cmd = String(chars[j]); j += 1        // single non-letter: \, \; \! \  \& …
                }
                if let rep = Self.textCommandReplacement(cmd) { buf += rep }
                else { buf += "\\" + cmd }                 // unknown → keep literal (rare)
                i = j
                continue
            }
            buf.append(ch); i += 1
        }
        flush()
        return parts.count == 1 ? parts[0] : .row(parts)
    }

    /// Maps the LaTeX spacing and escaped-character commands that may appear inside
    /// `\text`/`\mathrm`/`\operatorname` to their literal rendering. Spaces become
    /// Unicode space characters so the surrounding text remains a single run.
    private static func textCommandReplacement(_ cmd: String) -> String? {
        switch cmd {
        case ",", "thinspace":  return "\u{2009}"          // thin space
        case ":", "medspace":   return "\u{2005}"          // four-per-em (medium)
        case ";", "thickspace": return "\u{2004}"          // three-per-em (thick)
        case " ", "space":      return " "                 // normal inter-word space
        case "quad":            return "\u{2003}"          // em space
        case "qquad":           return "\u{2003}\u{2003}"  // two em spaces
        case "!", "negthinspace", "negmedspace", "negthickspace": return ""  // no negative space in text
        case "&": return "&"
        case "%": return "%"
        case "_": return "_"
        case "#": return "#"
        case "$": return "$"
        case "{": return "{"
        case "}": return "}"
        default:  return nil
        }
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

    /// Math font commands. `\mathbf` carries the upright-bold symbol style, which
    /// `mathVariant` maps to the Mathematical-Alphanumeric **bold** codepoints
    /// (𝐀…𝐳, bold Greek 𝚨…𝛚, bold digits 𝟎…𝟗). `\boldsymbol`/`\bm` are bold-italic;
    /// the rest map each letter/digit to its own codepoint block (𝔸 𝒜 𝔞 𝗔 𝚊 …),
    /// which the math font resolves. The mapped glyph already encodes the styling,
    /// so it carries `.roman` to avoid a synthetic italic slant on top of it.
    private static func styledLetters(_ node: MathNode, command: String) -> MathNode {
        // `\mathbf` keeps the `.bold` symbol style; the layout's `mathVariant`
        // resolves it to the bold Math-Alphanumeric codepoint per glyph.
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
