#if canImport(AppKit) || canImport(UIKit)
import XCTest
import Foundation
@testable import VinculumRender

/// `MathImageRenderer`'s `NSCache` is bounded by `totalCostLimit` (32 MB), and
/// that bound is only meaningful if the per-entry cost tracks the entry's real
/// pixel buffer.
///
/// The regression this guards (#5): the cost was point-area × 4, ignoring the
/// backing scale. On iOS the renderer uses the screen scale, so the buffer holds
/// `scale²` more bytes — 9× on a 3× device, precisely the case the cache comment
/// singles out. A 32 MB limit could therefore retain ~288 MB of real bitmaps.
final class MathImageCacheCostTests: XCTestCase {

    func testCacheCostIsPixelSpaceNotPointSpace() {
        let size = CGSize(width: 100, height: 50)
        let onex = MathImageRenderer.cacheCost(size: size, pixelScale: 1)
        XCTAssertEqual(onex, 100 * 50 * 4, "1× is plain RGBA point area")

        // The point-space bug: these would all equal `onex`.
        XCTAssertEqual(MathImageRenderer.cacheCost(size: size, pixelScale: 2), onex * 4,
                       "a 2× buffer holds 4× the bytes")
        XCTAssertEqual(MathImageRenderer.cacheCost(size: size, pixelScale: 3), onex * 9,
                       "a 3× buffer holds 9× the bytes — the case totalCostLimit must bound")
    }

    func testCacheCostGrowsWithArea() {
        let small = MathImageRenderer.cacheCost(size: CGSize(width: 10, height: 10), pixelScale: 2)
        let large = MathImageRenderer.cacheCost(size: CGSize(width: 20, height: 20), pixelScale: 2)
        XCTAssertEqual(large, small * 4, "cost is proportional to area at a fixed scale")
    }
}
#endif
