// Linux rendering backend platform layer.
//
// On Apple platforms VinculumRender draws with CoreText/CoreGraphics and its
// types come from AppKit/UIKit. On Linux there is no CoreGraphics; this file
// vends what the shared code expects — `PlatformColor`, a Silica `CGContext`
// adapter with the Apple-CoreGraphics method names, PNG export — backed by
// Silica (Cairo/FontConfig). Modeled on MermaidKit's Linux backend.
//
// `canImport(SilicaCairo)` is true only where the Linux backend is linked
// (see Package.swift's platform-conditioned dependency), so it is the precise
// "Linux render backend available" signal.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
@_exported import Silica
@_exported import SilicaCairo
@_exported import Cairo
import VinculumLayout

// MARK: - Platform color

/// A fixed sRGB color (there is no appearance system on Linux).
public struct PlatformColor: Sendable, Hashable {
    public var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public func withAlphaComponent(_ a: CGFloat) -> PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: a)
    }
    public static let black = PlatformColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = PlatformColor(red: 1, green: 1, blue: 1, alpha: 1)
}

/// The color as a Silica `CGColor` — no sRGB/appearance resolution needed.
func resolvedCGColor(_ color: PlatformColor) -> Silica.CGColor {
    Silica.CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
}

// MARK: - CGContext adapter (Apple-CoreGraphics method names over Silica)

extension Silica.CGContext {
    func saveGState() { try? save() }
    func restoreGState() { try? restore() }
    func setLineJoin(_ join: CGLineJoin) { lineJoin = join }
    func setLineCap(_ cap: CGLineCap) { lineCap = cap }
    func setLineWidth(_ w: CGFloat) { lineWidth = w }
    func setFillColor(_ c: Silica.CGColor) { fillColor = c }
    func setStrokeColor(_ c: Silica.CGColor) { strokeColor = c }
    func fill(_ rect: CGRect) { beginPath(); addRect(rect); fillPath(using: .winding) }
}

// MARK: - PNG export

/// PNG-encoded bytes for a Cairo image surface, or nil. Silica's surface only
/// vends `writePNG(atPath:)`, so the bytes round-trip through a temp file.
func encodePNG(_ surface: Cairo.Surface) -> Data? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("vinculum-\(UUID().uuidString).png")
    surface.flush()
    surface.writePNG(atPath: url.path)
    defer { try? FileManager.default.removeItem(at: url) }
    return try? Data(contentsOf: url)
}
#endif
