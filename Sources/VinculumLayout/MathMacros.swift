import Foundation

/// One user-defined math macro: an argument count and a body template in
/// which `#1`…`#9` are the parameter slots.
public struct MathMacro: Hashable, Sendable {
    public let argCount: Int
    public let body: String
    public init(argCount: Int, body: String) {
        self.argCount = argCount
        self.body = body
    }
}

/// A document's collected `\newcommand`/`\def` definitions, keyed by name
/// (without the leading backslash). Document-scoped: definitions from any
/// math block apply everywhere, order-independently.
public struct MathMacroTable: Hashable, Sendable {
    public var macros: [String: MathMacro]
    public init(macros: [String: MathMacro] = [:]) { self.macros = macros }
    public var isEmpty: Bool { macros.isEmpty }
    public var count: Int { macros.count }
}

/// A tiny TeX-macro processor: collects `\newcommand`/`\renewcommand`/`\def`
/// definitions from a document's math, then expands uses (with `#1`…
/// substitution and a hard recursion cap so a self-referential macro
/// degrades instead of hanging).
public enum MathMacros {

    /// Scans every math segment in `source` for definitions and returns the
    /// combined table. Later definitions of the same name win (matching
    /// \renewcommand). Only math context is scanned, so a `\newcommand`
    /// written in prose or a code fence is ignored.
    public static func collectDefinitions(from source: String) -> MathMacroTable {
        var table = MathMacroTable()
        for segment in MathScanner.scan(source) {
            let latex: String
            switch segment {
            case .inlineMath(let s), .displayMath(let s): latex = s
            case .text: continue
            }
            collect(into: &table, from: latex)
        }
        return table
    }

    /// Expands all macro uses in `latex`. Definition commands are stripped
    /// (they produce no output). Bounded by `limit` total expansions.
    public static func expand(_ latex: String, with table: MathMacroTable, limit: Int = 2000) -> String {
        guard !table.isEmpty || latex.contains("\\newcommand") || latex.contains("\\def")
                || latex.contains("\\renewcommand") else { return latex }
        let stripped = stripDefinitions(from: latex)
        guard !table.isEmpty else { return stripped }
        var budget = limit
        return expandUses(stripped, table: table, depth: 0, budget: &budget)
    }

    /// The definition commands' contribution to a block, so a
    /// definition-only block can render a chip instead of an empty box.
    public static func isDefinitionOnly(_ latex: String, table: MathMacroTable) -> Bool {
        expand(latex, with: table).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (latex.contains("\\newcommand") || latex.contains("\\def") || latex.contains("\\renewcommand"))
    }

    // MARK: - Collection

    private static func collect(into table: inout MathMacroTable, from latex: String) {
        let chars = Array(latex)
        var i = 0
        while i < chars.count {
            guard chars[i] == "\\" else { i += 1; continue }
            let (command, afterCommand) = readCommandName(chars, i + 1)
            if command == "newcommand" || command == "renewcommand" {
                if let (name, macro, next) = parseNewcommand(chars, afterCommand) {
                    table.macros[name] = macro
                    i = next
                    continue
                }
            } else if command == "def" {
                if let (name, macro, next) = parseDef(chars, afterCommand) {
                    table.macros[name] = macro
                    i = next
                    continue
                }
            }
            i = max(afterCommand, i + 1)
        }
    }

    /// `\newcommand{\name}[argc]{body}` or `\newcommand\name{body}`.
    private static func parseNewcommand(_ chars: [Character], _ start: Int) -> (String, MathMacro, Int)? {
        var i = skipSpaces(chars, start)
        // Name: either `{\name}` or bare `\name`.
        var name: String
        if i < chars.count, chars[i] == "{" {
            guard let (inner, after) = readBraceGroup(chars, i) else { return nil }
            guard inner.first == "\\" else { return nil }
            name = String(inner.dropFirst())
            i = after
        } else if i < chars.count, chars[i] == "\\" {
            let (cmd, after) = readCommandName(chars, i + 1)
            name = cmd; i = after
        } else {
            return nil
        }
        i = skipSpaces(chars, i)
        // Optional [argc].
        var argCount = 0
        if i < chars.count, chars[i] == "[" {
            var j = i + 1, digits = ""
            while j < chars.count, chars[j] != "]" { digits.append(chars[j]); j += 1 }
            if j < chars.count { j += 1 }
            argCount = Int(digits.trimmingCharacters(in: .whitespaces)) ?? 0
            i = skipSpaces(chars, j)
        }
        guard i < chars.count, chars[i] == "{",
              let (body, after) = readBraceGroup(chars, i) else { return nil }
        return (name, MathMacro(argCount: argCount, body: body), after)
    }

