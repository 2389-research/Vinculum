#if canImport(AppKit)
import AppKit
import Foundation
@testable import VinculumRender

/// The single source of truth for the wordmark render.
///
/// Shared by the generator that writes `docs/assets/wordmark-*.png` and the test
/// that verifies the committed asset still matches what the engine draws. These
/// were duplicated at first, which is a trap: change the generator's size or
/// colour, re-bless the asset, and the verifier would keep checking a recipe
/// nobody ships — going red for the wrong reason, or worse, green for one.
enum WordmarkRecipe {
    static let baseSize: CGFloat = 44
    static let font: MathFont = .stixTwo

    struct Variant {
        let name: String        // asset basename under docs/assets
        let ink: NSColor        // the radical + its vinculum bar
        let word: String        // hex colour of the word itself
        let prefersDark: Bool
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }

    /// Brand palette: cobalt radical over an ink word; lightened cobalt over
    /// parchment for dark canvases.
    static let variants: [Variant] = [
        Variant(name: "wordmark-light", ink: rgb(0x31, 0x5C, 0x9B), word: "#18212B", prefersDark: false),
        Variant(name: "wordmark-dark",  ink: rgb(0x6E, 0xA8, 0xFF), word: "#F4F0E6", prefersDark: true),
    ]

    static var light: Variant { variants[0] }

    /// The mark itself: the name under a real vinculum — the radical's own bar.
    static func latex(word: String) -> String {
        "\\sqrt{\\color{\(word)}{\\mathrm{Vinculum}}}"
    }

    static func render(_ v: Variant) -> NSImage? {
        MathImageRenderer.rendered(latex: latex(word: v.word), display: true,
                                   mathTheme: MathTheme(ink: v.ink, prefersDark: v.prefersDark),
                                   baseSize: baseSize, font: font)?.image
    }
}
#endif
