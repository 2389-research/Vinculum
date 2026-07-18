import XCTest
import Foundation
@testable import VinculumLayout

/// The `DisplayList` wire format (#78, docs/ANDROID.md). Platform-free — no font,
/// no renderer — so it also runs on Linux CI.
///
/// The committed fixture (`Tests/fixtures/displaylist-wire-v1.bin`) is the
/// cross-language contract: the Kotlin reader will be tested against the exact
/// same bytes and must reconstruct the same canonical list. Here we prove the
/// Swift writer is stable (bytes == fixture) and the reference reader is correct
/// (fixture → canonical), so the two ends can never drift silently.
final class DisplayListWireTests: XCTestCase {

    /// A tiny deterministic list exercising all three op kinds, all five path
    /// segment kinds, both non-default cap/join, and non-trivial colors.
    private func canonical() -> DisplayList {
        DisplayList(width: 10, ascent: 8, descent: 2, ops: [
            .fillRect(CGRect(x: 1, y: 2, width: 6, height: 0.5),
                      color: MathColor(red: 0, green: 0, blue: 0, alpha: 1)),
            .fillPath(subpaths: [
                .move(CGPoint(x: 0, y: 0)),
                .line(CGPoint(x: 1, y: 1)),
                .quad(to: CGPoint(x: 2, y: 0), control: CGPoint(x: 1.5, y: 0.5)),
                .cubic(to: CGPoint(x: 3, y: 0),
                       control1: CGPoint(x: 2.2, y: 0.2), control2: CGPoint(x: 2.8, y: -0.2)),
                .close,
            ], color: MathColor(red: 1, green: 0, blue: 0, alpha: 1)),
            .strokePath(path: [.move(CGPoint(x: 0, y: 0)), .line(CGPoint(x: 5, y: 0))],
                        width: 1.5, cap: .round, join: .bevel,
                        color: MathColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)),
        ])
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/fixtures/displaylist-wire-v1.bin")
    }

    // MARK: - Round-trip

    func testRoundTripPreservesEverything() {
        let list = canonical()
        let round = try? XCTUnwrap(DisplayListWire.deserialize(DisplayListWire.serialize(list)))
        assertEqual(round!, list)
    }

    func testEmptyListRoundTrips() {
        let empty = DisplayList(width: 0, ascent: 0, descent: 0, ops: [])
        let round = DisplayListWire.deserialize(DisplayListWire.serialize(empty))
        assertEqual(try! XCTUnwrap(round), empty)
    }

    // MARK: - The committed cross-language fixture

    func testWriterMatchesCommittedFixture() throws {
        // Regenerate with VINCULUM_UPDATE_WIRE_FIXTURE=1 when the format changes
        // ON PURPOSE (and bump the magic + this file's name).
        let bytes = DisplayListWire.serialize(canonical())
        if ProcessInfo.processInfo.environment["VINCULUM_UPDATE_WIRE_FIXTURE"] != nil {
            try Data(bytes).write(to: fixtureURL)
            throw XCTSkip("wrote fixture")
        }
        let committed = try XCTUnwrap([UInt8](try Data(contentsOf: fixtureURL)),
                                      "missing fixture — regenerate with VINCULUM_UPDATE_WIRE_FIXTURE=1")
        XCTAssertEqual(bytes, committed,
                       "the serialized bytes drifted from the committed fixture — the Kotlin reader "
                       + "is tested against those exact bytes, so this is a wire-compat break")
    }

    func testReaderDecodesCommittedFixture() throws {
        let committed = [UInt8](try Data(contentsOf: fixtureURL))
        let list = try XCTUnwrap(DisplayListWire.deserialize(committed))
        assertEqual(list, canonical())
    }

    func testMagicHeaderIsStable() {
        XCTAssertEqual(Array(DisplayListWire.serialize(canonical()).prefix(4)), Array("VDL1".utf8))
    }

    // MARK: - Malformed input never traps (returns nil)

    func testMalformedBuffersReturnNilNotCrash() {
        XCTAssertNil(DisplayListWire.deserialize([]))
        XCTAssertNil(DisplayListWire.deserialize(Array("XXXX".utf8)), "wrong magic")
        let good = DisplayListWire.serialize(canonical())
        XCTAssertNil(DisplayListWire.deserialize(Array(good.prefix(good.count - 3))), "truncated tail")
        XCTAssertNil(DisplayListWire.deserialize(Array(good.prefix(6))), "truncated header")
        // A wildly overstated opCount must not over-allocate (a forged count
        // once requested a 154 GB reserve and crashed the process — a DoS from
        // the untrusted JNI boundary).
        let header = Array("VDL1".utf8) + [UInt8](repeating: 0, count: 12)  // magic + 3 f32 zeros
        XCTAssertNil(DisplayListWire.deserialize(header + [0xFF, 0xFF, 0xFF, 0x7F]),  // opCount ~2.1B
                     "a forged opCount must not over-allocate")
        // …and the same for a forged per-path segment count.
        let oneFillPath = header
            + [1, 0, 0, 0]              // opCount = 1
            + [0]                       // tag 0 = fillPath
            + [0, 0, 0, 255]            // rgba
            + [0xFF, 0xFF, 0xFF, 0x7F]  // segCount ~2.1B
        XCTAssertNil(DisplayListWire.deserialize(oneFillPath),
                     "a forged segment count must not over-allocate")
    }

    // MARK: - Helpers

    private func assertEqual(_ a: DisplayList, _ b: DisplayList,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.width, b.width, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(a.ascent, b.ascent, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(a.descent, b.descent, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(a.ops.count, b.ops.count, "op count", file: file, line: line)
        for (x, y) in zip(a.ops, b.ops) { assertOpEqual(x, y, file: file, line: line) }
    }

    private func assertOpEqual(_ a: DisplayList.Op, _ b: DisplayList.Op,
                               file: StaticString, line: UInt) {
        switch (a, b) {
        case let (.fillRect(ra, ca), .fillRect(rb, cb)):
            XCTAssertEqual(ra.origin.x, rb.origin.x, accuracy: 1e-3, file: file, line: line)
            XCTAssertEqual(ra.origin.y, rb.origin.y, accuracy: 1e-3, file: file, line: line)
            XCTAssertEqual(ra.size.width, rb.size.width, accuracy: 1e-3, file: file, line: line)
            XCTAssertEqual(ra.size.height, rb.size.height, accuracy: 1e-3, file: file, line: line)
            assertColor(ca, cb, file: file, line: line)
        case let (.fillPath(pa, ca), .fillPath(pb, cb)):
            assertSegs(pa, pb, file: file, line: line); assertColor(ca, cb, file: file, line: line)
        case let (.strokePath(pa, wa, capa, joina, ca), .strokePath(pb, wb, capb, joinb, cb)):
            XCTAssertEqual(wa, wb, accuracy: 1e-3, file: file, line: line)
            XCTAssertEqual(capa, capb, file: file, line: line)
            XCTAssertEqual(joina, joinb, file: file, line: line)
            assertSegs(pa, pb, file: file, line: line); assertColor(ca, cb, file: file, line: line)
        default:
            XCTFail("op kind mismatch", file: file, line: line)
        }
    }

    private func assertSegs(_ a: [PathOp], _ b: [PathOp], file: StaticString, line: UInt) {
        XCTAssertEqual(a.count, b.count, "segment count", file: file, line: line)
        for (x, y) in zip(a, b) {
            switch (x, y) {
            case let (.move(p), .move(q)), let (.line(p), .line(q)): assertPoint(p, q, file: file, line: line)
            case let (.quad(t1, c1), .quad(t2, c2)):
                assertPoint(t1, t2, file: file, line: line); assertPoint(c1, c2, file: file, line: line)
            case let (.cubic(t1, a1, b1), .cubic(t2, a2, b2)):
                assertPoint(t1, t2, file: file, line: line)
                assertPoint(a1, a2, file: file, line: line); assertPoint(b1, b2, file: file, line: line)
            case (.close, .close): break
            default: XCTFail("segment kind mismatch", file: file, line: line)
            }
        }
    }

    private func assertPoint(_ a: CGPoint, _ b: CGPoint, file: StaticString, line: UInt) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-3, file: file, line: line)
    }

    private func assertColor(_ a: MathColor, _ b: MathColor, file: StaticString, line: UInt) {
        // 8-bit quantized on the wire, so within 1/255.
        XCTAssertEqual(a.red, b.red, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(a.green, b.green, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(a.alpha, b.alpha, accuracy: 0.004, file: file, line: line)
    }
}
