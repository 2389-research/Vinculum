#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics
import VinculumLayout

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The public entry point: turns LaTeX into a baseline-aligned text attachment,
/// orchestrating measure → layout → render. Results are cached by content +
/// theme + size. Returns nil when the LaTeX contains unsupported commands so a
/// host keeps its own fallback and a document never breaks.
public enum MathImageRenderer {

    // A cached result. A `nil` image is a NEGATIVE entry — LaTeX we already know
    // is unsupported or degenerate — so re-projecting it (every keystroke, in a
    // live editor) is a dictionary hit instead of a re-parse forever.
    // INVARIANT: entries (image included) are immutable after publication to
    // the cache — the image is shared across threads, so all mutation
    // (isTemplate, accessibility) happens in buildEntry, pre-publication.
    private final class Entry {
        let image: PlatformImage?
        let descent: CGFloat
        let speech: String
        let cost: Int
        init(image: PlatformImage?, descent: CGFloat, speech: String, cost: Int) {
            self.image = image; self.descent = descent; self.speech = speech; self.cost = cost
        }
    }

    /// A rendered equation: the bitmap, the baseline descent (points below
    /// the baseline the image extends), and the spoken description for
    /// accessibility. What `VinculumLabel`/`MathView` build on.
    public struct RenderedMath {
        public let image: PlatformImage
        public let descent: CGFloat
        public let spokenDescription: String
    }

    // NSCache is documented thread-safe; the compiler can't prove it Sendable.
    // Bounded by count and by pixel-byte cost so a long session can't grow the
    // bitmap cache without limit (matters most on iOS at 3×).
    nonisolated(unsafe) private static let cache: NSCache<NSString, Entry> = {
        let c = NSCache<NSString, Entry>()
        c.countLimit = 512
        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()
    /// The rendered equation for the given LaTeX, or nil if unsupported —
    /// the image, its baseline descent, and the spoken description, all from
    /// the cache when warm.
    public static func rendered(
        latex: String,
        display: Bool,
        mathTheme: MathTheme,
        baseSize: CGFloat,
        font: MathFont = .latinModern
    ) -> RenderedMath? {
        // The key is fully determined by the arguments, so check the cache
        // BEFORE parsing — a hit (positive OR negative) costs no parse/layout.
        let key = "\(font.name)|\(display ? "D" : "I")|\(mathTheme.fingerprint)|\(baseSize)|\(latex)" as NSString
        let entry: Entry
        if let cached = cache.object(forKey: key) {
            entry = cached
        } else {
            entry = buildEntry(latex: latex, display: display, mathTheme: mathTheme,
                               baseSize: baseSize, font: font)
            cache.setObject(entry, forKey: key, cost: entry.cost)
        }
        guard let image = entry.image else { return nil }
        return RenderedMath(image: image, descent: entry.descent, spokenDescription: entry.speech)
    }

    /// An attachment string for the given LaTeX, or nil if unsupported.
    public static func attachmentString(
        latex: String,
        display: Bool,
        mathTheme: MathTheme,
        baseSize: CGFloat,
        font: MathFont = .latinModern
    ) -> NSAttributedString? {
        guard let r = rendered(latex: latex, display: display, mathTheme: mathTheme,
                               baseSize: baseSize, font: font) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = r.image
        let imageSize = r.image.size
        attachment.bounds = CGRect(x: 0, y: -r.descent, width: imageSize.width, height: imageSize.height)
        return NSAttributedString(attachment: attachment)
    }

    /// Parses, lays out and rasterizes on a cache miss. Returns a negative
    /// entry (nil image) for unsupported/degenerate input so it's remembered.
    private static func buildEntry(latex: String, display: Bool,
                                   mathTheme: MathTheme, baseSize: CGFloat,
                                   font: MathFont) -> Entry {
        let negative = Entry(image: nil, descent: 0, speech: latex, cost: 1)
        let node = MathParser.parse(latex)
        guard MathParser.isFullySupported(node) else { return negative }
        // Spoken-math description so VoiceOver reads the equation, not
        // "image" — computed once here (same tree that gets typeset) and
        // stamped on the image BEFORE the entry is published to the cache
        // (the cached image is shared across threads; see Entry).
        let speech = MathSpeech.describe(node)

        let engine = MathLayoutEngine.make(font: font, baseSize: display ? baseSize * 1.15 : baseSize)
        let scene = engine.layout(node, display: display)
        guard scene.width > 0, scene.height > 0 else { return negative }

        let padding: CGFloat = 2
        let size = CGSize(width: ceil(scene.width) + padding * 2,
                          height: ceil(scene.height) + padding * 2)
        let origin = CGPoint(x: padding, y: scene.descent + padding)
        // No explicit \color anywhere → a tintable template image, so selected
        // math inverts with the run and dark-mode adapts without a re-render.
        let isTemplate = !scene.hasExplicitColor

        #if canImport(AppKit)
        let appearance = NSAppearance(named: mathTheme.prefersDark ? .darkAqua : .aqua)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let draw = { MathSceneRenderer.draw(scene, theme: mathTheme, in: context, at: origin, font: font) }
            if let appearance { appearance.performAsCurrentDrawingAppearance(draw) } else { draw() }
            return true
        }
        image.isTemplate = isTemplate
        // Pre-publication accessibility stamp (see Entry invariant).
        image.accessibilityDescription = speech
        #else
        let renderer = UIGraphicsImageRenderer(size: size)
        var image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            // Pin the trait style so a dynamic UIColor ink resolves to the
            // variant matching the theme's canvas, not the ambient trait.
            let traits = UITraitCollection(userInterfaceStyle: mathTheme.prefersDark ? .dark : .light)
            traits.performAsCurrent {
                MathSceneRenderer.draw(scene, theme: mathTheme, in: context, at: origin, font: font)
            }
        }
        if isTemplate { image = image.withRenderingMode(.alwaysTemplate) }
        // UIImage's accessibility setters are MainActor-isolated and this
        // builder is deliberately nonisolated (hosts pre-render off-main),
        // so stamp only when already on main — still pre-publication, so
        // the cached image is never mutated after it's shared. The speech
        // always travels on RenderedMath/VinculumLabel/MathView regardless.
        if Thread.isMainThread {
            let stamped = image
            MainActor.assumeIsolated {
                stamped.isAccessibilityElement = true
                stamped.accessibilityLabel = speech
            }
        }
        #endif

        let cost = Int(size.width * size.height * 4) // ~bytes/point²; proportional
        return Entry(image: image, descent: scene.descent + padding, speech: speech, cost: cost)
    }
}
#endif
