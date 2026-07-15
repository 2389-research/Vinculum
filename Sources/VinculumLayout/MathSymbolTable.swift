import Foundation

/// The command → (glyph, atom class) data tables.
extension MathParser {

    static let functionNames: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "log", "ln", "lg", "exp", "min", "max", "sup",
        "inf", "lim", "det", "dim", "ker", "arg", "gcd", "deg", "mod",
        "Pr", "hom", "argmin", "argmax", "limsup", "liminf",
        "coth", "sech", "csch",
    ]

    static let symbolTable: [String: (String, MathAtomClass)] = [
        // Greek lowercase.
        "alpha": ("α", .ordinary), "beta": ("β", .ordinary), "gamma": ("γ", .ordinary),
        "delta": ("δ", .ordinary), "epsilon": ("ε", .ordinary), "varepsilon": ("ε", .ordinary),
        "zeta": ("ζ", .ordinary), "eta": ("η", .ordinary), "theta": ("θ", .ordinary),
        "vartheta": ("ϑ", .ordinary), "iota": ("ι", .ordinary), "kappa": ("κ", .ordinary),
        "lambda": ("λ", .ordinary), "mu": ("μ", .ordinary), "nu": ("ν", .ordinary),
        "xi": ("ξ", .ordinary), "pi": ("π", .ordinary), "varpi": ("ϖ", .ordinary),
        "rho": ("ρ", .ordinary), "sigma": ("σ", .ordinary), "varsigma": ("ς", .ordinary),
        "tau": ("τ", .ordinary), "upsilon": ("υ", .ordinary), "phi": ("φ", .ordinary),
        "varphi": ("φ", .ordinary), "chi": ("χ", .ordinary), "psi": ("ψ", .ordinary),
        "omega": ("ω", .ordinary),
        // Greek uppercase.
        "Gamma": ("Γ", .ordinary), "Delta": ("Δ", .ordinary), "Theta": ("Θ", .ordinary),
        "Lambda": ("Λ", .ordinary), "Xi": ("Ξ", .ordinary), "Pi": ("Π", .ordinary),
        "Sigma": ("Σ", .ordinary), "Upsilon": ("Υ", .ordinary), "Phi": ("Φ", .ordinary),
        "Psi": ("Ψ", .ordinary), "Omega": ("Ω", .ordinary),
        // Large operators.
        "sum": ("∑", .largeOperator), "prod": ("∏", .largeOperator),
        "int": ("∫", .largeOperator), "iint": ("∬", .largeOperator),
        "iiint": ("∭", .largeOperator), "iiiint": ("⨌", .largeOperator),
        "oint": ("∮", .largeOperator), "oiint": ("∯", .largeOperator),
        "oiiint": ("∰", .largeOperator),
        "bigcup": ("⋃", .largeOperator), "bigcap": ("⋂", .largeOperator),
        "coprod": ("∐", .largeOperator), "biguplus": ("⨄", .largeOperator),
        "bigsqcup": ("⨆", .largeOperator), "bigvee": ("⋁", .largeOperator),
        "bigwedge": ("⋀", .largeOperator), "bigoplus": ("⨁", .largeOperator),
        "bigotimes": ("⨂", .largeOperator), "bigodot": ("⨀", .largeOperator),
        // Logic / misc additions.
        "land": ("∧", .binary), "lor": ("∨", .binary),
        "gets": ("←", .relation), "rightleftharpoons": ("⇌", .relation),
        "triangleq": ("≜", .relation), "coloneqq": ("≔", .relation),
        "colon": (":", .punctuation), "bigstar": ("★", .ordinary),
        // The amsmath \dots* variants are ellipses too → Inner, like \ldots.
        "dotsb": ("⋯", .inner), "dotsc": ("…", .inner), "dotsm": ("⋯", .inner),
        "dotsi": ("⋯", .inner), "dotso": ("…", .inner),
        // ── Batch 11 symbol sweep ──────────────────────────────────────────
        // Relations (extended).
        "leqslant": ("⩽", .relation), "geqslant": ("⩾", .relation), "eqsim": ("≂", .relation),
        "approxeq": ("≊", .relation), "backsim": ("∽", .relation), "backsimeq": ("⋍", .relation),
        "lessapprox": ("⪅", .relation), "gtrapprox": ("⪆", .relation), "lll": ("⋘", .relation),
        "ggg": ("⋙", .relation), "precsim": ("≾", .relation), "succsim": ("≿", .relation),
        "leqq": ("≦", .relation), "geqq": ("≧", .relation), "subseteqq": ("⫅", .relation),
        "supseteqq": ("⫆", .relation), "Subset": ("⋐", .relation), "Supset": ("⋑", .relation),
        "frown": ("⌢", .relation), "smile": ("⌣", .relation), "vDash": ("⊨", .relation),
        "Vdash": ("⊩", .relation), "Vvdash": ("⊪", .relation), "multimap": ("⊸", .relation),
        "risingdotseq": ("≓", .relation), "fallingdotseq": ("≒", .relation), "circeq": ("≗", .relation),
        "trianglelefteq": ("⊴", .relation), "trianglerighteq": ("⊵", .relation),
        "vartriangleleft": ("⊲", .relation), "vartriangleright": ("⊳", .relation),
        "bumpeq": ("≏", .relation), "Bumpeq": ("≎", .relation), "pitchfork": ("⋔", .relation),
        "shortmid": ("∣", .relation), "shortparallel": ("∥", .relation), "thickapprox": ("≈", .relation),
        "thicksim": ("∼", .relation), "eqcirc": ("≖", .relation), "doteqdot": ("≑", .relation),
        // Negated relations.
        "nleq": ("≰", .relation), "ngeq": ("≱", .relation), "nless": ("≮", .relation), "ngtr": ("≯", .relation),
        "nsim": ("≁", .relation), "ncong": ("≇", .relation), "nprec": ("⊀", .relation), "nsucc": ("⊁", .relation),
        "nvdash": ("⊬", .relation), "nvDash": ("⊭", .relation), "nVdash": ("⊮", .relation), "nVDash": ("⊯", .relation),
        "npreceq": ("⋠", .relation), "nsucceq": ("⋡", .relation), "lneq": ("⪇", .relation), "gneq": ("⪈", .relation),
        "lneqq": ("≨", .relation), "gneqq": ("≩", .relation), "subsetneqq": ("⫋", .relation),
        "supsetneqq": ("⫌", .relation), "lnsim": ("⋦", .relation), "gnsim": ("⋧", .relation),
        "precnsim": ("⋨", .relation), "succnsim": ("⋩", .relation), "ntriangleright": ("⋫", .relation),
        "ntrianglelefteq": ("⋬", .relation), "ntrianglerighteq": ("⋭", .relation),
        // Arrows (extended).
        "rightsquigarrow": ("⇝", .relation), "leadsto": ("⇝", .relation), "dashrightarrow": ("⇢", .relation),
        "dashleftarrow": ("⇠", .relation), "twoheadrightarrow": ("↠", .relation), "twoheadleftarrow": ("↞", .relation),
        "rightarrowtail": ("↣", .relation), "leftarrowtail": ("↢", .relation), "circlearrowleft": ("↺", .relation),
        "circlearrowright": ("↻", .relation), "curvearrowright": ("↷", .relation), "curvearrowleft": ("↶", .relation),
        "leftrightarrows": ("⇆", .relation), "rightleftarrows": ("⇄", .relation), "upuparrows": ("⇈", .relation),
        "downdownarrows": ("⇊", .relation), "Lleftarrow": ("⇚", .relation), "Rrightarrow": ("⇛", .relation),
        "longmapsto": ("⟼", .relation), "nrightarrow": ("↛", .relation), "nleftarrow": ("↚", .relation),
        "nRightarrow": ("⇏", .relation), "nLeftarrow": ("⇍", .relation), "nleftrightarrow": ("↮", .relation),
        "nLeftrightarrow": ("⇎", .relation), "looparrowright": ("↬", .relation), "looparrowleft": ("↫", .relation),
        "rightrightarrows": ("⇉", .relation), "leftleftarrows": ("⇇", .relation), "longleftrightarrow": ("⟷", .relation),
        "Longleftrightarrow": ("⟺", .relation), "mapsfrom": ("↤", .relation),
        // Harpoons.
        "leftharpoonup": ("↼", .relation), "leftharpoondown": ("↽", .relation), "rightharpoonup": ("⇀", .relation),
        "rightharpoondown": ("⇁", .relation), "upharpoonright": ("↾", .relation), "upharpoonleft": ("↿", .relation),
        "downharpoonright": ("⇂", .relation), "downharpoonleft": ("⇃", .relation), "leftrightharpoons": ("⇋", .relation),
        // Binary operators (extended).
        "ltimes": ("⋉", .binary), "rtimes": ("⋊", .binary), "leftthreetimes": ("⋋", .binary),
        "rightthreetimes": ("⋌", .binary), "Cap": ("⋒", .binary), "Cup": ("⋓", .binary),
        "barwedge": ("⊼", .binary), "veebar": ("⊻", .binary), "doublebarwedge": ("⩞", .binary),
        "curlywedge": ("⋏", .binary), "curlyvee": ("⋎", .binary), "boxdot": ("⊡", .binary),
        "boxminus": ("⊟", .binary), "circledast": ("⊛", .binary), "circledcirc": ("⊚", .binary),
        "circleddash": ("⊝", .binary), "dotplus": ("∔", .binary), "divideontimes": ("⋇", .binary),
        "lessdot": ("⋖", .binary), "gtrdot": ("⋗", .binary), "intercal": ("⊺", .binary),
        "smallsetminus": ("∖", .binary),
        // Letterlike / ordinary (extended).
        "hslash": ("ℏ", .ordinary), "Bbbk": ("𝕜", .ordinary), "digamma": ("ϝ", .ordinary),
        "varkappa": ("ϰ", .ordinary), "varrho": ("ϱ", .ordinary), "lozenge": ("◊", .ordinary),
        "blacklozenge": ("⧫", .ordinary), "blacktriangle": ("▲", .ordinary), "blacktriangledown": ("▼", .ordinary),
        "blacktriangleleft": ("◀", .ordinary), "blacktriangleright": ("▶", .ordinary), "vartriangle": ("△", .ordinary),
        "triangledown": ("▽", .ordinary), "measuredangle": ("∡", .ordinary), "sphericalangle": ("∢", .ordinary),
        "backprime": ("‵", .ordinary), "eth": ("ð", .ordinary), "beth": ("ℶ", .ordinary), "gimel": ("ℷ", .ordinary),
        "daleth": ("ℸ", .ordinary), "Finv": ("Ⅎ", .ordinary), "Game": ("⅁", .ordinary), "circledS": ("Ⓢ", .ordinary),
        "Diamond": ("◇", .ordinary), "Box": ("□", .ordinary),
        // Binary operators.
        "pm": ("±", .binary), "mp": ("∓", .binary), "times": ("×", .binary),
        "div": ("÷", .binary), "cdot": ("⋅", .binary), "ast": ("∗", .binary),
        "cup": ("∪", .binary), "cap": ("∩", .binary), "setminus": ("∖", .binary),
        "oplus": ("⊕", .binary), "otimes": ("⊗", .binary), "wedge": ("∧", .binary),
        "vee": ("∨", .binary), "circ": ("∘", .binary),
        // Relations.
        "leq": ("≤", .relation), "le": ("≤", .relation), "geq": ("≥", .relation),
        "ge": ("≥", .relation), "neq": ("≠", .relation), "ne": ("≠", .relation),
        "equiv": ("≡", .relation), "approx": ("≈", .relation), "sim": ("∼", .relation),
        "simeq": ("≃", .relation), "cong": ("≅", .relation), "propto": ("∝", .relation),
        "subset": ("⊂", .relation), "supset": ("⊃", .relation),
        "subseteq": ("⊆", .relation), "supseteq": ("⊇", .relation),
        "in": ("∈", .relation), "ni": ("∋", .relation), "notin": ("∉", .relation),
        "to": ("→", .relation), "rightarrow": ("→", .relation),
        "leftarrow": ("←", .relation), "Rightarrow": ("⇒", .relation),
        "Leftarrow": ("⇐", .relation), "leftrightarrow": ("↔", .relation),
        "Leftrightarrow": ("⇔", .relation), "mapsto": ("↦", .relation),
        "ll": ("≪", .relation), "gg": ("≫", .relation),
        "perp": ("⊥", .relation), "parallel": ("∥", .relation),
        "mid": ("∣", .relation),
        // Ordinary symbols.
        "infty": ("∞", .ordinary), "partial": ("∂", .ordinary),
        "nabla": ("∇", .ordinary), "forall": ("∀", .ordinary),
        "exists": ("∃", .ordinary), "nexists": ("∄", .ordinary),
        "emptyset": ("∅", .ordinary), "varnothing": ("∅", .ordinary),
        "hbar": ("ℏ", .ordinary), "ell": ("ℓ", .ordinary),
        "Re": ("ℜ", .ordinary), "Im": ("ℑ", .ordinary),
        "aleph": ("ℵ", .ordinary), "prime": ("′", .ordinary),
        "angle": ("∠", .ordinary), "degree": ("°", .ordinary),
        "neg": ("¬", .ordinary), "lnot": ("¬", .ordinary),
        // Plain TeX defines \ldots/\cdots/\ddots as \mathinner boxes, so the
        // dots are Inner atoms — that is what puts a thin space on BOTH sides
        // in f(x_1,\ldots,x_n) (TeXbook p. 172). \vdots is a plain vbox: Ord.
        "dots": ("…", .inner), "ldots": ("…", .inner),
        "cdots": ("⋯", .inner), "vdots": ("⋮", .ordinary), "ddots": ("⋱", .inner),
        "therefore": ("∴", .relation), "because": ("∵", .relation),
        // Standalone delimiters (also usable outside \left…\right).
        "langle": ("⟨", .opening), "rangle": ("⟩", .closing),
        "lceil": ("⌈", .opening), "rceil": ("⌉", .closing),
        "lfloor": ("⌊", .opening), "rfloor": ("⌋", .closing),
        "lbrace": ("{", .opening), "rbrace": ("}", .closing),
        "lbrack": ("[", .opening), "rbrack": ("]", .closing),
        "lvert": ("|", .opening), "rvert": ("|", .closing),
        "vert": ("|", .ordinary), "lVert": ("‖", .opening), "rVert": ("‖", .closing),
        "Vert": ("‖", .ordinary), "backslash": ("\\", .ordinary),
        "uparrow": ("↑", .relation), "downarrow": ("↓", .relation),
        "updownarrow": ("↕", .relation), "Uparrow": ("⇑", .relation),
        "Downarrow": ("⇓", .relation), "nearrow": ("↗", .relation),
        "searrow": ("↘", .relation), "swarrow": ("↙", .relation),
        "nwarrow": ("↖", .relation), "hookrightarrow": ("↪", .relation),
        "hookleftarrow": ("↩", .relation), "longrightarrow": ("⟶", .relation),
        "longleftarrow": ("⟵", .relation), "Longrightarrow": ("⟹", .relation),
        "iff": ("⟺", .relation), "implies": ("⟹", .relation), "impliedby": ("⟸", .relation),
        // More binary / relation / ordinary symbols KaTeX users reach for.
        "star": ("⋆", .binary), "bullet": ("•", .binary), "dagger": ("†", .binary),
        "ddagger": ("‡", .binary), "amalg": ("⨿", .binary), "sqcup": ("⊔", .binary),
        "sqcap": ("⊓", .binary), "uplus": ("⊎", .binary), "odot": ("⊙", .binary),
        "ominus": ("⊖", .binary), "oslash": ("⊘", .binary), "boxplus": ("⊞", .binary),
        "boxtimes": ("⊠", .binary), "triangleleft": ("◁", .binary), "triangleright": ("▷", .binary),
        "wr": ("≀", .binary), "diamond": ("⋄", .binary), "bigtriangleup": ("△", .binary),
        "bigtriangledown": ("▽", .binary),
        "prec": ("≺", .relation), "succ": ("≻", .relation), "preceq": ("⪯", .relation),
        "succeq": ("⪰", .relation), "models": ("⊨", .relation), "vdash": ("⊢", .relation),
        "dashv": ("⊣", .relation), "asymp": ("≍", .relation), "doteq": ("≐", .relation),
        "bowtie": ("⋈", .relation), "sqsubseteq": ("⊑", .relation), "sqsupseteq": ("⊒", .relation),
        "sqsubset": ("⊏", .relation), "sqsupset": ("⊐", .relation), "ntriangleleft": ("⋪", .relation),
        "gtrsim": ("≳", .relation), "lesssim": ("≲", .relation), "gtrless": ("≷", .relation),
        "lessgtr": ("≶", .relation), "between": ("≬", .relation), "nmid": ("∤", .relation),
        "nparallel": ("∦", .relation), "nsubseteq": ("⊈", .relation), "nsupseteq": ("⊉", .relation),
        "supsetneq": ("⊋", .relation), "subsetneq": ("⊊", .relation),
        "top": ("⊤", .ordinary), "bot": ("⊥", .ordinary), "flat": ("♭", .ordinary),
        "sharp": ("♯", .ordinary), "natural": ("♮", .ordinary), "clubsuit": ("♣", .ordinary),
        "diamondsuit": ("♢", .ordinary), "heartsuit": ("♡", .ordinary), "spadesuit": ("♠", .ordinary),
        "surd": ("√", .ordinary), "imath": ("ı", .ordinary), "jmath": ("ȷ", .ordinary),
        "wp": ("℘", .ordinary), "complement": ("∁", .ordinary), "triangle": ("△", .ordinary),
        "square": ("□", .ordinary), "blacksquare": ("■", .ordinary), "checkmark": ("✓", .ordinary),
        "circledR": ("®", .ordinary), "maltese": ("✠", .ordinary), "mho": ("℧", .ordinary),
        // Escaped literals.
        "{": ("{", .opening), "}": ("}", .closing),
        "|": ("‖", .ordinary),
        "$": ("$", .ordinary), "%": ("%", .ordinary), "&": ("&", .ordinary),
        "#": ("#", .ordinary),
    ]

    /// Reverse of `symbolTable`: glyph → atom class, so a directly-typed
    /// Unicode math character is classed like its command spelling.
    static let glyphAtomClass: [String: MathAtomClass] = {
        var map: [String: MathAtomClass] = [:]
        for (_, value) in symbolTable {
            // First writer wins; classes for a given glyph are consistent
            // in the table (all arrows relation, all operators binary, …).
            if map[value.0] == nil { map[value.0] = value.1 }
        }
        return map
    }()
}
