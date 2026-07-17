import Foundation

/// A fully self-contained, device-independent drawing list — a `MathScene`
/// reduced to nothing but filled/stroked paths and filled rectangles in
/// concrete colors, with **every glyph already resolved to its outline**.
///
/// This is the Android backend's boundary object (see `docs/ANDROID.md`): it
/// needs no font to draw, so the Kotlin `Canvas` side stays font-agnostic and
/// the JNI surface carries only geometry + color. It reproduces exactly what
/// the Apple (CoreGraphics) and Linux (Cairo) backends draw, because those also
/// fill glyph outlines — so "all outlines" is the *highest-fidelity* choice
/// against our own reference, not a compromise.
///
/// Coordinates are **y-up with the origin on the baseline** (the `MathScene`
/// convention). Bounds are tight to the ink; a consumer adds its own padding
/// when it allocates a surface. The y-down flip and any padding happen once at
/// the render boundary, never in here.
public struct DisplayList: Sendable {
    public var width: CGFloat
    public var ascent: CGFloat
    public var descent: CGFloat
    public var ops: [Op]

    public var height: CGFloat { ascent + descent }

    public init(width: CGFloat, ascent: CGFloat, descent: CGFloat, ops: [Op]) {
        self.width = width; self.ascent = ascent; self.descent = descent; self.ops = ops
    }

    /// One drawing primitive. Colors are **concrete** — the scene's `nil`
    /// (= theme ink) is already resolved against the ink the list was built
    /// with, so the list fully determines the picture.
    public enum Op: Sendable {
        /// A filled outline — every glyph (both spelled runs and MATH-table
        /// variant glyphs) lands here, plus any filled shape.
        case fillPath(subpaths: [PathOp], color: MathColor)
        /// A filled rectangle — fraction bars, over/underlines, boxed sides.
        case fillRect(CGRect, color: MathColor)
        /// A stroked path — radical signs, braces, arrows, box borders — kept
        /// as a stroke (not flattened to a fill) because `Canvas`/`Paint` draw
        /// it natively with the same cap/join.
        case strokePath(path: [PathOp], width: CGFloat, cap: StrokeCap, join: StrokeJoin, color: MathColor)
    }
}

/// The font capability the `DisplayList` emitter needs, injected so the emitter
/// stays platform-free. Two operations, both returning outlines in scene
/// coordinates (y-up, origin on the baseline):
///
/// - `glyphRun` shapes and pen-advances a text run to a single outline.
/// - `variantGlyph` outlines a single MATH-table glyph by ID (delimiter size
///   variants, `ssty` optical scripts — glyphs with no character spelling).
///
/// Backed by CoreText on Apple and FreeType on Linux/Android. Critically, it
/// must be the **same engine that measured the scene**, or the outlines won't
/// sit where the geometry expects them — the seam-parity law (issue #62).
public struct MathOutliner: Sendable {
    public var glyphRun: @Sendable (_ text: String, _ size: CGFloat, _ mono: Bool) -> [PathOp]
    public var variantGlyph: GlyphOutlineProvider

    public init(glyphRun: @escaping @Sendable (_ text: String, _ size: CGFloat, _ mono: Bool) -> [PathOp],
                variantGlyph: @escaping GlyphOutlineProvider) {
        self.glyphRun = glyphRun
        self.variantGlyph = variantGlyph
    }
}
