#if canImport(SwiftUI) && (canImport(AppKit) || canImport(UIKit))
import SwiftUI
import VinculumLayout

/// First-party SwiftUI math view:
///
/// ```swift
/// MathView(#"e^{i\pi} + 1 = 0"#)
///     .mathFont(.termes)
/// ```
///
/// Renders through `MathImageRenderer`'s cache and sizes itself to the
/// equation. Unsupported LaTeX renders nothing (check with
/// `MathParser.isFullySupported` if you need a fallback), keeping the
/// never-half-broken contract.
public struct MathView: View {
    private let latex: String
    private var display: Bool = true
    private var font: MathFont = .latinModern
    private var theme: MathTheme = .light
    private var baseSize: CGFloat = 17

    public init(_ latex: String) {
        self.latex = latex
    }

    public var body: some View {
        if let r = MathImageRenderer.rendered(
            latex: latex, display: display, mathTheme: theme, baseSize: baseSize, font: font) {
            image(for: r)
                // Inline math sits on the TEXT baseline in
                // HStack(alignment: .firstTextBaseline) rows — the image's
                // baseline is `descent` points above its bottom edge.
                .alignmentGuide(.firstTextBaseline) { d in d.height - r.descent }
                .alignmentGuide(.lastTextBaseline) { d in d.height - r.descent }
                .accessibilityLabel(r.spokenDescription)
        }
    }

    @ViewBuilder
    private func image(for r: MathImageRenderer.RenderedMath) -> some View {
        #if canImport(AppKit)
        Image(nsImage: r.image).renderingMode(r.image.isTemplate ? .template : .original)
        #else
        Image(uiImage: r.image)
        #endif
    }

    // MARK: - Modifiers

    /// Inline (text) style instead of display style.
    public func inlineStyle(_ inline: Bool = true) -> MathView {
        var copy = self; copy.display = !inline; return copy
    }
    /// Selects the math font (default `.latinModern`).
    public func mathFont(_ font: MathFont) -> MathView {
        var copy = self; copy.font = font; return copy
    }
    /// Ink color + appearance (default `.light`).
    public func mathTheme(_ theme: MathTheme) -> MathView {
        var copy = self; copy.theme = theme; return copy
    }
    /// The point size of the surrounding text (default 17).
    public func mathSize(_ size: CGFloat) -> MathView {
        var copy = self; copy.baseSize = size; return copy
    }
}
#endif
