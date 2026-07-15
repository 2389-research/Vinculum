import Foundation

/// Maps ASCII letters/digits to their Unicode Mathematical Alphanumeric
/// Symbols codepoints (blackboard 𝔸, script 𝒜, fraktur 𝔞, sans 𝗔, mono 𝚊,
/// bold-italic 𝑨). The block is contiguous per style with a handful of
/// pre-Unicode "Letterlike Symbols" holes (ℝ ℂ ℋ …) punched out — those
/// are the exception tables here. CoreText resolves the codepoints through
/// STIX Two / Apple Symbols, so no bundled font is required.
enum MathAlphabet {
    case blackboard   // \mathbb
    case script       // \mathcal, \mathscr
    case fraktur      // \mathfrak
    case sansSerif    // \mathsf
    case monospace    // \mathtt
    case boldItalic   // \boldsymbol, \bm

    init?(command: String) {
        switch command {
        case "mathbb": self = .blackboard
        case "mathcal", "mathscr": self = .script
        case "mathfrak": self = .fraktur
        case "mathsf": self = .sansSerif
        case "mathtt": self = .monospace
        case "boldsymbol", "bm": self = .boldItalic
        default: return nil
        }
    }

    /// The styled glyph for a single ASCII letter/digit, or nil when this
    /// alphabet has no variant for it (e.g. script has no digits) so the
    /// caller keeps the original character.
    func glyph(for ch: Character) -> String? {
        if let hole = exceptions[ch] { return hole }
        guard let scalar = ch.unicodeScalars.first,
              ch.unicodeScalars.count == 1 else { return nil }
        let v = scalar.value
        let upper: ClosedRange<UInt32> = 0x41...0x5A   // A–Z
        let lower: ClosedRange<UInt32> = 0x61...0x7A   // a–z
        let digit: ClosedRange<UInt32> = 0x30...0x39   // 0–9
        let base: UInt32
        let offset: UInt32
        if upper.contains(v) {
            guard let b = upperBase else { return nil }
            base = b; offset = v - 0x41
        } else if lower.contains(v) {
            guard let b = lowerBase else { return nil }
            base = b; offset = v - 0x61
        } else if digit.contains(v) {
            guard let b = digitBase else { return nil }
            base = b; offset = v - 0x30
        } else {
            return nil
        }
        return UnicodeScalar(base + offset).map(String.init)
    }

    private var upperBase: UInt32? {
        switch self {
        case .blackboard: return 0x1D538
        case .script:     return 0x1D49C
        case .fraktur:    return 0x1D504
        case .sansSerif:  return 0x1D5A0
        case .monospace:  return 0x1D670
        case .boldItalic: return 0x1D468
        }
    }

    private var lowerBase: UInt32? {
        switch self {
        case .blackboard: return 0x1D552
        case .script:     return 0x1D4B6
        case .fraktur:    return 0x1D51E
        case .sansSerif:  return 0x1D5BA
        case .monospace:  return 0x1D68A
        case .boldItalic: return 0x1D482
        }
    }

    private var digitBase: UInt32? {
        switch self {
        case .blackboard: return 0x1D7D8
        case .sansSerif:  return 0x1D7E2
        case .monospace:  return 0x1D7F6
        case .boldItalic: return 0x1D7CE   // bold digits (no italic digits exist)
        case .script, .fraktur: return nil // no digit variants
        }
    }

    /// The Letterlike-Symbols holes: codepoints that were encoded before
    /// the contiguous math block and are therefore missing from it.
    private var exceptions: [Character: String] {
        switch self {
        case .blackboard:
            return ["C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ"]
        case .script:
            return ["B": "ℬ", "E": "ℰ", "F": "ℱ", "H": "ℋ", "I": "ℐ",
                    "L": "ℒ", "M": "ℳ", "R": "ℛ",
                    "e": "ℯ", "g": "ℊ", "o": "ℴ"]
        case .fraktur:
            return ["C": "ℭ", "H": "ℌ", "I": "ℑ", "R": "ℜ", "Z": "ℨ"]
        case .sansSerif, .monospace, .boldItalic:
            return [:]
        }
    }
}
