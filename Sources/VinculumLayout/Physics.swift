#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// A small `physics`-package transpiler: Dirac bra-ket notation, derivatives, and
/// the common bracket/operator macros expand to equivalent LaTeX, which the ordinary
/// parser then lays out. Like `MHChem` and `SIUnitx`, this reuses the whole engine —
/// auto-sizing `\left…\right` delimiters, fractions, upright `\mathrm` — so physics
/// needs no new node or layout code.
///
/// Each builder takes the *already-serialized* LaTeX of its brace arguments (the
/// parser reads them as nodes and hands over `node.toLaTeX()`), and returns a LaTeX
/// string to re-parse.
public enum Physics {

    // MARK: - Dirac notation

    /// `\bra{ψ}` → ⟨ψ|.
    public static func bra(_ a: String) -> String { "\\left\\langle \(a) \\right|" }

    /// `\ket{ψ}` → |ψ⟩.
    public static func ket(_ a: String) -> String { "\\left| \(a) \\right\\rangle" }

    /// `\braket{ϕ}{ψ}` → ⟨ϕ|ψ⟩; single-argument `\braket{ψ}` → ⟨ψ|ψ⟩ (physics-package
    /// convention: the one argument is used on both sides).
    public static func braket(_ a: String, _ b: String?) -> String {
        "\\left\\langle \(a) \\middle| \(b ?? a) \\right\\rangle"
    }

    /// `\ketbra{ϕ}{ψ}` → |ϕ⟩⟨ψ|; single-argument `\ketbra{ψ}` → |ψ⟩⟨ψ| (a projector).
    public static func ketbra(_ a: String, _ b: String?) -> String {
        "\\left| \(a) \\right\\rangle\\!\\left\\langle \(b ?? a) \\right|"
    }

    /// `\expval{A}` → ⟨A⟩; `\expval{A}{ψ}` → ⟨ψ|A|ψ⟩.
    public static func expval(_ a: String, _ psi: String?) -> String {
        guard let psi else { return "\\left\\langle \(a) \\right\\rangle" }
        return "\\left\\langle \(psi) \\right| \(a) \\left| \(psi) \\right\\rangle"
    }

    /// `\mel{ϕ}{A}{ψ}` → ⟨ϕ|A|ψ⟩ (a matrix element).
    public static func mel(_ a: String, _ op: String, _ b: String) -> String {
        "\\left\\langle \(a) \\right| \(op) \\left| \(b) \\right\\rangle"
    }

    // MARK: - Brackets

    /// `\abs{x}` → |x|.
    public static func abs(_ a: String) -> String { "\\left| \(a) \\right|" }

    /// `\norm{x}` → ‖x‖.
    public static func norm(_ a: String) -> String { "\\left\\| \(a) \\right\\|" }

    /// `\comm{A}{B}` → [A, B] (commutator).
    public static func comm(_ a: String, _ b: String) -> String { "\\left[ \(a), \(b) \\right]" }

    /// `\acomm{A}{B}` → {A, B} (anticommutator / Poisson bracket).
    public static func acomm(_ a: String, _ b: String) -> String { "\\left\\{ \(a), \(b) \\right\\}" }

    /// `\order{x}` → O(x) (asymptotic order).
    public static func order(_ a: String) -> String { "\\mathcal{O}\\!\\left( \(a) \\right)" }

    // MARK: - Derivatives

    /// `\dd{x}` → dx (upright d); bare `\dd` → d.
    public static func dd(_ x: String?) -> String {
        guard let x, !x.isEmpty else { return "\\mathrm{d}" }
        return "\\mathrm{d} \(x)"
    }

    /// `\dv{f}{x}` → df/dx; single-argument `\dv{x}` → the operator d/dx; the optional
    /// `[n]` raises the order: `\dv[2]{f}{x}` → d²f/dx².
    public static func dv(_ f: String, _ x: String?, order n: String?) -> String {
        let exp = orderExp(n)
        guard let x, !x.isEmpty else {
            // One argument → the operator form d/dx applied to nothing yet.
            return "\\frac{\\mathrm{d}\(exp)}{\\mathrm{d} \(f)\(exp)}"
        }
        return "\\frac{\\mathrm{d}\(exp) \(f)}{\\mathrm{d} \(x)\(exp)}"
    }

    /// `\pdv{f}{x}` → ∂f/∂x; `\pdv{f}{x}{y}` → ∂²f/∂x∂y (mixed second partial); the
    /// optional `[n]` raises a single-variable order: `\pdv[2]{f}{x}` → ∂²f/∂x².
    public static func pdv(_ f: String, _ x: String?, _ y: String?, order n: String?) -> String {
        guard let x, !x.isEmpty else {
            let exp = orderExp(n)
            return "\\frac{\\partial\(exp)}{\\partial \(f)\(exp)}"
        }
        if let y, !y.isEmpty {
            // Mixed partial: numerator order is the count of denominator variables.
            return "\\frac{\\partial^{2} \(f)}{\\partial \(x) \\partial \(y)}"
        }
        let exp = orderExp(n)
        return "\\frac{\\partial\(exp) \(f)}{\\partial \(x)\(exp)}"
    }

    /// `^{n}` when the order is present and not 1, else empty.
    private static func orderExp(_ n: String?) -> String {
        guard let n, !n.isEmpty, n != "1" else { return "" }
        return "^{\(n)}"
    }

    // MARK: - Vector operators

    /// Standalone vector-calculus operators (no arguments). `\div` is intentionally
    /// absent — it stays the core division sign ÷.
    public static func vectorOperator(_ name: String) -> String? {
        switch name {
        case "grad":       return "\\nabla"
        case "curl":       return "\\nabla \\times"
        case "laplacian":  return "\\nabla^{2}"
        case "Tr":         return "\\operatorname{Tr}"
        case "tr":         return "\\operatorname{tr}"
        case "rank":       return "\\operatorname{rank}"
        default:           return nil
        }
    }
}
