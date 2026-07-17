#if canImport(AppKit) || canImport(UIKit)
import XCTest
import Foundation
import CoreGraphics
@testable import VinculumRender
@testable import VinculumLayout

/// Both process-wide caches on the Apple path are hand-synchronized rather than
/// actor-isolated, and their comments make specific multi-thread CLAIMS:
///
/// - `CoreTextMeasurer` — a plain Dictionary under an NSLock, computing misses
///   OUTSIDE the lock: "cross-thread races only ever recompute the same value."
/// - `MathImageRenderer` — an NSCache of Entry objects: "the image is shared
///   across threads, so all mutation happens in buildEntry, pre-publication."
///
/// Nothing drove either concurrently, so those claims were untested (#46). These
/// are the public measure/render entry points — reachable from any thread, and
/// documented as the API for hosts that pre-render off-main.
///
/// A pass here is EVIDENCE, NOT PROOF. This is a stress test: it is only as good
/// as the contention it happens to create, and it detects a race only if that
/// race actually corrupts an observable value on this run.
///
/// The issue asked for ThreadSanitizer, which would upgrade this from "didn't
/// misbehave" to "no data race". TSan is NOT available for this package, and it
/// is worth recording why so nobody re-litigates it:
///
///  - `swift test --sanitize=thread` aborts before running a test. SwiftPM
///    launches Apple-signed `swiftpm-xctest-helper`, and dyld refuses to insert
///    the TSan dylib into a platform binary: "Sanitizer load violates platform
///    policy".
///  - `xcodebuild test -enableThreadSanitizer YES` (macOS) crashes the runner
///    the same way — plain `xctest` is also a platform binary.
///  - `xcodebuild test -enableThreadSanitizer YES` on an iOS SIMULATOR *runs*
///    and reports success — but does not instrument anything. A deliberate
///    unsynchronized `value += 1` across 200 concurrent threads was NOT flagged,
///    `libclang_rt.tsan` never loads, and the "sanitized" run is FASTER than the
///    unsanitized one (1.128s vs 1.751s). The flag does not reach SwiftPM-built
///    targets, so a TSan CI job on this path would be green forever, whatever
///    the code did. That is worse than no job at all.
final class RenderCacheConcurrencyTests: XCTestCase {

    // MARK: - MathImageRenderer

