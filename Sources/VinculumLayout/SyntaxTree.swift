#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// Parses a qtree bracket expression (`[.S [.NP … ] [.VP … ] ]`) into a
/// `SyntaxTreeNode`. The bracket body arrives verbatim from the tokenizer (spaces
/// intact), so this scanner can use whitespace to separate labels and leaves the way
/// qtree does. Every label/leaf substring is handed to `MathParser.parse`, so tree
/// nodes may contain arbitrary math.
enum SyntaxTree {

    static func parse(_ raw: String) -> SyntaxTreeNode? {
        var chars = Array(raw)
        var i = 0
        return parseNode(&chars, &i)
    }

    private static func parseNode(_ c: inout [Character], _ i: inout Int) -> SyntaxTreeNode? {
        skipSpace(c, &i)
        guard i < c.count else { return nil }

        if c[i] == "[" {
            i += 1
            skipSpace(c, &i)
            if i < c.count, c[i] == "." { i += 1 }   // qtree marks the root label with a leading dot
            let labelText = readToken(&c, &i)
            var children: [SyntaxTreeNode] = []
            while true {
                skipSpace(c, &i)
                guard i < c.count, c[i] != "]" else { break }
                if c[i] == "[" {
                    guard let child = parseNode(&c, &i) else { break }
                    children.append(child)
                } else {
                    let leaf = readToken(&c, &i)
                    if leaf.isEmpty { break }   // guard against no progress
                    children.append(SyntaxTreeNode(label: MathParser.parse(leaf)))
                }
            }
            if i < c.count, c[i] == "]" { i += 1 }
            let label = labelText.isEmpty ? MathNode.row([]) : MathParser.parse(labelText)
            return SyntaxTreeNode(label: label, children: children)
        }

        // A bare leaf (no brackets).
        let leaf = readToken(&c, &i)
        return leaf.isEmpty ? nil : SyntaxTreeNode(label: MathParser.parse(leaf))
    }

    /// A maximal run up to a top-level space or bracket. A `{ … }` group is taken
    /// whole (braces and inner spaces preserved) so multi-word labels/leaves survive.
    private static func readToken(_ c: inout [Character], _ i: inout Int) -> String {
        var s = ""
        while i < c.count {
            let ch = c[i]
            if ch == " " || ch == "\n" || ch == "\t" || ch == "[" || ch == "]" { break }
            if ch == "{" {
                var depth = 0
                while i < c.count {
                    let d = c[i]; s.append(d); i += 1
                    if d == "{" { depth += 1 } else if d == "}" { depth -= 1; if depth == 0 { break } }
                }
            } else {
                s.append(ch); i += 1
            }
        }
        return s
    }

    private static func skipSpace(_ c: [Character], _ i: inout Int) {
        while i < c.count, c[i] == " " || c[i] == "\n" || c[i] == "\t" { i += 1 }
    }
}
