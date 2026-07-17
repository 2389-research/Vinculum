#if canImport(AppKit) || canImport(UIKit)
import XCTest
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
@testable import VinculumRender
import VinculumLayout

@MainActor
final class VinculumLabelTests: XCTestCase {

    func testLabelRendersAndSizes() {
        let label = VinculumLabel(frame: .zero)
        label.latex = #"x^2 + y^2 = z^2"#
        XCTAssertTrue(label.isRendered)
        XCTAssertGreaterThan(label.intrinsicContentSize.width, 10)
        XCTAssertGreaterThan(label.intrinsicContentSize.height, 5)
    }

    func testInsetsGrowIntrinsicSize() {
        let label = VinculumLabel(frame: .zero)
        label.latex = "x"
        let bare = label.intrinsicContentSize
        label.contentInsets = .init(top: 4, left: 10, bottom: 4, right: 20)
        XCTAssertEqual(label.intrinsicContentSize.width, bare.width + 30, accuracy: 0.001)
        XCTAssertEqual(label.intrinsicContentSize.height, bare.height + 8, accuracy: 0.001)
    }

    func testUnsupportedIsSilentByDefault() {
        let label = VinculumLabel(frame: .zero)
        label.latex = #"\notacommand{x}"#
        XCTAssertFalse(label.isRendered, "unsupported input must not half-render")
        XCTAssertEqual(label.intrinsicContentSize, .zero,
                       "silent by default — the host supplies the fallback")
    }

    func testInlineErrorIsOptIn() {
        let label = VinculumLabel(frame: .zero)
        label.displayErrorInline = true
        label.latex = #"\notacommand{x}"#
        XCTAssertFalse(label.isRendered)
        XCTAssertGreaterThan(label.intrinsicContentSize.width, 0,
                             "opt-in inline error shows the source")
    }

    // MARK: - Accessibility follows the visible outcome (#7)

    /// `isAccessibilityElement` / `accessibilityLabel` across AppKit + UIKit.
    private func a11y(_ label: VinculumLabel) -> (element: Bool, text: String?) {
        #if canImport(AppKit)
        return (label.isAccessibilityElement(), label.accessibilityLabel())
        #else
        return (label.isAccessibilityElement, label.accessibilityLabel)
        #endif
    }

    func testSilentUnsupportedExposesNoAccessibilityElement() {
        // The silent-by-default contract has to hold in the ACCESSIBILITY tree too:
        // the view draws nothing and reports zero size, so VoiceOver must not land
        // on an invisible node and spell out "backslash n o t a command".
        let label = VinculumLabel(frame: .zero)
        label.latex = #"\notacommand{x}"#
        XCTAssertFalse(label.isRendered)
        XCTAssertEqual(label.intrinsicContentSize, .zero)
        let (element, text) = a11y(label)
        XCTAssertFalse(element, "nothing is drawn — nothing may be exposed")
        XCTAssertNil(text, "the raw LaTeX source must not leak to VoiceOver")
    }

    func testInlineErrorCardIsReadableWhenVisible() {
        // The mirror case: when the source card IS shown, reading it is correct.
        let label = VinculumLabel(frame: .zero)
        label.displayErrorInline = true
        label.latex = #"\notacommand{x}"#
        // Reading isRendered flushes the coalesced refresh — the accessibility
        // state is only meaningful once refresh() has actually run.
        XCTAssertFalse(label.isRendered)
        let (element, text) = a11y(label)
        XCTAssertTrue(element, "a visible source card must be reachable")
        XCTAssertEqual(text, #"\notacommand{x}"#)
    }

    func testRenderedMathIsReadAsSpeechNotSource() {
        let label = VinculumLabel(frame: .zero)
        label.latex = #"x^2"#
        XCTAssertTrue(label.isRendered)
        let (element, text) = a11y(label)
        XCTAssertTrue(element)
        XCTAssertNotEqual(text, #"x^2"#, "VoiceOver reads spoken math, not the source")
        XCTAssertEqual(text?.isEmpty, false)
    }

    /// The review flagged template-image drawing as unverified on iOS
    /// (plausible black-on-dark). Rasterize a dark-theme label onto a dark
    /// background and require ink pixels that differ from it — on BOTH
    /// platforms, but this is the test the iOS CI job exists to run.
    func testDarkThemeLabelDrawsVisibleInk() throws {
        let label = VinculumLabel(frame: CGRect(x: 0, y: 0, width: 220, height: 70))
        label.mathTheme = .dark
        label.latex = #"x^2 + y^2 = z^2"#
        XCTAssertTrue(label.isRendered)
        label.layoutNow()

        let size = label.bounds.size
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let background: CGFloat = 0.12
        ctx.setFillColor(CGColor(gray: background, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        #if canImport(AppKit)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        label.displayIgnoringOpacity(label.bounds, in: NSGraphicsContext.current!)
        NSGraphicsContext.current = nil
        #else
        UIGraphicsPushContext(ctx)
        label.layer.render(in: ctx)
        UIGraphicsPopContext()
        #endif
        let image = try XCTUnwrap(ctx.makeImage())
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        var brighterThanBackground = 0
        var i = 0
        while i + 2 < data.count {
            if Int(data[i]) > Int(background * 255) + 60 { brighterThanBackground += 1 }
            i += 4
        }
        XCTAssertGreaterThan(brighterThanBackground, 50,
                             "dark-theme ink must be visible against a dark canvas")
    }

    func testFontSelectionChangesRender() {
        let lm = VinculumLabel(frame: .zero)
        lm.latex = #"\sum_{i=1}^n i"#
        let stix = VinculumLabel(frame: .zero)
        stix.font = .stixTwo
        stix.latex = #"\sum_{i=1}^n i"#
        XCTAssertTrue(lm.isRendered && stix.isRendered)
        XCTAssertNotEqual(lm.intrinsicContentSize, stix.intrinsicContentSize,
                          "different fonts produce different geometry")
    }
}
#endif
