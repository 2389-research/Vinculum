#if canImport(AppKit)
import XCTest
import AppKit
import CoreText
import CoreGraphics
@testable import VinculumRender
@testable import VinculumLayout

/// A COMPREHENSIVE visual command gallery: every symbol in `MathSymbolTable`
/// rendered as a labeled tile (font-specimen style, grouped by atom class),
/// every function-name operator, and a representative example of every
/// structural command — so "how does Vinculum render `\foo`?" has a picture.
/// Enumerated from the live tables, so it never drifts from the code.
///
/// `VINCULUM_GALLERY_DIR=/tmp/g swift test --filter CommandGalleryGenerator`
/// (CI runs it on `main` and publishes the PNGs to the `gallery` branch.)
@MainActor
final class CommandGalleryGenerator: XCTestCase {

    func testGenerateCommandGallery() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the command gallery")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        NSApp?.appearance = NSAppearance(named: .aqua)

        // ── Symbol charts: every symbolTable entry, grouped by atom class ──
        let byClass = Dictionary(grouping: MathParser.symbolTable.keys) {
            MathParser.symbolTable[$0]!.1
        }
        let classPosters: [(MathAtomClass, String, String)] = [
            (.relation, "Relations", "sym-relations"),
            (.binary, "Binary operators", "sym-binary"),
            (.largeOperator, "Big operators", "sym-operators"),
            (.opening, "Opening delimiters", "sym-open"),
            (.closing, "Closing delimiters", "sym-close"),
            (.punctuation, "Punctuation", "sym-punct"),
            (.ordinary, "Ordinary · Greek · letterlike · arrows", "sym-ordinary"),
            (.inner, "Inner — ellipses (thin-spaced subformula atoms)", "sym-inner"),
        ]
        // Every class that has symbols must have a poster — a new
        // MathAtomClass case must not silently drop its commands from
        // the charts (the dots did exactly that when .inner landed).
        XCTAssertEqual(Set(byClass.keys), Set(classPosters.map(\.0)),
                       "sym-chart posters out of sync with MathAtomClass usage")
        for (cls, title, file) in classPosters {
            let names = (byClass[cls] ?? []).sorted()
            guard !names.isEmpty else { continue }
            try symbolGrid(to: out.appendingPathComponent("\(file).png"),
                           title: "\(title) — \(names.count) commands",
                           entries: names.map { (label: "\\\($0)", latex: "\\\($0)") })
        }

        // Function-name operators.
        let fns = MathParser.functionNames.sorted()
        try symbolGrid(to: out.appendingPathComponent("sym-functions.png"),
                       title: "Function-name operators — \(fns.count) commands",
                       entries: fns.map { (label: "\\\($0)", latex: "\\\($0) x") })

        // ── Structural command examples (source + native render) ──
        try structuralPoster(to: out.appendingPathComponent("cmd-structural.png"))

