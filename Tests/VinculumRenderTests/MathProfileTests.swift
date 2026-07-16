#if canImport(AppKit)
import XCTest
import AppKit
import CoreGraphics
@testable import VinculumRender
import VinculumLayout

/// Phase-decomposing profiler: attributes the cold render pipeline to its
/// stages — parse, support-check, speech, layout (with CoreText measurement
/// isolated), and rasterize — across a complexity range, then verifies the
/// headline numbers the README publishes AND whether `NSImage(size:flipped:)`
/// defers pixel rasterization (so "cold render" excludes the paint).
/// Gated on $VINCULUM_PROFILE; never runs in normal CI. Source of truth for
/// docs/PERFORMANCE.md.
@MainActor
final class MathProfileTests: XCTestCase {

    private final class Accum: @unchecked Sendable { var seconds = 0.0; var calls = 0 }

    private struct Corpus { let name: String; let latex: String }
    private let corpus: [Corpus] = [
        .init(name: "inline (a+b=c)",   latex: #"a + b = c"#),
        .init(name: "fraction",         latex: #"\frac{a}{b}"#),
        .init(name: "quadratic",        latex: #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#),
        .init(name: "sum identity",     latex: #"\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}"#),
        .init(name: "2x2 matrix",       latex: #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
        .init(name: "zeta (product)",   latex: #"\zeta(s) = \sum_{n=1}^{\infty} \frac{1}{n^s} = \prod_{p} \frac{1}{1 - p^{-s}}"#),
    ]

    private func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count/2] }
    private func us(_ d: Duration) -> Double { Double(d / .nanoseconds(1)) / 1000.0 }

    func testProfilePipeline() throws {
        guard ProcessInfo.processInfo.environment["VINCULUM_PROFILE"] != nil else {
            throw XCTSkip("set VINCULUM_PROFILE to run the profiler")
        }
        NSApp?.appearance = NSAppearance(named: .aqua)
        let font: MathFont = .latinModern
        // Warm CoreText's process-wide init (font system, shaping tables) so the
        // first corpus row reflects steady state, not one-time startup.
        for w in 0..<6 { _ = MathImageRenderer.rendered(latex: "x^{2} + 1 = 0", display: true,
                                                        mathTheme: .light, baseSize: 20 + Double(w), font: font) }
        let node0 = MathParser.parse("x + 1"); _ = MathLayoutEngine.make(font: font, baseSize: 20).layout(node0, display: true)
        let N = 80, warmup = 15
        func padL(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
        func padR(_ s: String, _ w: Int) -> String { s.count >= w ? s : String(repeating: " ", count: w - s.count) + s }
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        func m(_ a: [Double]) -> Double { median(Array(a.dropFirst(warmup))) }

        var lines: [String] = []
        lines.append([padL("equation",16), padR("parse",7), padR("supp",6), padR("speech",7),
                      padR("layout",7), padR("·meas",7), padR("·geom",7), padR("#m",4),
                      padR("raster",7), padR("cold=Σ",8)].joined(separator: " "))

        // Each phase is timed in ONE pass per unique size — parse→layout→raster
        // at a fresh size IS one cold render, so the phases sum to the total with
        // no cross-pass double-warming. `rendered()` is deliberately NOT called
        // in this loop (it would warm CoreText for the size and skew the phases).
        for item in corpus {
            var parseS=[Double](), supS=[Double](), spS=[Double](), layS=[Double]()
            var measS=[Double](), rasS=[Double](); var measCalls=0
            for i in 0..<N {
                let size = 15.0 + Double(i) * 0.0007   // unique → true first-touch each iter

                var t0 = ContinuousClock.now
                let node = MathParser.parse(item.latex)
                parseS.append(us(ContinuousClock.now - t0))

                t0 = ContinuousClock.now; _ = MathParser.isFullySupported(node)
                supS.append(us(ContinuousClock.now - t0))

                t0 = ContinuousClock.now; _ = MathSpeech.describe(node)
                spS.append(us(ContinuousClock.now - t0))

                var services = font.layoutServices          // full production providers
                let real = services.measure
                let acc = Accum()
                services.measure = { text, sz, mono in
                    let m0 = ContinuousClock.now
                    let r = real(text, sz, mono)
                    acc.seconds += Double((ContinuousClock.now - m0) / .nanoseconds(1)) / 1e9
                    acc.calls += 1; return r
                }
                let engine = MathLayoutEngine(services: services, baseSize: size * 1.15)
                t0 = ContinuousClock.now
                let scene = engine.layout(node, display: true)
                layS.append(us(ContinuousClock.now - t0))
                measS.append(acc.seconds * 1_000_000); measCalls = acc.calls

                let w = max(1, Int(ceil(scene.width)) + 4), h = max(1, Int(ceil(scene.height)) + 4)
                let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                t0 = ContinuousClock.now
                MathSceneRenderer.draw(scene, theme: .light, in: ctx,
                                       at: CGPoint(x: 2, y: scene.descent + 2), font: font)
                rasS.append(us(ContinuousClock.now - t0))
            }
            let lay = m(layS), meas = m(measS)
            let cold = m(parseS)+m(supS)+m(spS)+lay+m(rasS)
            lines.append([padL(item.name,16), padR(f(m(parseS)),7), padR(f(m(supS)),6), padR(f(m(spS)),7),
                          padR(f(lay),7), padR(f(meas),7), padR(f(max(0,lay-meas)),7), padR("\(measCalls)",4),
                          padR(f(m(rasS)),7), padR(f(cold),8)].joined(separator: " "))
        }

        // Is NSImage(size:flipped:) lazy? Time rendered() (returns the image) vs
        // forcing the pixels via cgImage() — which runs the deferred draw block
        // WITHOUT TIFF encoding (tiffRepresentation would add ~2ms of encoding,
        // not pixel work). Sizes disjoint from the phase loop's 15.x → true miss.
        var e2e=[Double](), draw=[Double]()
        let quad = corpus[2].latex
        for i in 0..<N {
            let size = 17.0 + Double(i) * 0.001
            let t0 = ContinuousClock.now
            let r = MathImageRenderer.rendered(latex: quad, display: true, mathTheme: .light, baseSize: size, font: font)!
            e2e.append(us(ContinuousClock.now - t0))
            var rect = CGRect(origin: .zero, size: r.image.size)
            let t1 = ContinuousClock.now
            _ = r.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)  // runs the deferred draw
            draw.append(us(ContinuousClock.now - t1))
        }

        // Warm cache hit + headless (mock) layout — the other two headline numbers.
        _ = MathImageRenderer.rendered(latex: quad, display: true, mathTheme: .light, baseSize: 17, font: font)
        var warm=[Double]()
        for _ in 0..<400 { let t=ContinuousClock.now
            _ = MathImageRenderer.rendered(latex: quad, display: true, mathTheme: .light, baseSize: 17, font: font)
            warm.append(us(ContinuousClock.now - t)) }
        let mockEngine = MathLayoutEngine(measure: { t,s,_ in
            GlyphMetrics(width: CGFloat(t.count)*s*0.6, ascent: s*0.75, descent: s*0.25,
                         inkAscent: s*0.7, inkDescent: -s*0.05) }, baseSize: 17)
        let qnode = MathParser.parse(quad)
        var head=[Double]()
        for _ in 0..<400 { let t=ContinuousClock.now; _ = mockEngine.layout(qnode, display: true)
            head.append(us(ContinuousClock.now - t)) }

        let report = ([
            "=== VINCULUM PIPELINE PROFILE (µs, medians, Latin Modern, this machine) ===",
        ] + lines + [
            "",
            "quadratic — is rasterization deferred?",
            "  rendered() returns image [lazy NSImage, no pixels]: " + f(m(e2e)) + " µs",
            "  force the deferred draw (cgImage): " + f(m(draw)) + " µs",
            "  => cold render + first paint: " + f(m(e2e) + m(draw)) + " µs",
            "",
            "headline check — warm cache hit: " + String(format:"%.2f",median(warm)) + " µs"
              + "   headless layout (mock): " + f(median(Array(head.dropFirst(30)))) + " µs",
        ]).joined(separator: "\n")
        print(report)
        if let out = ProcessInfo.processInfo.environment["VINCULUM_PROFILE_OUT"] {
            try? report.write(toFile: out, atomically: true, encoding: .utf8)
        }
    }
}
#endif
