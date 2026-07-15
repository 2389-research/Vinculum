import Foundation

/// Spoken-math descriptions from the node tree — the text VoiceOver reads
/// for a rendered equation ("x equals the fraction negative b plus or minus
/// the square root of b squared minus 4 a c, over 2 a"). Loosely follows
/// ClearSpeak conventions: name the structure, read the content, close the
/// structure when it's compound.
///
/// Generated from the same tree that is typeset, so the speech always
/// matches the pixels.
public enum MathSpeech {

    /// A spoken description of the expression.
    public static func describe(_ node: MathNode) -> String {
        collapse(speak(node))
    }

    // MARK: - Tree walk

    private static func speak(_ node: MathNode) -> String {
        switch node {
        case .symbol(let glyph, _, _):
            return spokenSymbol(glyph)

        case .row(let children):
            return children.map(speak).joined(separator: " ")

        case .fraction(let n, let d), .cfrac(let n, let d, _):
            if let simple = simpleFraction(n, d) { return simple }
            return "the fraction \(speak(n)), over \(speak(d)),"

        case .radical(let degree, let radicand):
            switch degree.map(speak) {
            case nil: return "the square root of \(speak(radicand)),"
            case "2": return "the square root of \(speak(radicand)),"
            case "3": return "the cube root of \(speak(radicand)),"
            case let d?: return "the \(d)th root of \(speak(radicand)),"
            }

        case .scripts(let base, let sub, let sup):
            var s = speak(base)
            if let sub { s += " sub \(speak(sub))" }
            if let sup {
                let spoken = speak(sup)
                switch spoken {
                case "2": s += " squared"
                case "3": s += " cubed"
                default: s += " to the power \(spoken)"
                }
            }
            return s

        case .delimited(let left, let body, let right):
            let name = fenceName(left, right)
            return "open \(name) \(speak(body)) close \(name)"

        case .fenced(_, let segments):
            return "open " + segments.map(speak).joined(separator: ", such that ") + " close"

        case .matrix(let rows, _, _, let style):
            if style == .cases {
                return "cases: " + rows.map { $0.map(speak).joined(separator: " when ") }
                    .joined(separator: "; ")
            }
            let r = rows.count, c = rows.first?.count ?? 0
            let body = rows.enumerated().map { i, row in
                "row \(i + 1): " + row.map(speak).joined(separator: ", ")
            }.joined(separator: "; ")
            return "a \(r) by \(c) matrix: \(body)"

        case .functionName(let name):
            return spokenFunction(name)

        case .limitsOperator(let base), .classified(let base, _):
            return speak(base)

        case .ruleBox:
            return ""

        case .raised(let base, _), .colorbox(let base, _, _), .styled(let base, _),
             .mathStyle(let base, _):
            return speak(base)

        case .space:
            return ""

        case .accent(let base, let accent):
            return accentSpeech(base: base, accent: accent)

        case .genfrac(let top, let bottom, let hasRule, let left, _):
            if !hasRule && left == "(" {
                return "\(speak(top)) choose \(speak(bottom))"
            }
            if hasRule { return "the fraction \(speak(top)), over \(speak(bottom))," }
            return "\(speak(top)) over \(speak(bottom))"

        case .overUnder(let base, let over, let under, let kind):
            switch kind {
            case .overRightArrow: return "vector \(speak(base))"
            case .overbrace, .overbracket, .overparen:
                let ann = over.map { ", labeled \(speak($0))" } ?? ""
                return "\(speak(base))\(ann)"
            case .underbrace, .underbracket, .underparen:
                let ann = under.map { ", labeled \(speak($0))" } ?? ""
                return "\(speak(base))\(ann)"
            case .rightarrow, .leftarrow, .longRightArrow, .longLeftArrow, .leftRightArrow,
                 .hookRightArrow, .hookLeftArrow, .mapsToArrow,
                 .rightHarpoonUp, .rightHarpoonDown, .leftHarpoonUp, .leftHarpoonDown,
                 .rightLeftHarpoons:
                let word = (kind == .mapsToArrow) ? "maps to" : "arrow"
                let label = over.map(speak) ?? ""
                let sub = under.map { " under \(speak($0))" } ?? ""
                return "\(word) \(label)\(sub)"
            default:
                var s = speak(base)
                if let over { s = "\(speak(over)) over \(s)" }
                if let under { s = "\(s) under \(speak(under))" }
                return s
            }

        case .decorated(let base, let decoration):
            switch decoration {
            case .phantom, .hphantom, .vphantom: return ""
            case .cancel, .bcancel, .xcancel: return "\(speak(base)), crossed out,"
            case .negation: return "not \(speak(base))"
            default: return speak(base)
            }

        case .bigDelimiter(let glyph, _, _):
            return spokenSymbol(glyph)

        case .unsupported(let source):
            return source
        }
    }

