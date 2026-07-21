#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A tiny arithmetic expression evaluator for function plots — parses a formula in
/// one variable (`x`) once, then evaluates it at many sample points. Recursive
/// descent over `+ - * / ^`, unary minus, parentheses, the named functions below,
/// and the constants `pi`/`e`. Deterministic (pure `Double` math), so a plotted
/// curve is identical on every platform.
///
/// Not a general CAS — just enough to plot `x^2`, `sin(x)`, `exp(-x^2)`,
/// `1/(1+x^2)`, and the like.
public struct MathExpression {

    private let root: Node

    /// Parses `source`. Returns nil if it doesn't parse (so a caller can skip a
    /// malformed `\addplot` rather than crash).
    public init?(_ source: String) {
        var p = Parser(Array(source))
        guard let node = p.parseExpression(), p.atEnd() else { return nil }
        root = node
    }

    /// Evaluates at `x` (radians for the trig functions). May return .nan/.infinity
    /// (e.g. `1/x` at 0 or `ln(x)` for x≤0); callers drop non-finite samples.
    public func callAsFunction(_ x: Double) -> Double { root.eval(x) }

    // MARK: - AST

    private indirect enum Node {
        case constant(Double)
        case variable
        case unary(minus: Node)
        case binary(BinOp, Node, Node)
        case call(String, Node)

        func eval(_ x: Double) -> Double {
            switch self {
            case .constant(let v): return v
            case .variable: return x
            case .unary(let n): return -n.eval(x)
            case .binary(let op, let a, let b):
                let l = a.eval(x), r = b.eval(x)
                switch op {
                case .add: return l + r
                case .sub: return l - r
                case .mul: return l * r
                case .div: return l / r
                case .pow: return Foundation.pow(l, r)
                }
            case .call(let f, let arg):
                let v = arg.eval(x)
                switch f {
                case "sin": return Foundation.sin(v)
                case "cos": return Foundation.cos(v)
                case "tan": return Foundation.tan(v)
                case "exp": return Foundation.exp(v)
                case "ln", "log": return Foundation.log(v)
                case "log10": return Foundation.log10(v)
                case "sqrt": return Foundation.sqrt(v)
                case "abs": return Swift.abs(v)
                case "sinh": return Foundation.sinh(v)
                case "cosh": return Foundation.cosh(v)
                case "tanh": return Foundation.tanh(v)
                case "atan": return Foundation.atan(v)
                case "floor": return Foundation.floor(v)
                case "ceil": return Foundation.ceil(v)
                default: return .nan
                }
            }
        }
    }

    private enum BinOp { case add, sub, mul, div, pow }

    // MARK: - Recursive-descent parser

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }

        mutating func atEnd() -> Bool { skipSpaces(); return i >= c.count }
        mutating func skipSpaces() { while i < c.count, c[i] == " " { i += 1 } }
        mutating func peek() -> Character? { skipSpaces(); return i < c.count ? c[i] : nil }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() -> Node? {
            guard var node = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                i += 1
                guard let rhs = parseTerm() else { return nil }
                node = .binary(op == "+" ? .add : .sub, node, rhs)
            }
            return node
        }

        // term := unary (('*' | '/') unary)*
        mutating func parseTerm() -> Node? {
            guard var node = parseUnary() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                i += 1
                guard let rhs = parseUnary() else { return nil }
                node = .binary(op == "*" ? .mul : .div, node, rhs)
            }
            return node
        }

        // unary := '-' unary | power   — so `-x^2` is `-(x^2)`, standard precedence.
        mutating func parseUnary() -> Node? {
            if let op = peek(), op == "-" { i += 1; return parseUnary().map { .unary(minus: $0) } }
            if let op = peek(), op == "+" { i += 1; return parseUnary() }
            return parsePower()
        }

        // power := atom ('^' unary)?   (right-associative; the exponent may be signed, e.g. 2^-x)
        mutating func parsePower() -> Node? {
            guard let base = parseAtom() else { return nil }
            if let op = peek(), op == "^" {
                i += 1
                guard let exp = parseUnary() else { return nil }
                return .binary(.pow, base, exp)
            }
            return base
        }

        // atom := number | '(' expression ')' | ident ['(' expression ')']
        mutating func parseAtom() -> Node? {
            guard let ch = peek() else { return nil }
            if ch == "(" {
                i += 1
                guard let e = parseExpression(), peek() == ")" else { return nil }
                i += 1
                return e
            }
            if ch.isNumber || ch == "." { return parseNumber() }
            if ch.isLetter {
                let name = parseIdentifier()
                if peek() == "(" {
                    i += 1
                    guard let arg = parseExpression(), peek() == ")" else { return nil }
                    i += 1
                    return .call(name, arg)
                }
                switch name {
                case "x": return .variable
                case "pi": return .constant(Double.pi)
                case "e": return .constant(M_E)
                default: return .variable   // unknown bare name → treat as x, don't fail the plot
                }
            }
            return nil
        }

        mutating func parseNumber() -> Node? {
            skipSpaces()
            var s = ""
            while i < c.count, c[i].isNumber || c[i] == "." { s.append(c[i]); i += 1 }
            // Exponent form 1e-3.
            if i < c.count, c[i] == "e" || c[i] == "E",
               i + 1 < c.count, c[i + 1].isNumber || c[i + 1] == "-" || c[i + 1] == "+" {
                s.append("e"); i += 1
                if c[i] == "-" || c[i] == "+" { s.append(c[i]); i += 1 }
                while i < c.count, c[i].isNumber { s.append(c[i]); i += 1 }
            }
            return Double(s).map { .constant($0) }
        }

        mutating func parseIdentifier() -> String {
            skipSpaces()
            var s = ""
            while i < c.count, c[i].isLetter || c[i].isNumber { s.append(c[i]); i += 1 }
            return s
        }
    }
}
