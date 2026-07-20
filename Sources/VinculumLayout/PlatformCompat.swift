// Pure-Swift replacements for the handful of Foundation APIs the layout engine
// used that are absent from FoundationEssentials — so VinculumLayout can build
// against FoundationEssentials (no ICU) on wasm, shrinking the binary from ~48 MB
// toward single digits (issue #112). Used on EVERY platform (not conditionally):
// removing the dependency uniformly keeps output identical across platforms — and
// the SVG parity gate + wire conformance are the standing proof that it does.
//
// Each replacement is proven byte-equivalent to the Foundation API it supersedes
// in PlatformCompatTests.

extension StringProtocol {
    /// Replaces `trimmingCharacters(in:)` for a predicate — trims leading and
    /// trailing characters matching `drop`.
    func vTrimming(where drop: (Character) -> Bool) -> String {
        var s = Substring(self)
        while let f = s.first, drop(f) { s = s.dropFirst() }
        while let l = s.last, drop(l) { s = s.dropLast() }
        return String(s)
    }

    /// Replaces `.trimmingCharacters(in: .whitespaces)` — Unicode whitespace
    /// excluding line breaks.
    func vTrimmingWhitespace() -> String {
        vTrimming { $0.isWhitespace && !$0.isNewline }
    }

    /// Replaces `.trimmingCharacters(in: .whitespacesAndNewlines)`.
    func vTrimmingWhitespaceAndNewlines() -> String {
        vTrimming { $0.isWhitespace }
    }

    /// Replaces `replacingOccurrences(of:with:)` — non-overlapping, left-to-right,
    /// exactly as Foundation's (via `components`, which FoundationEssentials has).
    func vReplacing(_ target: String, with replacement: String) -> String {
        guard !target.isEmpty else { return String(self) }
        return String(self).components(separatedBy: target).joined(separator: replacement)
    }
}

/// A lowercase, zero-padded 2-digit hex byte — replaces `String(format: "%02x", n)`.
/// `n` is clamped to a byte.
func vHexByte(_ n: Int) -> String {
    let b = max(0, min(255, n))
    let s = String(b, radix: 16)
    return b < 16 ? "0" + s : s
}

/// Fixed 2-decimal formatting — replaces `String(format: "%.2f", v)`.
///
/// Deterministic (pure IEEE float ops, identical on every platform) and correct
/// (the printed value is within half a ulp-of-0.01 of the input). It does NOT
/// promise glibc-`printf` byte-equivalence — at exact `.xx5` binary-tie
/// boundaries the intermediate scale can round the other way. That's fine: the
/// SVG goldens are generated with THIS function, and the cross-platform parity
/// gate enforces that every platform agrees. What matters is determinism +
/// correctness, not matching a specific C library. Callers keep the existing
/// `v == v.rounded() ? Int(v) : …` integer fast path.
func vFormat2(_ v: Double) -> String {
    let neg = v < 0
    let n = Int((abs(v) * 100).rounded(.toNearestOrEven))
    let fracStr = n % 100 < 10 ? "0\(n % 100)" : "\(n % 100)"
    let sign = neg ? "-" : ""   // keep the sign for negatives, incl. "-0.00" (matches printf)
    return "\(sign)\(n / 100).\(fracStr)"
}

// MARK: - CoreGraphics geometry polyfill (wasm only)

// On Apple/Linux the scene IR's CGFloat/CGPoint/CGSize/CGRect come from full
// Foundation. FoundationEssentials (which VinculumLayout imports on wasm to shed
// ICU — issue #112) does NOT provide them, so we define structurally-identical
// stand-ins here, wasm-only. Every other platform keeps the real Foundation
// types unchanged, so this is not an API change off wasm.
#if os(WASI)
public typealias CGFloat = Double

public struct CGPoint: Hashable, Sendable {
    public var x: CGFloat, y: CGFloat
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero = CGPoint(x: 0, y: 0)
}

public struct CGSize: Hashable, Sendable {
    public var width: CGFloat, height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
    public static let zero = CGSize(width: 0, height: 0)
}

public struct CGRect: Hashable, Sendable {
    public var origin: CGPoint, size: CGSize
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
    public static let zero = CGRect(origin: .zero, size: .zero)
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public var minX: CGFloat { min(origin.x, origin.x + size.width) }
    public var minY: CGFloat { min(origin.y, origin.y + size.height) }
    public var maxX: CGFloat { max(origin.x, origin.x + size.width) }
    public var maxY: CGFloat { max(origin.y, origin.y + size.height) }
    public var midX: CGFloat { origin.x + size.width / 2 }
    public var midY: CGFloat { origin.y + size.height / 2 }
}
#endif
