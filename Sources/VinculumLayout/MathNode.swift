import Foundation

/// A parsed LaTeX math expression. The node tree is deliberately close to
/// TeX's own model — rows of atoms with spacing classes — so the layout
/// engine can apply real inter-atom spacing rules instead of guessing.
public indirect enum MathNode: Hashable, Sendable {
    /// A single glyph run (variable, digit, symbol) with its TeX atom class.
    case symbol(String, MathAtomClass, style: MathSymbolStyle = .italic)
    /// Horizontal sequence.
    case row([MathNode])
    case fraction(numerator: MathNode, denominator: MathNode)
    /// `\cfrac`: a continued fraction laid out at full display size (parts
    /// don't shrink per level) with the denominator aligned left/center/right.
    case cfrac(numerator: MathNode, denominator: MathNode, align: CfracAlign)
    case radical(degree: MathNode?, radicand: MathNode)
    case scripts(base: MathNode, subscript: MathNode?, superscript: MathNode?)
    /// Auto-sized fences around a body: ( ) [ ] { } | ‖.
    case delimited(left: String, body: MathNode, right: String)
    /// `\left … \middle| … \right`: fences with interior `\middle` delimiters,
    /// all stretched to the common body height. `fences.count ==
    /// segments.count + 1` (fences = [left, mid₀, …, right]).
    case fenced(fences: [String], segments: [MathNode])
    /// A grid of cells from a `\begin{…}…\end{…}` environment — matrices,
    /// `cases`, `aligned`. `left`/`right` are the enclosing fences (empty for
    /// none); `style` selects column alignment.
    case matrix(rows: [[MathNode]], left: String, right: String, style: MathMatrixStyle)
    /// Upright function name (sin, log …).
    case functionName(String)
    /// A `\operatorname*`-style operator that takes stacked limits in display
    /// (a custom `\lim`-like operator). Transparent to layout except that
    /// `takesDisplayLimits` is true for it.
    case limitsOperator(base: MathNode)
    /// A subexpression with a forced atom class: `\mathbin`, `\mathrel`,
    /// `\mathop`, `\mathord`, `\mathopen`, `\mathclose`, `\mathpunct`. Layout is
    /// transparent; only the inter-atom spacing class changes.
    case classified(base: MathNode, atomClass: MathAtomClass)
    /// `\rule{w}{h}` — a solid filled rectangle (em lengths).
    case ruleBox(width: Double, height: Double)
    /// `\raisebox{shift}{…}` — the base shifted up by `shift` ems.
    case raised(base: MathNode, shift: Double)
    /// `\colorbox{bg}{…}` / `\fcolorbox{border}{bg}{…}` — a background-filled
    /// (and optionally framed) box. Colors are names/hex resolved at layout.
    case colorbox(base: MathNode, background: String, border: String?)
    /// Explicit spacing (multiples of an em quad).
    case space(Double)
    /// An accent over (or rule under) a base: \hat \vec \bar \overline …
    case accent(base: MathNode, accent: MathAccent)
    /// Generalized fraction: numerator over denominator with an optional
    /// rule and optional enclosing fences. `\frac` is rule-yes/no-fence;
    /// `\binom` is rule-no/paren-fence.
    case genfrac(top: MathNode, bottom: MathNode, hasRule: Bool, left: String, right: String)
    /// Material set over and/or under a base: \overset \underset \stackrel
    /// (plain), \overbrace \underbrace (a drawn brace), \xrightarrow
    /// \xleftarrow (a stretchy arrow). `over`/`under` are the annotations.
    case overUnder(base: MathNode, over: MathNode?, under: MathNode?, kind: MathOverUnder)
    /// A box/spacing decoration: \boxed (framed) or the \phantom family
    /// (reserve space, draw nothing).
    case decorated(base: MathNode, decoration: MathDecoration)
    /// A recolored subexpression: \color / \textcolor. The color is a name
    /// ("red", "teal") or "#rrggbb"; the renderer resolves it.
    case styled(base: MathNode, color: String)
    /// A subexpression forced into an explicit TeX style regardless of the
    /// ambient context: \dfrac / \tfrac, \dbinom / \tbinom, \genfrac's style
    /// argument, and \displaystyle / \textstyle / \scriptstyle /
    /// \scriptscriptstyle.
    case mathStyle(base: MathNode, style: MathStyle)
    /// A lone delimiter glyph at an explicit size: \big \Big \bigg \Bigg
    /// (+ `l`/`r`/`m`). `factor` is the target height as a multiple of the
    /// base size; `atomClass` is the spacing class the suffix selects.
    case bigDelimiter(glyph: String, factor: CGFloat, atomClass: MathAtomClass)
    /// Something we don't understand — rendered as literal marked source
    /// (the PRD rule: unknown input degrades, never errors).
    case unsupported(String)
}

