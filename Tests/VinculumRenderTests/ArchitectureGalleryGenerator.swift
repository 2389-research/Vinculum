#if canImport(AppKit)
import XCTest
import AppKit
@testable import VinculumRender
import VinculumLayout

/// Figures for docs/ARCHITECTURE.md — each poster illustrates one design
/// decision the document explains (the pair-spacing table, the delimiter
/// stretch chain, the style lattice, graceful degradation). Written to
/// $VINCULUM_GALLERY_DIR as `arch-*.png` and published to the gallery
/// branch by CI, so the doc always shows the current engine's output.
@MainActor
final class ArchitectureGalleryGenerator: XCTestCase {

    func testGenerateArchitectureFigures() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the architecture figures")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        NSApp?.appearance = NSAppearance(named: .aqua)

        // The atom-class spacing model: the p.170 pair table's visible
        // consequences, including reclassification and Inner atoms.
        try PosterCompositor.poster(to: out.appendingPathComponent("arch-spacing.png"),
                                    title: "Atom-class spacing — the TeXbook p. 170 pair table at work", sections: [
            ("Classes decide the gaps (Ord·Op·Bin·Rel·Open·Close·Punct·Inner)", [
                #"a+b \qquad a=b \qquad f(a,b)"#,
                #"\log n(x) \qquad \sin(x)"#,
            ]),
            ("Binary vs. unary: reclassification, not guesswork", [
                #"x - 1 \qquad x = -1 \qquad (-x)"#,
            ]),
            ("Fractions, \\left…\\right groups, and dots are Inner atoms", [
                #"a\frac{1}{2}b \qquad x\left(\frac{y}{z}\right)w"#,
                #"f(x_1,\ldots,x_n) \qquad x_1+\cdots+x_n"#,
            ]),
            ("Medium/thick spaces vanish at script level", [
                #"x^{a=b} \qquad e^{i\pi+1} \qquad \sum_{i=0,\,i\ne j}"#,
            ]),
        ])

        // The delimiter stretch chain: base glyph → discrete size variants →
        // glyph assembly, plus the explicitly-sized \big family.
        try PosterCompositor.poster(to: out.appendingPathComponent("arch-delimiters.png"),
                                    title: "The delimiter stretch chain — variants, then assembly", sections: [
            ("Font size variants (purpose-drawn cuts, constant stroke weight)", [
                #"(x) \quad \left(\frac{a}{b}\right) \quad \left(\dfrac{a^2}{b^2}\right)"#,
            ]),
            ("Glyph assembly beyond the largest cut", [
                #"\left(\cfrac{1}{1+\cfrac{1}{1+\cfrac{1}{1+x}}}\right)"#,
            ]),
            ("Explicit \\big…\\Bigg sizes (always scaled, by design)", [
                #"\big( \Big( \bigg( \Bigg( x \Bigg) \bigg) \Big) \big)"#,
            ]),
        ])

        // The style lattice: D→T→S→SS shrink, forced styles, cramping.
        try PosterCompositor.poster(to: out.appendingPathComponent("arch-styles.png"),
                                    title: "The style lattice — display, text, script, scriptscript", sections: [
            ("Scripts shrink to 70%, then hit the 50% floor", [
                #"x^{y^{z^{w}}} \qquad a_{i_{j}}"#,
            ]),
            ("The same fraction across styles (\\dfrac forces display, \\tfrac text)", [
                #"\dfrac{a}{b} \quad \frac{a}{b} \quad \tfrac{a}{b} \quad x^{\frac{a}{b}}"#,
            ]),
            ("Operators grow their display-style cut and stack their limits", [
                #"\sum_{i=1}^{n} x_i \qquad \int_0^1 f\,dx"#,
            ]),
        ])

        // ssty optical scripts: the font's script/scriptscript redraws.
        try PosterCompositor.poster(to: out.appendingPathComponent("arch-ssty.png"),
                                    title: "ssty optical scripts — script glyphs redrawn, not just scaled", sections: [
            ("Superscripts, subscripts, and deep nesting take heavier optical variants", [
                #"x^{2} + a_{i}^{k} + \Gamma^{\lambda}_{\mu\nu}"#,
                #"e^{i\pi} = -1 \qquad x^{y^{z^{w}}}"#,
            ]),
            ("So a shrunk glyph keeps the base text's weight instead of thinning out", [
                #"\sum_{i=1}^{n} \frac{1}{i^{2}} = \frac{\pi^{2}}{6}"#,
            ]),
        ])

        // The parser never fails: unknown commands degrade to legible source.
        try PosterCompositor.poster(to: out.appendingPathComponent("arch-fallback.png"),
                                    title: "Degradation, not failure — unknown input stays legible", sections: [
            ("Unknown commands become monospace source cards, in place", [
                #"x + \nosuchcommand{y} + z"#,
                #"\frac{\unknownthing}{2}"#,
            ]),
        ])
    }
}
#endif
