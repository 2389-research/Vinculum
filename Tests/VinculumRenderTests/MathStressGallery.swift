#if canImport(AppKit)
import XCTest
import AppKit
import CoreText
import CoreGraphics
@testable import VinculumRender
import VinculumLayout

/// A large real-world corpus that doubles as (1) a RENDERING STRESS TEST —
/// dense, deeply-nested, multi-construct expressions laid out like pages of a
/// paper — and (2) a COVERAGE AUDIT: `testCorpusCoverageReport` reports, for
/// the whole corpus, how much renders natively and exactly which commands
/// degrade (the roadmap, measured against real math rather than a wishlist).
///
/// Formulas aren't copyrightable; these are canonical equations from physics,
/// analysis, algebra, number theory, and the TeXbook's classic torture cases,
/// assembled here — not copied from any one source.
///
/// `VINCULUM_STRESS_DIR=/tmp/stress swift test --filter MathStressGallery`
/// writes a PNG "page" per section for visual inspection.
@MainActor
final class MathStressGallery: XCTestCase {

    typealias Page = (title: String, equations: [String])

    static let pages: [Page] = [
        ("Electromagnetism & classical mechanics", [
            #"\nabla \cdot \vec{E} = \frac{\rho}{\epsilon_0}, \qquad \nabla \cdot \vec{B} = 0"#,
            #"\nabla \times \vec{E} = -\frac{\partial \vec{B}}{\partial t}"#,
            #"\nabla \times \vec{B} = \mu_0 \vec{J} + \mu_0 \epsilon_0 \frac{\partial \vec{E}}{\partial t}"#,
            #"\vec{F} = q\left(\vec{E} + \vec{v} \times \vec{B}\right)"#,
            #"\vec{S} = \frac{1}{\mu_0}\, \vec{E} \times \vec{B}"#,
            #"\nabla^2 \phi - \frac{1}{c^2}\frac{\partial^2 \phi}{\partial t^2} = 0"#,
            #"\frac{d}{dt}\!\left(\frac{\partial L}{\partial \dot{q}_i}\right) - \frac{\partial L}{\partial q_i} = 0"#,
            #"\dot{q}_i = \frac{\partial H}{\partial p_i}, \qquad \dot{p}_i = -\frac{\partial H}{\partial q_i}"#,
        ]),
        ("Quantum mechanics & relativity", [
            #"i\hbar \frac{\partial}{\partial t}\,\Psi = \hat{H}\,\Psi"#,
            #"\left(i\gamma^\mu \partial_\mu - m\right)\psi = 0"#,
            #"[\hat{x}, \hat{p}] = i\hbar, \qquad \Delta x\,\Delta p \ge \frac{\hbar}{2}"#,
            #"\langle x_f \mid x_i \rangle = \int \mathcal{D}[x(t)]\; e^{\,iS[x]/\hbar}"#,
            #"R_{\mu\nu} - \tfrac{1}{2} R\, g_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4}\, T_{\mu\nu}"#,
            #"\mathcal{L} = -\frac{1}{4} F_{\mu\nu} F^{\mu\nu} + \bar{\psi}\left(i\gamma^\mu D_\mu - m\right)\psi"#,
            #"E^2 = (pc)^2 + \left(mc^2\right)^2"#,
            #"\langle \hat{A} \rangle = \int \psi^{*}\, \hat{A}\, \psi \, dx"#,
        ]),
        ("Real & complex analysis", [
            #"f(x) = \sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!}\,(x - a)^n"#,
            #"\forall \epsilon > 0\ \exists \delta > 0 : 0 < |x - a| < \delta \implies |f(x) - L| < \epsilon"#,
            #"\left\| f \right\|_p = \left( \int_\Omega |f|^p \, d\mu \right)^{1/p}"#,
            #"f(a) = \frac{1}{2\pi i} \oint_\gamma \frac{f(z)}{z - a}\, dz"#,
            #"\hat{f}(\xi) = \int_{-\infty}^{\infty} f(x)\, e^{-2\pi i x \xi}\, dx"#,
            #"\int_M d\omega = \oint_{\partial M} \omega"#,
            #"f'(x) = \lim_{h \to 0} \frac{f(x + h) - f(x)}{h}"#,
            #"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}, \qquad \prod_{n=1}^{\infty} \frac{1}{1 - x^n}"#,
        ]),
        ("Linear algebra", [
            #"A\vec{v} = \lambda \vec{v}, \qquad \det(A - \lambda I) = 0"#,
            #"A = U \Sigma V^{\top}"#,
            #"A^{-1} = \frac{1}{ad - bc}\begin{pmatrix} d & -b \\ -c & a \end{pmatrix}"#,
            #"\begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc"#,
            #"\vec{x}^{\top} A \vec{x} = \sum_{i,j} a_{ij}\, x_i x_j"#,
            #"\begin{pmatrix} a_{11} & \cdots & a_{1n} \\ \vdots & \ddots & \vdots \\ a_{m1} & \cdots & a_{mn} \end{pmatrix}"#,
            #"\operatorname{tr}(AB) = \sum_{i} \sum_{j} a_{ij} b_{ji}"#,
        ]),
        ("Number theory & combinatorics", [
            #"\zeta(s) = \sum_{n=1}^{\infty} \frac{1}{n^s} = \prod_{p \text{ prime}} \frac{1}{1 - p^{-s}}"#,
            #"(x + y)^n = \sum_{k=0}^{n} \binom{n}{k} x^k y^{n-k}"#,
            #"a \equiv b \pmod{n}, \qquad a^{p-1} \equiv 1 \pmod{p}"#,
            #"\binom{n}{k} = \binom{n-1}{k-1} + \binom{n-1}{k}"#,
            #"n! \sim \sqrt{2\pi n}\left(\frac{n}{e}\right)^n"#,
            #"\sum_{n \ge 0} F_n x^n = \frac{x}{1 - x - x^2}"#,
            #"\gcd(a, b) = \gcd(b,\, a \bmod b)"#,
        ]),
        ("Quantum information & entanglement", [
            #"|\Phi^{+}\rangle = \frac{1}{\sqrt{2}}\left(|00\rangle + |11\rangle\right)"#,
            #"|\Psi^{-}\rangle = \frac{1}{\sqrt{2}}\left(|01\rangle - |10\rangle\right)"#,
            #"\rho = \sum_i p_i\, |\psi_i\rangle\langle\psi_i|"#,
            #"\rho_A = \operatorname{tr}_B\left(\rho_{AB}\right)"#,
            #"S(\rho_A) = -\operatorname{tr}\left(\rho_A \log_2 \rho_A\right)"#,
            #"\left| \langle AB \rangle + \langle AB' \rangle + \langle A'B \rangle - \langle A'B' \rangle \right| \le 2\sqrt{2}"#,
            #"|\mathrm{GHZ}\rangle = \frac{1}{\sqrt{2}}\left(|000\rangle + |111\rangle\right)"#,
            #"|\psi\rangle_{AB} = \sum_i \sqrt{\lambda_i}\; |i\rangle_A \otimes |i\rangle_B"#,
            #"\langle \hat{O} \rangle = \operatorname{tr}\!\left(\rho\, \hat{O}\right)"#,
        ]),
        ("Extended notation (v0.6–0.15)", [
            #"\frac{\cancel{n!}}{\cancel{n!}\,(n+1)} = \frac{1}{n+1}"#,
            #"\overrightarrow{F} = m\,\overrightarrow{a}, \qquad \overrightarrow{AB} \perp \overrightarrow{CD}"#,
            #"\bigoplus_{i=1}^{n} V_i \cong V, \qquad \coprod_{j \in J} X_j"#,
            #"x \equiv 7 \pmod{12}, \qquad a \bmod n, \qquad \binom{p}{k} \equiv 0 \pmod{p}"#,
            #"\mathbb{Q} \not\subset \mathbb{Z}, \qquad p \land q \lor \neg r \implies s"#,
            #"\left( \begin{smallmatrix} 1 & 0 \\ 0 & 1 \end{smallmatrix} \right) \qquad \dfrac{1}{2} \ne \tfrac{1}{2}"#,
            #"\underbrace{\overbrace{a + \cdots + a}^{n}}_{\text{$n$ copies}} = na"#,
        ]),
        ("Tables, arrays & linear systems", [
            #"\begin{array}{c|c|c} a & b & a + b \\ \hline 0 & 0 & 0 \\ 0 & 1 & 1 \\ 1 & 1 & 2 \end{array}"#,
            #"\left[ \begin{array}{ccc|c} 1 & 2 & 3 & 6 \\ 0 & 1 & 1 & 3 \\ 0 & 0 & 1 & 2 \end{array} \right]"#,
            #"\begin{array}{|c|c|} \hline \text{in} & \text{out} \\ \hline 0 & 1 \\ 1 & 0 \\ \hline \end{array}"#,
            #"\left( \begin{array}{rrr} 1 & -2 & 3 \\ -4 & 5 & -6 \\ 7 & -8 & 9 \end{array} \right)"#,
        ]),
        ("TeXbook classics & torture", [
            #"\sqrt{1 + \sqrt{1 + \sqrt{1 + \sqrt{1 + \cdots}}}}"#,
            #"\cfrac{1}{1 + \cfrac{1}{2 + \cfrac{1}{3 + \cfrac{1}{4 + \cdots}}}}"#,
            #"\underbrace{a + a + \cdots + a}_{n \text{ times}} = na"#,
            #"\overbrace{x_1 + x_2 + \cdots + x_n}^{n \text{ terms}}"#,
            #"\prod_{j \ge 0} \left( \sum_{k \ge 0} a_{jk} z^k \right) = \sum_{n \ge 0} z^n \left( \sum_{\substack{k_0, k_1, \ldots \ge 0 \\ k_0 + k_1 + \cdots = n}} a_{0k_0} a_{1k_1} \cdots \right)"#,
            #"f(x) = \begin{cases} x^2 \sin(1/x) & x \ne 0 \\ 0 & x = 0 \end{cases}"#,
            #"\begin{aligned} (a + b)^2 &= a^2 + 2ab + b^2 \\ (a - b)^2 &= a^2 - 2ab + b^2 \end{aligned}"#,
            #"e^x = \sum_{n=0}^{\infty} \frac{x^n}{n!} = \lim_{n \to \infty}\left(1 + \frac{x}{n}\right)^n"#,
        ]),
    ]

