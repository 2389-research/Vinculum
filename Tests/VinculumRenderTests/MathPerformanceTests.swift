#if canImport(AppKit)
import XCTest
@testable import VinculumRender
import VinculumLayout

/// The numbers behind the README's performance claims, measured on every
/// run. Loose ceilings only (CI machines vary wildly); the printed medians
/// are the documentation source.
@MainActor
final class MathPerformanceTests: XCTestCase {

    private let quadratic = #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#

    private func median(of samples: [Double]) -> Double {
        let s = samples.sorted()
        return s[s.count / 2]
    }

    /// Cold path: parse → layout → rasterize, cache defeated per iteration.
    func testColdRenderTime() {
        var samples: [Double] = []
        for i in 0..<40 {
            // A unique size per iteration busts the cache without changing
            // the work meaningfully.
            let size = 15.0 + Double(i) * 0.001
            let start = ContinuousClock.now
            _ = MathImageRenderer.rendered(latex: quadratic, display: true,
                                           mathTheme: .light, baseSize: size)
            samples.append(Double((ContinuousClock.now - start) / .milliseconds(1)))
        }
        let ms = median(of: Array(samples.dropFirst(5)))   // skip warmup
        print(String(format: "PERF cold parse+layout+raster: %.2f ms (median)", ms))
        XCTAssertLessThan(ms, 100, "cold render regressed an order of magnitude")
    }

    /// Warm path: the same equation again — must be a cache hit.
    func testWarmCacheHitTime() {
        _ = MathImageRenderer.rendered(latex: quadratic, display: true,
                                       mathTheme: .light, baseSize: 17)
        var samples: [Double] = []
        for _ in 0..<200 {
            let start = ContinuousClock.now
            _ = MathImageRenderer.rendered(latex: quadratic, display: true,
                                           mathTheme: .light, baseSize: 17)
            samples.append(Double((ContinuousClock.now - start) / .microseconds(1)))
        }
        let us = median(of: samples)
        print(String(format: "PERF warm cache hit: %.1f µs (median)", us))
        XCTAssertLessThan(us, 2000, "cache hits must stay trivially cheap")
    }

    /// Headless layout only (no CoreText, no raster) — the Linux-relevant
    /// number.
    func testHeadlessLayoutTime() {
        let node = MathParser.parse(quadratic)
        let engine = MathLayoutEngine(measure: { text, size, _ in
            GlyphMetrics(width: CGFloat(text.count) * size * 0.6,
                         ascent: size * 0.75, descent: size * 0.25,
                         inkAscent: size * 0.7, inkDescent: -size * 0.05)
        }, baseSize: 15)
        var samples: [Double] = []
        for _ in 0..<200 {
            let start = ContinuousClock.now
            _ = engine.layout(node, display: true)
            samples.append(Double((ContinuousClock.now - start) / .microseconds(1)))
        }
        let us = median(of: samples)
        print(String(format: "PERF headless layout: %.1f µs (median)", us))
        XCTAssertLessThan(us, 5000)
    }
}
#endif
