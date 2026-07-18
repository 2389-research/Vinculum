// The Android C ABI (#77), exercised on Linux — including the real @_cdecl entry
// point via pointer marshalling, which is what JNI calls.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
import Foundation
@testable import VinculumRender
@testable import VinculumLayout

final class VinculumWireCTests: XCTestCase {

    // MARK: - The ABI-stable core

    func testSupportedLatexProducesADecodableDisplayList() throws {
        let bytes = try XCTUnwrap(renderDisplayListWire(latex: #"x = \frac{-b}{2a}"#,
                                                        display: true, baseSize: 24),
                                  "supported LaTeX must produce bytes")
        XCTAssertEqual(Array(bytes.prefix(4)), Array("VDL1".utf8), "carries the versioned magic")
        let list = try XCTUnwrap(DisplayListWire.deserialize(bytes), "the bytes must decode")
        XCTAssertFalse(list.ops.isEmpty, "the equation must carry ink")
        XCTAssertTrue(list.width > 0 && list.height > 0)
        // A fraction: the bar must survive the full pipeline as a fillRect.
        XCTAssertTrue(list.ops.contains { if case .fillRect = $0 { return true }; return false })
    }

    func testUnsupportedLatexReturnsNil() {
        // The never-half-broken contract, across the boundary.
        XCTAssertNil(renderDisplayListWire(latex: #"\notacommand{x}"#, display: true, baseSize: 24))
        XCTAssertNil(renderDisplayListWire(latex: "", display: true, baseSize: 24))
    }

    /// The decoded geometry matches the emitter directly — the C path doesn't
    /// distort the scene, it just serializes it.
    func testWireRoundTripEqualsDirectEmit() throws {
        let (_, font) = try XCTUnwrap(MathSilicaRenderer.loadFont(resource: "latinmodern-math"))
        let node = MathParser.parse(#"\sqrt{x^2 + 1}"#)
        let constants = MathSilicaRenderer.mathConstants(for: font) ?? .latinModern
        let engine = MathLayoutEngine(
            services: MathFontServices(measure: MathSilicaRenderer.freeTypeMeasurer(font: font),
                                       constants: constants),
            baseSize: 24 * 1.15)
        let scene = engine.layout(node, display: true)
        let direct = MathDisplayListRenderer.displayList(for: scene, outliner: FreeTypeOutliner.make(font: font))

        let bytes = try XCTUnwrap(renderDisplayListWire(latex: #"\sqrt{x^2 + 1}"#, display: true, baseSize: 24))
        let decoded = try XCTUnwrap(DisplayListWire.deserialize(bytes))

        XCTAssertEqual(decoded.ops.count, direct.ops.count, "the C path must not add or drop ops")
        XCTAssertEqual(decoded.width, direct.width, accuracy: 1e-3)
        XCTAssertEqual(decoded.ascent, direct.ascent, accuracy: 1e-3)
    }

    // MARK: - The actual @_cdecl entry (what JNI calls)

    func testCEntryPointMarshalsAndFrees() throws {
        let latex = #"\frac{a}{b}"#
        let utf8 = Array(latex.utf8)
        var outLen: Int32 = -1
        let ptr: UnsafeMutablePointer<UInt8>? = utf8.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { cptr in
                vinculum_render_displaylist(cptr, Int32(buf.count), 1, 24, &outLen)
            }
        }
        let buffer = try XCTUnwrap(ptr, "the C entry must return a buffer for supported LaTeX")
        defer { vinculum_free(buffer) }
        XCTAssertGreaterThan(outLen, 0, "outLen must be set to the buffer length")
        let bytes = Array(UnsafeBufferPointer(start: buffer, count: Int(outLen)))
        XCTAssertEqual(Array(bytes.prefix(4)), Array("VDL1".utf8))
        XCTAssertNotNil(DisplayListWire.deserialize(bytes), "the marshalled bytes must decode")
    }

    func testCEntryPointReturnsNilAndZeroLenForUnsupported() {
        let latex = #"\notacommand{x}"#
        let utf8 = Array(latex.utf8)
        var outLen: Int32 = -1
        let ptr: UnsafeMutablePointer<UInt8>? = utf8.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { cptr in
                vinculum_render_displaylist(cptr, Int32(buf.count), 1, 24, &outLen)
            }
        }
        XCTAssertNil(ptr, "unsupported LaTeX must return nil across the C boundary")
        XCTAssertEqual(outLen, 0, "outLen must be zeroed on a nil return")
    }

    func testCEntryPointHandlesNullInput() {
        var outLen: Int32 = -1
        XCTAssertNil(vinculum_render_displaylist(nil, 0, 1, 24, &outLen))
        XCTAssertEqual(outLen, 0)
        vinculum_free(nil)   // must be null-safe
    }

    func testABIVersion() {
        XCTAssertEqual(vinculum_abi_version(), 1)
    }
}
#endif