    private var allEquations: [(page: String, latex: String)] {
        Self.pages.flatMap { page in page.equations.map { (page.title, $0) } }
    }

    // MARK: - Coverage audit (headless, fast)

    /// Parses the whole corpus and reports native-render coverage + the exact
    /// set of unsupported commands (with a real example of each). Prints the
    /// ledger and asserts the corpus never crashes the parser.
    func testCorpusCoverageReport() {
        var supported = 0
        var unsupportedExamples: [String: String] = [:]   // command → an equation that uses it
        var unsupportedCounts: [String: Int] = [:]
        var degraded: [(String, String)] = []             // (page, latex)

        for (page, latex) in allEquations {
            let node = MathParser.parse(latex)             // never throws by contract
            if MathParser.isFullySupported(node) {
                supported += 1
            } else {
                degraded.append((page, latex))
                for cmd in MathParser.unsupportedCommands(in: node) {
                    unsupportedCounts[cmd, default: 0] += 1
                    if unsupportedExamples[cmd] == nil { unsupportedExamples[cmd] = latex }
                }
            }
        }

        let total = allEquations.count
        let pct = total == 0 ? 0 : Int((Double(supported) / Double(total) * 100).rounded())
        print("""

        ╔══════════════════════════════════════════════════════════════╗
        ║  Vinculum stress corpus — coverage audit
        ╠══════════════════════════════════════════════════════════════╣
        ║  \(total) real equations · \(supported) render natively (\(pct)%) · \(degraded.count) degrade
        ╚══════════════════════════════════════════════════════════════╝
        """)
        if !unsupportedCounts.isEmpty {
            print("  Unsupported commands (by frequency):")
            for (cmd, count) in unsupportedCounts.sorted(by: { $0.value > $1.value }) {
                print(String(format: "    %-16@ ×%d   e.g. %@", cmd as NSString, count,
                             (unsupportedExamples[cmd] ?? "") as NSString))
            }
            print("\n  Degraded equations:")
            for (page, latex) in degraded { print("    [\(page)]  \(latex)") }
        } else {
            print("  Every equation in the corpus renders natively. 🎉")
        }
        print("")

        // The corpus is a ratchet: the parser must survive all of it, and
        // native coverage should not silently regress below where we are today.
        XCTAssertGreaterThanOrEqual(pct, 60, "native coverage of the real-world corpus regressed")
    }

