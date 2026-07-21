#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// Document-scoped equation numbering and cross-references (`\label`, `\eqref`,
/// `\ref`, `\tag`). Platform-free string processing over the document's display-math
/// segments — the same document scope as `MathMacros`. The render layer (`MathText`)
/// applies the result: injecting the number as a `\tag` and resolving references.
///
/// A display equation's number is: its `\tag{…}` / `\tag*{…}` value if present; else
/// nothing if it carries `\notag` / `\nonumber`; else — only when `autoNumber` is on —
/// the next sequential integer. References always resolve against whatever numbers are
/// known, so manual `\tag` + `\label` works without opting into auto-numbering.
public enum MathNumbering {

    public struct Numbers: Sendable, Equatable {
        /// `\label` key → the number string of the equation it sits in.
        public var labels: [String: String] = [:]
        /// Display-segment ordinal (0-based, over display-math segments only) → the
        /// number to inject as a `\tag`, for equations that didn't already tag themselves.
        public var autoTags: [Int: String] = [:]
    }

    /// Numbers the display equations of `source`. `autoNumber` assigns sequential
    /// numbers to equations that neither `\tag` nor `\notag`; `start` is the first.
    public static func number(_ source: String, autoNumber: Bool, start: Int = 1) -> Numbers {
        var result = Numbers()
        var counter = start
        var displayIndex = 0
        for segment in MathScanner.scan(source) {
            guard case .displayMath(let latex) = segment else { continue }
            let idx = displayIndex
            displayIndex += 1

            let number: String?
            var manual = false
            if let tag = bracedArg(of: "tag", in: latex) ?? bracedArg(of: "tag*", in: latex) {
                number = tag; manual = true                 // explicit \tag wins
            } else if latex.contains("\\notag") || latex.contains("\\nonumber") {
                number = nil                                 // suppressed
            } else if autoNumber {
                number = "\(counter)"; counter += 1          // auto
            } else {
                number = nil
            }

            if let number {
                if !manual { result.autoTags[idx] = number } // inject only if not already tagged
                // Only NUMBERED equations get a label entry, so a reference to an
                // unnumbered one resolves to "(?)" (undefined) rather than "()".
                for key in bracedArgs(of: "label", in: latex) { result.labels[key] = number }
            }
        }
        return result
    }

    /// Replaces `\eqref{key}` → `(N)` and `\ref{key}` → `N` using the label map.
    /// An unknown key becomes `(?)` / `?` so a dangling reference is visible, not silent.
    public static func resolveReferences(_ s: String, labels: [String: String]) -> String {
        guard s.contains("\\eqref") || s.contains("\\ref") else { return s }
        var out = replaceCommand(s, name: "eqref") { key in "(\(labels[key] ?? "?"))" }
        out = replaceCommand(out, name: "ref") { key in labels[key] ?? "?" }
        return out
    }

    /// Removes the numbering directives that are not math — `\label{…}`, `\notag`,
    /// `\nonumber` — so they never reach the parser (which would flag them
    /// unsupported and drop the whole equation to a fallback). `\tag{…}` is left
    /// in place: the parser handles it (places the number).
    public static func stripDirectives(_ latex: String) -> String {
        guard latex.contains("\\label") || latex.contains("\\notag") || latex.contains("\\nonumber") else {
            return latex
        }
        var s = replaceCommand(latex, name: "label") { _ in "" }
        s = removeBareCommand(s, name: "notag")
        s = removeBareCommand(s, name: "nonumber")
        return s
    }

    /// Removes every occurrence of a bare (argument-less) `\name`, respecting the
    /// command boundary so `\notag` doesn't nibble `\notagfoo`.
    private static func removeBareCommand(_ s: String, name: String) -> String {
        let chars = Array(s)
        let cmd = Array("\\" + name)
        var out = ""
        var i = 0
        while i < chars.count {
            if matchesCommand(chars, at: i, cmd) { i += cmd.count }
            else { out.append(chars[i]); i += 1 }
        }
        return out
    }

    // MARK: - String scanning

    /// The first `{…}` argument of `\name`, or nil. Matches only at a command
    /// boundary (so `\tag` doesn't fire inside `\tagged`).
    static func bracedArg(of name: String, in s: String) -> String? {
        bracedArgs(of: name, in: s).first
    }

    /// Every `{…}` argument of `\name` in `s`.
    static func bracedArgs(of name: String, in s: String) -> [String] {
        let chars = Array(s)
        let cmd = Array("\\" + name)
        var out: [String] = []
        var i = 0
        while i < chars.count {
            if matchesCommand(chars, at: i, cmd), i + cmd.count < chars.count, chars[i + cmd.count] == "{",
               let (arg, next) = readBrace(chars, i + cmd.count) {
                out.append(arg); i = next
            } else {
                i += 1
            }
        }
        return out
    }

    /// Replaces every `\name{key}` with `transform(key)`.
    static func replaceCommand(_ s: String, name: String, transform: (String) -> String) -> String {
        let chars = Array(s)
        let cmd = Array("\\" + name)
        var out = ""
        var i = 0
        while i < chars.count {
            if matchesCommand(chars, at: i, cmd), i + cmd.count < chars.count, chars[i + cmd.count] == "{",
               let (arg, next) = readBrace(chars, i + cmd.count) {
                out += transform(arg); i = next
            } else {
                out.append(chars[i]); i += 1
            }
        }
        return out
    }

    /// `\name` matches at `i` only if the following char is a command terminator
    /// (not a letter) — so `\ref` doesn't match the start of `\reflectbox`. The `*`
    /// in `tag*` is matched literally by including it in `cmd`.
    private static func matchesCommand(_ chars: [Character], at i: Int, _ cmd: [Character]) -> Bool {
        guard i + cmd.count <= chars.count else { return false }
        for k in 0..<cmd.count where chars[i + k] != cmd[k] { return false }
        // If the command name ends in a letter, the next char must not be a letter.
        if let last = cmd.last, last.isLetter, i + cmd.count < chars.count, chars[i + cmd.count].isLetter {
            return false
        }
        return true
    }

    /// Reads a single-level `{ … }` starting at `open` (index of `{`), returning the
    /// inner text and the index just past the closing `}`.
    private static func readBrace(_ chars: [Character], _ open: Int) -> (String, Int)? {
        guard open < chars.count, chars[open] == "{" else { return nil }
        var depth = 0, i = open, body = ""
        while i < chars.count {
            let c = chars[i]
            if c == "{" { depth += 1; if depth == 1 { i += 1; continue } }
            else if c == "}" { depth -= 1; if depth == 0 { return (body, i + 1) } }
            body.append(c); i += 1
        }
        return nil
    }
}
