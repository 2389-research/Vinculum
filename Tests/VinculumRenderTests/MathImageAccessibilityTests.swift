#if canImport(AppKit) || canImport(UIKit)
import XCTest
import Foundation
@testable import VinculumRender

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The spoken-math stamp on the cached bitmap.
///
/// In the `MathText` document path the image's own accessibility label is the
/// ONLY per-equation carrier — `attachmentString` puts nothing on the attachment
/// or the attributed string, so if the bitmap isn't labelled, VoiceOver reads
/// "image". And because cache entries are immutable by invariant, whatever the
/// FIRST render produced is what every later host gets, forever (#6).
final class MathImageAccessibilityTests: XCTestCase {

    /// The stamp, however each platform spells it.
    private func stampedSpeech(_ image: PlatformImage) -> String? {
        #if canImport(AppKit)
        return image.accessibilityDescription
        #else
        return image.accessibilityLabel
        #endif
    }

    func testFirstRenderOnMainStampsSpeech() {
        let r = MathImageRenderer.rendered(latex: #"a^{stampmain} + 1"#, display: true,
                                           mathTheme: .light, baseSize: 17)
        let rendered = try? XCTUnwrap(r)
        XCTAssertEqual(stampedSpeech(rendered!.image), rendered!.spokenDescription)
    }

    /// The regression itself. `rendered(...)` is nonisolated precisely so hosts
    /// can pre-render off the main thread; doing so must not cost the equation
    /// its VoiceOver text. Distinct LaTeX per test keeps this a COLD cache entry
    /// — the process-wide cache would otherwise let a warm main-thread entry
    /// answer the call and hide the bug.
    func testOffMainFirstRenderStillStampsTheCachedImage() {
        let latex = #"b^{stampoffmain} + 1"#
        let done = expectation(description: "off-main first render")
        var builtOffMain = false
        DispatchQueue.global().async {
            builtOffMain = !Thread.isMainThread
            _ = MathImageRenderer.rendered(latex: latex, display: true,
                                           mathTheme: .light, baseSize: 17)
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
        XCTAssertTrue(builtOffMain, "the first render must genuinely happen off-main")

        // Back on main: this is a cache HIT, returned verbatim with no re-stamp.
        // Whatever the off-main build wrote is all VoiceOver will ever see.
        let r = MathImageRenderer.rendered(latex: latex, display: true,
                                           mathTheme: .light, baseSize: 17)
        let rendered = try? XCTUnwrap(r)
        XCTAssertEqual(stampedSpeech(rendered!.image), rendered!.spokenDescription,
                       "an equation first rendered off-main was cached without its "
                       + "spoken description — VoiceOver reads \"image\" for it forever")
    }

    /// The document path is why the stamp exists at all: the attachment carries
    /// no accessibility of its own, so the bitmap must arrive already labelled.
    func testAttachmentImageCarriesSpeech() throws {
        let latex = #"c^{stampattach} + 1"#
        let attributed = try XCTUnwrap(MathImageRenderer.attachmentString(
            latex: latex, display: false, mathTheme: .light, baseSize: 17))
        let attachment = try XCTUnwrap(
            attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let image = try XCTUnwrap(attachment.image)
        let speech = try XCTUnwrap(MathImageRenderer.rendered(
            latex: latex, display: false, mathTheme: .light, baseSize: 17)).spokenDescription
        XCTAssertEqual(stampedSpeech(image), speech)
    }
}
#endif