extension MathNode {
    /// The node's direct children, in source order — the canonical traversal
    /// that every whole-tree analysis (support classification, diagnostics,
    /// depth checks) builds on, so a new node case touches one accessor
    /// instead of a hand-rolled switch per walk. Semantic per-case visitors
    /// (layout, `toLaTeX`, speech) still switch themselves.
    public var children: [MathNode] {
        switch self {
        case .symbol, .space, .functionName, .ruleBox, .bigDelimiter, .unsupported:
            return []
        case .row(let children):
            return children
        case .fraction(let n, let d), .cfrac(let n, let d, _):
            return [n, d]
        case .genfrac(let top, let bottom, _, _, _):
            return [top, bottom]
        case .radical(let degree, let radicand):
            return (degree.map { [$0] } ?? []) + [radicand]
        case .scripts(let base, let sub, let sup):
            return [base] + (sub.map { [$0] } ?? []) + (sup.map { [$0] } ?? [])
        case .delimited(_, let body, _):
            return [body]
        case .fenced(_, let segments):
            return segments
        case .matrix(let rows, _, _, _):
            return rows.flatMap { $0 }
        case .limitsOperator(let base), .classified(let base, _), .raised(let base, _),
             .colorbox(let base, _, _), .accent(let base, _), .decorated(let base, _),
             .styled(let base, _), .mathStyle(let base, _):
            return [base]
        case .overUnder(let base, let over, let under, _):
            return [base] + (over.map { [$0] } ?? []) + (under.map { [$0] } ?? [])
        }
    }
}

/// `\cfrac` denominator alignment (`\cfrac[l]`/`[r]`/`[c]`).
public enum CfracAlign: Hashable, Sendable { case left, center, right }

/// A `.decorated` treatment: a frame, reserved (invisible) space, or a
/// strike-through.
public enum MathDecoration: Hashable, Sendable {
    case boxed        // \boxed — stroked frame with padding
    case phantom      // reserve full box, draw nothing
    case hphantom     // reserve width only
    case vphantom     // reserve height only
    case cancel       // \cancel — a forward diagonal strike (╱)
    case bcancel      // \bcancel — a backward diagonal strike (╲)
    case xcancel      // \xcancel — both diagonals (╳)
    case negation     // \not — a short negation slash centered on the atom
    case smash        // \smash — keep width, report zero height & depth
    case rlap         // \mathrlap — zero width, content overhangs to the right
    case llap         // \mathllap — zero width, content overhangs to the left
    case clap         // \mathclap — zero width, content centered on the point
}

/// How an `.overUnder` decoration is drawn between base and annotations.
public enum MathOverUnder: Hashable, Sendable {
    case plain        // \overset / \underset / \stackrel — bare stacking
    case overbrace    // ⏞ drawn above the base
    case underbrace   // ⏟ drawn below the base
    case rightarrow   // stretchy → with the annotation(s) over/under it
    case leftarrow    // stretchy ←
    // The rest of the \x…arrow family, each with its own drawn head/shaft:
    case longRightArrow, longLeftArrow      // ⟹ ⟸ double-lined shafts
    case leftRightArrow                     // ↔ heads on both ends
    case hookRightArrow, hookLeftArrow      // ↪ ↩ hook at the tail
    case mapsToArrow                        // ↦ tail bar
    case rightHarpoonUp, rightHarpoonDown   // ⇀ ⇁ half-barb heads
    case leftHarpoonUp, leftHarpoonDown     // ↼ ↽
    case rightLeftHarpoons                  // ⇌ two opposed stacked harpoons
    // Arrows drawn OVER / UNDER the base itself, stretched to its width —
    // \overrightarrow{AB} (vectors), \overleftarrow, \overleftrightarrow, and
    // the \under… mirrors.
    case overRightArrow, overLeftArrow, overLeftRightArrow
    case underRightArrow, underLeftArrow, underLeftRightArrow
    // Square-bracket and parenthesis shapes over/under the base.
    case overbracket, underbracket, overparen, underparen
}

/// An accent decoration placed over (or, for rules, over/under) a base.
public enum MathAccent: Hashable, Sendable {
    case hat, check, tilde, bar, vec, dot, ddot, breve, mathring, acute, grave
    case widehat, widetilde, widecheck   // stretchy variants
    case overline, underline  // drawn rules, not glyphs

