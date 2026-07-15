#if canImport(AppKit)
import XCTest
import AppKit
@testable import VinculumRender

/// The math VERIFICATION HARNESS (launch prep): every fixture equation
/// renders to a PNG and is compared against a reference image checked
/// into the repo (Tests/fixtures/math-golden/). Regenerate goldens with
/// `VINCULUM_UPDATE_SNAPSHOTS=1 swift test --filter MathGolden` and inspect
/// the PNGs by eye — they ARE the review artifact.
///
/// The fixture list is ALSO the coverage ledger: `.mustRender` fixtures
/// failing to render is a regression; a `.knownUnsupported` fixture that
/// STARTS rendering means coverage improved — move it up and regenerate.
/// On comparison failure the actual render lands in /tmp/math-actual-*.png
/// for side-by-side inspection.
// Touches NSApp.appearance (main-actor) to pin Aqua for deterministic ink.
@MainActor
final class MathGoldenRenderTests: XCTestCase {

    enum Expectation { case mustRender, knownUnsupported }

    struct Fixture {
        let name: String
        let latex: String
        let expectation: Expectation
        var font: MathFont = .latinModern
    }

    // Coverage map: CommonMark-adjacent MathJax/LaTeX users actually write.
    static let fixtures: [Fixture] = [
        // Core constructs
        .init(name: "fraction-nested", latex: #"\frac{1}{1+\frac{1}{x}}"#, expectation: .mustRender),
        .init(name: "compound-interest", latex: #"A = P\left(1 + \frac{r}{n}\right)^{nt}"#, expectation: .mustRender),
        .init(name: "quadratic", latex: #"x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}"#, expectation: .mustRender),
        .init(name: "sqrt-index", latex: #"\sqrt[3]{x^2 + y^2}"#, expectation: .mustRender),
        .init(name: "sub-super", latex: #"x_i^2 + y_{i+1}^{n-1}"#, expectation: .mustRender),
        // Big operators
        .init(name: "sum-limits", latex: #"\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}"#, expectation: .mustRender),
        .init(name: "integral", latex: #"\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}"#, expectation: .mustRender),
        .init(name: "product-union", latex: #"\prod_{k=1}^n a_k \quad \bigcup_{i} S_i"#, expectation: .mustRender),
        .init(name: "limit", latex: #"\lim_{x \to 0} \frac{\sin x}{x} = 1"#, expectation: .mustRender),
        // Environments
        .init(name: "pmatrix", latex: #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#, expectation: .mustRender),
        .init(name: "bmatrix-vector", latex: #"\begin{bmatrix} x \\ y \\ z \end{bmatrix}"#, expectation: .mustRender),
        .init(name: "cases", latex: #"f(x) = \begin{cases} x^2 & x \ge 0 \\ -x & x < 0 \end{cases}"#, expectation: .mustRender),
        .init(name: "aligned", latex: #"\begin{aligned} a &= b + c \\ &= d + e \end{aligned}"#, expectation: .mustRender),
        .init(name: "vmatrix-det", latex: #"\det = \begin{vmatrix} a & b \\ c & d \end{vmatrix}"#, expectation: .mustRender),
        // Greek, blackboard, calligraphic
        .init(name: "greek", latex: #"\alpha + \beta = \gamma \cdot \Delta \Omega"#, expectation: .mustRender),
        .init(name: "mathbb", latex: #"x \in \mathbb{R}, \mathcal{L}(f)"#, expectation: .mustRender),
        // Relations / arrows / logic
        .init(name: "relations", latex: #"a \le b \ne c \approx d \equiv e"#, expectation: .mustRender),
        .init(name: "arrows", latex: #"f: A \to B, x \mapsto x^2, P \Rightarrow Q"#, expectation: .mustRender),
        .init(name: "set-logic", latex: #"A \cup B \subseteq C \cap D, \forall x \exists y"#, expectation: .mustRender),
        // Text + spacing
        .init(name: "text-mode", latex: #"v = 3\,\text{m/s} \quad \mathrm{const}"#, expectation: .mustRender),
        // Delimiter sizing
        .init(name: "big-delimiters", latex: #"\left( \frac{a}{b} \right) \left[ \sum_i x_i \right]"#, expectation: .mustRender),
        .init(name: "angle-norm", latex: #"\left\langle u, v \right\rangle \le \left\lVert u \right\rVert"#, expectation: .mustRender),
        // Advanced — expectation set empirically; promote as coverage grows.
        .init(name: "accents", latex: #"\hat{x} + \vec{v} + \bar{y} + \dot{z}"#, expectation: .mustRender),
        .init(name: "binomial", latex: #"\binom{n}{k} = \frac{n!}{k!(n-k)!}"#, expectation: .mustRender),
        .init(name: "overbrace", latex: #"\overbrace{a + b + c}^{\text{sum}}"#, expectation: .mustRender),
        .init(name: "underset", latex: #"\underset{x \to 0}{\mathrm{argmin}}\; f(x)"#, expectation: .mustRender),
        .init(name: "partial-derivative", latex: #"\frac{\partial^2 u}{\partial x^2}"#, expectation: .mustRender),
        .init(name: "prime-derivative", latex: #"f'(x) = \lim_{h\to 0}\frac{f(x+h)-f(x)}{h}"#, expectation: .mustRender),
        .init(name: "operatorname-custom", latex: #"\operatorname{softmax}(z)_i = \frac{e^{z_i}}{\sum_j e^{z_j}}"#, expectation: .mustRender),
        .init(name: "stacked-substack", latex: #"\sum_{\substack{i < n \\ i \text{ odd}}} i"#, expectation: .mustRender),
        // Phase 1 — math alphabets, direct Unicode, operators, \big
        .init(name: "alphabets", latex: #"\mathbb{RCQ}\ \mathcal{ABL}\ \mathfrak{gH}\ \mathsf{sf}\ \mathtt{tt}"#, expectation: .mustRender),
        .init(name: "unicode-direct", latex: #"∫_0^∞ e^{-x} dx ≤ α + β"#, expectation: .mustRender),
        .init(name: "big-manual", latex: #"\big( x \big) + \bigl[ y \bigr]"#, expectation: .mustRender),
        .init(name: "operators-more", latex: #"\Pr(X) = \operatorname{argmax}_\theta L(\theta)"#, expectation: .mustRender),
        // Phase 2 — accents & generalized fractions
        .init(name: "accents-wide", latex: #"\widehat{abc} + \tilde{n} + \ddot{u} + \overline{AB} + \underline{x}"#, expectation: .mustRender),
        .init(name: "binom-nested", latex: #"\dbinom{n}{k} + \cfrac{1}{1 + \cfrac{1}{x}}"#, expectation: .mustRender),
        // Phase 3 — over/under, stretchy arrow, stackrel
        .init(name: "underbrace", latex: #"\underbrace{1 + 2 + \cdots + n}_{n\text{ terms}}"#, expectation: .mustRender),
        .init(name: "xrightarrow", latex: #"A \xrightarrow{f} B \xrightarrow[g]{} C"#, expectation: .mustRender),
        .init(name: "stackrel", latex: #"a \stackrel{\text{def}}{=} b"#, expectation: .mustRender),
        // Phase 5 — boxed, phantom, color
        .init(name: "boxed", latex: #"\boxed{E = mc^2}"#, expectation: .mustRender),
        .init(name: "colored", latex: #"\color{#cc2222}{x} + \textcolor{#2244cc}{y} = \color{#00aa88}{z}"#, expectation: .mustRender),
        // Phase 4 — arrays with \hline no longer degrade (content survives)
        .init(name: "array-hline", latex: #"\begin{array}{cc} a & b \\ \hline c & d \end{array}"#, expectation: .mustRender),
        // Stress corpus — the hardest CLEAN real-world expressions, promoted from
        // MathStressGallery to lock their rendering against regression.
        .init(name: "stress-nested-radical", latex: #"\sqrt{1 + \sqrt{1 + \sqrt{1 + \sqrt{1 + \cdots}}}}"#, expectation: .mustRender),
        .init(name: "stress-continued-fraction", latex: #"\cfrac{1}{1 + \cfrac{1}{2 + \cfrac{1}{3 + \cfrac{1}{4 + \cdots}}}}"#, expectation: .mustRender),
        .init(name: "stress-qed-lagrangian", latex: #"\mathcal{L} = -\frac{1}{4} F_{\mu\nu} F^{\mu\nu} + \bar{\psi}\left(i\gamma^\mu D_\mu - m\right)\psi"#, expectation: .mustRender),
        .init(name: "stress-einstein-field", latex: #"R_{\mu\nu} - \tfrac{1}{2} R\, g_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4}\, T_{\mu\nu}"#, expectation: .mustRender),
        .init(name: "stress-path-integral", latex: #"\langle x_f \mid x_i \rangle = \int \mathcal{D}[x(t)]\; e^{\,iS[x]/\hbar}"#, expectation: .mustRender),
        .init(name: "stress-product-sum", latex: #"\prod_{j \ge 0} \left( \sum_{k \ge 0} a_{jk} z^k \right) = \sum_{n \ge 0} z^n \left( \sum_{\substack{k_0, k_1, \ldots \ge 0 \\ k_0 + k_1 + \cdots = n}} a_{0k_0} a_{1k_1} \cdots \right)"#, expectation: .mustRender),
        // Batch 2 — forced style, sized delimiters, \pmod/\bmod
        .init(name: "dfrac-tfrac", latex: #"\dfrac{1}{2} + \tfrac{3}{4}"#, expectation: .mustRender),
        .init(name: "big-sized", latex: #"\bigl( \frac{a}{b} \bigr) + \Big[ \sum_i x_i \Big]"#, expectation: .mustRender),
        .init(name: "pmod-congruence", latex: #"a \equiv b \pmod{n}, \quad a \bmod n"#, expectation: .mustRender),
        // Quantum information & entanglement
        .init(name: "bell-state", latex: #"|\Phi^{+}\rangle = \frac{1}{\sqrt{2}}\left(|00\rangle + |11\rangle\right)"#, expectation: .mustRender),
        .init(name: "chsh-inequality", latex: #"\left| \langle AB \rangle + \langle AB' \rangle + \langle A'B \rangle - \langle A'B' \rangle \right| \le 2\sqrt{2}"#, expectation: .mustRender),
        .init(name: "entanglement-entropy", latex: #"S(\rho_A) = -\operatorname{tr}\left(\rho_A \log_2 \rho_A\right)"#, expectation: .mustRender),
        .init(name: "schmidt-decomposition", latex: #"|\psi\rangle_{AB} = \sum_i \sqrt{\lambda_i}\; |i\rangle_A \otimes |i\rangle_B"#, expectation: .mustRender),
        .init(name: "density-matrix", latex: #"\rho = \sum_i p_i\, |\psi_i\rangle\langle\psi_i|"#, expectation: .mustRender),
        // Batch 3 — TeX fidelity: unary-sign spacing, cramped scripts
        .init(name: "unary-signs", latex: #"x = -1, \quad (-a)(-b) = ab"#, expectation: .mustRender),
        .init(name: "cramped-scripts", latex: #"\frac{1}{n^2} + \sqrt{a^2 + b^2}"#, expectation: .mustRender),
        // Batch 4 — array column specs + rules
        .init(name: "array-augmented", latex: #"\left[ \begin{array}{cc|c} 1 & 0 & 3 \\ 0 & 1 & 5 \end{array} \right]"#, expectation: .mustRender),
        .init(name: "array-bordered", latex: #"\begin{array}{|r|l|} \hline x & 1 \\ \hline y^2 & 2 \\ \hline \end{array}"#, expectation: .mustRender),
        .init(name: "array-aligned-cols", latex: #"\begin{array}{lcr} 1 & 22 & 333 \\ 4444 & 5 & 66 \end{array}"#, expectation: .mustRender),
        // Batch 5 — more big operators, \cancel family, \not
        .init(name: "big-operators-ext", latex: #"\bigoplus_{i=1}^{n} V_i \quad \coprod_j X_j \quad \iiint_V f\, dV"#, expectation: .mustRender),
        .init(name: "cancel", latex: #"\frac{\cancel{a}\, b}{\cancel{a}} = b, \quad \xcancel{x^2}"#, expectation: .mustRender),
        .init(name: "not-relations", latex: #"a \not= b, \quad x \not\in A, \quad P \not\subset Q"#, expectation: .mustRender),
        // Batch 6 — explicit spacing, smash, struts, lap
        .init(name: "explicit-spacing", latex: #"a \hspace{1em} b \quad p \mkern18mu q \quad x \thinspace y"#, expectation: .mustRender),
        .init(name: "smash-strut", latex: #"\frac{\smash{\sqrt{2}}}{2} + \mathstrut x"#, expectation: .mustRender),
        // Batch 7 — vector / over-arrows
        .init(name: "vector-arrows", latex: #"\overrightarrow{AB} + \overleftarrow{CD} = \overleftrightarrow{PQ}, \quad \underrightarrow{xy}"#, expectation: .mustRender),
        // Batch 8 — math inside \text, logic symbols
        .init(name: "math-in-text", latex: #"\overbrace{x_1 + \cdots + x_n}^{\text{$n$ terms}} \quad \text{for all $\epsilon > 0$}"#, expectation: .mustRender),
        .init(name: "logic-symbols", latex: #"p \land q \lor \neg r \implies (a \le b \colon a \in S)"#, expectation: .mustRender),
        // Batch 9 — \genfrac, extended stretchy arrows
        .init(name: "genfrac-forms", latex: #"\genfrac{[}{]}{0pt}{}{n}{k} \quad \genfrac{(}{)}{}{}{a+b}{c}"#, expectation: .mustRender),
        .init(name: "x-arrows-ext", latex: #"A \xLongrightarrow{\varphi} B \xhookrightarrow{\iota} C \xmapsto{f} D"#, expectation: .mustRender),
        // Batch 10 — smallmatrix
        .init(name: "smallmatrix", latex: #"\left( \begin{smallmatrix} 1 & 0 \\ 0 & 1 \end{smallmatrix} \right) x = \left( \begin{smallmatrix} a \\ b \end{smallmatrix} \right)"#, expectation: .mustRender),
        // Deferred items resolved — \middle, \operatorname* limits, \tag
        .init(name: "middle-fence", latex: #"\left\{\, x \in \mathbb{R} \;\middle|\; x > 0 \,\right\} \quad \left( \frac{a}{b} \middle/ \frac{c}{d} \right)"#, expectation: .mustRender),
        .init(name: "operatorname-star", latex: #"\operatorname*{Fix}_{x} T = x, \quad \operatorname*{argmax}_{\theta} \mathcal{L}(\theta)"#, expectation: .mustRender),
        .init(name: "tag", latex: #"x^2 + y^2 = r^2 \tag{3.1}"#, expectation: .mustRender),
        // Batch 11 — extended symbols
        .init(name: "symbols-relations", latex: #"a \leqslant b \lll c \precsim d, \quad x \nleq y \nsim z \ncong w"#, expectation: .mustRender),
        .init(name: "symbols-arrows", latex: #"p \rightsquigarrow q \twoheadrightarrow r, \quad A \leftrightarrows B, \quad u \rightharpoonup v \leftrightharpoons w"#, expectation: .mustRender),
        .init(name: "symbols-ops", latex: #"a \ltimes b \rtimes c, \quad x \boxdot y \circledast z \dotplus w, \quad \hslash \, \measuredangle \, \blacktriangle"#, expectation: .mustRender),
        // Batch 13 — environment fixes
        .init(name: "alignat-env", latex: #"\begin{alignat}{2} x &= 1 & \quad y &= 2 \\ a &= 30 & \quad b &= 4 \end{alignat}"#, expectation: .mustRender),
        .init(name: "matrix-star-right", latex: #"\begin{pmatrix*}[r] -1 & 2 \\ 30 & -4 \end{pmatrix*}"#, expectation: .mustRender),
        .init(name: "multline-env", latex: #"\begin{multline} a + b + c + d \\ + e + f + g + h \end{multline}"#, expectation: .mustRender),
        // Batch 12 — atom-class overrides, \pmb, stateful \color
        .init(name: "atom-class", latex: #"a \mathbin{\star} b \mathrel{\triangleq} c, \quad \pmb{v} = \mathbf{0}"#, expectation: .mustRender),
        .init(name: "stateful-color", latex: #"{\color{red} a + b} + \color{blue} c \cdot d"#, expectation: .mustRender),
        // Batch 14 — over/under brackets & parens, \widecheck
        .init(name: "over-brackets", latex: #"\overbracket{a + b + c}^{k} \quad \underbracket{x + y}_{m} \quad \overparen{p + q} \quad \underparen{u + v} \quad \widecheck{ABC}"#, expectation: .mustRender),
        // Batch 15 — boxes: \fbox, \colorbox, \fcolorbox, \rule, \raisebox
        .init(name: "boxes", latex: #"\fbox{a+b} \quad \colorbox{yellow}{x^2} \quad \fcolorbox{red}{gray}{y+z} \quad a \rule{1.5em}{0.5pt} b \quad \raisebox{0.4em}{w}"#, expectation: .mustRender),
        // Delimiter size-variants — tall fences should use font cuts, not scaling
        .init(name: "tall-delimiters", latex: #"\left( \dfrac{a}{\dfrac{b}{\dfrac{c}{d}}} \right) \left[ \begin{matrix} w \\ x \\ y \\ z \end{matrix} \right] \left\{ \sum_{i=1}^{n} \frac{1}{i} \right\}"#, expectation: .mustRender),
        // \cancelto
        .init(name: "cancelto", latex: #"\cancelto{0}{\frac{x}{y}} + \cancelto{\infty}{n}"#, expectation: .mustRender),
        // Glyph ASSEMBLY: a fence far beyond the largest size variant (~3 em)
        // must be built from font parts (caps + extenders), constant stroke.
        .init(name: "assembly-tall", latex: #"\left( \dfrac{a}{\dfrac{b}{\dfrac{c}{\dfrac{d}{\dfrac{e}{f}}}}} \right)"#, expectation: .mustRender),
        // Un-gated variant ladders: ⟨ ⟩ and ‖ step through size variants now.
        .init(name: "tall-angle", latex: #"\left\langle \begin{matrix} a \\ b \\ c \end{matrix} \middle\| \begin{matrix} x \\ y \\ z \end{matrix} \right\rangle"#, expectation: .mustRender),
        // Per-font canaries: same equation under each bundled font, proving
        // per-font constants, variants, and (STIX) cut-in kerns end-to-end.
        .init(name: "canary-termes", latex: canaryLaTeX, expectation: .mustRender, font: .termes),
        .init(name: "canary-pagella", latex: canaryLaTeX, expectation: .mustRender, font: .pagella),
        .init(name: "canary-stixtwo", latex: canaryLaTeX, expectation: .mustRender, font: .stixTwo),
        .init(name: "canary-firamath", latex: canaryLaTeX, expectation: .mustRender, font: .firaMath),
    ]

    static let canaryLaTeX = #"T_i^j = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} + \sum_{i=1}^{n} \left( \frac{x_i}{y_i} \right)"#

    private var goldenDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/fixtures/math-golden")
    }

    private var updating: Bool {
        ProcessInfo.processInfo.environment["VINCULUM_UPDATE_SNAPSHOTS"] == "1"
    }

    /// Deterministic 2× rasterization of the attachment image.
    private func pngData(for latex: String, font: MathFont = .latinModern) -> Data? {
        guard let attributed = MathImageRenderer.attachmentString(
            latex: latex, display: true, mathTheme: MathTheme.light, baseSize: 15, font: font),
              let image = Self.attachmentImage(in: attributed),
              image.size.width > 0, image.size.height > 0
        else { return nil }
        let scale: CGFloat = 2
        let width = Int(ceil(image.size.width * scale))
        let height = Int(ceil(image.size.height * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private static func attachmentImage(in attributed: NSAttributedString) -> NSImage? {
        var image: NSImage?
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            if let attachment = value as? NSTextAttachment, let found = attachment.image {
                image = found
                stop.pointee = true
            }
        }
        return image
    }

    /// Pixel mismatch ratio between two same-size PNGs (1.0 when sizes differ).
    private func mismatchRatio(_ a: Data, _ b: Data) -> Double {
        guard let imageA = NSBitmapImageRep(data: a), let imageB = NSBitmapImageRep(data: b),
              imageA.pixelsWide == imageB.pixelsWide, imageA.pixelsHigh == imageB.pixelsHigh,
              let bytesA = imageA.bitmapData, let bytesB = imageB.bitmapData
        else { return 1 }
        let count = imageA.bytesPerPlane
        var mismatched = 0
        var sampled = 0
        var i = 0
        while i + 2 < count {
            sampled += 1
            // ALL color channels — a single-channel sample was blind to
            // pure-hue regressions (\color drifting while luminance holds).
            if abs(Int(bytesA[i]) - Int(bytesB[i])) > 24
                || abs(Int(bytesA[i + 1]) - Int(bytesB[i + 1])) > 24
                || abs(Int(bytesA[i + 2]) - Int(bytesB[i + 2])) > 24 {
                mismatched += 1
            }
            i += 4
        }
        return Double(mismatched) / Double(max(1, sampled))
    }

    func testEquationFixturesMatchGoldenRenders() throws {
        // Goldens use MathTheme.light (black ink). Pin Aqua so dynamic-color
        // resolution is deterministic regardless of the runner's appearance.
        // (Done here, not in setUp — an override of the nonisolated setUp
        // can't touch main-actor NSApp; this test method is @MainActor.)
        let savedAppearance = NSApp?.appearance
        NSApp?.appearance = NSAppearance(named: .aqua)
        defer { NSApp?.appearance = savedAppearance }

        try FileManager.default.createDirectory(at: goldenDirectory, withIntermediateDirectories: true)
        var failures: [String] = []
        var coverageChanges: [String] = []

        for fixture in Self.fixtures {
            let rendered = pngData(for: fixture.latex, font: fixture.font)
            switch (fixture.expectation, rendered) {
            case (.mustRender, nil):
                failures.append("\(fixture.name): REGRESSION — no longer renders")
                continue
            case (.knownUnsupported, nil):
                continue // expected gap, tracked
            case (.knownUnsupported, .some):
                coverageChanges.append(fixture.name)
                continue // improvement! promote to .mustRender + regenerate
            case (.mustRender, .some(let png)):
                let goldenURL = goldenDirectory.appendingPathComponent("\(fixture.name).png")
                if updating {
                    try png.write(to: goldenURL)
                    continue
                }
                guard let golden = try? Data(contentsOf: goldenURL) else {
                    failures.append("\(fixture.name): missing golden — run with VINCULUM_UPDATE_SNAPSHOTS=1")
                    continue
                }
                let ratio = mismatchRatio(png, golden)
                if ratio > 0.02 {
                    let actualURL = URL(fileURLWithPath: "/tmp/math-actual-\(fixture.name).png")
                    try? png.write(to: actualURL)
                    failures.append("\(fixture.name): \(Int(ratio * 100))% pixels differ from golden "
                        + "(actual saved to \(actualURL.path))")
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, "math golden failures:\n" + failures.joined(separator: "\n"))
        if !coverageChanges.isEmpty {
            XCTFail("COVERAGE IMPROVED — promote to .mustRender and regenerate goldens: "
                + coverageChanges.joined(separator: ", "))
        }
    }
}
#endif
