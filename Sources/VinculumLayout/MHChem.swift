#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A small mhchem (`\ce{…}`) transpiler: converts a chemical formula/equation into
/// equivalent LaTeX math, which the ordinary parser then lays out. This reuses the
/// whole engine — scripts, upright text, arrows — so chemistry needs no new node or
/// layout code, exactly how mhchem itself expands to TeX.
///
/// Covers the common cases: auto-subscripted formulas (`H2O` → H₂O), groups
/// (`Ca(OH)2`), charges (`SO4^2-`), coefficients (`2 H2O`), reaction arrows
/// (`->`, `<-`, `<=>`, `<->`, and `->[cat]` conditions), bonds (`=`, `#`), states
/// (`(s) (l) (g) (aq)`), and hydrate dots (`*`).
public enum MHChem {

    public static func transpile(_ source: String) -> String {
        let c = Array(source)
        var i = 0
        var out = ""
        var afterAtom = false   // was the last thing an atom/group? → a following number is a subscript

        func readGroupOrChar() -> String {
            guard i < c.count else { return "" }
            if c[i] == "{" {
                var depth = 0, body = ""
                while i < c.count {
                    let ch = c[i]
                    if ch == "{" { depth += 1; if depth == 1 { i += 1; continue } }
                    else if ch == "}" { depth -= 1; if depth == 0 { i += 1; break } }
                    body.append(ch); i += 1
                }
                return body
            }
            let ch = c[i]; i += 1
            return String(ch)
        }

        while i < c.count {
            // Reaction arrows (longest match first), with optional [above][below].
            if let (latex, len) = matchArrow(c, i) {
                i += len
                let above = readBracket(c, &i)
                let below = readBracket(c, &i)
                if above != nil || below != nil {
                    // A conditional arrow → \xrightarrow[below]{above} (only the right arrow
                    // takes conditions in mhchem's common use).
                    out += " \\xrightarrow[\(transpile(below ?? ""))]{\(transpile(above ?? ""))} "
                } else {
                    out += " \(latex) "
                }
                afterAtom = false
                continue
            }

            let ch = c[i]
            switch ch {
            case "A"..."Z":
                var el = String(ch); i += 1
                while i < c.count, ("a"..."z").contains(c[i]) { el.append(c[i]); i += 1 }
                out += "\\mathrm{\(el)}"
                afterAtom = true

            case "0"..."9":
                var num = ""
                while i < c.count, ("0"..."9").contains(c[i]) { num.append(c[i]); i += 1 }
                // A fraction coefficient like 1/2.
                if i < c.count, c[i] == "/", i + 1 < c.count, ("0"..."9").contains(c[i + 1]) {
                    i += 1
                    var den = ""
                    while i < c.count, ("0"..."9").contains(c[i]) { den.append(c[i]); i += 1 }
                    out += afterAtom ? "_{\(num)/\(den)}" : "\\tfrac{\(num)}{\(den)}"
                } else {
                    out += afterAtom ? "_{\(num)}" : num
                }
                // A leading number is a coefficient; the next element starts fresh (afterAtom stays as set).

            case "^":
                i += 1
                out += "^{\(readGroupOrCharge(c, &i))}"
                afterAtom = true

            case "_":
                i += 1
                out += "_{\(readGroupOrChar())}"
                afterAtom = true

            case "(":
                if let (state, len) = matchState(c, i) {
                    out += "\\,\\mathrm{\(state)}"; i += len; afterAtom = true
                } else {
                    out += "("; i += 1; afterAtom = false
                }

            case ")":
                out += ")"; i += 1; afterAtom = true   // a number after ) is a subscript

            case "+":
                out += " + "; i += 1; afterAtom = false

            case "=":
                out += "{=}"; i += 1; afterAtom = false   // double bond

            case "#":
                out += "{\\equiv}"; i += 1; afterAtom = false   // triple bond

            case "-":
                out += "{-}"; i += 1; afterAtom = false   // single bond (arrows already matched above)

            case "*", ".":
                out += " \\cdot "; i += 1; afterAtom = false   // hydrate dot

            case " ":
                out += " "; i += 1; afterAtom = false   // a space separates species; a following number is a coefficient

            case "{":
                out += "{\(readGroupOrChar())}"   // pass a literal group through

            case "\\":
                // A LaTeX command inside \ce (e.g. \Delta, \alpha) — pass it through
                // verbatim rather than reading its letters as an element.
                var cmd = "\\"; i += 1
                while i < c.count, ("a"..."z").contains(c[i]) || ("A"..."Z").contains(c[i]) { cmd.append(c[i]); i += 1 }
                if cmd == "\\" && i < c.count { cmd.append(c[i]); i += 1 }   // a single escaped char
                out += cmd + " "
                afterAtom = true

            default:
                out.append(ch); i += 1
            }
        }
        return out
    }

    // MARK: - Sub-scanners

    private static func matchArrow(_ c: [Character], _ i: Int) -> (String, Int)? {
        func has(_ s: String) -> Bool {
            let a = Array(s)
            guard i + a.count <= c.count else { return false }
            for k in 0..<a.count where c[i + k] != a[k] { return false }
            return true
        }
        // Longest first.
        if has("<=>>") { return ("\\rightleftharpoons", 4) }
        if has("<<=>") { return ("\\rightleftharpoons", 4) }
        if has("<=>") { return ("\\rightleftharpoons", 3) }
        if has("<->") { return ("\\leftrightarrow", 3) }
        if has("->") { return ("\\longrightarrow", 2) }
        if has("<-") { return ("\\longleftarrow", 2) }
        return nil
    }

    /// After a `->` etc., reads an optional `[…]` condition.
    private static func readBracket(_ c: [Character], _ i: inout Int) -> String? {
        guard i < c.count, c[i] == "[" else { return nil }
        i += 1
        var depth = 1, body = ""
        while i < c.count, depth > 0 {
            let ch = c[i]
            if ch == "[" { depth += 1 } else if ch == "]" { depth -= 1; if depth == 0 { i += 1; break } }
            if depth > 0 { body.append(ch) }
            i += 1
        }
        return body
    }

    /// A charge body after `^`: a `{…}` group, or `[digits][+/-]` (e.g. `2+`, `-`).
    private static func readGroupOrCharge(_ c: [Character], _ i: inout Int) -> String {
        if i < c.count, c[i] == "{" {
            i += 1
            var depth = 1, body = ""
            while i < c.count, depth > 0 {
                let ch = c[i]
                if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1; if depth == 0 { i += 1; break } }
                if depth > 0 { body.append(ch) }
                i += 1
            }
            return body
        }
        var body = ""
        while i < c.count, ("0"..."9").contains(c[i]) { body.append(c[i]); i += 1 }
        if i < c.count, c[i] == "+" || c[i] == "-" { body.append(c[i]); i += 1 }
        return body.isEmpty ? "" : body
    }

    /// A physical state `(s) (l) (g) (aq)` at position `i`.
    private static func matchState(_ c: [Character], _ i: Int) -> (String, Int)? {
        for s in ["(aq)", "(s)", "(l)", "(g)"] {
            let a = Array(s)
            guard i + a.count <= c.count else { continue }
            if (0..<a.count).allSatisfy({ c[i + $0] == a[$0] }) { return (s, a.count) }
        }
        return nil
    }
}
