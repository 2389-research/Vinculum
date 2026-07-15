import Foundation

/// Everything a font contributes to layout, bundled into one value: the
/// glyph measurer, the parsed MATH-table constants, and the four optional
/// per-glyph refinement seams. On Apple platforms build it (indirectly)
/// with `MathLayoutEngine.make(font:baseSize:)`; headless hosts construct
/// it with just a measurer — every refinement degrades gracefully when
/// absent.
///
/// Bundling exists so an engine can never be HALF-configured by accident:
/// an earlier design passed each seam as a separate init parameter, and
/// real call sites silently dropped capabilities.
public struct MathFontServices: Sendable {
    /// Measures a glyph run (required — layout cannot guess advances).
    public var measure: MathTextMeasurer
    /// The font's MATH-table constants. Defaults to the Latin Modern
    /// preset so headless hosts get TeX-true numbers with no font present.
    public var constants: MathFontConstants
    /// MATH-table delimiter size variants; nil → continuous glyph scaling.
    public var delimiters: MathDelimiterProvider?
    /// MATH-table glyph assembly (heights beyond the largest variant);
    /// nil → fall through to scaling.
    public var delimiterAssembly: MathDelimiterAssemblyProvider?
    /// Per-glyph typography (italic correction, accent attachment, cut-in
    /// kerns); nil → neutral defaults.
    public var typography: MathGlyphTypographyProvider?
    /// Horizontal width variants for stretchy accents; nil → scaling.
    public var accentVariants: MathAccentVariantProvider?
    /// `ssty` optical-script variants (heavier redraws for script /
    /// scriptscript); nil → the base glyph is scaled, as before.
    public var scriptVariants: MathScriptVariantProvider?

    public init(measure: @escaping MathTextMeasurer,
                constants: MathFontConstants = .latinModern,
                delimiters: MathDelimiterProvider? = nil,
                delimiterAssembly: MathDelimiterAssemblyProvider? = nil,
                typography: MathGlyphTypographyProvider? = nil,
                accentVariants: MathAccentVariantProvider? = nil,
                scriptVariants: MathScriptVariantProvider? = nil) {
        self.measure = measure
        self.constants = constants
        self.delimiters = delimiters
        self.delimiterAssembly = delimiterAssembly
        self.typography = typography
        self.accentVariants = accentVariants
        self.scriptVariants = scriptVariants
    }
}
