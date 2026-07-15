import Foundation

// MathNode → LaTeX serialization. The contract is a RENDER
// round-trip, not string identity: `parse(node.toLaTeX())` must lay out to
// the same scene as the original node (Unicode symbols serialize as
// themselves — the parser accepts them — so no command-name reverse map is
// needed for the symbol table).

extension MathNode {

    /// LaTeX source that re-parses to a render-equivalent node tree.
    public func toLaTeX() -> String {
        switch self {
        case .symbol(let glyph, _, let style):
            switch style {
            case .italic: return glyph
            case .roman:
                // Only ASCII letters need an explicit upright wrapper:
                // mathVariant styles nothing else (digits are upright and
                // lowercase Greek is always italic, per LaTeX convention).
                let needsWrap = glyph.contains { $0.isASCII && $0.isLetter }
                if !needsWrap { return glyph }
                return glyph.contains(" ") ? "\\text{\(glyph)}" : "\\mathrm{\(glyph)}"
            case .bold:
                return "\\mathbf{\(glyph)}"
            }

        case .row(let children):
            return children.map { $0.toLaTeX() }.joined()

        case .fraction(let n, let d):
            return "\\frac{\(n.toLaTeX())}{\(d.toLaTeX())}"

        case .cfrac(let n, let d, let align):
            let opt = align == .left ? "[l]" : align == .right ? "[r]" : ""
            return "\\cfrac\(opt){\(n.toLaTeX())}{\(d.toLaTeX())}"

        case .radical(let degree, let radicand):
            let deg = degree.map { "[\($0.toLaTeX())]" } ?? ""
            return "\\sqrt\(deg){\(radicand.toLaTeX())}"

        case .scripts(let base, let sub, let sup):
            var s = "{\(base.toLaTeX())}"
            if let sub { s += "_{\(sub.toLaTeX())}" }
            if let sup { s += "^{\(sup.toLaTeX())}" }
            return s

        case .delimited(let left, let body, let right):
            return "\\left\(Self.fence(left)) \(body.toLaTeX()) \\right\(Self.fence(right))"

        case .fenced(let fences, let segments):
            guard fences.count == segments.count + 1 else { return segments.map { $0.toLaTeX() }.joined() }
            var s = "\\left\(Self.fence(fences[0])) "
            for (i, seg) in segments.enumerated() {
                s += seg.toLaTeX()
                s += i == segments.count - 1
                    ? " \\right\(Self.fence(fences[i + 1]))"
                    : " \\middle\(Self.fence(fences[i + 1])) "
            }
            return s

        case .matrix(let rows, let left, let right, let style):
            let body = rows.map { $0.map { $0.toLaTeX() }.joined(separator: " & ") }
                .joined(separator: " \\\\ ")
            switch style {
            case .substack:
                return "\\substack{\(body)}"
            case .cases:
                return "\\begin{cases} \(body) \\end{cases}"
            case .aligned:
                return "\\begin{aligned} \(body) \\end{aligned}"
            case .array(let spec):
                var cols = ""
                for (i, a) in spec.alignments.enumerated() {
                    if spec.columnRules.contains(i) { cols += "|" }
                    cols += a == .left ? "l" : a == .right ? "r" : "c"
                }
                if spec.columnRules.contains(spec.alignments.count) { cols += "|" }
                // Reconstruct \hline rows (full-width rules only; \cline
                // reconstructs as \hline over its span approximation).
                var rowsOut: [String] = []
                for (r, row) in rows.enumerated() {
                    if spec.rowRules.contains(where: { $0.boundary == r }) { rowsOut.append("\\hline") }
                    rowsOut.append(row.map { $0.toLaTeX() }.joined(separator: " & "))
                }
                if spec.rowRules.contains(where: { $0.boundary == rows.count }) { rowsOut.append("\\hline") }
                let arrayBody = rowsOut.joined(separator: " \\\\ ")
                    .replacingOccurrences(of: "\\hline \\\\ ", with: "\\hline ")
                return "\\begin{array}{\(cols)} \(arrayBody) \\end{array}"
            case .centered:
                let env: String
                switch (left, right) {
                case ("(", ")"): env = "pmatrix"
                case ("[", "]"): env = "bmatrix"
                case ("{", "}"): env = "Bmatrix"
                case ("|", "|"): env = "vmatrix"
                case ("‖", "‖"): env = "Vmatrix"
                default: env = "matrix"
                }
                return "\\begin{\(env)} \(body) \\end{\(env)}"
            }

        case .functionName(let name):
            return Self.standardFunctions.contains(name) ? "\\\(name) " : "\\operatorname{\(name)}"

        case .limitsOperator(let base):
            if case .functionName(let name) = base { return "\\operatorname*{\(name)}" }
            // A non-function operator forced to stack (e.g. `\int\limits`):
            // keep the `\limits` so the round-trip re-stacks rather than
            // reverting to the operator's default side scripts.
            return base.toLaTeX() + "\\limits "

        case .classified(let base, let cls):
            let cmd: String
            switch cls {
            case .binary: cmd = "mathbin"
            case .relation: cmd = "mathrel"
            case .largeOperator: cmd = "mathop"
            case .opening: cmd = "mathopen"
            case .closing: cmd = "mathclose"
            case .punctuation: cmd = "mathpunct"
            case .ordinary: cmd = "mathord"
            case .inner: cmd = "mathinner"
            }
            return "\\\(cmd){\(base.toLaTeX())}"

        case .ruleBox(let w, let h):
            return "\\rule{\(Self.em(w))}{\(Self.em(h))}"

        case .raised(let base, let shift):
            return "\\raisebox{\(Self.em(shift))}{\(base.toLaTeX())}"

        case .colorbox(let base, let bg, let border):
            if let border { return "\\fcolorbox{\(border)}{\(bg)}{\(base.toLaTeX())}" }
            return "\\colorbox{\(bg)}{\(base.toLaTeX())}"

        case .space(let ems):
            switch ems {
            case 3.0 / 18.0: return "\\,"
            case 4.0 / 18.0: return "\\:"
            case 5.0 / 18.0: return "\\;"
            case -3.0 / 18.0: return "\\!"
            case 1.0: return "\\quad "
            case 2.0: return "\\qquad "
            default: return "\\hspace{\(Self.em(ems))}"
            }

        case .accent(let base, let accent):
            return "\\\(Self.accentCommand(accent)){\(base.toLaTeX())}"

        case .genfrac(let top, let bottom, let hasRule, let left, let right):
            let t = top.toLaTeX(), b = bottom.toLaTeX()
            if hasRule, left.isEmpty, right.isEmpty { return "\\frac{\(t)}{\(b)}" }
            // Ruleless genfracs whose fences are the infix operators' own
            // serialize back to the infix form — the only round-trip-safe
            // spelling for brace/bracket delimiters, whose `{`/`}` can't live
            // inside `\genfrac`'s own brace-delimited delimiter arguments.
            if !hasRule {
                switch (left, right) {
                case ("(", ")"): return "\\binom{\(t)}{\(b)}"
                case ("{", "}"): return "{\(t) \\brace \(b)}"
                case ("[", "]"): return "{\(t) \\brack \(b)}"
                case ("", ""):   return "{\(t) \\atop \(b)}"
                default: break
                }
            }
            return "\\genfrac{\(left)}{\(right)}{\(hasRule ? "1pt" : "0pt")}{}{\(t)}{\(b)}"

        case .overUnder(let base, let over, let under, let kind):
            return Self.overUnderLaTeX(base: base, over: over, under: under, kind: kind)

        case .decorated(let base, let decoration):
            // Braced so a letter argument can't fuse into the command name
            // (`\not a` must not serialize to `\nota`).
            if decoration == .negation { return "\\not{\(base.toLaTeX())}" }
            let cmd: String
            switch decoration {
            case .boxed: cmd = "boxed"
            case .phantom: cmd = "phantom"
            case .hphantom: cmd = "hphantom"
            case .vphantom: cmd = "vphantom"
            case .cancel: cmd = "cancel"
            case .bcancel: cmd = "bcancel"
            case .xcancel: cmd = "xcancel"
            case .smash: cmd = "smash"
            case .rlap: cmd = "mathrlap"
            case .llap: cmd = "mathllap"
            case .clap: cmd = "mathclap"
            case .negation: cmd = "not"
            }
            return "\\\(cmd){\(base.toLaTeX())}"

        case .styled(let base, let color):
            return "\\textcolor{\(color)}{\(base.toLaTeX())}"

        case .mathStyle(let base, let style):
            let cmd: String
            switch style {
            case .display: cmd = "displaystyle"
            case .text: cmd = "textstyle"
            case .script: cmd = "scriptstyle"
            case .scriptScript: cmd = "scriptscriptstyle"
            }
            return "{\\\(cmd) \(base.toLaTeX())}"

        case .bigDelimiter(let glyph, let factor, let atomClass):
            let base: String
            switch factor {
            case ..<1.5: base = "big"
            case ..<2.1: base = "Big"
            case ..<2.7: base = "bigg"
            default: base = "Bigg"
            }
            let suffix: String
            switch atomClass {
            case .opening: suffix = "l"
            case .closing: suffix = "r"
            case .relation: suffix = "m"
            default: suffix = ""
            }
            return "\\\(base)\(suffix)\(Self.fence(glyph))"

        case .unsupported(let source):
            return source
        }
    }

