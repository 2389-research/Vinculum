import Foundation

/// A diagnosable parse problem, locatable in the source — the
/// squiggle-underline substrate for live-editor hosts.
public struct MathParseIssue: Sendable, Equatable {
    /// The offending source snippet, e.g. `"\badcmd"`.
    public let source: String
    /// Human-readable description.
    public let message: String
    /// Where `source` sits in the diagnosed string — nil when the snippet
    /// can't be located (e.g. it was produced by macro expansion). A nil
    /// range is honest; a wrong range never is.
    public let range: Range<String.Index>?
}

/// Support classification: native render vs. named source-card fallback.
extension MathParser {

    /// Diagnoses `latex`, returning one issue per unsupported token in
    /// source order, each with its location. Pass `parsing:` when the text
    /// actually parsed differs from what the user typed (macro expansion);
    /// ranges then refer to `latex` and fall back to nil when unlocatable.
    public static func diagnostics(for latex: String, parsing: String? = nil) -> [MathParseIssue] {
        let node = parse(parsing ?? latex)
        var snippets: [String] = []
        walkUnsupported(node) { snippets.append($0) }

        var issues: [MathParseIssue] = []
        var searchFrom = latex.startIndex
        for raw in snippets {
            let isCommand = raw.hasPrefix("\\") && raw.dropFirst().allSatisfy(\.isLetter)
                && raw.count > 1
            let message = isCommand
                ? "unsupported command \(raw)"
                : "unsupported input “\(raw)”"
            // Locate this occurrence: search forward from the previous hit so
            // duplicates map to successive positions; fall back to a
            // whole-string search, then to nil.
            let range = latex.range(of: raw, range: searchFrom..<latex.endIndex)
                ?? latex.range(of: raw)
            if let range { searchFrom = range.upperBound }
            issues.append(MathParseIssue(source: raw, message: message, range: range))
        }
        return issues
    }

    /// Ordered, non-deduped walk of `.unsupported` leaves, via the
    /// canonical `MathNode.children` traversal.
    private static func walkUnsupported(_ node: MathNode, _ emit: (String) -> Void) {
        if case .unsupported(let raw) = node { emit(raw) }
        for child in node.children { walkUnsupported(child, emit) }
    }

    public static func isFullySupported(_ node: MathNode) -> Bool {
        if case .unsupported = node { return false }
        return node.children.allSatisfy(isFullySupported)
    }

    /// The distinct commands that degraded this expression to source
    /// fallback, in first-seen order (deduped, capped). `isFullySupported`
    /// answers "did it degrade"; this answers "on WHAT" so the fallback
    /// card can name the culprit instead of a generic apology.
    public static func unsupportedCommands(in node: MathNode, limit: Int = 4) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        walkUnsupported(node) { raw in
            // The payload is the raw token ("\\foo" or a stray char). Only
            // surface real letter-commands (`\word`) — structural noise like
            // a stray `\\` row separator isn't a nameable culprit and would
            // just confuse the caption.
            let name = raw.hasPrefix("\\") ? raw : "\\" + raw
            let body = name.dropFirst()
            guard !body.isEmpty, body.allSatisfy(\.isLetter) else { return }
            if seen.insert(name).inserted { ordered.append(name) }
        }
        return Array(ordered.prefix(limit))
    }
}
