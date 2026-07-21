#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A small siunitx transpiler: converts `\num`, `\ang`, `\si`/`\unit`, and
/// `\SI`/`\qty` into equivalent LaTeX math, which the ordinary parser then lays
/// out. Like `MHChem`, this reuses the whole engine — upright unit symbols, thin
/// spaces, superscripts — so units need no new node or layout code.
///
/// Covers the common cases:
/// - `\num{1.5e3}` → 1.5×10³, with sign, decimal, and thousands grouping.
/// - `\ang{45;30;15}` → 45°30′15″ (degrees; minutes; seconds).
/// - `\si{kg.m.s^{-1}}` / `\unit{\kilo\gram}` → upright unit symbols, `.`/`~`
///   as thin spaces, `/` as a solidus, macro names expanded from a dictionary.
/// - `\SI{9.8}{m/s^2}` / `\qty{9.8}{m/s^2}` → number, thin space, units.
public enum SIUnitx {

    /// `\SI{value}{unit}` / `\qty{value}{unit}` — a number and a unit, thin-spaced.
    public static func quantity(_ value: String, _ unit: String) -> String {
        "\(number(value))\\,\(units(unit))"
    }

    // MARK: - Numbers

    /// `\num` — sign, decimal digits, and an `e`/`E` scientific exponent, with the
    /// digit grouping siunitx applies (thin space every three digits, from the
    /// decimal point outward, once a part has at least five digits).
    public static func number(_ source: String) -> String {
        let s = Array(source.vTrimmingWhitespace())
        var i = 0
        var out = ""

        // Leading sign.
        if i < s.count, s[i] == "+" || s[i] == "-" {
            out += s[i] == "-" ? "-" : ""; i += 1
        }

        // Mantissa: integer[.fraction].
        var intPart = "", fracPart = ""
        while i < s.count, s[i].isNumber { intPart.append(s[i]); i += 1 }
        if i < s.count, s[i] == "." {
            i += 1
            while i < s.count, s[i].isNumber { fracPart.append(s[i]); i += 1 }
        }
        out += groupInteger(intPart)
        if !fracPart.isEmpty { out += "." + groupFraction(fracPart) }

        // Exponent: e/E, optional sign, digits → ×10^{exp}.
        if i < s.count, s[i] == "e" || s[i] == "E" {
            i += 1
            var exp = ""
            if i < s.count, s[i] == "+" || s[i] == "-" { if s[i] == "-" { exp = "-" }; i += 1 }
            while i < s.count, s[i].isNumber { exp.append(s[i]); i += 1 }
            if !exp.isEmpty {
                let mantissa = out.isEmpty ? "" : out + " \\times "
                out = mantissa + "10^{\(exp)}"
            }
        }

        // Anything left (a stray char) passes through so nothing is silently dropped.
        while i < s.count { out.append(s[i]); i += 1 }
        return out
    }

    /// Groups an integer digit string in threes from the right with thin spaces,
    /// once it has ≥5 digits (siunitx's `group-minimum-digits` default).
    private static func groupInteger(_ digits: String) -> String {
        guard digits.count >= 5 else { return digits }
        var out = "", count = 0
        for ch in digits.reversed() {
            if count > 0, count % 3 == 0 { out = "\\," + out }
            out = String(ch) + out
            count += 1
        }
        return out
    }

    /// Groups a fractional digit string in threes from the left with thin spaces.
    private static func groupFraction(_ digits: String) -> String {
        guard digits.count >= 5 else { return digits }
        var out = "", count = 0
        for ch in digits {
            if count > 0, count % 3 == 0 { out += "\\," }
            out.append(ch)
            count += 1
        }
        return out
    }

    // MARK: - Angles

    /// `\ang{d}` or `\ang{d;m;s}` → degrees°, minutes′, seconds″.
    public static func angle(_ source: String) -> String {
        let parts = source.split(separator: ";", omittingEmptySubsequences: false)
            .map { number(String($0).vTrimmingWhitespace()) }
        var out = ""
        if parts.indices.contains(0), !parts[0].isEmpty { out += "\(parts[0])^{\\circ}" }
        if parts.indices.contains(1), !parts[1].isEmpty { out += "\(parts[1])'" }
        if parts.indices.contains(2), !parts[2].isEmpty { out += "\(parts[2])''" }
        return out
    }

    // MARK: - Units

