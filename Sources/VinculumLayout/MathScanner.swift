import Foundation

/// Splits a run of paragraph source text into math and non-math segments.
///
/// Math is scanned against the *source slice* of a paragraph rather than the
/// parsed inline tree, because cmark has no math extension and will happily
/// mangle `$a_b + c_d$` into emphasis nodes. Operating on the raw slice
/// sidesteps that entirely; the non-math remainder is re-parsed as inline
/// markdown by the converter.
///
/// The slice handed in must still contain the whole span. Display math may
/// cross physical lines, and markdown BLOCK parsing splits such spans before
/// any inline pass runs — to cmark, a lone `=` under the opening line is a
/// setext-heading underline (issue #1). Scan the raw source, or slices cut
/// only at blank lines, never cmark's block boundaries.
///
/// Rules (the KaTeX/Pandoc common subset):
/// - `$$…$$` is display math and may span newlines.
/// - `\[…\]` is display math and, like `$$…$$`, may span newlines;
///   `\(…\)` is inline math.
/// - `$…$` is inline math; the opener must not be followed by whitespace,
///   the closer must not be preceded by whitespace nor followed by a digit,
///   and the span must not cross a blank line.
/// - `\$` is an escaped dollar sign, never a delimiter.
public enum MathSegment: Equatable {
    case text(String)
    case inlineMath(String)
    case displayMath(String)
}

public enum MathScanner {
    public static func containsMathDelimiter(_ text: String) -> Bool {
        var previous: Character?
        for ch in text {
            if ch == "$" && previous != "\\" { return true }
            previous = ch
        }
        return text.contains("\\[") || text.contains("\\(")
    }

    public static func scan(_ text: String) -> [MathSegment] {
        var segments: [MathSegment] = []
        let chars = Array(text)
        var plain = ""
        var i = 0

        func flushPlain() {
            if !plain.isEmpty {
                segments.append(.text(plain))
                plain = ""
            }
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "\\", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "$" {                      // escaped dollar, never a delimiter
                    plain.append("\\$")
                    i += 2
                    continue
                }
                // LaTeX display `\[ … \]` and inline `\( … \)` delimiters.
                if next == "[", let close = findClosingBracket(in: chars, from: i + 2, closer: "]") {
                    let latex = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        flushPlain()
                        segments.append(.displayMath(latex))
                        i = close + 2
                        continue
                    }
                }
                if next == "(", let close = findClosingBracket(in: chars, from: i + 2, closer: ")") {
                    let latex = String(chars[(i + 2)..<close])
                    flushPlain()
                    segments.append(.inlineMath(latex))
                    i = close + 2
                    continue
                }
            }
            guard ch == "$" else {
                plain.append(ch)
                i += 1
                continue
            }

            // Display math: $$ … $$
            if i + 1 < chars.count, chars[i + 1] == "$" {
                if let close = findClosingDouble(in: chars, from: i + 2) {
                    let latex = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        flushPlain()
                        segments.append(.displayMath(latex))
                        i = close + 2
                        continue
                    }
                }
                plain.append("$$")
                i += 2
                continue
            }

            // Inline math: $ … $
            if let close = findClosingSingle(in: chars, from: i + 1) {
                let latex = String(chars[(i + 1)..<close])
                flushPlain()
                segments.append(.inlineMath(latex))
                i = close + 1
                continue
            }

            plain.append(ch)
            i += 1
        }
        flushPlain()
        return segments
    }

    /// Finds the index of the `\` in a `\]` or `\)` closer, or nil. May span
    /// newlines (display math) and ignores an escaped closer inside the body.
    private static func findClosingBracket(in chars: [Character], from start: Int, closer: Character) -> Int? {
        var i = start
        while i + 1 < chars.count {
            if chars[i] == "\\" {
                if chars[i + 1] == closer { return i }
                i += 2      // some other escape (\\, \{, …) — skip both
                continue
            }
            i += 1
        }
        return nil
    }

    /// Finds the index of the `$$` closer, or nil.
    private static func findClosingDouble(in chars: [Character], from start: Int) -> Int? {
        var i = start
        while i + 1 < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "$" && chars[i + 1] == "$" { return i }
            i += 1
        }
        return nil
    }

    /// Finds the index of a valid `$` closer for inline math, or nil.
    private static func findClosingSingle(in chars: [Character], from start: Int) -> Int? {
        // Opener must not be immediately followed by whitespace or another `$`.
        guard start < chars.count, !chars[start].isWhitespace, chars[start] != "$" else { return nil }
        var i = start
        var lastNonSpace = -1
        var newlineRun = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" {
                // The escaped character counts as ink — without this, math
                // ENDING in a command (`$x \in \R$`) never closes, because
                // the `$` looks whitespace-preceded.
                if i + 1 < chars.count, !chars[i + 1].isWhitespace { lastNonSpace = i + 1 }
                i += 2
                continue
            }
            if ch == "\n" {
                newlineRun += 1
                // A blank line terminates an inline `$…$` scan (no closer found).
                if newlineRun >= 2 { break }
            } else if !ch.isWhitespace {
                newlineRun = 0
            }
            if ch == "$" {
                // Closer must not be preceded by whitespace nor followed by a digit;
                // an invalid candidate is skipped and scanning continues.
                let precededBySpace = lastNonSpace != i - 1
                let followedByDigit = i + 1 < chars.count && chars[i + 1].isNumber
                if !precededBySpace && !followedByDigit && i > start {
                    return i
                }
                i += 1
                continue
            }
            if !ch.isWhitespace { lastNonSpace = i }
            i += 1
        }
        return nil
    }
}
