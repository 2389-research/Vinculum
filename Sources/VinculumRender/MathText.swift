#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics
import VinculumLayout

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The document pipeline: one call takes a whole string — prose with
/// embedded `$…$` / `$$…$$` / `\(…\)` / `\[…\]` math — and returns an
/// `NSAttributedString` with the math rendered inline. This is the API for
/// the common real-world case: markdown notes, chat messages, and LLM
/// output are documents with math in them, not isolated LaTeX strings.
///
/// ```swift
/// textView.textStorage?.setAttributedString(
///     MathText.attributedString(from: modelResponse))
/// ```
///
/// Behavior:
/// - Inline math flows on the text baseline at the base font's size;
///   display math gets its own centered paragraph.
/// - `\newcommand`/`\def` definitions anywhere in the document apply to
///   every math segment (document-scoped macros, definitions stripped).
/// - Unsupported math degrades to its VISIBLE source in code style —
///   never dropped, never half-rendered (the standing contract).
/// - Escaped `\$` is a dollar sign, never a delimiter.
public enum MathText {

    /// Renders `source` as styled text with math flowed inline.
    public static func attributedString(
        from source: String,
        baseFont: PlatformFont = defaultBaseFont,
        textColor: PlatformColor = defaultTextColor,
        mathTheme: MathTheme = .light,
        mathFont: MathFont = .latinModern
    ) -> NSAttributedString {
        let macros = MathMacros.collectDefinitions(from: source)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont, .foregroundColor: textColor,
        ]
        let fallbackAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.85,
                                                     weight: .regular),
            .foregroundColor: textColor.withAlphaComponent(0.75),
        ]
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        let out = NSMutableAttributedString()
        for segment in MathScanner.scan(source) {
            switch segment {
            case .text(let text):
                // Un-escape the scanner's preserved `\$`.
                let plain = text.replacingOccurrences(of: "\\$", with: "$")
                out.append(NSAttributedString(string: plain, attributes: textAttributes))

            case .inlineMath(let latex):
                let expanded = MathMacros.expand(latex, with: macros)
                if isBlankAfterMacroStripping(expanded) { continue }
                if let math = MathImageRenderer.attachmentString(
                    latex: expanded, display: false, mathTheme: mathTheme,
                    baseSize: baseFont.pointSize, font: mathFont) {
                    out.append(math)
                } else {
                    out.append(NSAttributedString(string: "$\(latex)$",
                                                  attributes: fallbackAttributes))
                }

            case .displayMath(let latex):
                let expanded = MathMacros.expand(latex, with: macros)
                if isBlankAfterMacroStripping(expanded) { continue }
                if let math = MathImageRenderer.attachmentString(
                    latex: expanded, display: true, mathTheme: mathTheme,
                    baseSize: baseFont.pointSize, font: mathFont) {
                    // Display math sits on its own centered paragraph.
                    if !out.string.isEmpty && !out.string.hasSuffix("\n") {
                        out.append(NSAttributedString(string: "\n", attributes: textAttributes))
                    }
                    let block = NSMutableAttributedString(attributedString: math)
                    block.append(NSAttributedString(string: "\n", attributes: textAttributes))
                    block.addAttribute(.paragraphStyle, value: centered,
                                       range: NSRange(location: 0, length: block.length))
                    out.append(block)
                } else {
                    out.append(NSAttributedString(string: "$$\(latex)$$",
                                                  attributes: fallbackAttributes))
                }
            }
        }
        return out
    }

    /// Whether `source` contains any math delimiters at all — the cheap
    /// pre-check for hosts processing many strings.
    public static func containsMath(_ source: String) -> Bool {
        MathScanner.containsMathDelimiter(source)
    }

    /// A math segment that held only `\newcommand`/`\def` definitions is
    /// empty after expansion strips them — render nothing for it.
    private static func isBlankAfterMacroStripping(_ expanded: String) -> Bool {
        expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The default prose font (system, 15 pt).
    public static var defaultBaseFont: PlatformFont {
        .systemFont(ofSize: 15)
    }

    /// The default prose color (the platform label color).
    public static var defaultTextColor: PlatformColor {
        #if canImport(AppKit)
        return .labelColor
        #else
        return .label
        #endif
    }
}
#endif
