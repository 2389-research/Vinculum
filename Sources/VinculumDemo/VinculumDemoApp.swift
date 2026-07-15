#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
import VinculumRender
import VinculumLayout

/// The Vinculum demo: paste anything with math in it — a markdown note, an
/// LLM response — and watch it render live. Run with:
///
///     swift run VinculumDemo
@main
struct VinculumDemoApp: App {
    init() {
        // An SPM executable has no app bundle, so AppKit defaults it to a
        // background process — no window, no Dock icon. Promote and
        // activate so `swift run VinculumDemo` actually shows the demo.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Vinculum") {
            DemoView()
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}

struct DemoView: View {
    @State private var source = DemoView.sample
    @State private var fontChoice = 0
    @State private var dark = false

    private static let fonts: [(String, MathFont)] = [
        ("Latin Modern", .latinModern), ("Termes", .termes),
        ("Pagella", .pagella), ("STIX Two", .stixTwo),
    ]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Source — prose with $…$, $$…$$, \\(…\\), \\[…\\]")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
            }
            .padding(10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Rendered — MathText.attributedString(from:)")
                    .font(.caption).foregroundStyle(.secondary)
                RichTextView(text: rendered, darkCanvas: dark)
            }
            .padding(10)
        }
        .toolbar {
            Picker("Font", selection: $fontChoice) {
                ForEach(0..<Self.fonts.count, id: \.self) { i in
                    Text(Self.fonts[i].0).tag(i)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Dark", isOn: $dark)
        }
    }

    private var rendered: NSAttributedString {
        MathText.attributedString(
            from: source,
            baseFont: .systemFont(ofSize: 15),
            textColor: dark ? .white : .labelColor,
            mathTheme: dark ? .dark : .light,
            mathFont: Self.fonts[fontChoice].1)
    }

    static let sample = """
    The quadratic formula solves \\(ax^2 + bx + c = 0\\) for any \\(a \\ne 0\\):

    \\[ x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a} \\]

    Euler's identity $e^{i\\pi} + 1 = 0$ ties five constants together, and the
    Basel problem $$\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}$$
    was its first great success.

    Macros work document-wide: $\\newcommand{\\R}{\\mathbb{R}}$ so we can say
    $f : \\R \\to \\R$ anywhere. Prices like \\$5 stay prose, and unsupported
    commands like $\\nosuchthing{x}$ stay visible as source.
    """
}

/// Minimal attributed-string presenter (SwiftUI `Text` drops attachments).
struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString
    let darkCanvas: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.textContainerInset = NSSize(width: 12, height: 12)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        tv.backgroundColor = darkCanvas ? NSColor(white: 0.12, alpha: 1) : .textBackgroundColor
        tv.textStorage?.setAttributedString(text)
    }
}
#else
// The demo is a macOS app; other platforms (Linux CI builds every target)
// get a stub that says so.
@main
struct VinculumDemoStub {
    static func main() { print("VinculumDemo is a macOS app — run it there with: swift run VinculumDemo") }
}
#endif
