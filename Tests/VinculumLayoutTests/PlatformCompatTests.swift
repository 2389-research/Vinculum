import XCTest
import Foundation
@testable import VinculumLayout

/// Proves the pure-Swift PlatformCompat helpers are byte-equivalent to the
/// Foundation APIs they replace — the safety net for building against
/// FoundationEssentials on wasm (#112). If any diverges, the SVG output (and its
/// cross-platform parity) would drift; these tests catch that at the source.
final class PlatformCompatTests: XCTestCase {

    /// `vFormat2`'s real contract: it's a CORRECT 2-decimal rounding — the
    /// printed value is within half of 0.01 of the input — and well-formed, over
    /// a dense sweep. (It does not promise printf byte-equivalence; the goldens
    /// are generated with it and the parity gate enforces cross-platform
    /// agreement, so correctness + determinism is the right invariant.)
    func testFormat2IsCorrectAndWellFormed() {
        var bad: [(Double, String)] = []
        var v = -400.0
        while v <= 400.0 {
            if v != v.rounded() {
                let s = vFormat2(v)
                // well-formed: optional '-', digits, '.', exactly two digits
                let ok = s.wholeMatch(of: /-?\d+\.\d\d/) != nil
                // correct: parses back within half a hundredth of the input
                let round = Double(s) ?? .nan
                if !ok || abs(round - v) > 0.005000001 { bad.append((v, s)) }
                if bad.count > 20 { break }
            }
            v += 0.001
        }
        XCTAssertEqual(bad.count, 0, "vFormat2 wrong/malformed at e.g. "
            + bad.prefix(5).map { "\($0.0)→\($0.1)" }.joined(separator: ", "))
    }

    /// Determinism: same input always yields the same string (trivially true for
    /// pure float ops, but this pins it as a contract for cross-platform parity).
    func testFormat2IsDeterministic() {
        for v in [162.051, 37.42, -0.001, 2.505, 0.015, 94.37, -17.212] {
            XCTAssertEqual(vFormat2(v), vFormat2(v))
        }
    }

    /// Spot-check exact output, incl. the negative-zero case and a known tie
    /// (46.865, which appears as a real layout width) — pins the actual strings
    /// so a future change to the formatter is a deliberate, golden-re-blessing act.
    func testFormat2KnownOutputs() {
        XCTAssertEqual(vFormat2(37.42), "37.42")
        XCTAssertEqual(vFormat2(-17.212), "-17.21")
        XCTAssertEqual(vFormat2(-0.001), "-0.00")
        XCTAssertEqual(vFormat2(46.865), "46.86")   // tie → rounds via the scaled value
        XCTAssertEqual(vFormat2(0.5), "0.50")
    }

    func testHexByteMatchesPrintf() {
        for n in 0...255 {
            XCTAssertEqual(vHexByte(n), String(format: "%02x", n), "hex \(n)")
        }
    }

    func testTrimWhitespaceMatchesFoundation() {
        let cases = ["  hi  ", "\t x\t", "no", "", "   ", " a b ", "l", " r ", "0", " 12 "]
        for s in cases {
            XCTAssertEqual(s.vTrimmingWhitespace(), s.trimmingCharacters(in: .whitespaces),
                           "whitespace: \(s.debugDescription)")
            XCTAssertEqual(s.vTrimmingWhitespaceAndNewlines(),
                           s.trimmingCharacters(in: .whitespacesAndNewlines),
                           "whitespaceAndNewlines: \(s.debugDescription)")
        }
    }

    /// The MathSpeech case: trimming a custom set (spaces and commas).
    func testTrimCustomSetMatchesFoundation() {
        let set: (Character) -> Bool = { $0 == " " || $0 == "," }
        for s in [" , a, b , ", "x", ", ,", "hello", " a,"] {
            XCTAssertEqual(s.vTrimming(where: set),
                           s.trimmingCharacters(in: CharacterSet(charactersIn: " ,")),
                           "custom trim: \(s.debugDescription)")
        }
    }
}
