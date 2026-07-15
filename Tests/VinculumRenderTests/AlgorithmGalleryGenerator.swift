#if canImport(AppKit)
import XCTest
import AppKit
@testable import VinculumRender
import VinculumLayout

/// Figures for docs/ALGORITHM.md — one poster per Appendix G rule cluster,
/// each showing the rule's *visible consequence* so the audit document can
/// put a render beside every claim. Written to $VINCULUM_GALLERY_DIR as
/// `alg-*.png`; CI republishes them on every push to `main`, so the doc
/// always shows what the current engine actually does.
@MainActor
final class AlgorithmGalleryGenerator: XCTestCase {

    func testGenerateAlgorithmFigures() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_GALLERY_DIR"] else {
            throw XCTSkip("set VINCULUM_GALLERY_DIR to generate the algorithm figures")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        NSApp?.appearance = NSAppearance(named: .aqua)

        // Rule 11 — radicals.
        try PosterCompositor.poster(to: out.appendingPathComponent("alg-radicals.png"),
                                    title: "Rule 11 — the radical is a font glyph that grows", sections: [
            ("Size variants first, assembly beyond the largest cut", [
                #"\sqrt{x} \quad \sqrt{x^2+1} \quad \sqrt{\frac{a}{b}} \quad \sqrt{\cfrac{1}{1+\cfrac{1}{x}}}"#,
            ]),
            ("The overbar uses the font's rule thickness and gap", [
                #"\sqrt{a}+\sqrt{b} = \sqrt{c}"#,
            ]),
            ("Degree indices ride TeX's fixed kerns (60% raise)", [
                #"\sqrt[3]{x} \quad \sqrt[n]{a^n + b^n} \quad \sqrt[p+q]{z}"#,
            ]),
        ])

        // Rule 12 — accents.
        try PosterCompositor.poster(to: out.appendingPathComponent("alg-accents.png"),
                                    title: "Rule 12 — accents center optically, not geometrically", sections: [
            ("Skew: the font's attachment point follows the letter's slant", [
                #"\hat{f} \quad \hat{d} \quad \hat{x} \quad \vec{v} \quad \bar{b} \quad \dot{q}"#,
            ]),
            ("Wide accents take the widest variant that fits the base", [
                #"\widehat{A} \quad \widehat{AB} \quad \widehat{ABC} \quad \widetilde{xyz} \quad \widecheck{abc}"#,
            ]),
            ("Tall bases: the accent seats on the ink, scripts stay attached", [
                #"\hat{A}^2 \quad \bar{X}_n \quad \overline{AB}^{\,2}"#,
            ]),
        ])

        // Rules 13/13a — large operators and limits.
        try PosterCompositor.poster(to: out.appendingPathComponent("alg-operators.png"),
                                    title: "Rules 13/13a — operators pick their glyph and limit form by style", sections: [
            ("Display style grows the operator and stacks ∑-class limits", [
                #"\sum_{i=1}^{n} x_i \qquad \textstyle\sum_{i=1}^{n} x_i"#,
                #"\prod_{p \text{ prime}} \frac{1}{1-p^{-s}} \qquad \bigcup_{i \in I} A_i"#,
            ]),
            ("∫-class keeps side scripts even in display (\\nolimits default)", [
                #"\int_{0}^{\infty} e^{-x^2}\,dx \qquad \oint_{C} \vec{F}\cdot d\vec{r} \qquad \iint_{D} f"#,
            ]),
            ("The \\lim family stacks; \\operatorname* forces it", [
                #"\lim_{x \to 0} \frac{\sin x}{x} \qquad \max_{i \le n} a_i \qquad \operatorname*{argmin}_{\theta} L(\theta)"#,
            ]),
        ])

        // Rule 15 — fractions.
        try PosterCompositor.poster(to: out.appendingPathComponent("alg-fractions.png"),
                                    title: "Rule 15 — fractions assemble around the math axis", sections: [
            ("The bar sits on the axis — where the minus sign lives", [
                #"\frac{a}{b} + c - \frac{1}{2}"#,
            ]),
            ("Shifts and clearances come from the font, per style", [
                #"\dfrac{a}{b} \quad \frac{a}{b} \quad \tfrac{a}{b} \quad x^{\frac{a}{b}}"#,
            ]),
            ("No bar → binomial clearances instead of a rule", [
                #"\binom{n}{k} \quad \dbinom{n}{k} \quad \genfrac{[}{]}{0pt}{}{n}{k}"#,
            ]),
            ("Continued fractions keep display size all the way down", [
                #"\cfrac{1}{1+\cfrac{1}{1+\cfrac{1}{x}}}"#,
            ]),
        ])

        // Rules 17/18a–f — scripts.
        try PosterCompositor.poster(to: out.appendingPathComponent("alg-scripts.png"),
                                    title: "Rules 17/18 — scripts are placed geometrically, not at fixed offsets", sections: [
            ("Shifts grow with the nucleus's height and depth", [
                #"x^2 \quad X^2 \quad \left(\frac{a}{b}\right)^{2} \quad \left(\cfrac{1}{1+x}\right)^{2}"#,
            ]),
            ("Simultaneous scripts: collision rules 18d/e keep them apart", [
                #"x_i^2 \quad \Gamma^{\lambda}_{\mu\nu} \quad \int_{a}^{b} \quad F_{n}^{(k)}"#,
            ]),
            ("Italic correction and cut-in kerns tuck subscripts under slants", [
                #"f_x \quad V_a \quad W_{ij} \quad T^{a}_{b} \quad j_1"#,
            ]),
            ("Primes are superscripts and bind before an explicit ^", [
                #"f' \quad f'' \quad f'^{2} \quad (g \circ f)'"#,
            ]),
        ])

        // Rules 9/10 + decorations — over/underlines, braces, boxes.
        try PosterCompositor.poster(to: out.appendingPathComponent("alg-decorations.png"),
                                    title: "Rules 9/10 & friends — lines, braces, and boxes over subformulas", sections: [
            ("Over/underline: the font's bar thickness and gap, inner cramped", [
                #"\overline{AB} \quad \underline{xy} \quad \overline{\overline{z}}"#,
            ]),
            ("Braces and brackets stretch to the base and carry annotations", [
                #"\overbrace{a + b + c}^{\text{sum}} \quad \underbrace{1 + \cdots + n}_{n\ \text{terms}}"#,
            ]),
            ("Boxes, cancels, and phantoms compose with anything", [
                #"\boxed{E = mc^2} \quad \cancel{x} \quad a\,\phantom{b}\,c"#,
            ]),
        ])
    }
}
#endif
