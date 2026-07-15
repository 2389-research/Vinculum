#if canImport(AppKit)
import XCTest
import AppKit
@testable import VinculumRender
import VinculumLayout

/// Renders the shared parity corpus with the macOS (CoreText) backend, for
/// side-by-side comparison against the Linux (Silica) renders. Writes PNGs to
/// $VINCULUM_PARITY_DIR; skipped otherwise.
@MainActor
final class ParityGenerator: XCTestCase {
    func testRenderParityCorpus() throws {
        guard let dir = ProcessInfo.processInfo.environment["VINCULUM_PARITY_DIR"] else {
            throw XCTSkip("set VINCULUM_PARITY_DIR")
        }
        NSApp?.appearance = NSAppearance(named: .aqua)
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let corpusURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/fixtures/parity-corpus.txt")
        let lines = try String(contentsOf: corpusURL, encoding: .utf8)
            .split(separator: "\n").map(String.init)

        for line in lines {
            guard let bar = line.firstIndex(of: "|") else { continue }
            let name = String(line[..<bar])
            let latex = String(line[line.index(after: bar)...])
            guard let r = MathImageRenderer.rendered(latex: latex, display: true,
                                                     mathTheme: .light, baseSize: 30,
                                                     font: .latinModern) else {
                print("PARITY-MAC FAILED \(name)"); continue
            }
            guard let tiff = r.image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: out.appendingPathComponent("\(name).png"))
        }
        print("PARITY-MAC wrote \(lines.count) renders to \(dir)")
    }
}
#endif