    // MARK: - Helpers

    private static func em(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))em" : "\(v)em"
    }

    /// The `\left`/`\right`-position spelling of a fence glyph.
    private static func fence(_ glyph: String) -> String {
        switch glyph {
        case "": return "."
        case "{": return "\\{"
        case "}": return "\\}"
        case "‖": return "\\Vert "
        case "⟨": return "\\langle "
        case "⟩": return "\\rangle "
        case "⌈": return "\\lceil "
        case "⌉": return "\\rceil "
        case "⌊": return "\\lfloor "
        case "⌋": return "\\rfloor "
        case "\\": return "\\backslash "
        default: return glyph
        }
    }

    private static func accentCommand(_ accent: MathAccent) -> String {
        switch accent {
        case .hat: return "hat"
        case .check: return "check"
        case .tilde: return "tilde"
        case .bar: return "bar"
        case .vec: return "vec"
        case .dot: return "dot"
        case .ddot: return "ddot"
        case .breve: return "breve"
        case .mathring: return "mathring"
        case .acute: return "acute"
        case .grave: return "grave"
        case .widehat: return "widehat"
        case .widetilde: return "widetilde"
        case .widecheck: return "widecheck"
        case .overline: return "overline"
        case .underline: return "underline"
        }
    }

    private static func overUnderLaTeX(base: MathNode, over: MathNode?, under: MathNode?,
                                       kind: MathOverUnder) -> String {
        let b = base.toLaTeX()
        switch kind {
        case .plain:
            switch (over, under) {
            case let (o?, u?): return "\\overset{\(o.toLaTeX())}{\\underset{\(u.toLaTeX())}{\(b)}}"
            case let (o?, nil): return "\\overset{\(o.toLaTeX())}{\(b)}"
            case let (nil, u?): return "\\underset{\(u.toLaTeX())}{\(b)}"
            default: return b
            }
        case .overbrace:
            return "\\overbrace{\(b)}" + (over.map { "^{\($0.toLaTeX())}" } ?? "")
        case .underbrace:
            return "\\underbrace{\(b)}" + (under.map { "_{\($0.toLaTeX())}" } ?? "")
        case .rightarrow, .leftarrow, .longRightArrow, .longLeftArrow, .leftRightArrow,
             .hookRightArrow, .hookLeftArrow, .mapsToArrow,
             .rightHarpoonUp, .rightHarpoonDown, .leftHarpoonUp, .leftHarpoonDown,
             .rightLeftHarpoons:
            let cmd: String
            switch kind {
            case .leftarrow: cmd = "xleftarrow"
            case .longRightArrow: cmd = "xLongrightarrow"
            case .longLeftArrow: cmd = "xLongleftarrow"
            case .leftRightArrow: cmd = "xleftrightarrow"
            case .hookRightArrow: cmd = "xhookrightarrow"
            case .hookLeftArrow: cmd = "xhookleftarrow"
            case .mapsToArrow: cmd = "xmapsto"
            case .rightHarpoonUp: cmd = "xrightharpoonup"
            case .rightHarpoonDown: cmd = "xrightharpoondown"
            case .leftHarpoonUp: cmd = "xleftharpoonup"
            case .leftHarpoonDown: cmd = "xleftharpoondown"
            case .rightLeftHarpoons: cmd = "xrightleftharpoons"
            default: cmd = "xrightarrow"
            }
            let opt = under.map { "[\($0.toLaTeX())]" } ?? ""
            return "\\\(cmd)\(opt){\(over?.toLaTeX() ?? "")}"
        case .overRightArrow: return "\\overrightarrow{\(b)}"
        case .overLeftArrow: return "\\overleftarrow{\(b)}"
        case .overLeftRightArrow: return "\\overleftrightarrow{\(b)}"
        case .underRightArrow: return "\\underrightarrow{\(b)}"
        case .underLeftArrow: return "\\underleftarrow{\(b)}"
        case .underLeftRightArrow: return "\\underleftrightarrow{\(b)}"
        case .overbracket:
            return "\\overbracket{\(b)}" + (over.map { "^{\($0.toLaTeX())}" } ?? "")
        case .underbracket:
            return "\\underbracket{\(b)}" + (under.map { "_{\($0.toLaTeX())}" } ?? "")
        case .overparen:
            return "\\overparen{\(b)}" + (over.map { "^{\($0.toLaTeX())}" } ?? "")
        case .underparen:
            return "\\underparen{\(b)}" + (under.map { "_{\($0.toLaTeX())}" } ?? "")
        }
    }

    /// Function names with dedicated TeX commands (`\sin` …); everything
    /// else round-trips through `\operatorname{…}`.
    private static let standardFunctions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "coth", "exp", "ln", "log", "lg", "lim",
        "limsup", "liminf", "max", "min", "sup", "inf", "det", "gcd", "deg",
        "dim", "hom", "ker", "arg", "Pr", "injlim", "projlim",
    ]
}