        // ── The extensible \x…arrow family, each with its own drawn head ──
        try PosterCompositor.poster(to: out.appendingPathComponent("cmd-arrows.png"),
            title: "Extensible arrows — each variant draws its own head", sections: [
            ("Arrows: plain, double-lined, bidirectional, hooked, mapsto", [
                #"A \xrightarrow{f} B \xleftarrow{g} C"#,
                #"A \xLongrightarrow{\phi} B \xLongleftarrow{\psi} C \xleftrightarrow{h} D"#,
                #"A \xhookrightarrow{\iota} B \xhookleftarrow{j} C \xmapsto{f} D"#,
            ]),
            ("Harpoons: single-barb heads, and the opposed pair", [
                #"X \xrightharpoonup{a} Y \xrightharpoondown{b} Z"#,
                #"X \xleftharpoonup{c} Y \xleftharpoondown{d} Z"#,
                #"\text{H}_2 + \text{I}_2 \xrightleftharpoons[k_r]{k_f} 2\,\text{HI}"#,
            ]),
        ])
    }

    // MARK: - Symbol grid (font-specimen tiles)

    private func symbolGrid(to url: URL, title: String, entries: [(label: String, latex: String)]) throws {
        let engine = MathLayoutEngine.make(baseSize: 21)
        let labelFont = CTFontCreateWithName("Menlo" as CFString, 9, nil)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 20, nil)

        struct Tile { let scene: MathScene; let label: CTLine; let labelW: CGFloat }
        var tiles: [Tile] = []
        for e in entries {
            let scene = engine.layout(MathParser.parse(e.latex), display: false)
            let (l, w) = ctLine(e.label, labelFont)
            tiles.append(Tile(scene: scene, label: l, labelW: w))
        }
        let contentW = tiles.map { max($0.scene.width, $0.labelW) }.max() ?? 40
        let cellW = contentW + 18
        let cellH: CGFloat = 52          // glyph band (baseline-aligned) + label band
        let baselineFromBottom: CGFloat = 22
        let labelBaselineFromBottom: CGFloat = 6
        let cols = max(4, min(entries.count, Int((980 / cellW).rounded(.down))))
        let rows = (tiles.count + cols - 1) / cols
        let margin: CGFloat = 26
        let (titleLine, _, titleAsc, titleDesc) = ctLineM(title, titleFont)

        let width = margin * 2 + CGFloat(cols) * cellW
        let gridTop = titleAsc + titleDesc + 18
        let height = margin + gridTop + CGFloat(rows) * cellH + margin

        let ctx = try bitmap(width: width, height: height)
        let y = height - margin - titleAsc
        drawLine(titleLine, x: margin, baseline: y, color: accentColor, in: ctx)
        let gridTopY = y - titleDesc - 18

        for (i, t) in tiles.enumerated() {
            let col = i % cols, row = i / cols
            let cellX = margin + CGFloat(col) * cellW
            let cellBottom = gridTopY - CGFloat(row + 1) * cellH
            // faint cell separator
            ctx.setStrokeColor(PlatformColor(white: 0.9, alpha: 1).cgColor); ctx.setLineWidth(0.5)
            ctx.stroke(CGRect(x: cellX, y: cellBottom, width: cellW, height: cellH))
            // glyph, baseline-aligned + centered
            let gx = cellX + (cellW - t.scene.width) / 2
            MathSceneRenderer.draw(t.scene, theme: .light, in: ctx,
                                   at: CGPoint(x: gx, y: cellBottom + baselineFromBottom),
                                   font: .latinModern)
            // command label (mono), centered under the glyph
            drawLine(t.label, x: cellX + (cellW - t.labelW) / 2,
                     baseline: cellBottom + labelBaselineFromBottom, color: grayColor, in: ctx)
        }
        try write(ctx, to: url)
    }

    // MARK: - Structural example poster (source · render rows, by section)

    private func structuralPoster(to url: URL) throws {
        let sections: [(String, [(String, String)])] = [
            ("Fractions & roots", [
                (#"\frac{a}{b}"#, #"\frac{a}{b}"#), (#"\dfrac / \tfrac"#, #"\dfrac{1}{2}\ \tfrac{1}{2}"#),
                (#"\cfrac"#, #"\cfrac{1}{1+\cfrac{1}{x}}"#), (#"\binom{n}{k}"#, #"\binom{n}{k}"#),
                (#"\genfrac"#, #"\genfrac{[}{]}{0pt}{}{n}{k}"#),
                (#"\sqrt / \sqrt[n]"#, #"\sqrt{2}\ \sqrt[3]{x}"#),
            ]),
            ("Scripts", [
                (#"x^2 \ x_i \ a_i^j"#, #"x^2 \quad x_i \quad a_i^j"#),
                (#"nested / primes"#, #"x^{2^n} \quad f''"#),
                (#"stacked limits"#, #"\sum_{i=1}^{n} \quad \lim_{x\to0}"#),
            ]),
            ("Delimiters (auto-sized + variants)", [
                (#"\left(\right)"#, #"\left(\frac{a}{b}\right)"#),
                (#"tall variants"#, #"\left[\dfrac{a}{\dfrac{b}{c}}\right]"#),
                (#"\middle"#, #"\left\{ x \middle| x>0 \right\}"#),
                (#"\big \Big \bigg"#, #"\big(\ \Big(\ \bigg(\ \Bigg("#),
            ]),
            ("Matrices & environments", [
                (#"pmatrix"#, #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
                (#"cases"#, #"\begin{cases} x & x\ge0 \\ -x & x<0 \end{cases}"#),
                (#"array + rules"#, #"\begin{array}{c|c} a & b \\ \hline c & d \end{array}"#),
                (#"aligned"#, #"\begin{aligned} a &= b \\ &= c \end{aligned}"#),
            ]),
            ("Accents & over/under", [
                (#"accents"#, #"\hat{x}\ \vec{v}\ \bar{y}\ \dot{z}\ \widehat{AB}"#),
                (#"vector arrows"#, #"\overrightarrow{AB}\ \overleftarrow{CD}"#),
                (#"brace/bracket/paren"#, #"\overbrace{a+b}\ \underbracket{c+d}\ \overparen{e+f}"#),
            ]),
            ("Boxes · decorations · color", [
                (#"boxes"#, #"\boxed{E}\ \fbox{x}\ \colorbox{yellow}{y}"#),
                (#"cancels"#, #"\cancel{x}\ \xcancel{y}\ \cancelto{0}{z}"#),
                (#"color"#, #"\color{red}{a} + \textcolor{blue}{b}"#),
            ]),
        ]
        try rowPoster(to: url, title: "Structural commands", sections: sections)
    }

    // MARK: - Shared compositor primitives

    private func rowPoster(to url: URL, title: String, sections: [(String, [(String, String)])]) throws {
        let engine = MathLayoutEngine.make(baseSize: 22)
        let labelFont = CTFontCreateWithName("Menlo" as CFString, 11, nil)
        let headerFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 14, nil)
        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 20, nil)

        struct Row { let label: CTLine; let labelW: CGFloat; let scene: MathScene }
        struct Sec { let header: CTLine; let hAsc: CGFloat; let hDesc: CGFloat; let rows: [Row] }
        var built: [Sec] = []
        var labelColW: CGFloat = 0, boxColW: CGFloat = 0
        for (header, exprs) in sections {
            var rows: [Row] = []
            for (label, latex) in exprs {
                let scene = engine.layout(MathParser.parse(latex), display: true)
                let (l, w) = ctLine(label, labelFont)
                rows.append(Row(label: l, labelW: w, scene: scene))
                labelColW = max(labelColW, w); boxColW = max(boxColW, scene.width)
            }
            let (h, _, ha, hd) = ctLineM(header, headerFont)
            built.append(Sec(header: h, hAsc: ha, hDesc: hd, rows: rows))
        }
        let margin: CGFloat = 28, gutter: CGFloat = 36, rowGap: CGFloat = 20, secGap: CGFloat = 26
        let (titleLine, titleW, titleAsc, titleDesc) = ctLineM(title, titleFont)
        let width = margin * 2 + max(labelColW + gutter + boxColW, titleW)
        var height = margin + titleAsc + titleDesc + secGap
        for s in built {
            height += s.hAsc + s.hDesc + rowGap * 0.6
            for r in s.rows { height += max(r.scene.height, 16) + rowGap }
            height += secGap
        }
        height += margin - rowGap

        let ctx = try bitmap(width: width, height: height)
        var y = height - margin - titleAsc
        drawLine(titleLine, x: margin, baseline: y, color: accentColor, in: ctx)
        y -= titleDesc + secGap
        let boxX = margin + labelColW + gutter
        for s in built {
            y -= s.hAsc
            drawLine(s.header, x: margin, baseline: y, color: PlatformColor.black, in: ctx)
            y -= s.hDesc + rowGap * 0.6
            for r in s.rows {
                let asc = max(r.scene.ascent, 11), desc = max(r.scene.descent, 4)
                y -= asc
                drawLine(r.label, x: margin + (labelColW - r.labelW), baseline: y, color: grayColor, in: ctx)
                MathSceneRenderer.draw(r.scene, theme: .light, in: ctx, at: CGPoint(x: boxX, y: y), font: .latinModern)
                y -= desc + rowGap
            }
            y -= secGap
        }
        try write(ctx, to: url)
    }

    private var accentColor: PlatformColor { PlatformColor(red: 0.20, green: 0.47, blue: 0.96, alpha: 1) }
    private var grayColor: PlatformColor { PlatformColor(white: 0.42, alpha: 1) }

    private func ctLine(_ s: String, _ font: CTFont) -> (CTLine, CGFloat) {
        let l = ctLineM(s, font); return (l.0, l.1)
    }
    private func ctLineM(_ s: String, _ font: CTFont) -> (CTLine, CGFloat, CGFloat, CGFloat) {
        let attr = NSAttributedString(string: s, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true])
        let l = CTLineCreateWithAttributedString(attr)
        var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(l, &a, &d, &lead))
        return (l, w, a, d)
    }
    private func drawLine(_ l: CTLine, x: CGFloat, baseline y: CGFloat, color: PlatformColor, in ctx: CGContext) {
        ctx.saveGState(); ctx.setFillColor(resolvedCGColor(color))
        ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(l, ctx); ctx.restoreGState()
    }
    private func bitmap(width: CGFloat, height: CGFloat) throws -> CGContext {
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw XCTSkip("no context")
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(PlatformColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }
    private func write(_ ctx: CGContext, to url: URL) throws {
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw XCTSkip("no image")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