    // MARK: - Visual stress pages (gated)

    func testGenerateStressPages() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_STRESS_DIR"] else {
            throw XCTSkip("set VINCULUM_STRESS_DIR to render the stress pages")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        NSApp?.appearance = NSAppearance(named: .aqua)

        for (index, page) in Self.pages.enumerated() {
            let url = out.appendingPathComponent(String(format: "page-%02d.png", index + 1))
            try renderPage(page, to: url)
        }
    }

    /// Lays the page's equations out centered and stacked on a white page,
    /// like a document — the "does dense real math hold up" view.
    private func renderPage(_ page: Page, to url: URL) throws {
        let engine = MathLayoutEngine.make(baseSize: 21)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 22, nil)
        let margin: CGFloat = 44, gap: CGFloat = 26

        // Lay out every equation; drop any that degrade (so the page is the
        // native-render view). Degraded ones are listed in the coverage audit.
        var scenes: [MathScene] = []
        for latex in page.equations {
            let node = MathParser.parse(latex)
            guard MathParser.isFullySupported(node) else { continue }
            scenes.append(engine.layout(node, display: true))
        }

        let titleLine = CTLineCreateWithAttributedString(NSAttributedString(string: page.title, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: titleFont,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true]))
        var tAsc: CGFloat = 0, tDesc: CGFloat = 0, tLead: CGFloat = 0
        let titleW = CGFloat(CTLineGetTypographicBounds(titleLine, &tAsc, &tDesc, &tLead))

        let contentWidth = max(scenes.map(\.width).max() ?? 0, titleW)
        let width = contentWidth + margin * 2
        var height = margin + (tAsc + tDesc) + gap * 1.5
        for s in scenes { height += s.height + gap }
        height += margin - gap

        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("no context")
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var y = height - margin - tAsc
        ctx.saveGState()
        ctx.setFillColor(NSColor(red: 0.20, green: 0.47, blue: 0.96, alpha: 1).cgColor)
        ctx.textPosition = CGPoint(x: margin, y: y)
        CTLineDraw(titleLine, ctx)
        ctx.restoreGState()
        y -= tDesc + gap * 1.5

        for s in scenes {
            y -= s.ascent
            let x = margin + (contentWidth - s.width) / 2   // centered like a display equation
            MathSceneRenderer.draw(s, theme: .light, in: ctx, at: CGPoint(x: x, y: y), font: .latinModern)
            y -= s.descent + gap
        }

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw XCTSkip("no image")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
