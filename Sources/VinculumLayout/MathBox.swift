import Foundation

/// The compositional unit of layout: a rectangle of typeset material with its
/// metrics and the positioned primitives that draw it. Boxes nest — a builder
/// lays out sub-boxes, then places each by translating its elements — exactly
/// TeX's hbox/vbox model, but as data (a scene fragment) rather than a draw
/// closure. Coordinates are y-up with the baseline at y = 0.
struct MathBox {
    var width: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
    /// Top of the actual ink above the baseline (≤ ascent). Accents sit on
    /// this so a hat hugs `x` instead of floating at the font ascent.
    /// Defaults to `ascent` for composite boxes.
    var inkAscent: CGFloat
    /// Primitives in this box's local coordinates (baseline origin at (0,0)).
    var elements: [MathElement]

    var height: CGFloat { ascent + descent }

    init(width: CGFloat, ascent: CGFloat, descent: CGFloat,
         inkAscent: CGFloat? = nil, elements: [MathElement] = []) {
        self.width = width
        self.ascent = ascent
        self.descent = descent
        self.inkAscent = inkAscent ?? ascent
        self.elements = elements
    }

    static let empty = MathBox(width: 0, ascent: 0, descent: 0)

    /// This box's elements translated so its baseline origin lands at `p`.
    func placed(at p: CGPoint) -> [MathElement] {
        (p.x == 0 && p.y == 0) ? elements : elements.map { $0.translated(by: p) }
    }
}