    /// "1 half", "2 thirds" … for small numeric fractions (ClearSpeak).
    private static func simpleFraction(_ n: MathNode, _ d: MathNode) -> String? {
        guard case .symbol(let ns, _, _) = unwrap(n), let nv = Int(ns), nv > 0, nv < 10,
              case .symbol(let ds, _, _) = unwrap(d), let dv = Int(ds), dv > 1, dv < 10
        else { return nil }
        let names = [2: "half", 3: "third", 4: "fourth", 5: "fifth",
                     6: "sixth", 7: "seventh", 8: "eighth", 9: "ninth"]
        guard let unit = names[dv] else { return nil }
        return nv == 1 ? "1 \(unit)" : "\(nv) \(unit)s"
    }

    private static func unwrap(_ node: MathNode) -> MathNode {
        if case .row(let kids) = node, kids.count == 1 { return unwrap(kids[0]) }
        return node
    }

    private static func accentSpeech(base: MathNode, accent: MathAccent) -> String {
        let b = speak(base)
        switch accent {
        case .hat, .widehat: return "\(b) hat"
        case .bar, .overline: return "\(b) bar"
        case .vec: return "vector \(b)"
        case .dot: return "\(b) dot"
        case .ddot: return "\(b) double dot"
        case .tilde, .widetilde: return "\(b) tilde"
        case .underline: return "\(b), underlined,"
        default: return b
        }
    }

    private static func fenceName(_ left: String, _ right: String) -> String {
        switch (left, right) {
        case ("(", ")"): return "paren"
        case ("[", "]"): return "bracket"
        case ("{", "}"): return "brace"
        case ("|", "|"): return "absolute value"
        case ("‖", "‖"): return "norm"
        case ("⟨", "⟩"): return "angle bracket"
        default: return "fence"
        }
    }

    private static func spokenFunction(_ name: String) -> String {
        let map: [String: String] = [
            "sin": "sine", "cos": "cosine", "tan": "tangent",
            "arcsin": "arc sine", "arccos": "arc cosine", "arctan": "arc tangent",
            "sinh": "hyperbolic sine", "cosh": "hyperbolic cosine", "tanh": "hyperbolic tangent",
            "ln": "natural log", "log": "log", "lg": "log",
            "lim": "the limit", "limsup": "the limit superior", "liminf": "the limit inferior",
            "max": "the maximum", "min": "the minimum", "sup": "the supremum",
            "inf": "the infimum", "det": "the determinant", "gcd": "the g c d",
            "exp": "the exponential", "Pr": "the probability",
        ]
        return map[name] ?? name
    }

    private static func spokenSymbol(_ glyph: String) -> String {
        if let spoken = symbolNames[glyph] { return spoken }
        return glyph
    }

    /// Common symbols → spoken names. Unknown glyphs speak as themselves
    /// (VoiceOver pronounces Greek and letters natively).
    private static let symbolNames: [String: String] = [
        "+": "plus", "−": "minus", "-": "minus", "±": "plus or minus",
        "×": "times", "⋅": "times", "·": "times", "∗": "star", "/": "over",
        "=": "equals", "≠": "is not equal to", "≈": "is approximately",
        "≡": "is equivalent to", "<": "is less than", ">": "is greater than",
        "≤": "is less than or equal to", "≥": "is greater than or equal to",
        "→": "goes to", "↦": "maps to", "⇒": "implies", "⇔": "if and only if",
        "∈": "is in", "∉": "is not in", "⊂": "is a subset of",
        "⊆": "is a subset of or equal to", "∪": "union", "∩": "intersect",
        "∀": "for all", "∃": "there exists", "¬": "not", "∧": "and", "∨": "or",
        "∑": "the sum", "∏": "the product", "∫": "the integral",
        "∮": "the contour integral", "∞": "infinity", "∂": "partial",
        "∇": "nabla", "√": "root", "∝": "is proportional to",
        ",": "comma", "!": "factorial", "′": "prime", "…": "dot dot dot",
        "⋯": "dot dot dot", "ℝ": "the real numbers", "ℂ": "the complex numbers",
        "ℕ": "the natural numbers", "ℤ": "the integers", "ℚ": "the rationals",
        "π": "pi", "θ": "theta", "α": "alpha", "β": "beta", "γ": "gamma",
        "δ": "delta", "ε": "epsilon", "λ": "lambda", "μ": "mu", "σ": "sigma",
        "φ": "phi", "ω": "omega", "Δ": "capital delta", "Ω": "capital omega",
        "Σ": "capital sigma", "ħ": "h bar",
    ]

    /// Collapses doubled spaces/commas the templates can produce.
    private static func collapse(_ s: String) -> String {
        var out = s
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        out = out.replacingOccurrences(of: " ,", with: ",")
        while out.contains(",,") { out = out.replacingOccurrences(of: ",,", with: ",") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return out
    }
}