    /// `\si` / `\unit` body → upright unit symbols. `.`/`~`/space → thin space,
    /// `/` → solidus, `^` → superscript, `\macro` expanded from the unit dictionary.
    ///
    /// Adjacent symbols (`kg`, `\kilo\gram`) accumulate into one upright `\mathrm`
    /// run, so a prefix hugs its unit and there is no spurious inter-atom gap. Special
    /// symbols (µ, Ω, Å) go in as their literal Unicode glyph so `\mathrm` keeps them
    /// upright without re-tokenizing a command.
    public static func units(_ source: String) -> String {
        let c = Array(source)
        var i = 0
        var out = ""
        var pending = ""   // upright letters/symbols awaiting a single \mathrm wrap

        func flush() {
            if !pending.isEmpty { out += "\\mathrm{\(pending)}"; pending = "" }
        }

        while i < c.count {
            let ch = c[i]
            switch ch {
            case "\\":
                // A unit macro (\kilo\gram, \per, \squared…) or a passthrough command.
                var name = ""; i += 1
                while i < c.count, c[i].isLetter { name.append(c[i]); i += 1 }
                switch name {
                case "per":       flush(); out += "/"
                case "squared":   flush(); out += "^{2}"
                case "cubed":     flush(); out += "^{3}"
                case "tothe", "raiseto", "power":
                                  flush(); out += "^" + readScript(&i, c)
                case "degree":    flush(); out += "^{\\circ}"
                case "arcminute": flush(); out += "'"
                case "arcsecond": flush(); out += "''"
                case "celsius", "degreeCelsius":
                                  flush(); out += "^{\\circ}"; pending += "C"
                case "percent":   flush(); out += "\\%"
                default:
                    if let sym = symbols[name] { pending += sym }
                    else { flush(); out += "\\\(name) " }   // unknown → real command verbatim
                }

            case "a"..."z", "A"..."Z":
                // A run of letters is one upright unit symbol (kg, mol, Hz…).
                while i < c.count, c[i].isLetter { pending.append(c[i]); i += 1 }

            case ".", "~", " ":
                // Inter-unit product → a thin space (collapse runs).
                flush(); out += "\\,"; i += 1
                while i < c.count, c[i] == "." || c[i] == "~" || c[i] == " " { i += 1 }

            case "/":
                flush(); out += "/"; i += 1

            case "^":
                flush(); i += 1
                out += "^" + readScript(&i, c)

            default:
                flush(); out.append(ch); i += 1
            }
        }
        flush()
        return out
    }

    /// Reads a `{…}` group or a single token after `^` and returns it braced.
    private static func readScript(_ i: inout Int, _ c: [Character]) -> String {
        guard i < c.count else { return "{}" }
        if c[i] == "{" {
            var depth = 0, body = ""
            while i < c.count {
                let ch = c[i]
                if ch == "{" { depth += 1; if depth == 1 { i += 1; continue } }
                else if ch == "}" { depth -= 1; if depth == 0 { i += 1; break } }
                body.append(ch); i += 1
            }
            return "{\(body)}"
        }
        // A bare exponent may be signed: ^-1, ^2.
        var body = ""
        if c[i] == "-" || c[i] == "+" { body.append(c[i]); i += 1 }
        while i < c.count, c[i].isNumber { body.append(c[i]); i += 1 }
        return body.isEmpty ? "{}" : "{\(body)}"
    }

    /// SI prefixes, base and derived units → their upright symbol. Prefix macros
    /// (`\kilo`) concatenate with the following unit macro (`\kilo\gram` → kg).
    /// Special glyphs are the literal Unicode character so a single `\mathrm` wrap
    /// keeps them upright (µ = U+00B5, Ω = U+03A9, Å = U+00C5).
    private static let symbols: [String: String] = [
        // Prefixes
        "yotta": "Y", "zetta": "Z", "exa": "E", "peta": "P", "tera": "T",
        "giga": "G", "mega": "M", "kilo": "k", "hecto": "h", "deca": "da", "deka": "da",
        "deci": "d", "centi": "c", "milli": "m", "micro": "\u{00B5}", "nano": "n",
        "pico": "p", "femto": "f", "atto": "a", "zepto": "z", "yocto": "y",
        // Base units
        "metre": "m", "meter": "m", "gram": "g", "kilogram": "kg", "second": "s",
        "ampere": "A", "kelvin": "K", "mole": "mol", "candela": "cd",
        // Derived units
        "newton": "N", "pascal": "Pa", "joule": "J", "watt": "W", "coulomb": "C",
        "volt": "V", "farad": "F", "siemens": "S", "weber": "Wb", "tesla": "T",
        "henry": "H", "hertz": "Hz", "lumen": "lm", "lux": "lx",
        "becquerel": "Bq", "gray": "Gy", "sievert": "Sv", "katal": "kat",
        "ohm": "\u{03A9}",   // Ω
        // Common non-SI accepted units
        "litre": "L", "liter": "L", "radian": "rad", "steradian": "sr",
        "electronvolt": "eV", "bar": "bar", "minute": "min", "hour": "h",
        "day": "d", "tonne": "t", "dalton": "Da", "bel": "B", "decibel": "dB",
        "byte": "B", "bit": "bit", "angstrom": "\u{00C5}",   // Å
    ]
}
