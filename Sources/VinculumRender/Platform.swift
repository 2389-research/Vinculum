#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
/// `NSColor` on macOS, `UIColor` on UIKit platforms.
public typealias PlatformColor = NSColor
/// `NSFont` on macOS, `UIFont` on UIKit platforms.
public typealias PlatformFont = NSFont
/// `NSImage` on macOS, `UIImage` on UIKit platforms.
public typealias PlatformImage = NSImage
#else
import UIKit
/// `NSColor` on macOS, `UIColor` on UIKit platforms.
public typealias PlatformColor = UIColor
/// `NSFont` on macOS, `UIFont` on UIKit platforms.
public typealias PlatformFont = UIFont
/// `NSImage` on macOS, `UIImage` on UIKit platforms.
public typealias PlatformImage = UIImage
#endif

/// Resolves a possibly-dynamic platform color to a concrete `CGColor` for
/// CoreGraphics fills/strokes. On AppKit it converts through sRGB first so
/// catalog/dynamic `NSColor`s resolve to component form under the current
/// appearance (falling back to plain `cgColor` when conversion fails);
/// UIKit's `cgColor` already resolves against the current trait collection.
func resolvedCGColor(_ color: PlatformColor) -> CGColor {
    #if canImport(AppKit)
    return color.usingColorSpace(.sRGB)?.cgColor ?? color.cgColor
    #else
    return color.cgColor
    #endif
}
#endif