    /// Overlapping keys: maximum contention on the SAME cache slots, mixing
    /// positive entries with the negative (nil-image) path that unsupported
    /// LaTeX takes — both are published to the same NSCache.
    func testConcurrentRenderOfOverlappingKeysIsConsistent() {
        let supported = [#"x^2"#, #"\frac{a}{b}"#, #"\sqrt{2}"#]
        let unsupported = [#"\notacommand{x}"#, #"\alsonotreal{y}"#]
        let all = supported + unsupported

        // Reference values, computed single-threaded first.
        var expected: [String: (descent: CGFloat, speech: String)?] = [:]
        for latex in all {
            let r = MathImageRenderer.rendered(latex: latex, display: true,
                                               mathTheme: .light, baseSize: 17)
            expected[latex] = r.map { (descent: $0.descent, speech: $0.spokenDescription) }
        }
        XCTAssertNotNil(expected[supported[0]] ?? nil, "the supported fixtures must render")
        XCTAssertNil(expected[unsupported[0]] ?? nil, "the unsupported fixtures must be negative entries")

        let mismatches = Mismatches()
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            let latex = all[i % all.count]
            let r = MathImageRenderer.rendered(latex: latex, display: true,
                                               mathTheme: .light, baseSize: 17)
            let want = expected[latex] ?? nil
            switch (r, want) {
            case (nil, nil):
                break
            case let (r?, want?):
                if r.descent != want.descent || r.spokenDescription != want.speech {
                    mismatches.add("\(latex): descent \(r.descent) vs \(want.descent), "
                                   + "speech \(r.spokenDescription) vs \(want.speech)")
                }
            default:
                mismatches.add("\(latex): nil-ness flipped under contention "
                               + "(got \(r == nil ? "nil" : "a render"))")
            }
        }
        XCTAssertEqual(mismatches.all, [], "a cached entry changed under concurrent access")
    }

    /// Distinct keys: concurrent INSERTS, and enough of them to push past
    /// countLimit (512) so eviction runs while other threads are reading.
    func testConcurrentRenderOfDistinctKeysEvictsWithoutCorruption() {
        let mismatches = Mismatches()
        DispatchQueue.concurrentPerform(iterations: 600) { i in
            let latex = "z_{\(i)} + \(i)"
            guard let r = MathImageRenderer.rendered(latex: latex, display: false,
                                                     mathTheme: .light, baseSize: 13) else {
                mismatches.add("\(latex) failed to render"); return
            }
            // An evicted entry must be REBUILT identically, never returned torn.
            guard let again = MathImageRenderer.rendered(latex: latex, display: false,
                                                         mathTheme: .light, baseSize: 13) else {
                mismatches.add("\(latex) failed on re-render"); return
            }
            if r.descent != again.descent || r.spokenDescription != again.spokenDescription {
                mismatches.add("\(latex): re-render disagreed with the first")
            }
        }
        XCTAssertEqual(mismatches.all, [], "eviction under contention corrupted entries")
    }

    // MARK: - CoreTextMeasurer

    /// The lock protects the dictionary, but misses are computed outside it —
    /// so duplicate concurrent misses are expected and must be harmless.
    func testConcurrentMeasurementIsDeterministic() {
        let measure = CoreTextMeasurer.make()
        let texts = ["x", "y", "abc", "∑", "1"]
        let sizes: [CGFloat] = [10, 17, 24]

        var expected: [String: GlyphMetrics] = [:]
        for t in texts {
            for s in sizes { expected["\(t)|\(s)"] = measure(t, s, false) }
        }

        let mismatches = Mismatches()
        DispatchQueue.concurrentPerform(iterations: 500) { i in
            let t = texts[i % texts.count], s = sizes[i % sizes.count]
            let got = measure(t, s, false)
            if let want = expected["\(t)|\(s)"], !Self.same(got, want) {
                mismatches.add("\(t)@\(s): \(got) vs \(want)")
            }
        }
        XCTAssertEqual(mismatches.all, [], "the measurer returned inconsistent metrics under contention")
    }

    /// The `cache.count > 8192` reset branch — a `removeAll` racing concurrent
    /// readers, and the only place the dictionary shrinks. Needs >8192 distinct
    /// keys to fire at all, so it is otherwise dead code in practice.
    func testConcurrentMeasurementAcrossTheCacheResetBound() {
        let measure = CoreTextMeasurer.make()
        let mismatches = Mismatches()
        // The keys must be genuinely distinct. My first attempt used
        // `("g\(i % 90)", 8 + i % 100)`, which cycles with period 900 — so 9000
        // iterations produced 900 keys, the cache never approached 8192, and the
        // branch this test exists for never ran. The cache is private, so there
        // is nothing to assert against; only the key count makes it fire.
        DispatchQueue.concurrentPerform(iterations: 9000) { i in
            let m = measure("g\(i)", 17, false)
            if !(m.width > 0) { mismatches.add("degenerate metrics at \(i): width \(m.width)") }
        }
        XCTAssertEqual(mismatches.all, [], "the cache-reset branch corrupted measurements")
        // Still correct afterwards.
        XCTAssertTrue(Self.same(measure("x", 17, false), measure("x", 17, false)),
                      "the measurer stopped being deterministic after the reset")
    }

    /// GlyphMetrics is not Equatable, and widening a public type's conformance
    /// to suit a test would be the tail wagging the dog — compare its fields.
    private static func same(_ a: GlyphMetrics, _ b: GlyphMetrics) -> Bool {
        a.width == b.width && a.ascent == b.ascent && a.descent == b.descent
            && a.inkAscent == b.inkAscent && a.inkDescent == b.inkDescent
    }

    /// Collects failures from many threads. XCTAssert from inside
    /// concurrentPerform is not reliably attributed, so failures are gathered
    /// and asserted once on the main thread.
    private final class Mismatches: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }
}
#endif
