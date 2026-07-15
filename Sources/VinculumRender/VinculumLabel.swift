#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreGraphics
import VinculumLayout

#if canImport(AppKit)
import AppKit
public typealias PlatformView = NSView
public typealias PlatformEdgeInsets = NSEdgeInsets
#else
import UIKit
public typealias PlatformView = UIView
public typealias PlatformEdgeInsets = UIEdgeInsets
#endif

/// The one-line adoption story: a view that renders LaTeX math.
///
/// ```swift
/// let label = VinculumLabel()
/// label.latex = #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#
/// ```
///
/// Rendering goes through `MathImageRenderer`'s cache, so identical
/// equations across many labels share bitmaps. Unsupported LaTeX renders
/// nothing by default (the never-half-broken contract — check `isRendered`
/// or opt into `displayErrorInline` to show the source in red).
public final class VinculumLabel: PlatformView {

    /// The LaTeX source to render.
    public var latex: String = "" { didSet { setNeedsRefresh() } }
    /// Display style (stacked limits, larger fraction parts). Default true —
    /// a standalone label is usually a display equation.
    public var displayMode: Bool = true { didSet { setNeedsRefresh() } }
    /// The math font. Default Latin Modern.
    public var font: MathFont = .latinModern { didSet { setNeedsRefresh() } }
    /// Ink + appearance.
    public var mathTheme: MathTheme = .light { didSet { setNeedsRefresh() } }
    /// Point size of surrounding text. Default 17.
    public var baseSize: CGFloat = 17 { didSet { setNeedsRefresh() } }
    /// Horizontal placement of the equation within the bounds.
    public var textAlignment: Alignment = .left { didSet { relayout() } }
    /// Padding between the rendered equation and the view's bounds.
    public var contentInsets: PlatformEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0) {
        didSet { relayout() }
    }
    /// When true, unsupported LaTeX shows its source in red instead of
    /// rendering nothing. Off by default: a document should degrade to the
    /// host's own fallback, never to a half-render.
    public var displayErrorInline: Bool = false { didSet { setNeedsRefresh() } }

    /// Whether the current `latex` rendered natively. Reading this flushes
    /// any pending (coalesced) refresh, so it is always current.
    public var isRendered: Bool { refreshIfNeeded(); return renderedFlag }
    private var renderedFlag = false

    public enum Alignment { case left, center, right }

    private let imageView = PlatformImageView()
    private let errorLabel = PlatformTextLabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        addSubview(imageView)
        addSubview(errorLabel)
        errorLabel.isHidden = true
    }

    private var imageSize: CGSize = .zero
    private var needsRefresh = false

    /// Coalesces configuration: setting latex + font + theme + size in
    /// sequence renders ONCE on the next runloop turn, not four times
    /// (each into the shared bitmap cache).
    private func setNeedsRefresh() {
        guard !needsRefresh else { return }
        needsRefresh = true
        DispatchQueue.main.async { [weak self] in self?.refreshIfNeeded() }
    }

    private func refreshIfNeeded() {
        guard needsRefresh else { return }
        needsRefresh = false
        refresh()
    }

    private func refresh() {
        let result = MathImageRenderer.rendered(
            latex: latex, display: displayMode, mathTheme: mathTheme,
            baseSize: baseSize, font: font)
        renderedFlag = result != nil
        imageView.setImage(result?.image, ink: mathTheme.ink)
        imageSize = result?.image.size ?? .zero
        // VoiceOver reads the equation itself.
        let speech = result?.spokenDescription ?? latex
        #if canImport(AppKit)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(speech)
        #else
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = speech
        #endif
        errorLabel.isHidden = renderedFlag || !displayErrorInline || latex.isEmpty
        if !errorLabel.isHidden { errorLabel.setErrorText(latex, size: baseSize) }
        relayout()
        invalidateIntrinsicContentSize()
    }

    private func relayout() {
        let insets = contentInsets
        let available = CGRect(x: insets.left, y: insets.top,
                               width: max(0, bounds.width - insets.left - insets.right),
                               height: max(0, bounds.height - insets.top - insets.bottom))
        let size = renderedFlag ? imageSize : errorLabel.naturalSize()
        let x: CGFloat
        switch textAlignment {
        case .left: x = available.minX
        case .center: x = available.minX + (available.width - size.width) / 2
        case .right: x = available.maxX - size.width
        }
        let frame = CGRect(x: x, y: available.minY + (available.height - size.height) / 2,
                           width: size.width, height: size.height)
        imageView.frame = frame
        errorLabel.frame = frame
    }

    public override var intrinsicContentSize: CGSize {
        refreshIfNeeded()
        let size = renderedFlag ? imageSize
            : (displayErrorInline && !latex.isEmpty ? errorLabel.naturalSize() : .zero)
        return CGSize(width: size.width + contentInsets.left + contentInsets.right,
                      height: size.height + contentInsets.top + contentInsets.bottom)
    }

    /// Flushes any pending refresh and lays out immediately (tests, and
    /// hosts that need geometry before the next runloop turn).
    public func layoutNow() {
        refreshIfNeeded()
        relayout()
    }

    #if canImport(AppKit)
    public override func layout() { super.layout(); refreshIfNeeded(); relayout() }
    public override var isFlipped: Bool { true }
    #else
    public override func layoutSubviews() { super.layoutSubviews(); refreshIfNeeded(); relayout() }
    #endif
}

// MARK: - Tiny platform shims

private final class PlatformImageView: PlatformView {
    private var image: PlatformImage?
    private var ink: PlatformColor = .black
    func setImage(_ image: PlatformImage?, ink: PlatformColor) {
        self.image = image
        self.ink = ink
        #if canImport(AppKit)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }
    #if canImport(AppKit)
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        // Raw NSImage.draw ignores isTemplate and draws the real (ink-
        // colored) pixels — correct as-is.
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
    }
    #else
    override func draw(_ rect: CGRect) {
        guard let image else { return }
        // Template-mode images tint from the context on UIKit; drawn raw
        // (outside UIImageView) that tint is effectively black, which
        // vanished on dark canvases (caught by the iOS simulator CI job).
        // Resolve the template against the theme ink explicitly.
        if image.renderingMode == .alwaysTemplate {
            image.withTintColor(ink, renderingMode: .alwaysOriginal).draw(in: bounds)
        } else {
            image.draw(in: bounds)
        }
    }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    #endif
}

private final class PlatformTextLabel: PlatformView {
    private var text: String = ""
    private var fontSize: CGFloat = 17
    func setErrorText(_ text: String, size: CGFloat) {
        self.text = text; self.fontSize = size
        #if canImport(AppKit)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }
    private var attributes: [NSAttributedString.Key: Any] {
        [.font: PlatformFont.monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular),
         .foregroundColor: PlatformColor.systemRed]
    }
    func naturalSize() -> CGSize {
        (text as NSString).size(withAttributes: attributes)
    }
    #if canImport(AppKit)
    override var isFlipped: Bool { true }
    #endif
    override func draw(_ rect: CGRect) {
        (text as NSString).draw(at: .zero, withAttributes: attributes)
    }
}
#endif
