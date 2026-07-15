#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The full color surface a native math render needs — the sole external
/// seam between the math typesetter and its host, mirroring MermaidKit's
/// `DiagramTheme`. Math is monochrome ink on a transparent attachment, so
/// the seam is far smaller than a diagram's: just the stroke/glyph color
/// and the appearance it targets.
///
/// This is the one type a future standalone math package would export for
/// hosts to build (or use the presets); Quoin adapts its design system
/// through `Theme.mathTheme`. Keeping this seam minimal is deliberate — the
/// smaller the surface, the more stable it stays across the extraction.
public struct MathTheme: Sendable {
    /// The single color for every stroke and glyph (fractions rules,
    /// radicals, braces, arrows, text). `\color` overrides it per-subtree
    /// at the typesetter, not here.
    public let ink: PlatformColor
    /// Whether the render targets a dark canvas. Drives the appearance the
    /// renderer pins while rasterizing (so dynamic inks resolve to the
    /// variant that matches the canvas) and the cache key.
    public let prefersDark: Bool

    /// A stable digest of the resolved ink + appearance — the render-cache
    /// key component, so two themes that differ only in ink can never serve
    /// each other's cached renders (mirrors `DiagramTheme.fingerprint`).
    /// Computed once, with the ink resolved under the SAME appearance the
    /// renderer pins while drawing.
    public let fingerprint: String

    public init(ink: PlatformColor, prefersDark: Bool) {
        self.ink = ink
        self.prefersDark = prefersDark
        self.fingerprint = Self.makeFingerprint(ink: ink, prefersDark: prefersDark)
    }

    /// Black ink on a light canvas — for hosts without their own theme.
    public static let light = MathTheme(ink: .black, prefersDark: false)
    /// White ink on a dark canvas.
    public static let dark = MathTheme(ink: .white, prefersDark: true)

    private static func makeFingerprint(ink: PlatformColor, prefersDark: Bool) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        #if canImport(AppKit)
        let resolve = {
            ink.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        if let appearance = NSAppearance(named: prefersDark ? .darkAqua : .aqua) {
            appearance.performAsCurrentDrawingAppearance { _ = resolve() }
        } else {
            _ = resolve()
        }
        #else
        ink.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func q(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return "\(prefersDark ? "D" : "L")|\(q(r)),\(q(g)),\(q(b)),\(q(a))"
    }
}
#endif
