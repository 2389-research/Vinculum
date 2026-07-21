#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// Serializes a `MathNode` tree to **Presentation MathML** — the second serializer
/// off the parse tree (alongside `toLaTeX`), for accessibility trees, copy-as-MathML,
/// and interop with tools that ingest MathML. Platform-free: pure string building,
/// no layout or fonts. Unknown/unsupported nodes degrade to a labelled `<merror>`
/// rather than vanishing.
///
/// This is Presentation (not Content) MathML: it describes how the math *looks*
/// (`<mfrac>`, `<msup>`, `<mo>`…), which is what screen readers and browsers render.
public enum MathMLExporter {

    /// Full document: `<math>…</math>` with the MathML namespace. `display`
    /// sets `display="block"` (vs the default inline).
    public static func export(_ node: MathNode, display: Bool = false) -> String {
        let attr = display ? #" display="block""# : ""
        return #"<math xmlns="http://www.w3.org/1998/Math/MathML"\#(attr)>"# + mathml(node) + "</math>"
    }

    // MARK: - Node → MathML

    static func mathml(_ node: MathNode) -> String {
        switch node {
        case .symbol(let s, let cls, _):
            return token(for: s, cls: cls)

        case .functionName(let name):
            return "<mo>\(escape(name))</mo>"

        case .row(let children):
            return mrow(children)

        case .fraction(let n, let d), .cfrac(let n, let d, _):
            return "<mfrac>\(mathml(n))\(mathml(d))</mfrac>"

        case .genfrac(let top, let bottom, let hasRule, let left, let right):
            let bars = hasRule ? "" : #" linethickness="0""#
            let frac = "<mfrac\(bars)>\(mathml(top))\(mathml(bottom))</mfrac>"
            return fenced(left, frac, right)

        case .radical(let degree, let radicand):
            if let degree {
                return "<mroot>\(mathml(radicand))\(mathml(degree))</mroot>"
            }
            return "<msqrt>\(mathml(radicand))</msqrt>"

        case .scripts(let base, let sub, let sup):
            switch (sub, sup) {
            case (let sub?, let sup?): return "<msubsup>\(mathml(base))\(mathml(sub))\(mathml(sup))</msubsup>"
            case (let sub?, nil):      return "<msub>\(mathml(base))\(mathml(sub))</msub>"
            case (nil, let sup?):      return "<msup>\(mathml(base))\(mathml(sup))</msup>"
            case (nil, nil):           return mathml(base)
            }

        case .multiScripts(let base, let preSub, let preSuper, let postSub, let postSuper):
            // <mmultiscripts> base (postsub postsup)? <mprescripts/> (presub presup)?
            let none = "<none/>"
            var s = "<mmultiscripts>\(mathml(base))"
            if postSub != nil || postSuper != nil {
                s += (postSub.map(mathml) ?? none) + (postSuper.map(mathml) ?? none)
            }
            if preSub != nil || preSuper != nil {
                s += "<mprescripts/>" + (preSub.map(mathml) ?? none) + (preSuper.map(mathml) ?? none)
            }
            return s + "</mmultiscripts>"

        case .accent(let base, let accent):
            return accentML(base: base, accent: accent)

        case .overUnder(let base, let over, let under, _):
            switch (under, over) {
            case (let u?, let o?): return "<munderover>\(mathml(base))\(mathml(u))\(mathml(o))</munderover>"
            case (let u?, nil):    return "<munder>\(mathml(base))\(mathml(u))</munder>"
            case (nil, let o?):    return "<mover>\(mathml(base))\(mathml(o))</mover>"
            case (nil, nil):       return mathml(base)
            }

        case .delimited(let left, let body, let right):
            return fenced(left, mathml(body), right)

        case .fenced(let fences, let segments):
            guard let first = fences.first else { return mrow(segments) }
            var inner = "<mo>\(escape(fenceGlyph(first)))</mo>"
            for (i, seg) in segments.enumerated() {
                inner += mathml(seg)
                if i + 1 < fences.count { inner += "<mo>\(escape(fenceGlyph(fences[i + 1])))</mo>" }
            }
            return "<mrow>\(inner)</mrow>"

        case .plot(let curves, _, _):
            // No plot element in Presentation MathML; describe it as text.
            let fns = curves.map(\.expression).joined(separator: ", ")
            return "<mtext>plot: \(escape(fns))</mtext>"

        case .inferenceRule(let premises, let conclusion, _):
            // Premises over a fraction-like bar over the conclusion.
            let prem = premises.count == 1 ? mathml(premises[0])
                : "<mrow>" + premises.map(mathml).joined(separator: "<mspace width=\"1em\"/>") + "</mrow>"
            return "<mfrac linethickness=\"0.8pt\">\(prem)\(mathml(conclusion))</mfrac>"

        case .youngTableau(let rows):
            return "<mtable frame=\"solid\" rowlines=\"solid\" columnlines=\"solid\">" + rows.map { row in
                "<mtr>" + row.map { "<mtd>\($0.map(mathml) ?? "")</mtd>" }.joined() + "</mtr>"
            }.joined() + "</mtable>"

        case .commutativeDiagram(let grid):
            // No CD element in Presentation MathML; approximate as a table whose cells
            // are objects or arrow glyphs — structure a reader/consumer can still walk.
            let table = "<mtable>" + grid.map { row in
                "<mtr>" + row.map { cell -> String in
                    switch cell {
                    case .object(let n): return "<mtd>\(mathml(n))</mtd>"
                    case .hArrow(let a): return "<mtd><mo>\(cdArrowGlyph(a, horizontal: true))</mo></mtd>"
                    case .vArrow(let a): return "<mtd><mo>\(cdArrowGlyph(a, horizontal: false))</mo></mtd>"
                    case .empty: return "<mtd/>"
                    }
                }.joined() + "</mtr>"
            }.joined() + "</mtable>"
            return table

        case .matrix(let rows, let left, let right, _):
            let table = "<mtable>" + rows.map { row in
                "<mtr>" + row.map { "<mtd>\(mathml($0))</mtd>" }.joined() + "</mtr>"
            }.joined() + "</mtable>"
            return (left.isEmpty && right.isEmpty) ? table : fenced(left, table, right)

        case .spanned(_, _, let content):
            return mathml(content)   // MathML columnspan is a table attr; content is faithful

        case .mathChoice(_, let text, _, _):
            return mathml(text)      // the text-style branch is the representative form

        case .limitsOperator(let base), .noLimitsOperator(let base),
             .classified(let base, _), .decorated(let base, _), .mathStyle(let base, _):
            return mathml(base)

        case .raised(let base, _):
            return mathml(base)

        case .styled(let base, let color):
            return #"<mstyle mathcolor="\#(escape(color))">\#(mathml(base))</mstyle>"#

        case .colorbox(let base, _, _):
            return "<menclose notation=\"box\">\(mathml(base))</menclose>"

        case .bigDelimiter(let glyph, _, _):
            return "<mo>\(escape(fenceGlyph(glyph)))</mo>"

        case .space(let em):
            return #"<mspace width="\#(fmt(em))em"/>"#

        case .ruleBox:
            return "<mspace/>"

        case .unsupported(let src):
            return "<merror><mtext>\(escape(src))</mtext></merror>"
        }
    }

