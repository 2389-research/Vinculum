#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import CoreGraphics
import VinculumLayout

/// An OpenType math font plus its parsed MATH-table data. Five fonts are
/// bundled — Latin Modern (the default), TeX Gyre Termes, TeX Gyre Pagella,
/// STIX Two, and the sans-serif Fira Math — and any user OTF with a MATH
/// table loads via `init?(url:)`.
///
/// Everything a font contributes to layout is parsed eagerly at load (so
/// instances are immutable and freely `Sendable`): the 56 `MathConstants`,
/// per-glyph typography (italic corrections, accent attachments, cut-in
/// kerns — STIX Two ships kern data for 233 glyphs), and the variant
/// ladders + glyph assemblies behind stretchy delimiters.
public final class MathFont: @unchecked Sendable {

    /// Stable identity: keys render caches and names the font in goldens.
    public let name: String
    /// nil when the resource failed to load — consumers fall back to system
    /// fonts and preset metrics, so rendering degrades rather than fails.
    let cgFont: CGFont?
    /// MATH-table data, parsed once. `constants` falls back to the Latin
    /// Modern preset so layout never lacks metrics.
    public let constants: MathFontConstants
    let glyphInfo: MathGlyphInfo?
    let variantsData: MathVariantsData?
    let scriptVariants: MathScriptVariants?
    let rawGsubTable: Data?
    /// The raw MATH table bytes (fixture extraction, diagnostics).
    let rawMathTable: Data?

    // MARK: - Bundled fonts

    public static let latinModern = MathFont(resource: "latinmodern-math")
    public static let termes = MathFont(resource: "texgyretermes-math")
    public static let pagella = MathFont(resource: "texgyrepagella-math")
    public static let stixTwo = MathFont(resource: "stixtwo-math")
    /// The sans-serif option — visibly distinct from the four serif faces;
    /// pairs with SF/Helvetica-style UI text.
    public static let firaMath = MathFont(resource: "firamath")
    public static var bundled: [MathFont] { [latinModern, termes, pagella, stixTwo, firaMath] }

    public var isAvailable: Bool { cgFont != nil }

    // MARK: - Loading

    private convenience init(resource: String) {
        let url = Bundle.module.url(forResource: resource, withExtension: "otf")
        self.init(fontURL: url, name: resource)
    }

    /// Loads a user-supplied OTF math font. Returns nil when the file can't
    /// be read as a font or carries no MATH table.
    public convenience init?(url: URL, name: String? = nil) {
        self.init(fontURL: url, name: name ?? url.deletingPathExtension().lastPathComponent)
        guard cgFont != nil, rawMathTable != nil else { return nil }
    }

    private init(fontURL: URL?, name: String) {
        self.name = name
        // A CGFont is immutable and safe to read from any thread. Loaded via
        // CGDataProvider (not CTFontCreateWithName) so the full glyph
        // repertoire — including unencoded math variants — is available.
        let font: CGFont? = {
            guard let fontURL,
                  let data = try? Data(contentsOf: fontURL),
                  let provider = CGDataProvider(data: data as CFData) else { return nil }
            return CGFont(provider)
        }()
        self.cgFont = font
        let table = font?.table(for: 0x4D41_5448 /* 'MATH' */).map { $0 as Data }
        self.rawMathTable = table
        let upm = font.map { Int($0.unitsPerEm) } ?? 0
        self.constants = table.flatMap { MathTableParser.constants(from: $0, unitsPerEm: upm) }
            ?? .latinModern
        self.glyphInfo = table.flatMap { MathTableParser.glyphInfo(from: $0, unitsPerEm: upm) }
        self.variantsData = table.flatMap { MathTableParser.variants(from: $0, unitsPerEm: upm) }
        // GSUB carries the `ssty` optical-script variants (script/scriptscript
        // redraws). Parsed once at load, like MATH.
        let gsub = font?.table(for: 0x4753_5542 /* 'GSUB' */).map { $0 as Data }
        self.rawGsubTable = gsub
        self.scriptVariants = gsub.map { GsubScriptStyleParser.parse(Array($0)) }
    }

    // MARK: - Sized CTFonts

    // A tiny size→CTFont memo. Measurement and drawing ask for a handful of
    // sizes over and over; CTFontCreateWithGraphicsFont isn't free.
    nonisolated(unsafe) private var ctFontCache: [CGFloat: CTFont] = [:]
    private let ctFontLock = NSLock()

    /// The sized CTFont — public so a CUSTOM renderer of the public
    /// `MathScene` IR can resolve `.glyph(id:)` elements (draw them with
    /// `CTFontDrawGlyphs` against this font; reset the context text matrix
    /// first). Cached per size.
    public func ctFont(size: CGFloat) -> CTFont? {
        guard let cgFont else { return nil }
        ctFontLock.lock(); defer { ctFontLock.unlock() }
        if let cached = ctFontCache[size] { return cached }
        // Bounded: a host animating sizes would otherwise grow this without
        // limit (script/display factors multiply the distinct sizes seen).
        if ctFontCache.count >= 256 { ctFontCache.removeAll(keepingCapacity: true) }
        let font = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
        ctFontCache[size] = font
        return font
    }

    /// The glyph ID for a single-scalar string, or nil.
    func glyphID(for text: String, size: CGFloat) -> UInt16? {
        guard text.unicodeScalars.count == 1, let ctFont = ctFont(size: size) else { return nil }
        var utf16 = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count),
              let id = glyphs.first, id != 0 else { return nil }
        return UInt16(id)
    }
}
#endif
