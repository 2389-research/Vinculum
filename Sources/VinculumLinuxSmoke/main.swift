#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import VinculumRender

let corpusPath = "/work/Tests/fixtures/parity-corpus.txt"
let outDir = "/work/parity-linux"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
guard let text = try? String(contentsOfFile: corpusPath, encoding: .utf8) else {
    print("no corpus"); exit(1)
}
var ok = 0, fail = 0
for line in text.split(separator: "\n") {
    guard let bar = line.firstIndex(of: "|") else { continue }
    let name = String(line[..<bar])
    let latex = String(line[line.index(after: bar)...])
    if let png = MathSilicaRenderer.renderPNG(latex: latex, baseSize: 30, display: true) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
        ok += 1
    } else {
        print("PARITY-LINUX FAILED \(name)"); fail += 1
    }
}
print("PARITY-LINUX ok=\(ok) fail=\(fail)")
#else
print("Linux backend only")
#endif