    /// The glyph drawn above the base (nil for the rule accents).
    public var glyph: String? {
        switch self {
        case .hat, .widehat: return "^"
        case .check, .widecheck: return "ˇ"
        case .tilde, .widetilde: return "~"
        case .bar: return "‾"
        case .vec: return "⃗"
        case .dot: return "˙"
        case .ddot: return "¨"
        case .breve: return "˘"
        case .mathring: return "˚"
        case .acute: return "´"
        case .grave: return "`"
        case .overline, .underline: return nil
        }
    }

    public var isStretchy: Bool { self == .widehat || self == .widetilde || self == .widecheck }

    /// Accents whose ONLY spelling is a combining mark (no spacing form).
    /// A lone combining mark drawn as a string gets shaping-dependent ink
    /// placement (CTLine may seat it at, before, or after the pen), which
    /// defeats attachment-point math — so these route through the glyph-ID
    /// variant path, whose metrics locate the ink exactly.
    public var combiningGlyph: String? {
        self == .vec ? "\u{20D7}" : nil   // combining right arrow above
    }

    /// The combining-mark spelling of a stretchy accent — the glyph whose
    /// MATH-table horizontal variants provide the wider drawn cuts.
    public var stretchyGlyph: String? {
        switch self {
        case .widehat: return "\u{0302}"     // combining circumflex
        case .widetilde: return "\u{0303}"   // combining tilde
        case .widecheck: return "\u{030C}"   // combining caron
        default: return nil
        }
    }

    public init?(command: String) {
        switch command {
        case "hat": self = .hat
        case "check": self = .check
        case "tilde": self = .tilde
        case "bar": self = .bar
        case "vec": self = .vec
        case "dot": self = .dot
        case "ddot": self = .ddot
        case "breve": self = .breve
        case "mathring": self = .mathring
        case "acute": self = .acute
        case "grave": self = .grave
        case "widehat": self = .widehat
        case "widetilde": self = .widetilde
        case "widecheck": self = .widecheck
        case "overline": self = .overline
        case "underline": self = .underline
        default: return nil
        }
    }
}

/// TeX atom classes drive inter-atom spacing (thin/medium/thick).
public enum MathAtomClass: Hashable, Sendable {
    case ordinary      // x, 1, α
    case largeOperator // ∑ ∫
    case binary        // + − ×
    case relation      // = ≤ →
    case opening       // ( [
    case closing       // ) ]
    case punctuation   // , ;
    case inner         // delimited subformulas and fractions (TeXbook p. 170)
}

extension MathAtomClass {
    /// Row/column index into the TeXbook p. 170 pair-spacing table
    /// (Ord Op Bin Rel Open Close Punct Inner).
    var spacingIndex: Int {
        switch self {
        case .ordinary: return 0
        case .largeOperator: return 1
        case .binary: return 2
        case .relation: return 3
        case .opening: return 4
        case .closing: return 5
        case .punctuation: return 6
        case .inner: return 7
        }
    }
}

public enum MathSymbolStyle: Hashable, Sendable {
    case italic   // variables
    case roman    // digits, function names, operators
    case bold     // \mathbf — upright bold
}

/// Column alignment for a `.matrix` grid.
public enum MathMatrixStyle: Hashable, Sendable {
    case centered   // matrix / pmatrix / bmatrix …
    case cases      // left-aligned columns (a `cases` list)
    case aligned    // alternating right/left, meeting at the `&` (aligned/align)
    case substack   // tight centered stack at script size (\substack)
    case array(ArraySpec)   // \begin{array}{l|c|r} … with per-column align + rules
}

/// The parsed column specification of an `array` environment: per-column
/// alignment, the vertical rules from `|` in the spec, and the horizontal
/// rules from `\hline` / `\cline`.
public struct ArraySpec: Hashable, Sendable {
    public enum Align: Hashable, Sendable { case left, center, right }
    /// Per-column alignment, in column order (`l`/`c`/`r`).
    public var alignments: [Align]
    /// Column-boundary indices (0…columns) carrying a vertical rule.
    public var columnRules: Set<Int>
    /// Horizontal rules across row boundaries.
    public var rowRules: [RowRule]

    /// A horizontal rule at row `boundary` (0 = top … rows = bottom), spanning
    /// columns `from…to`. `\hline` spans every column; `\cline{i-j}` spans i…j.
    public struct RowRule: Hashable, Sendable {
        public var boundary: Int
        public var fromColumn: Int
        public var toColumn: Int
        public init(boundary: Int, fromColumn: Int, toColumn: Int) {
            self.boundary = boundary; self.fromColumn = fromColumn; self.toColumn = toColumn
        }
    }

    public init(alignments: [Align], columnRules: Set<Int>, rowRules: [RowRule]) {
        self.alignments = alignments; self.columnRules = columnRules; self.rowRules = rowRules
    }
}
