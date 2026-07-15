import Foundation

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
    static let rawTextCommands: Set<String> = ["text", "mathrm", "operatorname", "textrm"]

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
                    if MathParser.rawTextCommands.contains(name), i < input.count, input[i] == "{" {
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
