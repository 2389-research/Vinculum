#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
import Foundation
import Cairo
@testable import VinculumRender
import VinculumLayout

/// Linux (Silica/Cairo/FreeType) render regression: renders the shared parity
/// corpus and compares each render against a committed ink-coverage signature.
///
/// Why a signature and not a full-resolution golden PNG: the Apple goldens are
/// produced and diffed in the same environment, but a Linux golden has to
/// survive whatever FreeType/Cairo the CI image happens to ship. A
/// size-normalized, quantized coverage grid absorbs anti-aliasing and
/// point-version differences while still failing loudly on what actually
/// regresses — a blank, garbled, or wrongly-laid-out render, every one of which
/// sails past the existing "is it a valid PNG?" smoke check.
///
/// Re-bless deliberately (in the CI image, see docs/LINUX.md):
///     VINCULUM_UPDATE_LINUX_GOLDENS=1 swift test --traits LinuxRaster
final class MathSilicaGoldenTests: XCTestCase {

    private static let gridW = 32, gridH = 8
    private static let cellTolerance = 1        // per-cell quantized ink drift allowed
    // A cell moving 2+ levels is a real change, not anti-aliasing jitter (which the
    // ±1 tolerance already absorbs), so the budget is tight: a blanked equation
    // trips ~7% of cells, and a partial regression must not hide under the bar.
    private static let maxBadCellRatio = 0.02   // >2% of cells off ⇒ a real regression
    private static let sizeTolerance = 2        // px drift allowed in width/height

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // VinculumRenderTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // repo root
    }

    private func corpus() throws -> [(name: String, latex: String)] {
        let url = repoRoot().appendingPathComponent("Tests/fixtures/parity-corpus.txt")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").compactMap { line in
                guard let bar = line.firstIndex(of: "|") else { return nil }
                return (String(line[..<bar]), String(line[line.index(after: bar)...]))
            }
    }

    /// Size-normalized ink signature: (width, height, one 0–9 ink level per cell
    /// of a gridW×gridH grid). Binning by fraction of the image makes the grid
    /// independent of the render's pixel size.
    private func signature(_ png: Data) throws -> (w: Int, h: Int, cells: [Int]) {
        let surface = try Cairo.Surface.Image(png: png)
        let w = surface.width, h = surface.height, stride = surface.stride
        let bytes = try XCTUnwrap(surface.data, "surface exposed no pixel data")
        var sums = [Int](repeating: 0, count: Self.gridW * Self.gridH)
        var counts = [Int](repeating: 0, count: Self.gridW * Self.gridH)
        for y in 0..<h {
            let gy = min(Self.gridH - 1, y * Self.gridH / max(h, 1))
            for x in 0..<w {
                let gx = min(Self.gridW - 1, x * Self.gridW / max(w, 1))
                // argb32, little-endian byte order B,G,R,A. Ink is darkness in the
                // DARKEST channel, not in red alone: the corpus renders
                // \color{red}{a}, whose pixels are (255,0,0) — a red-channel test
                // reads those glyphs as blank and would never notice them break.
                //
                // Count *covered* pixels rather than averaging darkness: averaging
                // dilutes a thin stroke across a whole cell to near-zero, which
                // collapses the signature's dynamic range — and with it any ability
                // to notice the render changed at all.
                let off = y * stride + x * 4
                let darkest = min(Int(bytes[off]), Int(bytes[off + 1]), Int(bytes[off + 2]))
                let idx = gy * Self.gridW + gx
                if 255 - darkest >= 64 { sums[idx] += 1 }
                counts[idx] += 1
            }
        }
        // level = tenths of the cell that carry ink (0…9)
        let cells = (0..<sums.count).map { i in
            counts[i] == 0 ? 0 : min(9, sums[i] * 10 / counts[i])
        }
        return (w, h, cells)
    }

    func testLinuxRendersMatchGoldenSignatures() throws {
        let goldenURL = repoRoot().appendingPathComponent("Tests/fixtures/linux-golden.txt")
        let update = ProcessInfo.processInfo.environment["VINCULUM_UPDATE_LINUX_GOLDENS"] != nil

        var golden: [String: (w: Int, h: Int, cells: [Int])] = [:]
        if !update {
            let text = try String(contentsOf: goldenURL, encoding: .utf8)
            for line in text.split(separator: "\n") {
                let f = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
                guard f.count == 4, let gw = Int(f[1]), let gh = Int(f[2]) else { continue }
                golden[String(f[0])] = (gw, gh, f[3].map { Int(String($0)) ?? 0 })
            }
        }

        var lines: [String] = []
        for (name, latex) in try corpus() {
            let png = try XCTUnwrap(MathSilicaRenderer.renderPNG(latex: latex, baseSize: 30, display: true),
                                    "\(name): render returned nil")
            let sig = try signature(png)
            // The failure the PNG-header smoke test cannot see.
            XCTAssertTrue(sig.cells.contains { $0 > 0 }, "\(name): render produced no ink at all")

            if update {
                lines.append("\(name)|\(sig.w)|\(sig.h)|\(sig.cells.map(String.init).joined())")
                continue
            }
            guard let want = golden[name] else {
                XCTFail("\(name): no committed golden — regenerate with VINCULUM_UPDATE_LINUX_GOLDENS=1")
                continue
            }
            XCTAssertLessThanOrEqual(abs(sig.w - want.w), Self.sizeTolerance,
                                     "\(name): width drifted \(want.w) → \(sig.w)")
            XCTAssertLessThanOrEqual(abs(sig.h - want.h), Self.sizeTolerance,
                                     "\(name): height drifted \(want.h) → \(sig.h)")
            guard sig.cells.count == want.cells.count else {
                XCTFail("\(name): signature grid size mismatch"); continue
            }
            let bad = zip(sig.cells, want.cells).filter { abs($0.0 - $0.1) > Self.cellTolerance }.count
            let ratio = Double(bad) / Double(want.cells.count)
            XCTAssertLessThanOrEqual(ratio, Self.maxBadCellRatio,
                "\(name): \(bad)/\(want.cells.count) grid cells drifted beyond tolerance — the Linux render changed")
        }

        if update {
            try (lines.joined(separator: "\n") + "\n").write(to: goldenURL, atomically: true, encoding: .utf8)
            print("WROTE \(lines.count) Linux golden signatures → \(goldenURL.path)")
        }
    }
}
#endif