    /// `\def\name{body}` or `\def\name#1#2{body}`.
    private static func parseDef(_ chars: [Character], _ start: Int) -> (String, MathMacro, Int)? {
        var i = skipSpaces(chars, start)
        guard i < chars.count, chars[i] == "\\" else { return nil }
        let (name, afterName) = readCommandName(chars, i + 1)
        i = afterName
        // Count #n parameter markers before the body brace.
        var argCount = 0
        while i + 1 < chars.count, chars[i] == "#", chars[i + 1].isNumber {
            argCount = max(argCount, Int(String(chars[i + 1])) ?? 0)
            i += 2
        }
        guard i < chars.count, chars[i] == "{",
              let (body, after) = readBraceGroup(chars, i) else { return nil }
        return (name, MathMacro(argCount: argCount, body: body), after)
    }

    // MARK: - Expansion

    private static func stripDefinitions(from latex: String) -> String {
        let chars = Array(latex)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" {
                let (command, afterCommand) = readCommandName(chars, i + 1)
                if command == "newcommand" || command == "renewcommand" {
                    if let (_, _, next) = parseNewcommand(chars, afterCommand) { i = next; continue }
                } else if command == "def" {
                    if let (_, _, next) = parseDef(chars, afterCommand) { i = next; continue }
                }
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    private static func expandUses(_ latex: String, table: MathMacroTable, depth: Int, budget: inout Int) -> String {
        guard depth < 40, budget > 0 else { return latex }
        let chars = Array(latex)
        var out = ""
        var i = 0
        var expandedAny = false
        while i < chars.count {
            guard chars[i] == "\\" else { out.append(chars[i]); i += 1; continue }
            let (name, afterName) = readCommandName(chars, i + 1)
            guard let macro = table.macros[name], !name.isEmpty else {
                out.append("\\"); out.append(contentsOf: name)
                i = afterName == i + 1 ? i + 1 : afterName
                continue
            }
            // Gather argCount brace groups.
            var j = skipSpaces(chars, afterName)
            var args: [String] = []
            var ok = true
            for _ in 0..<macro.argCount {
                guard j < chars.count, chars[j] == "{",
                      let (arg, after) = readBraceGroup(chars, j) else { ok = false; break }
                args.append(arg); j = after
            }
            guard ok else {
                // Not enough arguments: leave the command literal (it will
                // degrade to a source card, which is honest).
                out.append("\\"); out.append(contentsOf: name)
                i = afterName
                continue
            }
            budget -= 1
            out.append(substitute(macro.body, args: args))
            expandedAny = true
            i = j
        }
        // Re-expand for nested macro uses until a fixed point (bounded).
        return expandedAny ? expandUses(out, table: table, depth: depth + 1, budget: &budget) : out
    }

    private static func substitute(_ body: String, args: [String]) -> String {
        guard !args.isEmpty else { return body }
        let chars = Array(body)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i + 1 < chars.count, chars[i + 1].isNumber,
               let n = Int(String(chars[i + 1])), n >= 1, n <= args.count {
                out.append(args[n - 1]); i += 2
            } else {
                out.append(chars[i]); i += 1
            }
        }
        return out
    }

    // MARK: - Low-level scanning

    private static func readCommandName(_ chars: [Character], _ start: Int) -> (String, Int) {
        var i = start, name = ""
        while i < chars.count, chars[i].isLetter { name.append(chars[i]); i += 1 }
        return (name, i)
    }

    private static func skipSpaces(_ chars: [Character], _ start: Int) -> Int {
        var i = start
        while i < chars.count, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        return i
    }

    /// Reads a balanced `{…}` group starting at `chars[start] == "{"`,
    /// returning the inner text and the index just past the closing brace.
    private static func readBraceGroup(_ chars: [Character], _ start: Int) -> (String, Int)? {
        guard start < chars.count, chars[start] == "{" else { return nil }
        var depth = 0, i = start, inner = ""
        while i < chars.count {
            let c = chars[i]
            if c == "{" {
                if depth > 0 { inner.append(c) }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return (inner, i + 1) }
                inner.append(c)
            } else {
                inner.append(c)
            }
            i += 1
        }
        return nil // unbalanced
    }
}
