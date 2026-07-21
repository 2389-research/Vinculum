#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// LaTeX math lexer: source string → `Token` stream.
extension MathParser {

    enum Token: Equatable {
        case command(String)   // \frac, \alpha
        case character(Character)
        case groupOpen         // {
        case groupClose        // }
        case superscriptMark   // ^
        case subscriptMark     // _
        case rawText(String)   // the verbatim body of \text{…} (spaces kept)
    }

    /// Commands whose brace body is upright TEXT, not math — their interior
    /// spaces must survive the whitespace-stripping tokenizer, so the group is
    /// captured verbatim here rather than re-tokenized.
    static let rawTextCommands: Set<String> = ["text", "mathrm", "operatorname", "textrm", "ce", "addplot",
                                               "num", "ang", "si", "unit", "SI", "qty"]

    /// Commands whose *two* consecutive brace bodies are captured verbatim
    /// (siunitx `\SI{value}{unit}`, `\qty{value}{unit}`).
    static let rawText2Commands: Set<String> = ["SI", "qty"]

    /// Commands whose following balanced `[ … ]` bracket body is captured verbatim,
    /// spaces intact (qtree `\Tree [.S … ]`).
    static let bracketVerbatimCommands: Set<String> = ["Tree", "qtree"]

    struct Tokenizer {
        let input: [Character]
        init(_ s: String) { input = Array(s) }

        func tokenize() -> [Token] {
            var tokens: [Token] = []
            var i = 0
            while i < input.count {
                let ch = input[i]
                switch ch {
                case "\\":
                    var name = ""
                    var j = i + 1
                    while j < input.count, input[j].isLetter {
                        name.append(input[j])
                        j += 1
                    }
                    if name.isEmpty, j < input.count {
                        // Escaped single char: \{ \} \, \$ etc.
                        name = String(input[j])
                        j += 1
                    }
                    tokens.append(.command(name))
                    i = j
                    // Capture a text-command's brace body verbatim (spaces and
                    // nested braces preserved), so \text{if } keeps its space.
                    // Also skip an optional `*` (\operatorname*), emitting it so
                    // the parser can see the limit-taking star.
                    if MathParser.rawTextCommands.contains(name) {
                        if i < input.count, input[i] == "*" { tokens.append(.character("*")); i += 1 }
                    }
                    if MathParser.rawTextCommands.contains(name) {
                        // Read one verbatim brace body (nested braces preserved).
                        func readVerbatimBody() -> Bool {
                            guard i < input.count, input[i] == "{" else { return false }
                            var depth = 0, raw = ""
                            while i < input.count {
                                let c = input[i]
                                if c == "{" {
                                    depth += 1
                                    if depth == 1 { i += 1; continue }   // drop the outer opener
                                } else if c == "}" {
                                    depth -= 1
                                    if depth == 0 { i += 1; break }       // consume the outer closer
                                }
                                raw.append(c); i += 1
                            }
                            tokens.append(.rawText(raw))
                            return true
                        }
                        if readVerbatimBody(), MathParser.rawText2Commands.contains(name) {
                            _ = readVerbatimBody()   // second body: \SI{value}{unit}
                        }
                    }
                    // `\Tree [ … ]` (qtree): capture the balanced bracket body verbatim,
                    // spaces intact — qtree uses spaces to separate labels and leaves,
                    // which math-mode tokenizing would otherwise discard.
                    if MathParser.bracketVerbatimCommands.contains(name) {
                        while i < input.count, input[i] == " " || input[i] == "\n" || input[i] == "\t" { i += 1 }
                        if i < input.count, input[i] == "[" {
                            var depth = 0, raw = ""
                            while i < input.count {
                                let c = input[i]
                                if c == "[" { depth += 1 } else if c == "]" { depth -= 1 }
                                raw.append(c); i += 1
                                if depth == 0 { break }
                            }
                            tokens.append(.rawText(raw))
                        }
                    }
                case "{": tokens.append(.groupOpen); i += 1
                case "}": tokens.append(.groupClose); i += 1
                case "^": tokens.append(.superscriptMark); i += 1
                case "_": tokens.append(.subscriptMark); i += 1
                case " ", "\n", "\t": i += 1 // math mode ignores whitespace
                default:
                    tokens.append(.character(ch)); i += 1
                }
            }
            return tokens
        }
    }
}
