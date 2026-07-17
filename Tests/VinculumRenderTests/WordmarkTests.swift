#if canImport(AppKit)
import XCTest
import AppKit
import Foundation
@testable import VinculumRender

/// The README and the website lead with a wordmark that claims to be
/// `\sqrt{\mathrm{Vinculum}}` **typeset by Vinculum itself**.
///
/// That claim was true exactly once — when the PNG was generated and committed —
/// and then nothing checked it again. If the engine stopped producing that image
/// tomorrow, the front page would keep asserting it and no test would notice.
/// This makes the marketing checkable: re-render the wordmark and compare it to
/// the committed asset. If they diverge, CI goes red and someone re-blesses on
/// purpose (`ComparisonGenerator.testGenerateWordmark`).
///
/// Compared as a size-normalized ink signature rather than pixels: the point is
/// "the engine still draws this mark", which must not go red because a CI runner's
/// CoreText anti-aliases a shade differently or renders at a different scale.
@MainActor
final class WordmarkTests: XCTestCase {

    private static let gridW = 24, gridH = 6
    private static let cellTolerance = 1
    private static let maxBadCellRatio = 0.05

    /// RGBA8 pixels for an image (premultipliedLast → bytes are R,G,B,A).
    private func rgba(_ image: NSImage) -> (px: [UInt8], w: Int, h: Int)? {
        var rect = CGRect(origin: .zero, size: image.size)
        // Also forces the AppKit path's deferred draw block to actually run.
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (buf, w, h) : nil
    }

    /// Ink coverage over the image's ink bounding box, as a gridW×gridH grid of
    /// 0–9. Trimming to the ink box makes it independent of padding and scale.
    private func inkSignature(_ px: [UInt8], _ w: Int, _ h: Int) -> [Int]? {
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where alpha(x, y) > 32 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }   // no ink at all
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        var sums = [Int](repeating: 0, count: Self.gridW * Self.gridH)
        var counts = sums
        for y in minY...maxY {
            for x in minX...maxX {
                let gx = min(Self.gridW - 1, (x - minX) * Self.gridW / bw)
                let gy = min(Self.gridH - 1, (y - minY) * Self.gridH / bh)
                let i = gy * Self.gridW + gx
                if alpha(x, y) > 32 { sums[i] += 1 }
                counts[i] += 1
            }
        }
        return (0..<sums.count).map { counts[$0] == 0 ? 0 : min(9, sums[$0] * 10 / counts[$0]) }
    }

    /// Renders the light wordmark exactly as `ComparisonGenerator` does.
    private func renderWordmark() -> NSImage? {
        NSApp?.appearance = NSAppearance(named: .aqua)
        let cobalt = NSColor(srgbRed: 0x31/255, green: 0x5C/255, blue: 0x9B/255, alpha: 1)
        let latex = "\\sqrt{\\color{#18212B}{\\mathrm{Vinculum}}}"
        return MathImageRenderer.rendered(latex: latex, display: true,
                                          mathTheme: MathTheme(ink: cobalt, prefersDark: false),
                                          baseSize: 44, font: .stixTwo)?.image
    }

    private func committedWordmark() -> NSImage? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/assets/wordmark-light.png")
        return NSImage(contentsOf: url)
    }

    func testWordmarkRecipeStillRenders() throws {
        // The claim's first half: the engine can still typeset \sqrt{Vinculum}.
        let image = try XCTUnwrap(renderWordmark(), "the wordmark LaTeX no longer renders")
        let (px, w, h) = try XCTUnwrap(rgba(image))
        let sig = try XCTUnwrap(inkSignature(px, w, h), "the wordmark rendered no ink")
        XCTAssertTrue(sig.contains { $0 > 0 })
    }

    func testCommittedWordmarkStillMatchesWhatTheEngineRenders() throws {
        // The claim's second half: the image shipped on the README and the site is
        // what today's engine produces — not a fossil.
        let freshImage = try XCTUnwrap(renderWordmark(), "the wordmark LaTeX no longer renders")
        let (fpx, fw, fh) = try XCTUnwrap(rgba(freshImage))
        let fresh = try XCTUnwrap(inkSignature(fpx, fw, fh), "fresh render has no ink")

        let assetImage = try XCTUnwrap(committedWordmark(), "docs/assets/wordmark-light.png is missing")
        let (apx, aw, ah) = try XCTUnwrap(rgba(assetImage))
        let asset = try XCTUnwrap(inkSignature(apx, aw, ah), "committed wordmark has no ink")

        XCTAssertEqual(fresh.count, asset.count)
        let bad = zip(fresh, asset).filter { abs($0.0 - $0.1) > Self.cellTolerance }.count
        XCTAssertLessThanOrEqual(Double(bad) / Double(asset.count), Self.maxBadCellRatio,
            "\(bad)/\(asset.count) cells differ — the committed wordmark is no longer what the engine renders. "
            + "Re-bless via ComparisonGenerator.testGenerateWordmark if the change was intended.")
    }
}
#endif
