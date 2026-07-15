#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics
import VinculumLayout

extension MathLayoutEngine {
    /// The fully-equipped engine for a font: measurement, font-parsed
    /// constants, delimiter size variants, glyph assembly, per-glyph
    /// typography (italic correction / accent attachment / cut-in kerns),
    /// and wide-accent variants — everything the MATH table offers.
    ///
    /// This is the ONLY way render-side code should construct an engine.
    /// The bare `MathLayoutEngine(measure:baseSize:)` init exists for
    /// headless hosts injecting their own seams; on Apple platforms it
    /// silently drops every font capability (the expert-review finding
    /// that had the CI galleries rendering the pre-font-truth pipeline).
    public static func make(font: MathFont = .latinModern, baseSize: CGFloat) -> MathLayoutEngine {
        MathLayoutEngine(services: font.layoutServices, baseSize: baseSize)
    }
}

extension MathFont {
    /// The complete layout-services bundle for this font — every seam the
    /// MATH table can fill, plus the font's parsed constants.
    public var layoutServices: MathFontServices {
        MathFontServices(measure: CoreTextMeasurer.make(font: self),
                         constants: constants,
                         delimiters: CoreTextDelimiterProvider.make(font: self),
                         delimiterAssembly: CoreTextDelimiterProvider.makeAssembly(font: self),
                         typography: CoreTextTypographyProvider.make(font: self),
                         accentVariants: CoreTextDelimiterProvider.makeAccentVariants(font: self),
                         scriptVariants: CoreTextScriptVariantProvider.make(font: self))
    }
}
#endif