    // MARK: - Helpers

    private static func cdArrowGlyph(_ a: CDArrow, horizontal: Bool) -> String {
        switch a.kind {
        case .right: return "\u{2192}"   // →
        case .left:  return "\u{2190}"   // ←
        case .up:    return "\u{2191}"   // ↑
        case .down:  return "\u{2193}"   // ↓
        case .equal: return horizontal ? "=" : "\u{2016}"
        }
    }

    private static func mrow(_ children: [MathNode]) -> String {
        if children.count == 1 { return mathml(children[0]) }
        return "<mrow>" + children.map(mathml).joined() + "</mrow>"
    }

    /// A single symbol → `<mi>` (identifier), `<mn>` (number), or `<mo>` (operator),
    /// chosen from its atom class — the distinction screen readers rely on.
    private static func token(for s: String, cls: MathAtomClass) -> String {
        switch cls {
        case .ordinary:
            if s.count == 1, let c = s.first, c.isNumber { return "<mn>\(escape(s))</mn>" }
            return "<mi>\(escape(s))</mi>"
        case .largeOperator, .binary, .relation, .punctuation, .opening, .closing, .inner:
            return "<mo>\(escape(s))</mo>"
        }
    }

    private static func accentML(base: MathNode, accent: MathAccent) -> String {
        if accent == .underline {
            return #"<munder>\#(mathml(base))<mo>_</mo></munder>"#
        }
        let glyph = accent.glyph ?? (accent == .overline ? "\u{203E}" : "")
        let pos = accent.isUnder ? "munder" : "mover"
        return "<\(pos) accent=\"true\">\(mathml(base))<mo>\(escape(glyph))</mo></\(pos)>"
    }

    private static func fenced(_ left: String, _ inner: String, _ right: String) -> String {
        let l = left.isEmpty ? "" : "<mo>\(escape(fenceGlyph(left)))</mo>"
        let r = right.isEmpty ? "" : "<mo>\(escape(fenceGlyph(right)))</mo>"
        return "<mrow>\(l)\(inner)\(r)</mrow>"
    }

    /// Maps the parser's fence spelling ("(", "langle", "|", "") to its glyph.
    private static func fenceGlyph(_ f: String) -> String {
        switch f {
        case "langle": return "\u{27E8}"
        case "rangle": return "\u{27E9}"
        case "lceil": return "\u{2308}";  case "rceil": return "\u{2309}"
        case "lfloor": return "\u{230A}"; case "rfloor": return "\u{230B}"
        case "vert", "|": return "|"
        case "Vert", "\\|": return "\u{2016}"
        case "": return ""
        default: return f
        }
    }

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : vFormat2(v)
    }

    /// XML-escapes the five predefined entities so glyphs like `<`, `&` are valid.
    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(c)
            }
        }
        return out
    }
}

public extension MathNode {
    /// Presentation MathML for this subtree (no wrapping `<math>` element).
    func toMathML() -> String { MathMLExporter.mathml(self) }
}
